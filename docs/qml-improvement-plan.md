# Quickshell QML improvement plan

Multi-agent implementation plan for the shell at `roles/desktop/files/quickshell/`
(74 QML files, ~20.4k lines, plus 4 JS helper modules and 7 Node test files).
Produced 2026-08-07 from a four-way research sweep (architecture, duplication,
performance, tooling/robustness).

## How to use this document

- Work is split into **work packages (WPs)**. Each WP is sized for one agent in
  one session and ends in one commit (repo convention:
  `feat(quickshell): …` / `fix(quickshell): …` / `perf(quickshell): …` /
  `chore(quickshell): …`).
- **Respect phase order.** Phase 0 must be fully complete before anything else
  starts — it builds the safety net every later WP relies on. Within a phase,
  WPs marked ∥ are parallelizable *unless they share a file in "Files touched"*;
  two agents must never edit the same file concurrently. `Bar/Bar.qml` and
  `Common/T3Code.qml` are the high-contention files — WPs touching them are
  serialized explicitly.
- **Every WP finishes with:** `tests/run` passing (exists after WP0.1), plus the
  WP's own acceptance checks. For UI-affecting WPs, validate against a live
  deploy copy (see "Runtime validation" below).
- Mark progress by checking the box in the WP header and appending a one-line
  note (commit hash, deviations). If you discover the plan is wrong somewhere,
  fix the plan file in the same commit and say so in the note.
- Line numbers below were accurate at commit `e36f980`. Re-locate by symbol
  name if the file has since moved — do not trust raw line numbers blindly.

### Runtime validation

Headless/live checks that have worked well in this repo:

```sh
# Deploy a throwaway copy without running ansible:
rsync -a --delete roles/desktop/files/quickshell/ ~/.config/quickshell/

# Reload is automatic (Quickshell watches files) — check the journal:
journalctl --user -u quickshell.service -n 50 --no-pager

# Drive popouts headlessly:
qs ipc call popouts toggle t3code      # or: audio, control, settings, …
qs ipc call settings toggle

# Screenshot for visual checks:
grim -o "$(hyprctl monitors -j | jq -r '.[0].name')" /tmp/shot.png
```

Do not commit while the live config dir contains an unsynced throwaway copy —
the Ansible role is the source of truth; `~/.config/quickshell` is disposable.
`rsync -a --delete` from the repo is the one-command way back, and it also
reloads the shell.

**Techniques the Phase 1 verification pass established** (all cheap, all
non-destructive — prefer these to the disruptive checks some WPs still name):

- **`console.log` never reaches stdout or the qslog**, with any
  `QT_LOGGING_RULES`. A harness that needs to report must write a file:
  `Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" > \"$2\"", "sh", text, path])`.
  `console.warn` *does* reach `journalctl --user -u quickshell.service`, which
  is what makes temporary instrumentation the most reliable probe.
- **Offscreen component harness**: `qs -p <file.qml>` runs any single file as
  its own instance. Point `HOME` at a scratch dir holding a *copy* of
  `~/.local/state/quickshell/shell-settings.json` so the probe cannot write the
  real one. A root `ShellRoot` + `PanelWindow` is enough to get real focus
  behaviour; `activeFocus` resolves without `WlrKeyboardFocus.OnDemand`, so a
  probe need not steal the user's keyboard.
- **Prove the probe has teeth**: reconstruct the pre-fix code in the throwaway
  copy and confirm the probe fails. Several WP notes claim a fix is
  load-bearing; this is how that claim gets checked.
- **Multi-monitor without hardware**: `hyprctl output create headless`, then
  read the name back (`HEADLESS-1`). This Hyprland speaks a **Lua dispatch
  dialect** — `hyprctl dispatch 'hl.dsp.focus({ monitor = "<name>" })'`; plain
  `focusmonitor`/`movecursor` do not exist. Focus may refuse to move to an
  empty output, so the reliable way to exercise a bar's `visible` binding is to
  pin `barEnabled` to the output in the deployed `shell.qml`.
  `hyprctl layers -j` shows which output each `qs-*` surface is mapped to.
- **Triggering shell-internal code paths live**: add a throwaway `IpcHandler`
  target to the deployed `shell.qml` exposing the call and a `stats()` string.
  Far cheaper than staging the real-world event, and it exercises the shipped
  code rather than a copy.
- **Reading `Loader.active` instrumentation**: `active` defaults to **true**,
  so `onActiveChanged` fires only for slots that evaluate false. Absence of
  `active=true` lines is a logging artifact, not a gate that failed to open.

### Style ground rules for all agents

- Match the existing code style. Do **not** run qmlformat (deliberately
  deferred, see "Explicitly deferred" at the end).
- New shared components follow the existing pattern: PascalCase file in the
  directory that owns the concern; add to that directory's `qmldir` when one
  exists (after WP3.2: always).
- Theme values come from `Common/Theme.qml` tokens; add a token rather than a
  literal when a value expresses a design role.
- Pure logic goes in a `.js` module beside `Common/SettingsHelpers.js` with a
  Node test in `Common/tests/` — that harness is fast (whole suite ~360ms) and
  runs without Qt.

---

## Phase 0 — Safety net (sequential; nothing else starts until done)

### [x] WP0.1 Test runner aggregator, wired into verify and update

> Done. Deviation: `node --test <dir>` does not discover these files (the
> runner tries to `require` the directory), so `tests/run` expands
> `Common/tests/*.test.cjs` itself. `verify` runs both stages and reports
> rather than short-circuiting. `update`'s gate sits immediately before
> `ansible-playbook` so a package update still lands when the shell is broken.

**Files touched:** `tests/run` (new), `verify`, `update`
**Depends on:** nothing

The repo has 106 passing unit tests in
`roles/desktop/files/quickshell/Common/tests/*.test.cjs` that nothing executes,
and `tests/qml-lint` that nothing invokes.

1. Create `tests/run` (bash, executable): runs
   `node --test roles/desktop/files/quickshell/Common/tests/` then
   `tests/qml-lint`; exits nonzero if either fails; prints a one-line summary
   per stage.
2. Root `verify` (currently hard-execs `tests/verify-xps` at line 4): run
   `tests/run` first, then `verify-xps`.
3. `update` (deploy driver, `ansible-playbook` call at line ~255): run
   `tests/run` as a gate *before* the playbook; abort deploy on failure with a
   clear message. Support `--skip-tests` escape hatch.

**Accept:** `tests/run` exits 0 today; `update --help`/dry path shows the gate;
breaking a `.test.cjs` assertion makes both `verify` and `update` fail.

### [x] WP0.2 qml-lint: batch mode, portable paths, qmllint.ini, promoted categories

> Done — 9.9s → 2.4s, 468 → 439 warnings, one line of output on success
> (`--verbose` for the full report). Deviations:
> - `.qmllint.ini` lists only the deviations from qmllint's own defaults
>   instead of the 79-line `--write-defaults` dump, so a Qt upgrade can still
>   introduce new checks and the file states what this repo actually decided.
> - The pass/fail decision is qmllint's exit status (categories at `error`
>   level in the ini), not `--json` parsing. Category counts are still grepped
>   from the text output, but only for the summary line.
> - **`signal-handler-parameters` cannot be fixed here.** All 7 are
>   `Process.exited(int, QProcess::ExitStatus)`; the enum is not registered
>   with QML, so every `onExited` binding is flagged no matter how it is
>   written. Disabled in the ini with that reason recorded. Watch out for the
>   apparent fix: `function onExited(exitCode) {}` silences qmllint because it
>   is no longer recognized as a signal handler — and Quickshell stops calling
>   it too (verified at runtime against a live instance, alongside `Timer`).
>   WP0.4's promotion list drops this category.

**Files touched:** `tests/qml-lint`, `roles/desktop/files/quickshell/.qmllint.ini` (new)
**Depends on:** WP0.1

Current script spawns qmllint once per file (9.9s vs 2.2s batched), greps
human-readable output for `^Error` (brittle, discards 462 warnings), and
hardcodes `-I /usr/lib64/qt6/qml`.

1. Batch: single qmllint invocation with all 74 files.
2. Replace the output grep with `--json` output (or exit-code handling) so the
   check survives Qt version changes.
3. Replace the hardcoded import path with
   `$(qtpaths6 --query QT_INSTALL_QML)` (fallback to the current literal).
4. Generate `.qmllint.ini` (`qmllint --write-defaults`), then tune:
   - `disable` for Quickshell-inherent false positives: `unresolved-type` /
     `uncreatable-type` (PanelWindow, BluetoothAdapter, etc.).
   - Keep `unqualified` as warning for now — WP0.3 clears it, then flip to
     error in WP0.4.
5. Fix the small warning categories outright in this WP (they are few):
   6 `[unused-imports]` (e.g. `Bar/Bar.qml:5` Quickshell.Hyprland,
   `Bar/Bar.qml:11` Quickshell.Widgets), 7 `[signal-handler-parameters]`,
   1 `[comma]`.

**Accept:** `tests/qml-lint` runs in under ~4s, exits 0, and a deliberately
introduced syntax error is caught. Warning count drops accordingly.

### [x] WP0.3 `pragma ComponentBehavior: Bound` everywhere it is needed

> Done — 421 `[unqualified]` → 0, in one commit rather than batches of five
> (the pragma landed in all 28 files at once and qmllint then named every site
> that needed follow-up work, which was faster and no riskier). Notes:
> - The pragma is load-bearing, not cosmetic: a probe against a live Quickshell
>   confirmed a delegate that reads `modelData` without declaring it required
>   silently produces *nothing* under the pragma — and qmllint flags exactly
>   those sites. Zero `[unqualified]` therefore means no broken delegate.
> - `Bar/Workspaces.qml` needed no pragma, only ids; its `parent.parent.focused`
>   chains became `slot.focused`, which also cleared 4 `missing-property`.
> - Six delegates gained ids (`slot`, `dev`, `resultRow`, `sink`, `day`, `net`)
>   so children could qualify against them.
> - Three sites are false positives with inline `// qmllint disable unqualified`
>   and the reason at the site: `PanelWindow.margins` (×2) and ids declared
>   under `FileView.adapter` (`Common/Usage.qml`), whose type qmllint cannot
>   resolve. Runtime resolution of both was verified against a live instance.
> - `missing-property` 18 → 14; still a warning, per WP0.4.

**Files touched:** the 28 files qmllint flags (worst: `Settings/ModuleDetailView.qml`
(104 unqualified warnings), `Settings/ModulesPage.qml` (49), `LauncherView.qml`
(22), `Popovers/T3RequestCard.qml`, `T3CodePopover.qml`, `BluetoothPopover.qml`
(19 each), `Settings/FolderDialog.qml`, `Popovers/T3Composer.qml` (18 each))
**Depends on:** WP0.2

Zero of 74 files use the pragma. Unbound outer-id capture inside delegates is a
real stale-binding risk, and these account for the bulk of the 421
`[unqualified]` warnings.

1. Add the pragma file by file; qualify delegate accesses with
   `required property` declarations / explicit ids as needed. **This changes
   delegate scoping semantics — test each file's UI after converting.**
2. Work in batches of ~5 files per commit if preferred; keep `tests/run` green
   throughout.

**Accept:** qmllint reports 0 `[unqualified]` warnings; launcher search,
settings module detail view, T3 pages, and Bluetooth popover all still work in
a live deploy copy.

### [x] WP0.4 Flip lint to warnings-as-errors for the cleared categories

> Done. Each of the three promoted categories was probed by introducing a
> violation and confirming `tests/qml-lint` exits nonzero and names it first.
> `missing-property` stays a warning at 14.

**Files touched:** `tests/qml-lint`, `.qmllint.ini`
**Depends on:** WP0.3

Promote `unqualified`, `unused-imports`, `comma` to errors in `.qmllint.ini`.
Leave `missing-property` as warning (18 remaining are `Loader.item`
duck-typing — addressed structurally in WP4.2/WP6). `signal-handler-parameters`
is not in this list: WP0.2 established it is an upstream type-exposure gap and
disabled it.

**Accept:** an introduced unqualified access fails `tests/run`.

### [x] WP0.5 Settings-corruption safety

> Done. `parse()` now returns `{status, value}` with `status` in
> `empty | ok | corrupt`; only `empty` counts as a first run. Notes:
> - The backup is triggered *before* `applyLoaded`'s unchanged-settings early
>   return — otherwise a corrupt file whose defaults match the running state
>   slips past unprotected. The new test asserts that ordering.
> - `corruptBackupPending` gates both `scheduleSave()` and `saveNow()`, and
>   deliberately stays set if the `mv` fails: saving then would destroy the
>   file we could not copy. The user is told so via `announcement`.
> - Valid JSON that is not a settings object (`42`, `[]`, `null`) is corrupt,
>   not absent. The old code let `[]` through as an object.
> - Verified live: truncating the real `shell-settings.json` mid-object
>   produced `shell-settings.json.corrupt-<epoch>` byte-identical to the
>   damaged file, the shell fell back to defaults, and nothing overwrote it.
> - **Follow-up for WP1.2:** `announcement` reaches the user only as an
>   `Accessible.AlertMessage` inside the settings window, so someone who never
>   opens Settings sees nothing. Route it through `Notifs.send()` once that
>   helper exists.

**Files touched:** `Common/SettingsHelpers.js`, `Common/Settings.qml`,
`Common/tests/settings-helpers.test.cjs`
**Depends on:** WP0.1

Bug: `SettingsHelpers.parse()` (line ~426) returns `null` for *unparseable*
JSON, indistinguishable from *absent*; `Settings.qml` (applyLoaded, ~line
265–315) then treats it as first run and the next `scheduleSave()` overwrites
the user's recoverable file with defaults.

1. `parse(text)` → return a tagged result (e.g. `{ok, value}` or a distinct
   sentinel for "unparseable" vs "empty/absent").
2. On unparseable: before any save can run, rename the on-disk file to
   `shell-settings.json.corrupt-<epoch>` (Process `mv` or FileView write),
   surface the existing `announcement` mechanism ("settings file was corrupt;
   backed up and reset"), and only then proceed with defaults.
3. Node tests: corrupt input preserves original bytes path; empty input still
   means first run; valid input unchanged.

**Accept:** new tests pass; manually corrupting a deployed
`shell-settings.json` and reloading produces the backup file and the
announcement, not silent data loss.

### [x] WP0.6 Deploy-time validation in the Ansible role

> Done. Deviation: the check is split into a `command` with
> `failed_when: false` plus a `fail` task, because the repo's compact stdout
> callback reports a failed `command` as bare "non-zero return code" and drops
> the findings; routing them through `msg` puts the actual syntax error on
> screen. Tagged `quickshell-lint` (so `--skip-tags quickshell-lint` bypasses
> only the check) and `check_mode: false` so `--check` still validates.
> Verified: a broken QML file aborts with `changed 0` and nothing reaches
> `~/.config/quickshell`; a normal run is unchanged and idempotent.

**Files touched:** `roles/desktop/tasks/main.yml`, possibly
`roles/desktop/handlers/main.yml`
**Depends on:** WP0.2

The role does a bare recursive `copy:` (main.yml:234–242) with no validation
and no restart handler, so broken QML surfaces at next manual reload, far from
the change.

1. Add a pre-copy assertion task that runs `tests/qml-lint` on the source tree
   (delegate_to localhost / `local_action`, tagged so `--skip-tags` works).
2. Do **not** add an automatic shell-restart handler (a mid-session restart is
   disruptive; Quickshell hot-reloads file changes anyway). Instead print a
   debug message when files changed.
3. Also: `iw` and `curl` are runtime deps of the shell but absent from every
   role package list (only transitively installed today). Add them to
   `roles/desktop` packages. (Note: `iw` may become unnecessary after WP2.6 —
   add it anyway; removal is cheap.)

**Accept:** `update` with a syntax-broken QML file aborts before any file is
copied; a normal run is unchanged.

---

## Phase 1 — Bug fixes and cheap performance wins

All WPs here are small. ∥ = parallelizable. **Serialize anything touching
`Bar/Bar.qml` (WP1.4, WP1.6) and anything touching `Common/T3Code.qml`
(WP1.1, WP1.2, WP1.5, WP1.6).**

> **Phase complete.** All ten WPs landed (`b0fcc8a` … `20af650`), and every
> acceptance check a WP note recorded as unrun was cleared on 2026-08-07 —
> WP1.2's DND-on case, WP1.4 items 2–3 on a second output, WP1.8's focus
> handoff, both of WP1.9's, and WP1.10 against the live shell. The one item
> deliberately left is WP1.8's latch *timing*, which needs frame-level capture.
> The methods are written up under "Runtime validation" so later phases do not
> have to rediscover them.

### [x] WP1.1 T3 socket reconnect wedge

> Done. `connect()` now splits the unpaired case from the not-ready case:
> unpaired returns with `state = "unpaired"` and no retry, paired-but-not-ready
> sets `"offline"` and calls `scheduleRetry()`. `socketLoader.onStatusChanged`
> connects on the transition to `Ready` while `paired` and not already
> connected/connecting. Notes:
> - `Loader.Error` deliberately does **not** schedule a retry: the component can
>   never load (QtWebSockets missing), so retrying would only leave a no-op
>   timer firing every 120 s. The existing warning still fires.
> - `onStatusChanged` calls `retryTimer.stop()` before `connect()`. The only
>   retry that can be armed at that point is the one `connect()` itself armed on
>   the not-ready path, and letting it fire afterwards would tear down the
>   socket that call just opened.
> - The extra `state !== "connecting"` guard is unreachable today (you cannot
>   reach `"connecting"` without a Ready loader) but states the "one connect
>   attempt at a time" invariant instead of relying on it.
> - Verified only on the normal path (the chip reconnects across config
>   reloads). The plan's delayed-loader simulation was **not** run — worth doing
>   if this area is touched again.

**Files touched:** `Common/T3Code.qml`
**Depends on:** Phase 0

`connect()` (~line 388) early-returns when
`socketLoader.status !== Loader.Ready` *without* calling `scheduleRetry()`, and
`socketLoader.onStatusChanged` (~2355) never calls `connect()` on transition to
`Ready`. If the loader isn't ready when the state file loads, the shell stays
"offline" until restart.

Fix both sides: schedule a retry on the early-return path, and call `connect()`
from `onStatusChanged` when status becomes `Ready` while `paired && state !== "connected"`.

**Accept:** simulate by delaying the loader (temporarily set `active` false →
true after state file load); state recovers to connecting/connected without a
restart.

### [x] WP1.2 T3 notifications must respect DND / quiet hours

> Done, but **the premise was wrong**: `org.freedesktop.Notifications` is owned
> by this shell's own `NotificationServer`, so `notify-send` looped back into
> `onNotification` and `if (!root.toastsSuppressed && !notif.lastGeneration)`
> already suppressed the toast. The stated acceptance check passed before this
> change. The real defects were a fork per transition and a gate that only
> worked *by accident* of this shell owning the bus name — install any other
> notification daemon and DND silently stops applying to T3. Notes:
> - `Notifs.publish(source, notif)` is now the single entry constructor for both
>   the D-Bus path and the new `Notifs.send(request)`; a synthetic notification
>   runs the same `derivePresentation`, gets the same field shape, and obeys the
>   same 50-entry / 3-toast bounds. Shell sends are `live: false` /
>   `notif: null` / `actions: []`, already handled everywhere, keyed
>   `shell-<serial>-<arrived>` so they cannot collide with D-Bus keys.
> - `notifyTransition` calls the helper, preserving appName "T3 Code" and icon
>   "utilities-terminal". It loses only a live remote object (T3 notifications
>   carry no actions) and the icon-diagnosis `console.log`.
> - **WP0.5's follow-up is included**: both corruption announcements now also
>   raise a critical notification via `Settings.notifyCorruption()`. The
>   `Settings`↔`Notifs` mutual reference is safe because both call sites are in
>   `corruptBackupProc.onExited` — the `mv` must start and finish first, so it
>   cannot run during singleton construction, and it is a one-shot call, not a
>   binding. Under DND it still only reaches the center: `toastsSuppressed`
>   gates all urgencies, and changing that would affect every critical
>   notification.
> - Shaped so `Common/tests/settings.test.cjs` keeps matching
>   `root.announcement = "The settings file could not be read.` as literal
>   source text, rather than editing a test this WP does not own. That assertion
>   is brittle — worth relaxing to a text-presence check next time someone is in
>   that file.
> - Two `notify-send` callers remain: `Common/Launcher.qml` should migrate;
>   `Settings/NotificationsPage.qml`'s test button arguably should not, since
>   exercising the real D-Bus round trip is its point.
> - Verified live via the corruption route (see the commit): a critical toast
>   rendered with the right app name, summary and body.
> - **DND-on verified 2026-08-07** (the check this note previously listed as
>   outstanding). A throwaway `probe` IpcHandler calling `Notifs.send()`
>   directly removed the need for a T3 thread transition on demand. With DND
>   off: toast rendered, `toasts=1 entries=1`. With DND on: no toast,
>   `toasts=0 entries=2`, and the notification center showed the entry with a
>   coalesced count of 2 beside a lit Do Not Disturb switch. The gate is the
>   single `!toastsSuppressed` test in `publish()`, so the D-Bus path and
>   `send()` cannot diverge.

**Files touched:** `Common/T3Code.qml`, `Common/Notifs.qml`, `Common/Settings.qml`
**Depends on:** Phase 0; serialize with WP1.1 (same file)

`notifyTransition` (~line 341) shells out to `notify-send` directly, bypassing
`Common/Notifs.qml` DND/quiet-hours logic (Notifs.qml:22–24). Either route the
send through a new `Notifs.send(...)` helper that applies the same gating, or
minimally check the same DND conditions before spawning. Prefer the helper —
other future senders will need it.

**Accept:** with DND enabled in settings, a T3 thread transition produces no
desktop notification; with DND off it still does.

### [x] WP1.3 ∥ Deduplicate drifted logic: media glyphs, battery, percent normalization

> Done — `Common/StatusHelpers.js` now holds the media glyph table and player
> selection, the battery charge semantics, and the percent normalization the
> three call sites had drifted copies of; the popovers consume it and
> `Common/tests/status-helpers.test.cjs` covers it (suite 109 → 120 tests). The
> Bar side lands with WP1.4. Notes:
> - Named `StatusHelpers.js` rather than the plan's `MediaHelpers.js`: it
>   carries battery and Wi-Fi logic too, and the shared percent normalization
>   belongs to neither media nor battery alone.
> - `Common/qmldir` is deliberately untouched — `.js` helpers are imported by
>   path and none of the four existing ones is listed there, so the plan's
>   instruction to add an entry would have been wrong, not just redundant.
> - **Battery semantics: the popover was right and the bar was wrong.** "full"
>   stays distinct from "charging"; the bar draws both the same through
>   `isPluggedIn()`, but its tooltip no longer claims "charging" for a full
>   battery. `alert`, `glyph` and `idleColor` are unchanged in behaviour.
> - The helpers take the service object (or null) rather than pre-read values,
>   so the null guards are shared too. Verified against a live-but-windowless
>   Quickshell that QML binding capture reaches property reads made inside an
>   imported `.js` module, and that the shipped module runs unchanged under
>   Quickshell's JS engine.
> - The two enum tables are mirrored numerically to keep the module Qt-free; a
>   test pins them against the installed `.qmltypes` and skips when Qt is absent.
> - All seven glyph codepoints were diffed against the originals, including the
>   easily-missed U+F001 the old code returned for a null player (it was the
>   generic music mark, not an empty string).
> - Reactive state stayed with each consumer as a thin `readonly property`
>   wrapper — nothing went into `SysInfo.qml`. Phase 2 absorbs exactly those
>   wrappers: `battery`/`batteryPct`/`batteryState`/`batteryPlugged` and
>   `player`/`mediaVisible` in `Bar.qml`, `battery`/`pct`/`chargeState`/
>   `charging`/`full` in `BatteryPopover`, `players`/`player` in `MediaPopover`.

**Files touched:** `Common/MediaHelpers.js` (new) or extend an existing helper,
`Common/qmldir`, `Popovers/MediaPopover.qml`, `Popovers/BatteryPopover.qml`,
`Popovers/WifiPopover.qml`, `Common/tests/` (new test file), and the Bar side
**coordinated with WP1.4** (Bar.qml owner applies the Bar edits)
**Depends on:** Phase 0

Three confirmed drift bugs:
- `playerGlyph()` — `Bar/Bar.qml:150–168` has a `youtube` branch that the copy
  in `Popovers/MediaPopover.qml:82–97` lacks. Also duplicated: the
  active-player selection expression (`Bar.qml:145–149` prefers
  playing→paused→first vs `MediaPopover.qml:20–24` raw list).
- Battery: `charging` includes `FullyCharged` in `Bar.qml:132–134` but not in
  `BatteryPopover.qml:9–11`.
- `pct <= 1 ? pct*100 : pct` normalization in three places
  (`Bar.qml`, `BatteryPopover.qml`, `WifiPopover.qml:14–18`).

Extract to a pure-JS helper (testable) + singleton properties where reactive
(battery state belongs in `Common/SysInfo.qml` or the Phase-2 `Battery`
singleton — if Phase 2 is imminent, put the reactive part there and only the
pure functions here).

**Accept:** Node tests cover glyph mapping and normalization; bar and popover
show identical glyphs/charging state for the same player/battery.

### [x] WP1.4 Bar.qml quick wins (single owner for all Bar.qml edits in this phase)

> Done — all six items. Notes:
> - The tailscale stopgap is a `unanchoredPanels: ["settings", "tailscale"]`
>   list on `barWindow` with a comment pointing at WP3.1; those two are exactly
>   the `Popouts.defaultIsland` names no `registerPanel()` covers.
> - **One extra fix the module gating forced:** `onModsChanged` now also returns
>   early on a bar that is not `visible`. Every output runs that handler, and
>   with modules no longer instantiated on hidden bars, a hidden bar's empty
>   `panelAnchors` would have closed the mapped bar's popout on any module
>   change — item 3 would have shipped a new multi-monitor bug without this.
> - `SystemClock.enabled` verified headlessly: while disabled `date` freezes,
>   and re-enabling resyncs it in the same turn, so a bar taking over an output
>   never shows a stale time.
> - `T3Chip` gained `property bool barVisible`, threaded from `Bar.qml` as
>   `barWindow.visible && !barWindow.hidden`, rather than
>   `Window.window.visible` — which is null exactly when the window is unmapped.
>   Including auto-hide is a deliberate extension: it stops the 30 Hz pulse
>   behind a slid-away bar and is the only part of items 2–4 observable on a
>   single monitor.
> - `micMuted` was dead and left `source` dead too, so both went; the
>   `PwObjectTracker` still binds `Pipewire.defaultAudioSource` (WP2.1's call).
> - `idleColor` lost its redundant `&& !barWindow.charging` inside the false
>   branch of the same test.
> - **Verified live:** with the Tailscale popover open, enabling the `vol`
>   module (visible on the bar in the same frame, so `onModsChanged` provably
>   fired) left the popover open. Note `bt` is useless for this test — its
>   `autoRule` is `btConnected`, so it stays hidden with no device paired.
> - **Items 2–3 verified 2026-08-07** on a `hyprctl output create headless`
>   second output, with `onActiveChanged`/`onDateChanged` instrumentation in the
>   deployed copy and `precision` forced to `Seconds` so ticks are countable.
>   With the bar on eDP-1: 8 clock ticks in 8s on eDP-1, **zero** on
>   HEADLESS-1, and all 13 module slots there `active=false`. Pinning
>   `barEnabled` to HEADLESS-1 swapped it cleanly — ticks moved entirely to
>   HEADLESS-1, eDP-1 logged `clock enabled=false` and 13 slots to
>   `active=false`, and `hyprctl layers -j` confirmed the single `qs-bar`
>   surface migrated. The bar rendered correctly on the narrower output, in
>   compact mode, so the fit machinery survives the move.

**Files touched:** `Bar/Bar.qml`, `Bar/T3Chip.qml`
**Depends on:** Phase 0; coordinates with WP1.3

Bundle the small Bar.qml items so only one agent edits the file:
1. Register the missing `tailscale` panel or exclude it at the
   `Settings.onModsChanged` close loop (~line 308) the way `settings` is
   excluded — fixes the "Tailscale popover closes on any settings change" bug.
   (The structural fix is WP3.1; this is the stopgap.)
2. `SystemClock` (~line 1205): add `enabled: barWindow.visible`
   (property confirmed present in quickshell-core.qmltypes).
3. Module instantiation (~line 326–353 `ModuleSlot`): add `barWindow.visible`
   to `active` so hidden bars on multi-monitor don't instantiate all modules.
4. `Bar/T3Chip.qml:85–97`: gate the 30 Hz pulse timer on window visibility
   (thread `barWindow.visible` down or use `Window.window.visible`).
5. Delete dead property `micMuted` (~line 130).
6. Apply the Bar-side edits from WP1.3 (use the new shared helpers).

**Accept:** with a 2-monitor setup (or `Settings.monitor` pinned), the hidden
bar's clock/pulse timers stop (verify via `journalctl` debug or by observing
CPU with `top -p $(pgrep quickshell)` idle drop); tailscale popover survives a
module-setting change.

### [x] WP1.5 ∥ T3 popover sizes against its own screen

> Done. `T3CodePopover` takes `availableWidth`/`availableHeight` from the host
> instead of reading `Screens.focused`, so it sizes against the output the bar
> is actually on. The host already fed both to any panel that declares them, so
> `Bar/IslandPopout.qml` needed **no change at all**. Units were audited against
> `updateAvailableSize` so nothing is subtracted twice — the host removes the
> side margins, the bar and a 48px shadow budget, and the popover now removes
> only its own padding, header, footer, spacing and no-read banner. Notes:
> - The 484/800 fallbacks are preserved as the property defaults, so an unhosted
>   instance measures exactly as before.
> - `screenBottomMargin` (16) is gone rather than kept alongside the host's
>   shadow budget, which would have double-counted. Net effect on a single
>   screen is a 32px smaller max page height, which only bites when the inbox is
>   tall enough to hit the cap.
> - `Screens.barScreen` (already in `Common/Screens.qml`) would have been a
>   smaller fix, but the host-supplied envelope is what WP4.4 formalises and it
>   also accounts for the bar and shadow.
> - Verified the popover still renders correctly on the single output. The
>   multi-monitor case needs a second output; `hyprctl output create headless`
>   plus `hyprctl dispatch focusmonitor` reproduces it without hardware, since
>   `Screens.focused` maps from `Hyprland.focusedMonitor`.
> - The title used to promise an "Escape contract stopgap" this WP's body never
>   specified. Retitled 2026-08-07; `handleEscape()` was always WP4.4's, and
>   WP4.4 item 1 already carries it. Nothing was dropped.

**Files touched:** `Popovers/T3CodePopover.qml`, `Bar/IslandPopout.qml`
**Depends on:** Phase 0

`T3CodePopover.qml:13–22` computes its size budget from `Screens.focused`; on
multi-monitor with a pinned bar this is the wrong output. `IslandPopout`
already sets `availableWidth/availableHeight` on loaded items that declare them
(IslandPopout.qml:185–195) — add those two properties to `T3CodePopover` and
use them instead of `Screens.focused`. (Full base-type contract lands in
WP4.4; this fixes the live bug.)

**Accept:** on a pinned-bar multi-monitor layout, the T3 popover fits the
hosting screen. Single-screen behavior unchanged.

### [x] WP1.6 Idle-CPU sweep

> Done, all five items, in one commit but split across two agents by file
> (T3Code vs SysInfo/Usage). Notes:
> - **`rpcHandlers` does not notify.** It is mutated in place at seven sites,
>   and an in-place mutation never re-evaluates a binding, so the plan's
>   `Object.keys(rpcHandlers).length > 0` would have silently stopped RPC
>   timeouts from ever firing. All seven now go through `putRpcHandler` /
>   `dropRpcHandler` / `clearRpcHandlers`, maintaining `rpcDeadlineCount` (an
>   `int`, so it notifies). In-place `delete` is kept inside those helpers
>   because `abortPendingRpcs` captures the old object by identity, and the
>   sweep and `cancelActionRequests` delete while iterating with `for…in`.
> - **Deviation:** the count tracks only handlers carrying a `deadline`.
>   `startDetailSubscription`'s has none, so the plan's predicate would have
>   pinned the 500 ms timer on for as long as the popover showed a thread.
> - **Deviation:** the action half is
>   `Object.values(actionStates).some(s => s && s.pending === true)`, not a key
>   count. `failAction` deliberately leaves finished entries in place to show
>   their error, so a key count would have kept the timer running forever after
>   the first failed action. `actionStates` itself needed no change.
> - Item 2's gate needed no widening: `workingNowMs` reaches only
>   `T3InboxPage`/`T3ThreadPage` via `T3CodePopover`. `Bar/T3Chip.qml` reads
>   counts and `state`, never a duration. Added `triggeredOnStart: true` so the
>   labels refresh on open instead of showing the previous close's value.
> - `SysInfo.wifiDevice` was deleted too (beyond the plan's list): `bitrateProc`
>   was its only reader, and `Bar.qml`/`ControlCenterPopover.qml` each carry
>   their own copy for WP2.2 to absorb.
> - **Deviation:** item 4's list is `["control","tailscale"]`, not
>   `[…,"battery"]` — `BatteryPopover` reads no `ts*` or `brightness` property.
>   The only brightness consumer outside the control centre is `OsdWindow.qml`,
>   which is not a popout and refreshes over IPC.
> - **Deviation:** item 5 gates on the `usage` module only. Nothing on the T3
>   side reads the `Usage` singleton, and since both modules default to `on`,
>   including `t3` would have made the gate a no-op for the default config.
>   `refresh()`'s `pollTimer.restart()` is guarded on the same predicate, and
>   `warmUp()` clears `loading` when the module is off.
> - **The plan's accept criterion (`top` before/after) is not measurable on a
>   machine in use.** Sampling the live shell gave 0.12%–6.44% CPU and
>   3.9–213 wakeups/s across windows of *identical* code; the variance is
>   compositor traffic from the user's desktop and dwarfs anything Phase 1 does.
>   Instrumenting both trees and counting firings in the journal is the metric
>   that works: sweep 109 → 1, working clock 54 → 1, with an unrelated control
>   timer unchanged at 1664 vs 1670. Use that method for later perf WPs.



**Files touched:** `Common/SysInfo.qml`, `Common/T3Code.qml`, `Common/Usage.qml`
**Depends on:** Phase 0; serialize with WP1.1/1.2 (T3Code.qml)

1. **T3Code ~line 646–664**: the 500ms sweep timer runs unconditionally while
   connected. Gate:
   `running: state === "connected" && (Object.keys(rpcHandlers).length > 0 || Object.keys(actionStates).length > 0)`
   — verify both are notifying (they are assigned via reassignment; confirm
   each assignment site triggers the binding, otherwise start/stop the timer
   imperatively at the mutation sites).
2. **T3Code ~332–337**: the 1 Hz `workingNowMs` tick — add
   `&& Popouts.open && Popouts.currentName === "t3code"` (same pattern commit
   `5dc5c6d` used for SysInfo).
3. **SysInfo dead code**: delete `wifiBitrate` + `bitrateProc` (forks `iw`
   every 30s, zero readers), `uptime` + its always-on 60s timer (~294–303),
   `kernel` + the `uname -r` Process (~115–121). Grep first to confirm still
   unreferenced.
4. **SysInfo ~308–319**: the 30s popout poll spawns `tailscale status --json`
   and `brightnessctl` for *every* popout. Scope:
   `running: Popouts.open && ["control","tailscale","battery"].includes(Popouts.currentName)`.
5. **Usage ~196–209**: gate `pollTimer.running` on the `usage` or `t3` module
   being enabled in `Settings.mods` (keep the shell.qml warm-up working when
   enabled).

**Accept:** `tests/run` green; idle `quickshell` CPU visibly drops
(compare `top` over 60s before/after); weather/usage/t3 chips still update.

### [x] WP1.7 ∥ Brightness via sysfs FileView

> Done. `brightnessProc` is gone; a one-shot `sh -c` discovery process finds
> `/sys/class/backlight/*` and two `FileView`s read `brightness` and
> `max_brightness`, mirroring the `sensorDiscovery`/`tempView` pattern.
> `brightnessctl` still does every write. `brightness` stays `-1` until the
> first successful read. Notes:
> - This machine has one backlight, `intel_backlight` (`max_brightness` 512).
>   brightnessctl's percent is a *rounded* ratio, not truncated — verified with
>   `brightnessctl -m -p set N` (pretend mode, no write) at 511→100%, 383→75%,
>   508→99%, 3→1%, 2→0%. Implemented as `Math.round(value * 100 / backlightMax)`.
>   A truncating implementation would have been off by one across most of the
>   range.
> - No `watchChanges`: backlight sysfs attributes deliver no inotify events
>   (already documented at `Common/Osd.qml`). `refreshBrightness()` keeps an
>   explicit `reload()` and remains the sole re-read path; `brightness-control`
>   runs `brightnessctl set` to completion before pinging
>   `qs ipc call osd brightness`, so there is no read-before-write race.
> - `setBrightness()` still sets `brightness` optimistically rather than
>   re-reading, so the slider and the OSD scroll wheel do not fight a delayed
>   read-back. Unchanged behaviour.
> - The discovery one-liner takes the first `/sys/class/backlight/*` entry with
>   a readable `brightness`. On a machine with both `acpi_video0` and a vendor
>   backlight this could pick a different device than brightnessctl does; not
>   reproducible here with a single device.
> - **Verified live:** the control centre reads 100%, `brightnessctl -m` reports
>   100%, sysfs is 512/512 and the shell's formula gives 100% — all three agree.
>   The "no fork on the read path" check via `strace` was not run (yama
>   `ptrace_scope=1` blocks attaching without privilege); the code path no
>   longer contains a `Process`, which is the same claim statically.



**Files touched:** `Common/SysInfo.qml` (serialize with WP1.6 — same file)
**Depends on:** WP1.6 (merge into the same session/agent as WP1.6 if easier)

Replace the `brightnessctl -m` Process (~242–252) with `FileView`s on
`/sys/class/backlight/*/brightness` + `max_brightness`, mirroring the existing
`sensorDiscovery`/`tempView` pattern (~124–156). Keep `brightnessctl` only for
*writing* (sysfs writes need permissions; brightnessctl handles that via
systemd-logind).

**Accept:** OSD brightness percentage updates on key press with no fork on the
read path; value matches `brightnessctl -m`.

### [x] WP1.8 ∥ Popover open latency: BlockMeter, slot latching, async page loaders

> Done — ~395 → ~195 objects per Control Center open, and Control Center
> reopens without incubating at all. Deviations:
> - **BlockMeter is one Repeater of N rects plus one partial rect, not a tiled
>   `Image` or `ShaderEffect`.** `blockWidth`/`gap` really are overridden (3/2 in
>   Weather and the stat cards), `trackColor` is `"transparent"` at one site, and
>   both colours are dynamic — so a tile needs one asset per geometry plus a
>   `MultiEffect` mask, i.e. an offscreen render target per meter, which breaks
>   the batching that makes solid rects cheap in the first place. `ShaderEffect`
>   needs a checked-in `.qsb` and a build step the repo does not have.
>   Equivalence is proved, not eyeballed: a 16.7M-sample pixel model shows 0
>   mismatches, and an offscreen Qt Quick render of old vs new over a 14-case
>   matrix produces byte-identical PNGs (an intentionally broken variant differs
>   in 3.9M px, so the check has teeth).
> - **Latching is restricted to `control`** via a `warmNames` list on the host.
>   Blanket latching regresses idle CPU and correctness: `wifi` leaves the
>   scanner enabled, `usage` and the settings `SystemPage` hold unconditional
>   1 Hz timers, `media`'s tick is gated on `visible` which stays true,
>   `tailscale` runs its status `Process` once at construction and would reopen
>   stale, and `t3code` must reopen on the Inbox and call `closeDetail()`.
> - `sync()` now re-seats a reused slot on its own tab (`snapCollapsed` when
>   `openProgress < 0.01`) before animating. Without it a warm Control Center
>   reopened after another panel sweeps across the bar as it grows — a bug that
>   already exists at HEAD inside the 260 ms close window.
> - `beginClose()` zeroes both loader opacities, so a latched panel still runs
>   the normal 45 ms + 150 ms fade on reopen: the latch skips construction only,
>   not the choreography.
> - **`T3CodePopover`'s page loader stays synchronous**, as does
>   `ModuleDetailView`'s. T3's implicit height *is* its page height and drives
>   the host geometry and layer-surface size, so an incubating page opens the
>   body in two stages and collapses it on every navigation — the per-frame
>   resize `3f9c1d2` removed. Both slot Loaders in `IslandPopout` are already
>   async, so neither loader was ever on the click frame.
> - Async `detailLoader` needed two supporting changes: `focusFirst()` moved
>   from a `Qt.callLater` (which now always sees `item === null`, silently
>   losing keyboard focus) to `onLoaded`, and the list hides on
>   `detailLoader.item` rather than `subPageActive`, because the sub-page is
>   transparent — a frame early shows both, a frame late shows neither.
> - **Verified live:** the Control Center renders correctly with the new meters
>   (volume 3%, brightness full, three stat strips).
> - **The Modules cog focus handoff is verified 2026-08-07** and the change was
>   necessary, not defensive. An offscreen `qs -p` harness hosting `ModulesPage`
>   reports `activeFocusItem = SettingsAction text="All modules"` with
>   `activeFocus=true` after `openSubPage()`, and focus returning to the
>   originating `ModuleRow` after `closeSubPage()`. Reconstructing the
>   pre-WP1.8 shape — `focusFirst()` driven from `openSubPage` via
>   `Qt.callLater` — reproduces exactly the predicted failure:
>   `TypeError: Cannot call method 'focusFirst' of null` and
>   `activeFocusItem=null`. The `onLoaded` handoff is load-bearing under an
>   async loader.
> - Latch *timing* is still only reasoned about, not measured. It needs a
>   frame-level capture rather than a screenshot; not attempted.



**Files touched:** `Popovers/BlockMeter.qml`, `Bar/IslandPopout.qml`,
`Settings/SettingsView.qml`, `Popovers/T3CodePopover.qml`,
`Settings/ModulesPage.qml`, `Settings/ModuleDetailView.qml`
**Depends on:** Phase 0. Serialize with WP1.5 (IslandPopout.qml).

1. **BlockMeter** builds ~400 throwaway Rectangles per ControlCenter open (two
   Repeaters, ~23–31 and ~42–50). Replace the block strip with a single
   `Image { fillMode: Image.Tile }` using a generated tile asset (block +
   gap), or a small `ShaderEffect`. Preserve the exact visual (block width,
   gap, rounding, fill fraction behavior).
2. **IslandPopout `closeTimer`** (~390–407) clears both slot names on close,
   forcing full re-incubation per open. Latch the last-used slot (don't clear
   its name; keep the loader alive but invisible). Bound memory: latch only
   one slot. This mirrors what commit `a401fe1` did for the launcher.
3. **Synchronous page Loaders**: add `asynchronous: true` to
   `SettingsView.qml:473–490`, `T3CodePopover.qml:263–266`,
   `ModulesPage.qml:713–724`, `ModuleDetailView.qml:94–96`. Verify no visible
   pop-in (sizing was stabilized by `3f9c1d2`; if pop-in appears, keep sync
   and note it).

**Accept:** ControlCenter and Settings reopen visibly faster (grim screenshots
of intermediate frames or simple wall-clock via journal timestamps); no visual
regressions in the meters (screenshot diff).

### [x] WP1.9 ∥ Process hygiene: exit codes, stderr, silent catches

> Done. Runtime findings first, since they changed the design: Quickshell emits
> **no `exited` at all** when a binary cannot be launched — only the falling
> edge of `running` — so the LauncherView pattern this WP points at is not
> sufficient on its own (LauncherView has the same latent stuck-`loading` bug;
> left alone as out of scope). All four producers settle on `runningChanged`
> with a `NOT_STARTED` sentinel, and count `staleRuns` because a restart's kill
> reports itself as a crash exit *after* the replacement has started, which
> would otherwise render as a spurious error for the length of every refresh.
> Two plan corrections: `NetworkDevice.address` is the randomized **MAC**
> (`4A:06:51:7D:95:E4` here), so `WifiPopover` took the
> `["ip","-j","-4","addr","show",name]` + `JSON.parse` route — verified to
> return the same address the `jq` pipeline did; and `jq` **is** declared, in
> `roles/apps/defaults/main.yml:54`, so the unquoted interpolation and the
> swallowed stderr were the real defects. Notes:
> - New `Common/ProcHelpers.js` + `proc-helpers.test.cjs` (10 tests) holds
>   exit-code/stderr classification, curl's silent exit codes (6 DNS, 7 connect,
>   22 HTTP, 28 timeout — `curl -sf` emits no stderr, so the status is the whole
>   report), and the `ip`/`tailscale` JSON shapes. `tailscalePeers()` returns
>   `null` rather than `[]` for unreadable output, so "0 of 0 devices online"
>   can only mean an empty tailnet.
> - `Weather` gained `fetchError`/`offline` beside a `ready` that keeps its
>   latching "there is something to draw" meaning, so stale-but-drawable is
>   distinguishable from never-loaded. Logging is on message *change*, not per
>   attempt — the 30 s retry would otherwise write 120 journal lines an hour.
> - `Usage` gained `fetchError` that stays empty while the module is off, so
>   "off" cannot read as "broken", and `loading` now clears on every terminal
>   edge including never-started.
> - **Scope extended past the listed files to the consumers**, because the
>   acceptance criteria could not otherwise pass — the states existed and
>   nothing rendered them. The weather chip used to vanish behind
>   `visible: Weather.ready`, so an offline-at-startup module was invisible
>   rather than informative; it now stays on the bar (na glyph, dimmed "—",
>   "unavailable", reason in the tooltip). `UsageChips` separates "the fetcher
>   broke" from "every provider is signed out". Both popover footers carry the
>   reason as `Text.PlainText`, because a traceback containing `<module>` would
>   otherwise be eaten as markup by those RichText footers.
> - The offline chip is never wider than a ready one, so the fit machinery
>   needed no change; `detailSaving` is now more honest than before (it used to
>   report a 5px saving for a module occupying zero width).
> - Verified headlessly against the real files: offline weather, missing script,
>   missing binary, dead tailscaled, bogus device, stacked restarts, and the
>   live happy path was confirmed after deploy.
> - **Both acceptance checks run 2026-08-07, on the mapped bar.** Moving
>   `usage-fetch.py` aside turns the usage chip into a red "Models unavailable"
>   with a dimmed provider icon, and the popover footer carries
>   `/usr/bin/python3: can't open file '/home/john/.config/…` beside the poll
>   countdown. For weather, pointing the deployed copy's `curl` at
>   `http://127.0.0.1:1/` was used instead of `nmcli networking off` — it
>   isolates the connect failure without taking the user's network down, and
>   the journal confirms the exit-7 classification ("could not connect to the
>   host"). Both weather states render as designed: `N/A — unavailable` when
>   nothing ever loaded, and — staged by serving a captured open-meteo response
>   from a local port and then killing it — the last known forecast still drawn
>   with the reason in red in the popover footer. `ready && offline` behaves.



**Files touched:** `Common/Weather.qml`, `Common/Usage.qml`,
`Popovers/TailscalePopover.qml`, `Popovers/WifiPopover.qml`
(SysInfo parts fold into WP1.6/1.7 to avoid file contention)
**Depends on:** Phase 0

Adopt the good pattern from `LauncherView.qml:240–265` (staleness guard +
stderr collector + exit-code branch):
1. **Weather.qml** (~159–197): `curl -sf` failure yields empty stdout →
   parse-fail warning and a permanently blank module. Add an `offline` state
   surfaced in the weather chip/popover ("weather unavailable"), keep the
   existing 30s retry.
2. **Usage.qml** (~179–191): capture stderr from `usage-fetch.py`, log it, and
   expose an error state to the chip instead of only `console.warn`.
3. **TailscalePopover.qml:53–55**: `catch { peers = [] }` renders as "0 of 0
   devices online" — indistinguishable from an empty tailnet. Add an error
   state.
4. **WifiPopover.qml:20–27**: replace the
   `sh -c "ip -j -4 addr show <interpolated> | jq …"` pipeline (unquoted
   interpolation, undeclared `jq` dep, stderr swallowed) with either
   `NetworkDevice.address` (property exists — **first verify at runtime that
   it is the IPv4 address, not MAC**) or a direct
   `["ip", "-j", "-4", "addr", "show", name]` + `JSON.parse`.

**Accept:** unplug network → weather module shows offline state; break the
usage script → chip shows error; popovers still correct in the happy path.

### [x] WP1.10 ∥ T3 socket error surfacing

> Done. **Deviation:** the property is `T3Code.connectionError`, the last
> *connection* error, not the last socket error — QML's `XMLHttpRequest`
> collapses refused/DNS/TLS/timeout into `status === 0` with an empty
> `statusText`, so at a dead port the ticket POST fails and
> `T3Socket.errorString` is never written at all; a socket-only property fails
> this WP's own accept check. `Common/T3CodeHelpers.js` gained
> `socketErrorText`/`ticketErrorText` (t3code-helpers 34 → 38 tests). Notes:
> - Qt raises the close and the error that caused it as two transitions in
>   either order, and only one carries text — a refusal is `3 ("")` then
>   `4 ("Connection refused")`, a TLS failure is `4` then `3 ("")`. Both are
>   read, an empty string never overwrites a real one, and the read sits
>   outside the connected/connecting guard because the close has usually
>   already called `scheduleRetry()` by then. Every string in the tests was
>   captured from a live Qt 6.11 WebSocket, not written from memory.
> - The reason survives the retries that follow it and is cleared only just
>   before `state = "connected"`, so the caption stays on the failure instead of
>   flickering to a generic line on every retry tick.
> - `Loader.Error` (QtWebSockets missing) now sets `connectionError` to
>   "QtWebSockets is not installed" — not a socket error but a different and
>   more actionable diagnosis, and previously the one permanent "off" with no
>   on-screen explanation at all. It cannot be overwritten or cleared by
>   construction: `connect()` returns on the not-Ready branch before it requests
>   a ticket, the socket `Connections` block only enables while the loader is
>   `Ready`, and the clear runs on an open that can never happen. The existing
>   journal warning, which names the package, still fires. A derived
>   `readonly property bool websocketsMissing` lets the popover drop its
>   "— retrying" suffix here, where nothing retries — it is also the only way a
>   consumer can tell this terminal state from a retrying one, since both read
>   `state === "offline"`.
> - The popover's header caption got an explicit width and `ElideRight` (new ids
>   `headerRow`/`headerActions`): at `t3MinWidth` an unelided error ran under
>   the ＋New/↻ buttons. Measured in the shell's own font, the QtWebSockets
>   caption fits unelided at that width precisely because it carries no suffix.
> - Verified end to end in a windowless throwaway instance (dead port, upgrade
>   500, upgrade 401, recovery clearing the error, and a forced `Loader.Error`).
> - **Verified against the live shell 2026-08-07.** Overriding `root.host` to
>   `http://127.0.0.1:1` in the deployed copy avoids touching the real pairing
>   file at all — `accessToken` still loads, so `paired` stays true and the
>   ticket POST is what fails. The chip goes to `T3 off` and the popover header
>   caption reads "Server did not respond — retrying" with `offline ·
>   127.0.0.1:1` in the footer. That caption is the `ticketErrorText(0)` branch,
>   confirming this WP's central deviation in production: the failure surfaces
>   through the ticket XHR, not `T3Socket.errorString`. Restoring the file
>   reconnects without a restart.



**Files touched:** `Popovers/T3CodePopover.qml`, `Bar/T3Chip.qml` (coordinate
with WP1.4 if concurrent), `Common/T3Code.qml` (one property; coordinate)
**Depends on:** Phase 0

`Common/T3Socket.qml:17` exposes `errorString`; nothing consumes it. The user
sees "off" identically for TLS failure, DNS failure, server down, revoked
ticket. Surface the string (tooltip on the chip's off state and/or a caption
line in the popover's offline view).

**Accept:** point the configured host at a dead port → popover shows the
underlying socket error text instead of bare "off".

---

## Phase 2 — Service singletons

Goal: one place derives default-sink/wifi-device/adapter/battery/player;
Bar, popovers, and OSD become pure consumers. Kills the per-output
multiplication of trackers and the divergent selection logic.

**Pattern for each:** new singleton in `Common/`, registered in
`Common/qmldir`; owns the Quickshell service objects (`PwObjectTracker`,
device find, etc.) and exposes `readonly` derived properties. Consumers switch
from local derivation to the singleton.

> **Rescoped 2026-08-07, before WP2A landed.** The phase was written as five
> parallel singleton WPs plus a six-WP join, on the premise that each singleton
> also resolves a drift bug. WP1.3 already did that half: the *pure* logic moved
> to `StatusHelpers.js` and battery/media/percent stopped disagreeing. What is
> left for Battery, Media and BluetoothState is a 3–5 line reactive wrapper
> fixing no bug, which does not justify a WP and a commit each.
>
> The payoff moved to Phase 4. `Bar.qml` carried **27** `barWindow.<service>`
> references, concentrated in exactly the inline module components WP4.3 wants
> to extract into `Bar/Modules/*.qml`; without singletons every one becomes a
> property threaded into the extracted file. That — not drift — is why the thin
> singletons still earn their place, and why Bar is the consumer that had to
> migrate first.
>
> So the phase is two WPs, not six:
> - **WP2A** — all five singletons + `Bar.qml`. **Done.**
> - **WP2B** — the remaining consumers, plus the parts of the old WP2.6 that
>   were never about singletons at all (tailscale spawn unification, the two
>   debounce timers, the `SysInfo` refcount, the `Usage` countdown). Those are
>   the phase's real remaining behavioural content.
>
> WP2.1–2.5 below are kept only as the record of what each singleton absorbs.
>
> **Phase complete** (`814bce7`, WP2B). Read WP2B's first note before
> adding any `acquire()`/`release()` call: the refcount must key on
> `visible` via `Common/Claim.qml`, not on construction, because
> `IslandPopout` latches the Control Center and it is never destroyed.

### [x] WP2A Five service singletons + Bar.qml migration

> Done. Notes:
> - **`Common/Network.qml` had to be renamed `Common/WifiState.qml`.**
>   `Quickshell.Networking` exports a type named `Network`, so a consumer
>   importing both resolves the name by import order — and the Quickshell one
>   is a value type, so `Network.enabled` would not even have meant anything.
>   The plan's own name was the bug; `BluetoothState` already had the right
>   shape for the same reason. Audio/Battery/Media/BluetoothState were checked
>   against every Quickshell module a consumer imports and are clear.
> - **qmllint caught a load-time break the tests would otherwise have shipped**:
>   four of the five singletons were missing `import Quickshell`, so `Singleton`
>   itself did not resolve. It surfaced as 487 `[import]` warnings
>   ("incomplete composite type"), not as an error — worth watching, because the
>   file would have failed to load at runtime.
> - `Audio` exposes `volume` as rounded percent *and* `setVolume`/`stepVolume`/
>   `toggleMuted` on Pipewire's 0..1 scale, because every call site was
>   converting and clamping identically. Bar's wheel handler is now one line.
> - `BluetoothState.connected` deliberately does **not** derive from its own
>   `devices` list: that list is gated on the adapter being enabled, while the
>   bar module's auto-rule should turn on as soon as any device is connected.
> - The `PwObjectTracker` that moved out of `Bar.qml` was instantiated **once
>   per output**. This is the only part of the phase that is a real saving
>   rather than a tidy-up.
> - Bar shed five imports (Pipewire, Mpris, UPower, Bluetooth, Networking) and
>   the `StatusHelpers.js` import; qmllint named the first five itself, and
>   `Networking` only became detectably dead after the `WifiState` rename.
> - **Verified live**: all five singletons' values cross-checked against
>   `wpctl`, `nmcli`, `upower`, `bluetoothctl` and `playerctl` through a
>   throwaway `probe` IpcHandler — all match. Because this config has `vol`,
>   `bt` and `media` switched **off**, the bar itself cannot exercise three of
>   them; a second Quickshell instance under a fake `HOME` with those modules
>   enabled rendered the volume module at 3% with the low-volume glyph, and left
>   `bt`/`media` correctly hidden by their auto-rules.
> - **Not done here:** `AudioPopover`'s enumerated `sinks` list stays local to
>   that popover. It is popover-scoped state whose tracker should not be alive
>   shell-wide; WP2B decides whether it moves.

**Files touched:** `Common/Audio.qml`, `Common/WifiState.qml`,
`Common/BluetoothState.qml`, `Common/Battery.qml`, `Common/Media.qml` (all
new), `Common/qmldir`, `Bar/Bar.qml`

### [x] WP2B Remaining consumers + Tailscale unification

> Done. **The headline is a regression this WP introduced and then fixed** —
> the plan's own prescription was the cause, so read this before writing any
> more `acquire()`/`release()` calls:
> - The plan says the refcount goes in `Component.onCompleted`/`onDestruction`.
>   That is wrong now. WP1.8 latches the Control Center (`IslandPopout.warmNames`),
>   so it is constructed once and **never destroyed** — `release()` never fired
>   and the pollers ran for the rest of the session, strictly worse than the
>   `Popouts.open` gate being replaced. Measured, not reasoned: with
>   instrumentation counting timer firings, 4 stat samples and 1 tailscale spawn
>   in 16s while open, and *the same again* in the 20s after closing.
> - Fixed with `Common/Claim.qml`, a small primitive that holds a claim while
>   `active` is true and releases on teardown, keyed on the item's `visible`.
>   Window visibility propagates down to items, so it tracks latched and
>   non-latched panels alike — verified directly: the latched panel reports
>   `visible=false` on close while never being destroyed. After the fix: 0
>   firings when closed, never above `watchers=1` across three open/close
>   cycles.
> - The `Claim` signals are edge-paired by construction, so a consumer cannot
>   double-release. Four call sites use it (Control Center ×2 singletons,
>   Tailscale, Usage popover, Settings System page).
>
> Other notes:
> - **`Common/Tailscale.qml` is a new singleton, not an extension of `SysInfo`.**
>   The plan offered either; SysInfo is already a grab-bag of CPU/RAM/temp/
>   backlight/idle-inhibit and Phase 4–6 want it smaller. The two old spawns had
>   *different* quality: the control centre's parsed self-status behind a bare
>   `catch` that could not tell a dead tailscaled from `tailscale down`, while
>   the popover's classified failures properly. One run now answers both, with
>   the popover's error handling and an unreadable read clearing `running`
>   rather than leaving a stale "connected".
> - New `ProcHelpers.tailscaleSelf()` beside `tailscalePeers()`, +3 tests
>   (134 → 137), including the case the bare `catch` collapsed.
> - Debounce unified at **1400ms**, the longer of the two — 1200ms occasionally
>   read the pre-toggle state back.
> - **`Usage.nextPollSecs` became derived rather than counted down.** Three
>   copies of that arithmetic existed because the counter was unreliable: the
>   popover resynced on open, and `SystemPage` recomputed its own and only fell
>   back to the shared value when `updatedAt` was 0. It is now anchored on when
>   the poll *period* started, not on `updatedAt` — the timer fires on schedule
>   whether or not the fetch it started succeeded, so anchoring on data arrival
>   would have stalled the countdown at 0 through every failed fetch.
> - **Scope extended by one line:** SysInfo's 10s temperature poll ran
>   unconditionally for the whole session for a single reader — the same stat
>   card as CPU and RAM. Same watcher basis now. It was not in the plan's list
>   because the plan only named the two `Popouts.open` gates; this one was worse.
> - `AudioPopover` keeps its enumerated device list and that list's tracker, as
>   WP2A predicted: it is popover-scoped, and binding every sink node shell-wide
>   would be waste. Its tracker dropped the two defaults, which `Common/Audio.qml`
>   now covers permanently.
> - `Common/qmldir` gained its first non-singleton entry (`Claim`).
> - **Verified live**: every migrated popover screenshotted and correct — audio
>   3%/100% with the right device name, Wi-Fi with SSID/signal/IP/others/
>   "Scanning…", battery "Fully charged" with the power-profile row, Control
>   Center tiles, Tailscale self row plus peer list from the single spawn, and
>   both countdowns ticking (popover 4:09 → 4:01, System page 3:38 → 3:31).
> - **Not exercised: the Tailscale toggle itself.** `Tailscale.toggle()` runs
>   `tailscale down`/`up`, and this machine reaches the T3 server over the
>   tailnet, so testing it would drop a live connection. The command and the
>   refresh-after-settling shape are unchanged from the two call sites it
>   replaces; only the interval and the location moved.
> - One pre-existing warning is *not* from this WP and was checked rather than
>   assumed: opening the audio popover logs `channelVolumes and channelMap are
>   not the same size` for a RAOP network sink. Reproduced on the pre-WP2B
>   commit; that node is in the device list, which both versions bind identically.

**Files touched:** `Common/Tailscale.qml`, `Common/Claim.qml` (both new),
`Common/Audio.qml`, `Common/WifiState.qml`, `Common/Osd.qml`,
`Common/SysInfo.qml`, `Common/Usage.qml`, `Common/ProcHelpers.js`,
`Common/qmldir`, `Common/tests/proc-helpers.test.cjs`,
`Popovers/{ControlCenter,Audio,Wifi,Bluetooth,Battery,Media,Tailscale,Usage}Popover.qml`,
`Settings/SystemPage.qml`

<details>
<summary>Original WP2B specification</summary>

### WP2B Remaining consumers + Tailscale unification

**Files touched:** `Popovers/ControlCenterPopover.qml`, `Common/Osd.qml`,
`Popovers/AudioPopover.qml`, `Popovers/WifiPopover.qml`,
`Popovers/BluetoothPopover.qml`, `Popovers/BatteryPopover.qml`,
`Popovers/MediaPopover.qml`, `Popovers/TailscalePopover.qml`,
`Popovers/UsagePopover.qml`, `Common/SysInfo.qml`, `Common/Usage.qml`
**Depends on:** WP2A

1. Switch the remaining consumers to the singletons; delete the local
   derivations. `MediaPopover` keeps its manual source pick and falls back to
   `Media.player`; `BatteryPopover` keeps `fmtDuration` and reads
   `Battery.device` for the time estimates.
2. Unify the duplicate `tailscale status --json` spawn: extend `SysInfo` (or a
   new `Common/Tailscale.qml`) to keep the peer list; `TailscalePopover` reads
   it and calls a shared `refresh()`. Also unify the two toggle-debounce
   timers (1400ms vs 1200ms → one).
3. Fix the responsibility inversions in these files:
   - `SysInfo` stats polling gated on `Popouts.open` (~270, ~310) → replace
     with a refcount API (`SysInfo.acquire()/release()` from popover
     `Component.onCompleted/onDestruction`).
   - `UsagePopover.qml:11–24` drives `Usage.nextPollSecs` countdown from
     inside the popover → move the 1s countdown into `Common/Usage.qml`.

**Accept:** `grep -rn 'defaultAudioSink\|PwObjectTracker'` shows only
`Common/Audio.qml` (plus `AudioPopover`'s device list if item 1 leaves it
there); same for the other services. All popovers + OSD + bar behave
identically (screenshot pass over each popout via
`qs ipc call popouts toggle <name>`). Note this config has `vol`, `bt` and
`media` off — use the fake-`HOME` second instance to see those.

</details>

---

### Record of what each singleton absorbs (folded into WP2A)

### [x] WP2.1 ∥ `Common/Audio.qml`
Default sink, volume, mute, `PwObjectTracker` (today in `Bar.qml:122–130`,
`ControlCenterPopover.qml:22–28`, `AudioPopover.qml:14,25`, `Osd.qml:16–18`).

### [x] WP2.2 ∥ `Common/WifiState.qml` (planned as `Network.qml`)
Wifi device (`find(d => d.networks !== undefined)`), active network, signal
(today in `Bar.qml:136–140`, `ControlCenterPopover.qml:18–19`,
`WifiPopover.qml:10,28`, `SysInfo.qml:105`). Fold `SysInfo`'s wifi bits here.

### [x] WP2.3 ∥ `Common/BluetoothState.qml`
Default adapter, powered, connected devices (today in `Bar.qml:142`,
`ControlCenterPopover.qml:20`, `BluetoothPopover.qml:8`).

### [x] WP2.4 ∥ `Common/Battery.qml`
UPower display device, normalized pct, charging/full semantics — the *single*
definition resolving the WP1.3 drift (today `Bar.qml:132–134`,
`BatteryPopover.qml:8–19`).

### [x] WP2.5 ∥ `Common/Media.qml`
Active-player selection (playing → paused → first), `playerGlyph` re-export
from the WP1.3 helper (today `Bar.qml:145–168`, `MediaPopover.qml:17–24`).

### WP2.6 — superseded by WP2B above.

---

## Phase 3 — Panel registry and module resolution

> **Phase complete** (`5a641dd`, `7c8b8f7`). Two corrections worth carrying
> forward: `missing-property` cannot drop until WP4.2/WP4.4 — all 14 are
> dynamic-type accesses, not sibling-resolution failures — and Quickshell
> does not watch `qmldir` files, so a qmldir edit needs a `.qml` touch to
> reload.

### [x] WP3.1 `PanelRegistry` as single source of truth

> Done. `Common/PanelRegistryData.js` describes all 13 panels; `Popouts`'
> island map and `IslandPopout`'s source map are now one line each, and the
> `unanchoredPanels` stopgap WP1.4 left in `Bar.qml` is gone — "no module owns
> this panel" is a fact the registry states rather than a list to keep in sync.
> Notes:
> - **Sources are stored relative to the shell root**, and `IslandPopout` asks
>   for them with `sourceMap("../")`. That reproduces the exact strings that
>   were hand-written in the file before, so path resolution provably did not
>   change; a data module in `Common/` holding paths only correct relative to
>   `Bar/` would have been a trap for the next host.
> - The three flags map cleanly onto the eight hardcoded checks:
>   `centerAnchored` (Bar's geometry sweep, the host's centre-island retarget),
>   `fillsBody` (both slot loaders), `persistsAcrossHosts` (`shell.qml`'s
>   focus-change dismissal, `BarPopoutWindow`'s focus-grab handoff).
>   `Settings.qml`'s four self-references use a `SETTINGS` constant. The only
>   remaining `"settings"` literal outside `Settings/` is `shell.qml`'s **IPC
>   target name**, which is a different key space and correctly left alone.
> - `PANEL_LESS_MODULES` (`ws`, `idle`) exists so the test can insist the two
>   key spaces account for each other *completely*. Without it, a typo'd
>   `moduleId` would just look like another module that happens to own no panel.
> - **Two assertions in `settings.test.cjs` had to change**, and they are the
>   brittleness WP1.2's note predicted: they matched the island and source maps
>   as literal source text, which no longer exists. Rewritten to assert against
>   the registry — where the claim now belongs, and where reformatting cannot
>   break it.
> - **The test was checked for teeth on all four drift classes**: a panel in
>   `Bar.qml` but not the registry (2 failures), a typo'd `moduleId`, a source
>   pointing at a missing file, and a consumer reverted to `=== "settings"`
>   (names the exact file and line). Suite 137 → 148.
> - **Verified live**: all 12 module panels open over
>   `qs ipc call popouts toggle <name>`, with island placement matching the
>   derived map — media on the left, calendar centred under the clock, the rest
>   right. Settings opens centred and body-filling. `persistsAcrossHosts` was
>   exercised in both directions on a second output: settings survives the
>   focused-screen change and hands itself to the returning bar, while the
>   Control Center is dismissed with the bar that spawned it.
> - Note for later: `hyprctl output create headless` does **not** always name
>   the output `HEADLESS-1`; it was `HEADLESS-2` this time, and the Lua focus
>   dispatch fails with "monitor not found" on a stale name. Read the name back.

<details>
<summary>Original WP3.1 specification</summary>

### WP3.1 `PanelRegistry` as single source of truth

**Files touched:** `Common/PanelRegistryData.js` (new), `Common/Popouts.qml`,
`Bar/IslandPopout.qml`, `Bar/Bar.qml`, `Common/tests/panel-registry.test.cjs` (new)
**Depends on:** Phase 2 (Bar.qml churn settles)

Today three hand-maintained registries disagree (`Popouts.defaultIsland` 13
keys, `IslandPopout.sources` 13 keys, `registerPanel` calls 11 names), plus a
fourth key space of module ids in `SettingsHelpers.js:6–9`. Known fallout: the
tailscale bug (stopgapped in WP1.4), and `"settings"` special-cased by string
in 8 places.

1. One JS data module: per panel `{ name, island, source, moduleId,
   centerAnchored, fillsBody, persistsAcrossHosts }`.
2. `Popouts.defaultIsland`, `IslandPopout.sources`, and Bar's id→panel mapping
   all derive from it. Replace the 8 hardcoded `"settings"` string checks
   (`shell.qml:60`, `Bar.qml:308,467–473`, `IslandPopout.qml:373,570,600`,
   `BarPopoutWindow.qml:44`, `Settings.qml:106–118,444`) with the three
   declarative flags.
3. Node test asserting: every `registerPanel`d name exists in the registry,
   every registry source file exists on disk, moduleId ↔ panel mapping is
   total. (Mirror the style of `Common/tests/settings.test.cjs`.)

**Accept:** test fails if a panel is added to one map but not the registry;
tailscale stopgap from WP1.4 replaced by proper registration; all popouts
still open via `qs ipc call popouts toggle <name>`.

</details>

### [x] WP3.2 qmldir everywhere + generalized sync test

> Done — `Bar/`, `Popovers/` and the root gained qmldirs, and
> `Common/tests/qmldir.test.cjs` covers all five directories (the plan said
> four; `Common/` was already indexed but nothing enforced it). The
> Settings-only check in `settings.test.cjs` is removed as superseded. Suite
> 148 → 153. Notes:
> - **The accept criterion "`missing-property` count should drop" was wrong.**
>   It is unchanged at 14, and cannot move here: all 14 are dynamic-type
>   accesses — `Loader.item` and `Window` attached properties resolving as
>   `QObject`/`QQuickItem`/`QQuickWindow` — which no amount of sibling
>   indexing can type. That is exactly what WP0.4's note predicted, so the
>   expectation contradicted an earlier finding in this same document. It needs
>   WP4.2 (declaring the duck-typed bar contract as real properties) and WP4.4
>   (the `PopoutPanel` base type). One of the 14 is neither: WifiPopover's
>   `WifiSecurityType.None` is an upstream enum-exposure gap, like the
>   `signal-handler-parameters` case WP0.2 found.
> - **The qmldirs are load-bearing, and that was proved rather than assumed.**
>   Removing `Surface` from the deployed `Popovers/qmldir` makes
>   `BatteryPopover` fail with "Surface is not a type" — confirming a directory
>   carrying a qmldir really does stop being implicitly scanned, which is also
>   what makes the completeness test necessary rather than decorative.
> - **Quickshell watches `*.qml` but not `qmldir`.** Editing a qmldir alone
>   does not trigger a reload — the first attempt at the check above silently
>   "passed" for that reason. Touch any `.qml` to force it. Low risk in
>   practice, since adding a type changes a `.qml` in the same deploy, but it
>   will mislead anyone testing a rename or removal by hand.
> - Two structural exemptions, both enforced rather than assumed:
>   `shell.qml` (the entry point, and a lowercase basename can never be a QML
>   type name — the test derives this from the filename rather than listing it),
>   and `Common/T3Socket.qml`, whose reason is now recorded in `Common/qmldir`
>   itself. The test fails if an exemption's file disappears, if its reason is
>   missing, or if T3Socket stops being loaded by URL — so the exemption cannot
>   quietly outlive its justification.
> - **Verified live**: clean load, then every lazily-resolved type exercised —
>   all 12 popouts, all six settings pages, the launcher, and the OSD — with no
>   type-resolution failures. The eager root types (`LauncherWindow`,
>   `NotificationToasts`, `OsdWindow`) are proved by the shell loading at all.

<details>
<summary>Original WP3.2 specification</summary>

### WP3.2 qmldir everywhere + generalized sync test

**Files touched:** `Bar/qmldir` (new), `Popovers/qmldir` (new), root `qmldir`
(new), `Common/tests/qmldir.test.cjs` (generalize existing settings check)
**Depends on:** WP3.1 (IslandPopout source paths settle)

`Settings/qmldir` exists precisely because implicit directory scanning "proved
unreliable" (its own header comment); `Bar/`, `Popovers/`, and the root rely
on exactly that mechanism. Add qmldirs, generalize the
`settings.test.cjs:12–24` sync check to all four directories, and note
`Common/T3Socket.qml`'s deliberate omission (graceful degradation when
QtWebSockets is absent) with a comment in `Common/qmldir`.

**Accept:** shell loads cleanly from a deploy copy; qmldir test covers all
dirs; qmllint resolves sibling types (`missing-property` count should drop).

</details>

---

## Phase 4 — Bar decomposition

Strictly sequential (all touch `Bar/Bar.qml`).

### [x] WP4.1 `BarChip` primitive

> Done — `Bar/BarChip.qml` carries the hover/held pill, tooltip and pointer
> plumbing for the clock, media and weather chips. Like `BarIcon` it knows
> nothing about the bar: it reports `entered`/`exited`/`clicked` as signals and
> takes `held` as a property, so the wiring to `barWindow.hoverOpen` /
> `togglePopout` stays at the use site. Content binds its colours off the
> chip's `held` and `hovered` instead of reaching for a sibling MouseArea's id.
> Notes:
> - **The line-count target was wrong.** The plan expected ~240 → ~90; the real
>   result is `Bar.qml` 1187 → 1111 and a 69-line primitive, so **net −7**.
>   Those 240 lines were three *components*, and most of that is content that
>   was never duplicated — the elided media title, the clock's two date
>   formats, weather's three-part readout. What actually repeated was the
>   ~25-line wrapper (Rectangle + colour + Behavior + MouseArea + BarTooltip)
>   ×3. That duplication is gone; judge this WP on there being one hover
>   contract rather than three, not on the diff size.
> - `hPadding` defaults to 7 (media and clock's `+14`); weather sets 6 and
>   `spacing: 5`, which is what it always used.
> - **Equivalence is measured, not eyeballed.** Clock and weather were captured
>   from the live bar on HEAD and on this change: **exactly 0 differing
>   pixels** across the whole centre cluster. Media is switched off in this
>   config and its only MPRIS player reports no track, so it was rendered in a
>   second instance under a fake `HOME` against a stub MPRIS service — max
>   per-channel deviation **1/255**, zero at 0.4% fuzz, i.e. render noise
>   between two processes rather than a rendering change.
> - `held` re-checked live: opening the calendar popout gives the clock chip
>   the strong pill and brightens its date text; closing removes both.
> - Two tests had to follow the refactor, both correctly: `Bar/qmldir` (WP3.2's
>   completeness check caught the new file immediately), and the hover-recovery
>   assertion in `settings.test.cjs`, whose file list still named `Bar.qml` —
>   which no longer owns a module hover surface at all. It now checks
>   `BarChip` and additionally asserts that bar modules do *not* grow their own
>   hover MouseArea again.

<details>
<summary>Original WP4.1 specification</summary>

### WP4.1 `BarChip` primitive

`cmpMedia` (607–701), `cmpClock` (719–790), `cmpWeather` (792–881) are three
~80-line near-copies of hover-rect + row + tooltip. Extract
`Bar/BarChip.qml` with `default property alias content` and the
`held/containsMouse` fill states; `Bar/BarIcon.qml` already is this shape for
glyph modules — keep the two consistent.
**Accept:** ~240 lines → ~90; screenshots of media/clock/weather chips
identical; hover/tooltip behavior unchanged.

</details>

### [x] WP4.2 `panelName` wiring collapse (planned as a `BarModule` base type)

> Done, in the shape agreed before starting: `panelName` goes on the existing
> primitives rather than into a new wrapper type. `BarIcon`, `BarChip`,
> `T3Chip` and `UsageChips` each take `panelName` plus a **typed**
> `property Bar host`, and turn that one name into registration, the `held`
> state, hover-switching and click. The 11 call sites lose ~6 lines of
> boilerplate each; `Bar.qml` 1111 → 1068. Notes:
> - **Typing the host is what makes this checkable.** `host.registerPanelTypo(…)`
>   is a lint error naming the member, with a "Did you mean" suggestion —
>   verified by deliberately misspelling it. The alternatives both fail that
>   test: `Window.window` types as a plain `QQuickWindow` (it is where two of
>   the 14 `missing-property` warnings came from), and `property var host`
>   would be unresolvable and so checked by nothing.
> - The primitives drive the panel from inside their `MouseArea` and **still
>   emit** `clicked`/`entered`/`exited`, because a use-site `onClicked` would
>   otherwise override the type's handler and silently unwire the panel. That
>   is what lets the idle module keep its own click while owning no panel.
> - `anchorItem` exists for the bell alone: it registered its *wrapper*, whose
>   height is the full bar row rather than the icon's, so registering the icon
>   instead would have moved the popout's anchor rect.
> - `UsageChips` takes registration and `held` but keeps its own handlers — its
>   clicks select a provider or close, which the generic toggle cannot express.
>   A test pins that as the only remaining hand-wiring.
> - `Bar/Workspaces.qml` needed `pragma ComponentBehavior: Bound` after all
>   (WP0.3 recorded it as not needing one) because threading `host` into its
>   tooltip is an outer-id capture. Safe here: its delegate declares `index`
>   as `required` and never touches `modelData`, which is the failure mode
>   WP0.3 warned about.
> - **The lint flip did not happen, and the second half of this WP belongs to
>   WP4.3.** Typing `BarTooltip`'s host cleared 2 warnings (14 → 12), but the
>   plan's other target — declaring `isle`/`dividerBefore`/`dividerAfter`/
>   `detailSaving` as real properties — has nowhere to live yet: the modules
>   are inline `Component`s whose roots are variously `Row`, `Item`, `BarIcon`
>   and `BarChip`, so there is no common base to declare the contract on until
>   WP4.3 extracts them to files. Of the 12 that remain, 10 are `Loader.item`
>   duck-typing in Settings/Launcher/T3 (WP4.4 and WP6), one is `Bar.qml`'s
>   `detailSaving` (WP4.3), and one is the upstream `WifiSecurityType` enum
>   gap. No suppressions were added to force the flip.
> - **Verified live**: clean load; a probe of `panelAnchors` reports exactly
>   the panels whose modules are enabled *and* pass their auto-rule — 8 on this
>   config, 9 with `vol` switched on in a second instance, with `media` and
>   `bluetooth` correctly absent because nothing is playing and no device is
>   paired. `held` renders on the owning module for wifi and for the bell.
> - **Not verified: hover-switch and click by pointer.** This machine has
>   `wtype` (keyboard only) and no pointer-injection tool, so the MouseArea
>   paths were exercised only through their `held`/registration consequences.
>   The handler bodies moved verbatim into the primitives.

<details>
<summary>Original WP4.2 specification</summary>

### WP4.2 `BarModule` base type + panel wiring collapse

The register/unregister/held/onClicked/onEntered/onExited boilerplate repeats
11× (~lines 619, 728, 804, 910, 941, 1012, 1048, 1069, 1090, 1123, 1190) with
the panel name typed 5–6× each. Give `BarIcon`/`BarChip` (or a `BarModule`
base) a `panelName` property that drives all of it from the WP3.1 registry.
Declare the duck-typed `isle`/`dividerBefore`/`dividerAfter`/`detailSaving`
contract as real properties so qmllint checks it (removes the remaining
`missing-property` warnings; flip that category to error in `.qmllint.ini`
when clean).
**Accept:** one name per module; a typo'd panelName now fails the WP3.1 test.

</details>

### [ ] WP4.3 Extract modules to `Bar/Modules/*.qml`

Move the 13 inline module components out (spans listed in the architecture
notes; e.g. `cmpBell` 1116–1181). `moduleComponents` map becomes URLs.
Extract the layout engine (island rects, `panelAnchors`, fit/compact recompute,
~174–360) into a non-visual `BarLayout.qml` and the hover-to-switch state
machine (~362–486) into `BarPopoutController.qml` if the split proves clean —
otherwise leave them and note it.
**Accept:** `Bar.qml` under ~400 lines; all modules render and toggle
popouts; reordering modules in Settings still works.

### [ ] WP4.4 `PopoutPanel` contract type + anchor-rect caching

1. `Popovers/PopoutPanel.qml` base type declaring `drawBackground`,
   `availableWidth/Height`, virtual `handleEscape()` (returns false).
   `Surface.qml` and `Settings/SettingsView.qml` inherit it; the duck-typing
   in `IslandPopout.qml:185–195, 258–259, 563` becomes property access.
   Implement `handleEscape` in `T3CodePopover` (thread page → back to inbox
   instead of dismissing the popout).
2. Perf: `hoverPanelAt` (`Bar.qml:393–437`) runs `mapToItem` over all anchors
   per pointer-motion event while a popout is open. Cache anchor rects,
   invalidated on `fitTimer`/register/unregister/geometry change.

**Accept:** Escape inside a T3 thread goes back one page; popout hover-switch
still works across all modules; no per-motion JS spike (verify with
`QSG_RENDER_TIMING` or profiler if in doubt).

---

## Phase 5 — T3Code decomposition

`Common/T3Code.qml` is 2,385 lines / ~55 top-level properties / 8 subsystems;
its `// ----` section banners are the decomposition map. **Keep `T3Code.qml`
as a façade re-exporting the current API** so the 269 call sites migrate
gradually. Strictly sequential; land each WP green before the next.

### [ ] WP5.1 `T3Connection.qml` — state file, ticket fetch, socket loader,
retry/backoff, ping (lines ~355–472, 2340–2385). Exposes `state`, `host`,
`send()`, `signal message(text)`. Includes the WP1.1 fix — port it, don't
re-break it. Also fix the empty `catch (e) {}` at ~441 (environment descriptor)
with a `console.warn`.
### [ ] WP5.2 `T3Rpc.qml` — request ids, `rpcHandlers`, timeout sweeper,
`actionStates` machine (~474–714, 716–1040). Port the WP1.6 timer gating.
### [ ] WP5.3 `T3Threads.qml` — classification, `threadMap`/projections,
counts, `notifyTransition` (~129–353 + `applyItem`). This is all
`Bar/T3Chip.qml` and `T3InboxPage` actually need.
### [ ] WP5.4 `T3Detail.qml` — detail subscription + `recomputeDetailDerived`
(~1678–2340). Only `T3ThreadPage` consumes it.
### [ ] WP5.5 `T3Drafts.qml` — composer + structured-input drafts (~1042–1676).
Pure state, no I/O; must remain a singleton (drafts survive popover teardown —
contract documented at `T3CodePopover.qml:5–7`).
### [ ] WP5.6 `T3Git.qml` — git/VCS actions (~2040–2148). Then delete dead
properties from the façade: `detailActionStates`, `pairHint`, `dayMs`,
`queuedTurnGraceMs` (grep to confirm still unreferenced).

**Accept per WP:** `tests/run` green; T3 pair/unpair, inbox, thread view,
composer send, structured input, git actions all verified on a live deploy
copy (`docs/t3-*-manual-verification.md` checklists apply); no regression in
reconnect behavior (kill server, watch backoff in journal).

---

## Phase 6 — Primitive consolidation, theming, polish

∥ Mostly parallel; group by directory to avoid contention.

### [ ] WP6.1 ∥ Shared popover primitives
- `Popovers/ActionButton.qml` — verbatim T3 action button ×3
  (`T3InboxPage.qml:24–67`, `T3RequestCard.qml:36–79`, `T3ThreadPage.qml:104–147`).
- `Popovers/ListRow.qml` — the icon/title/trailing row pattern ×~8
  (WifiPopover, AudioPopover, TailscalePopover, BluetoothPopover,
  ModulesPage; ~250 lines).
- One scrollbar component (byte-identical ×3 in T3 pages + variant in
  `Settings/SettingsPage.qml:48–58`).
- Header+Toggle row ×4; `LinkText` footer action ×4.
- `DebouncedProcess.qml` extracted from the `LauncherView.qml:240–303` pattern.

### [ ] WP6.2 ∥ Unified Toggle/Slider with accessibility
`Popovers/Toggle.qml` + `Settings/SettingsSwitch.qml` → one parameterized
switch; `Popovers/HSlider.qml` + `Settings/SettingsSlider.qml` → one slider.
The popover variants currently have **zero** keyboard/`Accessible` support —
the merged components carry the Settings versions' a11y at both sizes. Size
variants become Theme tokens.

### [ ] WP6.3 ∥ Theme tokens + adoption
- Add `Theme.accentHover` (kills `#c8e2f4` ×4 + `#b7dcf6`), `Theme.rowInset`
  (the bare `x: 10` ×29), `Theme.insetSurface` (`#1b1c22` ×2), radius roles
  for the 6/7/8 "small control" cluster.
- `Qt.rgba(1,1,1,0.08)` in HSlider/SettingsSlider/BlockMeter is exactly
  `Theme.hairline` — use it.
- Launcher/toasts/OSD: replace 19 numeric `font.pixelSize` + 6 `font.weight`
  literals with the type scale, and `Theme.fontSans` ×9 with `Theme.fontMenu`
  so these windows finally respect the user's font setting.
- Delete dead tokens `Theme.breakpointMedium/Wide`,
  `mediaTitleMediumWidth/WideWidth` (Theme.qml:120–123).

### [ ] WP6.4 ∥ Notification card unification
`NotificationToasts.qml:94–344` and `NotifsPopover.qml` (~150–330) build the
same card anatomy twice (~180 lines each; `closeMouse` is char-identical).
Extract a shared card component (probably `Popovers/NotifCard.qml` or a new
`Common/` visual dir), parameterized for toast vs list contexts.

### [ ] WP6.5 ∥ Settings row scaffolding
A `SettingsRow` base absorbing `narrow`, `labelWidth`, the 12-line UndoChip
slot, and label block duplicated across `SwitchRow`/`PickerRow`/`SliderRow`/
`SettingsTextRow` (+ the offset 5th copy in `SystemPage.qml:97`). Give rows a
`settingKey` property generating `dirty`/`set`/`reset` (pattern already proven
in `ModuleDetailView.qml:31–40`); pass the friendly label to `resetKeys`
consistently.

### [ ] WP6.6 ∥ Formatting helpers + small dead code
- One `Common/Format.js`: `m:ss` (×2), d/h/m duration (×5 variants!), clamp01
  (×15), hour/day ms constants (×5).
- `Wallpaper.pastelize` (Wallpaper.qml:237–257) → call the already-tested
  `SettingsHelpers.hueToHex`/`hexHue` (same 0.5/0.75 constants).
- Delete: `UsageChips.visibleKeys` no-op (~30–32), `WeatherPopover`
  `implicitWidth` redundant override (:9), `T3Composer.selectedProvider`,
  `T3RequestCard.draftKey`, `FolderDialog.displayPath`, duplicate
  `nm-connection-editor` command string in WifiPopover (×2 → one property).
- Replace `shell.qml:150` `_init` side-effect array with explicit
  `Component.onCompleted` touches.

### [ ] WP6.7 ∥ Interaction polish sweep
- `cursorShape: Qt.PointingHandCursor` on the 56 clickable MouseAreas missing
  it (all of `Popovers/`, 4 in Bar).
- `Accessible.role`/`name` for the T3 pages that already have
  `activeFocusOnTab` (focus ring with no label is worse than neither).
- Settings key audit: `Settings.qml` `snapshot()`/`applyLoaded()`/`sectionKeys`
  hand-enumerate the schema ×4 — loop `Object.keys(SettingsHelpers.defaults())`
  instead (~80 lines saved, kills "added a setting, forgot to persist it").

### [ ] WP6.8 ∥ Remaining perf odds and ends
- Toast countdown (`NotificationToasts.qml:142–156`): when `!showProgress`,
  use a plain `Timer` instead of a refresh-rate `NumberAnimation` with no
  visual consumer.
- `Settings/NotificationsPage.qml:363–368`: infinite preview animation repaints
  the settings surface while the page is open — drive at ~10 Hz or gate on
  visibility of the preview card.
- `Notifs.iconSource` (~208–224): memoize the desktop-entry/icon lookup by
  app key (50-entry popover currently re-scans per delegate).
- `LauncherView.appScore` (~48–79): precompute a lowercase token index per app
  when `DesktopEntries.applications.values` changes; score against it.
- `Common/Wallpaper.qml:150–158`: bind `folderModel.folder` lazily (only when
  shuffle enabled or wallpaper settings page open).
- `Common/Clock.qml` singleton (second/minute/nowMs) replacing the scattered
  `SystemClock` instances + `Date.now()` tickers (Bar, NotifsPopover, Notifs,
  T3Code, NotificationToasts).
- `Theme.asset(name, variant)` helper for the 11 hand-built
  `Quickshell.shellDir + "/assets/…"` paths.

### [ ] WP6.9 Deploy hygiene
Exclude `Common/tests/` from the Ansible copy (or move it to the repo-level
`tests/` tree) so the deployed config dir stops accumulating non-runtime
files; the role's retired-files cleanup task (main.yml:244–251) shows this
drift recurs.

---

## Explicitly deferred (decided against for now — do not pick up)

- **qmlformat one-shot reformat**: 60/74 files would churn and the tool fights
  the deliberate hand-wrapped style. Revisit only as a dedicated, single
  commit with a tuned `.qmlformat.ini`, after the refactors above settle.
- **Automatic shell restart on deploy**: Quickshell hot-reloads; a forced
  restart is more disruptive than the problem.
- **QML-level tests via `qmltestrunner-qt6`**: installed and viable, but start
  after Phase 5 when the T3 singletons are small enough to test against a stub
  socket. Candidate first targets: Settings load/merge/save cycle,
  T3Connection state machine.

## Dependency graph (coarse)

```
Phase 0 (sequential) ──► Phase 1 (mostly ∥) ──► Phase 2 (∥ + WP2.6 join)
                                                      │
                                          Phase 3 (sequential, small)
                                                      │
                                          Phase 4 (sequential, Bar.qml)
                                                      │
                                          Phase 5 (sequential, T3Code.qml)
                                                      │
                                          Phase 6 (∥, independent)
```

Phase 6 WPs that touch only their own files (6.3 partially, 6.6, 6.7, 6.8
items) can interleave earlier whenever their files aren't contended — check
"Files touched" against in-flight WPs first.
