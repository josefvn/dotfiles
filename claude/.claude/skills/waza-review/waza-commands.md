# Waza command reference (review-relevant subset)

Compiled against the waza docs at https://microsoft.github.io/waza/reference/cli/.
Flags move between releases, so when something does not behave as described here,
check `waza <command> --help` before assuming the file is at fault.

## Contents

- [Availability and auth](#availability-and-auth)
- [waza check](#waza-check)
- [waza tokens](#waza-tokens)
- [waza quality](#waza-quality)
- [waza suggest](#waza-suggest)
- [waza coverage](#waza-coverage)
- [waza spec verify](#waza-spec-verify)
- [Commands to avoid during a review](#commands-to-avoid-during-a-review)
- [Exit codes and global flags](#exit-codes-and-global-flags)
- [Environment variables](#environment-variables)

## Availability and auth

```bash
command -v waza >/dev/null 2>&1 && waza --version
waza models            # probes Copilot auth; add --json for scripting
```

Deterministic and offline: `check`, `tokens count`, `tokens profile`, `tokens compare`,
`coverage`, `spec verify` (without `--semantic`), `migrate`, `replay`, `gate`, `compare`.

Requires Copilot auth: `quality`, `suggest`, `tokens suggest`, `dev`, `new task from-prompt`,
`run` with the `copilot-sdk` executor, and `spec verify --semantic`.

Waza checks for a newer version in the background on every command and prints a one-line
notice after the output. Suppress it with `--no-update-check` or `WAZA_NO_UPDATE_CHECK=1`
when parsing output.

## waza check

Validates skill compliance and readiness.

```bash
waza check <skill-name | skill-path>
waza check ./skills/code-explainer --verbose
waza check --verbose --format json
```

| Flag | Description |
|---|---|
| `--verbose` | Detailed compliance report |
| `--format` | `text` (default) or `json` |

With no argument it checks every skill in the workspace, which is rarely what a
single-file review wants. Always pass the path explicitly.

Text output covers four blocks: compliance score, token budget, whether an eval
suite was found, and advisory checks.

```
Skill: code-explainer
Compliance Score: High
Token Budget: 420 / 500 tokens
Evaluation Suite: Found
Advisory Checks
   scope-reduction: Capability scope: 3 signal(s) detected
```

The `scope-reduction` advisory counts three signals and takes the maximum:
comma-separated phrases after `USE FOR:`, level-two (`## `) headings in the body,
and numbered procedures starting at `1.`. Below the threshold (default 2) it warns
about possible scope loss from token-limit compression. Advisory only; it does not
block readiness.

The JSON shape is not documented and has changed across releases. Prefer text output
for reporting to a human, and if JSON is needed, parse defensively rather than
assuming field names.

## waza tokens

```bash
waza tokens count skills/my-skill/SKILL.md     # count tokens in a file or tree
waza tokens count skills/
waza tokens check my-skill                     # count against the configured budget
waza tokens profile my-skill                   # structural analysis
waza tokens suggest my-skill                   # LLM optimisation suggestions
waza tokens compare main --skills --threshold 10
```

`tokens count` and `tokens profile` accept any markdown path, which is what makes
them usable on a CLAUDE.md without staging a shim.

`tokens profile` flags: `--format text|json`, `--tokenizer bpe|estimate`. It reports
token count, section count, code block count, and workflow step detection:

```
my-skill: 1,722 tokens (detailed), 8 sections, 4 code blocks
   warning: no workflow steps detected
```

It warns on: no workflow steps detected, more than 2,500 tokens, fewer than 3 sections.

Token limits resolve in priority order: `.waza.yaml` `tokens.limits`, then
`.token-limits.json` (deprecated), then built-in defaults. Configure per-file limits as:

```yaml
tokens:
  limits:
    defaults:
      "*.md": 2000
      "skills/**/SKILL.md": 5000
    overrides:
      "skills/complex-skill/SKILL.md": 7500
```

Because the ceiling is project-dependent, report the limit waza actually used rather
than quoting a number from memory.

## waza quality

LLM-as-judge scoring across five dimensions: clarity, completeness, trigger precision,
scope coverage, anti-patterns. Each scores 1 to 5, with an overall out of 5.0 and
per-dimension feedback.

```bash
waza quality skills/code-explainer
waza quality skills/code-explainer --format json
waza quality skills/code-explainer --model gpt-4o
```

| Flag | Default | Description |
|---|---|---|
| `--model` | project default | Judge model |
| `--format` | `table` | `table` or `json` |
| `--rubric` | | Custom rubric path (reserved for future use) |

Unauthenticated it fails with `Error: not authenticated - run "copilot login" first`.
Scores vary between runs because a model produces them; treat a single run as a signal,
not a measurement, and do not compare a score across two different judge models.

## waza suggest

Generates suggested eval artifacts from a SKILL.md using an LLM. Defaults to `--dry-run`,
which prints to stdout and writes nothing.

```bash
waza suggest skills/code-explainer --dry-run
waza suggest skills/code-explainer --focus negative-triggers --count 5 --dry-run
waza suggest skills/code-explainer --apply
```

| Flag | Description |
|---|---|
| `--model` | Judge model |
| `--dry-run` | Print suggestions to stdout (default) |
| `--apply` | Write suggested files to disk |
| `--force` | Allow `--apply` to overwrite existing files |
| `--count <n>` | Generate exactly N tasks (default: 3 diverse plus 1 negative) |
| `--focus <category>` | `triggers`, `negative-triggers`, `edge-fixtures`, `do-not-use-for`, `parameters` |
| `--output-dir` | Default `<skill-path>/evals` |
| `--format` | `yaml` (default) or `json` |

Each suggested task carries a `confidence` in [0, 1] and a `rationale` citing the
SKILL.md span it came from. Both appear in dry-run and JSON output but are not written
into the task YAML. `--apply` is merge-safe: it preserves an existing `eval.yaml`,
refuses to overwrite existing task files by path or by `id`, and prints a diff instead.

Never run `--apply --force` on a user's repository without asking.

## waza coverage

Eval coverage grid for discovered skills and `.agent.md` custom agents.

```bash
waza coverage
waza coverage --format markdown
waza coverage --path custom-evals --path agents
```

Levels: **Full** (an `eval.yaml`/`eval.yml` with tasks and at least 2 distinct grader
types), **Partial** (an eval file but fewer than 2 grader types or no tasks),
**Missing** (no eval file). The headline percentage counts only fully covered items.

Repo-scoped rather than file-scoped, so it belongs in a review only when the user asks
about eval coverage across a project.

## waza spec verify

Checks that an `eval.yaml` covers the executable contract in a `SKILL.md`. Parses the
description, `USE FOR` triggers, `DO NOT USE FOR` triggers and parameter blocks into
requirement IDs with source spans, then reports which task IDs exercise each one.

```bash
waza spec verify skills/pr-summarizer evals/pr-summarizer/eval.yaml
waza spec verify --skill skills/pr-summarizer --eval evals/pr-summarizer/eval.yaml --format json
```

| Flag | Description |
|---|---|
| `--format` | `human` (default), `json`, `github-actions` |
| `--warn` | Report uncovered requirements and exit 0 (default) |
| `--fail` | Exit 1 when uncovered requirements reach `--threshold` |
| `--threshold` | Uncovered count threshold for `--fail` (default 1) |
| `--semantic` | LLM-assisted matching after deterministic matching |
| `--judge-model` | Judge model for `--semantic` |

Requires an existing eval suite, so it is unavailable for a standalone file review.

## Commands to avoid during a review

- `waza run` executes a real evaluation against a model and consumes premium requests.
  Reviewing a file and benchmarking a skill are different jobs; only run it on request.
- `waza dev --auto` rewrites the user's SKILL.md in place, iterating until it hits a
  compliance target. Never invoke it as part of a review.
- `waza suggest --apply --force`, `waza run --update-snapshots`, and `waza init` all
  write to the working tree.

## Exit codes and global flags

| Code | Meaning |
|---|---|
| `0` | Success |
| `1` | One or more tasks or checks failed |
| `2` | Configuration or runtime error |

`waza gate` and `waza adversarial` use their own richer code sets; see the CLI docs.

Global flags: `--help`, `--version`, `--verbose`, `--no-update-check`.

## Environment variables

| Variable | Description |
|---|---|
| `GITHUB_TOKEN` | Token for Copilot SDK execution |
| `COPILOT_CLI_PATH` | Explicit path to a Copilot CLI binary; unset means the bundled CLI |
| `COPILOT_BASE_URL` | Custom provider endpoint; set means the default auth check is skipped |
| `COPILOT_API_KEY` | API key for a custom provider |
| `WAZA_HOME` | Config directory (default `~/.waza`) |
| `WAZA_CACHE` | Cache directory (default `.waza-cache`) |
| `WAZA_NO_UPDATE_CHECK` | Set to `1` to disable the version check |

A custom provider via `COPILOT_BASE_URL` bypasses the standard auth check, so
`waza models` can fail while `waza quality` still works. If the user has a custom
provider configured, trust the actual command rather than the probe.
