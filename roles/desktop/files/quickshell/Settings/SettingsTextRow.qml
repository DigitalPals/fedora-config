import QtQuick
import "../Common"

// [label 90][framed text input][undo 18] (design v2 value rows). Commits on
// Enter or focus loss; the caller normalizes and the display snaps back to
// whatever the store kept. Escape restores the stored value locally without
// reaching the panel's escape chain.
Item {
    id: root

    property string label
    property string value: ""
    property string placeholder: ""
    property bool numeric: false
    property bool dirty: false
    readonly property bool narrow: width < 440
    readonly property int labelWidth: Settings.font === "mono" ? 122 : 90
    signal committed(string text)
    signal resetRequested()

    height: narrow ? 52 : 32

    onValueChanged: {
        if (!input.activeFocus)
            input.text = value;
    }

    Text {
        id: labelText
        anchors.left: parent.left
        y: root.narrow ? 0 : (parent.height - height) / 2
        width: root.narrow ? parent.width - 100 : root.labelWidth
        text: root.label
        font.family: Theme.fontMenu
        font.pixelSize: Theme.fontCaption
        color: Theme.textMid
    }

    Rectangle {
        id: frame
        x: root.narrow ? 0 : root.labelWidth
        y: root.narrow ? 23 : (parent.height - height) / 2
        width: root.narrow ? parent.width - undoSlot.width - 2 : undoSlot.x - x - 2
        height: 28
        radius: 7
        color: input.activeFocus ? Theme.hoverFillStrong : Theme.cardFill
        border.width: input.activeFocus ? 1 : 0
        border.color: Theme.accent

        TextInput {
            id: input
            anchors.left: parent.left
            anchors.leftMargin: 9
            anchors.right: parent.right
            anchors.rightMargin: 9
            anchors.verticalCenter: parent.verticalCenter
            font.family: root.numeric ? Theme.fontMono : Theme.fontMenu
            font.pixelSize: Theme.fontCaption
            color: Theme.textHi
            selectionColor: Theme.accentBg
            selectedTextColor: Theme.textHi
            clip: true
            activeFocusOnTab: true
            inputMethodHints: root.numeric ? Qt.ImhFormattedNumbersOnly : Qt.ImhNone
            Accessible.role: Accessible.EditableText
            Accessible.name: root.label
            Component.onCompleted: text = root.value
            onEditingFinished: {
                if (text !== root.value)
                    root.committed(text);
                // The store may have normalized the commit into a different
                // value (or rejected it); reflect what actually stuck.
                Qt.callLater(() => text = root.value);
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    text = root.value;
                    focus = false;
                    event.accepted = true;
                }
            }

            Text {
                visible: input.text === ""
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                text: root.placeholder
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontCaption
                color: Theme.textFaint
                elide: Text.ElideRight
            }
        }

        MouseArea {
            anchors.fill: parent
            visible: !input.activeFocus
            cursorShape: Qt.IBeamCursor
            onClicked: input.forceActiveFocus()
        }
    }

    Item {
        id: undoSlot
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 28
        height: 28

        UndoChip {
            visible: root.dirty
            onClicked: root.resetRequested()
        }
    }
}
