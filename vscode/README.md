# VS Code markdown preview styles

`markdown.css` restyles VS Code's built-in markdown preview, mainly to cap the
content at a readable max width instead of letting text run the full window.

## Why there is a symlink involved

The `markdown.styles` setting accepts only https URLs or paths relative to the
open workspace folder. An absolute path is not a workaround: the preview runs in
a webview whose allowed resource roots are the open workspace folder(s) plus the
previewed file's own directory, so a local stylesheet outside the open folder is
silently refused.

The way around it is a user-level setting pointing at a relative path, plus a
symlink in each project that points back to this repo. One source of truth, no
copies to keep in sync.

## One-time setup

1. Add to user settings (`Preferences: Open User Settings (JSON)`):

   ```json
   {
     "markdown.styles": [".vscode/markdown.css"]
   }
   ```

   Projects with no symlink just ignore the setting, so this is safe globally.

2. Ignore the link everywhere so it never lands in a project's git history:

   ```bash
   git config --global core.excludesfile ~/.config/git/ignore
   echo '.vscode/markdown.css' >> ~/.config/git/ignore
   ```

## Per project

From the project root:

```bash
mkdir -p .vscode
ln -s ~/Projects/dotfiles/vscode/markdown.css .vscode/markdown.css
```

Or use the helper below.

## Helper

```bash
md-css() {
  local target="$HOME/Projects/dotfiles/vscode/markdown.css"
  [ -f "$target" ] || { echo "md-css: $target not found" >&2; return 1; }
  mkdir -p .vscode
  ln -sf "$target" .vscode/markdown.css
  echo "md-css: linked .vscode/markdown.css -> $target"
}
```

## Notes

- Edits to `markdown.css` show up on save. If a preview is already open and looks
  stale, run `Markdown: Reload Preview` from the command palette.
- No `!important` needed; this stylesheet is injected after VS Code's own
  defaults, so plain selectors win.
- Wide content (code blocks, tables, images) needs `max-width: 100%` and
  `overflow-x: auto`, otherwise it pushes past the max width.
