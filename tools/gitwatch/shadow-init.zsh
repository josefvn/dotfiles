#!/usr/bin/env zsh
#
# shadow-init.zsh — create the shadow git repository for a project.
#
# A shadow repository is a git directory that lives *beside* a work tree rather
# than inside it, and records a commit for every change as it happens. The work
# tree's real `.git` is never touched: its history, branches, index and hooks are
# entirely separate.
#
#   Projects/
#     my-acme-project/                 work tree — untouched
#     .git-shadow/
#       my-acme-project/               shadow git-dir for the primary checkout
#     my-acme-project.worktrees/
#       feature-branch/                a linked worktree
#       .git-shadow/
#         feature-branch/              shadow git-dir for that worktree
#
# The shadow git-dir is placed the same way `backup-project.zsh` places
# `.backups`: `${parent}/.git-shadow/${name}`. Beside, not inside, so there is no
# `.gitignore` entry to add, no `git status` noise in the real repository, no
# file-watcher feedback loop, and the history survives deletion of the work tree.
#
# The project path is a required argument with no default, so the target is
# always explicit. The same rule applies to a linked worktree, which is just
# another project path as far as this script is concerned.
#
#   shadow-init.zsh [-q] <project-path>
#
#   -q, --quiet   only report when something was actually created or changed
#
# Idempotent: re-running adjusts configuration and leaves existing history alone.
# `shadow-gitwatch.zsh` calls it before spawning a watcher on any checkout.

emulate -L zsh
setopt local_options extended_glob
set -euo pipefail

# The identity for auto-commits. There is no global git identity on this
# machine — the real one is local to each project's own .git/config — and a
# separate git-dir inherits none of that, so the shadow needs its own or every
# commit fails with "please tell me who you are".
readonly shadow_user_name='gitwatch (local history)'
readonly shadow_user_email='gitwatch@localhost'

die() {
  print -u2 -- "shadow-init: $*"
  exit 1
}

log() {
  print -r -- "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

usage() {
  print -u2 -- 'usage: shadow-init.zsh [-q] <project-path>'
}

# Arrange: parse arguments. The project path is required — there is no default.
typeset -i quiet=0
typeset target=''

while (( $# > 0 )); do
  case $1 in
    -q|--quiet)
      quiet=1
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

# Resolve to an absolute real path so the shadow always lands beside the work
# tree itself, whatever the caller's working directory or symlinks.
readonly src=${target:A}
readonly name=${src:t}
readonly parent=${src:h}
readonly shadow_root=$parent/.git-shadow
readonly shadow=$shadow_root/$name

[[ -w $parent || -d $shadow_root ]] || die "cannot create the shadow directory: $shadow_root"

# Act: create the repository if it is not there yet. `git init` with an explicit
# --git-dir and --work-tree produces exactly the split layout wanted: a
# non-bare repository whose administrative files live outside the tree it tracks.
typeset -i created=0
if [[ ! -d $shadow ]]; then
  mkdir -p $shadow
  git --git-dir=$shadow --work-tree=$src init --quiet
  created=1
fi

[[ -d $shadow ]] || die "shadow git-dir was not created: $shadow"

# Assert: the configuration every auto-commit depends on. Written on every run,
# not just at creation, so an existing shadow picks up changes here.
#
# core.worktree lets `git --git-dir=<shadow> …` work without also passing
# --work-tree, which makes the repository usable by hand. gitwatch passes both
# anyway, so this is for humans.
git --git-dir=$shadow config core.bare false
git --git-dir=$shadow config core.worktree $src
git --git-dir=$shadow config user.name $shadow_user_name
git --git-dir=$shadow config user.email $shadow_user_email

# Signing is fatal for an unattended committer: it prompts, or fails, and either
# way the commit is lost. Nothing enables it today, so this is insurance against
# a future global `commit.gpgsign = true`.
git --git-dir=$shadow config commit.gpgsign false
git --git-dir=$shadow config tag.gpgsign false

# core.hooksPath is deliberately never set. The real repository points it at
# `.husky/_`, but that setting lives in the real .git/config, which this git-dir
# does not read — so husky and commitlint never see an auto-commit. The shadow's
# own hooks directory is empty and stays that way.
if git --git-dir=$shadow config --get core.hooksPath > /dev/null 2>&1; then
  die "core.hooksPath is set in $shadow; auto-commits must not run hooks"
fi

# What to exclude is the work tree's own business, and git already knows: a
# .gitignore is a file in the work tree, so it is read no matter which git-dir
# is in use. The shadow therefore tracks exactly the set of files the real
# repository would track, with no exclude list of its own to maintain or drift.
if (( created )); then
  log "shadow repository created for $src"
  log "  git-dir   $shadow"
elif (( ! quiet )); then
  log "shadow repository ready for $src"
  log "  git-dir   $shadow"
fi
