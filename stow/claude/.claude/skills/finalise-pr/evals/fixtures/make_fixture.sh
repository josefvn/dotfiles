#!/usr/bin/env bash
set -euo pipefail

# Creates a test fixture for the finalise-pr skill.
# Usage:
#   ./make_fixture.sh [--conflict]
#
# Produces a temporary directory containing:
#   - A bare repo (origin) with a main branch
#   - A worktree on a feature branch with a dirty working tree
#
# The dirty tree contains:
#   - A new untracked file (src/api/auth.ts)
#   - A file with hunks belonging to two different logical commits (src/api/client.ts)
#   - A formatting-only change mixed with a real change (src/web/app.ts)
#   - A new file in a second directory (src/web/auth-status.ts)
#   - Test additions (tests/client.test.ts)
#
# With --conflict: adds commits to origin/main that conflict with the dirty tree.

CONFLICT=false
if [[ "${1:-}" == "--conflict" ]]; then
  CONFLICT=true
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE="$SCRIPT_DIR/sample-project"

TMPDIR=$(mktemp -d)
BARE="$TMPDIR/origin.git"
WORK="$TMPDIR/worktree"

echo "Creating fixture in: $TMPDIR"

# --- Create bare origin ---
git init --bare "$BARE" >/dev/null 2>&1

# --- Create initial working copy to set up main ---
SETUP="$TMPDIR/setup"
git clone "$BARE" "$SETUP" >/dev/null 2>&1
cd "$SETUP"

git config user.email "fixture@test.local"
git config user.name "Fixture"

# Copy base project files
cp -R "$SAMPLE/base/." .

git add -A
git commit -m "feat: initial project structure" >/dev/null

git push origin main >/dev/null 2>&1

# --- Optionally add conflicting commits to main ---
if [[ "$CONFLICT" == true ]]; then
  sed -i.bak 's/async get(path: string)/async get(path: string, options?: RequestInit)/' src/api/client.ts
  rm -f src/api/client.ts.bak
  git add src/api/client.ts
  git commit -m "feat(api): add options param to get method" >/dev/null
  git push origin main >/dev/null 2>&1
fi

# --- Create a feature branch worktree ---
git checkout -b feature/add-auth >/dev/null 2>&1
git push -u origin feature/add-auth >/dev/null 2>&1

# Set up the worktree
cd "$TMPDIR"
git clone "$BARE" "$WORK" >/dev/null 2>&1
cd "$WORK"
git config user.email "fixture@test.local"
git config user.name "Fixture"
git checkout feature/add-auth >/dev/null 2>&1

# --- Apply dirty working tree ---
cp "$SAMPLE/dirty/src/api/auth.ts" src/api/auth.ts
cp "$SAMPLE/dirty/src/api/client.ts" src/api/client.ts
cp "$SAMPLE/dirty/src/web/app.ts" src/web/app.ts
cp "$SAMPLE/dirty/src/web/auth-status.ts" src/web/auth-status.ts
cp "$SAMPLE/dirty/tests/client.test.ts" tests/client.test.ts

echo ""
echo "Fixture ready:"
echo "  Origin: $BARE"
echo "  Worktree: $WORK"
echo ""
echo "The dirty tree contains:"
echo "  - src/api/auth.ts          (new untracked file)"
echo "  - src/api/client.ts        (hunks for two commits: auth logic + logging)"
echo "  - src/web/app.ts           (real change + formatting)"
echo "  - src/web/auth-status.ts   (new untracked file, web scope)"
echo "  - tests/client.test.ts     (test additions)"
echo ""
if [[ "$CONFLICT" == true ]]; then
  echo "  Warning: origin/main has a conflicting commit in src/api/client.ts"
fi
echo ""
echo "To test: cd $WORK && invoke /finalise-pr"
