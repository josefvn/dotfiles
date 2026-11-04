#!/usr/bin/env zsh
#
# backup-project.zsh — dated rsync snapshots of a project directory.
#
# Snapshots land in a `.backups` directory beside the project, named
# `~<name>-YYYYMMDD` and hardlinked against the previous snapshot with
# --link-dest, so a daily history costs about as much disk as a single copy plus
# whatever actually changed.
#
#   Projects/
#     my-project/                         the project
#     my-project.worktrees/               its linked worktrees
#     .backups/
#       ~my-project-20260818/             a snapshot
#         .worktrees/
#           feature-branch/               a worktree, inside that snapshot
#
# The project path is a required argument with no default, so the target is
# always explicit.
#
#   backup-project.zsh [-n] [--keep DAYS] [--no-worktrees] <project-path>
#
#   -n, --dry-run     show what would be copied, prune nothing
#       --keep DAYS   retention window (default 14)
#       --no-worktrees  copy only the project, skip its linked worktrees
#
# Linked worktrees are found with `git worktree list` and copied into
# `.worktrees/` inside the snapshot, so a snapshot is one self-contained dated
# unit and pruning it removes its worktrees with it.
#
# What to skip is the project's own business: a `.backupignore` file at the root
# of a tree, in rsync exclude-from syntax, is applied to that tree. Without one,
# everything is copied. Anything local-but-unrecoverable (.env files, .git,
# local notes) is deliberately backed up.
#
# GNU rsync (`brew install rsync`) is used when present. The openrsync that
# macOS ships as /usr/bin/rsync is the fallback, but it cannot rewrite the
# read-only files inside .git/objects, so with it only the day's first run
# succeeds.

emulate -L zsh
setopt local_options extended_glob null_glob
set -euo pipefail

zmodload zsh/system

readonly excludes_file=.backupignore
readonly default_keep=14

# macOS ships openrsync as /usr/bin/rsync. It writes into the destination file
# in place, so it cannot overwrite the mode-444 files git leaves in
# .git/objects, and every run after the day's first one dies with EACCES. GNU
# rsync writes a temp file and renames it, so prefer that when it is installed.
# launchd hands the agent a minimal PATH, so the candidates are absolute.
typeset rsync_bin=/usr/bin/rsync
typeset candidate
for candidate in /opt/homebrew/bin/rsync /usr/local/bin/rsync; do
  [[ -x $candidate ]] || continue
  [[ $($candidate --version 2>/dev/null | head -1) == openrsync* ]] && continue
  rsync_bin=$candidate
  break
done
readonly rsync_bin

die() {
  print -u2 -- "backup-project: $*"
  exit 1
}

log() {
  print -r -- "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

usage() {
  print -u2 -- 'usage: backup-project.zsh [-n] [--keep DAYS] [--no-worktrees] <project-path>'
}

# Arrange: parse arguments. The project path is required — there is no default.
typeset -i dry_run=0
typeset -i include_worktrees=1
typeset -i keep=$default_keep
typeset target=''

while (( $# > 0 )); do
  case $1 in
    -n|--dry-run)
      dry_run=1
      shift
      ;;
    --keep)
      (( $# >= 2 )) || die '--keep needs a number of days'
      [[ $2 == <-> ]] || die "--keep expects a whole number of days, got: $2"
      keep=$2
      shift 2
      ;;
    --no-worktrees)
      include_worktrees=0
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

# Resolve to an absolute real path so the snapshot always lands beside the
# project itself, whatever the caller's working directory or symlinks.
readonly src=${target:A}
readonly name=${src:t}
readonly parent=${src:h}
readonly today=$(date +%Y%m%d)
readonly backup_root=$parent/.backups
readonly dest=$backup_root/"~"$name-$today

if [[ -d $backup_root ]]; then
  [[ -w $backup_root ]] || die "cannot write snapshots into: $backup_root"
elif (( ! dry_run )); then
  [[ -w $parent ]] || die "cannot create the backup directory: $backup_root"
  mkdir -p $backup_root
fi

# Only one run at a time: the launchd agent fires both on a calendar interval
# and at load, so two runs can otherwise collide.
readonly lockfile=${TMPDIR:-/tmp}/backup-project-$name.lock
: >>| $lockfile
if ! zsystem flock -t 0 -f lock_fd $lockfile 2>/dev/null; then
  log "another backup of $name is already running, nothing to do"
  exit 0
fi

# Existing dated snapshots, oldest first. Globs sort lexically and the names
# are YYYYMMDD, so that is chronological. An undated `~<name>` directory does
# not match, and is therefore never used as a base and never pruned.
typeset -a snapshots
snapshots=( $backup_root/"~"$name-[0-9](#c8)(/) )

# Act: copy. --link-dest points at the newest snapshot that is not today's, so
# unchanged files become hardlinks rather than fresh copies.
typeset link_dest=''
typeset snapshot
for snapshot in $snapshots; do
  [[ $snapshot == $dest ]] && continue
  link_dest=$snapshot
done

# Copy one tree, hardlinking against its counterpart in the previous snapshot.
# Each tree gets its own rsync run so that anchored excludes such as
# `/website/out/` resolve against that tree's own root, which is what a
# `.backupignore` is written against.
#
#   snapshot_tree <source> <destination> <link-dest|''> [extra rsync flags...]
#
# The first three arguments must be quoted at the call site: an unquoted empty
# parameter expands to no word at all in zsh, which would silently shift the
# extra flags into the link-dest position.
snapshot_tree() {
  local tree_src=$1 tree_dest=$2 tree_link=$3
  shift 3

  local -a flags
  flags=( --archive --delete --stats "$@" )

  if [[ -n $tree_link && -d $tree_link ]]; then
    flags+=( --link-dest=$tree_link )
  fi

  # Each tree carries its own exclude list, so a worktree is filtered by the
  # `.backupignore` on its own branch rather than the project's.
  if [[ -f $tree_src/$excludes_file ]]; then
    flags+=( --exclude-from=$tree_src/$excludes_file )
  else
    log "  note: no $excludes_file in $tree_src, copying everything"
  fi

  (( dry_run )) && flags+=( --dry-run )

  # Progress bars are for humans; the launchd log stays readable without them.
  if [[ -t 1 ]]; then
    flags+=( --progress )
  fi

  local -i tree_status=0
  $rsync_bin $flags "$tree_src/" "$tree_dest/" || tree_status=$?

  # 24 is "some source files vanished before they could be transferred", which
  # is routine on a live working tree and not a failure.
  if (( tree_status != 0 && tree_status != 24 )); then
    die "rsync failed with exit code $tree_status while copying $tree_src"
  fi
  (( tree_status == 24 )) && log '  note: some files vanished mid-run (rsync 24), copy is otherwise complete'

  return 0
}

log "backing up $src"
log "  into      $dest"
log "  using     $rsync_bin"
if [[ -n $link_dest ]]; then
  log "  hardlinks against ${link_dest:t}"
else
  log '  no previous snapshot, this one is a full copy'
fi
(( dry_run )) && log '  dry run: nothing will be written or pruned'

# `.worktrees` inside a snapshot is written by this script, never by the
# project, so the main transfer must not see it: --delete would otherwise
# remove it on the second run of any given day. rsync protects excluded paths
# on the receiving side from deletion, which is exactly the behaviour wanted.
snapshot_tree "$src" "$dest" "$link_dest" --exclude=/.worktrees/

log "snapshot written: $dest"

# Linked worktrees are separate checkouts of the same repository, each holding
# its own uncommitted work, so they are snapshotted too. `git worktree list` is
# the source of truth: it finds them wherever they live and, unlike a glob over
# the conventional `<name>.worktrees` directory, ignores stray directories that
# merely sit beside real ones.
typeset -a worktrees
worktrees=()
if (( include_worktrees )) && [[ -e $src/.git ]] && (( $+commands[git] )); then
  typeset wt_line wt_path
  while IFS= read -r wt_line; do
    [[ $wt_line == 'worktree '* ]] || continue
    wt_path=${wt_line#worktree }
    # The main worktree is the project itself, already copied above.
    [[ ${wt_path:A} == $src ]] && continue
    # A registered worktree whose directory is gone is prunable, not copyable.
    [[ -d $wt_path ]] || continue
    worktrees+=( ${wt_path:A} )
  done < <(git -C $src worktree list --porcelain 2>/dev/null)
fi

if (( ${#worktrees} )); then
  log "worktrees: ${#worktrees} linked checkout(s) to copy"

  typeset wt wt_name wt_dest wt_link
  for wt in $worktrees; do
    wt_name=${wt:t}
    wt_dest=$dest/.worktrees/$wt_name
    wt_link=''
    [[ -n $link_dest ]] && wt_link=$link_dest/.worktrees/$wt_name

    log "  worktree  $wt"
    log "    into    $wt_dest"

    (( dry_run )) || mkdir -p ${wt_dest:h}
    snapshot_tree "$wt" "$wt_dest" "$wt_link"
  done

  log "worktrees written into $dest/.worktrees"
elif (( include_worktrees )); then
  log 'no linked worktrees to copy'
fi

# Assert: prune anything past the retention window. Deleting an old snapshot is
# safe — hardlinked data survives as long as any remaining snapshot points at
# it. Only exactly-named, dated directories directly inside $backup_root
# qualify, so nothing outside the backup directory can ever be removed.
if (( dry_run )); then
  log 'dry run: skipping prune'
  exit 0
fi

readonly cutoff=$(date -v-${keep}d +%Y%m%d)
log "pruning snapshots older than $cutoff (keeping $keep days)"

snapshots=( $backup_root/"~"$name-[0-9](#c8)(/) )
for snapshot in $snapshots; do
  [[ $snapshot == $dest ]] && continue
  [[ ${snapshot:h} == $backup_root ]] || continue
  [[ ${snapshot:t} == "~$name-"[0-9](#c8) ]] || continue

  typeset stamp=${${snapshot:t}##*-}
  if [[ $stamp < $cutoff ]]; then
    log "  removing ${snapshot:t}"
    rm -rf -- $snapshot
  fi
done

log 'done'
