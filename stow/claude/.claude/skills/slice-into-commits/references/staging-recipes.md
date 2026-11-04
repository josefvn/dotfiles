# Staging recipes

Exact command sequences for partial file staging used by the slice-into-commits skill.

---

## Partial staging via patch

When a file has hunks that belong to different commits, stage only the relevant hunks:

```bash
# 1. Generate a full patch for the file
git diff -U3 -- <file> > "$(git rev-parse --git-dir)/skill-hunk.patch"

# 2. Edit the patch to keep only the target hunks
#    Keep the file header (--- and +++ lines) intact.
#    Remove unwanted hunk headers and their content.
#    Adjust hunk counts if needed.

# 3. Dry-run to verify
git apply --cached --check --recount "$(git rev-parse --git-dir)/skill-hunk.patch"

# 4. Apply
git apply --cached --recount "$(git rev-parse --git-dir)/skill-hunk.patch"

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
git ls-files -z --others --exclude-standard | xargs -0 git add -N
```

Without `git add -N`, untracked files do not appear in `git diff` and cannot be partially staged.
