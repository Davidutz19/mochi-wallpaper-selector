# mochi-wallpaper-selector

A [Mochi](https://github.com/DavidutzDev/mochi) plugin to pick a wallpaper on the
island: a big preview of the selected wallpaper and a strip of all the others.

It sets the wallpaper with the daemon that runs (awww, swww, hyprpaper or swaybg)
or a command of your own, remembers the last one, and sets it again when Mochi
starts.

## Keys

| Key | Does |
|---|---|
| Left, Right, H, L | Select the previous or next wallpaper |
| Home, End | Jump to the first or last |
| Enter | Set the selected wallpaper and close |
| Space | Set it and stay open, to try another |
| R | Set a random one |
| Escape | Close |

With the mouse: a click selects, a double click sets, the wheel scrolls the strip.

## Install

```toml
# ~/.config/mochi/plugins.toml
[plugins.wallpaper]
source = "git:github.com/DavidutzDev/mochi-wallpaper-selector"
```

```sh
mochi plugins install wallpaper
```

With home-manager, Nix builds it during the switch:

```nix
programs.mochi.plugins.wallpaper.src = inputs.mochi-wallpaper-selector;
```

Then add `"wallpaper"` to `modules` in `config.toml`, and bind a key:

```sh
mochi ipc wallpaper toggle
```

## Settings

`settings.toml` lists them, commented at their defaults, for the `[module.wallpaper]`
section of `config.toml`:

| Setting | Default | |
|---|---|---|
| `directory` | `"~/Pictures/Wallpapers"` | The folder of wallpapers |
| `recursive` | `false` | Its subfolders too |
| `daemon` | `"auto"` | `auto`, `awww`, `swww`, `hyprpaper`, `swaybg` or `command`. `auto` takes the first of these that runs |
| `command` | `""` | With `daemon = "command"`: a shell command, `{path}` is the image, quoted. For example `"feh --bg-fill {path}"` |
| `transition` | `""` | awww and swww's transition, like `grow`, `fade` or `wipe` |
| `restore` | `true` | Set the last wallpaper again when Mochi starts |
| `default` | `""` | The wallpaper to set when none was picked yet: a path or a file name in the directory |

The last wallpaper is saved in `$XDG_STATE_HOME/mochi-wallpaper/current`
(`~/.local/state/mochi-wallpaper/current`).

## Actions

`mochi ipc wallpaper <action>`:

| Action | Does |
|---|---|
| `toggle`, `open`, `close` | The picker |
| `set <path>` | Set a wallpaper: a path, or a file name in the directory |
| `next`, `previous`, `random` | Set another wallpaper from the directory |
| `restore` | Set the last wallpaper again, or the default |
| `current`, `list` | Print the wallpaper set last, or all of them |

## Development

```sh
cargo test
cargo clippy --all-targets -- -D warnings
```

To try changes, list the plugin with a `path:` source and run
`mochi plugins install wallpaper`; views reload as you save them, and
`mochi reload` restarts the backend after a rebuild.
