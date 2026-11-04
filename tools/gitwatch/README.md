# gitwatch

Commits every change in a project to a **shadow repository** — a git-dir beside
the work tree, not inside it — within seconds of it happening. Local history at
the granularity of an editor's timeline, but for every writer: editors, agents,
`task` runs.

Complements [backup/](../backup), which snapshots once a day. The real
repository's history, branches, index and hooks are never touched.

```
Projects/
  my-acme-project/               the project — untouched
  .git-shadow/
    my-acme-project/             its shadow git-dir
  my-acme-project.worktrees/
    feature-branch/              a linked worktree
    .git-shadow/
      feature-branch/            its shadow git-dir
```

One launchd agent covers a whole project: it polls `git worktree list` every 30s
and keeps one `gitwatch` process alive per checkout, so worktrees are picked up
and cleaned up as they come and go.

## Setup

```sh
brew install gitwatch          # pulls coreutils and fswatch
```

Install the agent from this directory, so `$PWD` supplies the script path:

```sh
sed -e 's|{{LABEL}}|com.example.my-acme-project-shadow-gitwatch|g' \
    -e "s|{{HOME}}|$HOME|g" \
    -e "s|{{SCRIPT_PATH}}|$PWD/shadow-gitwatch.zsh|g" \
    -e "s|{{PROJECT_PATH}}|$HOME/Projects/my-acme-project|g" \
    -e 's|{{PROJECT_NAME}}|my-acme-project|g' \
    gitwatch-agent.template.plist > ~/Library/LaunchAgents/com.example.my-acme-project-shadow-gitwatch.plist

mkdir -p ~/Library/Logs/my-acme-project     # launchd will NOT create this
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.example.my-acme-project-shadow-gitwatch.plist
```

Paths inside the plist must be absolute; `~` and `$HOME` are not expanded there.
Logs land in `~/Library/Logs/<project>/<project>.gitwatch.log` and
`.gitwatch.error.log`.

## Reading the history

```sh
shadow-git.zsh <project-path> [--] <git args…>

shadow-git.zsh ~/Projects/my-acme-project -- log --oneline
shadow-git.zsh ~/Projects/my-acme-project -- log --oneline -- src/app.ts
shadow-git.zsh ~/Projects/my-acme-project.worktrees/feature-branch -- status
```

**Recover through a scratch file, never `checkout`.** The shadow's work tree *is*
the live project, so `git checkout` or `git restore` writes straight into what
you are working on — and the watcher commits the result seconds later.

```sh
shadow-git.zsh <project> -- show <commit>:src/app.ts > /tmp/recovered
```

## What is committed, what is watched

Two different questions, answered by two files the **project** owns:

| File | Controls | How |
| --- | --- | --- |
| `.gitignore` | what is committed | git reads the work tree's own ignore rules, so the shadow tracks exactly what the real repo would |
| `.backupignore` | what wakes the watcher | high-churn paths are dropped at the `fswatch` level, so a `pnpm install` does not spin the watcher |

Worth knowing:

- **Gitignored files are never captured.** `.env` and friends exist only in the
  daily rsync backup. The two layers are complementary.
- A path in `.backupignore` but not `.gitignore` **is still committed** — it just
  never triggers a commit on its own.
- A worktree with no `.backupignore` falls back to the primary checkout's.
- With no `.backupignore` at all, every file change wakes the watcher. The log
  says so.

`.backupignore` is the same rsync-syntax file `backup-project.zsh` uses.
Anchored (`/website/out/`), floating (`node_modules/`) and wildcard
(`*.tsbuildinfo`) patterns are translated; character classes are not.

## Commits and hooks

Commits are authored as `gitwatch (local history) <gitwatch@localhost>` and
**no hooks ever run**: `core.hooksPath` lives in the real `.git/config`, which
the shadow git-dir does not read, so husky and commitlint never see an
auto-commit. Signing is disabled — an unattended committer that prompts is one
that loses work.

## Limitations

- **History growth is unmanaged.** Nothing squashes or prunes. Delete a shadow
  when it stops earning its disk — `rm -rf <parent>/.git-shadow/<name>` — and it
  is recreated on the next start.
- **Shadows are not backed up.** They sit outside the tree `backup-project.zsh`
  copies. This is a local safety net, not an archive.
- Removing a worktree leaves its shadow in place on purpose; deleting history is
  a human decision.

## Scripts

| Script | Use |
| --- | --- |
| `shadow-gitwatch.zsh <project>` | the supervisor the agent runs. `--interval`, `--debounce`, `--once` |
| `shadow-git.zsh <project> -- …` | run git against a shadow repository |
| `shadow-init.zsh <project>` | create one; idempotent, and called automatically |

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| Agent exits non-zero, logs empty | The log directory does not exist. `mkdir -p ~/Library/Logs/<project>`. |
| No commits and no errors | The change was to a gitignored file. Check `shadow-git.zsh <project> -- status`. |
| Constant CPU during installs or builds | That checkout has no `.backupignore`. |
| Commits contain build output | The project's `.gitignore` does not cover it. |
| `another supervisor for <path> is already running` | The agent is loaded and you also ran the script by hand. |
| `fatal: Unable to read current working directory` | A watcher noticing its worktree was removed. Harmless. |
| `fswatch` processes left running | The supervisor was `SIGKILL`ed, so its cleanup trap never ran. The next start sweeps them. |

Reload after editing the plist:

```sh
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/<label>.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/<label>.plist
```
