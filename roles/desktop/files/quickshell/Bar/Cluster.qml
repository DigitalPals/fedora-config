pragma ComponentBehavior: Bound
import QtQuick
import "../Common"
import "../Common/LayoutHelpers.js" as LayoutHelpers
import "../Common/SettingsHelpers.js" as SettingsHelpers

// One section of the menubar, and the thing that decides where its pills are.
//
// Grouping remains behavioral rather than decorative. T3, usage and GitHub
// retain their shared ordering/anchor contract, while every group rests
// directly on the single bar slab. Status and centre runs still own one
// pointer target for their combined popovers.
//
// Grouping follows adjacency in the user's own module order, so dragging a
// module out of a run in the settings window splits the pill exactly there.
Item {
    id: root

    required property Bar host
    required property string col
    property var model: []
    property int spacing: Theme.barSpacing

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

                function previousShownId(at) {
                    for (let i = Math.min(at, items.length) - 1; i >= 0; i--) {
                        if (root.host.moduleShown(items[i].entry))
                            return items[i].entry.id;
                    }
                    return "";
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

                // Group furniture is transparent at rest. Status and centre
                // groups are one click target, so their shared hover surface
                // follows that same target instead of suggesting that each
                // piece of status content has a separate action.
                Rectangle {
                    id: pill

                    readonly property string isle: root.col
                    readonly property real pad: group.kind === "chip" ? 0
                        : group.kind === "status" ? 6
                        : group.kind === "center" ? 7 : 0

                    width: slotRow.implicitWidth + pad * 2
                    height: Theme.chipHeight
                    radius: Theme.chipRadius
                    anchors.verticalCenter: parent.verticalCenter
                    color: {
                        if (!group.ownsPointer)
                            return "transparent";
                        if (group.held)
                            return Theme.barChipHover;
                        return "transparent";
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

                    BarHover {
                        id: groupHover
                        anchors.fill: parent
                        visible: group.ownsPointer
                        host: root.host
                        target: pill
                        visualEnabled: group.kind !== "center"
                            || !root.host.indicatorActionHovered
                        radius: pill.radius
                        pressed: groupMouse.pressed
                        tint: Theme.barTextHi
                        pressPoint: Qt.point(groupMouse.mouseX, groupMouse.mouseY)
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
                        spacing: group.kind === "chip" ? 2
                            : group.kind === "status" ? 7
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
                                    // Quick actions sit quietly against the
                                    // clock. The clock/weather boundary gets
                                    // the fine rule visible in the screenshot.
                                    kind: group.kind === "center"
                                            && (entry.modelData.entry.id === "clock"
                                                || group.previousShownId(
                                                    entry.modelData.at) === "indicators")
                                        ? "space" : "rule"
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
                                    groupHovered: groupHover.over
                                }
                            }
                        }
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
                        check: groupHover.check
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
