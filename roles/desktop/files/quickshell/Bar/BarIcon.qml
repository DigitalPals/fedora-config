import QtQuick
import "../Common"

// A glyph button in a bar cluster: nerd-font icon, optional mono label,
// optional accent (active) or red (alert) pill state.
Rectangle {
    id: root

    property string glyph
    property real glyphSize: 13
    property string label: ""
    property real labelSize: 11.5
    property bool active: false
    // Subtle open-state: the module's popout is expanded below it (t5).
    property bool held: false
    property bool alert: false
    property color idleColor: Theme.icon
    property color hoverColor: Theme.textHi
    property int hPadding: 8
    property string tooltip: ""
    signal clicked(real mouseX)
    signal entered

    readonly property color fg: active ? Theme.accentFg : alert ? Theme.redText : held || mouse.hovered ? hoverColor : idleColor

    implicitHeight: 22
    implicitWidth: inner.implicitWidth + hPadding * 2
    radius: Theme.chipRadius
    color: active ? Theme.accent : alert ? Theme.redBg : held ? Theme.hoverFillStrong : mouse.hovered ? Theme.hoverFill : "transparent"
    anchors.verticalCenter: parent.verticalCenter

    Row {
        id: inner
        anchors.centerIn: parent
        spacing: 4

        Text {
            visible: root.glyph !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.glyph
            font.family: Theme.fontIcon
            font.pixelSize: root.glyphSize
            color: root.fg
        }

        Text {
            visible: root.label !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            font.family: Theme.fontMono
            font.pixelSize: root.labelSize
            font.weight: root.alert ? 600 : 500
            color: root.alert ? Theme.redText : root.fg
        }
    }

    MouseArea {
        id: mouse
        property bool hovered: false
        anchors.fill: parent
        hoverEnabled: true
        onEntered: {
            hovered = true;
            root.entered();
        }
        onExited: hovered = false
        onClicked: mouse => root.clicked(mouse.x)
    }
}
