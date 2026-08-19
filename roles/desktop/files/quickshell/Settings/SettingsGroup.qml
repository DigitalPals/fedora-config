import QtQuick
import "../Common"

// A consistent card for one coherent group of settings. The card owns the
// section title and optional reset action; callers only supply the rows.
Rectangle {
    id: root

    default property alias content: contentColumn.data
    property string title: ""
    property bool dirty: false
    property int padding: 14
    property int rowSpacing: 4
    signal resetRequested()

    readonly property int headingHeight: title === "" ? 0 : 26
    readonly property int headingGap: title === "" ? 0 : 8
    readonly property real availableContentHeight: Math.max(0,
        height - padding * 2 - headingHeight - headingGap)

    implicitHeight: padding * 2 + headingHeight + headingGap
        + contentColumn.childrenRect.height
    radius: Theme.cardRadius
    color: Theme.cardFill
    border.width: 1
    border.color: Theme.hairlineSoft

    Text {
        id: heading
        visible: root.title !== ""
        x: root.padding
        y: root.padding
        width: Math.max(0, resetAction.x - x - 8)
        height: root.headingHeight
        verticalAlignment: Text.AlignVCenter
        text: root.title.toUpperCase()
        font.family: Theme.fontMenu
        font.pixelSize: Theme.fontCaption
        font.weight: Theme.weightSemibold
        font.letterSpacing: 0.6
        color: Theme.textDim
        elide: Text.ElideRight
    }

    SettingsAction {
        id: resetAction
        visible: root.title !== "" && root.dirty
        anchors.right: parent.right
        anchors.rightMargin: root.padding - 4
        y: root.padding - 2
        compact: true
        text: "Reset " + root.title.toLowerCase()
        glyph: "↺"
        onTriggered: root.resetRequested()
    }

    Column {
        id: contentColumn
        x: root.padding
        y: root.padding + root.headingHeight + root.headingGap
        width: parent.width - root.padding * 2
        spacing: root.rowSpacing
    }
}
