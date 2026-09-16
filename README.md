# omarchy-protondrive-sync

An [Omarchy](https://omarchy.org) bar-widget plugin that keeps one local
folder and one Proton Drive folder in sync, using Proton's official
`proton-drive` CLI. Not an official Proton or Omarchy project.

- Local changes sync near-instantly (inotify).
- Remote changes are picked up on a poll interval (default 2 minutes).
- Runs entirely inside your own desktop session as a subprocess the Omarchy
  shell supervises -- no systemd unit, no root.
- Conflicts (edited on both sides since the last sync) are never resolved
  by silently deleting one version -- see `SPEC.md`.

See `SPEC.md` for the full design, the sync algorithm, and known
limitations. See `CLAUDE.md` if you're an AI agent picking up work here.

## Requirements

- Proton Drive CLI, installed and logged in -- see below.
- `inotify-tools` (for instant local-change detection; without it, local
  changes still sync, just only on the poll interval):
  ```
  sudo pacman -S inotify-tools
  ```
- `python3` (stdlib only, no extra packages) -- already on any Omarchy
  install.

### Installing the Proton Drive CLI on Omarchy

It's not packaged for Arch/AUR (checked, not present as of this writing)
-- Proton ships it as a single self-contained binary. Download it, verify
it, put it on your `PATH`, then log in:

```
curl -fsSL -o ~/.local/bin/proton-drive \
  https://proton.me/download/drive/cli/0.8.0/linux-x64/proton-drive
chmod +x ~/.local/bin/proton-drive
```

Verify the checksum before trusting it (values change every release --
confirm the current one at
[proton.me/download/drive/cli](https://proton.me/download/drive/cli/index.html)
rather than assuming the one below is still current):

```
echo "cf61c2688c45e1055d8add6221d9471a5a5b64bf3bcdb86460f5cb18414596cc4df3cdb6627c9097c94bec32a3c9915ada3211ef2ae5be33c46ebbc996ccaa28  $HOME/.local/bin/proton-drive" | sha512sum -c -
```

`~/.local/bin` is already on `PATH` for a default Omarchy user account. If
`proton-drive` immediately crashes with `Illegal instruction` (older
CPUs without AVX2 -- uncommon, but happens on some NAS/embedded
hardware), re-download using the `linux-x64-baseline` build instead of
`linux-x64` in the URL above.

Then authenticate (opens a browser, no password on the command line):

```
proton-drive auth login
```

## Install

```
omarchy plugin add https://github.com/xqus/omarchy-protondrive-sync.git --enable
```

Or, for local development, point it at a local path instead of a URL, then
re-run after each change (plugin folders can't be symlinks -- the shell
refuses to load them, as a security boundary):

```
omarchy plugin add /path/to/omarchy-protondrive-sync --enable
```

## Configure

Click the ⚙ in the panel to open the settings form (local folder, Proton
Drive folder, poll interval, conflict strategy) and hit Save. Omarchy's
shell doesn't provide a generic settings GUI of its own -- the manifest
`schema` is stored but never rendered into a form anywhere in the version
this was built against -- so this plugin ships its own, writing through
the same `setBarWidget` shell IPC call the `omarchy bar set` CLI itself
uses.

You can also set values directly from a terminal, which is equivalent:

```
omarchy bar set xqus.protondrive-sync localFolder "~/ProtonSync"
omarchy bar set xqus.protondrive-sync remoteFolder "/my-files/Sync"
omarchy bar set xqus.protondrive-sync pollIntervalSec 120
omarchy bar set xqus.protondrive-sync conflictStrategy "Keep both (rename)"
```

| Setting | Meaning |
|---|---|
| `localFolder` | Folder to watch, e.g. `~/ProtonSync`. Created if missing. |
| `remoteFolder` | Remote path under `/my-files`, e.g. `/my-files/Sync`. Created if missing. `/devices` ("Computers") is not supported -- see `SPEC.md`. |
| `pollIntervalSec` | How often to check Proton Drive for changes made elsewhere. |
| `conflictStrategy` | What to do when a file changed on both sides since the last sync: `"Keep both (rename)"` (default), `"Prefer local"`, or `"Prefer remote"`. |

Each `omarchy bar set` call only touches the one key you name -- it merges
into the widget's existing settings, so setting one value doesn't clear the
others. **`omarchy plugin disable` followed by `enable` does not preserve
settings** -- it re-adds a bare `{"id": ...}` entry to the bar layout, so
any previously-set keys are gone and need to be set again. Use
`omarchy restart shell` instead if you need to force a reload (e.g. after
changing the plugin's QML files), not disable+enable.

Click the bar icon for status, recent activity, and a manual "sync now."
Right-click the icon to sync immediately; middle-click to re-check
installation/login state.

## Testing the daemon standalone

The sync engine is a plain script and can be run without the shell, useful
for debugging:

```
python3 bin/protondrive-sync \
  --local ~/ProtonSync \
  --remote /my-files/Sync \
  --state-file /tmp/protondrive-sync-state.json \
  --once
```

`--once` reconciles a single time and exits instead of watching/polling
forever.

## License

MIT, see `LICENSE`.
