import QtQuick
import "../Common"

// The skeleton every settings row shares: the fixed label column on the left,
// the reserved undo column on the right, and the reflow between them when the
// panel is narrow. A concrete row — SwitchRow, PickerRow, SliderRow,
// SettingsTextRow — declares only its control, laid out between `labelWidth`
// and `contentRight`.
//
// `settingKey` names a key in Settings, and a row that sets one needs nothing
// else: `stored` reads the value, `dirty` compares it against the default,
// `commit()` writes it, and the undo chip resets it and announces itself as
// `resetLabel` — the row's own label unless the announcement has to be more
// specific than the label ("Duration" reads as nothing on its own; "Toast
// duration" reads as something).
//
// A row whose value does not live in Settings leaves `settingKey` empty and
// wires `dirty` and `onResetRequested` itself. That is every row in
// ModuleDetailView, which stores per-module options rather than settings.
Item {
    id: root

    property string label
    property color labelColor: Theme.textMid
    property string settingKey: ""
    property string resetLabel: label
    property bool dirty: settingKey !== ""
        && Settings[settingKey] !== Settings.defaults[settingKey]
    // What the undo chip restores — the argument to Settings.resetKeys().
    // Usually just this row's key, but a mode picker whose companion values
    // only make sense under one mode restores them together.
    property var resetKeys: settingKey === "" ? [] : [settingKey]

    // Reflow metrics. Each row reserves a different slice of the narrow line
    // for its own control, and the switch row's label sits 2px lower because
    // its control is taller than the text beside it.
    property int narrowHeight: 52
    property int narrowLabelY: 0
    property int narrowLabelInset: 100
    // Most rows use the theme's compact label column. A page can reserve more
    // room for a longer label without changing every settings page or losing
    // alignment between the rows in that page.
    property int minimumLabelWidth: 0

    signal resetRequested()

    readonly property bool narrow: width < Theme.settingsNarrowWidth
    readonly property int labelWidth: Theme.settingsLabelWidth >= root.minimumLabelWidth
        ? Theme.settingsLabelWidth : root.minimumLabelWidth
    readonly property int undoWidth: 28
    // The undo column is always reserved, so the chip appearing never shifts
    // the row (design v2). Controls stop here rather than at the row's edge.
    readonly property real contentRight: width - undoWidth
    readonly property real labelTextWidth: labelText.width
    readonly property var stored: settingKey === "" ? undefined : Settings[settingKey]

    height: narrow ? narrowHeight : 32

    function commit(value) {
        if (root.settingKey !== "")
            Settings.set(root.settingKey, value);
    }

    function requestReset() {
        if (root.resetKeys.length > 0)
            Settings.resetKeys(root.resetKeys, root.resetLabel);
        root.resetRequested();
    }

    Text {
        id: labelText
        anchors.left: parent.left
        y: root.narrow ? root.narrowLabelY : (parent.height - height) / 2
        width: root.narrow ? parent.width - root.narrowLabelInset : root.labelWidth
        text: root.label
        font.family: Theme.fontMenu
        font.pixelSize: Theme.fontCaption
        color: root.labelColor
    }

    Item {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: root.undoWidth
        height: root.undoWidth

        UndoChip {
            visible: root.dirty
            onClicked: root.requestReset()
        }
    }
}
