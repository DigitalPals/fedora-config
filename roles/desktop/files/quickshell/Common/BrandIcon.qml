pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects

// One approved product mark. BrandIcons owns name-to-file resolution; this
// component owns sampling and optional contextual tinting.
//
// Leave colorized false where product identity matters. Menubar and control
// marks set it true so the same canonical SVG follows their shared icon tone.
Item {
    id: root

    property string name: ""
    property bool colorized: false
    property color tint: Theme.icon
    readonly property bool available: BrandIcons.has(name)
    readonly property int status: sourceImage.status

    implicitWidth: Theme.iconMedium
    implicitHeight: Theme.iconMedium
    // Every use sits beside copy or inside a named control; exposing the image
    // as a second accessibility node would announce the same identity twice.
    Accessible.ignored: true

    Image {
        id: sourceImage
        anchors.fill: parent
        source: BrandIcons.source(root.name)
        sourceSize: Qt.size(Math.max(1, Math.round(root.width * 2)),
            Math.max(1, Math.round(root.height * 2)))
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        Accessible.ignored: true

        layer.enabled: root.available && root.colorized
        layer.effect: MultiEffect {
            colorization: 1
            colorizationColor: root.tint
        }
    }
}
