pragma ComponentBehavior: Bound
import QtQuick
import "../Common"

// Model usage: one mini chip per provider (brand mark + minimum remaining).
//
// Each chip is its own hover and click target but they share a single popout
// anchor, so moving the pointer across them swaps the panel's contents without
// moving the panel. That is why this keeps its own panel wiring instead of
// inheriting BarChip's: the generic toggle cannot express "select a provider,
// or close if it was already the one showing".
Item {
    id: root

    // ---- panel wiring -----------------------------------------------------
    // Same contract as BarIcon/BarChip: one panel name drives registration and
    // the held state, against a typed host so a typo is a lint error.
    property Bar host: null
    property string panelName: ""
    property string isle: ""
    property Item anchorItem: root

    readonly property bool ownsPanel: panelName !== "" && host !== null

    onOwnsPanelChanged: {
        if (ownsPanel)
            host.registerPanel(panelName, anchorItem);
    }

    onAnchorItemChanged: {
        if (ownsPanel)
            host.registerPanel(panelName, anchorItem);
    }

    Component.onCompleted: {
        if (ownsPanel)
            host.registerPanel(panelName, anchorItem);
    }

    Component.onDestruction: {
        if (ownsPanel)
            host.unregisterPanel(panelName, anchorItem);
    }

    signal chipClicked(string key)
    signal chipEntered(string key)

    // The usage popout is expanded below this module.
    property bool held: ownsPanel && host.popoutOpen(panelName)
    property int displayMode: 2

    readonly property var availableKeys: Usage.providerKeys.filter(k => {
        // Provider toggles only control the bar; every provider keeps its
        // popover tab for sign-in and error details. A menubar chip is useful
        // only when the provider returned a real usage figure, so do not
        // render unavailable providers as a misleading "--%" icon.
        if (Settings.modOpts.usage[k] !== true)
            return false;
        return Usage.minRemaining(k) >= 0;
    })
    readonly property bool empty: availableKeys.length === 0
    readonly property real detailSaving: {
        if (empty)
            return emptyText.implicitWidth + 5;
        let total = 0;
        for (let i = 0; i < providerRepeater.count; i++) {
            const item = providerRepeater.itemAt(i) as UsageProviderItem;
            if (item)
                total += item.detailSaving;
        }
        return total;
    }

    // The bar-wide hover fallback reports scene coordinates when mapping the
    // popout costs a provider MouseArea its enter event. Resolve that point to
    // a provider here while the delegates and their keys are still together.
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

    implicitHeight: Theme.chipInnerHeight
    implicitWidth: row.implicitWidth
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3

        // Offline / loading state
        Rectangle {
            id: emptyChip

            property string providerKey: "claude"
            visible: root.empty
            height: Theme.chipInnerHeight
            width: emptyRow.implicitWidth + 14
            radius: Theme.chipRadius
            color: root.held ? Theme.barChipHover : "transparent"
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color {
                ColorAnimation { duration: Theme.chipFadeDuration }
            }

            BarHover {
                id: emptyHover
                anchors.fill: parent
                host: root.host
                target: emptyChip
                radius: emptyChip.radius
                pressed: emptyMouse.pressed
                tint: Theme.barTextHi
                pressPoint: Qt.point(emptyMouse.mouseX, emptyMouse.mouseY)
            }

            Row {
                id: emptyRow
                anchors.centerIn: parent
                spacing: 4

                BarBrandIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 12
                    height: 12
                    name: "claude"
                    opacity: highlighted ? 1 : 0.52
                    highlighted: root.held || emptyHover.over
                }

                Text {
                    id: emptyText
                    visible: root.displayMode > 0
                    anchors.verticalCenter: parent.verticalCenter
                    // "offline" is every provider being signed out, which the
                    // fetcher reports perfectly well; "unavailable" is the
                    // fetcher itself having failed, which it cannot.
                    text: Usage.loading && !Usage.anyOk ? "Models…"
                        : Usage.fetchError !== "" ? "unavailable" : "offline"
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.barLabelSize
                    font.weight: Theme.weightBold
                    color: Usage.fetchError !== "" ? Theme.barRedText : Theme.barTextFaint
                }
            }

            MouseArea {
                id: emptyMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.chipEntered("claude")
                onPositionChanged: root.chipEntered("claude")
                onClicked: root.chipClicked("claude")
            }
        }

        Repeater {
            id: providerRepeater
            model: root.availableKeys

            delegate: UsageProviderItem {
                id: chip

                readonly property string providerKey: modelData
                readonly property string status: Usage.chipStatus(modelData)
                readonly property int remaining: Usage.minRemaining(modelData)
                readonly property bool stressed: status === "warn" || status === "crit"
                // This provider's view is expanded below the bar.
                readonly property bool current: root.held && Usage.selected === modelData
                detailSaving: usageText.implicitWidth + 4
                height: Theme.chipInnerHeight
                width: chipRow.implicitWidth + 14
                radius: Theme.chipRadius
                // Quota state belongs to the percentage text. Keep the bar
                // slab quiet instead of adding warning/critical tile fills.
                color: current ? Theme.barChipHover : "transparent"
                anchors.verticalCenter: parent.verticalCenter
                scale: chipMouse.pressed ? 0.95 : 1

                Behavior on color {
                    ColorAnimation { duration: Theme.chipFadeDuration }
                }

                Behavior on scale {
                    NumberAnimation {
                        duration: Theme.pressDuration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.springCurve
                    }
                }

                BarHover {
                    id: chipHover
                    anchors.fill: parent
                    host: root.host
                    target: chip
                    radius: chip.radius
                    pressed: chipMouse.pressed
                    tint: Theme.barTextHi
                    pressPoint: Qt.point(chipMouse.mouseX, chipMouse.mouseY)
                }

                Row {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: 4

                    BarBrandIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: chip.modelData === "codex" ? 13 : 12
                        height: width
                        name: Usage.meta[chip.modelData].icon
                        opacity: highlighted || chip.status !== "error" ? 1 : 0.52
                        highlighted: chip.current || chipHover.over
                    }

                    Text {
                        id: usageText
                        visible: root.displayMode > 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: chip.status === "error" || chip.remaining < 0
                            ? "--%" : chip.remaining + "%"
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.barLabelSize
                        font.weight: Theme.weightMedium
                        font.features: Theme.tabularNumberFeatures
                        color: chip.status === "crit" ? Theme.barRedText
                            : chip.status === "warn" ? Theme.barAmber
                            : chip.status === "stale" ? Theme.barTextFaint
                            : chip.status === "error" ? Theme.barRedText
                            : Theme.barTextMid
                    }
                }

                MouseArea {
                    id: chipMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.chipEntered(chip.modelData)
                    onPositionChanged: root.chipEntered(chip.modelData)
                    onClicked: root.chipClicked(chip.modelData)
                }

                BarTooltip {
                    check: chipHover.check
                    text: Usage.meta[chip.modelData].title + " usage · "
                        + (chip.status === "error" || chip.remaining < 0
                            ? "unavailable" : chip.remaining + "% remaining")
                    align: 1
                    y: chip.height + 11
                    x: chip.width - width
                }
            }
        }
    }
}
