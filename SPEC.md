# SPEC: omarchy-protondrive-sync

Two-way sync between exactly one local folder and one Proton Drive folder,
built on the official `proton-drive` CLI, shipped as an Omarchy bar-widget
plugin. Not affiliated with Proton or Omarchy/Basecamp.

## Goals

- Local changes sync to Proton Drive as close to instantly as inotify allows.
- Remote changes (edited elsewhere -- another machine, the web UI) are picked
  up on a configurable poll interval.
- Runs entirely inside the user's own graphical session, as a subprocess the
  Omarchy shell (`omarchy-shell`, a Quickshell process) supervises. No
  systemd unit, no root, no daemon outside the session.
- Never silently destroy data. When in doubt (a conflicting edit, a failed
  listing), do less rather than guess wrong.

## Non-goals

- Multi-folder sync. One local folder, one remote folder, by design -- this
  is meant to be simple and auditable, not a general sync client.
- Syncing while logged out. The engine lives inside the shell process; it
  stops when your session ends, same as Dropbox's own daemon would.
- `/devices` ("Computers" in the Proton Drive UI). See "Why not Computers"
  below.
- True server-side rename/move detection. See "Known limitations."

## Why not Computers (`/devices`)

Checked live against the CLI (`proton-drive filesystem list -j /devices`):
`/devices` is an index of *registered desktop-app devices*
(`{"type":"Windows","name":{"value":"..."}, ...}`), each mirroring whatever
folder that specific machine's native Proton Drive app was configured to
back up. It is:

- Not a folder you can create or address directly --
  `proton-drive filesystem info -j /devices` fails with "Device not found".
- Populated only by Proton's own Windows/Mac desktop client agent (one-way,
  device -> cloud). There is no CLI path to register a new device or write
  into an existing one.

So it's the wrong target for a two-way sync tool by construction, not just
by convention. `remoteFolder` is validated to be under `/my-files` at
startup; the daemon refuses to run otherwise.

## Architecture

```
manifest.json        Plugin metadata + settings schema (Omarchy plugin format)
Panel.qml            Bar icon + dropdown panel (entry point, kind: bar-widget)
Service.qml          Settings, daemon process lifecycle, event parsing
ProtonSyncIcon.qml    Bar icon glyph (generic transfer arrows, not a Proton mark)
Model.js             Activity-log formatting helpers for the panel
bin/protondrive-sync  The actual sync engine (Python 3, stdlib only)
```

`Service.qml` runs inside `omarchy-shell`'s single long-lived Quickshell
process (this is how *every* Omarchy bar-widget plugin works, not something
special to this one) and spawns `bin/protondrive-sync` as a managed
subprocess via `Quickshell.Io.Process`. The daemon's stdout is
line-delimited JSON that `Service.qml` parses to drive the UI; its stdin
takes plain-text commands (`pause`, `resume`, `sync-now`, `quit`).

## Daemon protocol

One JSON object per line on stdout:

| `type`     | Fields                                              | Meaning |
|------------|------------------------------------------------------|---------|
| `ready`    | `localFolder`, `remoteFolder`                        | Daemon started, about to run its first reconcile |
| `state`    | `paused`, `trackedFiles`, `localFolder`, `remoteFolder` | Emitted after every reconcile pass |
| `activity` | `action`, `path`, `detail?`                          | One sync action. `action` is one of `uploaded`, `downloaded`, `deleted-local`, `deleted-remote`, `created-local-dir`, `created-remote-dir`, `conflict`, `error` |
| `error`    | `message`                                            | A whole reconcile pass was aborted (e.g. remote listing failed) |

Every event also carries `ts` (Unix epoch seconds).

Stdin commands, one per line, no arguments: `pause`, `resume`, `sync-now`,
`quit`.

## Sync algorithm

Each reconcile pass (triggered by a debounced local filesystem event, the
poll timer, or `sync-now`):

1. `local_scan()` walks the local folder: relpath -> `{size, sha1}` (real
   SHA-1 of file content, via `hashlib`).
2. `remote_scan()` walks the remote folder one `filesystem list` call per
   directory (list is single-level, like `ls`) and also collects every
   folder whose entire subtree has no files (`empty_dirs`). This raises
   instead of returning a partial tree on any listing failure -- see
   "Known limitations" for why that distinction matters.
3. For each relpath present locally, remotely, or in the on-disk sync state
   (`~/.local/state/omarchy/protondrive-sync/state.json`), diff against the
   last known `{localSha1, remoteSha1}` for that path:
   - New on one side only, never tracked before -> upload/download it.
   - Changed on one side only since last sync -> upload/download it.
   - Changed on **both** sides with different content -> conflict (see
     below).
   - Missing from one side, previously tracked -> a deletion. Only
     propagated if the *other* side is unchanged since the last sync (see
     "Deletion safety").
4. Empty directories are mirrored separately (created on whichever side is
   missing them) and are **never deleted** by this engine, regardless of
   settings -- see "Known limitations."
5. State is written back to disk after every pass (atomic rename via a
   temp file).

Every `proton-drive` invocation from the daemon passes `-j` (placed *after*
the subcommand's own arguments -- confirmed against the live CLI; placing
it before `filesystem` fails with "Command not found: -j filesystem",
which contradicts the `-h` help text's apparent ordering).

### Content identity

Proton Drive's `filesystem list -j` / `info -j` output includes
`activeRevision.claimedDigests.sha1` -- the uploader's own claimed SHA-1 of
the file content (`"sha1Verified": false`; it's client-reported, not
server-verified, but consistent enough to diff against). This is what
lets the engine tell "genuinely different content" apart from "same
content, different mtime," which a naive size+mtime heuristic can't do
reliably. Confirmed live by uploading a known file and inspecting the
listing.

### Conflict resolution

The `conflictStrategy` setting has three modes, mapped to the daemon's
`--conflict-strategy` flag:

- **`rename`** (default, "Keep both"): move the local copy aside to
  `name (local conflict copy).ext`, upload it under that name, then
  download the remote version to the original path. Nothing is lost.
- **`local`**: upload the local copy over the remote one
  (`-f replace` on upload).
- **`remote`**: download the remote copy over the local one
  (`-f remove` on download -- see the strategy-vocabulary note below).

### Deletion safety

A deletion is only ever propagated (trashing the remote file, or removing
the local one) if the *surviving* side's content hash still matches what
was recorded at the last sync. If it doesn't -- i.e. the file was edited on
the side that *didn't* delete it, sometime between the last sync and now --
the engine treats it as a conflict instead of honoring the delete, and
restores/keeps the edited version. `local`/`remote` conflict-strategy
settings still take a side deterministically in this case (`local` always
honors a local delete even over a remote edit; `remote` is symmetric); the
default `rename` strategy always preserves the edit. This was caught by an
end-to-end test during development (see git history) that initially
deleted a remotely-edited file outright before this check was added.

### Upload vs. download strategy vocabularies differ

Confirmed against `proton-drive filesystem upload --help` /
`download --help`: `-f` (file-conflict-strategy) accepts different values
per direction. Upload: `create-new-revision`, `rename`, `replace`, `skip`.
Download: `rename`, `remove`, `skip` -- **no `replace`**. An early version of
this daemon passed `replace` to `download` and every remote-wins/rename
download failed with `Invalid conflict strategy "replace"`; fixed to use
`remove`, which is download's equivalent "overwrite the local copy"
semantics. `-d` (folder-conflict-strategy) is irrelevant here since every
upload/download targets a single file, never a folder.

## Settings

| Key | Type | Default | Notes |
|---|---|---|---|
| `localFolder` | `path` | *(empty)* | Required. Created if missing. |
| `remoteFolder` | `string` | `/my-files/Sync` | Required. Must be under `/my-files`. Created if missing. |
| `pollIntervalSec` | `integer` | `120` | 30-3600. Local changes don't wait for this -- inotify triggers a reconcile immediately (debounced ~1.5s). |
| `conflictStrategy` | `enum` | `Keep both (rename)` | See "Conflict resolution." |

## Known limitations

- **Session-bound.** Sync only runs while the graphical session (and its
  `omarchy-shell` process) is alive. This is a deliberate scope choice, not
  an oversight -- see "Non-goals."
- **No rename/move detection.** Moving or renaming a file (or a non-empty
  folder) is observed as a delete at the old path plus a create at the new
  path -- correct end state, but it re-uploads/re-downloads full content
  instead of a cheap server-side `filesystem move`/`rename`, and does so
  one file at a time, which is slow for a large renamed folder. A future
  version could detect this via matching SHA-1 between a disappeared and
  appeared path within one reconcile pass, but that heuristic risks
  misfiring on duplicate-content files and was deliberately left out of
  v1 rather than shipped half-verified. Combined with the next point,
  renaming a non-empty folder also leaves the now-empty old folder behind
  as an orphan on the *other* side once its files are gone, since nothing
  proactively removes it. To rename a folder without the re-upload/
  re-download cost or the orphan, do it by hand instead -- see "Manual
  folder surgery" below. Done this way for real once already, renaming a
  synced Obsidian vault folder with zero re-upload/re-download.

### Manual folder surgery

Renaming or removing a synced folder outside the daemon's own logic
(directly with `mv`/`rmdir`/`proton-drive filesystem rename` on one or
both sides) needs the daemon fully halted first, not just paused. `pause`
(over stdin, or the panel's toggle) only blocks a *new* reconcile cycle
from starting -- a cycle already in progress keeps running to completion,
which can take a while (each CLI call is a multi-second round trip), and
the IPC call returns "ok" the instant it writes to the daemon's stdin,
*not* once the daemon has actually idled. Trusting that as confirmation
was tried for real and raced a manual fix: the in-flight cycle finished
using pre-fix data and recreated the very thing that had just been
removed.

The reliable sequence:
1. `stop` over IPC (kills the process outright -- deterministic, nothing
   left running to race).
2. Poll `debug`'s `running` field until it's `false`.
3. Make the change on both sides (`mv`/`rmdir` locally,
   `filesystem rename`/`trash` remotely as needed). If renaming, also
   patch the renamed prefix into `state.json`'s keys so the daemon
   recognizes the files as already synced instead of re-transferring
   everything.
4. `start` over IPC (or `refresh`, which checks CLI/auth/config first and
   starts if ready).

One more thing worth knowing even with this sequence: Proton Drive's own
`trash` doesn't seem to be immediately consistent -- a `filesystem list`
moments after a `trash` can still briefly show the trashed item. If
`start` fires right after a `trash` in step 3, the daemon's first
reconcile pass can occasionally still observe the stale listing and
recreate the directory it was just told is gone, correcting itself on the
next pass once the trash has propagated. Leaving a few seconds between
step 3 and step 4 avoids this.
- **Empty directories are mirrored but never deleted**, even if removed on
  the other side. An empty-folder-existence check was judged too blunt a
  signal to safely drive a recursive delete; the failure mode is a stray
  empty folder, never lost data.
- **Symlinks are skipped**, both as files and as directories to descend
  into, on the local side.
- **No true atomicity.** A crash mid-reconcile can leave one file synced
  and its sibling not; the next reconcile pass just picks up where it left
  off (state is only written after a successful action), so this is a
  liveness/ordering limitation, not a correctness one.
- **SHA-1 is client-claimed, not server-verified** (`sha1Verified: false`
  in Proton's own metadata). Good enough for diffing; not a cryptographic
  integrity guarantee.
- **Large trees**: every reconcile pass does a full local walk and a full
  recursive remote listing (one `filesystem list` call per remote
  directory). Fine for a "sync one project folder" use case; not designed
  for huge trees or very short poll intervals -- see Proton's own guidance
  against generating unusually high API traffic.

## Testing

No live-shell test harness ships with this repo (there isn't one for
Omarchy plugins in general). What was actually verified during
development, against a real Proton Drive account and a throwaway remote
test folder (created and trashed+emptied afterward each time):

- Initial upload of new local files and an empty directory.
- Re-upload of a locally-modified file (correct create-new-revision, not a
  spurious delete).
- No-op reconcile producing zero activity when nothing changed.
- Download of a remote-only new file.
- Empty remote directory mirroring to local.
- Plain local deletion propagating to a remote trash.
- The delete-vs-remote-edit conflict path: file deleted locally while
  edited remotely between syncs correctly triggers a `conflict` event and
  restores the remote edit, rather than deleting it.
- A false-positive fix: deleting the last file in a folder must not log a
  spurious `created-remote-dir` for a folder that already existed (caught
  because `remote_dirs` is snapshotted before the file loop runs and can
  be stale by the time the directory-reconcile step reads it;
  `ensure_path`/`create_folder` now report whether they *actually* created
  something before the daemon logs it as new).

The QML files (`Panel.qml`, `Service.qml`, `ProtonSyncIcon.qml`) were
checked with `qmllint` and produce the same warning signature (categories
and rough count) as the real, shipped `omarchy-dropbox` plugin's own files
linted the same way outside the full Quickshell runtime -- `qs.Commons`/
`qs.Ui` can't resolve standalone, which cascades into "unqualified access"
and "inheritance cycle" noise for *any* Omarchy plugin linted this way, not
just this one. Zero `Error`-severity output. That parity is the ceiling of
what's verifiable without actually enabling the plugin in a live
`omarchy-shell` session -- that step is still owed before calling the UI
side done. See CLAUDE.md for how to do that.
