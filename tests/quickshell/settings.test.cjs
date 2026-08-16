const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir, load } = require("./shell.cjs");

function read(relative) {
    return fs.readFileSync(path.join(shellDir, relative), "utf8");
}

test("the settings IPC target is declared exactly once shell-wide", () => {
    const qmlFiles = [];
    const walk = dir => {
        for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
            if (entry.isDirectory() && !entry.name.startsWith(".") && entry.name !== "tests")
                walk(path.join(dir, entry.name));
            else if (entry.name.endsWith(".qml"))
                qmlFiles.push(path.join(dir, entry.name));
        }
    };
    walk(shellDir);
    const declaring = qmlFiles.filter(file =>
        /target:\s*"settings"/.test(fs.readFileSync(file, "utf8")));
    assert.deepEqual(declaring.map(file => path.relative(shellDir, file)),
        ["shell.qml"]);
});

test("settings is a connected center popout rather than a modal window", () => {
    const shell = read("shell.qml");
    const settings = read("Common/Settings.qml");
    const registry = load("PanelRegistryData.js");

    assert.equal(fs.existsSync(path.join(shellDir, "SettingsWindow.qml")), false);
    assert.doesNotMatch(shell, /SettingsWindow\s*\{/);

    // These used to be matched as literal text in Popouts.qml and
    // PopoutHost.qml. Both derive from the registry now, so the registry is
    // where the claim belongs — and asserting it here rather than on rendered
    // source means reformatting those maps cannot fail this test.
    const panel = registry.byName(registry.SETTINGS);
    assert.ok(panel, "the settings panel must be registered");
    assert.equal(panel.island, "center");
    assert.equal(panel.source, "Settings/SettingsView.qml");
    assert.equal(panel.centerAnchored, true);

    // Opened through the popout host with no module anchor to inherit.
    assert.match(settings,
        /Popouts\.openPanel\(PanelRegistry\.SETTINGS,[\s\S]{0,80}?Qt\.rect\(0,\s*0,\s*0,\s*0\)\)/);
});

test("the panel card grows out of its trigger and never out of thin air", () => {
    const host = read("Bar/PopoutHost.qml");

    // The scale origin is the trigger's own centre, clamped inside the card:
    // an origin outside the shape reads as the card sliding rather than
    // growing, which is the whole difference between the two.
    assert.match(host, /originX:\s*clamp\(anchor\.x \+ anchor\.width \/ 2 - bodyX/);
    assert.match(host, /Scale \{[\s\S]*?origin\.x: host\.originX/);
    assert.match(host, /origin\.y: host\.bottomBar \? card\.height : 0/,
        "a bottom bar grows the card upward, from its own lower edge");
    // Transform springs, opacity eases: an overshooting fade reads as a flicker.
    assert.match(host, /bezierCurve: host\.closing \? Theme\.easeInCurve : Theme\.springCurve/);
    assert.match(host, /bodyTop:\s*barBottom \+ Theme\.popGap/,
        "the card hangs a fixed gap below the bar");
    // The mask has to come from real geometry, not from the animating card.
    const mask = host.match(/Item \{\s*id: hitRegion[\s\S]*?\n    \}/)?.[0] ?? "";
    assert.ok(mask !== "", "the popout host must still publish an input region");
    assert.doesNotMatch(mask, /transform|scale:/);
});

test("settings exposes responsive output and keyboard contracts", () => {
    const view = read("Settings/SettingsView.qml");
    const host = read("Bar/PopoutHost.qml");
    const modules = read("Settings/ModulesPage.qml");
    const picker = read("Settings/PickerRow.qml");

    // The envelope is declared once, on the contract both the settings view
    // and every popover surface inherit; the view only overrides defaults.
    const contract = read("Popovers/PopoutPanel.qml");
    assert.match(contract, /property real availableWidth/);
    assert.match(contract, /property real availableHeight/);
    assert.match(contract, /function handleEscape\(\): bool/);
    assert.match(view, /^PopoutPanel \{/m,
        "the settings view must inherit the popout contract");
    assert.match(read("Popovers/Surface.qml"), /^PopoutPanel \{/m,
        "every popover surface must inherit it too");
    assert.match(view, /availableWidth\s*<\s*680/);
    assert.match(view, /function handleEscape\(\): bool/);
    // The host holds its loaded item as the contract type now, so these are
    // plain property writes rather than existence checks.
    assert.match(host, /item as PopoutPanel/,
        "the host must hold its panel as the contract type");
    assert.match(host, /panel\.availableWidth = /);
    assert.match(host, /panel\.availableHeight = /);
    assert.doesNotMatch(host, /!== undefined/,
        "the panel contract must not be probed for at runtime any more");
    // Every panel lays out once at its own implicit size and is revealed by
    // the animating card; binding one to the card would relayout the whole
    // tree on every morph frame.
    assert.match(host, /width:\s*Math\.max\(1, implicitWidth\)/);
    assert.match(host, /height:\s*Math\.max\(1, implicitHeight\)/);
    assert.doesNotMatch(host, /width:\s*fillBody \? parent\.width/,
        "the settings surface must not track the animating clip size");
    assert.match(host, /nameFor\(frontSlot\) !== Popouts\.currentName/,
        "an outgoing popover must not overwrite Settings geometry during a morph");
    assert.match(modules, /Qt\.Key_Space/);
    assert.match(modules, /Qt\.Key_Escape/);
    assert.match(picker, /readonly property real captionWidth/);
    assert.doesNotMatch(picker, /width:\s*root\.narrow \? parent\.width : implicitWidth/,
        "picker flows need a concrete lane width or every pill wraps");
});

test("popout height cannot feed back into its own required envelope", () => {
    const host = read("Bar/PopoutHost.qml");
    const window = read("Bar/BarPopoutWindow.qml");

    assert.match(window, /implicitHeight:\s*Math\.max\(1, popout\.requiredHeight\)/);
    assert.doesNotMatch(host, /onHeightChanged:\s*retargetFront\(\)/,
        "requiredHeight drives native height, so native height cannot retarget requiredHeight");
    assert.match(host, /onOutputAvailableHeightChanged:\s*retargetFront\(\)/,
        "screen-height changes still need to recompute the panel envelope");
    // The envelope reads a stable surfaceH, never the animating renderedH:
    // tracking the morph per frame resizes the blurred Wayland surface on
    // every animation frame, while shrinking after the morph produces one
    // conspicuous compositor reconfigure after the card has already settled.
    assert.match(host, /requiredHeight:\s*presented\s*\?\s*bodyTop \+ Math\.max\(1, surfaceH\)/,
        "the surface envelope must come from the settled height");
    assert.match(host, /surfaceH = Math\.max\(surfaceH, geometry\.bodyH\)/,
        "the surface must grow to the morph's target before the springs start");
    assert.doesNotMatch(host, /surfaceH\s*=\s*(?:host\.)?targetH/,
        "the mapped surface must not shrink after a shorter panel settles");
    assert.doesNotMatch(host, /id:\s*settleTimer/,
        "a post-animation timer must not trigger a second layer-shell configure");
    assert.match(host, /host\.presented = false;\s*host\.surfaceH = 0;/,
        "the surface envelope resets only after the close animation unmaps it");
    // Quickshell 0.2.1 sends this region in the wrong coordinate space on a
    // scaled output. It is only a rendering optimisation, but at 2x it becomes
    // a hard visual clip through the panel sides and bottom.
    assert.doesNotMatch(window, /^\s*HyprlandWindow\.visibleMask\s*:/m,
        "a HiDPI popout must not be clipped by Hyprland's visible-mask hint");
    assert.doesNotMatch(host, /visualItem/,
        "the host must not retain a dead visual-mask contract");
    // The input mask holds still too — it binds to the morph's target, so the
    // compositor hears about it once per switch instead of once per frame.
    assert.match(host, /id: hitRegion[\s\S]{0,80}?x: host\.targetX/,
        "the input region must not follow the animating rendered geometry");
});

test("the tray and the updates chip use the reorderable module pipeline", () => {
    const helpers = read("Common/SettingsHelpers.js");
    const modules = read("Settings/ModulesPage.qml");
    const bar = read("Bar/Bar.qml");

    assert.match(helpers, /"updates", "gh"/);
    assert.match(helpers, /"usage", "tray"/);
    assert.match(modules, /updates:\s*\{ name: "Updates"/);
    assert.match(modules, /tray:\s*\{ name: "System tray"/);
    assert.doesNotMatch(modules, /pinnedTail|text:\s*"pinned"/);
    // The modules are files; the bar maps ids to their sources.
    assert.match(bar, /updates:\s*"Modules\/Updates\.qml"/);
    assert.match(bar, /tray:\s*"Modules\/Tray\.qml"/);
    assert.match(read("Bar/Modules/Updates.qml"), /panelName:\s*"updates"/);
    // Both hide when empty, but a failed/retrying update check must remain
    // reachable so its error and manual retry cannot disappear with the chip.
    assert.match(bar, /case "updates": return Updates\.total > 0 \|\| Updates\.error !== ""/);
    assert.match(bar, /case "tray": return SystemTray\.items\.values\.length > 0;/);
});

test("the three modules the redesign absorbed leave nothing behind", () => {
    const helpers = read("Common/SettingsHelpers.js");
    const modules = read("Settings/ModulesPage.qml");
    const bar = read("Bar/Bar.qml");

    for (const [id, file] of [["bell", "Bell"], ["idle", "Idle"], ["control", "Control"]]) {
        assert.ok(!fs.existsSync(path.join(shellDir, `Bar/Modules/${file}.qml`)),
            `Bar/Modules/${file}.qml is still on disk`);
        assert.doesNotMatch(bar, new RegExp(`${id}:\\s*"Modules/`),
            `the bar still maps a source for ${id}`);
        assert.doesNotMatch(modules, new RegExp(`^\\s*${id}:\\s*\\{ name:`, "m"),
            `the settings module list still names ${id}`);
    }
    assert.match(helpers, /RETIRED_MODULE_IDS = \["bell", "idle", "control"\]/);
});

test("T3 Code and grouped model usage are separate reorderable modules", () => {
    const helpers = read("Common/SettingsHelpers.js");
    const modules = read("Settings/ModulesPage.qml");
    const bar = read("Bar/Bar.qml");

    assert.match(helpers, /"gh", "t3", "usage"/,
        "fresh layouts should keep the two modules adjacent");
    assert.match(modules, /t3:\s*\{ name: "T3 Code"/);
    assert.match(modules, /usage:\s*\{ name: "Model usage"/);
    assert.match(bar, /t3:\s*"Modules\/T3\.qml"/);
    assert.match(bar, /usage:\s*"Modules\/Usage\.qml"/);
    assert.match(read("Bar/Modules/T3.qml"), /panelName:\s*"t3code"/);
    assert.match(read("Bar/Modules/Usage.qml"), /panelName:\s*"usage"/);
    // Separate files make this structural rather than a span check.
    assert.doesNotMatch(read("Bar/Modules/T3.qml"), /panelName:\s*"usage"/,
        "the T3 module must not own the grouped usage popout");
});

test("the T3 running indicator is a static dot", () => {
    const chip = read("Bar/T3Chip.qml");
    const dot = chip.match(/\/\/ Live work:[\s\S]*?\n    Text \{/)?.[0] ?? "";

    assert.ok(dot !== "", "the T3 chip must still mark live work");
    assert.match(dot, /width:\s*root\.busy \? 5 : 0/);
    assert.match(dot, /width:\s*5[\s\S]*height:\s*5/);
    assert.doesNotMatch(dot, /\b(?:Timer|SequentialAnimation|PropertyAnimation)\s*\{/,
        "the five-pixel running indicator must not pulse");
    assert.doesNotMatch(chip, /modOpts\.t3\.pulse|heartbeat|pulseOpacity|pulseStartedAt|barVisible/);
});

test("usage chip hover joins the latched menu session", () => {
    const bar = read("Bar/Bar.qml");
    const usage = read("Bar/Modules/Usage.qml");
    const chips = read("Bar/UsageChips.qml");

    // A closed bar remains inert. Once any popout was clicked open, hovering a
    // provider selects it and morphs the current view to Usage in place.
    assert.match(usage,
        /onChipEntered:\s*key => \{\s*if \(!Popouts\.open\)\s*return;\s*Usage\.selected = key;\s*root\.host\.hoverPopout\("usage", root\.isle, usageChips\.anchorItem\);/,
        "provider hover must be gated by, and participate in, the open menu session");
    // Mapping the popout surface can cost Qt an enter event; motion over a
    // chip still re-delivers the provider.
    assert.match(chips, /onPositionChanged:[\s\S]{0,60}?chipEntered/);
    assert.match(chips, /function providerAtScenePoint\(scenePoint\)/,
        "the bar-wide fallback needs provider-level hit testing");
    const fallback = bar.match(/function hoverPanelAt\(position\)[\s\S]*?\n    \}/)?.[0] ?? "";
    assert.match(fallback, /providerAtScenePoint\(position\)/);
    assert.ok(fallback.indexOf("providerAtScenePoint(position)")
            < fallback.indexOf("Object.keys(panelAnchors)"),
        "provider selection must happen before generic Usage hit testing");
    assert.match(usage,
        /Popouts\.openPanel\("usage", root\.isle,[\s\S]*?anchorOf\(usageChips\.anchorItem\)\)/,
        "all providers should retain the grouped UsageChips anchor");
});

test("regression fixes keep asynchronous state identity-safe", () => {
    const wallpaper = read("Common/Wallpaper.qml");
    const sysInfo = read("Common/SysInfo.qml");
    const bar = read("Bar/Bar.qml");
    const tooltip = read("Bar/BarTooltip.qml");
    const packages = fs.readFileSync(path.resolve(shellDir, "../../tasks/main.yml"), "utf8");

    assert.match(wallpaper, /property string activeAccentFor/);
    assert.match(wallpaper, /root\.currentIdentity === completedFor/);
    assert.match(wallpaper, /Settings\.setInternal\("wallAccentFor", completedFor\)/);
    assert.match(wallpaper, /property bool accentBusy/);
    assert.match(wallpaper, /property string accentError/);
    assert.match(packages, /- ImageMagick/);
    assert.match(sysInfo, /property string nightLightLifecycle/);
    assert.doesNotMatch(sysInfo, /running:\s*root\.nightLight/);
    assert.match(bar, /Component\.onCompleted:[\s\S]*Settings\.autoHide[\s\S]*hideTimer\.restart/);
    assert.match(tooltip,
        /target:\s*Popouts[\s\S]*function onOpenChanged\(\)[\s\S]*delay\.stop\(\)[\s\S]*root\.ready = false/,
        "tooltips must be disarmed when a popout surface maps or unmaps");
    assert.match(bar, /readonly property bool tooltipPointerInside:\s*barHover\.hovered/);
    assert.match(bar,
        /const scenePoint = hoverLayer\.mapToItem[\s\S]{0,120}?barWindow\.tooltipPointerPosition = scenePoint/,
        "the full-bar handler must publish pointer motion for tooltip validation");
    // The hover check lives in one shared object now, so a chip's fill and the
    // tooltip hanging under it cannot disagree about whether the pointer is
    // there. The tooltip takes it as a typed, required property, which is what
    // stops a raw `containsMouse` being handed over by mistake.
    const check = read("Bar/PointerCheck.qml");
    assert.match(tooltip, /required property PointerCheck check/,
        "the tooltip must take the shared check, not a bare bool");
    assert.match(tooltip, /readonly property bool activeHover:\s*check\.over/);
    // The bar reaches the check as a typed `host`, not through Window.window —
    // an attached window is a plain QQuickWindow to the type system, so that
    // read could never be checked.
    assert.match(check, /required property Bar host/);
    assert.match(check, /required property Item target/);
    assert.match(check,
        /if \(!root\.host \|\| !root\.host\.tooltipPointerInside \|\| !root\.target\)\s*return false/,
        "a stale local MouseArea must not keep a hover state alive after leaving the bar");
    // Match code, not prose: the files explain in comments why they stopped
    // using Window.window.
    const code = (tooltip + check).split("\n")
        .filter(l => !l.trim().startsWith("//")).join("\n");
    assert.doesNotMatch(code, /Window\.window/,
        "reading the bar off the attached window is what made this unverifiable");
});

test("schema four carries the glass menubar's defaults and its migration", () => {
    const helpers = read("Common/SettingsHelpers.js");
    assert.match(helpers, /var VERSION = 4/);
    assert.match(helpers, /"updates", "gh", "t3", "usage", "tray"/);
    assert.match(helpers, /warmth:\s*3400/);
    assert.match(helpers, /osd:\s*"bottom"/);
    assert.match(helpers, /themeMode:\s*"dark"/);
    assert.match(helpers, /barHeight:\s*46/);
    assert.match(helpers, /barRadius:\s*23/);
    assert.match(helpers, /mod\("media", true\)/);
    assert.match(helpers, /mod\("bt", false\)/);
    assert.match(helpers, /wallDir:\s*"~\/Pictures\/Wallpapers"/);
    assert.match(helpers, /DETAIL_POLICIES/);
    // A settings file written by the previous schema must adopt the redesign
    // wherever the user never chose otherwise, or the redesign never appears.
    assert.match(helpers, /function adoptRedesign\(parsed\)/);
    assert.match(helpers, /V3_DEFAULTS = \{[\s\S]*?barHeight: 30/);
});

test("settings improvements expose fitting, embedded folders, undo, and shortcut", () => {
    const bar = read("Bar/Bar.qml");
    const modules = read("Settings/ModulesPage.qml");
    const wallpaper = read("Settings/WallpaperPage.qml");
    const folder = read("Settings/FolderDialog.qml");
    const settings = read("Common/Settings.qml");
    const bindings = fs.readFileSync(path.resolve(shellDir, "../bindings.lua"), "utf8");

    assert.match(bar, /LayoutHelpers\.fitBar/);
    assert.doesNotMatch(bar, /width\s*>=\s*Theme\.breakpoint/);
    assert.match(modules, /LayoutHelpers\.stackedDropIndex/);
    assert.match(modules, /id:\s*edgeScroll/);
    assert.match(wallpaper, /GridView\s*\{/);
    assert.match(folder, /popupType:\s*Controls\.Popup\.Item/);
    assert.match(settings, /interval:\s*8000/);
    assert.match(settings, /function retrySave/);
    assert.match(settings, /migrationPending = parsed !== null && parsed\.v !== 3/);
    assert.match(settings, /if \(!ready \|\| migrationPending \|\| corruptBackupPending\)/,
        "v1/v2 files must wait for the next user mutation before a v3 write");
    assert.match(bindings, /mainMod \..*" \+ comma".*settings toggle/);
});

test("settings geometry accommodates wide menu fonts and focused rows", () => {
    const view = read("Settings/SettingsView.qml");
    const page = read("Settings/SettingsPage.qml");
    const theme = read("Common/Theme.qml");
    const base = read("Settings/SettingsRow.qml");
    const system = read("Settings/SystemPage.qml");

    assert.match(view, /preferredHeight:\s*660/);
    // The gutter is unconditional: making it depend on scrollbarVisible
    // loops (narrower content re-wraps taller and flips the scrollbar).
    assert.match(page, /scrollGutter:\s*8/);
    assert.doesNotMatch(page, /scrollGutter:\s*scrollbarVisible/);
    assert.match(page, /width:\s*root\.width - root\.scrollGutter/);
    // The label column widens for the mono menu face. Every row used to
    // carry this expression; it lives in Theme now and reaches the rows
    // through SettingsRow, so assert it where it is rather than where it
    // was — the rows below check that they still inherit the base.
    assert.match(theme,
        /readonly property int settingsLabelWidth:\s*Settings\.font === "mono" \? 122 : 96/);
    assert.match(base, /readonly property int labelWidth:\s*Theme\.settingsLabelWidth/);
    for (const row of ["SliderRow", "PickerRow", "SwitchRow", "SettingsTextRow"])
        assert.match(read(`Settings/${row}.qml`), /^SettingsRow \{$/m,
            `${row} must build on SettingsRow`);
    assert.doesNotMatch(system, /resetArmed|Confirm reset/);
    assert.match(system, /onTriggered:\s*Settings\.resetAll\(\)/);
});

test("touchpad scroll speed defaults to Hyprland's factor and applies live", () => {
    const settings = read("Common/Settings.qml");
    const helpers = read("Common/SettingsHelpers.js");
    const system = read("Settings/SystemPage.qml");
    const input = fs.readFileSync(path.resolve(shellDir, "../input.lua"), "utf8");

    assert.match(helpers, /scrollFactor:\s*1\.0/);
    assert.match(helpers, /realIn\(parsed\.scrollFactor, 0\.2, 2\.0, 0\.1/);
    assert.match(settings, /"input:touchpad:scroll_factor"/);
    assert.match(system, /min:\s*0\.2[\s\S]*max:\s*2\.0[\s\S]*step:\s*0\.1/);
    assert.match(input, /persisted_scroll_factor\(\)/);
    assert.match(input, /"scrollFactor"%s\*:%s\*\(\[%d%\.\]\+\)/);
    assert.doesNotMatch(input, /scroll_factor\s*=\s*0\.4/);
});

test("the grouped rail adds search, sections, and the rail save state (design 1c)", () => {
    const view = read("Settings/SettingsView.qml");
    const settings = read("Common/Settings.qml");

    assert.match(view, /group:\s*"SHELL"/);
    assert.match(view, /group:\s*"SYSTEM"/);
    assert.match(view, /property string navQuery/);
    assert.match(view, /Search settings/);
    assert.match(view, /id:\s*railFooter/);
    assert.match(view, /Saved · applies live/);
    assert.doesNotMatch(view, /shell-settings\.json/,
        "the config path chip lives on the System page, not a bottom footer");
    assert.match(view, /case "notifications": return notificationsPage;/);
    assert.match(settings, /"notifications", "system"\]/);
});

test("notification settings drive the toasts and the notification center", () => {
    const toasts = read("NotificationToasts.qml");
    const notifs = read("Common/Notifs.qml");
    const page = read("Settings/NotificationsPage.qml");

    assert.match(toasts, /Settings\.notifPosition/);
    assert.match(toasts, /Settings\.notifDensity/);
    assert.match(toasts, /Settings\.notifIcons/);
    assert.match(toasts, /Settings\.notifBodyLines/);
    assert.match(toasts, /showProgress:\s*Settings\.notifProgress && !critical/);
    // A plain array model recreates every delegate when one toast expires,
    // resetting the survivors' countdowns; ScriptModel diffs by identity.
    assert.match(toasts, /model:\s*ScriptModel\s*\{\s*values:\s*Notifs\.toasts\s*\}/);
    assert.doesNotMatch(toasts, /model:\s*Notifs\.toasts/);
    assert.match(notifs, /readonly property bool dnd:\s*Settings\.notifDnd/);
    assert.match(notifs, /toastsSuppressed:\s*dnd \|\| quietActive/);
    assert.match(notifs, /Settings\.notifDuration \* 1000/);
    assert.match(page, /Send test notification/);
    assert.match(page, /Critical alerts ignore the timer/);
    // DND writers must go through the persisted setting, never the singleton.
    for (const name of ["Popovers/NotifsPopover.qml", "Popovers/ControlCenterPopover.qml"])
        assert.doesNotMatch(read(name), /Notifs\.dnd\s*=/,
            `${name} must use Notifs.setDnd`);
});

test("per-module options live under one validated modOpts key", () => {
    const helpers = read("Common/SettingsHelpers.js");
    const settings = read("Common/Settings.qml");

    assert.match(helpers, /function defaultModOpts/);
    assert.match(helpers, /function normalizeModOpts/);
    assert.match(helpers, /modOpts:\s*normalizeModOpts\(parsed\.modOpts\)/);
    assert.match(settings, /"mods", "modOpts"/);
    assert.match(settings, /function setModuleOption/);
    assert.match(settings, /onModOptsChanged:\s*scheduleSave/);
    // The QS_WEATHER_* env vars survive exactly one upgrade as a seed; a file
    // that already carries modOpts must never take them again.
    assert.match(settings, /function seedWeatherFromEnv/);
    assert.match(settings, /parsed\.modOpts !== undefined/);
    assert.doesNotMatch(read("Common/Weather.qml"), /Quickshell\.env\("QS_WEATHER/,
        "Weather must read its location from Settings, not the environment");
});

test("the module cog opens a per-module sub-page inside the Modules page", () => {
    const modules = read("Settings/ModulesPage.qml");
    const view = read("Settings/SettingsView.qml");
    const detail = read("Settings/ModuleDetailView.qml");

    assert.doesNotMatch(modules, /cyclePolicy/,
        "the A/D/C policy cycler is replaced by the cog + sub-page");
    assert.match(modules, /function openSubPage/);
    assert.match(modules, /if \(dragActive\)\s*\n\s*return;/,
        "a drag in progress must not be interrupted by opening a sub-page");
    assert.match(modules, /ModuleDetailView \{/);
    assert.match(modules, /id:\s*cogButton/);
    assert.match(view, /subPageActive \?\? false/,
        "Escape must close an open module sub-page before clearing search");
    assert.match(detail, /Settings\.setModuleDetail\(view\.moduleId/,
        "the detail policy control lives on the sub-page, stored in mods");
    assert.match(detail, /Settings\.setModuleOption/);
});

test("the settings store keeps its fixed literal state path", () => {
    const settings = read("Common/Settings.qml");
    assert.match(settings,
        /Quickshell\.env\("HOME"\) \+ "\/\.local\/state\/quickshell\/shell-settings\.json"/);
    assert.match(settings, /path:\s*root\.filePath/);
    assert.doesNotMatch(settings, /:\s*Quickshell\.statePath\(/,
        "Settings must not use statePath — it forks per config directory");
});

test("an unreadable settings file is preserved before anything saves over it", () => {
    // Regression guard for silent data loss: parse() used to answer null for
    // both "no file yet" and "file we could not read", so applyLoaded treated
    // damage as a first run and the next debounced save replaced the user's
    // only copy with defaults.
    const settings = read("Common/Settings.qml");

    assert.match(settings, /firstRun = result\.status === "empty"/,
        "only an absent file counts as a first run");

    // The backup has to be triggered ahead of applyLoaded's no-op early
    // return, or a corrupt file that merges to the running state slips past.
    const applyLoaded = settings.slice(settings.indexOf("function applyLoaded"));
    const backupAt = applyLoaded.indexOf("backUpCorruptFile()");
    const earlyReturnAt = applyLoaded.indexOf("serialize(snapshot())");
    assert.ok(backupAt > 0, "applyLoaded must back up a corrupt file");
    assert.ok(backupAt < earlyReturnAt,
        "the backup must happen before the unchanged-settings early return");

    assert.match(settings, /"mv", filePath, corruptBackupProc\.backupPath/,
        "the original bytes are moved aside, not rewritten");
    assert.match(settings, /\.corrupt-" \+ Math\.floor\(Date\.now\(\) \/ 1000\)/);

    // Both save paths stay shut until the move has succeeded, and the failure
    // branch must not clear the guard.
    assert.match(settings, /function saveNow\(\) \{\s*\n\s*if \(!ready \|\| corruptBackupPending\)/);
    assert.match(settings,
        /function scheduleSave\(\) \{\s*\n\s*if \(!ready \|\| migrationPending \|\| corruptBackupPending\)/);
    const onExited = settings.slice(settings.indexOf("id: corruptBackupProc"));
    const clears = onExited.slice(0, onExited.indexOf("console.warn"))
        .match(/corruptBackupPending = false/g) ?? [];
    assert.equal(clears.length, 1,
        "corruptBackupPending clears only on a successful move");

    assert.match(settings, /root\.announcement = "The settings file could not be read\./,
        "the user is told the file was kept rather than lost");
});
