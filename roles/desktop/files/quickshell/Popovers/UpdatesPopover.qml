pragma ComponentBehavior: Bound
import QtQuick
import "../Common"

// Pending updates, and the one button that installs them.
//
// The upgrade is not run inside the shell: it needs a password and it prints a
// transaction worth reading, so the button opens a terminal and this panel
// steps back. What it owns is the count, where the count came from, and how
// stale it is.
Surface {
    id: root

    implicitWidth: 340
    spacing: 10

    readonly property var rows: {
        const out = [];
        if (Updates.dnfCount > 0)
            out.push({
                key: "dnf",
                glyph: "terminal",
                name: "System · dnf",
                sub: Updates.namesLabel(Updates.dnfNames, Updates.dnfCount),
                count: Updates.dnfCount
            });
        if (Updates.flatpakCount > 0)
            out.push({
                key: "flatpak",
                glyph: "widgets",
                name: "Flatpak",
                sub: Updates.namesLabel(Updates.flatpakNames, Updates.flatpakCount),
                count: Updates.flatpakCount
            });
        return out;
    }

    // ---- header ----------------------------------------------------------
    Row {
        width: parent.width
        spacing: 9

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 32
            height: 32
            radius: 11
            color: Theme.accentSoft

            Sym {
                anchors.centerIn: parent
                name: "deployed_code_update"
                size: Theme.iconMedium
                symWeight: 600
                color: Theme.accent
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 32 - refreshButton.width - parent.spacing * 2
            spacing: 1

            Text {
                width: parent.width
                text: "Updates"
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontSecondary
                font.weight: Theme.weightHeavy
                color: Theme.textHi
            }

            Text {
                width: parent.width
                text: Updates.busy ? "Checking…"
                    : Updates.error !== "" ? Updates.error
                    : Updates.checkedLabel() + " · every "
                        + Settings.modOpts.updates.pollMins + " m"
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontMicro
                font.weight: Theme.weightSemibold
                color: Updates.error !== "" ? Theme.redText : Theme.textFaint
                elide: Text.ElideRight
            }
        }

        Rectangle {
            id: refreshButton

            anchors.verticalCenter: parent.verticalCenter
            width: 32
            height: 32
            radius: 10
            enabled: !Updates.busy
            opacity: enabled ? 1 : 0.45
            color: refreshMouse.containsMouse && enabled
                ? Theme.hoverFillStrong : Theme.chip
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: Updates.busy ? "Checking for updates" : "Check for updates"
            Accessible.onPressAction: {
                if (enabled)
                    Updates.check();
            }

            Keys.onPressed: event => {
                if (enabled && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                        || event.key === Qt.Key_Space)) {
                    Updates.check();
                    event.accepted = true;
                }
            }

            Sym {
                anchors.centerIn: parent
                name: "refresh"
                size: Theme.iconSmall + 1
                color: Updates.busy ? Theme.accent : Theme.textMid
            }

            MouseArea {
                id: refreshMouse
                anchors.fill: parent
                enabled: parent.enabled
                hoverEnabled: true
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    refreshButton.forceActiveFocus();
                    Updates.check();
                }
            }
        }
    }

    // ---- what is pending --------------------------------------------------
    Column {
        width: parent.width
        spacing: 6

        Repeater {
            model: root.rows

            delegate: Rectangle {
                id: row

                required property var modelData

                width: parent.width
                height: 50
                radius: Theme.tileRadius
                color: Theme.tile

                Behavior on color {
                    ColorAnimation { duration: Theme.surfaceDuration }
                }

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 28
                        height: 28
                        radius: 9
                        color: Theme.chip

                        Sym {
                            anchors.centerIn: parent
                            name: row.modelData.glyph
                            size: Theme.iconSmall + 1
                            color: Theme.textMid
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 28 - countText.implicitWidth - parent.spacing * 2
                        spacing: 1

                        Text {
                            width: parent.width
                            text: row.modelData.name
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.fontCaption
                            font.weight: Theme.weightHeavy
                            color: Theme.textHi
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: row.modelData.sub
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.fontMicro
                            font.weight: Theme.weightSemibold
                            color: Theme.textFaint
                            elide: Text.ElideRight
                        }
                    }

                    Text {
                        id: countText
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.count
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.fontSecondary
                        font.weight: Theme.weightHeavy
                        font.features: Theme.tabularNumberFeatures
                        color: Theme.accent
                    }
                }
            }
        }

        Item {
            visible: root.rows.length === 0
            width: parent.width
            height: 74

            Column {
                anchors.centerIn: parent
                spacing: 7

                Sym {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: Updates.busy ? "refresh"
                        : Updates.error !== "" ? "cloud_off" : "check_circle"
                    size: Theme.iconLarge
                    fill: Updates.busy || Updates.error !== "" ? 0 : 1
                    color: Updates.busy ? Theme.accent
                        : Updates.error !== "" ? Theme.textFaint : Theme.accent
                    opacity: 0.9
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Updates.busy ? "Checking for updates…"
                        : Updates.error !== "" ? "Could not check"
                        : Updates.wasPending ? "Updated · nothing pending" : "All up to date"
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontCaption
                    font.weight: Theme.weightBold
                    color: Theme.textMid
                }
            }
        }
    }

    // ---- act --------------------------------------------------------------
    Rectangle {
        id: goButton

        visible: root.rows.length > 0
        width: parent.width
        height: 38
        radius: 14
        color: goMouse.containsMouse ? Theme.accent : Theme.accentSoft

        Behavior on color {
            ColorAnimation { duration: Theme.chipFadeDuration }
        }

        scale: goMouse.pressed ? 0.98 : 1

        Behavior on scale {
            NumberAnimation {
                duration: Theme.pressDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.springCurve
            }
        }

        Row {
            anchors.centerIn: parent
            spacing: 7

            Sym {
                anchors.verticalCenter: parent.verticalCenter
                name: "terminal"
                size: Theme.iconSmall + 1
                symWeight: 600
                color: goMouse.containsMouse ? Theme.textOnAccent : Theme.accent
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Update now"
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontTiny
                font.weight: Theme.weightHeavy
                color: goMouse.containsMouse ? Theme.textOnAccent : Theme.accent
            }
        }

        MouseArea {
            id: goMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Updates.run()
        }
    }

    Item {
        width: parent.width
        height: footnote.implicitHeight + 2

        Text {
            id: footnote
            x: 4
            width: parent.width - 8
            text: Updates.busy ? "checking the dnf cache and Flatpak remotes"
                : root.rows.length > 0
                ? "sudo dnf upgrade" + (Settings.modOpts.updates.flatpak
                    ? " · flatpak update" : "") + " — runs in kitty"
                : "checked against the dnf metadata cache"
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontMicro
            font.weight: Theme.weightSemibold
            color: Theme.textFaint
            elide: Text.ElideRight
        }
    }
}
