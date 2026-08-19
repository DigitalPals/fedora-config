import QtQuick

// Intentional empty/loading/error treatment for content areas. The loading
// mark is the only continuously animated piece and stops with `shown`, so a
// closed panel or settled state consumes no animation frames.
Item {
    id: root

    property bool shown: true
    property string kind: "empty"
    property string glyph: {
        if (kind === "loading")
            return "progress_activity";
        if (kind === "error")
            return "cloud_off";
        return "inbox";
    }
    property string title: ""
    property string detail: ""

    implicitHeight: shown ? content.implicitHeight + 12 : 0
    visible: shown || opacity > 0.001
    opacity: shown ? 1 : 0
    clip: true

    transform: Translate {
        y: root.shown ? 0 : 8

        Behavior on y {
            NumberAnimation {
                duration: Theme.expandDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.springCurve
            }
        }
    }

    Behavior on implicitHeight {
        NumberAnimation {
            duration: Theme.expandDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.springCurve
        }
    }

    Behavior on opacity {
        NumberAnimation { duration: Theme.chipFadeDuration; easing.type: Easing.OutCubic }
    }

    Column {
        id: content

        anchors.centerIn: parent
        width: Math.min(parent.width, 320)
        spacing: 6

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 44
            height: 44
            radius: 16
            color: root.kind === "error" ? Theme.redBgSoft : Theme.accentBgSoft
            border.width: 1
            border.color: root.kind === "error" ? Theme.redBorder : Theme.hairlineSoft

            Sym {
                id: statusGlyph
                anchors.centerIn: parent
                name: root.glyph
                size: Theme.iconLarge
                fill: root.kind === "loading" ? 0 : 1
                color: root.kind === "error" ? Theme.redText : Theme.accent

                RotationAnimation on rotation {
                    running: root.shown && root.kind === "loading"
                    from: 0
                    to: 360
                    duration: 1100
                    loops: Animation.Infinite
                }
            }
        }

        Text {
            visible: text !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            text: root.title
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontSecondary
            font.weight: Theme.weightSemibold
            color: root.kind === "error" ? Theme.redText : Theme.textMid
        }

        Text {
            visible: text !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            text: root.detail
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
            lineHeight: Theme.proseLineHeight
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontCaption
            color: Theme.textDim
        }
    }
}
