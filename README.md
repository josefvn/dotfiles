# dotfiles

Configuration managed with [GNU Stow](https://www.gnu.org/software/stow/)
(`brew install stow`).

## Layout

Each top-level directory that mirrors a path under `$HOME` is a **stow
package**. Its contents are laid out exactly as they should appear in the home
directory:

```
dotfiles/
  .stowrc                       stow defaults: target $HOME, dir this repo
  claude/                       package
    .stow-local-ignore          what stow skips inside this package
    .claude/
      skills/                   → ~/.claude/skills
  backup/                       not a package — see backup/README.md
```

`backup/` is a standalone script and its launchd template, not a package. Never
run `stow */`; name packages explicitly.

## Installing

`.stowrc` supplies `--target` and `--dir`, so from anywhere:

```sh
stow claude
```

Preview first with `stow -nv claude`, remove with `stow -D claude`, and
re-apply after moving files around with `stow -R claude`.

## Packages

### claude

Links `~/.claude/skills` to `claude/.claude/skills`.

`~/.claude` itself stays a real directory — Claude Code keeps sessions, caches
and logs there, and none of that belongs in the repo. Stow descends into it and
folds the tree at `skills`, so the whole directory is one symlink and any skill
added later under `~/.claude/skills` lands in this repo automatically.

`.stow-local-ignore` keeps `.DS_Store` out of the target; it replaces stow's
built-in ignore list, so the defaults worth keeping (`README.*`, `.git*`, editor
backups) are repeated in it.
