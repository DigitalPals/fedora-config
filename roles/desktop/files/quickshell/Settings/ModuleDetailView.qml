pragma ComponentBehavior: Bound
import QtQuick
import "../Common"

// Per-widget settings sub-page, opened by the cog on a Widgets-page row.
// The detail policy control lives here (storage stays in Settings.mods);
// everything else reads and writes Settings.modOpts through setModuleOption.
SettingsPage {
    id: view

    required property string moduleId
    required property string moduleName
    property bool hasDetail: false
    signal backRequested()

    readonly property var opts: Settings.modOpts[moduleId] ?? ({})
    readonly property var optDefaults: Settings.defaults.modOpts[moduleId] ?? ({})
    readonly property var modEntry: {
        const mods = Settings.mods;
        for (const col of ["left", "center", "right"]) {
            const hit = mods[col].find(m => m.id === view.moduleId);
            if (hit)
                return hit;
        }
        return { detail: "auto" };
    }

    function focusFirst() {
        backAction.forceActiveFocus();
    }

    function optDirty(key) {
        return view.opts[key] !== view.optDefaults[key];
    }

    function setOpt(key, value) {
        Settings.setModuleOption(view.moduleId, key, value);
    }

    function resetOpt(key) {
        Settings.setModuleOption(view.moduleId, key, view.optDefaults[key]);
    }

    function setNumericOpt(key, text) {
        if (text.trim() !== "")
            setOpt(key, Number(text));
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 8

        Row {
            spacing: 8

            SettingsAction {
                id: backAction
                text: "All widgets"
                glyph: "arrow_back"
                Accessible.name: "Back to all widgets"
                onTriggered: view.backRequested()
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: view.moduleName
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontSecondary
                font.weight: Theme.weightSemibold
                color: Theme.textHi
            }
        }

        SectionHeader {
            label: "OPTIONS"
        }

        PickerRow {
            visible: view.hasDetail
            width: parent.width
            label: "Detail"
            model: [
                { value: "auto", label: "Auto" },
                { value: "prefer", label: "Prefer detail" },
                { value: "compact", label: "Always compact" }
            ]
            current: view.modEntry.detail
            dirty: view.modEntry.detail !== "auto"
            onPicked: value => Settings.setModuleDetail(view.moduleId, value)
            onResetRequested: Settings.setModuleDetail(view.moduleId, "auto")
        }

        Loader {
            width: parent.width
            sourceComponent: {
                switch (view.moduleId) {
                case "ws": return wsOptions;
                case "media": return mediaOptions;
                case "indicators": return indicatorsOptions;
                case "clock": return clockOptions;
                case "weather": return weatherOptions;
                case "t3": return t3Options;
                case "hermes": return hermesOptions;
                case "usage": return usageOptions;
                case "gh": return ghOptions;
                case "vol": return volOptions;
                case "batt": return battOptions;
                case "updates": return updatesOptions;
                case "tray": return trayOptions;
                default: return null;
                }
            }
        }
    }

    Component {
        id: indicatorsOptions

        Column {
            spacing: 8

            PickerRow {
                width: parent.width
                label: "Visibility"
                model: [
                    { value: "hover", label: "Hover" },
                    { value: "always", label: "Always show" }
                ]
                current: view.opts.mode
                dirty: view.optDirty("mode")
                onPicked: value => view.setOpt("mode", value)
                onResetRequested: view.resetOpt("mode")
            }
        }
    }

    Component {
        id: wsOptions

        Column {
            spacing: 8

            SliderRow {
                width: parent.width
                label: "Min slots"
                min: 1
                max: 10
                step: 1
                value: view.opts.minSlots
                unit: ""
                dirty: view.optDirty("minSlots")
                onMoved: value => view.setOpt("minSlots", value)
                onResetRequested: view.resetOpt("minSlots")
            }

            SwitchRow {
                width: parent.width
                label: "Hide empty"
                description: "Only show workspaces that have windows"
                checked: view.opts.hideEmpty
                dirty: view.optDirty("hideEmpty")
                onToggled: value => view.setOpt("hideEmpty", value)
                onResetRequested: view.resetOpt("hideEmpty")
            }

            PickerRow {
                width: parent.width
                label: "Style"
                model: [
                    { value: "numbers", label: "Numbers" },
                    { value: "dots", label: "Dots" }
                ]
                current: view.opts.style
                dirty: view.optDirty("style")
                onPicked: value => view.setOpt("style", value)
                onResetRequested: view.resetOpt("style")
            }
        }
    }

    Component {
        id: mediaOptions

        Column {
            spacing: 8

            PickerRow {
                width: parent.width
                label: "Title"
                model: [
                    { value: "title-artist", label: "Title — Artist" },
                    { value: "title", label: "Title" },
                    { value: "artist-title", label: "Artist — Title" }
                ]
                current: view.opts.titleFormat
                dirty: view.optDirty("titleFormat")
                onPicked: value => view.setOpt("titleFormat", value)
                onResetRequested: view.resetOpt("titleFormat")
            }

            SliderRow {
                width: parent.width
                label: "Max width"
                min: 120
                max: 360
                step: 20
                value: view.opts.maxWidth
                dirty: view.optDirty("maxWidth")
                onMoved: value => view.setOpt("maxWidth", value)
                onResetRequested: view.resetOpt("maxWidth")
            }
        }
    }

    Component {
        id: clockOptions

        Column {
            spacing: 8

            SwitchRow {
                width: parent.width
                label: "Seconds"
                description: "Tick every second instead of every minute"
                checked: view.opts.seconds
                dirty: view.optDirty("seconds")
                onToggled: value => view.setOpt("seconds", value)
                onResetRequested: view.resetOpt("seconds")
            }

            SwitchRow {
                width: parent.width
                label: "Date"
                description: "Show the date next to the time"
                checked: view.opts.showDate
                dirty: view.optDirty("showDate")
                onToggled: value => view.setOpt("showDate", value)
                onResetRequested: view.resetOpt("showDate")
            }

            PickerRow {
                width: parent.width
                label: "Date format"
                model: ["ddd dd", "ddd d MMM", "dd MMM", "dd-MM"].map(fmt =>
                    ({ value: fmt, label: Qt.formatDateTime(new Date(), fmt) }))
                current: view.opts.dateFormat
                dirty: view.optDirty("dateFormat")
                onPicked: value => view.setOpt("dateFormat", value)
                onResetRequested: view.resetOpt("dateFormat")
            }

            SwitchRow {
                width: parent.width
                label: "Events"
                description: "Show upcoming system-calendar events in the popover"
                checked: view.opts.showEvents
                dirty: view.optDirty("showEvents")
                onToggled: value => view.setOpt("showEvents", value)
                onResetRequested: view.resetOpt("showEvents")
            }

            SliderRow {
                visible: view.opts.showEvents
                width: parent.width
                label: "Look ahead"
                min: 1
                max: 31
                step: 1
                value: view.opts.daysAhead
                unit: value === 1 ? "day" : "days"
                valueWidth: 62
                dirty: view.optDirty("daysAhead")
                onMoved: value => view.setOpt("daysAhead", value)
                onResetRequested: view.resetOpt("daysAhead")
            }

            SliderRow {
                visible: view.opts.showEvents
                width: parent.width
                label: "Refresh"
                min: 5
                max: 60
                step: 5
                value: view.opts.pollMins
                unit: "min"
                dirty: view.optDirty("pollMins")
                onMoved: value => view.setOpt("pollMins", value)
                onResetRequested: view.resetOpt("pollMins")
            }

            SettingsAction {
                visible: view.opts.showEvents
                text: "Online accounts"
                glyph: "manage_accounts"
                onTriggered: Calendar.manageAccounts()
            }

            Text {
                width: parent.width
                leftPadding: Theme.settingsLabelWidth
                text: "12/24-hour time is set on the System page. Google sign-in is handled by GNOME Online Accounts; credentials never enter Quickshell."
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontCaption
                color: Theme.textDim
                wrapMode: Text.Wrap
            }
        }
    }

    Component {
        id: weatherOptions

        Column {
            spacing: 8

            SettingsTextRow {
                width: parent.width
                label: "Place"
                value: view.opts.place
                placeholder: "Shown on the chip and popover"
                dirty: view.optDirty("place")
                onCommitted: text => view.setOpt("place", text)
                onResetRequested: view.resetOpt("place")
            }

            SettingsTextRow {
                width: parent.width
                label: "Latitude"
                numeric: true
                value: String(view.opts.lat)
                dirty: view.optDirty("lat")
                onCommitted: text => view.setNumericOpt("lat", text)
                onResetRequested: view.resetOpt("lat")
            }

            SettingsTextRow {
                width: parent.width
                label: "Longitude"
                numeric: true
                value: String(view.opts.lon)
                dirty: view.optDirty("lon")
                onCommitted: text => view.setNumericOpt("lon", text)
                onResetRequested: view.resetOpt("lon")
            }

            SliderRow {
                width: parent.width
                label: "Update every"
                min: 5
                max: 60
                step: 5
                value: view.opts.pollMins
                unit: "min"
                dirty: view.optDirty("pollMins")
                onMoved: value => view.setOpt("pollMins", value)
                onResetRequested: view.resetOpt("pollMins")
            }
        }
    }

    Component {
        id: t3Options

        Column {
            spacing: 8

            SwitchRow {
                width: parent.width
                label: "Status label"
                description: "Show the waiting/running word on the chip"
                checked: view.opts.showLabel
                dirty: view.optDirty("showLabel")
                onToggled: value => view.setOpt("showLabel", value)
                onResetRequested: view.resetOpt("showLabel")
            }
        }
    }

    Component {
        id: usageOptions

        Column {
            spacing: 8

            PickerRow {
                width: parent.width
                label: "Usage source"
                model: [
                    { value: "cliproxy", label: "CLIProxyAPI" },
                    { value: "direct", label: "Provider CLIs" }
                ]
                current: view.opts.source
                dirty: view.optDirty("source")
                onPicked: value => view.setOpt("source", value)
                onResetRequested: view.resetOpt("source")
            }

            SettingsTextRow {
                visible: view.opts.source === "cliproxy"
                width: parent.width
                minimumLabelWidth: 126
                label: "Management URL"
                value: view.opts.cliproxyUrl
                placeholder: "https://host:8317/management.html"
                dirty: view.optDirty("cliproxyUrl")
                onCommitted: text => view.setOpt("cliproxyUrl", text)
                onResetRequested: view.resetOpt("cliproxyUrl")
            }

            SwitchRow {
                visible: view.opts.source === "cliproxy"
                width: parent.width
                label: "Verify TLS"
                description: "Require a certificate trusted by this computer"
                checked: view.opts.cliproxyTlsVerify
                dirty: view.optDirty("cliproxyTlsVerify")
                onToggled: value => view.setOpt("cliproxyTlsVerify", value)
                onResetRequested: view.resetOpt("cliproxyTlsVerify")
            }

            SettingsTextRow {
                visible: view.opts.source === "cliproxy"
                width: parent.width
                minimumLabelWidth: 126
                label: "Management key"
                value: ""
                placeholder: Usage.cliproxyKeyConfigured
                    ? "Configured — enter to replace" : "Required"
                secret: true
                dirty: Usage.cliproxyKeyConfigured
                onCommitted: text => Usage.saveCliProxyKey(text)
                onResetRequested: Usage.clearCliProxyKey()
            }

            Text {
                visible: view.opts.source === "cliproxy"
                width: parent.width
                text: Usage.credentialBusy ? "Checking private key…"
                    : Usage.credentialError ? Usage.credentialError
                    : Usage.cliproxyKeyConfigured
                        ? "Key stored privately; it is not saved in shell settings."
                        : "A CLIProxyAPI management key is required."
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontMicro
                color: Usage.credentialError ? Theme.redText : Theme.textFaint
                wrapMode: Text.Wrap
            }

            SwitchRow {
                width: parent.width
                label: "Claude"
                checked: view.opts.claude
                dirty: view.optDirty("claude")
                onToggled: value => view.setOpt("claude", value)
                onResetRequested: view.resetOpt("claude")
            }

            SwitchRow {
                visible: view.opts.source === "direct"
                width: parent.width
                label: "Keep Claude signed in"
                description: "Let Claude Code refresh its saved login for usage checks"
                checked: view.opts.claudeAutoRefresh
                dirty: view.optDirty("claudeAutoRefresh")
                onToggled: value => view.setOpt("claudeAutoRefresh", value)
                onResetRequested: view.resetOpt("claudeAutoRefresh")
            }

            SwitchRow {
                width: parent.width
                label: "Codex"
                checked: view.opts.codex
                dirty: view.optDirty("codex")
                onToggled: value => view.setOpt("codex", value)
                onResetRequested: view.resetOpt("codex")
            }

            SwitchRow {
                width: parent.width
                label: "Kimi"
                checked: view.opts.kimi
                dirty: view.optDirty("kimi")
                onToggled: value => view.setOpt("kimi", value)
                onResetRequested: view.resetOpt("kimi")
            }

            SwitchRow {
                width: parent.width
                label: "xAI / Grok"
                description: view.opts.source === "cliproxy"
                    ? "Show Grok quota when CLIProxyAPI exposes a percentage"
                    : "Grok usage requires the CLIProxyAPI source"
                checked: view.opts.xai
                dirty: view.optDirty("xai")
                onToggled: value => view.setOpt("xai", value)
                onResetRequested: view.resetOpt("xai")
            }

            SliderRow {
                width: parent.width
                label: "Warn below"
                min: 10
                max: 50
                step: 5
                value: view.opts.warnAt
                unit: "%"
                dirty: view.optDirty("warnAt")
                onMoved: value => view.setOpt("warnAt", value)
                onResetRequested: view.resetOpt("warnAt")
            }

            SliderRow {
                width: parent.width
                label: "Critical below"
                min: 5
                max: 25
                step: 5
                value: view.opts.critAt
                unit: "%"
                dirty: view.optDirty("critAt")
                onMoved: value => view.setOpt("critAt", value)
                onResetRequested: view.resetOpt("critAt")
            }
        }
    }

    Component {
        id: hermesOptions

        Column {
            spacing: 8

            SwitchRow {
                width: parent.width
                label: "Status label"
                description: "Show Hermes activity beside its icon"
                checked: view.opts.showLabel
                dirty: view.optDirty("showLabel")
                onToggled: value => view.setOpt("showLabel", value)
                onResetRequested: view.resetOpt("showLabel")
            }

            PickerRow {
                width: parent.width
                label: "Activity detail"
                model: [
                    { value: "full", label: "Full detail" },
                    { value: "verb", label: "Verb only" },
                    { value: "generic", label: "Working only" }
                ]
                current: view.opts.activityDetail
                dirty: view.optDirty("activityDetail")
                onPicked: value => view.setOpt("activityDetail", value)
                onResetRequested: view.resetOpt("activityDetail")
            }
        }
    }

    Component {
        id: ghOptions

        Column {
            id: githubRows

            // "Recent account repos" is intentionally descriptive and wider
            // than the shared compact label column. Keep this group aligned
            // while reserving enough room that the label cannot cover a track.
            readonly property int optionLabelWidth: 156

            spacing: 8

            PickerRow {
                width: parent.width
                minimumLabelWidth: githubRows.optionLabelWidth
                label: "Badge"
                model: [
                    { value: "dot", label: "Dot" },
                    { value: "count", label: "Count" },
                    { value: "off", label: "Off" }
                ]
                current: view.opts.badge
                dirty: view.optDirty("badge")
                onPicked: value => view.setOpt("badge", value)
                onResetRequested: view.resetOpt("badge")
            }

            SliderRow {
                width: parent.width
                minimumLabelWidth: githubRows.optionLabelWidth
                label: "Recent account repos"
                min: 3
                max: 15
                step: 1
                value: view.opts.repos
                unit: ""
                dirty: view.optDirty("repos")
                onMoved: value => view.setOpt("repos", value)
                onResetRequested: view.resetOpt("repos")
            }

            SliderRow {
                width: parent.width
                minimumLabelWidth: githubRows.optionLabelWidth
                label: "Repo refresh"
                min: 1
                max: 30
                step: 1
                value: view.opts.pollMins
                unit: "min"
                dirty: view.optDirty("pollMins")
                onMoved: value => view.setOpt("pollMins", value)
                onResetRequested: view.resetOpt("pollMins")
            }

            SwitchRow {
                width: parent.width
                minimumLabelWidth: githubRows.optionLabelWidth
                label: "CI reports"
                description: "Workflow rows in the Inbox for recent and watched repositories"
                checked: view.opts.ciActivity
                dirty: view.optDirty("ciActivity")
                onToggled: value => view.setOpt("ciActivity", value)
                onResetRequested: view.resetOpt("ciActivity")
            }

            SwitchRow {
                width: parent.width
                minimumLabelWidth: githubRows.optionLabelWidth
                label: "Toasts"
                description: "Watched pushes and failed/action-required workflows"
                checked: view.opts.toasts
                dirty: view.optDirty("toasts")
                onToggled: value => view.setOpt("toasts", value)
                onResetRequested: view.resetOpt("toasts")
            }

            // The account card and the watch list: the one block of module
            // options that is not a value row.
            GitHubWatchList {
                width: parent.width
            }
        }
    }

    Component {
        id: volOptions

        Column {
            spacing: 8

            SliderRow {
                width: parent.width
                label: "Scroll step"
                min: 1
                max: 10
                step: 1
                value: view.opts.step
                unit: "%"
                dirty: view.optDirty("step")
                onMoved: value => view.setOpt("step", value)
                onResetRequested: view.resetOpt("step")
            }

            SwitchRow {
                width: parent.width
                label: "Percentage"
                description: "Show the volume number next to the icon"
                checked: view.opts.showPct
                dirty: view.optDirty("showPct")
                onToggled: value => view.setOpt("showPct", value)
                onResetRequested: view.resetOpt("showPct")
            }

            PickerRow {
                width: parent.width
                label: "Middle click"
                model: [
                    { value: "mute", label: "Mute" },
                    { value: "none", label: "Nothing" }
                ]
                current: view.opts.middleClick
                dirty: view.optDirty("middleClick")
                onPicked: value => view.setOpt("middleClick", value)
                onResetRequested: view.resetOpt("middleClick")
            }
        }
    }

    Component {
        id: battOptions

        Column {
            spacing: 8

            SwitchRow {
                width: parent.width
                label: "Percentage"
                description: "Show the charge number next to the icon"
                checked: view.opts.showPct
                dirty: view.optDirty("showPct")
                onToggled: value => view.setOpt("showPct", value)
                onResetRequested: view.resetOpt("showPct")
            }

            SliderRow {
                width: parent.width
                label: "Amber below"
                min: 10
                max: 40
                step: 5
                value: view.opts.warnAt
                unit: "%"
                dirty: view.optDirty("warnAt")
                onMoved: value => view.setOpt("warnAt", value)
                onResetRequested: view.resetOpt("warnAt")
            }

            SliderRow {
                width: parent.width
                label: "Alert below"
                min: 5
                max: 20
                step: 5
                value: view.opts.critAt
                unit: "%"
                dirty: view.optDirty("critAt")
                onMoved: value => view.setOpt("critAt", value)
                onResetRequested: view.resetOpt("critAt")
            }
        }
    }

    Component {
        id: updatesOptions

        Column {
            spacing: 8

            SliderRow {
                width: parent.width
                label: "Check every"
                min: 10
                max: 240
                step: 10
                value: view.opts.pollMins
                unit: " min"
                dirty: view.optDirty("pollMins")
                onMoved: value => view.setOpt("pollMins", value)
                onResetRequested: view.resetOpt("pollMins")
            }

            SwitchRow {
                width: parent.width
                label: "Include Flatpak"
                checked: view.opts.flatpak
                dirty: view.optDirty("flatpak")
                onToggled: value => view.setOpt("flatpak", value)
                onResetRequested: view.resetOpt("flatpak")
            }

            SwitchRow {
                width: parent.width
                label: "Notify when updates appear"
                checked: view.opts.notify
                dirty: view.optDirty("notify")
                onToggled: value => view.setOpt("notify", value)
                onResetRequested: view.resetOpt("notify")
            }
        }
    }

    Component {
        id: trayOptions

        Column {
            spacing: 8

            SwitchRow {
                width: parent.width
                label: "Start expanded"
                checked: view.opts.expanded
                dirty: view.optDirty("expanded")
                onToggled: value => view.setOpt("expanded", value)
                onResetRequested: view.resetOpt("expanded")
            }
        }
    }
}
