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

Open the plugin's settings from the Omarchy bar-widget settings panel:

| Setting | Meaning |
|---|---|
| Local folder | Folder to watch, e.g. `~/ProtonSync`. Created if missing. |
| Proton Drive folder | Remote path under `/my-files`, e.g. `/my-files/Sync`. Created if missing. `/devices` ("Computers") is not supported -- see `SPEC.md`. |
| Remote poll interval | How often to check Proton Drive for changes made elsewhere. |
| On conflict | What to do when a file changed on both sides since the last sync: keep both (default), prefer local, or prefer remote. |

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
