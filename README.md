# television.yazi

A [Yazi](https://github.com/sxyazi/yazi) plugin that uses [television](https://github.com/alexpasmantier/television) instead of `fzf` for file picking.

## Requirements

- [Yazi](https://github.com/sxyazi/yazi) v25.4.8+
- [`tv`](https://github.com/alexpasmantier/television) available on `PATH`

## What It Does

- Opens `tv files <cwd>` from the active Yazi directory
- Reveals the selected file or enters the selected directory
- Supports passing extra `tv` flags through `setup()` or plugin args

## Installation

```sh
ya pkg add OneNoted/television
```

For a local checkout, place this repo at `~/.config/yazi/plugins/television.yazi`.

## Configuration

Add a keymap that points at the plugin instead of Yazi's built-in `fzf` plugin:

```toml
[[mgr.prepend_keymap]]
on = [ "f" ]
run = "plugin television"
desc = "Jump to a file with television"
```

Optional `init.lua` setup:

```lua
require("television"):setup({
  channel = "files",
  args = {
    "--preview-size",
    "55",
  },
})
```

You can also pass one-off `tv` flags from the keymap:

```toml
[[mgr.prepend_keymap]]
on = [ "F" ]
run = "plugin television -- --input=src"
desc = "Open television with an initial query"
```

## Notes

- The plugin always forces `--source-output {}` so Yazi receives raw paths back from `tv`.
- Cancellation is treated as a normal exit.
- If your `tv` setup is customized through television channels, set `channel` in `setup()` to use that channel instead of `files`.
