# GitHub PR

Commands and patterns for creating and managing pull requests.

---

## PR description template

Use this template unless `.github/pull_request_template.md` exists in the repo (fill that instead):

```markdown
## Summary
One or two sentences on what this change does and why.

## Changes
- One line per logical commit, in commit order.

## Testing
What was verified, or a statement that verification is still needed.

## Notes
Follow-ups, known limits, breaking changes and their impact. Omit this section when empty.
```

---

## Creating a PR

Write the body to a temp file first (avoids shell escaping issues):

```bash
cat > /tmp/skill-pr-body.md << 'EOF'
<generated description>
EOF

git push -u origin <branch>

gh pr create \
  --base <base> \
  --title "<title>" \
  --body-file /tmp/skill-pr-body.md
```

Add `--draft` if the user chooses draft state.

---

## Copilot review

Request a Copilot review at creation time or after:

```bash
# At creation time
gh pr create --base <base> --title "<title>" --body-file /tmp/skill-pr-body.md --reviewer @copilot

# After creation
gh pr edit <pr-url> --add-reviewer @copilot
```

Effort levels (GA since August 2026):
- **Lite** — default, requested via CLI as above
- **Balanced** — cannot be set from CLI; requires repo/org default set to Balanced in GitHub settings

The effort level cannot be set from the CLI or API. If the user wants Balanced, tell them to set it as the repository default under Settings → Code review → Copilot, or select it manually under Reviewers on the PR page.

Copilot always leaves a Comment review (never Approve or Request Changes), so it never blocks a merge.

Offer three options:
1. Lite (requested via CLI)
2. Balanced (mention the repo-default requirement)
3. Skip

---

## Conflict detection

```bash
gh pr view --json mergeable,mergeStateStatus,url
```

- `mergeable` is `UNKNOWN` for a few seconds after creation — query once more before concluding
- `CONFLICTING` or `mergeStateStatus` of `DIRTY` means real conflicts
- `BEHIND` means the branch needs updating (not necessarily conflicting)

If conflicts exist, offer: skill rebases and resolves, or user resolves. Either way, re-push with:

```bash
git push --force-with-lease
```

---

## Watching checks

```bash
gh pr checks --watch
```

Report the final status (pass/fail) and any failed check names.

---

## Viewing review comments

After Copilot or human review:

```bash
gh pr view --json reviews,comments
```

This is informational — report unresolved comments to the user but do not auto-fix them in v1.
