import QtQuick
import QtQuick.Effects
import "../Common"

// Modules page (design v2): live mini-bar preview and three drag-and-drop
// columns. Rows never shift during a drag — an overlay caret marks the
// insertion gap, a floating proxy follows the pointer, and the commit uses
// the prototype's exact splice semantics.
Item {
    id: page

    readonly property var moduleMeta: ({
        ws: { name: "Workspaces", short: "Workspaces" },
        media: { name: "Media", short: "Media", tag: "while playing" },
        clock: { name: "Clock", short: "Clock" },
        weather: { name: "Weather", short: "Weather" },
        t3: { name: "T3 usage chips", short: "T3" },
        vol: { name: "Volume", short: "Vol" },
        wifi: { name: "Wi-Fi", short: "Wi-Fi" },
        batt: { name: "Battery", short: "Batt", tag: "on laptops" },
        bell: { name: "Notifications", short: "Bell" },
        bt: { name: "Bluetooth", short: "BT", tag: "when connected" }
    })

    // ---- drag state -------------------------------------------------------
    property var dragMod: null     // { id, name, fromCol }
    property var dropAt: null      // { col, idx }, idx ∈ [0, len]
    property point dragPos: Qt.point(0, 0)
    readonly property bool dragActive: dragMod !== null

    readonly property int pitch: 31          // 28px row + 3px gap
    readonly property int rowsStartY: 20     // column header + gap

    function cancelDrag() {
        dragMod = null;
        dropAt = null;
    }

    function columnIdAt(x) {
        if (x < colC.x - 4)
            return "left";
        if (x < colR.x - 4)
            return "center";
        return "right";
    }

    function updateDrop(pos) {
        const col = columnIdAt(pos.x);
        const list = Settings.mods[col];
        const local = pos.y - rowsStartY;
        const idx = Math.max(0, Math.min(list.length, Math.floor((local + pitch / 2) / pitch)));
        if (!dropAt || dropAt.col !== col || dropAt.idx !== idx)
            dropAt = { col: col, idx: idx };
    }

    function commitDrag() {
        if (!dragMod || !dropAt) {
            cancelDrag();
            return;
        }
        const mods = {
            left: Settings.mods.left.map(m => ({ id: m.id, on: m.on })),
            center: Settings.mods.center.map(m => ({ id: m.id, on: m.on })),
            right: Settings.mods.right.map(m => ({ id: m.id, on: m.on }))
        };
        const srcList = mods[dragMod.fromCol];
        const srcIdx = srcList.findIndex(m => m.id === dragMod.id);
        if (srcIdx < 0) {
            cancelDrag();
            return;
        }
        const item = srcList[srcIdx];
        let idx = dropAt.idx;
        srcList.splice(srcIdx, 1);
        if (dropAt.col === dragMod.fromCol && srcIdx < idx)
            idx--;
        mods[dropAt.col].splice(idx, 0, item);
        Settings.setModuleOrder(mods.left, mods.center, mods.right);
        cancelDrag();
    }

    // ---- components -------------------------------------------------------
    component MiniChip: Rectangle {
        required property var modelData

        readonly property bool on: modelData.on

        height: 18
        width: chipText.implicitWidth + 12
        radius: 4
        color: on ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
        border.width: on ? 0 : 1
        border.color: Qt.rgba(1, 1, 1, 0.18)

        Text {
            id: chipText
            anchors.centerIn: parent
            text: page.moduleMeta[parent.modelData.id].short
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontCaption
            font.weight: Theme.weightMedium
            color: parent.on ? Theme.textMid : Theme.textFaint
        }
    }

    component ModuleRow: Rectangle {
        id: row

        required property var modelData
        required property int index
        required property string colId

        readonly property var meta: page.moduleMeta[modelData.id]
        readonly property bool dragged: page.dragMod !== null && page.dragMod.id === modelData.id

        width: parent.width
        height: 28
        radius: 7
        color: modelData.on ? Theme.cardFill : "transparent"
        border.width: modelData.on ? 0 : 1
        border.color: Qt.rgba(1, 1, 1, 0.14)
        opacity: row.dragged ? 0.35 : 1

        MouseArea {
            id: dragArea
            anchors.fill: parent
            cursorShape: page.dragActive ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            preventStealing: true

            property point pressPos

            onPressed: mouse => pressPos = Qt.point(mouse.x, mouse.y)
            onPositionChanged: mouse => {
                if (!page.dragActive) {
                    if (Math.abs(mouse.x - pressPos.x) + Math.abs(mouse.y - pressPos.y) < 4)
                        return;
                    page.dragMod = { id: row.modelData.id, name: row.meta.name, fromCol: row.colId };
                }
                page.dragPos = dragArea.mapToItem(columnsRow, mouse.x, mouse.y);
                page.updateDrop(page.dragPos);
            }
            onReleased: {
                if (page.dragActive)
                    page.commitDrag();
            }
            onCanceled: page.cancelDrag()
        }

        Item {
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.right: rowSwitch.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height

            Text {
                id: rowHandle
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "⠿"
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontCaption
                color: Theme.textDim
            }

            Text {
                id: rowName
                anchors.left: rowHandle.right
                anchors.leftMargin: 6
                anchors.right: rowTag.visible ? rowTag.left : parent.right
                anchors.rightMargin: rowTag.visible ? 6 : 0
                anchors.verticalCenter: parent.verticalCenter
                text: row.meta.name
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontCaption
                color: row.modelData.on ? Theme.textMid : Theme.textLow
                elide: Text.ElideRight
            }

            Text {
                id: rowTag
                visible: row.meta.tag !== undefined
                    && implicitWidth + rowHandle.width + 40 < parent.width
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: row.meta.tag ?? ""
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontCaption
                color: Theme.textFaint
            }
        }

        SettingsSwitch {
            id: rowSwitch
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            trackWidth: 22
            trackHeight: 12
            checked: row.modelData.on
            onToggled: value => Settings.setModuleEnabled(row.modelData.id, value)
        }
    }

    component ModuleColumn: Item {
        id: column

        required property string colId
        required property string title
        property bool pinnedTail: false

        readonly property var list: Settings.mods[colId]

        Text {
            text: column.title
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontCaption
            font.weight: Theme.weightSemibold
            font.letterSpacing: 0.8
            color: Theme.textDim
        }

        Column {
            y: page.rowsStartY
            width: parent.width
            spacing: 3

            Repeater {
                model: column.list
                delegate: ModuleRow { colId: column.colId }
            }

            Rectangle {
                visible: column.pinnedTail
                width: parent.width
                height: 28
                radius: 7
                color: Qt.rgba(1, 1, 1, 0.03)

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 22
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Control Center"
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontCaption
                    color: Theme.textLow
                }

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: "pinned"
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontCaption
                    color: Theme.textFaint
                }
            }
        }

        // Insertion caret in the row gap — an overlay, so rows never move.
        Rectangle {
            id: caret
            visible: page.dragActive && page.dropAt !== null && page.dropAt.col === column.colId
            x: 2
            width: parent.width - 4
            height: 2
            radius: 1
            y: page.rowsStartY + (page.dropAt ? page.dropAt.idx : 0) * page.pitch - 2.5
            color: Theme.accent
            z: 10
        }

        RectangularShadow {
            visible: caret.visible
            anchors.fill: caret
            radius: 1
            blur: 8
            color: Theme.accentAlpha(0.8)
            z: 9
        }
    }

    // ---- layout -----------------------------------------------------------
    SectionHeader {
        id: previewHeader
        label: "LIVE PREVIEW"
        dirty: Settings.modsModified
        onResetRequested: Settings.resetKeys(["mods"])
    }

    Rectangle {
        id: miniBar
        anchors.top: previewHeader.bottom
        anchors.topMargin: 10
        width: parent.width
        height: 30
        radius: 9
        color: Theme.cardFill

        // Chips laid out at token size in a 0.72-scaled space, matching the
        // design's miniature scale without a sub-floor pixel size.
        Item {
            width: parent.width / 0.72
            height: parent.height / 0.72
            scale: 0.72
            transformOrigin: Item.TopLeft

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                Repeater {
                    model: Settings.mods.left
                    delegate: MiniChip {}
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                Repeater {
                    model: Settings.mods.center
                    delegate: MiniChip {}
                }
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3

                Repeater {
                    model: Settings.mods.right
                    delegate: MiniChip {}
                }

                Rectangle {
                    height: 18
                    width: ccText.implicitWidth + 10
                    radius: 4
                    color: Theme.accentAlpha(0.14)

                    Text {
                        id: ccText
                        anchors.centerIn: parent
                        text: "CC"
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.fontCaption
                        font.weight: Theme.weightMedium
                        color: Theme.textHi
                        renderType: Text.QtRendering
                    }
                }
            }
        }
    }

    Item {
        id: columnsRow
        anchors.top: miniBar.bottom
        anchors.topMargin: 10
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: footnote.top
        anchors.bottomMargin: 8

        readonly property real unit: (width - 16) / 3.15

        ModuleColumn {
            id: colL
            x: 0
            width: columnsRow.unit
            height: parent.height
            colId: "left"
            title: "LEFT"
        }

        ModuleColumn {
            id: colC
            x: columnsRow.unit + 8
            width: columnsRow.unit
            height: parent.height
            colId: "center"
            title: "CENTER"
        }

        ModuleColumn {
            id: colR
            x: (columnsRow.unit + 8) * 2
            width: columnsRow.unit * 1.15
            height: parent.height
            colId: "right"
            title: "RIGHT"
        }
    }

    Text {
        id: footnote
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        text: "Auto-hide rules stay: Media only while playing · Bluetooth only when connected · Battery on laptops"
        font.family: Theme.fontMenu
        font.pixelSize: Theme.fontCaption
        color: Theme.textFaint
    }

    // Floating proxy row that follows the pointer during a drag.
    Rectangle {
        visible: page.dragActive
        x: columnsRow.x + page.dragPos.x + 8
        y: columnsRow.y + page.dragPos.y - 14
        width: proxyRow.implicitWidth + 16
        height: 28
        radius: 7
        color: Theme.popBg
        border.width: 1
        border.color: Theme.popBorder
        opacity: 0.92
        z: 30

        Row {
            id: proxyRow
            anchors.centerIn: parent
            spacing: 6

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "⠿"
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontCaption
                color: Theme.textDim
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: page.dragMod ? page.dragMod.name : ""
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontCaption
                color: Theme.textHi
            }
        }
    }
}
