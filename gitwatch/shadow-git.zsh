#!/usr/bin/env zsh
#
# shadow-git.zsh — run git against a project's shadow repository.
#
# The shadow repository holds the fine-grained local history written by
# `shadow-gitwatch.zsh`. It is a git-dir beside the work tree rather than inside
# it, so plain `git` in the project never sees it and every inspection needs
# both --git-dir and --work-tree. This wraps that:
#
#   shadow-git.zsh <project-path> [--] <git args…>
#
#   shadow-git.zsh ~/Projects/my-acme-project -- log --oneline
#   shadow-git.zsh ~/Projects/my-acme-project -- show --stat HEAD
#   shadow-git.zsh ~/Projects/my-acme-project.worktrees/feature-branch -- status
#
# The project path is a required first argument with no default, so the target is
# always explicit — the same rule `backup-project.zsh` follows. The `--` is
# optional but recommended: without it, a leading `-` in the git arguments is
# ambiguous.
#
# Recovering a file is a normal git operation against the shadow:
#
#   shadow-git.zsh <project> -- log --oneline -- path/to/file
#   shadow-git.zsh <project> -- show <commit>:path/to/file > /tmp/recovered
#
# Note that a plain `checkout` or `restore` writes straight into the live work
# tree. Redirecting `git show` to a scratch file first is the safe habit.

emulate -L zsh
setopt local_options
set -euo pipefail

die() {
  print -u2 -- "shadow-git: $*"
  exit 1
}

usage() {
  print -u2 -- 'usage: shadow-git.zsh <project-path> [--] <git args…>'
}

if (( $# == 0 )); then
  usage
  die 'no project path given'
fi

case $1 in
  -h|--help)
    usage
    exit 0
    ;;
  -*)
    usage
    die "the first argument must be a project path, got: $1"
    ;;
esac

readonly target=$1
shift

# An optional separator, so `-- log --oneline` and `log --oneline` both work.
if (( $# > 0 )) && [[ $1 == '--' ]]; then
  shift
fi

(( $# > 0 )) || die 'no git arguments given'

[[ -d $target ]] || die "not a directory: $target"

# Resolved exactly as shadow-init.zsh resolves it, so this works unchanged for a
# linked worktree: `…/my-acme-project.worktrees/feature-branch` resolves to
# `…/my-acme-project.worktrees/.git-shadow/feature-branch`.
readonly src=${target:A}
readonly shadow=${src:h}/.git-shadow/${src:t}

if [[ ! -d $shadow ]]; then
  die "no shadow repository for $src
  expected: $shadow
  create it with: shadow-init.zsh $src"
fi

exec git --git-dir=$shadow --work-tree=$src "$@"
