pragma Singleton
import QtQuick
import Quickshell

Singleton {
    id: root

    // Palette — design tokens from "Menubar Directions" (2a/3a, t5)
    // Bar islands and their fused popouts share one surface color so the
    // connected shapes read as a single slab (t5).
    // Fully opaque: the fused popout surface hangs over its own drop
    // shadow, and any translucency shows the shadow's edge through the
    // surface as a banded seam under the bar.
    readonly property color barBg: "#131419"
    readonly property color popBg: "#131419"
    readonly property color popBorder: Qt.rgba(1, 1, 1, 0.08)
    readonly property color hairline: Qt.rgba(1, 1, 1, 0.08)
    readonly property color hairlineSoft: Qt.rgba(1, 1, 1, 0.06)
    readonly property color hoverFill: Qt.rgba(1, 1, 1, 0.05)
    readonly property color hoverFillStrong: Qt.rgba(1, 1, 1, 0.09)
    readonly property color activeFill: Qt.rgba(1, 1, 1, 0.07)
    readonly property color cardFill: Qt.rgba(1, 1, 1, 0.04)
    // A link or footer action under the pointer: the accent, lifted.
    readonly property color accentHover: "#c8e2f4"
    // Recessed panel inside a surface — a picker list, a diff pane.
    readonly property color insetSurface: "#1b1c22"

    readonly property color textHi: "#e2e5ec"
    readonly property color textMid: "#c2c6d1"
    // All text tokens meet WCAG AA against barBg/popBg. dotDim is the
    // intentionally decorative exception and must not be used for copy.
    readonly property color textLow: "#9aa0af"
    readonly property color textDim: "#858a99"
    readonly property color textFaint: "#797e8d"
    readonly property color dotDim: "#4a4e5c"
    readonly property color icon: "#a7adbd"

    // Settings-driven: the accent (and its derived fills below) follows the
    // Shell settings accent, which defaults to the original #9ecbeb.
    readonly property color accent: Settings.effectiveAccent
    readonly property color accentFg: "#0e0f13"
    readonly property color red: "#e8837a"
    readonly property color redText: "#ffb3ab"
    readonly property color redBg: Qt.rgba(232 / 255, 131 / 255, 122 / 255, 0.16)
    readonly property color redBgSoft: Qt.rgba(232 / 255, 131 / 255, 122 / 255, 0.08)
    readonly property color redBorder: Qt.rgba(232 / 255, 131 / 255, 122 / 255, 0.35)
    readonly property color amber: "#d3b47e"
    readonly property color amberBg: Qt.rgba(211 / 255, 180 / 255, 126 / 255, 0.14)
    readonly property color amberBgSoft: Qt.rgba(211 / 255, 180 / 255, 126 / 255, 0.08)
    readonly property color amberBorder: Qt.rgba(211 / 255, 180 / 255, 126 / 255, 0.35)
    readonly property color accentBg: Qt.rgba(accent.r, accent.g, accent.b, 0.14)
    readonly property color accentBgSoft: Qt.rgba(accent.r, accent.g, accent.b, 0.09)
    readonly property color connected: "#79b88b"

    // Accent at an arbitrary alpha, for the few fills outside the two
    // standard tints. Tracks the settings accent like accentBg does.
    function accentAlpha(alpha) {
        return Qt.rgba(accent.r, accent.g, accent.b, alpha);
    }

    // Weather icon tints — the one place the bar carries real color, so
    // they stay a shade below full saturation to sit inside the palette.
    readonly property color wxSun: "#e5b558"
    readonly property color wxMoon: "#bfc6da"
    readonly property color wxCloud: "#98a1b5"
    readonly property color wxFog: "#828896"
    readonly property color wxRain: "#6ab0ea"
    readonly property color wxSnow: "#c8e2f5"
    readonly property color wxStorm: "#a992e0"

    // Provider brand colors
    readonly property color brandClaude: "#d97757"
    readonly property color brandCodex: "#4fb8a8"
    readonly property color brandKimi: "#4d6bfe"

    // Typography. fontMenu is settings-driven; the family strings live in
    // SettingsHelpers.FONT_CHOICES so the picker and this token agree.
    readonly property string fontSans: "IBM Plex Sans"
    readonly property string fontMenu: {
        const choice = Settings.fontChoices.find(f => f.id === Settings.font);
        return choice ? choice.family : "OPPO Sans 4.0";
    }
    readonly property string fontMono: "JetBrains Mono"
    readonly property string fontIcon: "JetBrainsMono Nerd Font"

    // Semantic logical-pixel type scale for popovers and larger shell
    // surfaces. The compact menubar has its own optical size below.
    readonly property int fontCaption: 12
    readonly property int fontSecondary: 13
    readonly property int fontBody: 14
    readonly property int fontHeading: 16
    readonly property int fontProminent: 20
    readonly property int fontDisplay: 28
    readonly property int fontHero: 34
    readonly property real proseLineHeight: 1.4

    // The installed IBM Plex and variable OPPO Sans faces map cleanly to
    // these semantic weights.
    readonly property int weightRegular: Font.Normal
    readonly property int weightMedium: Font.Medium
    readonly property int weightSemibold: Font.DemiBold
    readonly property int weightBold: Font.Bold

    readonly property int iconSmall: 12
    readonly property int iconMedium: 16
    readonly property int iconLarge: 20

    // Menubar typography stays compact independently of the roomier popover
    // scale. OPPO Sans supplies tabular figures for values that update in place.
    readonly property int barTextSize: 13
    readonly property int barIconSize: 14
    readonly property var tabularNumberFeatures: ({ "tnum": 1 })

    // Metrics. Bar geometry is settings-driven; the defaults reproduce the
    // original literals (30 / 8 / 12 / 9). Attached (non-floating) bars sit
    // edge-to-edge with square corners.
    readonly property int barHeight: Settings.barHeight
    readonly property int barTopMargin: Settings.floating ? Settings.gap : 0
    readonly property int barSideMargin: Settings.floating ? Settings.gap + 4 : 0
    readonly property int clusterRadius: Settings.floating ? Settings.barRadius : 0
    readonly property int chipRadius: 6
    readonly property int chipHeight: 24
    readonly property int tooltipHeight: 26
    readonly property int popWidth: 400
    readonly property int popWideWidth: 420
    readonly property int t3MinWidth: 320
    readonly property int t3MaxWidth: 520
    readonly property int surfacePadding: 12
    readonly property int controlHeight: 34
    readonly property int settingsControlHeight: 28
    readonly property int rowHeight: 44
    readonly property int tileHeight: 56
    readonly property int calendarCellSize: 32
    readonly property int pickerRowHeight: 40
    readonly property int popRadius: 14
    readonly property int rowRadius: 9

    // The settings row grid: a fixed label column, and the width below which
    // a row stacks its control under its label instead of beside it. The
    // label column widens for the mono menu face. A footnote that belongs to
    // the row above it aligns to the control, at labelWidth + 10.
    readonly property int settingsLabelWidth: Settings.font === "mono" ? 122 : 90
    readonly property int settingsNarrowWidth: 440

    // Switch geometry per surface, for Common/Toggle.qml: `box` is the hit
    // area, `track` the pill drawn centred inside it. The knob always sits
    // 4px inside the track height, so it follows from `track` alone. Popover
    // chrome is the roomy one; settings rows and the compact module list step
    // down from it but keep the same 34×28 target to click at.
    readonly property var switchPopover: ({
        box: Qt.size(44, root.controlHeight),
        track: Qt.size(34, 20)
    })
    readonly property var switchRow: ({
        box: Qt.size(34, root.settingsControlHeight),
        track: Qt.size(26, 14)
    })
    readonly property var switchCompact: ({
        box: Qt.size(34, root.settingsControlHeight),
        track: Qt.size(22, 12)
    })

    // Connected popout motion. The trigger remains in the menubar while the
    // panel expands from its position directly beneath the bar. Spatial
    // motion is intentionally a little slower than opacity so the chrome
    // reads as one continuous surface while copy stays crisp.
    readonly property int popoutTabMinWidth: 104
    readonly property int popoutTabPadding: 24
    readonly property int popoutTabRadius: 17
    readonly property int popoutMotionDuration: 290
    readonly property int popoutCloseDuration: 210
    readonly property int popoutContentFadeDuration: 150
    readonly property int popoutContentRevealDelay: 45
    readonly property var popoutEnterCurve: [0.38, 1.15, 0.22, 1.0, 1.0, 1.0]
    readonly property var popoutExitCurve: [0.4, 0.0, 0.2, 1.0, 1.0, 1.0]

    // Hover/state feedback on bar chips and tooltips.
    readonly property int chipFadeDuration: 120
}
