---
name: open-pr
description: >-
  Write a PR description, push the branch, create a GitHub pull request, and optionally
  request a Copilot review. Use when the user says "open a PR", "create a PR", "push and
  open a PR", "submit this for review", or when another skill needs a PR created.
---

# Open PR

**INTERACTIVE WORKFLOW SKILL**

USE FOR: writing a PR description, pushing a branch, creating a GitHub PR, Copilot review, watching checks.

DO NOT USE FOR: committing (use slice-into-commits), rebasing (use handle-rebase), reviewing someone else's PR, merging.

## Constraints

`gh` CLI available and authenticated. Temp files in `$(git rev-parse --git-dir)/`. Force pushes always use `--force-with-lease --force-if-includes`, never bare `--force`.

## Workflow

### 1. Gather context

Read commit log since merge-base. Resolve base branch. Derive PR title from commits.

### 2. Write description

Check for `.github/pull_request_template.md`. If present, fill it. Otherwise use template from [github-pr.md](references/github-pr.md): Summary, Changes (one line per commit), Testing, Notes.

### 3. Present for approval

Show PR title as heading + full description body. Ask to fine-tune or approve.

**End the turn. Wait for user to approve or request changes.**

### 4. Push

`git push -u origin <branch>`. If rejected because the branch was rebased, use `git push --force-with-lease --force-if-includes`. A plain `--force-with-lease` trusts the remote-tracking ref, which the rebase's fetch already moved; `--force-if-includes` also refuses when the remote has commits the local branch never contained. If that is rejected too, someone else pushed: stop and report.

### 5. Ask about PR state

Offer: ready for review (default) / draft.

**End the turn. Wait for user's choice.**

### 6. Create PR

Write body to `$(git rev-parse --git-dir)/skill-pr-body.md`. Run `gh pr create`. Report PR URL.

### 7. Copilot review

Offer: Lite (`--add-reviewer @copilot`) / Balanced (needs repo default) / Skip.

**End the turn. Wait for user's choice.**

### 8. Post-creation

Check `gh pr view --json mergeable,mergeStateStatus`. If conflicts: offer `/handle-rebase` (then push as in step 4) or handover. Optionally watch checks.

Report PR URL and status. **Done.**
