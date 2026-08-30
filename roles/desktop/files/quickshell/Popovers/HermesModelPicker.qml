pragma ComponentBehavior: Bound
import QtQuick
import "../Common"

// Provider-aware Hermes model picker. It follows T3's compact provider rail +
// searchable model list, while all catalog and mutation state remains Hermes-owned.
Item {
    id: root

    property string conversationId: ""
    property string provider: ""
    property string model: ""
    property string label: ""
    property bool expanded: false
    property bool openUpward: true
    property real maxWidth: 1000
    signal selected(string provider, string model)

    property string railProvider: ""
    property string query: ""
    readonly property var groups: Hermes.modelGroups
    readonly property var rows: modelRows()
    readonly property int panelWidth: 336
    readonly property int panelHeight: 290
    readonly property int popupHeight: panelHeight
    readonly property Item popupItem: panel

    implicitWidth: trigger.implicitWidth
    implicitHeight: trigger.implicitHeight
    z: expanded ? 100 : 0

    function modelRows() {
        const result = [];
        const needle = query.trim().toLowerCase();
        for (const group of (Array.isArray(groups) ? groups : [])) {
            const providerId = String(group.providerId ?? "");
            if (needle === "" && railProvider !== "" && providerId !== railProvider)
                continue;
            for (const candidate of (Array.isArray(group.models) ? group.models : [])) {
                const id = String(candidate.id ?? "");
                const name = String(candidate.label ?? id);
                if (needle !== "" && (id + " " + name + " "
                        + String(group.provider ?? providerId)).toLowerCase()
                        .indexOf(needle) < 0)
                    continue;
                result.push({ providerId: providerId,
                    provider: String(group.provider ?? providerId),
                    id: id, label: name });
            }
        }
        return result;
    }

    function open() {
        railProvider = provider || (groups.length > 0
            ? String(groups[0].providerId ?? "") : "");
        query = "";
        expanded = true;
        searchInput.forceActiveFocus();
    }

    function close() {
        expanded = false;
        query = "";
    }

    function containsPickerPoint(item, x, y) {
        if (!item)
            return false;
        const point = root.mapFromItem(item, x, y);
        const inButton = point.x >= 0 && point.x <= root.width
            && point.y >= 0 && point.y <= root.height;
        const inPanel = panel.visible && point.x >= panel.x
            && point.x <= panel.x + panel.width && point.y >= panel.y
            && point.y <= panel.y + panel.height;
        return inButton || inPanel;
    }

    onEnabledChanged: if (!enabled) close()
    onVisibleChanged: if (!visible) close()

    TapHandler {
        enabled: root.expanded && root.enabled && root.visible
        margin: root.Window.window
            ? Math.max(root.Window.window.width, root.Window.window.height) : 0
        onTapped: eventPoint => {
            if (!root.containsPickerPoint(root, eventPoint.position.x,
                    eventPoint.position.y))
                root.close();
        }
    }

    HermesBarControl {
        id: trigger
        anchors.fill: parent
        text: root.label
        accessibleDescription: "Provider and model"
        brand: Hermes.providerIcon(root.provider)
        tint: HermesTheme.textPrimary
        active: root.expanded
        maxWidth: root.maxWidth
        enabled: root.enabled
        onTriggered: root.expanded ? root.close() : root.open()
    }

    Rectangle {
        id: panel
        z: 1000
        visible: root.expanded && root.enabled
        x: 0
        y: root.openUpward ? -height - 6 : root.height + 6
        width: root.panelWidth
        height: root.panelHeight
        radius: HermesTheme.panelRadius
        color: HermesTheme.overlay
        border.width: 1
        border.color: HermesTheme.borderStrong
        clip: true

        Rectangle {
            id: providerRail
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 44
            color: HermesTheme.hover

            Column {
                width: parent.width
                y: 6
                spacing: 2

                Repeater {
                    model: root.groups

                    delegate: Rectangle {
                        id: providerRow
                        required property var modelData
                        readonly property string providerId:
                            String(modelData.providerId ?? "")
                        width: 40
                        height: 36
                        x: 2
                        radius: HermesTheme.controlRadius
                        color: root.railProvider === providerId
                            ? Theme.chip
                            : providerMouse.containsMouse ? HermesTheme.hoverStrong
                                : "transparent"
                        Accessible.role: Accessible.Button
                        Accessible.name: String(modelData.provider ?? providerId)

                        BrandIcon {
                            visible: Hermes.providerIcon(providerRow.providerId) !== ""
                            anchors.centerIn: parent
                            width: 17
                            height: 17
                            name: Hermes.providerIcon(providerRow.providerId)
                        }

                        Text {
                            visible: Hermes.providerIcon(providerRow.providerId) === ""
                            anchors.centerIn: parent
                            text: String(providerRow.modelData.provider
                                ?? providerRow.providerId).slice(0, 1).toUpperCase()
                            font.family: HermesTheme.fontUi
                            font.pixelSize: Theme.fontBody
                            font.weight: Theme.weightSemibold
                            color: HermesTheme.textSecondary
                        }

                        Rectangle {
                            visible: root.railProvider === providerRow.providerId
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 3
                            height: 18
                            radius: 2
                            color: HermesTheme.accent
                        }

                        MouseArea {
                            id: providerMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.railProvider = providerRow.providerId;
                                root.query = "";
                                searchInput.forceActiveFocus();
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            id: searchBox
            anchors.left: providerRail.right
            anchors.leftMargin: 8
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.top: parent.top
            anchors.topMargin: 8
            height: 34
            radius: HermesTheme.controlRadius
            color: HermesTheme.surfaceRaised
            border.width: searchInput.activeFocus ? 1 : 0
            border.color: HermesTheme.focus

            Sym {
                id: searchIcon
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                name: "search"
                size: Theme.iconSmall
                color: HermesTheme.textFaint
            }

            TextInput {
                id: searchInput
                anchors.left: searchIcon.right
                anchors.leftMargin: 6
                anchors.right: parent.right
                anchors.rightMargin: 7
                anchors.verticalCenter: parent.verticalCenter
                text: root.query
                onTextEdited: root.query = text
                font.family: HermesTheme.fontUi
                font.pixelSize: Theme.fontSecondary
                color: HermesTheme.textPrimary
                selectionColor: HermesTheme.accentSoft
                selectedTextColor: HermesTheme.textPrimary

                Text {
                    visible: searchInput.text === ""
                    text: "Search models…"
                    font: searchInput.font
                    color: HermesTheme.textFaint
                }
            }
        }

        Flickable {
            id: modelFlick
            anchors.left: providerRail.right
            anchors.leftMargin: 4
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.top: searchBox.bottom
            anchors.topMargin: 5
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 4
            contentWidth: width
            contentHeight: modelColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            Column {
                id: modelColumn
                width: modelFlick.width

                Text {
                    visible: root.rows.length === 0
                    width: parent.width
                    height: 44
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: "No models found"
                    font.family: HermesTheme.fontUi
                    font.pixelSize: Theme.fontCaption
                    color: HermesTheme.textFaint
                }

                Repeater {
                    model: root.rows

                    delegate: Rectangle {
                        id: modelRow
                        required property var modelData
                        readonly property bool selectedModel:
                            String(modelData.id) === root.model
                            && String(modelData.providerId) === root.provider
                        width: parent.width
                        height: 44
                        radius: HermesTheme.controlRadius
                        color: selectedModel ? Theme.chip
                            : modelMouse.containsMouse ? HermesTheme.hoverStrong
                                : "transparent"

                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.right: checkMark.left
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1

                            Text {
                                width: parent.width
                                text: String(modelRow.modelData.label ?? "")
                                elide: Text.ElideRight
                                font.family: HermesTheme.fontUi
                                font.pixelSize: Theme.fontSecondary
                                font.weight: Theme.weightMedium
                                color: HermesTheme.textPrimary
                            }

                            Text {
                                width: parent.width
                                text: root.query !== ""
                                    ? String(modelRow.modelData.provider ?? "")
                                    : String(modelRow.modelData.id ?? "")
                                elide: Text.ElideRight
                                font.family: HermesTheme.fontUi
                                font.pixelSize: Theme.fontMicro
                                color: HermesTheme.textFaint
                            }
                        }

                        Sym {
                            id: checkMark
                            visible: modelRow.selectedModel
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            name: "check"
                            size: Theme.iconSmall
                            color: HermesTheme.accent
                        }

                        MouseArea {
                            id: modelMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.selected(String(modelRow.modelData.providerId),
                                    String(modelRow.modelData.id));
                                root.close();
                            }
                        }
                    }
                }
            }
        }

        ScrollChrome {
            anchors.fill: modelFlick
            target: modelFlick
            fadeSize: 16
            edgeColor: HermesTheme.overlay
            thumbColor: HermesTheme.accent
        }
    }
}
