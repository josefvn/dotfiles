# dotfiles

Configuration managed with [GNU Stow](https://www.gnu.org/software/stow/)
(`brew install stow`).

## Layout

The top level splits the repo by how things are installed:

```
dotfiles/
  .stowrc                       stow defaults: target $HOME, dir stow/
  stow/                         stow packages, and nothing else
    claude/
      .stow-local-ignore        what stow skips inside this package
      .claude/
        skills/*                → ~/.claude/skills/*
  tools/                        not packages; each is installed by hand
    backup/                     daily project snapshots — see its README
    gitwatch/                   shadow-git history of every change — see its README
    vscode/                     markdown preview stylesheet — see its README
```

Every directory in `stow/` is a **stow package**, laid out exactly as it should
appear under `$HOME`. Anything that is not a package goes in `tools/`, with a
README explaining its setup.

## Installing

Stow reads `.stowrc` only from the current directory (or `~/.stowrc`), so run
these from the repo root:

```sh
stow claude
```

Preview first with `stow -nv claude`, remove with `stow -D claude`, and
re-apply after adding or moving files with `stow -R claude`. Since `stow/` holds
only packages, `stow $(ls stow)` installs everything. Don't `cd stow` first:
without `.stowrc`, stow would target the repo root instead of `$HOME`.

Before moving or renaming a package, run `stow -D` on it first; otherwise the
links in `$HOME` are left dangling.

## Packages

### claude

Links each file in `stow/claude/.claude` into `~/.claude`.

`~/.claude` itself stays a real directory — Claude Code keeps sessions, caches
and logs there, and none of that belongs in the repo. `~/.claude/skills` is a
real directory too, because it also holds skills not managed here (such as
`synced/`). `.stowrc` passes `--no-folding`, so stow always creates real
directories and links files one by one, even on a fresh machine where
`~/.claude` does not exist yet. Without it, stow would link the whole folder
into the repo, and everything Claude Code writes there would land in it. After
adding or renaming a file, run `stow -R claude` to link it.

`.stow-local-ignore` keeps `.DS_Store` out of the target; it replaces stow's
built-in ignore list, so the defaults worth keeping (`README.*`, `.git*`, editor
backups) are repeated in it.
