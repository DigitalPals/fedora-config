import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import "../Common"
import "../Common/LayoutHelpers.js" as LayoutHelpers

// One persistent connected surface for every bar module. Triggers stay in
// the menubar while this host grows the panel directly from the bar edge.
// Keeping two content slots alive lets geometry morph between modules while
// their views cross-fade.
Item {
    id: host

    required property rect leftIslandRect
    required property rect centerIslandRect
    required property rect rightIslandRect
    required property bool live
    property real outputAvailableHeight: 560

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
            notifications: "../Popovers/NotifsPopover.qml",
            settings: "../Settings/SettingsView.qml"
        })

    property bool presented: false
    property bool closing: false
    property bool geometryAnimations: false
    property bool contentAnimations: true
    property string requestedName: ""
    property string slotAName: ""
    property string slotBName: ""
    property int slotASerial: 0
    property int slotBSerial: 0
    property int requestSerial: 0
    property int frontSlot: -1

    // The native surface keeps a stable transparent envelope for a complete
    // open/switch/close cycle. Only the scene-graph geometry below animates.
    property real envelopeBodyH: 0
    property real targetBodyX: 0
    property real targetBodyW: 1
    property real targetBodyH: 0
    property real targetTabX: 0
    property real targetTabW: 1

    property real renderedBodyX: 0
    property real renderedBodyW: 1
    property real renderedBodyH: 0
    property real openProgress: 0

    // Island rect y values are position-independent distances from the
    // fused screen edge (see Bar.qml). All geometry below is computed in
    // that top-bar frame; for a bottom bar only the SURFACE is mirrored
    // vertically while content and input region get direct flipped math.
    readonly property bool bottomBar: Settings.position === "bottom"

    readonly property rect activeIslandRect: Popouts.island === "left" ? leftIslandRect
        : Popouts.island === "center" ? centerIslandRect : rightIslandRect
    readonly property rect effectiveAnchor: Popouts.anchorRect.width > 0
        ? Popouts.anchorRect : activeIslandRect
    readonly property real barBottom: activeIslandRect.y + activeIslandRect.height
    readonly property real bloomProgress: Math.max(0, Math.min(1, openProgress))
    readonly property var edgeFlares: LayoutHelpers.edgeFlareRadii({
        island: Popouts.island,
        floating: Settings.floating,
        barRadius: Theme.clusterRadius,
        popRadius: Theme.popRadius,
        sideMargin: Theme.barSideMargin,
        bodyX: renderedBodyX,
        bodyW: renderedBodyW,
        width: host.width
    })
    // Each crown remains circular while it opens. Only the outer crown of
    // an edge popout may shrink, and only when the body is close enough to
    // collide with the menubar's rounded-end tangent.
    readonly property real leftFlareRadius: Math.min(
        edgeFlares.left * bloomProgress,
        Math.max(0, renderedBodyH / 2))
    readonly property real rightFlareRadius: Math.min(
        edgeFlares.right * bloomProgress,
        Math.max(0, renderedBodyH / 2))
    readonly property real bridgeLeft: Math.max(Theme.barSideMargin,
        renderedBodyX - leftFlareRadius)
    readonly property real bridgeRight: Math.min(host.width - Theme.barSideMargin,
        renderedBodyX + renderedBodyW + rightFlareRadius)
    // The arc begins at the slab's exact lower edge. Starting it inside the
    // bar clips its horizontal tangent and leaves a visible kink at high DPR.
    readonly property real bridgeY: barBottom
    readonly property real bodyTop: bridgeY
    readonly property real bodyRight: renderedBodyX + renderedBodyW
    readonly property real bodyBottom: bodyTop + Math.max(0, renderedBodyH)
    readonly property real effectiveRadius: Math.max(0.01,
        Math.min(Theme.popRadius, renderedBodyW / 2, Math.max(0.02, renderedBodyH) / 2))
    readonly property real bodyLeftSideTop: bodyTop + leftFlareRadius
    readonly property real bodyRightSideTop: bodyTop + rightFlareRadius
    readonly property real requiredHeight: presented
        ? barBottom + envelopeBodyH + 48
        : 0
    readonly property alias maskItem: hitRegion

    function clamp(value, low, high) {
        return Math.max(low, Math.min(high, value));
    }

    function loaderFor(slot) {
        return slot === 0 ? loaderA : loaderB;
    }

    function nameFor(slot) {
        return slot === 0 ? slotAName : slotBName;
    }

    function setNameFor(slot, name) {
        if (slot === 0)
            slotAName = name;
        else
            slotBName = name;
    }

    function serialFor(slot) {
        return slot === 0 ? slotASerial : slotBSerial;
    }

    function setSerialFor(slot, serial) {
        if (slot === 0)
            slotASerial = serial;
        else
            slotBSerial = serial;
    }

    function geometryFor(item) {
        const anchored = Popouts.anchorRect.width > 0;
        const anchor = effectiveAnchor;
        const contentW = item && item.implicitWidth > 0 ? item.implicitWidth : Theme.popWidth;
        const contentH = item && item.implicitHeight > 0 ? item.implicitHeight : 1;
        const bodyMargin = Theme.barSideMargin + Theme.popRadius;
        const maxW = Math.max(1, host.width - 2 * bodyMargin);
        const bodyW = Math.round(Math.min(!anchored && Popouts.island === "center"
            ? Math.max(activeIslandRect.width, contentW) : contentW, maxW));

        let bodyX;
        if (anchored)
            bodyX = anchor.x + (anchor.width - bodyW) / 2;
        else if (Popouts.island === "left")
            bodyX = activeIslandRect.x;
        else if (Popouts.island === "right")
            bodyX = activeIslandRect.x + activeIslandRect.width - bodyW;
        else
            bodyX = activeIslandRect.x + (activeIslandRect.width - bodyW) / 2;
        bodyX = Math.round(clamp(bodyX, bodyMargin,
            host.width - bodyMargin - bodyW));

        const tabW = Math.round(Math.min(maxW, Math.max(Theme.popoutTabMinWidth,
            anchor.width + 2 * Theme.popoutTabPadding)));
        const tabX = Math.round(clamp(anchor.x + (anchor.width - tabW) / 2,
            Theme.barSideMargin, host.width - Theme.barSideMargin - tabW));
        const collapsedW = Math.max(24,
            Math.min(bodyW, tabW - 2 * Theme.popoutTabRadius));
        const collapsedX = tabX + (tabW - collapsedW) / 2;

        return {
            bodyX: bodyX,
            bodyW: bodyW,
            bodyH: contentH,
            tabX: tabX,
            tabW: tabW,
            collapsedX: collapsedX,
            collapsedW: collapsedW
        };
    }

    // Large surfaces may opt in to the output envelope. The shadow budget
    // is removed before they calculate their implicit size.
    function updateAvailableSize(item) {
        if (!item)
            return;
        const shadowSpace = 48;
        if (item.availableWidth !== undefined)
            item.availableWidth = Math.max(320, host.width
                - 2 * (Theme.barSideMargin + Theme.popRadius + shadowSpace));
        if (item.availableHeight !== undefined)
            item.availableHeight = Math.max(280, host.outputAvailableHeight
                - host.barBottom - shadowSpace);
    }

    function rememberTargets(geometry) {
        targetBodyX = geometry.bodyX;
        targetBodyW = geometry.bodyW;
        targetBodyH = geometry.bodyH;
        targetTabX = geometry.tabX;
        targetTabW = geometry.tabW;
        envelopeBodyH = Math.max(envelopeBodyH, geometry.bodyH * 1.12);
    }

    function snapCollapsed(geometry) {
        geometryAnimations = false;
        openProgress = 0;
        renderedBodyX = geometry.collapsedX;
        renderedBodyW = geometry.collapsedW;
        renderedBodyH = 0;
    }

    function animateToTargets() {
        geometryAnimations = true;
        closing = false;
        renderedBodyX = targetBodyX;
        renderedBodyW = targetBodyW;
        renderedBodyH = targetBodyH;
        openProgress = 1;
    }

    function prepareName(name) {
        if (name === "" || sources[name] === undefined)
            return;

        requestedName = name;
        requestSerial++;
        const slot = frontSlot < 0 ? 0 : 1 - frontSlot;
        const loader = loaderFor(slot);
        const reusable = nameFor(slot) === name && loader.item !== null;
        setSerialFor(slot, requestSerial);

        contentAnimations = false;
        loader.opacity = 0;
        contentAnimations = true;
        if (reusable) {
            // A previously inactive slot already contains this component and
            // therefore will not emit loaded again.
            Qt.callLater(() => slotLoaded(slot));
        } else {
            setNameFor(slot, name);
        }
    }

    function slotLoaded(slot) {
        const serial = serialFor(slot);
        Qt.callLater(() => {
            if (serial !== serialFor(slot)
                    || serial !== requestSerial
                    || !live || !Popouts.open
                    || Popouts.currentName !== nameFor(slot))
                return;

            const loader = loaderFor(slot);
            if (!loader.item)
                return;
            if (loader.item.drawBackground !== undefined)
                loader.item.drawBackground = false;

            updateAvailableSize(loader.item);

            const geometry = geometryFor(loader.item);
            const firstOpen = frontSlot < 0 || openProgress < 0.01;
            const oldSlot = frontSlot;

            presented = true;
            closeTimer.stop();
            rememberTargets(geometry);
            if (firstOpen)
                snapCollapsed(geometry);

            frontSlot = slot;
            if (oldSlot >= 0 && oldSlot !== slot)
                loaderFor(oldSlot).opacity = 0;

            Qt.callLater(() => {
                if (!live || !Popouts.open
                        || Popouts.currentName !== nameFor(slot)
                        || frontSlot !== slot)
                    return;
                animateToTargets();
                revealTimer.slot = slot;
                revealTimer.restart();
            });
        });
    }

    function retargetFront() {
        // During a cross-fade, the outgoing slot remains front until the new
        // component has completed. Ignore its late implicit-size signals or
        // it can overwrite the incoming panel's geometry (notably the
        // 420px Control Center -> 720px Settings transition).
        if (frontSlot < 0 || !Popouts.open
                || nameFor(frontSlot) !== Popouts.currentName)
            return;
        const loader = loaderFor(frontSlot);
        if (!loader.item)
            return;
        updateAvailableSize(loader.item);
        const geometry = geometryFor(loader.item);
        rememberTargets(geometry);
        animateToTargets();
    }

    function beginClose() {
        if (!presented || closing)
            return;
        closing = true;
        revealTimer.stop();
        contentAnimations = true;
        loaderA.opacity = 0;
        loaderB.opacity = 0;

        const collapsedW = Math.max(24,
            targetTabW - 2 * Theme.popoutTabRadius);
        geometryAnimations = true;
        renderedBodyX = targetTabX + (targetTabW - collapsedW) / 2;
        renderedBodyW = collapsedW;
        renderedBodyH = 0;
        openProgress = 0;
        closeTimer.restart();
    }

    function sync() {
        const want = live && Popouts.open && Popouts.currentName !== "";
        if (!want) {
            beginClose();
            return;
        }

        closing = false;
        closeTimer.stop();
        if (frontSlot >= 0 && nameFor(frontSlot) === Popouts.currentName
                && loaderFor(frontSlot).item) {
            presented = true;
            retargetFront();
            if (loaderFor(frontSlot).opacity < 0.99) {
                revealTimer.slot = frontSlot;
                revealTimer.restart();
            }
            return;
        }
        prepareName(Popouts.currentName);
    }

    Connections {
        target: Popouts

        function onChanged() {
            host.sync();
        }
    }

    Connections {
        target: frontSlot === 0 ? loaderA.item : null
        ignoreUnknownSignals: true

        function onImplicitWidthChanged() { host.retargetFront(); }
        function onImplicitHeightChanged() { host.retargetFront(); }
    }

    Connections {
        target: frontSlot === 1 ? loaderB.item : null
        ignoreUnknownSignals: true

        function onImplicitWidthChanged() { host.retargetFront(); }
        function onImplicitHeightChanged() { host.retargetFront(); }
    }

    onLiveChanged: sync()
    onCenterIslandRectChanged: {
        if (Popouts.currentName === "settings")
            retargetFront();
    }
    onWidthChanged: retargetFront()
    onHeightChanged: retargetFront()
    Component.onCompleted: sync()

    Timer {
        id: revealTimer
        property int slot: -1
        interval: Theme.popoutContentRevealDelay
        onTriggered: {
            if (host.live && Popouts.open && host.frontSlot === slot)
                host.loaderFor(slot).opacity = 1;
        }
    }

    Timer {
        id: closeTimer
        interval: Theme.popoutCloseDuration + 50
        onTriggered: {
            if (Popouts.open)
                return;
            host.presented = false;
            host.closing = false;
            host.geometryAnimations = false;
            host.contentAnimations = false;
            host.slotAName = "";
            host.slotBName = "";
            host.frontSlot = -1;
            host.requestedName = "";
            host.envelopeBodyH = 0;
            host.contentAnimations = true;
        }
    }

    Behavior on openProgress {
        enabled: host.geometryAnimations
        NumberAnimation {
            duration: host.closing ? Theme.popoutCloseDuration : Theme.popoutMotionDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: host.closing ? Theme.popoutExitCurve : Theme.popoutEnterCurve
        }
    }
    Behavior on renderedBodyX {
        enabled: host.geometryAnimations
        NumberAnimation {
            duration: host.closing ? Theme.popoutCloseDuration : Theme.popoutMotionDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: host.closing ? Theme.popoutExitCurve : Theme.popoutEnterCurve
        }
    }
    Behavior on renderedBodyW {
        enabled: host.geometryAnimations
        NumberAnimation {
            duration: host.closing ? Theme.popoutCloseDuration : Theme.popoutMotionDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: host.closing ? Theme.popoutExitCurve : Theme.popoutEnterCurve
        }
    }
    Behavior on renderedBodyH {
        enabled: host.geometryAnimations
        NumberAnimation {
            duration: host.closing ? Theme.popoutCloseDuration : Theme.popoutMotionDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: host.closing ? Theme.popoutExitCurve : Theme.popoutEnterCurve
        }
    }
    // Everything inside this frame is authored for a top bar and mirrored
    // wholesale for a bottom bar; text-free geometry only.
    Item {
        id: mirrorFrame
        anchors.fill: parent

        transform: Scale {
            yScale: host.bottomBar ? -1 : 1
            origin.y: host.height / 2
        }

    // The rectangular body owns the broad soft shadow. The connector is
    // opaque and overlaps both the body and the bar tab, so no seam or shadow
    // band remains visible at either join.
    Item {
        x: 0
        // Never let the body shadow tint the bar's final pixel row.
        y: host.barBottom
        width: parent.width
        height: Math.max(0, parent.height - y)
        clip: true

        RectangularShadow {
            visible: host.renderedBodyH > 0.5
            x: host.renderedBodyX
            y: host.bodyTop - parent.y
            width: Math.max(1, host.renderedBodyW)
            height: Math.max(1, host.renderedBodyH)
            radius: host.effectiveRadius
            blur: 48
            spread: 0
            // Mirrored for bottom bars, so it lands downward either way.
            offset.y: host.bottomBar ? -16 : 16
            color: Qt.rgba(0, 0, 0, 0.5)
        }
    }

    Shape {
        anchors.fill: parent
        visible: host.openProgress > 0.001 && host.renderedBodyH > 0.1
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillColor: Theme.popBg
            startX: host.bridgeLeft
            startY: host.bridgeY

            PathLine {
                x: host.bridgeRight
                y: host.bridgeY
            }
            PathArc {
                x: host.bodyRight
                y: host.bodyRightSideTop
                radiusX: Math.max(0.01, host.rightFlareRadius)
                radiusY: Math.max(0.01, host.rightFlareRadius)
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: host.bodyRight
                y: host.bodyBottom - host.effectiveRadius
            }
            PathArc {
                x: host.bodyRight - host.effectiveRadius
                y: host.bodyBottom
                radiusX: host.effectiveRadius
                radiusY: host.effectiveRadius
            }
            PathLine {
                x: host.renderedBodyX + host.effectiveRadius
                y: host.bodyBottom
            }
            PathArc {
                x: host.renderedBodyX
                y: host.bodyBottom - host.effectiveRadius
                radiusX: host.effectiveRadius
                radiusY: host.effectiveRadius
            }
            PathLine {
                x: host.renderedBodyX
                y: host.bodyLeftSideTop
            }
            PathArc {
                x: host.bridgeLeft
                y: host.bridgeY
                radiusX: Math.max(0.01, host.leftFlareRadius)
                radiusY: Math.max(0.01, host.leftFlareRadius)
                direction: PathArc.Counterclockwise
            }
        }
    }
    }

    // The layer-shell input mask can be rectangular; visual clipping remains
    // the curved shape above. Keeping the region tight avoids stealing input
    // from the desktop around the panel. Flipped directly rather than via
    // the mirror frame — mask regions must come from untransformed geometry.
    Item {
        id: hitRegion
        x: Math.min(host.bridgeLeft, host.renderedBodyX)
        y: host.bottomBar ? host.height - host.bodyBottom : host.bridgeY
        width: Math.max(host.bridgeRight, host.bodyRight) - x
        height: Math.max(0, host.bodyBottom - host.bridgeY)
        visible: host.presented && height > 0.5
    }

    Item {
        id: contentClip
        x: host.renderedBodyX
        y: host.bottomBar ? host.height - host.bodyTop - height : host.bodyTop
        width: Math.max(1, host.renderedBodyW)
        height: Math.max(0, host.renderedBodyH)
        clip: true

        FocusScope {
            anchors.fill: parent
            focus: host.presented && Popouts.open

            Keys.onEscapePressed: event => {
                const item = host.frontSlot >= 0
                    ? host.loaderFor(host.frontSlot).item : null;
                if (!item || !item.handleEscape || !item.handleEscape())
                    Popouts.close();
                event.accepted = true;
            }

            Loader {
                id: loaderA
                readonly property bool fillBody: host.slotAName === "settings"
                active: host.slotAName !== ""
                source: active ? host.sources[host.slotAName] : ""
                x: fillBody ? 0 : (parent.width - implicitWidth) / 2
                width: fillBody ? parent.width : implicitWidth
                height: fillBody ? parent.height : implicitHeight
                // Content pins to the fused edge, so growth reveals it from
                // the bar on either position.
                y: fillBody ? 0 : host.bottomBar ? parent.height - implicitHeight : 0
                opacity: 0
                enabled: host.frontSlot === 0 && Popouts.open
                focus: enabled
                z: host.frontSlot === 0 ? 2 : 1
                onLoaded: host.slotLoaded(0)

                Behavior on opacity {
                    enabled: host.contentAnimations
                    NumberAnimation {
                        duration: Theme.popoutContentFadeDuration
                        easing.type: Easing.OutCubic
                    }
                }
            }

            Loader {
                id: loaderB
                readonly property bool fillBody: host.slotBName === "settings"
                active: host.slotBName !== ""
                source: active ? host.sources[host.slotBName] : ""
                x: fillBody ? 0 : (parent.width - implicitWidth) / 2
                width: fillBody ? parent.width : implicitWidth
                height: fillBody ? parent.height : implicitHeight
                y: fillBody ? 0 : host.bottomBar ? parent.height - implicitHeight : 0
                opacity: 0
                enabled: host.frontSlot === 1 && Popouts.open
                focus: enabled
                z: host.frontSlot === 1 ? 2 : 1
                onLoaded: host.slotLoaded(1)

                Behavior on opacity {
                    enabled: host.contentAnimations
                    NumberAnimation {
                        duration: Theme.popoutContentFadeDuration
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }
}
