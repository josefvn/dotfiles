---
name: slice-into-commits
description: >-
  Interactively slice a dirty working tree into logical conventional commits.
  Use when the user says "review my changes", "commit this", "break this into commits",
  "slice this work", or when another skill needs changes committed as a sequence.
---

# Slice into commits

**INTERACTIVE WORKFLOW SKILL** — loops through commits one at a time, pausing for user input.

USE FOR: reviewing uncommitted changes, building a commit plan, staging per commit, writing conventional commit subjects.

DO NOT USE FOR: committing everything at once, rebasing (use handle-rebase), opening a PR (use open-pr).

## Constraints

No interactive git (`add -p`, `rebase -i`). Use `-m`, `git apply --cached` for partial staging. Temp files in `$(git rev-parse --git-dir)/`.

## Workflow

### 1. Prepare

`git reset`, `git add -N` untracked files only (per [staging-recipes.md](references/staging-recipes.md); never `git add -N .`, which also stages deletions). Read full diff.

### 2. Plan

Order by dependency. Apply [conventional-commits.md](references/conventional-commits.md) and [simplified-english.md](references/simplified-english.md).

### 3. Present plan

PR title heading + numbered list per [commit-card-format.md](references/commit-card-format.md).

**End turn. Wait for user to pick a number or request changes.**

### 4. Commit card

Warn if dependencies uncommitted. Print card per [commit-card-format.md](references/commit-card-format.md). Offer: 1) Commit 2) Change message 3) User commits.

**End turn. Wait for choice.**

### 5. Execute

**1/2:** stage (`git add --` whole, [staging-recipes.md](references/staging-recipes.md) partial), commit `-m`.

**3:** print paths/ranges. Write subject to `$(git rev-parse --git-dir)/SKILL_COMMIT_MSG`, never the working tree. Tell user `git commit -F "$(git rev-parse --git-dir)/SKILL_COMMIT_MSG"`.

**End turn. Wait for return.**

### 6. Re-sync

Re-derive plan from `git log`, `git status`, `git diff`. Drop empty, re-scope partial, offer amend if non-conventional.

Changes remain → regenerate list, **loop to step 4.**

No changes → output PR title. **Done.**
