import QtQuick
import "../Common"

Flickable {
    id: root
    default property alias content: contentRoot.data
    property int spacing: Theme.panelSectionSpacing
    readonly property bool scrollbarVisible: contentHeight > height + 1
    // Always reserved: tying the gutter to scrollbarVisible loops, because
    // the narrower content re-wraps taller, which flips scrollbarVisible.
    readonly property int scrollGutter: 8

    contentWidth: width
    contentHeight: contentRoot.childrenRect.height
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height
    clip: true
    flickDeceleration: 3000

    function revealFocus(item) {
        if (!item)
            return;
        const point = item.mapToItem(contentRoot, 0, 0);
        const top = point.y;
        const bottom = top + item.height;
        if (top < contentY)
            contentY = Math.max(0, top - 4);
        else if (bottom > contentY + height)
            contentY = Math.min(contentHeight - height, bottom - height + 4);
    }

    Connections {
        target: root.Window.window
        enabled: target !== null
        function onActiveFocusItemChanged() {
            const item = root.Window.window ? root.Window.window.activeFocusItem : null;
            if (item)
                root.revealFocus(item);
        }
    }

    Item {
        id: contentRoot
        width: root.width - root.scrollGutter
        height: childrenRect.height
    }

    ScrollChrome {
        // Flickable normally reparents declarative children to contentItem;
        // this overlay must stay fixed to the viewport while the page moves.
        parent: root
        anchors.fill: parent
        target: root
    }
}
