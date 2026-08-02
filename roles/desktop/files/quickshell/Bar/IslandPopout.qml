import QtQuick
import QtQuick.Effects
import Quickshell.Widgets
import "../Common"

// One popout surface per bar section (caelestia-style, design t5).
// The surface hangs directly under the unified bar slab — same color,
// zero gap, square top corners, rounded bottom corners; clicking a
// sibling module on the same section swaps the content in place, and
// opening another section's popout closes this one. Unanimated: popouts
// appear and dismiss instantly.
Item {
    id: host

    required property rect islandRect
    required property string isle // "left" | "center" | "right"
    // False on outputs whose bar is currently hidden: keeps their panels
    // unloaded instead of building a second copy of every popover.
    required property bool live

    anchors.fill: parent

    // Every panel any island can host; a name may appear on several
    // islands (Wi-Fi opens right from the bar, left from Control Center).
    readonly property var sources: ({
            control: "../Popovers/ControlCenterPopover.qml",
            calendar: "../Popovers/CalendarPopover.qml",
            media: "../Popovers/MediaPopover.qml",
            weather: "../Popovers/WeatherPopover.qml",
            usage: "../Popovers/UsagePopover.qml",
            t3code: "../Popovers/T3CodePopover.qml",
            audio: "../Popovers/AudioPopover.qml",
            wifi: "../Popovers/WifiPopover.qml",
            bluetooth: "../Popovers/BluetoothPopover.qml",
            tailscale: "../Popovers/TailscalePopover.qml",
            battery: "../Popovers/BatteryPopover.qml",
            notifications: "../Popovers/NotifsPopover.qml"
        })

    // Panel this surface is showing. No transitions: the popout appears
    // and disappears instantly.
    property string panelName: ""
    property bool shown: false

    function sync() {
        const want = live && Popouts.open && Popouts.island === isle;
        if (want) {
            panelName = Popouts.currentName;
            shown = true;
        } else if (shown) {
            shown = false;
            panelName = "";
        }
    }

    Connections {
        target: Popouts

        function onChanged() {
            host.sync();
        }
    }

    onLiveChanged: sync()
    Component.onCompleted: sync()

    // ---- geometry -----------------------------------------------------

    readonly property real contentW: loader.item ? loader.item.implicitWidth : Theme.popWidth
    readonly property real contentH: loader.item ? loader.item.implicitHeight : 0

    // The panel hangs under the module that opened it. Panels opened
    // without one (IPC, a keybind) fall back to the island: left anchors
    // left, right anchors right, center expands to its own full width.
    readonly property bool anchored: Popouts.anchorRect.width > 0

    readonly property real surfaceW: {
        const w = !anchored && isle === "center" ? Math.max(islandRect.width, contentW) : contentW;
        return Math.min(w, host.width - 2 * Theme.barSideMargin);
    }

    readonly property real surfaceX: {
        let x;
        if (anchored)
            x = Popouts.anchorRect.x + (Popouts.anchorRect.width - surfaceW) / 2;
        else if (isle === "left")
            x = islandRect.x;
        else if (isle === "right")
            x = islandRect.x + islandRect.width - surfaceW;
        else
            x = islandRect.x + (islandRect.width - surfaceW) / 2;
        // Never off the screen edge: a module near a corner pulls its
        // panel back to the bar's own margin.
        return Math.max(Theme.barSideMargin, Math.min(host.width - Theme.barSideMargin - surfaceW, x));
    }

    // Zero gap: flush against the island's bottom edge.
    readonly property real surfaceY: islandRect.y + islandRect.height
    readonly property real requiredHeight: shown ? surfaceY + contentH + 34 : 0

    readonly property alias maskItem: surface

    // ---- popout shadow ------------------------------------------------
    // The bar slab draws its own shadow in Bar.qml; the panel only
    // shades itself.
    RectangularShadow {
        visible: surface.visible
        x: surface.x
        y: surface.y
        width: surface.width
        height: surface.height
        radius: Theme.popRadius
        blur: 48
        spread: 0
        offset.y: 16
        color: Qt.rgba(0, 0, 0, 0.5)
    }

    // ---- surface ------------------------------------------------------

    ClippingRectangle {
        id: surface

        visible: height > 0.5 && host.panelName !== ""
        x: host.surfaceX
        y: host.surfaceY
        width: Math.max(1, host.surfaceW)
        height: host.shown ? host.contentH : 0
        color: Theme.popBg
        // The bar slab spans the full width above, so the panel's top
        // edge is always tucked beneath it: square top corners.
        topLeftRadius: 0
        topRightRadius: 0
        bottomLeftRadius: Theme.popRadius
        bottomRightRadius: Theme.popRadius

        FocusScope {
            anchors.fill: parent
            focus: host.shown

            Keys.onEscapePressed: Popouts.close()

            // Content pinned to the anchor edge. An anchored surface is
            // already the content's width, so it only matters for the
            // island fallback.
            Item {
                id: contentBox
                x: !host.anchored && host.isle === "right" ? surface.width - host.contentW : 0
                y: 0
                width: host.contentW
                height: host.contentH

                Loader {
                    id: loader
                    focus: true
                    active: host.panelName !== ""
                    source: active ? host.sources[host.panelName] : ""

                    // The fused surface draws the background.
                    onLoaded: {
                        if (item.drawBackground !== undefined)
                            item.drawBackground = false;
                    }
                }
            }
        }
    }

    // Seam cover: a hairline strip across the bar/panel junction so edge
    // anti-aliasing never shows a gap between the joined shapes.
    Rectangle {
        visible: surface.visible
        x: surface.x
        y: host.surfaceY - 2
        width: surface.width
        height: 4
        color: Theme.popBg
    }
}
