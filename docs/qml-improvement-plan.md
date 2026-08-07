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

### [ ] WP0.3 `pragma ComponentBehavior: Bound` everywhere it is needed

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

### [ ] WP0.4 Flip lint to warnings-as-errors for the cleared categories

**Files touched:** `tests/qml-lint`, `.qmllint.ini`
**Depends on:** WP0.3

Promote `unqualified`, `unused-imports`, `comma` to errors in `.qmllint.ini`.
Leave `missing-property` as warning (18 remaining are `Loader.item`
duck-typing — addressed structurally in WP4.2/WP6). `signal-handler-parameters`
is not in this list: WP0.2 established it is an upstream type-exposure gap and
disabled it.

**Accept:** an introduced unqualified access fails `tests/run`.

### [ ] WP0.5 Settings-corruption safety

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

### [ ] WP0.6 Deploy-time validation in the Ansible role

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

### [ ] WP1.1 T3 socket reconnect wedge

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

### [ ] WP1.2 T3 notifications must respect DND / quiet hours

**Files touched:** `Common/T3Code.qml`, `Common/Notifs.qml`
**Depends on:** Phase 0; serialize with WP1.1 (same file)

`notifyTransition` (~line 341) shells out to `notify-send` directly, bypassing
`Common/Notifs.qml` DND/quiet-hours logic (Notifs.qml:22–24). Either route the
send through a new `Notifs.send(...)` helper that applies the same gating, or
minimally check the same DND conditions before spawning. Prefer the helper —
other future senders will need it.

**Accept:** with DND enabled in settings, a T3 thread transition produces no
desktop notification; with DND off it still does.

### [ ] WP1.3 ∥ Deduplicate drifted logic: media glyphs, battery, percent normalization

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

### [ ] WP1.4 Bar.qml quick wins (single owner for all Bar.qml edits in this phase)

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

### [ ] WP1.5 ∥ T3 popover sizes against its own screen + Escape contract stopgap

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

### [ ] WP1.6 Idle-CPU sweep

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

### [ ] WP1.7 ∥ Brightness via sysfs FileView

**Files touched:** `Common/SysInfo.qml` (serialize with WP1.6 — same file)
**Depends on:** WP1.6 (merge into the same session/agent as WP1.6 if easier)

Replace the `brightnessctl -m` Process (~242–252) with `FileView`s on
`/sys/class/backlight/*/brightness` + `max_brightness`, mirroring the existing
`sensorDiscovery`/`tempView` pattern (~124–156). Keep `brightnessctl` only for
*writing* (sysfs writes need permissions; brightnessctl handles that via
systemd-logind).

**Accept:** OSD brightness percentage updates on key press with no fork on the
read path; value matches `brightnessctl -m`.

### [ ] WP1.8 ∥ Popover open latency: BlockMeter, slot latching, async page loaders

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

### [ ] WP1.9 ∥ Process hygiene: exit codes, stderr, silent catches

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

### [ ] WP1.10 ∥ T3 socket error surfacing

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
from local derivation to the singleton. Keep each consumer migration in the
same WP as its singleton.

∥ All five singletons are parallelizable **except the shared consumer files**:
`Bar/Bar.qml`, `Popovers/ControlCenterPopover.qml`, and `Common/Osd.qml`
appear in several WPs. Either serialize the phase's Bar/ControlCenter edits
through one agent, or land singletons first and do one combined consumer-
migration WP (**recommended: WP2.6 does all consumer edits**).

### [ ] WP2.1 ∥ `Common/Audio.qml`
Default sink, volume, mute, `PwObjectTracker` (today in `Bar.qml:122–130`,
`ControlCenterPopover.qml:22–28`, `AudioPopover.qml:14,25`, `Osd.qml:16–18`).

### [ ] WP2.2 ∥ `Common/Network.qml`
Wifi device (`find(d => d.networks !== undefined)`), active network, signal
(today in `Bar.qml:136–140`, `ControlCenterPopover.qml:18–19`,
`WifiPopover.qml:10,28`, `SysInfo.qml:105`). Fold `SysInfo`'s wifi bits here.

### [ ] WP2.3 ∥ `Common/BluetoothState.qml`
Default adapter, powered, connected devices (today in `Bar.qml:142`,
`ControlCenterPopover.qml:20`, `BluetoothPopover.qml:8`).

### [ ] WP2.4 ∥ `Common/Battery.qml`
UPower display device, normalized pct, charging/full semantics — the *single*
definition resolving the WP1.3 drift (today `Bar.qml:132–134`,
`BatteryPopover.qml:8–19`).

### [ ] WP2.5 ∥ `Common/Media.qml`
Active-player selection (playing → paused → first), `playerGlyph` re-export
from the WP1.3 helper (today `Bar.qml:145–168`, `MediaPopover.qml:17–24`).

### [ ] WP2.6 Consumer migration + Tailscale unification

**Files touched:** `Bar/Bar.qml`, `Popovers/ControlCenterPopover.qml`,
`Common/Osd.qml`, `Popovers/AudioPopover.qml`, `Popovers/WifiPopover.qml`,
`Popovers/BluetoothPopover.qml`, `Popovers/BatteryPopover.qml`,
`Popovers/MediaPopover.qml`, `Popovers/TailscalePopover.qml`, `Common/SysInfo.qml`
**Depends on:** WP2.1–2.5 all merged

1. Switch every consumer to the singletons; delete the local derivations.
2. Unify the duplicate `tailscale status --json` spawn: extend `SysInfo` (or a
   new `Common/Tailscale.qml`) to keep the peer list; `TailscalePopover` reads
   it and calls a shared `refresh()`. Also unify the two toggle-debounce
   timers (1400ms vs 1200ms → one).
3. While here, fix the responsibility inversions that touch these files:
   - `SysInfo` stats polling gated on `Popouts.open` (~270, ~310) → replace
     with a refcount API (`SysInfo.acquire()/release()` from popover
     `Component.onCompleted/onDestruction`).
   - `UsagePopover.qml:11–24` drives `Usage.nextPollSecs` countdown from
     inside the popover → move the 1s countdown into `Common/Usage.qml`.

**Accept:** `grep -rn 'defaultAudioSink\|PwObjectTracker'` shows only
`Common/Audio.qml`; same for the other services. All popovers + OSD + bar
behave identically (screenshot pass over each popout via
`qs ipc call popouts toggle <name>`).

---

## Phase 3 — Panel registry and module resolution

### [ ] WP3.1 `PanelRegistry` as single source of truth

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

### [ ] WP3.2 qmldir everywhere + generalized sync test

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

---

## Phase 4 — Bar decomposition

Strictly sequential (all touch `Bar/Bar.qml`).

### [ ] WP4.1 `BarChip` primitive

`cmpMedia` (607–701), `cmpClock` (719–790), `cmpWeather` (792–881) are three
~80-line near-copies of hover-rect + row + tooltip. Extract
`Bar/BarChip.qml` with `default property alias content` and the
`held/containsMouse` fill states; `Bar/BarIcon.qml` already is this shape for
glyph modules — keep the two consistent.
**Accept:** ~240 lines → ~90; screenshots of media/clock/weather chips
identical; hover/tooltip behavior unchanged.

### [ ] WP4.2 `BarModule` base type + panel wiring collapse

The register/unregister/held/onClicked/onEntered/onExited boilerplate repeats
11× (~lines 619, 728, 804, 910, 941, 1012, 1048, 1069, 1090, 1123, 1190) with
the panel name typed 5–6× each. Give `BarIcon`/`BarChip` (or a `BarModule`
base) a `panelName` property that drives all of it from the WP3.1 registry.
Declare the duck-typed `isle`/`dividerBefore`/`dividerAfter`/`detailSaving`
contract as real properties so qmllint checks it (removes the remaining
`missing-property` warnings; flip that category to error in `.qmllint.ini`
when clean).
**Accept:** one name per module; a typo'd panelName now fails the WP3.1 test.

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
