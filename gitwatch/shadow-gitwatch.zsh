#!/usr/bin/env zsh
#
# shadow-gitwatch.zsh — fine-grained local history for a project and all of its
# linked worktrees, in shadow git repositories.
#
# The daily rsync snapshots written by `backup-project.zsh` give one recovery
# point per day. This fills the gap between them: a commit within seconds of any
# change, whoever made it — an editor, an agent, a `task` run. Editor timelines
# only record editor-made saves, so they cannot do this.
#
# One long-running supervisor covers a whole project. It polls
# `git worktree list` and keeps exactly one `gitwatch` process alive per
# checkout, so worktrees created and removed during normal work are picked up
# and cleaned up without touching launchd.
#
#   Projects/
#     my-acme-project/                 the primary checkout
#     .git-shadow/
#       my-acme-project/               its shadow git-dir, holding gitwatch.pid
#     my-acme-project.worktrees/
#       feature-branch/                a linked worktree
#       .git-shadow/
#         feature-branch/              its shadow git-dir
#
# The project path is a required argument with no default, so the target is
# always explicit.
#
#   shadow-gitwatch.zsh [--interval SECS] [--debounce SECS] [--once] <project-path>
#
#     --interval SECS   worktree poll interval (default 30)
#     --debounce SECS   quiet period before a commit (default 5)
#     --once            start the watchers, report, and exit without supervising
#
# What gets committed is the work tree's own business: a `.gitignore` is a file
# in the work tree, so git reads it whichever git-dir is in use. The shadow
# therefore records exactly the set of files the real repository would track, and
# there is no second exclude list here to maintain or let drift.
#
# What gets *watched* is a separate question, and needs the project's
# `.backupignore` — see watch_exclude_regex below.

emulate -L zsh
setopt local_options extended_glob null_glob
set -euo pipefail

zmodload zsh/system

readonly excludes_file=.backupignore
readonly default_interval=30
readonly default_debounce=5

# launchd hands an agent a minimal PATH — `launchctl getenv PATH` is empty — so
# Homebrew is invisible unless it is put back. gitwatch itself needs `fswatch`
# and coreutils' `greadlink` on PATH at run time, not just at spawn time, so
# this is exported rather than only used to locate the binary. The plist sets it
# too; this makes the script work when run by hand from a bare environment.
if [[ -d /opt/homebrew/bin ]]; then
  export PATH=/opt/homebrew/bin:$PATH
fi
if [[ -d /opt/homebrew/opt/coreutils/libexec/gnubin ]]; then
  export PATH=/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH
fi

die() {
  print -u2 -- "shadow-gitwatch: $*"
  exit 1
}

log() {
  print -r -- "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# For anything reported from inside a command substitution, where stdout is the
# caller's return value and a log line written to it would be captured as data
# rather than printed. launchd sends both streams to the same directory.
warn() {
  print -ru2 -- "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

usage() {
  print -u2 -- 'usage: shadow-gitwatch.zsh [--interval SECS] [--debounce SECS] [--once] <project-path>'
}

# Arrange: parse arguments. The project path is required — there is no default.
typeset -i poll_interval=$default_interval
typeset -i debounce=$default_debounce
typeset -i run_once=0
typeset target=''

while (( $# > 0 )); do
  case $1 in
    --interval)
      (( $# >= 2 )) || die '--interval needs a number of seconds'
      [[ $2 == <1-> ]] || die "--interval expects a whole number of seconds, got: $2"
      poll_interval=$2
      shift 2
      ;;
    --debounce)
      (( $# >= 2 )) || die '--debounce needs a number of seconds'
      [[ $2 == <1-> ]] || die "--debounce expects a whole number of seconds, got: $2"
      debounce=$2
      shift 2
      ;;
    --once)
      run_once=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      usage
      die "unknown option: $1"
      ;;
    *)
      [[ -z $target ]] || die "expected one project path, also got: $1"
      target=$1
      shift
      ;;
  esac
done

if [[ -z $target ]]; then
  usage
  die 'no project path given'
fi

[[ -d $target ]] || die "not a directory: $target"

readonly src=${target:A}
readonly name=${src:t}

# The scripts are siblings of this one, so the set travels together wherever the
# repository is cloned and nothing has to be hardcoded.
readonly here=${${(%):-%x}:A:h}
readonly init_script=$here/shadow-init.zsh
[[ -x $init_script ]] || die "not executable: $init_script"

# launchd resolves ProgramArguments against no PATH worth the name, so the
# candidates are absolute, with a PATH lookup as the last resort for anyone who
# installed gitwatch elsewhere.
typeset gitwatch_bin=''
typeset candidate
for candidate in /opt/homebrew/bin/gitwatch /usr/local/bin/gitwatch; do
  [[ -x $candidate ]] || continue
  gitwatch_bin=$candidate
  break
done
if [[ -z $gitwatch_bin ]]; then
  gitwatch_bin=${commands[gitwatch]:-}
fi
[[ -n $gitwatch_bin ]] || die 'gitwatch not found; install it with: brew install gitwatch'
readonly gitwatch_bin

(( $+commands[git] )) || die 'git not found'
(( $+commands[fswatch] )) || die 'fswatch not found; install it with: brew install fswatch'

# Only one supervisor per project: launchd restarts the agent on any exit, and a
# second one would double every watcher. The key includes a checksum of the full
# path, because two projects can share a final path component and a lock keyed on
# the name alone would leave the second one permanently unwatched.
readonly lockfile=${TMPDIR:-/tmp}/shadow-gitwatch-$name-$(print -rn -- $src | cksum | cut -d' ' -f1).lock
: >>| $lockfile
if ! zsystem flock -t 0 -f lock_fd $lockfile 2>/dev/null; then
  die "another supervisor for $src is already running"
fi

###############################################################################
# Paths
###############################################################################

# The shadow git-dir sits beside the work tree, exactly where `backup-project.zsh`
# puts `.backups`. Resolving it from the path alone means a linked worktree needs
# no special case: `…/my-acme-project.worktrees/feature-branch` becomes
# `…/my-acme-project.worktrees/.git-shadow/feature-branch`.
shadow_dir_for() {
  local checkout=${1:A}
  print -r -- "${checkout:h}/.git-shadow/${checkout:t}"
}

pid_file_for() {
  print -r -- "$(shadow_dir_for $1)/gitwatch.pid"
}

###############################################################################
# Watch exclusions
###############################################################################

# gitwatch spawns a fresh timer subprocess for every filesystem event it is
# handed, killing the previous one. Commit-level filtering does not help with
# that: a `pnpm install` writing a hundred thousand files under `node_modules/`
# is a hundred thousand spawn/kill cycles before a single commit is considered.
# fswatch has to drop those events instead, which is what gitwatch's -x does.
#
# The pattern comes from the project's own `.backupignore` — the same file
# `backup-project.zsh` reads, listing exactly the regenerable, high-churn output
# that should not be watched either. One list per project, two consumers, no
# defaults hidden in this repository.
#
# `.backupignore` is in rsync exclude-from syntax and fswatch wants a POSIX
# extended regular expression over absolute paths, so the patterns are
# translated. The supported subset is the one that appears in practice:
#
#   node_modules/            a name, at any depth
#   /website/out/            a leading slash, anchored to the project root
#   *.tsbuildinfo            the * ? and ** wildcards
#
# rsync's character classes are not translated; a pattern using one is passed
# through with its brackets escaped, which fails safe by matching nothing.

# Escape every extended-regex metacharacter in a literal string.
escape_ere() {
  print -r -- "${1//(#m)[^A-Za-z0-9_\/,:=@%~-]/\\$MATCH}"
}

# Translate an rsync wildcard pattern into an extended regex fragment: `**`
# crosses directory boundaries, `*` and `?` do not, everything else is literal.
glob_to_ere() {
  local pattern=$1 out='' char
  local -i i=1 len=${#pattern}

  while (( i <= len )); do
    char=${pattern[i]}
    case $char in
      '*')
        if [[ ${pattern[i+1]} == '*' ]]; then
          out+='.*'
          (( i += 2 ))
          continue
        fi
        out+='[^/]*'
        ;;
      '?')
        out+='[^/]'
        ;;
      [A-Za-z0-9_/,:=@%~-])
        out+=$char
        ;;
      *)
        out+='\'$char
        ;;
    esac
    (( ++i ))
  done

  print -r -- $out
}

# Which `.backupignore` applies to a checkout. A worktree on a branch that
# predates the file — or that deleted it — still shares the project's build
# tooling and so its churn, and an unfiltered watcher there is the expensive
# case this whole mechanism exists to avoid. So the primary checkout's list is
# the fallback. Patterns are re-anchored against the checkout being watched, so
# an anchored entry like `/website/out/` still resolves to that worktree's own
# root.
exclude_file_for() {
  local checkout=${1:A}

  if [[ -f $checkout/$excludes_file ]]; then
    print -r -- $checkout/$excludes_file
  elif [[ -f $src/$excludes_file ]]; then
    print -r -- $src/$excludes_file
  fi
}

# Build the whole -x pattern for one checkout from a given exclude list, or an
# empty string if there is nothing usable in it.
watch_exclude_regex() {
  local checkout=${1:A}
  local file=$2

  [[ -f $file ]] || return 0

  local -a alternatives
  local line pattern prefix
  local -i dir_only

  while IFS= read -r line || [[ -n $line ]]; do
    # Comments and blank lines, as rsync reads them.
    pattern=${line%%[[:space:]]#}
    pattern=${${pattern##[[:space:]]#}%%[[:space:]]#}
    [[ -z $pattern || $pattern == '#'* ]] && continue

    # gitwatch splices the pattern into a single-quoted string that is later
    # word-split and eval'd, so whitespace or a quote in it would not survive the
    # trip. Nothing realistic hits this; say so rather than watch it misbehave.
    # The note goes to stderr: this function's stdout is the regex itself.
    if [[ $pattern == *[[:space:]\'\"\$\`]* ]]; then
      warn "  note: skipping unsupported $excludes_file pattern: $pattern"
      continue
    fi

    # A trailing slash means "directories only" in rsync. For a watcher matching
    # on paths the distinction is moot, since the suffix below already covers the
    # entry and everything beneath it.
    dir_only=0
    if [[ $pattern == */ ]]; then
      dir_only=1
      pattern=${pattern%/}
    fi
    [[ -z $pattern ]] && continue

    # rsync anchors a pattern to the transfer root only when it starts with a
    # slash; anything else floats, matching at a component boundary at any depth.
    if [[ $pattern == /* ]]; then
      prefix="^$(escape_ere $checkout)/"
      pattern=${pattern#/}
    else
      prefix='/'
    fi

    alternatives+=( "${prefix}$(glob_to_ere $pattern)(/|\$)" )
  done < $file

  (( ${#alternatives} )) || return 0

  print -r -- ${(j:|:)alternatives}
}

###############################################################################
# Children
###############################################################################

# path → pid of the gitwatch process watching it.
typeset -A watchers
watchers=()

# gitwatch is `fswatch | while read …`, so killing it alone leaves fswatch and
# the reader orphaned but very much alive: fswatch only notices the broken pipe
# on its next write, which may never come on a quiet tree. Nor can the process
# group be signalled — a background job in a non-interactive shell shares the
# supervisor's group, so that would take the supervisor down with it. Walking
# the tree and killing depth-first is what is left.
kill_tree() {
  local pid=$1 child
  local -a children

  children=( ${(f)"$(pgrep -P $pid 2> /dev/null || true)"} )
  for child in $children; do
    [[ -n $child ]] && kill_tree $child
  done

  kill $pid 2> /dev/null || true
}

# True if the pid is alive and really is one of our gitwatch children. Pids are
# recycled, so a stale PID file from a previous boot can easily name something
# unrelated — including this supervisor, whose own command line contains the
# word "gitwatch" twice. The match is therefore on the invocation this script
# actually makes, `gitwatch -g <git-dir> …`, and never on this process.
#
# Given a shadow git-dir, the match is narrowed to a watcher serving that exact
# directory. Shadow roots are shared between projects that sit side by side, so
# "is a gitwatch" is not enough to conclude "is mine".
is_live_watcher() {
  local pid=${1:-} shadow=${2:-}
  [[ $pid == <1-> ]] || return 1
  [[ $pid != $$ ]] || return 1
  kill -0 $pid 2> /dev/null || return 1

  local cmd
  cmd=$(ps -o command= -p $pid 2> /dev/null) || return 1

  if [[ -n $shadow ]]; then
    [[ $cmd == *"gitwatch -g $shadow "* ]]
  else
    [[ $cmd == *gitwatch\ -g\ * ]]
  fi
}

# Kill anything still watching a checkout that kill_tree cannot reach.
#
# A gitwatch that dies without taking its pipeline with it — a crash, or someone
# killing it by hand — leaves fswatch reparented to init. The parent link is
# then gone, so walking the tree finds nothing and the watcher survives its own
# supervisor. Matching on the command line is the only handle left.
#
# Both patterns are written so they cannot match this supervisor, whose own
# command line ends with the project path and contains the word gitwatch twice:
# it is neither invoked as `bin/gitwatch -g …` nor named fswatch. $$ is skipped
# anyway, belt and braces.
sweep_strays() {
  local checkout=$1
  local shadow=$(shadow_dir_for $checkout)

  local -a stray
  stray=( ${(f)"$(pgrep -f "bin/gitwatch -g $(escape_ere $shadow) " 2> /dev/null || true)"} )
  stray+=( ${(f)"$(pgrep -f "^fswatch .* $(escape_ere $checkout)\$" 2> /dev/null || true)"} )

  local pid
  for pid in $stray; do
    [[ -n $pid && $pid != $$ ]] || continue
    kill_tree $pid
  done
}

start_watcher() {
  local checkout=$1
  local label=${checkout:t}
  local shadow=$(shadow_dir_for $checkout)

  # Idempotent, and the reason the agent can point straight at this script: a
  # brand-new worktree gets its shadow repository created on first sight, and
  # gitwatch refuses to start against a git-dir that does not exist yet.
  if ! $init_script --quiet $checkout; then
    log "  warning: could not initialise the shadow repository for $label, skipping"
    return 1
  fi

  local regex='' ignore_file
  ignore_file=$(exclude_file_for $checkout)

  if [[ -n $ignore_file ]]; then
    regex=$(watch_exclude_regex $checkout $ignore_file)
    if [[ $ignore_file != $checkout/$excludes_file ]]; then
      log "  note: $label has no $excludes_file, using the one from ${${ignore_file:h}:t}"
    fi
  else
    log "  note: no $excludes_file for $label, every file change wakes the watcher"
  fi

  local -a args
  args=( -g $shadow -s $debounce -f )
  if [[ -n $regex ]]; then
    args+=( -x $regex )
  fi
  args+=( $checkout )

  # -f commits whatever is pending before watching, so every (re)start leaves a
  # fresh baseline and nothing written while the supervisor was down is lost.
  $gitwatch_bin $args &
  local pid=$!

  watchers[$checkout]=$pid
  print -r -- $pid > $shadow/gitwatch.pid

  log "  watching $label (pid $pid, debounce ${debounce}s)"
  return 0
}

stop_watcher() {
  local checkout=$1 reason=${2:-gone}
  local pid=${watchers[$checkout]:-}
  local label=${checkout:t}
  local shadow=$(shadow_dir_for $checkout)

  # Only if it is still the watcher we started. Our child may already be gone and
  # its pid recycled onto something entirely unrelated, which kill_tree would
  # otherwise take down along with its children.
  if [[ -n $pid ]] && is_live_watcher $pid $shadow; then
    kill_tree $pid
  fi
  if [[ -n $pid ]]; then
    wait $pid 2> /dev/null || true
  fi
  unset "watchers[$checkout]"

  # Whatever the tree walk could not reach, because its parent was already gone.
  sweep_strays $checkout

  rm -f -- "$(pid_file_for $checkout)"

  # The shadow git-dir is deliberately left in place. Deleting history is a
  # human decision, and a removed worktree is exactly the case where the trail
  # is most likely to be wanted.
  log "  stopped watching $label ($reason)"
}

###############################################################################
# Worktrees
###############################################################################

# Every checkout to watch, primary first. `git worktree list` is the source of
# truth rather than a glob over the conventional `<name>.worktrees` directory:
# git knows where its worktrees actually are and ignores stray directories
# sitting beside real ones. A project that is not a git repository at all is
# still watched, as itself.
list_checkouts() {
  local -a found
  # Not `path`: zsh ties that name to PATH, and assigning a work-tree path to it
  # would quietly replace the command search path for the rest of the process.
  local line checkout_path

  if ! git -C $src rev-parse --git-dir > /dev/null 2>&1; then
    print -r -- $src
    return 0
  fi

  while IFS= read -r line; do
    [[ $line == 'worktree '* ]] || continue
    checkout_path=${line#worktree }
    # A registered worktree whose directory is gone is prunable, not watchable.
    [[ -d $checkout_path ]] || continue
    found+=( ${checkout_path:A} )
  done < <(git -C $src worktree list --porcelain 2>/dev/null)

  (( ${#found} )) || found=( $src )
  print -rl -- $found
}

###############################################################################
# Lifecycle
###############################################################################

typeset -i shutting_down=0
typeset sleep_pid=''

shutdown() {
  (( shutting_down )) && return
  shutting_down=1

  # Cleanup must finish even if something in it fails. errexit here would abort
  # part-way through, and the shutting_down guard means no later handler would
  # pick up where this one left off — every watcher would survive its supervisor.
  setopt local_options no_err_exit
  trap - ZERR

  [[ -n $sleep_pid ]] && kill $sleep_pid 2> /dev/null

  log "stopping ${#watchers} watcher(s)"
  local checkout
  for checkout in ${(k)watchers}; do
    stop_watcher $checkout 'supervisor shutting down'
  done
  log 'done'
}

trap 'shutdown; exit 0' TERM INT HUP
trap 'shutdown' EXIT

# zsh does not run the EXIT trap when errexit kills the shell from inside a
# function, and every part of this script that matters runs inside one. Without
# this, an unexpected non-zero status anywhere would leave a full set of
# gitwatch and fswatch processes behind with nothing left to reap them. ZERR
# fires on exactly the statuses errexit acts on, so it is the missing half.
trap 'shutdown; exit 1' ZERR

# A watcher recorded by a previous supervisor of *this* project is an orphan: the
# lock above proves no other supervisor of it is running, and nothing else would
# adopt it. Killing them and starting clean is both simpler and better defined
# than trying to adopt processes whose arguments may no longer match the current
# configuration — gitwatch's -f re-commits anything pending on the way back up,
# so nothing is lost by the restart.
#
# Only this project's own shadow git-dirs are touched. A shadow root is shared by
# everything sitting in the same parent directory, so two projects side by side
# have their primary shadows in one `.git-shadow`, and the lock is keyed per
# project — meaning a sibling's supervisor is legitimately running at the same
# time. Sweeping the root as a whole would kill its watchers.
reconcile_orphans() {
  local -a checkouts
  local checkout shadow pid_file pid

  checkouts=( ${(f)"$(list_checkouts)"} )

  local -i killed=0
  for checkout in $checkouts; do
    shadow=$(shadow_dir_for $checkout)
    pid_file=$shadow/gitwatch.pid
    [[ -f $pid_file ]] || continue

    pid=$(<$pid_file) || continue
    if is_live_watcher $pid $shadow; then
      kill_tree $pid
      (( ++killed ))
    fi
    rm -f -- $pid_file
  done

  # A watcher whose supervisor was killed outright never wrote its exit, and one
  # whose gitwatch died leaves an fswatch with no parent to walk down from. Both
  # are found by their command line instead, matched on this project's own shadow
  # git-dirs and checkout paths.
  for checkout in $checkouts; do
    sweep_strays $checkout
  done

  (( killed )) && log "cleared $killed orphaned watcher(s) from a previous run"
  return 0
}

# One pass: start what should be running, stop what should not.
sync_watchers() {
  local -a wanted
  wanted=( ${(f)"$(list_checkouts)"} )

  local checkout pid

  # Anything that vanished, or died on its own — a crashed gitwatch is simply
  # started again on the next pass, which gives each watcher KeepAlive
  # semantics without a launchd job of its own.
  for checkout in ${(k)watchers}; do
    pid=${watchers[$checkout]}
    if (( ! ${wanted[(Ie)$checkout]} )); then
      stop_watcher $checkout 'worktree removed'
    elif ! is_live_watcher $pid "$(shadow_dir_for $checkout)"; then
      stop_watcher $checkout 'watcher exited'
    fi
  done

  for checkout in $wanted; do
    [[ -n ${watchers[$checkout]:-} ]] && continue
    start_watcher $checkout || true
  done
}

###############################################################################

log "supervising $src"
log "  gitwatch  $gitwatch_bin"
log "  poll      every ${poll_interval}s"

reconcile_orphans
sync_watchers

if (( run_once )); then
  # The watchers stay up, reparented away from this shell, which is the point:
  # --once is for starting or verifying a set of watchers by hand without
  # holding a terminal. Nothing supervises them afterwards, so a worktree added
  # later is not picked up, and the next supervised run clears them as orphans.
  # Stop one by hand with: kill $(cat <shadow-git-dir>/gitwatch.pid)
  trap - EXIT TERM INT HUP
  log "started ${#watchers} watcher(s); --once given, so nothing is supervising them"
  exit 0
fi

while (( ! shutting_down )); do
  # A plain `sleep` would block the signal handler until it returned, and launchd
  # only waits so long after SIGTERM before resorting to SIGKILL — which would
  # leave every fswatch behind. Waiting on a background sleep is interruptible.
  sleep $poll_interval &
  sleep_pid=$!
  wait $sleep_pid 2> /dev/null || true
  sleep_pid=''

  (( shutting_down )) && break

  sync_watchers
done
