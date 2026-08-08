# Working on the Quickshell shell

Notes for anyone changing `roles/desktop/files/quickshell/` — how to test it,
the traps that cost real time to find, and the things already decided against.

Distilled from `docs/qml-improvement-plan.md`, a 43-package refactor completed
2026-08-08 (42 done, 1 measured and declined). That plan is in git history if
you need the reasoning behind a particular change; `git log --oneline
-- roles/desktop/files/quickshell` is usually faster.

## Ground rules

- The Ansible role is the source of truth. `~/.config/quickshell` is
  disposable — never edit it expecting the change to survive.
- Match the surrounding style. **Do not run qmlformat** (see "Already decided
  against").
- Theme values come from `Common/Theme.qml`. Add a token rather than a literal
  when the value expresses a design role.
- New shared components: PascalCase file in the directory that owns the
  concern, and **add it to that directory's `qmldir`** — a directory carrying a
  `qmldir` is no longer implicitly scanned, so an unlisted type fails at
  runtime as "X is not a type". `tests/quickshell/qmldir.test.cjs` enforces it.
- Pure logic goes in a `.js` module in `Common/` with a Node test in
  `tests/quickshell/` — that suite runs in under a second without Qt.
- `tests/run` is the gate: Node tests plus `tests/qml-lint`. `update` runs it
  before deploying, and the Ansible role lints the tree before copying it.

## Testing without a GUI

```sh
# Deploy a throwaway copy without running ansible (this also reloads the shell):
rsync -a --delete roles/desktop/files/quickshell/ ~/.config/quickshell/

# Watch it load:
journalctl --user -u quickshell.service -n 50 --no-pager

# Drive popouts and settings:
qs ipc call popouts toggle t3code      # or: audio, control, wifi, notifications, …
qs ipc call settings open notifications

# Screenshot (-c includes the mouse cursor):
grim -g "1020,50 400x420" /tmp/shot.png
```

Do not commit while the live config dir holds an unsynced throwaway copy.
`rsync -a --delete` from the repo is the one-command way back.

### Techniques that work here

- **`console.log` never reaches stdout or the qslog**, under any
  `QT_LOGGING_RULES`. `console.warn` *does* reach
  `journalctl --user -u quickshell.service`. A harness that must report a value
  writes a file:
  `Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" > \"$2\"", "sh", text, path])`.
- **Offscreen harness**: `qs -p <file.qml>` runs a single file as its own
  instance. Point `HOME` at a scratch dir holding a *copy* of
  `~/.local/state/quickshell/shell-settings.json` so the probe cannot write the
  real one. A root `ShellRoot` + `PanelWindow` gives real focus behaviour, and
  `activeFocus` resolves without `WlrKeyboardFocus.OnDemand`, so the probe need
  not steal the keyboard.
- **Triggering internal code paths live**: add a throwaway `IpcHandler` target
  to the *deployed* `shell.qml`. Cheaper than staging the real event, and it
  exercises the shipped code rather than a copy.
- **Keyboard**: `wtype -k Tab` / `wtype -k space` sends real key events, which
  is how focus order and activation get tested end to end.
- **Pointer**: `hyprctl dispatch 'hl.dsp.cursor.move({ x = …, y = … })'` takes
  absolute screen-logical coordinates. Call it in a loop until
  `hyprctl cursorpos` agrees — the first call after the pointer has been
  elsewhere can land short. With `grim -c` this makes cursor shape and hover
  state observable.
- **Multi-monitor without hardware**: `hyprctl output create headless`, then
  read the name back (`HEADLESS-1`). Focus may refuse to move to an empty
  output, so to exercise a bar's `visible` binding pin `barEnabled` to that
  output in the deployed `shell.qml`. `hyprctl layers -j` shows which output
  each `qs-*` surface is on.
- **This Hyprland speaks a Lua dispatch dialect** —
  `hyprctl dispatch 'hl.dsp.focus({ monitor = "<name>" })'`. Plain
  `focusmonitor` / `movecursor` do not exist.
- **Prove the probe has teeth.** Reconstruct the pre-fix code in the throwaway
  copy and confirm the probe fails. A check that cannot fail has not verified
  anything.

### Pixel diffs

`compare -metric AE` is **not** a pixel count in this ImageMagick 7 — it
returned 6.7e7 for a 120×80 crop. Use:

```sh
magick a.png b.png -compose difference -composite -colorspace Gray \
  -threshold 8% -format '%[fx:mean*w*h]' info:
```

and always check it against a deliberately broken variant before believing a
zero. Then subtract the noise floor: capture the *same* tree twice and diff
that too. Live values move constantly — the control centre differs from itself
by ~134k px eight seconds apart (CPU/RAM/temp), the battery popover by its time
estimate, several settings pages by their clock previews. A panel's outer edge
blends with whatever is behind it, so `-shave 12x0` before comparing.

## Traps

- **An unqualified reference to another singleton's property lints clean and
  throws at runtime.** Inside a Quickshell `Singleton`, qmllint cannot resolve
  the scope, so `threadMap` where `T3Threads.threadMap` was meant produces no
  warning — and every call throws `ReferenceError`, invisibly except in the
  journal. This shipped three times during the T3 split (WP5.1, WP5.2, and
  settle/snooze after Phase 5). `tests/quickshell/t3-singleton-scope.test.cjs`
  now enforces a watchlist; extend the list when a new cross-singleton name
  appears.
- **In-place mutation never re-evaluates a binding.** Mutating an object or
  array in place is invisible to QML; reassigning it notifies. Both behaviours
  are useful — a memo cache wants the former, an invalidation wants the latter
  — but mixing them up silently breaks either the update or the performance.
- **A counter written from inside a binding can feed back into the binding
  graph.** Instrumenting `iconSource` with `property int` counters drove the
  shell to 171% CPU and 6.6 GB and filled `/run/user/1000` with a 3.1 GB log,
  after which the restarted instance could not create its IPC socket. Count in
  a `.pragma library` script instead — module scope is not a QML property, so
  nothing can capture it. Note such scripts are **cached past a hot reload**;
  changing one needs `systemctl --user restart quickshell.service`.
- **A `.js` imported without `.pragma library` gets a separate copy per
  importing component.** Fine for stateless helpers, useless for shared state.
- **`readonly property int` silently truncates.** Card heights are text metrics
  plus padding and land on fractions; an `int` cost a pixel and shifted
  everything below it. Use `real` for anything derived from text.
- **Quickshell does not watch `qmldir` files.** A qmldir edit needs a `.qml`
  touch before it reloads.
- **`Loader.active` defaults to true**, so `onActiveChanged` fires only for
  slots that evaluate false. Absence of `active=true` lines is a logging
  artifact, not a gate that failed.
- **`signal-handler-parameters` cannot be satisfied** for
  `Process.exited(int, QProcess::ExitStatus)` — the enum is not registered with
  QML. The apparent fix (`function onExited(exitCode) {}`) silences qmllint
  *and* stops Quickshell calling the handler. Disabled in `.qmllint.ini` with
  that reason.
- **Quickshell emits no `exited` at all when a binary cannot be launched** —
  only the falling edge of `running`. Anything reading exit status must handle
  a never-started process; `Common/ProcHelpers.js` has the sentinel.
- **Popout lifetime**: `IslandPopout` latches the Control Center, so it is
  constructed once and never destroyed. Anything refcounted must key on
  `visible` via `Common/Claim.qml`, not on construction or destruction.
- **Idle CPU is not measurable with `top` on a machine in use** — sampling the
  live shell gave 0.12%–6.44% across windows of *identical* code. Instrument
  both trees and count timer firings in the journal instead.
- **A pixel-identical bar is not a working bar.** WP4.3 shipped a module
  registration regression that looked perfect in a screenshot. `tests/run`
  carries a duplicate-handler check because qmllint has no opinion on that and
  the failure mode is a shell silently running stale code.

## Layout

- `Common/` — singletons (services, settings, theme), pure `.js` helpers, and
  the shared controls both other directories draw (`Toggle`, `HSlider`,
  `NotifCard`, `NotifIcon`, `NotifActions`).
- `Bar/` — the menubar, the popout host, and 13 modules under `Bar/Modules/`
  sharing a `BarModule` base.
- `Popovers/` — panel contents, all built on `PopoutPanel` / `Surface`.
- `Settings/` — the settings window; rows build on `Settings/SettingsRow.qml`.
- `tests/quickshell/` — Node tests. `shell.cjs` locates the source tree;
  `load("X.js")` pulls a helper out of `Common/`.

Two conventions worth knowing: a settings row that names a `settingKey` gets
its value, dirty state, commit and undo from the base, and per-surface styling
travels as a single `var` object (`Theme.switchRow`, a card's `style`) rather
than as a dozen properties.

## Already decided against — do not pick these up

- **qmlformat one-shot reformat**: most files would churn and the tool fights
  the deliberate hand-wrapped style. Revisit only as a dedicated commit with a
  tuned `.qmlformat.ini`.
- **Automatic shell restart on deploy**: Quickshell hot-reloads; a forced
  restart is more disruptive than the problem it solves.
- **The remaining perf items** (toast countdown timer, memoising
  `Notifs.iconSource`, a `Clock` singleton, a launcher token index): measured
  2026-08-08 and declined. Two premises were already false in the code, and the
  third does not reproduce — with eight notifications the icon lookups go
  8 → 24 → 96 and then flat, identically with and without a memo. Do not reopen
  without new numbers.
- **Merging the remaining list rows into one `ListRow`**: they differ more than
  the shared action buttons did. Reopen only if a fifth consumer appears.
- **`Theme.fontSans` → `Theme.fontMenu` in the launcher and toasts**: those are
  overlay surfaces, not menubar chrome, so they follow the general UI face and
  do not track the menu font setting. `typography.test.cjs` enforces the split.

Still open, if anyone wants it: **QML-level tests via `qmltestrunner-qt6`** —
installed and viable now that the T3 singletons are small enough to test
against a stub socket. First targets would be the Settings load/merge/save
cycle and the `T3Connection` state machine.
