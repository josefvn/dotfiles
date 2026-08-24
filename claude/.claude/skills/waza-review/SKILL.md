---
name: waza-review
description: Analyse a SKILL.md, .agent.md or CLAUDE.md file with the Microsoft waza CLI (compliance, token budget, structure, LLM-as-judge quality) and turn the raw output into a prioritised review with concrete fixes. Use this whenever the user asks to review, audit, lint, grade, check, score or "run waza on" an agent instruction file, whether they upload it, give a path, or paste its contents into the chat. Also use it when the user asks why a skill is not triggering, whether a skill is too long or over budget, or whether a CLAUDE.md is well written, since waza measures those things directly instead of guessing.
---

# Waza skill review

USE FOR: reviewing a SKILL.md, auditing a CLAUDE.md, checking skill compliance, checking token budget, diagnosing skill trigger problems, scoring skill content quality, preparing a skill for submission or PR.

DO NOT USE FOR: authoring a brand new skill from nothing, running a full behavioural eval suite against a model (`waza run`), or reviewing ordinary source code and documentation that is not agent instructions.

Waza is Microsoft's Go CLI for agent skills. It measures things that are otherwise guesswork: whether a skill declares what the spec requires, how many tokens it burns, how many distinct capabilities it still covers, and how an LLM judge scores its clarity and trigger precision. The value of this skill is doing the measurement first and reading the file second, so the review is grounded in tool output rather than in a pleasant-sounding impression.

## Step 1: Assert that waza is available

Do this before anything else, including before reading the target file. Everything downstream depends on it.

```bash
command -v waza >/dev/null 2>&1 && waza --version
```

**If waza is present**, note the version in the final report. Behaviour and flags shift between releases, so the version is part of the evidence.

**If waza is missing**, stop. Tell the user plainly that waza is not on PATH and offer the install options below. Do not quietly substitute your own reading of the file for a waza run: the user asked for a measurement, and a hand-wave dressed up as a report is worse than no report. If they then say "just review it yourself", that is fine, but make sure it is their choice and label the output as a manual review.

```bash
# macOS, Linux, Git Bash, MSYS2, Cygwin
curl -fsSL https://raw.githubusercontent.com/microsoft/waza/main/install.sh | bash

# Native Windows PowerShell
irm https://raw.githubusercontent.com/microsoft/waza/main/install.ps1 | iex
```

In VS Code, the `ms-vscode.vscode-chat-customizations-evaluations` extension ships a `Chat Customizations Evaluations: Download Waza Binary` command, and the binary location can be overridden with the `chatCustomizationsEvaluations.waza.command` setting. If the user has a waza binary somewhere off PATH, ask for the path and use it in place of `waza` throughout.

## Step 2: Check whether the LLM-backed commands are usable

`waza quality`, `waza suggest` and `waza tokens suggest` call a model through the Copilot SDK; the rest are deterministic and offline. Probe once so the plan is realistic:

```bash
waza models 2>&1 | head -5
```

An unauthenticated environment reports something like `Error: not authenticated - run "copilot login" first`. If that happens, run the deterministic checks anyway, say explicitly in the report which checks were skipped and why, and mention that `copilot login` unlocks them. A partial review that names its gaps is useful. A review that silently drops the quality score and reads as complete is not.

## Step 3: Get the content onto disk in a shape waza understands

Waza commands take paths, and most of them expect a skill directory containing a `SKILL.md`. Normalise the input into that shape before running anything.

**The file is already on disk** (a path the user gave, or an upload): run against it in place where the command accepts a file path. For commands that want a skill directory, use the directory the file already lives in. Never write into the user's repository as part of a review.

**The content was pasted into the chat**: write it verbatim to a scratch directory and work there. Do not reformat, reflow or tidy it on the way in; token counts and structure checks are measuring the exact bytes the user has.

```bash
mkdir -p /tmp/waza-review/<slug>
cat > /tmp/waza-review/<slug>/SKILL.md <<'WAZA_EOF'
...pasted content, unmodified...
WAZA_EOF
```

**The target is a CLAUDE.md**: this needs care. `waza tokens count` and `waza tokens profile` take any markdown path and work directly on it. `waza check` and `waza quality` expect skill semantics, so they need the file staged as a `SKILL.md` shim:

```bash
mkdir -p /tmp/waza-review/claude-md
cp path/to/CLAUDE.md /tmp/waza-review/claude-md/SKILL.md
```

The shim produces real signal on clarity, structure and token weight, and produces noise on anything spec-specific. A CLAUDE.md has no YAML frontmatter and no `USE FOR` block, so waza will flag missing `name`, missing `description` and poor trigger precision every time. Those are artefacts of the shim, not defects in the file. Say so in the report and drop them from the findings rather than passing them on. Handing someone three confident findings they cannot act on teaches them to distrust the other seven.

## Step 4: Run the checks

Deterministic tier, always run these:

```bash
waza tokens count <path-to-file>
waza tokens profile <path-to-file>
waza check <skill-dir> --verbose
```

LLM tier, run only if step 2 succeeded:

```bash
waza quality <skill-dir>
waza tokens suggest <skill-name-or-path>
```

Optional, and only when the user cares about evaluation coverage rather than the file itself: `waza coverage` for a repo-wide grid, `waza suggest <skill-path> --dry-run` to propose eval tasks, and `waza spec verify <skill-path> <eval.yaml>` when an eval suite already exists. Do not run `waza run`; that executes a real eval against a model, costs premium requests, and is a different job from reviewing a file.

Capture stdout and the exit code for every command. Exit codes are `0` success, `1` one or more tasks or checks failed, `2` configuration or runtime error. A `2` usually means the input was staged wrong rather than that the file is bad, so re-read the error and fix the staging before reporting anything.

`references/waza-commands.md` has the fuller flag reference, output shapes, and the JSON variants for scripted runs. Read it when a command errors unexpectedly, when the user wants machine-readable output, or when they ask about a waza command not covered above.

## Step 5: Write the report

Use this structure. Lead with the verdict, because that is the thing the user actually wants.

```markdown
# Waza review: <filename>

`waza <version>` · <n> checks run · <shim or auth caveat, if any>

## Verdict

<Two or three sentences. Is this file in good shape, and what is the single biggest thing to fix?>

## Measurements

| Check           | Result                                                 | Source                 |
| --------------- | ------------------------------------------------------ | ---------------------- |
| Compliance      | <score>                                                | `waza check --verbose` |
| Token budget    | <used> / <limit>                                       | `waza tokens count`    |
| Structure       | <n> sections, <n> code blocks, workflow steps <yes/no> | `waza tokens profile`  |
| Content quality | <overall>/5.0                                          | `waza quality`         |

## Findings

<Ordered by impact, not by the order waza printed them. For each: what waza
reported, what it means, and the concrete edit that fixes it.>

## Not covered

<Checks skipped, and why. Shim artefacts discarded, and which ones.>
```

Some things to hold to while writing it:

- Report waza's numbers as waza gave them. Never round a score up, never infer a token count, never describe a failed check as a warning. If a command errored, the report says it errored.
- Separate waza's findings from your own. Your reading of the file is often the more useful half of the review, especially on a CLAUDE.md, but the user needs to know which is which so they can weigh it.
- Turn each finding into an edit. "Trigger precision scored 2/5" is a measurement; "the description says what the skill does but never says when to reach for it, so add the trigger phrases the user would actually type" is a fix. The measurement without the fix leaves the work undone.
- Order by impact. A skill that never triggers has one problem worth solving, and its token count is not it.
- Do not modify the user's file. Offer the rewrite, show the diff or the replacement block, and let them apply it. If they ask you to apply it, do it then.

## Interpreting the common findings

**Compliance score low or missing frontmatter fields.** The `name` and `description` in the YAML frontmatter are the whole triggering mechanism; a skill with a vague description is invisible regardless of how good the body is. Fix the description first.

**Token budget exceeded.** Limits resolve from `.waza.yaml` `tokens.limits`, then a legacy `.token-limits.json`, then built-in defaults, so the ceiling depends on the project. Report the limit waza used rather than assuming a number. The usual fix is not compression but progressive disclosure: move detail into `references/` and leave a pointer.

**Scope reduction advisory.** This counts `USE FOR` items, level-two headings, and numbered procedures, takes the maximum, and warns when it falls below the threshold. It fires when a file has been compressed to fit a budget and lost workflow coverage on the way. It is advisory and does not block readiness, so present it as a question rather than a defect: did this file used to do more?

**No workflow steps detected** (from `tokens profile`). The file describes a topic instead of a procedure. Agent instruction files work better as ordered steps than as prose about a domain.

**Trigger precision scored low** (from `waza quality`). The description is missing the anti-triggers. Adding an explicit `DO NOT USE FOR` line usually moves this more than rewriting the positive triggers does.

## Offering the next step

Once the report is delivered, one suggestion is enough, tied to what the review found. A file with weak triggers benefits from `waza suggest <skill-path> --focus negative-triggers --dry-run`, which proposes negative-trigger eval tasks. A file that scored well and is heading for a PR benefits from a real eval suite via `waza new eval <skill-name>`. A file that is over budget benefits from a restructure into `references/`, which you can draft directly. Do not list all three.
