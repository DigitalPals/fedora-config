pragma ComponentBehavior: Bound
import QtQuick
import "../Common"
import "../Common/LayoutHelpers.js" as LayoutHelpers
import "../Common/SettingsHelpers.js" as SettingsHelpers

// One section of the menubar, and the thing that decides where its pills are.
//
// The design does not draw a chip per module: it draws a small number of
// rounded groups, and a run of modules that belong together shares one. The
// T3, usage and GitHub chips sit inside a single background; volume, Wi-Fi,
// Bluetooth and battery are bare glyphs inside the pill that opens the
// Control Center; the clock, date and weather are one sentence inside the
// pill that opens the notification centre. Everything else brings its own.
//
// Grouping follows adjacency in the user's own module order, so dragging a
// module out of a run in the settings window splits the pill exactly there.
Item {
    id: root

    required property Bar host
    required property string col
    property var model: []
    property int spacing: 8

    readonly property var groups: LayoutHelpers.groupModules(model,
        id => SettingsHelpers.moduleGroup(id))

    implicitWidth: row.implicitWidth
    implicitHeight: Theme.barHeight

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.spacing

        Repeater {
            id: groupRepeater
            model: root.groups

            delegate: Item {
                id: group

                required property var modelData
                readonly property string kind: modelData.kind
                readonly property var items: modelData.items
                // The status and centre pills own the pointer themselves;
                // their modules are content, not targets.
                readonly property bool ownsPointer: kind === "status" || kind === "center"
                // Which panel each interactive group opens. A map rather than
                // a chain of comparisons so the panel names sit together and
                // the registry test can find them.
                readonly property var groupPanels: ({
                    status: "control",
                    center: "notifications"
                })
                readonly property string panelName: groupPanels[kind] ?? ""
                readonly property bool held: panelName !== ""
                    && root.host.popoutOpen(panelName)
                // A group whose every module is switched off or ruled out (no
                // player, no battery, no updates) takes its pill with it.
                readonly property bool populated: {
                    for (let i = 0; i < items.length; i++) {
                        if (root.host.moduleShown(items[i].entry))
                            return true;
                    }
                    return false;
                }

                // Whether anything before position `at` in this group is on
                // screen: a divider is only a separator when there is
                // something on both sides of it. Derived from the same
                // reactive inputs as the slot's own visibility rather than
                // from the laid-out items, so it never lags a frame behind.
                function shownBefore(at) {
                    for (let i = 0; i < at && i < items.length; i++) {
                        if (root.host.moduleShown(items[i].entry))
                            return true;
                    }
                    return false;
                }

                visible: populated
                width: populated ? pill.width : 0
                height: Theme.barHeight
                anchors.verticalCenter: parent.verticalCenter
                onWidthChanged: root.host.scheduleFit()

                // The group owns the panel registration for the pills that
                // open one; the bare modules inside them register nothing.
                Component.onCompleted: {
                    if (panelName !== "")
                        root.host.registerPanel(panelName, pill);
                }

                Component.onDestruction: {
                    if (panelName !== "")
                        root.host.unregisterPanel(panelName, pill);
                }

                // The shared background. A "chip" group is a quiet tray for
                // the chips inside it and never lights up on its own; the
                // interactive ones take the full hover/held ladder.
                Rectangle {
                    id: pill

                    readonly property string isle: root.col
                    readonly property real pad: group.kind === "chip" ? 3
                        : group.kind === "status" ? 13
                        : group.kind === "center" ? 14 : 0

                    width: slotRow.implicitWidth + pad * 2
                    height: Theme.chipHeight
                    radius: Theme.pillRadius
                    anchors.verticalCenter: parent.verticalCenter
                    color: {
                        if (group.kind === "chip")
                            return Theme.barChip;
                        if (!group.ownsPointer)
                            return "transparent";
                        if (group.held || groupPointer.over)
                            return Theme.barChipHover;
                        // The centre pill is bare at rest so the clock reads
                        // as part of the bar rather than as another button.
                        return group.kind === "center" ? "transparent" : Theme.barChip;
                    }
                    scale: group.ownsPointer && groupMouse.pressed ? 0.96 : 1

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

                    // A module appearing or dropping its detail resizes the
                    // pill around it; the glide is what keeps the neighbours
                    // from snapping sideways.
                    Behavior on width {
                        enabled: root.host.animationsReady
                            && !(group.kind === "center"
                                && root.host.indicatorDisclosureAnimating)
                        NumberAnimation {
                            duration: Theme.expandDuration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.springCurve
                        }
                    }

                    Row {
                        id: slotRow
                        z: 2
                        anchors.verticalCenter: parent.verticalCenter
                        x: pill.pad
                        spacing: group.kind === "chip" ? 0
                            : group.kind === "status" ? 9
                            : group.kind === "center" ? 0 : root.spacing

                        Repeater {
                            id: slotRepeater
                            model: group.items

                            delegate: Row {
                                id: entry

                                required property var modelData

                                // `active`, not `visible`: an item's `visible`
                                // reads back its *effective* visibility, which
                                // includes this Row — so binding to it makes
                                // the wrapper depend on itself and latch at
                                // false, and a module that only turns on later
                                // (a track starts, updates appear, a tray icon
                                // registers) never gets on screen.
                                visible: slotLoader.active
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 0

                                Divider {
                                    kind: group.kind === "center" ? "dot" : "rule"
                                    visible: group.kind !== "solo"
                                        && group.shownBefore(entry.modelData.at)
                                }

                                ModuleSlot {
                                    id: slotLoader
                                    host: root.host
                                    col: root.col
                                    modelData: entry.modelData.entry
                                    index: entry.modelData.index
                                    groupAnchor: group.ownsPointer ? pill : null
                                    interactive: !group.ownsPointer
                                    groupHovered: group.kind === "center"
                                        ? root.host.tooltipPointerInside
                                            && root.host.itemContainsPoint(pill,
                                                root.host.tooltipPointerPosition)
                                        : groupPointer.over
                                }
                            }
                        }
                    }

                    PointerCheck {
                        id: groupPointer
                        host: root.host
                        target: pill
                        hovered: groupMouse.containsMouse
                    }

                    MouseArea {
                        id: groupMouse
                        z: 1
                        anchors.fill: parent
                        enabled: group.ownsPointer
                        visible: group.ownsPointer
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.host.hoverPopout(group.panelName, root.col, pill)
                        onPositionChanged: root.host.hoverPopout(group.panelName, root.col, pill)
                        onClicked: root.host.togglePopout(group.panelName, root.col, pill)
                    }

                    BarTooltip {
                        check: groupPointer
                        text: group.kind === "status" ? root.host.statusSummary
                            : group.kind === "center" && !root.host.indicatorActionHovered
                                ? "Notifications & calendar" : ""
                        align: group.kind === "status" ? 1 : 0
                        y: pill.height + 8
                        x: align > 0 ? pill.width - width : (pill.width - width) / 2
                    }
                }
            }
        }
    }
}
