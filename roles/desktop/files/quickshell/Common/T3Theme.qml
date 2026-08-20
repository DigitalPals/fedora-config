pragma Singleton
import QtQuick
import Quickshell
import "SettingsHelpers.js" as SettingsHelpers

// T3 Code keeps its own spacing, radii, and surface hierarchy, but participates
// in the shell's semantic palette. This makes wallpaper and fixed accent
// choices flow into the workspace without making individual T3 views depend on
// shell implementation details.
Singleton {
    id: root

    readonly property bool dark: Theme.dark

    // The roles preserve T3's canvas -> card -> raised-control rhythm while
    // following the active fixed or wallpaper-derived shell colors. Floating
    // controls intentionally retain the shell's glass/solid preference.
    readonly property color canvas: Theme.background
    readonly property color chrome: Theme.background
    readonly property color surface: Theme.popBg
    readonly property color surfaceRaised: Theme.copyReferenceBg
    readonly property color overlay: Theme.menuBg
    readonly property color composerGlass: Theme.surfaceMenu

    readonly property color textPrimary: Theme.textHi
    readonly property color textSecondary: Theme.textMid
    readonly property color textMuted: Theme.textLow
    readonly property color textFaint: Theme.textFaint

    readonly property color border: Theme.hairlineSoft
    readonly property color borderStrong: Theme.stroke
    readonly property color hover: Theme.hoverFill
    readonly property color hoverStrong: Theme.hoverFillStrong

    // Accent is used as both copy (working state, links) and control fill, so
    // lift the selected shell accent to AA against the least favorable T3
    // surface. The paired foreground is independently checked against that
    // adjusted fill. With the current wallpaper palette this turns the former
    // dark blue into the shell's much brighter primary.
    readonly property color accent: SettingsHelpers.ensureContrast(
        Theme.accent.toString(), surfaceRaised.toString(), 4.5)
    readonly property color accentHover: dark
        ? Qt.lighter(accent, 1.14) : Qt.darker(accent, 1.10)
    readonly property color accentForeground: SettingsHelpers.ensureContrast(
        Theme.accentFg.toString(), accent.toString(), 4.5)
    readonly property color link: accent
    readonly property color accentSoft: Theme.accentBg
    readonly property color accentSubtle: Theme.accentBgSoft
    readonly property color focus: Theme.accentGlow

    readonly property color amber: Theme.amber
    readonly property color amberSoft: Theme.amberBgSoft
    readonly property color amberBorder: Theme.amberBorder
    readonly property color red: Theme.redText
    readonly property color redSoft: Theme.redBgSoft
    readonly property color redBorder: Theme.redBorder
    readonly property color success: Theme.ok

    readonly property string fontSans: Theme.fontSans
    readonly property string fontMono: Theme.fontMono
    readonly property var tabularNumberFeatures: Theme.tabularNumberFeatures

    readonly property int outerRadius: 16
    readonly property int composerRadius: 22
    readonly property int panelRadius: 12
    readonly property int rowRadius: 8
    readonly property int controlRadius: 8
    readonly property int pagePadding: 12
    readonly property int headerHeight: 52
    readonly property int footerHeight: 30
    readonly property int activeRowHeight: 58
    readonly property int quietRowHeight: 38
    readonly property int iconButtonSize: 32

    // T3 interactions are deliberately quick. Continuous state animation is
    // duty-cycled at the call site so idle windows do not repaint forever.
    readonly property int fastDuration: 140
    readonly property int normalDuration: 180
}
