---
name: finalise-pr
description: >-
  Slice uncommitted work into logical conventional commits and open a GitHub PR.
  Use when the user says "review my changes", "commit this", "prep a PR",
  "finalise this branch", "ship this", or has a dirty worktree to turn into a PR.
---

# Finalise PR

**INTERACTIVE WORKFLOW SKILL**

USE FOR: slicing dirty worktree into commits, conventional commit messages, GitHub PR, rebasing, Copilot review.

DO NOT USE FOR: reviewing someone else's PR, merged-code review, user wants one commit, non-git VCS.

## Constraints

No interactive git (`add -p`, `rebase -i`, editors). Use `-m`, `GIT_EDITOR=true`. Work against `origin/<base>`. Temp files in `$(git rev-parse --git-dir)/`.

## Workflow

1. **Preflight** — resolve base (`gh repo view --json defaultBranchRef`). Stop if: not git, detached, on base, no changes, in-progress op.

2. **Behind-base** — fetch, count divergence, report overlap. Offer: rebase / user rebases / defer.

3. **Rebase** — per [git-recipes.md](references/git-recipes.md): WIP commit → rebase → reset. Handle conflicts or hand over.

4. **Analyse** — unstage, `git add -N` untracked, read diff. Plan commits by dependency. Use [conventional-commits.md](references/conventional-commits.md) and [simplified-english.md](references/simplified-english.md).

5. **Present plan** — PR title heading + numbered list. Wait for pick.

6. **Commit card** — files, hunks, "Not in this commit" (mandatory if splitting), "Why", "Needs first".

7. **Commit** — offer: commit / change message / user commits. Partial files: patch-apply per [git-recipes.md](references/git-recipes.md). User-commits: write subject to `SKILL_COMMIT_MSG`, end turn.

8. **Re-sync** — re-derive plan from git state. Loop to step 6.

9. **PR** — description per [github-pr.md](references/github-pr.md), push, create PR, Copilot review, watch checks.
