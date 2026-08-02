import QtQuick
import Quickshell
import "../Common"

// Model Usage bar module: one mini chip per provider (brand mark +
// min-remaining %), the whole group a single click target (design 3a).
Rectangle {
    id: root

    signal clicked
    signal entered
    signal exited

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
    implicitWidth: row.implicitWidth + 12
    radius: Theme.chipRadius
    color: root.held || groupMouse.containsMouse ? Theme.hoverFill : "transparent"
    anchors.verticalCenter: parent.verticalCenter

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 3

        // Offline / loading state
        Row {
            visible: root.empty
            spacing: 8
            anchors.verticalCenter: parent.verticalCenter

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

        Repeater {
            model: root.visibleKeys

            delegate: Rectangle {
                required property string modelData
                readonly property string status: Usage.chipStatus(modelData)
                readonly property int remaining: Usage.minRemaining(modelData)
                readonly property bool stressed: status === "warn" || status === "crit"

                height: 22
                width: chipRow.implicitWidth + 14
                radius: Theme.chipRadius
                color: status === "crit" ? Theme.redBg : status === "warn" ? Theme.amberBg : Theme.hoverFill
                anchors.verticalCenter: parent.verticalCenter

                Row {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: 5

                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        width: modelData === "codex" ? 12 : 11
                        height: width
                        sourceSize: Qt.size(24, 24)
                        source: Quickshell.shellDir + "/assets/" + Usage.meta[modelData].icon
                                + (status === "error" ? "-dim" : "") + ".svg"
                    }

                    Text {
                        visible: root.displayMode > 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: status === "error" || remaining < 0 ? "--%" : remaining + "%"
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                        font.weight: stressed || status === "error" ? 600 : 500
                        color: status === "crit" ? Theme.redText
                             : status === "warn" ? Theme.amber
                             : status === "error" ? Theme.redText
                             : Theme.textMid
                    }
                }
            }
        }
    }

    MouseArea {
        id: groupMouse
        anchors.fill: parent
        hoverEnabled: true
        onEntered: root.entered()
        onExited: root.exited()
        onClicked: root.clicked()
    }

    BarTooltip {
        hovered: groupMouse.containsMouse
        text: "Model usage"
        align: 1
        y: root.height + 6
        x: root.width - width
    }
}
