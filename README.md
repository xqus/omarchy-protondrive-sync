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

- [Proton Drive CLI](https://proton.me/download/drive/cli), installed and
  logged in (`proton-drive auth login`).
- `inotify-tools` (for instant local-change detection; without it, local
  changes still sync, just only on the poll interval).
- `python3` (stdlib only, no extra packages).

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

There is currently no settings GUI to click through -- Omarchy's shell
stores a manifest `schema` for bar-widget settings but (as of the version
this was built against) never renders it into a form. Set values with the
bar CLI instead, which is also what any GUI would write to under the hood:

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
