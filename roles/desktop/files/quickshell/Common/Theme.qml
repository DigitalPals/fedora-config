pragma Singleton
import QtQuick
import Quickshell

// Design tokens for the glass menubar ("QuickShell Menubar" redesign).
//
// Every surface in the shell is translucent and sits over the compositor's
// blur, so the palette is expressed as alpha over an unknown backdrop rather
// than as opaque fills. The `dark*` / `light*` literals below are the two
// reference palettes; the semantic tokens under them pick one, which is what
// makes the Control Center's Dark mode switch a one-property flip.
//
// The `*Ref` colors are the opaque equivalents of the glass surfaces over the
// shell's own dimmed wallpaper. Nothing draws them — they exist so contrast
// can be reasoned about (and tested) against a fixed reference instead of
// against whatever photograph happens to be behind the panel.
Singleton {
    id: root

    readonly property bool dark: Settings.themeMode !== "light"

    // ---- reference surfaces (opaque; used for contrast math) --------------
    readonly property color darkPopBg: "#171526"
    readonly property color lightPopBg: "#eeedf3"
    readonly property color popBg: dark ? darkPopBg : lightPopBg
    readonly property color barBg: popBg

    // ---- glass ------------------------------------------------------------
    // The bar is the lighter glass; panels sit a step denser so copy stays
    // readable over a busy wallpaper.
    readonly property color glass: dark
        ? Qt.rgba(22 / 255, 20 / 255, 36 / 255, 0.52)
        : Qt.rgba(1, 1, 1, 0.55)
    readonly property color glassStrong: dark
        ? Qt.rgba(26 / 255, 24 / 255, 44 / 255, 0.72)
        : Qt.rgba(252 / 255, 252 / 255, 255 / 255, 0.80)
    // Menus that float above a panel need to stay legible over it.
    readonly property color glassMenu: dark
        ? Qt.rgba(26 / 255, 24 / 255, 44 / 255, 0.88)
        : Qt.rgba(252 / 255, 252 / 255, 255 / 255, 0.92)
    // Full-screen scrims behind the power menu / shortcut sheet.
    readonly property color scrim: dark
        ? Qt.rgba(10 / 255, 8 / 255, 22 / 255, 0.42)
        : Qt.rgba(236 / 255, 236 / 255, 244 / 255, 0.5)

    // Hairlines. `stroke` is the outer edge, `strokeHi` the inset highlight
    // along the top that gives the glass its lit rim.
    readonly property color stroke: dark
        ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(1, 1, 1, 0.65)
    readonly property color strokeHi: dark
        ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.90)
    readonly property color popBorder: stroke
    readonly property color hairline: stroke
    readonly property color hairlineSoft: dark
        ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(24 / 255, 22 / 255, 44 / 255, 0.10)

    // ---- fills ------------------------------------------------------------
    // chip: a resting pill inside the bar. chipHover: the same pill lit, and
    // the open/held state. tile: a recessed block inside a panel.
    readonly property color chip: dark
        ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(24 / 255, 22 / 255, 44 / 255, 0.07)
    readonly property color chipHover: dark
        ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(24 / 255, 22 / 255, 44 / 255, 0.13)
    readonly property color tile: dark
        ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(24 / 255, 22 / 255, 44 / 255, 0.06)
    // Occupied workspace pips are functional state, not decorative furniture:
    // keep them well above dotDim while the focused pip remains uniquely accent.
    readonly property color wsOccupied: dark
        ? Qt.rgba(1, 1, 1, 0.72) : Qt.rgba(28 / 255, 26 / 255, 46 / 255, 0.62)

    // Legacy aliases, kept so every popover keeps reading one vocabulary.
    readonly property color hoverFill: chip
    readonly property color hoverFillStrong: chipHover
    readonly property color activeFill: chip
    readonly property color cardFill: tile
    readonly property color insetSurface: tile

    // ---- text -------------------------------------------------------------
    // The design's --txt3 lands at 3.2:1 over the panel reference, below the
    // 4.5:1 floor this shell holds itself to. The low three steps are lifted
    // to the lightest value that clears AA and are verified by
    // tests/quickshell/typography.test.cjs; `dotDim` is the one decorative
    // token and must never carry copy.
    readonly property color darkTextHi: "#f5f4fb"
    readonly property color darkTextMid: "#a1a0a9"
    readonly property color darkTextLow: "#8f8e9b"
    readonly property color darkTextDim: "#868593"
    readonly property color darkTextFaint: "#84838f"
    readonly property color darkIcon: "#c3c2cd"

    readonly property color lightTextHi: "#1c1a2e"
    readonly property color lightTextMid: "#4a4860"
    readonly property color lightTextLow: "#5b596f"
    readonly property color lightTextDim: "#605e74"
    readonly property color lightTextFaint: "#63617a"
    readonly property color lightIcon: "#3a3850"

    readonly property color textHi: dark ? darkTextHi : lightTextHi
    readonly property color textMid: dark ? darkTextMid : lightTextMid
    readonly property color textLow: dark ? darkTextLow : lightTextLow
    readonly property color textDim: dark ? darkTextDim : lightTextDim
    readonly property color textFaint: dark ? darkTextFaint : lightTextFaint
    readonly property color icon: dark ? darkIcon : lightIcon
    // Decorative only — empty workspace pips and inactive rails.
    readonly property color dotDim: dark
        ? Qt.rgba(245 / 255, 244 / 255, 251 / 255, 0.30)
        : Qt.rgba(28 / 255, 26 / 255, 46 / 255, 0.26)
    // Copy drawn on top of the accent or on a photographic tile.
    readonly property color textOnAccent: "#ffffff"

    // ---- accent and status -------------------------------------------------
    readonly property color accent: Settings.effectiveAccent
    readonly property color accentFg: "#ffffff"
    readonly property color accentSoft: Qt.rgba(accent.r, accent.g, accent.b, 0.24)
    readonly property color accentGlow: Qt.rgba(accent.r, accent.g, accent.b, 0.50)
    readonly property color accentBg: accentSoft
    readonly property color accentBgSoft: Qt.rgba(accent.r, accent.g, accent.b, 0.12)
    readonly property color accentHover: Qt.lighter(accent, 1.25)

    readonly property color red: "#ff6b6b"
    readonly property color redText: dark ? "#ff8f8f" : "#c22f2f"
    readonly property color redBg: Qt.rgba(1, 107 / 255, 107 / 255, 0.18)
    readonly property color redBgSoft: Qt.rgba(1, 107 / 255, 107 / 255, 0.10)
    readonly property color redBorder: Qt.rgba(1, 107 / 255, 107 / 255, 0.38)

    readonly property color amber: dark ? "#ffc26e" : "#b5761e"
    readonly property color amberBg: dark
        ? Qt.rgba(1, 194 / 255, 110 / 255, 0.17)
        : Qt.rgba(181 / 255, 118 / 255, 30 / 255, 0.14)
    readonly property color amberBgSoft: dark
        ? Qt.rgba(1, 194 / 255, 110 / 255, 0.09)
        : Qt.rgba(181 / 255, 118 / 255, 30 / 255, 0.08)
    readonly property color amberBorder: dark
        ? Qt.rgba(1, 194 / 255, 110 / 255, 0.38)
        : Qt.rgba(181 / 255, 118 / 255, 30 / 255, 0.35)

    readonly property color ok: dark ? "#63d68c" : "#1f9d57"
    readonly property color connected: ok

    // Accent at an arbitrary alpha, for the few fills outside the standard
    // tints. Tracks the settings accent like accentSoft does.
    function accentAlpha(alpha) {
        return Qt.rgba(accent.r, accent.g, accent.b, alpha);
    }

    // Weather icon tints — the one place the bar carries real colour, so
    // they stay a shade below full saturation to sit inside the palette.
    readonly property color wxSun: "#ffc26e"
    readonly property color wxMoon: "#bfc6da"
    readonly property color wxCloud: dark ? "#a8b0c4" : "#5c6377"
    readonly property color wxFog: dark ? "#949aa8" : "#5f6572"
    readonly property color wxRain: "#6ab0ea"
    readonly property color wxSnow: dark ? "#c8e2f5" : "#4a8fbe"
    readonly property color wxStorm: "#a992e0"

    // Provider brand colors
    readonly property color brandClaude: "#d97757"
    readonly property color brandCodex: "#4fb8a8"
    readonly property color brandKimi: "#4d6bfe"

    // ---- typography --------------------------------------------------------
    // fontMenu is settings-driven; the family strings live in
    // SettingsHelpers.FONT_CHOICES so the picker and this token agree.
    readonly property string fontSans: "IBM Plex Sans"
    readonly property string fontMenu: {
        const choice = Settings.fontChoices.find(f => f.id === Settings.font);
        return choice ? choice.family : "Urbanist";
    }
    readonly property string fontMono: "JetBrains Mono"
    // Material Symbols Rounded, installed as a pinned variable font by the
    // apps role. Draw it through Common/Sym.qml rather than by hand: the
    // glyph is selected by ligature name and the fill/weight axes need
    // setting for the icon to read at the intended optical weight.
    readonly property string fontIcon: "Material Symbols Rounded"
    // Retained for the handful of places that still want a Nerd Font glyph
    // (provider marks in prose, the Fedora logo).
    readonly property string fontNerd: "JetBrainsMono Nerd Font"

    // Semantic logical-pixel type scale. The design descends to 8.5px for
    // meta copy; this scale floors at 10 and is verified by the typography
    // test, so the hierarchy is preserved without shipping unreadable text.
    readonly property int fontMicro: 10
    readonly property int fontTiny: 11
    readonly property int fontCaption: 12
    readonly property int fontSecondary: 13
    readonly property int fontBody: 14
    readonly property int fontHeading: 16
    readonly property int fontProminent: 20
    readonly property int fontDisplay: 28
    readonly property int fontHero: 34
    readonly property real proseLineHeight: 1.45

    // Urbanist is a variable face, so every one of these maps to a real
    // instance rather than a synthesised one.
    readonly property int weightRegular: Font.Normal
    readonly property int weightMedium: Font.Medium
    readonly property int weightSemibold: Font.DemiBold
    readonly property int weightBold: Font.Bold
    readonly property int weightHeavy: Font.ExtraBold

    readonly property int iconTiny: 11
    readonly property int iconSmall: 13
    readonly property int iconMedium: 16
    readonly property int iconLarge: 20
    readonly property int iconHero: 27

    // Menubar typography. The bar sets its own optical size independently of
    // the roomier panel scale.
    readonly property int barTextSize: 13
    readonly property int barLabelSize: fontTiny
    readonly property int barIconSize: 16
    readonly property var tabularNumberFeatures: ({ "tnum": 1 })

    // ---- metrics -----------------------------------------------------------
    // Bar geometry is settings-driven; the defaults reproduce the design
    // (46 / 23 / 10). Attached (non-floating) bars sit edge-to-edge with
    // square corners.
    readonly property int barHeight: Settings.barHeight
    readonly property int barTopMargin: Settings.floating ? Settings.gap : 0
    readonly property int barSideMargin: Settings.floating ? Settings.gap : 0
    readonly property int clusterRadius: Settings.floating ? Settings.barRadius : 0
    // Inner gutter either side of the bar's content, and the gap between the
    // three sections.
    readonly property int barPadding: 10
    readonly property int barSpacing: 10

    // Pills. Everything in the bar is a full-radius pill; `chipRadius` stays
    // for the few square-cornered badges.
    readonly property int chipHeight: 32
    readonly property int chipInnerHeight: 26
    readonly property int chipRadius: 6
    readonly property int pillRadius: 999
    readonly property int roundButton: 32
    readonly property int tooltipHeight: 28

    readonly property int popWidth: 392
    readonly property int popWideWidth: 430
    readonly property int t3MinWidth: 360
    readonly property int t3MaxWidth: 520
    readonly property int surfacePadding: 14
    readonly property int controlHeight: 46
    // Inline action pills sit beside copy inside compact cards. They need a
    // smaller target than standalone header, footer and form controls so a
    // two-line tile does not grow or clip when its actions are revealed.
    readonly property int inlineActionHeight: 32
    readonly property int settingsControlHeight: 28
    readonly property int rowHeight: 50
    readonly property int tileHeight: 60
    readonly property int calendarCellSize: 22
    readonly property int pickerRowHeight: 40
    readonly property int popRadius: 28
    readonly property int cardRadius: 20
    readonly property int rowRadius: 16
    readonly property int tileRadius: 16
    // Gap between the bar's inner edge and the top of a panel hanging from it.
    readonly property int popGap: 12

    // The settings row grid: a fixed label column, and the width below which
    // a row stacks its control under its label instead of beside it.
    readonly property int settingsLabelWidth: Settings.font === "mono" ? 122 : 96
    readonly property int settingsNarrowWidth: 440

    // Switch geometry per surface, for Common/Toggle.qml: `box` is the hit
    // area, `track` the pill drawn centred inside it. The knob always sits
    // 4px inside the track height, so it follows from `track` alone.
    readonly property var switchPopover: ({
        box: Qt.size(44, 34),
        track: Qt.size(36, 21)
    })
    readonly property var switchRow: ({
        box: Qt.size(40, root.settingsControlHeight),
        track: Qt.size(36, 21)
    })
    readonly property var switchCompact: ({
        box: Qt.size(36, root.settingsControlHeight),
        track: Qt.size(32, 19)
    })

    // ---- motion ------------------------------------------------------------
    // One spring, used everywhere something moves or resizes; it is the
    // design's cubic-bezier(.34, 1.4, .28, 1) with the slight overshoot that
    // makes the bar feel physical. Colour and opacity never spring — an
    // overshooting fade reads as a flicker — so they use the ease curves.
    readonly property var springCurve: [0.34, 1.4, 0.28, 1.0, 1.0, 1.0]
    readonly property var easeOutCurve: [0.22, 1.0, 0.36, 1.0, 1.0, 1.0]
    readonly property var easeInCurve: [0.4, 0.0, 1.0, 1.0, 1.0, 1.0]

    // Hover tint and other pure colour cross-fades.
    readonly property int chipFadeDuration: 200
    // A control acknowledging a press (scale down and back).
    readonly property int pressDuration: 250
    // Something growing or sliding inside the bar: a revealed tray, a
    // widening workspace pip, the media transport unfolding.
    readonly property int expandDuration: 450
    // Surface-level colour changes — theme switch, accent change.
    readonly property int surfaceDuration: 450
    // A panel entering: the transform springs while opacity eases, so the
    // shape arrives a beat after the content becomes legible.
    readonly property int panelMotionDuration: 550
    readonly property int panelFadeDuration: 320
    readonly property int panelCloseDuration: 260
    // Cross-fade when one panel morphs into another in the same surface.
    readonly property int popoutContentFadeDuration: 180
    readonly property int popoutContentRevealDelay: 40
    // A row entering a list: the per-item stagger and its cap.
    readonly property int staggerStep: 26
    readonly property int staggerMax: 8

    // Retained names for the popout host.
    readonly property int popoutMotionDuration: panelMotionDuration
    readonly property int popoutCloseDuration: panelCloseDuration
    readonly property var popoutEnterCurve: springCurve
    readonly property var popoutExitCurve: easeInCurve
    readonly property int popoutTabMinWidth: 104
    readonly property int popoutTabPadding: 24
    readonly property int popoutTabRadius: 17
}
