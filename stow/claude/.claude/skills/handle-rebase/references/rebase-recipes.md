# Rebase recipes

Exact command sequences for the handle-rebase skill. Every command is non-interactive.

---

## Why a WIP commit (not git stash)

- Conflicts resolve inside a normal rebase; `git rebase --abort` restores the exact prior state
- The work exists as a reachable commit, so the reflog can recover it
- Stash refs are shared across worktrees — a blind `stash pop` is dangerous in multi-worktree setups
- Rebasing one WIP commit means resolving conflicts once against the complete change set
- `git reset --mixed` at the end produces exactly the unstaged state the next step wants

---

## Full rebase sequence

```bash
# 1. Record the starting point
GIT_DIR_PATH=$(git rev-parse --git-dir)
git rev-parse HEAD > "$GIT_DIR_PATH/skill-pre-rebase-head"

# 2. Dirty tree only: capture everything, untracked included, as a WIP commit.
#    Its SHA is the backup. On a clean tree skip this step and step 4.
git add -A && git commit -q -m "wip: temporary commit created by handle-rebase skill" && git rev-parse HEAD > "$GIT_DIR_PATH/skill-wip-commit"

# 3. Rebase non-interactively
GIT_EDITOR=true GIT_SEQUENCE_EDITOR=true git rebase origin/<base>

# 4. Unwind the WIP commit, but only if the rebase has finished and HEAD is the WIP commit
[ ! -d "$(git rev-parse --git-path rebase-merge)" ] && [ "$(git log -1 --format=%s)" = "wip: temporary commit created by handle-rebase skill" ] && git reset -q --mixed HEAD~1
```

Decide step 2 with `git status --porcelain`: empty output means clean. Never run step 4 on a clean tree; with no WIP commit, `HEAD~1` is a real commit.

---

## Conflict resolution

If step 3 stops with conflicts:

```bash
git status --porcelain
```

Resolve, then continue:

```bash
git add -- <resolved-files> && GIT_EDITOR=true git rebase --continue
```

`--continue` can stop again on a later commit. Repeat resolve and continue until no rebase is in progress (`git rev-parse --git-path rebase-merge` does not exist). Only then run step 4.

---

## Abort and recovery

If anything goes wrong mid-rebase:

```bash
git rebase --abort
```

`--abort` puts HEAD back on the WIP commit, if there was one. Unwind it with step 4.

If everything is lost, restore the starting point and the WIP commit's files:

```bash
GIT_DIR_PATH=$(git rev-parse --git-dir) && git reset -q --hard "$(cat "$GIT_DIR_PATH/skill-pre-rebase-head")" && git checkout "$(cat "$GIT_DIR_PATH/skill-wip-commit")" -- . && git reset -q
```

This brings back new files too, because they were committed in the WIP commit. If the backup files are gone, find the WIP commit with `git reflog | grep 'handle-rebase skill'`.

---

## Cleanup

Delete the backup files once the rebase is verified (skill step 4), not later:

```bash
GIT_DIR_PATH=$(git rev-parse --git-dir) && rm -f "$GIT_DIR_PATH/skill-pre-rebase-head" "$GIT_DIR_PATH/skill-wip-commit"
```

Each run overwrites both files, so a stale backup never points at the wrong rebase. The reflog keeps the WIP commit for 90 days.
