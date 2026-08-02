import QtQuick
import Quickshell
import "../Common"

// Model Usage bar module: one mini chip per provider (brand mark +
// min-remaining %). Each chip is its own hover/click target and opens
// that provider's usage view (design 1d: per-provider popovers).
Item {
    id: root

    signal chipClicked(string key)
    signal chipEntered(string key)
    signal chipExited(string key)

    // The usage popout is expanded below this module (t5 open-state).
    property bool held: false
    property int displayMode: 2

    readonly property var availableKeys: Usage.providerKeys.filter(k => {
        const p = Usage.provider(k);
        if (!p)
            return false;
        // Providers that were never signed in stay out of the bar; their
        // tab in the popover still shows the sign-in hint.
        return p.status === "ok" || p.kind !== "nocreds";
    })
    readonly property var visibleKeys: {
        // Medium and wide bars have room for every authenticated provider.
        // Only the narrow icon-only layout collapses to the most constrained
        // provider.
        if (displayMode >= 1 || availableKeys.length <= 1)
            return availableKeys;
        const ranked = availableKeys.slice().sort((a, b) => {
            const ar = Usage.minRemaining(a);
            const br = Usage.minRemaining(b);
            return (ar < 0 ? 101 : ar) - (br < 0 ? 101 : br);
        });
        return ranked.slice(0, 1);
    }
    readonly property bool empty: visibleKeys.length === 0

    implicitHeight: 22
    implicitWidth: row.implicitWidth
    anchors.verticalCenter: parent.verticalCenter

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3

        // Offline / loading state
        Rectangle {
            visible: root.empty
            height: 22
            width: emptyRow.implicitWidth + 14
            radius: Theme.chipRadius
            color: root.held ? Theme.hoverFillStrong : emptyMouse.containsMouse ? Theme.hoverFill : "transparent"
            anchors.verticalCenter: parent.verticalCenter

            Row {
                id: emptyRow
                anchors.centerIn: parent
                spacing: 8

                Image {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 12
                    height: 12
                    sourceSize: Qt.size(24, 24)
                    source: Quickshell.shellDir + "/assets/claude-dim.svg"
                }

                Text {
                    visible: root.displayMode > 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: Usage.loading && !Usage.anyOk ? "Models…" : "Models offline"
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                    color: Theme.textFaint
                }
            }

            MouseArea {
                id: emptyMouse
                anchors.fill: parent
                hoverEnabled: true
                onEntered: root.chipEntered("claude")
                onExited: root.chipExited("claude")
                onClicked: root.chipClicked("claude")
            }
        }

        Repeater {
            model: root.visibleKeys

            delegate: Rectangle {
                id: chip

                required property string modelData
                readonly property string status: Usage.chipStatus(modelData)
                readonly property int remaining: Usage.minRemaining(modelData)
                readonly property bool stressed: status === "warn" || status === "crit"
                // This provider's view is expanded below the bar.
                readonly property bool current: root.held && Usage.selected === modelData

                height: 22
                width: chipRow.implicitWidth + 14
                radius: Theme.chipRadius
                color: status === "crit" ? Theme.redBg
                     : status === "warn" ? Theme.amberBg
                     : current || chipMouse.containsMouse ? Theme.hoverFillStrong
                     : Theme.hoverFill
                anchors.verticalCenter: parent.verticalCenter

                Row {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: 5

                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        width: chip.modelData === "codex" ? 12 : 11
                        height: width
                        sourceSize: Qt.size(24, 24)
                        source: Quickshell.shellDir + "/assets/" + Usage.meta[chip.modelData].icon
                                + (chip.status === "error" ? "-dim" : "") + ".svg"
                    }

                    Text {
                        visible: root.displayMode > 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: chip.status === "error" || chip.remaining < 0 ? "--%" : chip.remaining + "%"
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                        font.weight: chip.stressed || chip.status === "error" ? 600 : 500
                        color: chip.status === "crit" ? Theme.redText
                             : chip.status === "warn" ? Theme.amber
                             : chip.status === "error" ? Theme.redText
                             : Theme.textMid
                    }
                }

                MouseArea {
                    id: chipMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: root.chipEntered(chip.modelData)
                    onExited: root.chipExited(chip.modelData)
                    onClicked: root.chipClicked(chip.modelData)
                }

                BarTooltip {
                    hovered: chipMouse.containsMouse
                    text: Usage.meta[chip.modelData].title + " usage"
                    align: 1
                    y: chip.height + 6
                    x: chip.width - width
                }
            }
        }
    }
}
