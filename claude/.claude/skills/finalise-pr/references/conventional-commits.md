# Conventional commits

Rules for commit messages produced by the finalise-pr skill.

---

## Format

```
type(scope): subject
```

Or without scope when none is clearly dominant:

```
type: subject
```

One line only. No body, no footers. The detail lives in the PR description.

---

## Types

| Type | Use when |
|------|----------|
| `feat` | A new capability is added |
| `fix` | A bug is corrected |
| `chore` | Maintenance that does not change runtime behaviour |
| `ci` | CI/CD pipeline changes |
| `docs` | Documentation only |
| `style` | Formatting, whitespace, semicolons — no logic change |
| `refactor` | Code restructure that does not add or fix |
| `perf` | A performance improvement |
| `test` | Adding or correcting tests |
| `build` | Build system or dependency changes |
| `revert` | Reverting a previous commit |

---

## Subject rules

- Imperative mood ("add", not "added" or "adds")
- Lower-case start
- No trailing full stop
- Target 50 characters, hard ceiling 72
- Spell out what changed rather than naming it vaguely

---

## Scope derivation

Derive the scope from the project structure at runtime. Priority order:

1. **Top-level meaningful directory** where the change lives (e.g. `api`, `web`, `docs`, `cli`, `infra`, `engine`)
2. If the project has a monorepo structure with named packages, use the package's short name (strip any `@org/` prefix)
3. If changes span multiple directories equally, either split the commit or drop the scope
4. No scope at all when nothing is clearly dominant — a missing scope is better than a misleading one

Keep scopes to a single short lower-case word.

---

## Breaking changes

Use `!` before the colon:

```
feat(api)!: require authentication on all endpoints
```

No `BREAKING CHANGE:` footer (commits stay one-line). Explain the impact in the PR description's Notes section instead.

---

## Examples

**Bad → Good:**

```
Added new feature for users
→ feat(web): add user profile page

Fixed the issue
→ fix(api): return 404 when resource is missing

Updated stuff
→ refactor(cli): extract config parsing into its own module

misc changes and formatting
→ style(web): apply prettier to touched files
```
