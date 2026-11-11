---
name: handle-rebase
description: >-
  Rebase the current branch onto origin's default branch with safety backups and
  conflict handling. Use when the user says "rebase this branch", "catch up to main",
  "rebase onto base", "update this branch", or when another skill needs a rebase performed.
---

# Handle rebase

**INTERACTIVE WORKFLOW SKILL**

USE FOR: rebasing a feature branch onto the default branch, catching up to upstream.

DO NOT USE FOR: rebasing onto an arbitrary branch, squashing, interactive rebase, resolving conflicts in an existing PR.

## Constraints

No interactive git. Use `GIT_EDITOR=true GIT_SEQUENCE_EDITOR=true`. Work against `origin/<base>`. Temp files in `$(git rev-parse --git-dir)/`.

Ask questions with `AskUserQuestion` (clickable options). If it is unavailable, list the options as text and end the turn.

## Workflow

### 1. Resolve base and assess divergence

Resolve base branch. Fetch. Count with `git rev-list --left-right --count HEAD...origin/<base>`.

If not behind: report "already up to date". **Done.**

If behind: intersect file sets to report overlap risk. Ask with `AskUserQuestion`: Proceed / Abort.

Skip this confirmation when another skill invoked this one after the user already chose to rebase.

### 2. Execute rebase

> See [rebase-recipes.md](references/rebase-recipes.md) for full command sequences and recovery.

Record HEAD → if the tree is dirty, WIP commit (`git add -A`) → non-interactive rebase → if a WIP commit was made, `git reset --mixed HEAD~1`.

Never run the reset on a clean tree, or before the rebase has finished. Check that HEAD is the WIP commit first.

### 3. Handle outcome

**Success:** report branch is up to date. **Done.**

**Conflicts:** present conflicted files. Ask with `AskUserQuestion`:
- A: Skill resolves (read markers, resolve, continue; repeat until the rebase finishes, then unwind)
- B: User resolves manually

If B, tell user plainly:
1. Resolve files, `git add`, `git rebase --continue`
2. Repeat step 1 each time the rebase stops again
3. Or `git rebase --abort` to undo
4. Tell me when the rebase has finished; I unwind the WIP commit

**End the turn as plain text, not `AskUserQuestion`. Wait for user to return.**

### 4. Verify and unwind

Confirm no rebase is in progress. If a WIP commit was made and HEAD is it, `git reset --mixed HEAD~1`. Then check `git log -1 --format=%s` is not the WIP subject.

### 5. Cleanup

Delete the backup files per [rebase-recipes.md](references/rebase-recipes.md). This skill never pushes; pushing belongs to open-pr. **Done.**
