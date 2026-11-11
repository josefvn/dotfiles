---
name: waza-review
description: Analyse a SKILL.md, .agent.md or CLAUDE.md file with the Microsoft waza CLI (compliance, token budget, structure, LLM-as-judge quality) and turn the raw output into a report followed by prioritised recommendations, then stop and ask before anything is changed. Use this whenever the user asks to review, audit, lint, grade, check, score or "run waza on" an agent instruction file, whether they upload it, give a path, or paste its contents into the chat. Also use it when the user asks why a skill is not triggering, whether a skill is too long or over budget, or whether a CLAUDE.md is well written, since waza measures those things directly instead of guessing. The review is read-only and never edits the reviewed file.
---

# Waza skill review

USE FOR: reviewing a SKILL.md, auditing a CLAUDE.md, checking skill compliance, checking token budget, diagnosing skill trigger problems, scoring skill content quality, preparing a skill for submission or PR.

DO NOT USE FOR: authoring a brand new skill from nothing, running a full behavioural eval suite against a model (`waza run`), or reviewing ordinary source code that is not agent instructions.

## Read-only contract

This skill measures and advises. It does not edit the reviewed file, write elsewhere in the user's repo, or run a waza command that touches the working tree.

Deliver in this order, and no further:

1. **Report** — what waza measured (step 5). Numbers and observations, no fixes.
2. **Recommendations** — what to change and why (step 6), as proposals.
3. **Stop and ask** — hand the decision to the user (step 7).

Applying a recommendation needs an explicit instruction given after the review (a step 7 answer or a later message); "review this file" is not consent to edit it. If the opening request bundles a fix ("review and tidy it up"), run the review to completion first, then ask which recommendations to apply.

Ask questions with `AskUserQuestion` (clickable options). If it is unavailable, list the options as text and end the turn.

## Step 1: Assert waza is available

```bash
command -v waza >/dev/null 2>&1 && waza --version
```

If missing, stop and tell the user. Ask with `AskUserQuestion`: Install now / Stop. The install command:

```bash
curl -fsSL https://raw.githubusercontent.com/microsoft/waza/main/install.sh | bash
```

In VS Code the `ms-vscode.vscode-chat-customizations-evaluations` extension ships a download command. Do not substitute your own reading for a waza run — the user asked for a measurement.

## Step 2: Check LLM-backed commands

`waza quality`, `waza suggest` and `waza tokens suggest` require Copilot auth. Probe:

```bash
waza models 2>&1 | head -5
```

If unauthenticated, run deterministic checks only and note skipped checks in the report. Mention `copilot login` unlocks them.

## Step 3: Stage the content

Waza takes paths. Normalise input:

- **File on disk**: use in place. Never write into the user's repo.
- **Pasted content**: write verbatim to `/tmp/waza-review/<slug>/SKILL.md`. Do not reformat.
- **CLAUDE.md target**: `waza tokens count/profile` work directly on any markdown. For `waza check`/`quality`, copy to a shim: `cp CLAUDE.md /tmp/waza-review/claude-md/SKILL.md`. The shim produces noise on missing frontmatter/triggers — drop those from findings, don't pass them through.

## Step 4: Run the checks

Deterministic (always run):

```bash
waza tokens count <path>
waza tokens profile <path>
waza check <skill-dir>
```

LLM tier (only if step 2 succeeded):

```bash
waza quality <skill-dir>
waza tokens suggest <skill-name-or-path>
```

Optional (only on request): `waza coverage` for repo-wide grid, `waza suggest <path> --dry-run` for eval tasks, `waza spec verify <path> <eval.yaml>` for existing eval suites. Never run `waza run` (costs premium requests, different job).

Capture stdout and exit code for every command. Exit codes: `0` success, `1` check failed, `2` config/runtime error (fix staging before reporting).

## Step 5: Write the report

Measurements only. No fixes, no rewrites, no suggested edits — those belong in step 6.

```markdown
# Waza review: <filename>

`waza <version>` · <n> checks run · <caveats if any>

## Verdict
<2-3 sentences. Is this file in good shape? What is the single biggest problem?>

## Measurements
| Check | Result | Source |
|---|---|---|
| Compliance | <score> | `waza check` |
| Token budget | <used> / <limit> | `waza tokens count` |
| Structure | <sections>, <code blocks>, workflow steps <yes/no> | `waza tokens profile` |
| Content quality | <score>/5.0 | `waza quality` |

## Findings
<Ordered by impact. For each: what waza reported, and what it means. State the problem; do not prescribe the fix here.>

## Not covered
<Checks skipped and why. Shim artefacts discarded.>
```

Rules:
- Report numbers as waza gave them. Never round up or infer.
- Separate waza findings from your own observations.
- Order by impact (a skill that never triggers has one problem; token count isn't it).
- Describe problems, not solutions. Step 6 carries the solutions.

## Step 6: Write the recommendations

A separate section after the report, so the user reads the measurement before the opinion.

```markdown
## Recommendations

1. **<Fix>** — <finding it addresses, and the concrete change: replacement wording, section to split out, frontmatter line to add.>
2. ...
```

Rules:
- One recommendation per finding worth acting on. Say which findings you are deliberately leaving alone.
- Order by impact, matching the report's finding order.
- Show proposed wording inline in a fenced block, so the user can judge it without asking.
- Phrase as proposals ("replace X with Y"), not as completed work ("I updated X").
- Everything stays in the chat. Nothing is written to disk, including `references/`.
- Where you are unsure, ask a question instead of making a recommendation.

## Step 7: Stop and ask

End the review here and ask with `AskUserQuestion`:

- **Implement all** — apply every recommendation, then stop again.
- **Discuss** — talk through a finding before deciding.
- **Nothing further** — the report was the deliverable.

To implement only some, the user types the numbers in "Other". Apply only those, then stop again.

Then wait. An obvious or low-risk recommendation is still a recommendation until the user picks it.

Optionally offer one follow-up diagnostic as an offer, not an action:

- Weak triggers: `waza suggest <path> --focus negative-triggers --dry-run`
- Good scores, heading to PR: `waza new eval <skill-name>`
- Over budget: a split into `references/`, sketched in the recommendations and written on request

## Interpreting common findings

**Low compliance / missing frontmatter**: The `name` and `description` are the triggering mechanism. Fix description first.

**Token budget exceeded**: Limits resolve from `.waza.yaml` > `.token-limits.json` > built-in defaults. Report the limit waza used. Recommend progressive disclosure (`references/`), not compression.

**Scope reduction advisory**: Counts `USE FOR` items, `##` headings, numbered procedures (takes max). Advisory only. Present as a question: did the file lose coverage?

**No workflow steps detected**: File describes a topic instead of a procedure. Agent instructions work better as ordered steps.

**Low trigger precision**: Description missing anti-triggers. Adding `DO NOT USE FOR` usually moves this more than rewriting positive triggers.

## Command reference

### waza check

```bash
waza check <skill-name | skill-path> [--format text|json]
```

Always pass path explicitly (no argument checks all skills in workspace). Text output: compliance score, token budget, eval suite presence, advisory checks.

### waza tokens

```bash
waza tokens count <path>          # token count for file or tree
waza tokens profile <path>        # structural analysis (--format text|json)
waza tokens suggest <path>        # LLM optimisation suggestions (requires auth)
waza tokens compare main --skills --threshold 10
```

`tokens count` and `tokens profile` accept any markdown path (works on CLAUDE.md without shim).

Profile reports: token count, section count, code block count, workflow step detection. Warns on: no workflow steps, >2500 tokens, <3 sections.

Token limits priority: `.waza.yaml` `tokens.limits` > `.token-limits.json` > built-in defaults.

### waza quality

LLM-as-judge scoring: clarity, completeness, trigger precision, scope coverage, anti-patterns. Each 1-5, overall out of 5.0.

```bash
waza quality <skill-dir> [--format table|json] [--model <model>]
```

Scores vary between runs. Treat as signal, not absolute measurement.

### waza suggest

Generates eval artifacts from a SKILL.md. Defaults to `--dry-run`.

```bash
waza suggest <path> --dry-run
waza suggest <path> --focus negative-triggers --count 5 --dry-run
```

`--apply` writes files to the working tree, so it is out of scope for a review. Never run it — with or without `--force` — unless the user asks for it by name in a later turn. Within a review, always `--dry-run`.

Focus options: `triggers`, `negative-triggers`, `edge-fixtures`, `do-not-use-for`, `parameters`.

### waza coverage

Repo-wide eval coverage grid. Levels: Full, Partial, Missing.

```bash
waza coverage [--format markdown] [--path <dir>]
```

### waza spec verify

Checks eval.yaml covers the contract in a SKILL.md.

```bash
waza spec verify <skill-path> <eval.yaml> [--format human|json|github-actions]
waza spec verify --skill <path> --eval <path> [--semantic] [--fail --threshold <n>]
```

### Commands to avoid during a review

- `waza run`: executes real eval, costs premium requests
- `waza dev --auto`: rewrites SKILL.md in place
- `waza suggest --apply --force`, `waza run --update-snapshots`, `waza init`: write to working tree

### Exit codes

`0` success, `1` check(s) failed, `2` config/runtime error.

### Environment variables

| Variable | Description |
|---|---|
| `GITHUB_TOKEN` | Copilot SDK execution |
| `COPILOT_BASE_URL` | Custom provider (bypasses standard auth check) |
| `COPILOT_API_KEY` | API key for custom provider |
| `WAZA_NO_UPDATE_CHECK` | Set `1` to suppress version notice |
