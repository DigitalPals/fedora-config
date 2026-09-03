pragma ComponentBehavior: Bound
import QtQuick
import "../../Common"

// The Overview tab's model-usage summary: one row per enabled provider —
// brand mark, name, minimum remaining, and a hairline meter — with the full
// story one tab away. Clicking a row deep-links to that provider's Usage tab.
Column {
    id: root

    readonly property var keys: Usage.providerKeys.filter(k =>
        Settings.modOpts.usage[k] === true)

    width: parent ? parent.width : 0
    spacing: 2

    Repeater {
        model: root.keys

        delegate: Rectangle {
            id: row

            required property string modelData
            readonly property int remaining: Usage.minRemaining(modelData)
            readonly property string status: Usage.chipStatus(modelData)
            readonly property color tone: status === "crit" || status === "error"
                ? Theme.redText : status === "warn" ? Theme.amber : Theme.textHi
            readonly property color barTone: status === "crit" || status === "error"
                ? Theme.red : status === "warn" ? Theme.amber : Theme.accent

            width: parent ? parent.width : 0
            height: 40
            radius: Theme.rowRadius
            color: rowMouse.containsMouse ? Theme.chip : "transparent"

            Behavior on color {
                ColorAnimation { duration: Theme.chipFadeDuration }
            }

            BrandIcon {
                id: mark
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 14
                height: 14
                name: Usage.meta[row.modelData].icon
            }

            Item {
                anchors.left: mark.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                height: 24

                Text {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    text: Usage.meta[row.modelData].title
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontSecondary
                    font.weight: Theme.weightMedium
                    color: Theme.textHi
                }

                Row {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    spacing: 3

                    Text {
                        text: row.remaining >= 0 ? row.remaining : "--"
                        font.family: Theme.fontNumeric
                        font.pixelSize: Theme.fontCaption
                        font.weight: Theme.weightSemibold
                        font.features: Theme.tabularNumberFeatures
                        color: row.tone
                    }

                    Text {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 1
                        text: "left"
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.fontMicro
                        color: Theme.textFaint
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.rightMargin: 24
                    anchors.bottom: parent.bottom
                    height: 3
                    radius: 2
                    color: Qt.rgba(1, 1, 1, 0.10)

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: parent.width
                            * Math.max(0, Math.min(100, row.remaining)) / 100
                        radius: 2
                        color: row.barTone
                        visible: row.remaining >= 0
                    }
                }
            }

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    Usage.selected = row.modelData;
                    Popouts.openPanel("usage", "right");
                }
            }

            Accessible.role: Accessible.Button
            Accessible.name: Usage.meta[row.modelData].title + " usage"
        }
    }
}
