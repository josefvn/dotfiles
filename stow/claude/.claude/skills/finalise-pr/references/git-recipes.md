# Git recipes

Exact command sequences used by the finalise-pr skill. Every command is non-interactive.

---

## Rebase onto origin/base via WIP commit

Why a WIP commit rather than `git stash`:
- Conflicts resolve inside a normal rebase; `git rebase --abort` restores the exact prior state
- The work exists as a reachable commit, so the reflog can recover it
- Stash refs are shared across worktrees — a blind `stash pop` is dangerous in multi-worktree setups
- Rebasing one WIP commit means resolving conflicts once against the complete change set
- `git reset --mixed` at the end produces exactly the unstaged state the next step wants

### Sequence

```bash
# 1. Safety backup
GIT_DIR_PATH=$(git rev-parse --git-dir)
git rev-parse HEAD > "$GIT_DIR_PATH/skill-pre-rebase-head"
git diff HEAD > "$GIT_DIR_PATH/skill-backup-$(date +%s).patch"

# 2. Capture the entire dirty tree as a real commit (including untracked)
git add -A
git commit -m "wip: temporary commit created by finalise-pr skill"

# 3. Rebase non-interactively
GIT_EDITOR=true GIT_SEQUENCE_EDITOR=true git rebase origin/<base>

# 4. Unwind the WIP commit, leaving everything unstaged
git reset --mixed HEAD~1
```

### Conflict handling

If step 3 fails with conflicts:

```bash
git status --porcelain
```

Present the conflicted files to the user. Offer two paths:

**Skill resolves:** read the conflict markers, resolve, then:
```bash
git add -- <resolved-files>
GIT_EDITOR=true git rebase --continue
git reset --mixed HEAD~1
```

**User resolves (handover):** state plainly:
1. Resolve conflicts in the listed files
2. Run `git add -- <files>` then `git rebase --continue`
3. Run `git reset --mixed HEAD~1` to unwind the WIP commit
4. Or `git rebase --abort` to return to the pre-rebase state

End the turn. On return, verify:
```bash
git status
git log -1 --format=%s
```
Confirm no "wip: temporary commit" exists as HEAD and no rebase is in progress.

### Abort and recovery

If anything goes wrong mid-rebase:
```bash
git rebase --abort
```

If the WIP commit was already created but rebase was aborted:
```bash
git reset --mixed HEAD~1
```

If everything is lost, recover from the backup:
```bash
GIT_DIR_PATH=$(git rev-parse --git-dir)
git reset --hard $(cat "$GIT_DIR_PATH/skill-pre-rebase-head")
git apply "$GIT_DIR_PATH/skill-backup-*.patch"
```

### Cleanup

Delete backup files only after the final push succeeds:
```bash
GIT_DIR_PATH=$(git rev-parse --git-dir)
rm -f "$GIT_DIR_PATH"/skill-pre-rebase-head "$GIT_DIR_PATH"/skill-backup-*.patch
```

---

## Partial staging via patch

When a file has hunks that belong to different commits, stage only the relevant hunks:

```bash
# 1. Generate a full patch for the file
git diff -U3 -- <file> > /tmp/skill-hunk.patch

# 2. Edit the patch to keep only the target hunks
#    Keep the file header (--- and +++ lines) intact.
#    Remove unwanted hunk headers and their content.
#    Adjust hunk counts if needed.

# 3. Dry-run to verify
git apply --cached --check --recount /tmp/skill-hunk.patch

# 4. Apply
git apply --cached --recount /tmp/skill-hunk.patch

# 5. Verify what was staged
git diff --cached -- <file>
```

### Failure handling

If `git apply --cached --check` fails:
- Do NOT retry blindly
- Fall back to handing the file to the user with the exact line ranges listed
- Continue staging the other files in the commit

---

## Unstaging and making untracked files diffable

```bash
# Unstage everything
git reset

# Make untracked files visible in git diff (without staging content)
git add -N $(git ls-files --others --exclude-standard)
```

Without `git add -N`, untracked files do not appear in `git diff` and cannot be partially staged.

---

## Force push after rebase

Always use `--force-with-lease`:

```bash
git push --force-with-lease
```

Never use bare `--force`.

If `--force-with-lease` is rejected, someone else moved the remote branch. Stop and report to the user rather than escalating.
