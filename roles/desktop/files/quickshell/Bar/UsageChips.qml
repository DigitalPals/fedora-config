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
        return availableKeys;
    }
    readonly property bool empty: visibleKeys.length === 0
    readonly property real detailSaving: {
        if (empty)
            return emptyText.implicitWidth + 6;
        let total = 0;
        for (let i = 0; i < providerRepeater.count; i++) {
            const item = providerRepeater.itemAt(i);
            if (item)
                total += item.detailSaving;
        }
        return total;
    }

    // The bar-level HoverHandler reports scene coordinates even when mapping
    // the popout window prevents one of the chip MouseAreas from receiving a
    // fresh enter event. Resolve that point to the provider delegate here so
    // the grouped module can still switch between provider views reliably.
    function providerAtScenePoint(scenePoint) {
        const children = row.children;
        for (let i = 0; i < children.length; i++) {
            const child = children[i];
            if (!("providerKey" in child) || !child.visible
                    || child.width <= 0 || child.height <= 0)
                continue;
            const local = child.mapFromItem(null, scenePoint.x, scenePoint.y);
            if (local.x >= 0 && local.x <= child.width
                    && local.y >= 0 && local.y <= child.height)
                return child.providerKey;
        }
        return "";
    }

    implicitHeight: Theme.chipHeight
    implicitWidth: row.implicitWidth
    anchors.verticalCenter: parent.verticalCenter

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3

        // Offline / loading state
        Rectangle {
            property string providerKey: "claude"

            visible: root.empty
            height: Theme.chipHeight
            width: emptyRow.implicitWidth + 12
            radius: Theme.chipRadius
            color: root.held ? Theme.hoverFillStrong : emptyMouse.containsMouse ? Theme.hoverFill : "transparent"
            anchors.verticalCenter: parent.verticalCenter

            Row {
                id: emptyRow
                anchors.centerIn: parent
                spacing: 6

                Image {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 12
                    height: 12
                    sourceSize: Qt.size(24, 24)
                    source: Quickshell.shellDir + "/assets/claude-dim.svg"
                }

                Text {
                    id: emptyText
                    visible: root.displayMode > 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: Usage.loading && !Usage.anyOk ? "Models…" : "Models offline"
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.barTextSize
                    color: Theme.textFaint
                }
            }

            MouseArea {
                id: emptyMouse
                anchors.fill: parent
                hoverEnabled: true
                onEntered: root.chipEntered("claude")
                onPositionChanged: root.chipEntered("claude")
                onExited: root.chipExited("claude")
                onClicked: root.chipClicked("claude")
            }
        }

        Repeater {
            id: providerRepeater
            model: root.visibleKeys

            delegate: Rectangle {
                id: chip

                required property string modelData
                readonly property string providerKey: modelData
                readonly property string status: Usage.chipStatus(modelData)
                readonly property int remaining: Usage.minRemaining(modelData)
                readonly property bool stressed: status === "warn" || status === "crit"
                // This provider's view is expanded below the bar.
                readonly property bool current: root.held && Usage.selected === modelData
                readonly property real detailSaving: usageText.implicitWidth + 5

                height: Theme.chipHeight
                width: chipRow.implicitWidth + 12
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
                        id: usageText
                        visible: root.displayMode > 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: chip.status === "error" || chip.remaining < 0 ? "--%" : chip.remaining + "%"
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.barTextSize
                        font.weight: chip.stressed || chip.status === "error" ? Theme.weightSemibold : Theme.weightMedium
                        font.features: Theme.tabularNumberFeatures
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
                    onPositionChanged: root.chipEntered(chip.modelData)
                    onExited: root.chipExited(chip.modelData)
                    onClicked: root.chipClicked(chip.modelData)
                }

                BarTooltip {
                    hovered: chipMouse.containsMouse
                    text: Usage.meta[chip.modelData].title + " usage · "
                        + (chip.status === "error" || chip.remaining < 0
                            ? "unavailable" : chip.remaining + "% remaining")
                    align: 1
                    y: chip.height + 6
                    x: chip.width - width
                }
            }
        }
    }
}
