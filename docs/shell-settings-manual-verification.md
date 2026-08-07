# Shell settings — manual verification

The Shell settings window (design v2) makes bar geometry, appearance,
modules, wallpaper, and system behavior live-configurable, persisted to
`~/.local/state/quickshell/shell-settings.json`. Automated coverage:
`node --test roles/desktop/files/quickshell/Common/tests/*.test.cjs` (store merge/clamp
rules, qmldir completeness, IPC single-declaration, typography lint) and
`tests/verify-xps` (settings IPC liveness). Everything pointer-driven below
is manual.

## Opening and closing

- [ ] `qs ipc call settings toggle` opens the centered window; again closes it.
- [ ] `qs ipc call settings open modules` lands on the Modules page.
- [ ] Gear in the Control Center footer opens it (and closes the popout).
- [ ] Right-click anywhere on the bar slab opens it; left-clicks on modules
      still open their popouts.
- [ ] `Super+,` opens Settings directly without making the menubar focusable.
- [ ] Esc closes; clicking the scrim closes; opening the launcher closes it
      (focus grab handover).
- [ ] Opening settings while a popout is open closes the popout first.

## Persistence

- [ ] First slider drag creates the JSON; `watch -n1 stat -c %y` on it shows
      at most ~2 writes/s during a continuous drag.
- [ ] Editing the JSON externally applies live (no restart); junk values are
      clamped or reverted to defaults on the next save.
- [ ] Deleting the file live restores defaults; restart keeps them.
- [ ] Reset controls reset exactly their group and show an eight-second
      `… reset · Undo` footer. Undo restores the snapshot; a new reset replaces
      it; any manual edit clears it. A forced save failure exposes Retry.

## Wallpaper page

- [ ] Grid lists the configured wallpaper folder; clicking a thumb swaps the
      wallpaper live and moves the accent ring + ✓.
- [ ] "Shuffle now" picks a different wallpaper each press.
- [ ] Rotate 15 min / 1 hour / Daily arms the timer ("Off" disarms).
- [ ] "Choose folder" stays inside the settings surface. Valid folders,
      including paths with spaces, preserve the current basename or choose the
      first alphabetic supported image. Empty/unreadable folders change nothing.
- [ ] "Open" opens the selected directory in the file manager. Large folders
      scroll smoothly without constructing every thumbnail at once.

## Appearance page

- [ ] Height slider resizes the real bar live; miniature preview and badge
      track it; presets snap it (pill highlights only on exact match).
- [ ] Corner radius reshapes bar islands live.
- [ ] Font rows render their own family; picking one reflows the bar and
      popovers instantly.
- [ ] Accent swatches recolor the whole shell (bar, popouts, toasts,
      settings chrome). "From wallpaper" derives a pastel from the current
      wallpaper (cached in the JSON as `wallAccent`); switching wallpaper
      while enabled re-derives it.
- [ ] Accent hue sweeps continuously through fixed HSL S=.50/L=.75 colors and
      turns off wallpaper-derived accent mode.

## Bar layout page

- [ ] Position Bottom moves the bar; every popout opens above it with the
      fused surface mirrored, content upright, shadow below; tooltips flip
      above modules; toasts hug the top edge; Esc/hover-switching still work.
- [ ] Floating off = edge-to-edge square bar; Edge gap dims while attached.
- [ ] Edge gap slider moves the bar off the screen edge live.
- [ ] Auto-hide: bar slides away after ~1.6 s without hover; hovering the
      screen edge reveals it; it stays out while a popout or the settings
      window is open; clicks pass through the vacated strip.
- [ ] Reserve space off lets tiled windows extend under the bar
      (exclusive zone released; Hyprland re-tiles once per toggle).
- [ ] Monitors: pinning to a named output keeps the bar there regardless of
      focus; unplugging that output falls back to follow-focus.

## Modules page

- [ ] Mini preview mirrors order and enablement (disabled = dashed chip),
      including Idle inhibit and Control Center.
- [ ] Each detail-capable module cycles Auto, Prefer detail, and Always compact;
      Prefer detail compacts only after Auto modules.
- [ ] Toggles apply to the bar instantly; auto-rules keep working (Media
      only while playing, Bluetooth only when connected, Battery on
      laptops).
- [ ] Drag a row: source dims, proxy follows the pointer, accent caret
      marks the gap (rows never shift); drop reorders within and across
      columns, including end-of-column; Esc during a drag cancels it (a
      second Esc closes the window).
- [ ] Disabling a module whose popout is open closes that popout.
- [ ] T3 Code and Model usage can each be toggled, reordered, and moved across
      columns; Claude, Codex, and Kimi remain grouped under Model usage.
- [ ] Disabling T3 Code or Model usage while its popout is open closes only
      that popout; the other module still opens normally.
- [ ] Idle inhibit and Control Center can be reordered within or across
      columns; moving Control Center keeps its popout attached to its module.
- [ ] In a narrow/stacked settings panel, pointer and keyboard drops use the
      correct column-relative index, edge dragging scrolls, and focus returns
      to the dropped row.

## System page

- [ ] 12 h clock reformats the bar clock and both live captions.
- [ ] °F refetches weather in Fahrenheit (bar chip + popover + forecast).
- [ ] Warmth drag with Night light on retints smoothly (single hyprsunset
      restart per pause, not per step).
- [ ] OSD placement Top shows volume/brightness pills top-center, clearing
      the bar; Bottom returns them; slide-in direction matches the edge.
- [ ] Poll every 1 min shortens the countdown; the usage popover and the
      caption agree.

## Regression sweep

- [ ] All popouts open/close/hover-switch as before at default settings;
      Calendar → Weather and other adjacent-module switches work without a
      second click; with Settings open, hovering a module also switches.
- [ ] Click Claude once, then hover Codex and Kimi; the open Usage view changes
      immediately while its panel stays anchored. From another open popout,
      hovering a provider opens Usage after the normal hover delay and selects
      the provider under the pointer.
- [ ] Resize/hotplug from a wide output down to 800 logical px: detail compacts
      Media → Weather → Clock date → T3 → Volume → Battery → Usage, every
      enabled module remains, clusters retain an 8px gutter, and the center
      shifts only after all eligible detail is compact.
- [ ] Fine-grained touchpad scrolling over Volume changes it once per
      accumulated wheel step, not once per raw event.
- [ ] Tab/arrow traversal, automatic focus scrolling, roles/states/actions,
      and Orca announcements work for navigation, custom controls, resets,
      drag/drop, policy buttons, and save errors.
- [ ] `journalctl --user -u quickshell.service` free of QML errors and
      binding loops after exercising every page.
- [ ] `tests/verify-xps` passes.
