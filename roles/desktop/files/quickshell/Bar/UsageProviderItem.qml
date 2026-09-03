import QtQuick

// Concrete delegate contract so aggregate measurements from Repeater.itemAt()
// stay statically checked.
Rectangle {
    required property string modelData
    property real detailSaving: 0
}
