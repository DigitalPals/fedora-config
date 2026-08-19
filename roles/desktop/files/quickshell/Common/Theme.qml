pragma Singleton
import QtQuick
import Quickshell
import "." as Common
import "SettingsHelpers.js" as SettingsHelpers

// Design tokens for the glass menubar ("QuickShell Menubar" redesign).
//
// Shell surfaces can be translucent over compositor blur or opaque. The
// `dark*` / `light*` literals below are the fixed reference palettes; semantic
// surface tokens choose glass or solid, and semantic color tokens keep views
// from knowing which variant is active.
//
// The opaque colors are also the glass surfaces' contrast references. Solid
// mode draws them through semantic aliases; views never paint them directly.
Singleton {
    id: root

    readonly property bool dark: Settings.themeMode !== "light"
    readonly property bool paletteActive:
        Settings.paletteMode === "wallpaper" && Common.Palette.ready

    // ---- reference surfaces (opaque; used for contrast math) --------------
    readonly property color darkPopBg: "#171526"
    readonly property color lightPopBg: "#eeedf3"
    readonly property color background: paletteActive ? Common.Palette.background
        : dark ? "#100e1c" : "#f7f5fb"
    readonly property color popBg: paletteActive ? Common.Palette.surfaceContainerLow
        : dark ? darkPopBg : lightPopBg
    readonly property color darkMenuBg: "#1a182c"
    readonly property color lightMenuBg: "#fcfcff"
    readonly property color menuBg: paletteActive ? Common.Palette.surfaceContainer
        : dark ? darkMenuBg : lightMenuBg
    // The highest container is the least favorable opaque backdrop for copy:
    // it is lightest in dark mode and darkest in light mode. Calibrating the
    // shared copy colors here keeps one semantic ladder safe on every lower
    // panel, menu, and group surface too.
    readonly property color copyReferenceBg: paletteActive
        ? Common.Palette.surfaceContainerHigh : popBg
    // The bar's opaque reference is independent of the surrounding shell
    // theme for fixed/custom presets. It is also the exact solid-mode fill.
    readonly property color barBg: paletteActive ? Common.Palette.surface
        : Settings.effectiveBarColor

    // ---- glass ------------------------------------------------------------
    // The bar is the lighter glass; panels sit a step denser so copy stays
    // readable over a busy wallpaper.
    readonly property color glass: Qt.rgba(barBg.r, barBg.g, barBg.b,
        dark ? 0.52 : 0.55)
    readonly property color glassStrong: Qt.rgba(popBg.r, popBg.g, popBg.b,
        dark ? 0.72 : 0.80)
    // Menus that float above a panel need to stay legible over it.
    readonly property color glassMenu: Qt.rgba(menuBg.r, menuBg.g, menuBg.b,
        dark ? 0.88 : 0.92)
    // Rendering uses semantic surface tokens. The raw glass colours above
    // remain the translucent variants; disabling glass swaps in opaque
    // references without making nested chip/tile fills opaque.
    readonly property color barSurface: Settings.glassEnabled ? glass : barBg
    readonly property color surfaceStrong: Settings.glassEnabled ? glassStrong : popBg
    readonly property color surfaceMenu: Settings.glassEnabled ? glassMenu : menuBg
    // Full-screen scrims behind the power menu / shortcut sheet.
    readonly property color scrim: dark
        ? Qt.rgba(10 / 255, 8 / 255, 22 / 255, 0.42)
        : Qt.rgba(236 / 255, 236 / 255, 244 / 255, 0.5)

    // Hairlines.
    readonly property color stroke: paletteActive ? Common.Palette.outlineVariant
        : dark ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(1, 1, 1, 0.65)
    readonly property color popBorder: stroke
    readonly property color hairline: stroke
    readonly property color hairlineSoft: paletteActive
        ? Qt.rgba(Common.Palette.outlineVariant.r, Common.Palette.outlineVariant.g,
            Common.Palette.outlineVariant.b, 0.58)
        : dark ? Qt.rgba(1, 1, 1, 0.08)
        : Qt.rgba(24 / 255, 22 / 255, 44 / 255, 0.10)

    // ---- menubar palette -------------------------------------------------
    // A chosen bar colour may deliberately disagree with the shell's global
    // light/dark mode. Derive its own foreground ladder so a white bar in a
    // dark shell (or the reverse) remains readable. The helper floors every
    // copy-bearing step at 4.5:1 against barBg.
    readonly property var barPalette: paletteActive
        ? SettingsHelpers.semanticPalette(barBg.toString(),
            Common.Palette.onSurface.toString(), Common.Palette.onSurfaceVariant.toString())
        : SettingsHelpers.barPalette(Settings.effectiveBarColor)
    readonly property bool barLightForeground:
        SettingsHelpers.relativeLuminance(barPalette.foreground) > 0.5
    readonly property color barTextHi: barPalette.textHi
    readonly property color barTextMid: barPalette.textMid
    readonly property color barTextLow: barPalette.textLow
    readonly property color barTextDim: barPalette.textDim
    readonly property color barTextFaint: barPalette.textFaint
    readonly property color barIcon: barPalette.icon
    readonly property color barDotDim: barLightForeground
        ? Qt.rgba(1, 1, 1, 0.30) : Qt.rgba(0, 0, 0, 0.26)
    readonly property color barWsOccupied: barLightForeground
        ? Qt.rgba(1, 1, 1, 0.72) : Qt.rgba(0, 0, 0, 0.62)
    readonly property color barStroke: paletteActive ? Common.Palette.outlineVariant
        : barLightForeground ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(0, 0, 0, 0.14)
    readonly property color barChip: paletteActive
        ? Qt.rgba(Common.Palette.surfaceContainer.r, Common.Palette.surfaceContainer.g,
            Common.Palette.surfaceContainer.b, 0.52)
        : barLightForeground ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.07)
    readonly property color barChipHover: paletteActive
        ? Qt.rgba(Common.Palette.surfaceContainerHigh.r, Common.Palette.surfaceContainerHigh.g,
            Common.Palette.surfaceContainerHigh.b, 0.72)
        : barLightForeground ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.13)

    readonly property color barAccent: SettingsHelpers.ensureContrast(
        paletteActive ? Common.Palette.primary.toString() : Settings.effectiveAccent,
        barBg.toString(), 4.5)
    readonly property var barAccentPalette: SettingsHelpers.barPalette(
        barAccent.toString())
    readonly property color barAccentFg: paletteActive
        ? SettingsHelpers.ensureContrast(Common.Palette.onPrimary.toString(),
            barAccent.toString(), 4.5) : barAccentPalette.foreground
    readonly property color barAccentGlow: Qt.rgba(
        barAccent.r, barAccent.g, barAccent.b, 0.50)
    readonly property color barRed: SettingsHelpers.ensureContrast(
        barLightForeground ? "#ff8f8f" : "#c22f2f",
        barBg.toString(), 4.5)
    readonly property var barRedPalette: SettingsHelpers.barPalette(barRed)
    readonly property color barRedFg: barRedPalette.foreground
    readonly property color barRedText: barRed
    readonly property color barAmber: SettingsHelpers.ensureContrast(
        barLightForeground ? "#ffc26e" : "#b5761e",
        barBg.toString(), 4.5)
    readonly property var barAmberPalette: SettingsHelpers.barPalette(barAmber)
    readonly property color barAmberFg: barAmberPalette.foreground
    readonly property color barRedBg: Qt.rgba(
        barRedText.r, barRedText.g, barRedText.b, 0.18)
    readonly property color barAmberBg: Qt.rgba(
        barAmber.r, barAmber.g, barAmber.b, barLightForeground ? 0.17 : 0.14)

    readonly property color barWxSun: SettingsHelpers.ensureContrast(
        "#ffc26e", barBg.toString(), 4.5)
    readonly property color barWxMoon: SettingsHelpers.ensureContrast(
        "#bfc6da", barBg.toString(), 4.5)
    readonly property color barWxCloud: SettingsHelpers.ensureContrast(
        barLightForeground ? "#a8b0c4" : "#5c6377",
        barBg.toString(), 4.5)
    readonly property color barWxFog: SettingsHelpers.ensureContrast(
        barLightForeground ? "#949aa8" : "#5f6572",
        barBg.toString(), 4.5)
    readonly property color barWxRain: SettingsHelpers.ensureContrast(
        "#6ab0ea", barBg.toString(), 4.5)
    readonly property color barWxSnow: SettingsHelpers.ensureContrast(
        barLightForeground ? "#c8e2f5" : "#4a8fbe",
        barBg.toString(), 4.5)
    readonly property color barWxStorm: SettingsHelpers.ensureContrast(
        "#a992e0", barBg.toString(), 4.5)

    // ---- fills ------------------------------------------------------------
    // chip: a resting pill inside the bar. chipHover: the same pill lit, and
    // the open/held state. tile: a recessed block inside a panel.
    readonly property color chip: paletteActive
        ? Qt.rgba(Common.Palette.surfaceContainer.r, Common.Palette.surfaceContainer.g,
            Common.Palette.surfaceContainer.b, 0.56)
        : dark ? Qt.rgba(1, 1, 1, 0.08)
        : Qt.rgba(24 / 255, 22 / 255, 44 / 255, 0.07)
    readonly property color chipHover: paletteActive
        ? Qt.rgba(Common.Palette.surfaceContainerHigh.r, Common.Palette.surfaceContainerHigh.g,
            Common.Palette.surfaceContainerHigh.b, 0.74)
        : dark ? Qt.rgba(1, 1, 1, 0.16)
        : Qt.rgba(24 / 255, 22 / 255, 44 / 255, 0.13)
    readonly property color tile: paletteActive
        ? Qt.rgba(Common.Palette.surfaceContainerHigh.r, Common.Palette.surfaceContainerHigh.g,
            Common.Palette.surfaceContainerHigh.b, 0.62)
        : dark ? Qt.rgba(1, 1, 1, 0.09)
        : Qt.rgba(24 / 255, 22 / 255, 44 / 255, 0.06)
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

    readonly property var textPalette: paletteActive
        ? SettingsHelpers.semanticPalette(copyReferenceBg.toString(),
            Common.Palette.onSurface.toString(), Common.Palette.onSurfaceVariant.toString())
        : null
    readonly property color textHi: paletteActive ? textPalette.textHi
        : dark ? darkTextHi : lightTextHi
    readonly property color textMid: paletteActive ? textPalette.textMid
        : dark ? darkTextMid : lightTextMid
    readonly property color textLow: paletteActive ? textPalette.textLow
        : dark ? darkTextLow : lightTextLow
    readonly property color textDim: paletteActive ? textPalette.textDim
        : dark ? darkTextDim : lightTextDim
    readonly property color textFaint: paletteActive ? textPalette.textFaint
        : dark ? darkTextFaint : lightTextFaint
    readonly property color icon: paletteActive ? textPalette.icon
        : dark ? darkIcon : lightIcon
    // Decorative only — empty workspace pips and inactive rails.
    readonly property color dotDim: dark
        ? Qt.rgba(245 / 255, 244 / 255, 251 / 255, 0.30)
        : Qt.rgba(28 / 255, 26 / 255, 46 / 255, 0.26)
    // Copy drawn on top of the accent or on a photographic tile.
    readonly property color textOnAccent: accentFg

    // ---- accent and status -------------------------------------------------
    readonly property color accent: paletteActive ? Common.Palette.primary
        : Settings.effectiveAccent
    readonly property color accentFg: paletteActive
        ? SettingsHelpers.ensureContrast(Common.Palette.onPrimary.toString(),
            accent.toString(), 4.5) : "#ffffff"
    readonly property color accentSoft: paletteActive
        ? Qt.rgba(Common.Palette.primaryContainer.r, Common.Palette.primaryContainer.g,
            Common.Palette.primaryContainer.b, 0.72)
        : Qt.rgba(accent.r, accent.g, accent.b, 0.24)
    readonly property color accentGlow: Qt.rgba(accent.r, accent.g, accent.b, 0.50)
    readonly property color accentBg: accentSoft
    readonly property color accentBgSoft: paletteActive
        ? Qt.rgba(Common.Palette.primaryContainer.r, Common.Palette.primaryContainer.g,
            Common.Palette.primaryContainer.b, 0.42)
        : Qt.rgba(accent.r, accent.g, accent.b, 0.12)
    readonly property color accentHover: Qt.lighter(accent, 1.25)

    readonly property color red: paletteActive ? Common.Palette.errorRole : "#ff6b6b"
    readonly property color redText: paletteActive
        ? SettingsHelpers.ensureContrast(Common.Palette.errorRole.toString(),
            copyReferenceBg.toString(), 4.5) : dark ? "#ff8f8f" : "#c22f2f"
    readonly property color redBg: paletteActive
        ? Qt.rgba(Common.Palette.errorContainer.r, Common.Palette.errorContainer.g,
            Common.Palette.errorContainer.b, 0.68)
        : Qt.rgba(1, 107 / 255, 107 / 255, 0.18)
    readonly property color redBgSoft: paletteActive
        ? Qt.rgba(Common.Palette.errorContainer.r, Common.Palette.errorContainer.g,
            Common.Palette.errorContainer.b, 0.42)
        : Qt.rgba(1, 107 / 255, 107 / 255, 0.10)
    readonly property color redBorder: paletteActive ? Common.Palette.outlineVariant
        : Qt.rgba(1, 107 / 255, 107 / 255, 0.38)

    readonly property color amber: SettingsHelpers.ensureContrast(
        dark ? "#ffc26e" : "#b5761e", copyReferenceBg.toString(), 4.5)
    readonly property color amberBg: dark
        ? Qt.rgba(1, 194 / 255, 110 / 255, 0.17)
        : Qt.rgba(181 / 255, 118 / 255, 30 / 255, 0.14)
    readonly property color amberBgSoft: dark
        ? Qt.rgba(1, 194 / 255, 110 / 255, 0.09)
        : Qt.rgba(181 / 255, 118 / 255, 30 / 255, 0.08)
    readonly property color amberBorder: dark
        ? Qt.rgba(1, 194 / 255, 110 / 255, 0.38)
        : Qt.rgba(181 / 255, 118 / 255, 30 / 255, 0.35)

    readonly property color ok: SettingsHelpers.ensureContrast(
        dark ? "#63d68c" : "#1f9d57", copyReferenceBg.toString(), 4.5)
    readonly property color connected: ok

    // Accent at an arbitrary alpha, for the few fills outside the standard
    // tints. Tracks the settings accent like accentSoft does.
    function accentAlpha(alpha) {
        return Qt.rgba(accent.r, accent.g, accent.b, alpha);
    }

    readonly property real stateHoverOpacity: 0.08
    readonly property real statePressedOpacity: 0.12

    // Weather icon tints — the one place the bar carries real colour, so
    // they stay a shade below full saturation to sit inside the palette.
    readonly property color wxSun: SettingsHelpers.ensureContrast(
        "#ffc26e", copyReferenceBg.toString(), 4.5)
    readonly property color wxMoon: SettingsHelpers.ensureContrast(
        "#bfc6da", copyReferenceBg.toString(), 4.5)
    readonly property color wxCloud: SettingsHelpers.ensureContrast(
        dark ? "#a8b0c4" : "#5c6377", copyReferenceBg.toString(), 4.5)
    readonly property color wxFog: SettingsHelpers.ensureContrast(
        dark ? "#949aa8" : "#5f6572", copyReferenceBg.toString(), 4.5)
    readonly property color wxRain: SettingsHelpers.ensureContrast(
        "#6ab0ea", copyReferenceBg.toString(), 4.5)
    readonly property color wxSnow: SettingsHelpers.ensureContrast(
        dark ? "#c8e2f5" : "#4a8fbe", copyReferenceBg.toString(), 4.5)
    readonly property color wxStorm: SettingsHelpers.ensureContrast(
        "#a992e0", copyReferenceBg.toString(), 4.5)

    // Provider brand colors
    readonly property color brandClaude: SettingsHelpers.ensureContrast(
        "#d97757", copyReferenceBg.toString(), 4.5)
    readonly property color brandCodex: SettingsHelpers.ensureContrast(
        "#4fb8a8", copyReferenceBg.toString(), 4.5)
    readonly property color brandKimi: SettingsHelpers.ensureContrast(
        "#4d6bfe", copyReferenceBg.toString(), 4.5)

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
    // Bar geometry is settings-driven. Hug and attached styles meet the
    // screen edge; floating alone consumes the user's gap and outer radius.
    readonly property int barHeight: Settings.barHeight
    readonly property bool barFloating: Settings.barStyle === "floating"
    readonly property bool barHug: Settings.barStyle === "hug"
    readonly property int barTopMargin: barFloating ? Settings.gap : 0
    readonly property int barSideMargin: barFloating ? Settings.gap : 0
    readonly property int clusterRadius: barFloating ? Settings.barRadius : 0
    readonly property int hugCornerSize: 16
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
