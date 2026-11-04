# backup

Dated `rsync` snapshots of a project directory, driven by a launchd agent.

Snapshots land in a `.backups` directory beside the project, named
`~<name>-YYYYMMDD` and hardlinked against the previous snapshot with
`--link-dest`, so a daily history costs about as much disk as a single copy plus
whatever actually changed.

```
Projects/
  my-project/                  the project
  my-project.worktrees/        its linked worktrees
    feature-branch/
  .backups/
    ~my-project-20260818/      a snapshot
    ~my-project-20260819/      mostly hardlinks to the above
      .worktrees/
        feature-branch/        that day's copy of the worktree
```

Linked worktrees are snapshotted alongside the project — see
[Worktrees](#worktrees).

## Dependencies

| Dependency | Required | Notes |
| --- | --- | --- |
| macOS | yes | launchd, `~/Library/Logs`, and BSD `date -v` for the retention cutoff. Not portable to Linux as written. |
| zsh 5.9+ with `zsh/system` | yes | Ships with macOS. Provides `zsystem flock`, used so the calendar run and the run-at-load run cannot collide. |
| **GNU rsync 3.x** | **strongly recommended** | `brew install rsync`. See below — without it, only the first run of each day succeeds. |
| Homebrew | only for GNU rsync | Used to install rsync; the script itself does not call `brew`. |

### Why GNU rsync matters

macOS ships **openrsync** as `/usr/bin/rsync`. It writes into the destination
file in place, so it cannot overwrite the mode-`444` files git leaves in
`.git/objects`. The day's first run creates the snapshot fine; every run after
that hits those now read-only files and dies:

```
rsync: .git/objects/pack/pack-….pack: copy_file tofd: openat: Permission denied
backup-project: rsync failed with exit code 11
```

GNU rsync writes a temp file and renames it, so it has no such problem. Install
it with:

```sh
brew install rsync
```

The script picks a binary at startup, preferring GNU rsync and falling back to
the system one:

1. `/opt/homebrew/bin/rsync` (Apple silicon)
2. `/usr/local/bin/rsync` (Intel)
3. `/usr/bin/rsync` (openrsync fallback)

Candidates whose `--version` reports openrsync are skipped. The paths are
absolute because launchd hands the agent a minimal `PATH` that does not include
`/opt/homebrew/bin`. The chosen binary is echoed in the log:

```
[2026-08-20 17:16:27]   using     /opt/homebrew/bin/rsync
```

If that line reads `/usr/bin/rsync`, GNU rsync is not installed and the
day's-first-run-only limitation applies.

## Layout

```
backup/
  backup-project.zsh            the script
  backup-agent.template.plist   launchd agent template
```

Nothing else is needed here: what to skip is the backed-up project's own
business, declared in a `.backupignore` at its root — see
[What is excluded](#what-is-excluded).

## Usage

```sh
backup-project.zsh [-n] [--keep DAYS] [--no-worktrees] <project-path>
```

| Flag | Meaning |
| --- | --- |
| `-n`, `--dry-run` | show what would be copied, prune nothing |
| `--keep DAYS` | retention window, default 14 |
| `--no-worktrees` | copy only the project, skip its linked worktrees |

The project path is required and has no default, so the target is always
explicit. Snapshots older than the retention window are pruned; deleting one is
safe, as hardlinked data survives while any remaining snapshot references it.

## Worktrees

Linked worktrees are separate checkouts of the same repository, each with its
own uncommitted work, so they are backed up daily along with the project. This
is automatic; pass `--no-worktrees` to opt out.

Worktrees are discovered with `git worktree list`, not by globbing the
conventional `<project>.worktrees` directory. That matters: git knows where its
worktrees actually are, skips the main worktree (already copied as the project
itself), and ignores stray directories sitting beside real ones — a leftover
empty directory from a removed worktree is correctly not backed up.

Each worktree is copied into `.worktrees/` inside that day's project snapshot,
so a snapshot is one self-contained dated unit and pruning it takes its
worktrees with it:

```
.backups/~my-project-20260821/
  …project files…
  .worktrees/
    docs-rewrite/
    feature-branch/
```

Every tree gets its own `rsync` run rather than one run over the worktrees
parent. This is deliberate: anchored excludes like `/website/out/` are written
relative to a project root, and would silently fail to match if the transfer
root were the directory *containing* the worktrees. It also means each worktree
is filtered by the `.backupignore` on its own branch. Hardlinking is
per-worktree too — each is `--link-dest`ed against its own copy in the previous
snapshot, so a worktree's daily history costs no more than the project's does.

`.worktrees` is excluded from the project's own transfer. Without that,
`--delete` would remove it on the second run of any given day, since nothing
named `.worktrees` exists in the source. A side effect: if a project genuinely
contains a top-level `.worktrees` directory, it will not be backed up.

### Restoring a worktree

A worktree's `.git` is a *file*, not a directory, holding an absolute pointer
into the main repository:

```
gitdir: /Users/you/Projects/my-project/.git/worktrees/feature-branch
```

The other half of that link lives in the project's own `.git/worktrees/`, which
is backed up too, so restoring a snapshot to its original path gives back
working worktrees.

**Restoring anywhere else needs a repair step, and failing to do it is worse
than a visible error.** If the original project still exists on the machine,
those absolute paths still resolve — so a restored worktree silently attaches to
the *live* repository. `git status` looks perfectly healthy while you are in
fact operating on the original repo, and a `checkout` or `reset` there would hit
live work.

Restore the worktrees to a sibling directory and repair them, from the restored
project:

```sh
mv my-project/.worktrees my-project.worktrees
cd my-project
git worktree repair ../my-project.worktrees/*
```

Confirm each worktree now points at the restored repo, not the original:

```sh
git -C ../my-project.worktrees/feature-branch rev-parse --git-common-dir
```

`git worktree repair` fixes both halves of the link and touches only the
restored copy, leaving the live repository untouched.

## Installing the launchd agent

Fill in the template placeholders and load the result. Run this from this
directory, so that `$PWD` supplies the path to the script and nothing has to be
hardcoded to where the repository happens to be cloned. For
`~/Projects/my-project`:

```sh
sed -e 's|{{LABEL}}|com.example.my-project-backup|g' \
    -e "s|{{HOME}}|$HOME|g" \
    -e "s|{{SCRIPT_PATH}}|$PWD/backup-project.zsh|g" \
    -e "s|{{PROJECT_PATH}}|$HOME/Projects/my-project|g" \
    -e 's|{{PROJECT_NAME}}|my-project|g' \
    backup-agent.template.plist > ~/Library/LaunchAgents/com.example.my-project-backup.plist

mkdir -p ~/Library/Logs/my-project
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.example.my-project-backup.plist
```

`launchd` resolves `ProgramArguments` against no working directory and inherits
no shell, so both `{{SCRIPT_PATH}}` and `{{PROJECT_PATH}}` must expand to
absolute paths — `~` and `$HOME` are not expanded inside the plist.

The log directory must exist first — **launchd does not create it**, and an
agent whose `StandardOutPath` is unwritable fails at spawn.

The agent runs daily at 09:00 and again at load, covering the case where a
calendar interval is missed across a full power-off. The script is idempotent
and holds a lock, so the extra run is cheap.

Reload after editing the plist, and trigger a run on demand:

```sh
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.example.my-project-backup.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.example.my-project-backup.plist
launchctl kickstart gui/$(id -u)/com.example.my-project-backup
```

## Logs

Both streams are `.log` files in one directory per project:

```
~/Library/Logs/<project-name>/<project-name>.log
~/Library/Logs/<project-name>/<project-name>.error.log
```

Check agent state and the last result with:

```sh
launchctl print gui/$(id -u)/com.example.my-project-backup | grep -E 'state =|last exit|runs ='
```

## What is excluded

Nothing, unless the project says so. Each tree is filtered by a `.backupignore`
at its own root — the project's for the project, and each worktree's own copy
for that worktree, so the list travels with the branch it belongs to.

The file is an `rsync --exclude-from` list, one pattern per line, `#` for
comments:

```
# Dependencies
node_modules/

# Build output
dist/
.next/

# Anchored to the project root: a bare `out/` would match anywhere
/website/out/

# OS noise
.DS_Store
```

Patterns without a leading slash match at any depth; a leading slash anchors to
the root of that tree. The rule for what goes in: if a build, codegen or install
step recreates it, it does not belong in a backup. Anything
local-but-unrecoverable — `.env` files, `.git`, local notes — is deliberately
left out of the list and so gets backed up.

A tree with no `.backupignore` is copied whole, and the run logs a note saying
so.

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| `Permission denied` on `.git/objects/…`, exit 11 | openrsync in use. `brew install rsync`. |
| Agent shows a non-zero `last exit code` but logs are empty | The log directory does not exist. `mkdir -p ~/Library/Logs/<project-name>`. |
| `another backup of <name> is already running` | Expected: the lock is held by a concurrent run. Not an error. |
| `rsync 24` / `some files vanished mid-run` | Routine on a live working tree. Treated as success. |
| The snapshot contains `node_modules` and other build output | That tree has no `.backupignore`; the log says so. Add one at its root. |
| A worktree is missing from the snapshot | It is not registered with git, or its directory is gone. Check `git worktree list`. |
| A restored worktree shows the live repo's state | Its `.git` pointer is absolute and still resolves. Run `git worktree repair` — see [Restoring a worktree](#restoring-a-worktree). |
