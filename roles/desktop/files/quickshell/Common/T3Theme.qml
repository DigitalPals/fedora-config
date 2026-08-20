pragma Singleton
import QtQuick
import Quickshell

// T3 Code's visual language intentionally does not inherit the wallpaper
// palette. The web client uses a quiet neutral canvas with a blue interaction
// colour; keeping those roles local prevents the shell's purple/glass theme
// from flattening the hierarchy inside this one workspace.
Singleton {
    id: root

    readonly property bool dark: Theme.dark

    // Surfaces mirror the stock T3 Code palette. The popout itself is opaque
    // enough to provide stable contrast over any wallpaper; glass is reserved
    // for the composer and floating menus.
    readonly property color canvas: dark ? "#0a0a0a" : "#fcfcfc"
    readonly property color chrome: dark ? "#0a0a0a" : "#ffffff"
    readonly property color surface: dark ? "#111111" : "#ffffff"
    readonly property color surfaceRaised: dark ? "#141414" : "#f4f4f5"
    readonly property color overlay: dark ? "#191919" : "#ffffff"
    readonly property color composerGlass: dark
        ? Qt.rgba(25 / 255, 25 / 255, 25 / 255, 0.94)
        : Qt.rgba(1, 1, 1, 0.96)

    readonly property color textPrimary: dark ? "#f5f5f5" : "#18181b"
    readonly property color textSecondary: dark ? "#d4d4d8" : "#3f3f46"
    readonly property color textMuted: dark ? "#a1a1aa" : "#52525b"
    readonly property color textFaint: dark ? "#818181" : "#71717a"

    readonly property color border: dark
        ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(24 / 255, 24 / 255, 27 / 255, 0.12)
    readonly property color borderStrong: dark
        ? Qt.rgba(1, 1, 1, 0.17) : Qt.rgba(24 / 255, 24 / 255, 27 / 255, 0.20)
    readonly property color hover: dark
        ? Qt.rgba(1, 1, 1, 0.055) : Qt.rgba(24 / 255, 24 / 255, 27 / 255, 0.055)
    readonly property color hoverStrong: dark
        ? Qt.rgba(1, 1, 1, 0.095) : Qt.rgba(24 / 255, 24 / 255, 27 / 255, 0.095)

    readonly property color accent: dark ? "#346bf1" : "#1b4ed8"
    readonly property color accentHover: dark ? "#4b7cf3" : "#1644bf"
    readonly property color accentForeground: "#ffffff"
    readonly property color accentSoft: Qt.rgba(accent.r, accent.g, accent.b,
        dark ? 0.20 : 0.13)
    readonly property color accentSubtle: Qt.rgba(accent.r, accent.g, accent.b,
        dark ? 0.10 : 0.075)
    readonly property color focus: Qt.rgba(accent.r, accent.g, accent.b, 0.72)

    readonly property color amber: dark ? "#f0b849" : "#9a6500"
    readonly property color amberSoft: Qt.rgba(amber.r, amber.g, amber.b,
        dark ? 0.11 : 0.09)
    readonly property color amberBorder: Qt.rgba(amber.r, amber.g, amber.b,
        dark ? 0.26 : 0.22)
    readonly property color red: dark ? "#ff7070" : "#c92a2a"
    readonly property color redSoft: Qt.rgba(red.r, red.g, red.b,
        dark ? 0.11 : 0.08)
    readonly property color redBorder: Qt.rgba(red.r, red.g, red.b,
        dark ? 0.27 : 0.22)
    readonly property color success: dark ? "#54d49b" : "#147d54"

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
