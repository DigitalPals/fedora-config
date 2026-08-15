pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "Common"

// The session menu the bar's power button raises.
//
// A full-screen scrim rather than a popover, because every one of these ends
// the session in some way and none of them should be a stray click away. The
// buttons arrive one after another out of the bottom, which is the pause that
// makes an accidental double-click land on nothing.
PanelWindow {
    id: root

    readonly property var actions: [
        { key: "lock", glyph: "lock", label: "Lock", danger: false },
        { key: "suspend", glyph: "bedtime", label: "Suspend", danger: false },
        { key: "logout", glyph: "logout", label: "Log out", danger: false },
        { key: "restart", glyph: "restart_alt", label: "Restart", danger: false },
        { key: "shutdown", glyph: "power_settings_new", label: "Shut down", danger: true }
    ]

    // Kept mapped through the fade-out so the exit animation is visible.
    property bool present: Session.powerOpen

    visible: present || scrim.opacity > 0.01
    screen: Screens.focused
    anchors { top: true; left: true; right: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-power"
    WlrLayershell.keyboardFocus: Session.powerOpen
        ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    HyprlandFocusGrab {
        active: Session.powerOpen
        windows: [root]
        onCleared: Session.closeMenu()
    }

    function trigger(key) {
        switch (key) {
        case "lock": Session.lock(); break;
        case "suspend": Session.suspend(); break;
        case "logout": Session.logout(); break;
        case "restart": Session.reboot(); break;
        case "shutdown": Session.shutdown(); break;
        }
    }

    Rectangle {
        id: scrim
        anchors.fill: parent
        color: Theme.scrim
        opacity: Session.powerOpen ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.panelFadeDuration + 130; easing.type: Easing.OutCubic }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: Session.closeMenu()
        }
    }

    FocusScope {
        id: stage
        anchors.fill: parent
        focus: Session.powerOpen
        opacity: scrim.opacity

        property int selected: 0

        Keys.onEscapePressed: Session.closeMenu()
        Keys.onLeftPressed: selected = (selected + root.actions.length - 1) % root.actions.length
        Keys.onRightPressed: selected = (selected + 1) % root.actions.length
        Keys.onReturnPressed: root.trigger(root.actions[selected].key)
        Keys.onEnterPressed: root.trigger(root.actions[selected].key)

        Connections {
            target: Session

            function onPowerOpenChanged() {
                if (Session.powerOpen)
                    stage.selected = 0;
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 30

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 30

                Repeater {
                    model: root.actions

                    delegate: Column {
                        id: action

                        required property var modelData
                        required property int index
                        readonly property bool current: stage.selected === index
                        readonly property bool lit: current || actionMouse.containsMouse

                        // Staggered out of the bottom: each button lands a
                        // beat after the one before it, which is the pause
                        // that keeps a double-click from reaching one.
                        readonly property int delay: Session.powerOpen
                            ? 60 + index * 70 : 0
                        readonly property real lift: Session.powerOpen ? 0 : 28

                        spacing: 11
                        opacity: Session.powerOpen ? 1 : 0

                        // A Translate rather than `y`: the Row places these,
                        // and writing y would fight the positioner.
                        transform: Translate {
                            y: action.lift

                            Behavior on y {
                                SequentialAnimation {
                                    PauseAnimation { duration: action.delay }
                                    NumberAnimation {
                                        duration: Theme.panelMotionDuration + 50
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Theme.springCurve
                                    }
                                }
                            }
                        }

                        Behavior on opacity {
                            SequentialAnimation {
                                PauseAnimation { duration: action.delay }
                                NumberAnimation {
                                    duration: Theme.panelFadeDuration
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }

                        Rectangle {
                            id: button
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 76
                            height: 76
                            radius: 38
                            color: action.modelData.danger
                                ? (action.lit ? Theme.red : Qt.rgba(1, 99 / 255, 99 / 255, 0.85))
                                : (action.lit ? Theme.chipHover : Theme.glassStrong)
                            border.width: 1
                            border.color: action.current ? Theme.accent
                                : Qt.rgba(1, 1, 1, 0.16)
                            scale: actionMouse.pressed ? 0.92
                                : action.lit ? 1.1 : 1

                            Behavior on color {
                                ColorAnimation { duration: Theme.chipFadeDuration }
                            }

                            Behavior on border.color {
                                ColorAnimation { duration: Theme.chipFadeDuration }
                            }

                            Behavior on scale {
                                NumberAnimation {
                                    duration: Theme.pressDuration + 100
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Theme.springCurve
                                }
                            }

                            Sym {
                                anchors.centerIn: parent
                                name: action.modelData.glyph
                                size: Theme.iconHero
                                color: action.modelData.danger ? Theme.textOnAccent : Theme.textHi
                            }

                            MouseArea {
                                id: actionMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: stage.selected = action.index
                                onClicked: root.trigger(action.modelData.key)
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: action.modelData.label
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.fontCaption
                            font.weight: Theme.weightBold
                            font.letterSpacing: 0.3
                            color: action.lit ? Theme.textHi : Theme.textMid
                        }
                    }
                }
            }

            Rectangle {
                id: cancel
                anchors.horizontalCenter: parent.horizontalCenter
                width: cancelLabel.implicitWidth + 52
                height: 40
                radius: 20
                color: cancelMouse.containsMouse ? Theme.chipHover : Theme.chip
                border.width: 1
                border.color: Theme.stroke
                opacity: Session.powerOpen ? 1 : 0

                // Last in, after every button has landed.
                transform: Translate {
                    y: Session.powerOpen ? 0 : 20

                    Behavior on y {
                        SequentialAnimation {
                            PauseAnimation { duration: Session.powerOpen ? 220 : 0 }
                            NumberAnimation {
                                duration: Theme.panelMotionDuration + 50
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.springCurve
                            }
                        }
                    }
                }

                Behavior on color {
                    ColorAnimation { duration: Theme.chipFadeDuration }
                }

                Behavior on opacity {
                    SequentialAnimation {
                        PauseAnimation { duration: Session.powerOpen ? 220 : 0 }
                        NumberAnimation {
                            duration: Theme.panelFadeDuration
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                Text {
                    id: cancelLabel
                    anchors.centerIn: parent
                    text: "Cancel"
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontCaption
                    font.weight: Theme.weightHeavy
                    font.letterSpacing: 0.4
                    color: Theme.textMid
                }

                MouseArea {
                    id: cancelMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Session.closeMenu()
                }
            }
        }
    }
}
