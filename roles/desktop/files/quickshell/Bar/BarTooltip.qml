import QtQuick
import "../Common"

Item {
    id: root

    property string text: ""
    property bool hovered: false
    // -1 left, 0 centered, 1 right.
    property int align: 0
    property bool ready: false
    // The bar that owns this tooltip, threaded down from the module rather
    // than reached through Window.window: an attached window is a plain
    // QQuickWindow to the type system, so reading the bar's pointer state off
    // it could not be checked. Null degrades to the local hover state.
    property Bar host: null
    // Validate the local MouseArea state against the bar-wide pointer. This
    // clears stale containsMouse values after a missed surface-exit event and
    // also prevents a tooltip from lingering over a different module.
    readonly property bool pointerOverTarget: {
        // Skip the scene mapping while not hovered: this also drops the
        // binding's dependency on tooltipPointerPosition, so idle tooltips
        // cost nothing on pointer moves elsewhere in the bar.
        if (!root.hovered)
            return false;
        if (!root.host)
            return root.hovered;
        if (!root.host.tooltipPointerInside || !root.parent)
            return false;
        const scenePoint = root.host.tooltipPointerPosition;
        const localPoint = root.parent.mapFromItem(null,
            scenePoint.x, scenePoint.y);
        return localPoint.x >= 0 && localPoint.x <= root.parent.width
            && localPoint.y >= 0 && localPoint.y <= root.parent.height;
    }
    readonly property bool activeHover: hovered && pointerOverTarget

    width: tip.implicitWidth
    height: tip.implicitHeight
    z: 1000
    opacity: ready ? 1 : 0
    // Popouts.open stays a hard cut (see the Connections note below); only
    // hover-driven appearance eases.
    visible: text !== "" && !Popouts.open && opacity > 0.01

    Behavior on opacity {
        NumberAnimation { duration: Theme.chipFadeDuration; easing.type: Easing.OutCubic }
    }

    // Call sites place the tip 6px below their module (y: parent.height + 6);
    // with a bottom bar this shifts it to 6px above instead.
    transform: Translate {
        y: Settings.position === "bottom" && root.parent
            ? -(root.height + root.parent.height + 12) : 0
    }

    onActiveHoverChanged: {
        if (activeHover)
            delay.restart();
        else {
            delay.stop();
            ready = false;
        }
    }

    // Mapping the separate popout surface can prevent the bar MouseArea
    // from receiving its final exit event. Do not carry an armed tooltip
    // across either edge of that surface's lifetime: otherwise it reappears
    // at its old module as soon as the popout closes.
    Connections {
        target: Popouts

        function onOpenChanged() {
            delay.stop();
            root.ready = false;
        }
    }

    Timer {
        id: delay
        interval: 550
        onTriggered: root.ready = root.activeHover
    }

    Rectangle {
        id: tip
        implicitWidth: label.implicitWidth + 14
        implicitHeight: Theme.tooltipHeight
        radius: 6
        color: Theme.popBg
        border.width: 1
        border.color: Theme.popBorder

        Text {
            id: label
            anchors.centerIn: parent
            text: root.text
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontCaption
            color: Theme.textMid
        }
    }
}
