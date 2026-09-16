# Working in this repo

This is an Omarchy shell plugin (bar-widget kind) that syncs one local
folder with one Proton Drive folder via the official `proton-drive` CLI.
Read `SPEC.md` first -- it has the full design, the sync algorithm, the
conflict/deletion-safety rules, and known limitations. This file is about
*how to work on the code*, not what it does.

## Layout

- `bin/protondrive-sync` -- the actual sync engine. Plain Python 3, stdlib
  only, no dependencies. This is where sync logic/bugs live.
- `Service.qml` -- owns settings, spawns/supervises the daemon process,
  parses its JSON stdout into QML properties the panel reads.
- `Panel.qml` -- the bar icon + dropdown UI. Modeled closely on the
  first-party `omarchy-dropbox` plugin
  (`/usr/share/omarchy/shell/plugins/panels/dropbox/`) -- when in doubt
  about a `qs.Ui`/`qs.Commons` component's API, read that file, not this
  one; it's the ground truth this was built against.
- `ProtonSyncIcon.qml` -- generic transfer-arrows glyph, not a Proton brand
  mark (this is an unofficial plugin).
- `Model.js` -- formatting helpers for the panel's activity list.
- `manifest.json` -- plugin metadata + settings schema.

## Editing the daemon (`bin/protondrive-sync`)

This is a normal Python script -- edit and test it directly, no shell
involved:

```
python3 bin/protondrive-sync --local <dir> --remote /my-files/<path> \
  --state-file /tmp/test-state.json --once
```

`--once` runs a single reconcile pass and exits. Always test real changes
against a **throwaway remote folder**, not the user's actual synced data --
create it, test, then clean up:

```
proton-drive filesystem trash "/my-files/_devtest"
proton-drive filesystem empty-trash
```

Before trusting any assumption about the CLI's behavior (flag placement,
exact error text, JSON shape), verify it live rather than going from the
`--help` text or docs alone -- this CLI is young (per the note in the
user's Obsidian vault, `3-Resources/Proton Drive CLI.md`, if available) and
has already been caught disagreeing with its own `--help` output twice
during this plugin's development:

- `-j` must come *after* the subcommand's positional args
  (`filesystem list <path> -j`), not before `filesystem` -- despite the
  general-options section of `--help` reading like a prefix flag.
- `upload`'s `-f replace` and `download`'s `-f remove` are NOT
  interchangeable -- the two directions have different strategy
  vocabularies (upload: `create-new-revision`/`rename`/`replace`/`skip`;
  download: `rename`/`remove`/`skip`). Passing `replace` to `download`
  fails with `Invalid conflict strategy "replace"`.

## Editing the QML (`Service.qml`, `Panel.qml`, `ProtonSyncIcon.qml`)

There is no way to unit-test these in isolation -- they only really run
inside a live `omarchy-shell` process. Two things that *are* available
without a live session:

1. **`qmllint`** (`/usr/lib/qt6/bin/qmllint` if not on `$PATH`) catches real
   syntax errors. It cannot resolve the `qs.Commons`/`qs.Ui` imports
   standalone (Quickshell registers those at runtime, not via a normal QML
   import path), so every Omarchy plugin -- including the first-party ones
   -- produces a wall of `[import]`/`[unqualified]`/`[inheritance-cycle]`/
   `[required]` warnings when linted this way. That's expected noise, not
   a bug. To sanity-check a warning count, lint the real Dropbox plugin
   the same way and compare:
   ```
   qmllint /usr/share/omarchy/shell/plugins/panels/dropbox/Panel.qml
   ```
   Anything qmllint reports as `Error` (not `Warning`) is real and must be
   fixed. Anything in a category *absent* from the Dropbox baseline is
   worth a second look.
2. **Installing it for real** (see below) is the only way to know the UI
   actually renders and behaves. Don't claim a QML change works without
   doing this.

## Installing/testing changes in a live shell

Plugin folders **cannot be symlinks** -- `PluginRegistry.qml` (the actual
shell runtime) refuses to load one, the same check
`omarchy-plugin-validate` runs standalone (confirmed both reject a
symlinked `~/.config/omarchy/plugins/<id>` directory during this plugin's
development). So there's no live-reload-from-a-symlink shortcut; the real
install path is a real copy:

```
omarchy plugin add /path/to/this/repo --enable
```

This does a `git clone` into `~/.config/omarchy/plugins/xqus.protondrive-sync/`,
so after editing this repo you need to either re-run that (after
committing, since it clones a git ref) or manually sync files over:

```
rsync -a --exclude .git ./ ~/.config/omarchy/plugins/xqus.protondrive-sync/
omarchy-shell shell rescanPlugins
```

The second form is faster for iterating and doesn't require committing
first. Saving a file under `~/.config/omarchy/plugins/` is *supposed* to
hot-reload it per Omarchy's own plugin docs, but confirmed during this
plugin's development: that didn't pick up a QML code change here, and
neither did `omarchy-shell shell rescanPlugins` (which only re-syncs
manifest/settings metadata, not the actual QML component -- see
`syncPluginWidgets()` in `/usr/share/omarchy/shell/shell.qml`, which
explicitly skips re-creating a Component when the entry-point URL is
unchanged) nor `omarchy plugin disable` + `enable` (which reloaded nothing
either, since it's the same cached Component by URL). **Only
`omarchy restart shell` reliably picked up a QML source change** in
testing. It briefly restarts the whole bar/panel process -- expect a
flicker, not a crash.

Also confirmed the hard way: **`omarchy plugin disable` followed by
`enable` does not preserve a widget's settings.** It re-adds a bare
`{"id": ...}` bar-layout entry, silently dropping whatever
`localFolder`/`remoteFolder`/etc. had been set before. If you disable/
enable while testing, you will need to re-run `omarchy bar set` for every
key afterward. Prefer `omarchy restart shell` over disable+enable for
both reasons above -- it reloads code AND leaves settings alone.

There is also no settings GUI to speak of yet -- see README.md's
"Configure" section. `omarchy bar set <id> <key> <value>` is the only
current way to set a value, and each call merges into the existing
settings object (confirmed via `setBarWidget` in
`shell/services/PluginRegistry.qml`: `entry[String(key)] = value`, an
in-place mutation, not a replace) -- so the settings loss described above
comes specifically from disable/enable re-adding the entry, not from
`bar set` itself.

To remove it: `omarchy plugin remove xqus.protondrive-sync` (check the
exact subcommand name with `omarchy plugin --help` if it's changed).

## Things already learned the hard way (see SPEC.md "Testing" for the full list)

- Deletion propagation must check the *surviving* side's content hash
  against the last-known sync state before honoring a delete -- otherwise
  a delete-here + edit-there race silently destroys the edit. This was a
  real bug caught during development, not a hypothetical.
- A failed remote listing must abort the whole reconcile pass, never be
  treated as an empty remote -- otherwise a transient CLI error looks like
  "everything was deleted remotely" and the engine starts deleting local
  files. Also a real bug caught during development.
- Directory-existence bookkeeping computed *before* the per-file loop runs
  goes stale if that loop changes what's empty (e.g. deleting the last file
  in a folder). `ensure_path`/`create_folder` return whether they *actually*
  created something so the caller doesn't log a false "created" for an
  idempotent no-op.
- `restart()` originally did `stop(); Qt.callLater(start)`. `Qt.callLater`
  only defers to the next event-loop tick, which runs *before* the
  underlying `QProcess` has actually finished exiting -- so `start()`'s own
  `daemonProcess.running` guard silently no-op'd and a settings change just
  killed the daemon forever instead of restarting it. Fixed by restarting
  from `onExited` instead (`_pendingRestart` flag), which only fires once
  the process is actually gone. Caught live via `setBarWidget` +`debug`,
  not by inspection -- the bug produced no error, just a daemon that never
  came back.
- Relatedly: `stop()` killing the daemon (via `running = false`) surfaces
  in `onExited` as a nonzero/signal exit code, indistinguishable from a
  real crash unless you track that the stop was intentional
  (`_intentionalStop`). Without that flag, every ordinary settings-change
  restart showed a scary "exited unexpectedly" error in the panel for
  completely normal behavior.
- `Service.qml`'s `onLocalFolderChanged`/`onRemoteFolderChanged`/etc. only
  called `restart()`, guarded by `if (running)`. That covers a daemon
  that's already going picking up a settings change, but not the far more
  common first-run case: the plugin loads with nothing configured yet
  (`ready` false, nothing started), and settings arrive afterward via
  `omarchy bar set`. Nothing reacted to `ready` flipping true in that case
  until `onReadyChanged: if (ready && !daemonProcess.running) start()` was
  added. Caught live: the panel sat on "stopped" indefinitely after
  configuring both folders, even though a manual `refresh` IPC call proved
  CLI/auth/config were all fine.
