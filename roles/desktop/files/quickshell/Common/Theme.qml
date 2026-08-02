pragma Singleton
import QtQuick
import Quickshell

Singleton {
    id: root

    // Palette — design tokens from "Menubar Directions" (2a/3a, t5)
    // Bar islands and their fused popouts share one surface color so the
    // connected shapes read as a single slab (t5).
    readonly property color barBg: Qt.rgba(19 / 255, 20 / 255, 25 / 255, 0.96)
    readonly property color popBg: Qt.rgba(19 / 255, 20 / 255, 25 / 255, 0.96)
    readonly property color popBorder: Qt.rgba(1, 1, 1, 0.08)
    readonly property color hairline: Qt.rgba(1, 1, 1, 0.08)
    readonly property color hairlineSoft: Qt.rgba(1, 1, 1, 0.06)
    readonly property color hoverFill: Qt.rgba(1, 1, 1, 0.05)
    readonly property color hoverFillStrong: Qt.rgba(1, 1, 1, 0.09)
    readonly property color activeFill: Qt.rgba(1, 1, 1, 0.07)
    readonly property color cardFill: Qt.rgba(1, 1, 1, 0.04)

    readonly property color textHi: "#e2e5ec"
    readonly property color textMid: "#c2c6d1"
    readonly property color textLow: "#8b90a0"
    readonly property color textDim: "#6a6f7e"
    readonly property color textFaint: "#5a5e6c"
    readonly property color dotDim: "#4a4e5c"
    readonly property color icon: "#a7adbd"

    readonly property color accent: "#9ecbeb"
    readonly property color accentFg: "#0e0f13"
    readonly property color red: "#e8837a"
    readonly property color redText: "#ffb3ab"
    readonly property color redBg: Qt.rgba(232 / 255, 131 / 255, 122 / 255, 0.16)
    readonly property color redBgSoft: Qt.rgba(232 / 255, 131 / 255, 122 / 255, 0.08)
    readonly property color amber: "#d3b47e"
    readonly property color amberBg: Qt.rgba(211 / 255, 180 / 255, 126 / 255, 0.14)
    readonly property color accentBgSoft: Qt.rgba(158 / 255, 203 / 255, 235 / 255, 0.09)

    // Provider brand colors (from Lumen source)
    readonly property color brandClaude: "#d97757"
    readonly property color brandCodex: "#4fb8a8"
    readonly property color brandKimi: "#4d6bfe"

    // Typography
    readonly property string fontSans: "IBM Plex Sans"
    readonly property string fontMono: "JetBrains Mono"
    readonly property string fontIcon: "JetBrainsMono Nerd Font"

    // Motion — Material 3 curves (as used by caelestia/end-4 quickshells).
    // Spatial: springy enter with slight overshoot; accel: quick exit.
    readonly property var curveSpatial: [0.38, 1.21, 0.22, 1, 1, 1]
    readonly property var curveDecel: [0.05, 0.7, 0.1, 1, 1, 1]
    readonly property var curveAccel: [0.3, 0, 0.8, 0.15, 1, 1]
    readonly property int animOpen: 330
    readonly property int animClose: 140

    // Connected popouts are unanimated: they appear and dismiss instantly.

    // Metrics
    readonly property int barHeight: 34
    readonly property int barTopMargin: 8
    readonly property int barSideMargin: 12
    readonly property int clusterRadius: 11
    readonly property int chipRadius: 7
    readonly property int popWidth: 360
    readonly property int popRadius: 14
    readonly property int rowRadius: 9
}
