# Shell commands

I mostly work in the Zed agent panel, which renders every shell command in full. Long, multi-line commands make the panel hard to read, so keep commands compact.

- Start every Bash tool command with 1–3 `#` comment lines explaining what it does and why, then a blank line, then the command itself on a single line. Keep each comment line to 85 characters or fewer; if the comment is longer, wrap it onto the next `#` line (up to 3 lines). For example:
  ```
  # Count lines in each SKILL.md to spot oversized skills

  wc -l stow/claude/.claude/skills/*/SKILL.md
  ```
- Apart from those comment lines, chain steps with `&&`, `;` or `|` instead of newlines.
- Give each command one job. Run unrelated steps as separate commands, each with its own comment, rather than chaining them with `;` or `echo ---` separators.
- Don't repeat work within a command. For example, list results once and count them from the output rather than running the same query twice.
- Don't `cd` into the current working directory; commands already run there, so use relative paths.
- Do not use heredocs, multi-line `for`/`while`/`if` blocks or line continuations (`\`) in commands.
- When logic does not fit on one line, write it to a script file with the Write tool, then run that file in a one-line command.
- Start every script file you write with a 1–3 line comment explaining what it does.
- Use the Read, Edit and Write tools for file contents rather than `cat <<EOF` or `sed` with multi-line patterns.
- Keep the command description short (a few words).
