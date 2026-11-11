---
name: finalise-pr
description: >-
  Slice uncommitted work into logical conventional commits and open a GitHub PR.
  Use when the user says "prep a PR", "finalise this branch", "ship this", or has
  a dirty worktree to turn into a PR.
  Orchestrates handle-rebase, slice-into-commits, and open-pr.
---

# Finalise PR

**INTERACTIVE ORCHESTRATOR SKILL**

USE FOR: full branch-to-PR workflow (rebase, slice commits, open PR).

DO NOT USE FOR: just rebasing (use /handle-rebase), just committing (use /slice-into-commits), just opening a PR (use /open-pr), reviewing someone else's PR.

## Constraints

Ask questions with `AskUserQuestion` (clickable options). If it is unavailable, list the options as text and end the turn.

## Workflow

### 1. Preflight

Resolve base branch (`gh repo view --json defaultBranchRef`). Verify: git repo, not detached, not on base, has changes, no in-progress operation. Stop with message if any guard fails.

### 2. Behind-base check

Fetch, count divergence (`git rev-list --left-right --count HEAD...origin/<base>`). If not behind, go straight to step 4.

If behind, report and ask with `AskUserQuestion`:
1. Rebase now → invoke `/handle-rebase`
2. User rebases manually
3. Defer, rebase after slicing, before the PR

### 3. Rebase phase (if chosen)

Invoke `/handle-rebase`, telling it the user already confirmed, so it skips its own prompt. On completion, continue.

### 4. Commit slicing phase

Invoke `/slice-into-commits`. It handles analysis, plan presentation, commit loop with user approval, re-sync. On completion (no changes remain), continue.

### 4a. Deferred rebase (if option 3)

Invoke `/handle-rebase` the same way as step 3. The tree is clean now, so it makes no WIP commit. On completion, continue.

### 5. PR phase

Invoke `/open-pr`. It handles description, approval, push, PR creation, Copilot review, checks. On completion, report PR URL. **Done.**
