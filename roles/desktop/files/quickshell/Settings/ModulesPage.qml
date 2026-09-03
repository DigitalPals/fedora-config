pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Controls as Controls
import "../Common"
import "../Common/LayoutHelpers.js" as LayoutHelpers
import "../Common/WidgetCatalog.js" as WidgetCatalog

// Widgets page (design v2): live mini-bar preview and three drag-and-drop
// columns. Rows never shift during a drag — an overlay caret marks the
// insertion gap, a floating proxy follows the pointer, and the commit uses
// the prototype's exact splice semantics.
//
// The same edit can now be made on the bar itself by dragging a widget along
// it. Both paths commit through LayoutHelpers.moveWidget, so a drop means the
// same thing whichever surface it was made on.
Item {
    id: page

    readonly property var widgetMeta: WidgetCatalog.WIDGETS

    // ---- drag state -------------------------------------------------------
    property var dragMod: null     // { id, name, fromCol }
    property var dropAt: null      // { col, idx }, idx ∈ [0, len]
    property point dragPos: Qt.point(0, 0)
    property string announcement: ""
    readonly property bool dragActive: dragMod !== null

    // ---- per-widget settings sub-page -------------------------------------
    property string subPage: ""
    readonly property bool subPageActive: subPage !== ""

    function openSubPage(id) {
        if (dragActive)
            return;
        subPage = id;
        announcement = widgetMeta[id].name + " settings.";
    }

    function closeSubPage() {
        const id = subPage;
        subPage = "";
        announcement = "Widget list.";
        Qt.callLater(() => focusModule(id));
    }

    readonly property int pitch: 31          // 28px row + 3px gap
    readonly property int rowsStartY: 20     // column header + gap
    // Three useful columns need enough room for full widget names, switches,
    // and settings buttons. Below this threshold retain the stacked workflow.
    readonly property bool stacked: width < 640
    readonly property var columnOrder: ["left", "center", "right"]

    function cancelDrag() {
        const focusId = dragMod ? dragMod.id : "";
        dragMod = null;
        dropAt = null;
        edgeScroll.stop();
        if (focusId !== "")
            Qt.callLater(() => focusModule(focusId));
    }

    function columnIdAt(x, y) {
        if (stacked) {
            if (y < colC.y)
                return "left";
            if (y < colR.y)
                return "center";
            return "right";
        }
        if (x < colC.x - 4)
            return "left";
        if (x < colR.x - 4)
            return "center";
        return "right";
    }

    function updateDrop(pos) {
        if (pos.x < 0 || pos.x > columnsRow.width
                || pos.y < rowsStartY - pitch || pos.y > columnsRow.height) {
            dropAt = null;
            return;
        }
        let next;
        if (stacked) {
            next = LayoutHelpers.stackedDropIndex([
                { id: "left", y: colL.y, height: colL.height, rowsStart: rowsStartY,
                    pitch: pitch, length: Settings.mods.left.length },
                { id: "center", y: colC.y, height: colC.height, rowsStart: rowsStartY,
                    pitch: pitch, length: Settings.mods.center.length },
                { id: "right", y: colR.y, height: colR.height, rowsStart: rowsStartY,
                    pitch: pitch, length: Settings.mods.right.length }
            ], pos.y);
        } else {
            const col = columnIdAt(pos.x, pos.y);
            const list = Settings.mods[col];
            const local = pos.y - rowsStartY;
            next = { col: col, idx: Math.max(0, Math.min(list.length,
                Math.floor((local + pitch / 2) / pitch))) };
        }
        if (!dropAt || dropAt.col !== next.col || dropAt.idx !== next.idx)
            dropAt = next;
    }

    function keyboardToggle(row) {
        if (!dragActive) {
            dragMod = { id: row.modelData.id, name: row.meta.name, fromCol: row.colId };
            dropAt = { col: row.colId, idx: row.index };
            announcement = row.meta.name + " picked up. Use arrow keys to move.";
        } else {
            commitDrag();
        }
    }

    function keyboardMove(key) {
        if (!dragActive || !dropAt)
            return false;
        let colIndex = columnOrder.indexOf(dropAt.col);
        if (key === Qt.Key_Left)
            colIndex = Math.max(0, colIndex - 1);
        else if (key === Qt.Key_Right)
            colIndex = Math.min(columnOrder.length - 1, colIndex + 1);
        else if (key !== Qt.Key_Up && key !== Qt.Key_Down)
            return false;
        const col = columnOrder[colIndex];
        let idx = dropAt.idx;
        if (key === Qt.Key_Up)
            idx--;
        else if (key === Qt.Key_Down)
            idx++;
        idx = Math.max(0, Math.min(Settings.mods[col].length, idx));
        dropAt = { col: col, idx: idx };
        revealDrop();
        return true;
    }

    function commitDrag() {
        if (!dragMod || !dropAt) {
            cancelDrag();
            return;
        }
        // Shared with the bar's own drag, so a drop lands in the same place
        // whichever surface it was made on.
        const result = LayoutHelpers.moveWidget(Settings.mods, dragMod.fromCol,
            dragMod.id, dropAt.col, dropAt.idx);
        if (!result) {
            cancelDrag();
            return;
        }
        const focusId = dragMod.id;
        announcement = WidgetCatalog.widgetName(focusId)
            + " dropped in " + result.col + " position " + (result.idx + 1) + ".";
        Settings.setModuleOrder(result.mods.left, result.mods.center,
            result.mods.right);
        dragMod = null;
        dropAt = null;
        edgeScroll.stop();
        Qt.callLater(() => focusModule(focusId));
    }

    function focusModule(id) {
        const columns = [colL, colC, colR];
        for (const column of columns) {
            const row = column.rowForId(id);
            if (row) {
                row.forceActiveFocus();
                revealRow(row);
                return;
            }
        }
    }

    function focusAdjacent(row, key) {
        let colIndex = columnOrder.indexOf(row.colId);
        let rowIndex = row.index;
        if (key === Qt.Key_Up)
            rowIndex--;
        else if (key === Qt.Key_Down)
            rowIndex++;
        else if (key === Qt.Key_Left)
            colIndex--;
        else if (key === Qt.Key_Right)
            colIndex++;
        else
            return false;
        colIndex = Math.max(0, Math.min(columnOrder.length - 1, colIndex));
        const column = colIndex === 0 ? colL : colIndex === 1 ? colC : colR;
        rowIndex = Math.max(0, Math.min(column.list.length - 1, rowIndex));
        const target = column.rowAt(rowIndex);
        if (target) {
            target.forceActiveFocus();
            revealRow(target);
        }
        return true;
    }

    function revealRow(row) {
        const point = row.mapToItem(columnsRow, 0, 0);
        if (point.y < columnsViewport.contentY)
            columnsViewport.contentY = Math.max(0, point.y - 4);
        else if (point.y + row.height > columnsViewport.contentY + columnsViewport.height)
            columnsViewport.contentY = Math.min(columnsViewport.contentHeight - columnsViewport.height,
                point.y + row.height - columnsViewport.height + 4);
    }

    function revealDrop() {
        if (!dropAt)
            return;
        const column = dropAt.col === "left" ? colL : dropAt.col === "center" ? colC : colR;
        const y = column.y + rowsStartY + dropAt.idx * pitch;
        if (y < columnsViewport.contentY + 12)
            columnsViewport.contentY = Math.max(0, y - 12);
        else if (y > columnsViewport.contentY + columnsViewport.height - 12)
            columnsViewport.contentY = Math.min(columnsViewport.contentHeight - columnsViewport.height,
                y - columnsViewport.height + 12);
    }

    // ---- components -------------------------------------------------------
    component MiniChip: Rectangle {
        required property var modelData

        readonly property bool on: modelData.on

        height: 18
        width: Math.min(104, chipText.implicitWidth + 12)
        radius: 4
        color: on ? Theme.chip : "transparent"
        border.width: on ? 0 : 1
        border.color: Theme.stroke

        Text {
            id: chipText
            anchors.centerIn: parent
            width: parent.width - 10
            horizontalAlignment: Text.AlignHCenter
            text: page.widgetMeta[parent.modelData.id].short
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontCaption
            font.weight: Theme.weightMedium
            color: parent.on ? Theme.textMid : Theme.textFaint
            elide: Text.ElideRight
        }
    }

    component ModuleRow: Rectangle {
        id: row

        required property var modelData
        required property int index
        required property string colId

        readonly property var meta: page.widgetMeta[modelData.id]
        readonly property bool dragged: page.dragMod !== null && page.dragMod.id === modelData.id

        width: parent.width
        height: 28
        radius: 7
        color: modelData.on ? Theme.cardFill : "transparent"
        border.width: activeFocus ? 1 : 0
        border.color: activeFocus ? Theme.accent : Theme.hairline
        opacity: row.dragged ? 0.35 : modelData.on ? 1 : 0.55
        activeFocusOnTab: index === 0 && (colId === "left"
            || (Settings.mods.left.length === 0 && colId === "center")
            || (Settings.mods.left.length === 0 && Settings.mods.center.length === 0
                && colId === "right"))
        Accessible.role: Accessible.ListItem
        Accessible.name: row.meta.name
        Accessible.description: page.dragActive ? "Drag in progress" : "Press Space to pick up"
        Accessible.selected: row.dragged
        Accessible.onPressAction: page.keyboardToggle(row)
        onActiveFocusChanged: {
            if (activeFocus)
                page.revealRow(row);
        }

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Space) {
                page.keyboardToggle(row); event.accepted = true;
            } else if (event.key === Qt.Key_Escape && page.dragActive) {
                page.cancelDrag(); event.accepted = true;
            } else if (page.keyboardMove(event.key)) {
                event.accepted = true;
            } else if (!page.dragActive && page.focusAdjacent(row, event.key)) {
                event.accepted = true;
            }
        }

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
                    page.announcement = row.meta.name + " picked up.";
                    edgeScroll.start();
                }
                page.dragPos = dragArea.mapToItem(columnsViewport, mouse.x, mouse.y);
                page.updateDrop(Qt.point(page.dragPos.x,
                    page.dragPos.y + columnsViewport.contentY));
            }
            onReleased: {
                if (page.dragActive)
                    page.commitDrag();
            }
            onCanceled: page.cancelDrag()
            onClicked: row.forceActiveFocus()
        }

        Item {
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.right: cogButton.visible ? cogButton.left : rowSwitch.left
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
                // Optional tags yield to the complete module name. Never make
                // the name elide merely to preserve secondary metadata.
                visible: row.meta.tag !== undefined
                    && rowName.implicitWidth + implicitWidth + rowHandle.width + 18 <= parent.width
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: row.meta.tag ?? ""
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontCaption
                color: Theme.textFaint
            }
        }

        Rectangle {
            id: cogButton
            visible: row.meta.detail === true
                || Settings.defaults.modOpts[row.modelData.id] !== undefined
            anchors.right: rowSwitch.left
            anchors.rightMargin: 1
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            height: 22
            radius: 5
            color: cogMouse.containsMouse || activeFocus ? Theme.hoverFill : "transparent"
            border.width: activeFocus ? 1 : 0
            border.color: Theme.accent
            activeFocusOnTab: visible
            onActiveFocusChanged: {
                if (activeFocus)
                    page.revealRow(row);
            }
            Accessible.role: Accessible.Button
            Accessible.name: row.meta.name + " settings"
            Accessible.onPressAction: page.openSubPage(row.modelData.id)
            Controls.ToolTip.visible: cogMouse.containsMouse
            Controls.ToolTip.text: "Widget settings"

            // Dirty when the detail policy or any widget option left default.
            readonly property bool optsDirty: row.modelData.detail !== "auto"
                || (Settings.defaults.modOpts[row.modelData.id] !== undefined
                    && JSON.stringify(Settings.modOpts[row.modelData.id])
                        !== JSON.stringify(Settings.defaults.modOpts[row.modelData.id]))

            Sym {
                anchors.centerIn: parent
                name: "\u{F0493}"
                size: Theme.iconSmall
                color: cogButton.optsDirty ? Theme.accent : Theme.textDim
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                        || event.key === Qt.Key_Space) {
                    page.openSubPage(row.modelData.id);
                    event.accepted = true;
                }
            }

            MouseArea {
                id: cogMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    cogButton.forceActiveFocus();
                    page.openSubPage(row.modelData.id);
                }
            }
        }

        Toggle {
            id: rowSwitch
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            metrics: Theme.switchCompact
            checked: row.modelData.on
            accessibleName: "Show " + row.meta.name
            onActiveFocusChanged: {
                if (activeFocus)
                    page.revealRow(row);
            }
            onToggled: value => Settings.setModuleEnabled(row.modelData.id, value)
        }
    }

    component ModuleColumn: Item {
        id: column

        required property string colId
        required property string title

        readonly property var list: Settings.mods[colId]
        readonly property int naturalHeight: page.rowsStartY
            + list.length * page.pitch

        function rowForId(id) {
            const index = list.findIndex(candidate => candidate.id === id);
            return index >= 0 ? rowRepeater.itemAt(index) : null;
        }


        function rowAt(index) {
            return rowRepeater.itemAt(index);
        }

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
                id: rowRepeater
                model: column.list
                delegate: ModuleRow { colId: column.colId }
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
        visible: !detailLoader.item
        label: "LIVE PREVIEW"
        dirty: Settings.modsModified
        onResetRequested: Settings.resetKeys(["mods"], "Widgets")
    }

    Rectangle {
        id: miniBar
        visible: !detailLoader.item
        anchors.top: presetRow.bottom
        anchors.topMargin: 10
        width: parent.width
        height: 30
        radius: 9
        color: Theme.cardFill
        clip: true

        // Chips laid out at token size in a 0.72-scaled space, matching the
        // design's miniature scale without a sub-floor pixel size.
        Item {
            width: parent.width / 0.72
            height: parent.height / 0.72
            scale: 0.72
            transformOrigin: Item.TopLeft

            Item {
                id: previewLeftLane
                x: 8
                y: 0
                width: Math.max(0, parent.width / 3 - 12)
                height: parent.height
                clip: true
                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    Repeater { model: Settings.mods.left; delegate: MiniChip {} }
                }
            }

            Item {
                id: previewCenterLane
                x: parent.width / 3 + 4
                y: 0
                width: Math.max(0, parent.width / 3 - 8)
                height: parent.height
                clip: true
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    Repeater { model: Settings.mods.center; delegate: MiniChip {} }
                }
            }

            Item {
                id: previewRightLane
                x: parent.width * 2 / 3 + 4
                y: 0
                width: Math.max(0, parent.width / 3 - 12)
                height: parent.height
                clip: true
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    Repeater { model: Settings.mods.right; delegate: MiniChip {} }
                }
            }
        }
    }

    ResponsiveActionRow {
        id: presetRow
        visible: !detailLoader.item
        anchors.top: previewHeader.bottom
        anchors.topMargin: 6
        width: parent.width
        actionsFirst: true
        description: "Visibility profiles preserve widget order and options"

        SettingsAction { text: "Focused"; onTriggered: Settings.applyModulePreset("focused") }
        SettingsAction { text: "Connected"; onTriggered: Settings.applyModulePreset("connected") }
        SettingsAction { text: "Everything"; onTriggered: Settings.applyModulePreset("everything") }
    }

    Flickable {
        id: columnsViewport
        visible: !detailLoader.item
        anchors.top: miniBar.bottom
        anchors.topMargin: 10
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: footnote.top
        anchors.bottomMargin: 8
        contentWidth: width
        contentHeight: columnsRow.height
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Item {
        id: columnsRow
        width: columnsViewport.width
        height: page.stacked
            ? colL.naturalHeight + colC.naturalHeight + colR.naturalHeight + 16
            : Math.max(columnsViewport.height,
                Math.max(colL.naturalHeight, colC.naturalHeight, colR.naturalHeight))

        readonly property real unit: (width - 16) / 3

        ModuleColumn {
            id: colL
            x: 0
            y: 0
            width: page.stacked ? parent.width : columnsRow.unit
            height: page.stacked ? naturalHeight : parent.height
            colId: "left"
            title: "LEFT"
        }

        ModuleColumn {
            id: colC
            x: page.stacked ? 0 : columnsRow.unit + 8
            y: page.stacked ? colL.y + colL.height + 8 : 0
            width: page.stacked ? parent.width : columnsRow.unit
            height: page.stacked ? naturalHeight : parent.height
            colId: "center"
            title: "CENTER"
        }

        ModuleColumn {
            id: colR
            x: page.stacked ? 0 : (columnsRow.unit + 8) * 2
            y: page.stacked ? colC.y + colC.height + 8 : 0
            width: page.stacked ? parent.width : columnsRow.unit
            height: page.stacked ? naturalHeight : parent.height
            colId: "right"
            title: "RIGHT"
        }
        }
    }

    ScrollChrome {
        visible: columnsViewport.visible && overflow
        anchors.fill: columnsViewport
        target: columnsViewport
    }

    Timer {
        id: edgeScroll
        interval: 16
        repeat: true
        onTriggered: {
            if (!page.dragActive)
                return;
            const edge = 28;
            let delta = 0;
            if (page.dragPos.y < edge)
                delta = -Math.max(2, (edge - page.dragPos.y) / 4);
            else if (page.dragPos.y > columnsViewport.height - edge)
                delta = Math.max(2, (page.dragPos.y - columnsViewport.height + edge) / 4);
            const next = Math.max(0, Math.min(columnsViewport.contentHeight - columnsViewport.height,
                columnsViewport.contentY + delta));
            if (next !== columnsViewport.contentY) {
                columnsViewport.contentY = next;
                page.updateDrop(Qt.point(page.dragPos.x, page.dragPos.y + next));
            }
        }
    }

    Text {
        id: footnote
        visible: !detailLoader.item
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        text: "Drag here or on the bar itself; or Space to pick up, arrows move, Space drops, Escape cancels. The cog opens a widget's settings."
        font.family: Theme.fontMenu
        font.pixelSize: Theme.fontCaption
        color: Theme.textFaint
        wrapMode: Text.Wrap
        maximumLineCount: 2
    }

    // Floating proxy row that follows the pointer during a drag.
    Rectangle {
        visible: page.dragActive
        x: columnsViewport.x + page.dragPos.x + 8
        y: columnsViewport.y + page.dragPos.y - 14
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

    // Per-widget settings sub-page: replaces the list content while open;
    // the list keeps its instance (and scroll position) underneath. Built
    // asynchronously so the cog click is not spent constructing it, which is
    // why the list hides on `detailLoader.item` rather than on subPageActive
    // — the sub-page is transparent, so swapping a frame early would show
    // both, and a frame late would show neither.
    Loader {
        id: detailLoader
        anchors.fill: parent
        active: page.subPageActive
        asynchronous: true
        // Incubation finishes after openSubPage has returned, so the sub-page
        // claims focus here; a callLater would still find item null.
        onLoaded: {
            const detail = item as ModuleDetailView;
            if (page.subPageActive && detail)
                detail.focusFirst();
        }
        sourceComponent: ModuleDetailView {
            moduleId: page.subPage
            moduleName: (page.widgetMeta[page.subPage] ?? ({ name: "" })).name
            hasDetail: (page.widgetMeta[page.subPage] ?? ({})).detail === true
            onBackRequested: page.closeSubPage()
        }
    }

    Item {
        width: 1
        height: 1
        opacity: 0
        Accessible.role: Accessible.AlertMessage
        Accessible.name: page.announcement
    }
}
