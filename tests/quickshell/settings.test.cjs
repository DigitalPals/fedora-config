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
    // IslandPopout.qml. Both derive from the registry now, so the registry is
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

test("edge join shortens the mirrored connector without adding a corner cap", () => {
    const host = read("Bar/IslandPopout.qml");
    const mirrored = host.match(/Item \{\s*id: mirrorFrame[\s\S]*?\/\/ The layer-shell input mask/)?.[0] ?? "";

    assert.match(host, /LayoutHelpers\.edgeFlareRadii/);
    assert.match(host, /leftFlareRadius:[\s\S]*?edgeFlares\.left \* bloomProgress/);
    assert.match(host, /rightFlareRadius:[\s\S]*?edgeFlares\.right \* bloomProgress/);
    assert.match(mirrored, /host\.rightFlareRadius/);
    assert.match(mirrored, /host\.leftFlareRadius/);
    assert.doesNotMatch(mirrored, /host\.edgeJoin !== null/);
    assert.match(mirrored, /Shape \{/);
    assert.match(mirrored, /yScale: host\.bottomBar \? -1 : 1/);
});

test("settings exposes responsive output and keyboard contracts", () => {
    const view = read("Settings/SettingsView.qml");
    const host = read("Bar/IslandPopout.qml");
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
    // Which panels fill the body is a registry flag now, not a name test.
    assert.match(host, /fillBody:\s*PanelRegistry\.fillsBody\(host\.slotAName\)/);
    // Settings lays out once at its target size and is revealed by the
    // animating clip; binding it to the clip would relayout every frame.
    assert.match(host, /width:\s*fillBody \? Math\.max\(1, host\.targetBodyW\) : implicitWidth/);
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

test("Idle inhibit and Control Center use the reorderable module pipeline", () => {
    const helpers = read("Common/SettingsHelpers.js");
    const modules = read("Settings/ModulesPage.qml");
    const bar = read("Bar/Bar.qml");

    assert.match(helpers, /"idle", "control"/);
    assert.match(modules, /idle:\s*\{ name: "Idle inhibit"/);
    assert.match(modules, /control:\s*\{ name: "Control Center"/);
    assert.doesNotMatch(modules, /pinnedTail|text:\s*"pinned"/);
    // The modules are files now; the bar maps ids to their sources.
    assert.match(bar, /idle:\s*"Modules\/Idle\.qml"/);
    assert.match(bar, /control:\s*"Modules\/Control\.qml"/);
    assert.match(read("Bar/Modules/Control.qml"), /panelName:\s*"control"/);
    assert.match(read("Bar/Modules/Idle.qml"), /SysInfo\.idleInhibited = !SysInfo\.idleInhibited/);
    assert.doesNotMatch(bar, /togglePopout\("control", "right"/);
});

test("an open Settings panel preserves menubar hover switching", () => {
    const bar = read("Bar/Bar.qml");
    const icon = read("Bar/BarIcon.qml");
    const chip = read("Bar/BarChip.qml");
    const t3 = read("Bar/T3Chip.qml");
    const usage = read("Bar/UsageChips.qml");
    const hoverOpen = bar.match(/function hoverOpen\([\s\S]*?\n    \}/)?.[0] ?? "";

    assert.match(hoverOpen, /!Popouts\.open \|\| Popouts\.currentName === name/);
    assert.match(hoverOpen, /pendingHoverName === name/,
        "pointer motion must not keep restarting the hover-switch delay");
    assert.doesNotMatch(hoverOpen, /currentName === "settings"/,
        "Settings must not disarm the click-once, hover-between-modules interaction");
    assert.match(bar, /onPointChanged:[\s\S]*?barWindow\.hoverPanelAt\(scenePoint\)/,
        "the full-bar handler must route hover motion around stale MouseArea enter state");
    // The scan reads cached rects now; the mapping itself moved into
    // anchorRects(), which is what Object.keys(panelAnchors) drives.
    assert.match(bar, /function hoverPanelAt\(position\)[\s\S]*anchorRects\(\)/);
    assert.match(bar, /function anchorRects\(\)[\s\S]*Object\.keys\(panelAnchors\)/);
    // A stale rect sends hover to the wrong module, so every way the
    // layout can move must drop the cache.
    for (const site of [/function registerPanel[\s\S]{0,120}?invalidateAnchorRects\(\)/,
                        /function unregisterPanel[\s\S]{0,160}?invalidateAnchorRects\(\)/,
                        /function recomputeFit\(\) \{\s*invalidateAnchorRects\(\)/,
                        // Folded into the handler that already restarts the fit
                        // pass — a second onWidthChanged on the same object is a
                        // load failure, which duplicate-handlers.test.cjs guards.
                        /onWidthChanged: \{[\s\S]{0,300}?invalidateAnchorRects\(\)/,
                        /onCenterShiftChanged: invalidateAnchorRects\(\)/])
        assert.match(bar, site, `anchor cache invalidation missing: ${site}`);
    // Every type that owns a module hover surface. Bar.qml is not one of
    // them any more — the clock, media and weather chips it used to build
    // inline are BarChips now, and BarChip carries the recovery for all
    // three. Bar.qml's own full-bar fallback is asserted above.
    for (const source of [icon, chip, t3, usage])
        assert.match(source,
            /onPositionChanged:[\s\S]{0,200}?(hoverOpen|hoverIn|entered|chipEntered)/,
            "module hover must recover when a mapped popout costs Qt an enter event");
    assert.doesNotMatch(bar, /MouseArea\s*\{[^}]*hoverEnabled[^}]*onEntered:\s*barWindow\.hoverOpen/,
        "bar modules should hover through BarIcon/BarChip, not their own MouseArea");
});

test("T3 Code and grouped model usage are separate reorderable modules", () => {
    const helpers = read("Common/SettingsHelpers.js");
    const modules = read("Settings/ModulesPage.qml");
    const bar = read("Bar/Bar.qml");

    assert.match(helpers, /"t3", "usage", "vol"/,
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

test("the full-bar hover fallback resolves the provider before active Usage", () => {
    const bar = read("Bar/Bar.qml");
    const usage = read("Bar/UsageChips.qml");
    const hoverAt = bar.match(/function hoverPanelAt\(position\)[\s\S]*?\n    \}/)?.[0] ?? "";

    assert.match(usage, /function providerAtScenePoint\(scenePoint\)/);
    assert.match(usage, /mapFromItem\(null, scenePoint\.x, scenePoint\.y\)/,
        "provider hit-testing must use the same scene coordinates as bar anchors");
    assert.match(hoverAt, /providerAtScenePoint\(position\)/);
    assert.ok(hoverAt.indexOf("providerAtScenePoint(position)")
            < hoverAt.indexOf('Popouts.currentName === "usage"'),
        "provider selection must happen before treating Usage as the active panel");
    assert.match(hoverAt, /Usage\.selected = provider/);
    assert.match(bar, /interval:\s*120/,
        "switching from a different popout should retain the standard delay");
    assert.match(read("Bar/Modules/Usage.qml"),
        /Popouts\.openPanel\("usage", usageModule\.isle,[\s\S]*?anchorOf\(usageChips\)\)/,
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
        /barWindow\.tooltipPointerPosition = scenePoint/,
        "the full-bar handler must publish pointer motion for tooltip validation");
    assert.match(tooltip, /readonly property bool activeHover:\s*hovered && pointerOverTarget/);
    // The bar reaches the tooltip as a typed `host` now, not through
    // Window.window — an attached window is a plain QQuickWindow to the
    // type system, so that read could never be checked.
    assert.match(tooltip, /property Bar host/,
        "the tooltip must take the bar as a typed property");
    assert.match(tooltip,
        /if \(!root\.host\.tooltipPointerInside \|\| !root\.parent\)\s*return false/,
        "a stale local MouseArea must not keep a tooltip visible after leaving the bar");
    // Match code, not prose: the file explains in a comment why it stopped
    // using Window.window.
    const tooltipCode = tooltip.split("\n").filter(l => !l.trim().startsWith("//")).join("\n");
    assert.doesNotMatch(tooltipCode, /Window\.window/,
        "reading the bar off the attached window is what made this unverifiable");
});

test("schema three adds detail policies and a configurable wallpaper folder", () => {
    const helpers = read("Common/SettingsHelpers.js");
    assert.match(helpers, /var VERSION = 3/);
    assert.match(helpers, /"t3", "usage", "vol"/);
    assert.match(helpers, /warmth:\s*3400/);
    assert.match(helpers, /osd:\s*"top"/);
    assert.match(helpers, /mod\("media", false\)/);
    assert.match(helpers, /mod\("bt", false\)/);
    assert.match(helpers, /wallDir:\s*"~\/Pictures\/Wallpapers"/);
    assert.match(helpers, /DETAIL_POLICIES/);
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
        /readonly property int settingsLabelWidth:\s*Settings\.font === "mono" \? 122 : 90/);
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
