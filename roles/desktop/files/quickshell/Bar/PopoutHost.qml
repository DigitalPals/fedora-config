import QtQuick
import "../Common"
import "../Popovers"
import "../Common/PanelRegistryData.js" as PanelRegistry
import "../Common/Format.js" as Format

// The surface every bar panel is drawn on: one detached card of glass,
// floating a fixed gap below the bar, centred on whatever opened it.
//
// It springs up out of its trigger — scaled down and offset toward the bar,
// with the transform origin pinned to the trigger's own edge — while the
// content eases in a beat earlier, so the copy is legible before the shape has
// finished settling. Switching panels keeps the same card and morphs its
// geometry, which is what makes hovering along the bar read as one surface
// following the pointer rather than a series of windows.
//
// Two content slots stay alive so a switch can cross-fade rather than blink.
Item {
    id: host

    required property rect leftIslandRect
    required property rect centerIslandRect
    required property rect rightIslandRect
    required property bool live
    property real outputAvailableHeight: 560

    // Derived from Common/PanelRegistryData.js, which stores paths from the
    // shell root; this host lives one directory down. The strings this
    // produces are the ones that were hand-written here before.
    readonly property var sources: PanelRegistry.sourceMap("../")

    // Panels whose instance may outlive a close, so reopening them skips
    // incubation entirely. Entry criteria: every piece of state the view
    // holds is derived from a singleton, and nothing in it keeps working
    // while it is hidden.
    readonly property var warmNames: ["control"]

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

    // A little air below the card so a full-height panel does not sit flush
    // against the bottom of the screen, and the margin it will not cross at
    // the sides.
    readonly property int shadowBudget: 20
    readonly property int edgeMargin: Math.max(12, Theme.barSideMargin)

    // Island rects carry a position-independent distance from the bar's
    // anchored screen edge (see Bar.qml), so all geometry is computed in the
    // top-bar frame and mapped at the end.
    readonly property bool bottomBar: Settings.position === "bottom"
    readonly property real barBottom: Theme.barTopMargin + Theme.barHeight

    readonly property rect activeIslandRect: Popouts.island === "left" ? leftIslandRect
        : Popouts.island === "center" ? centerIslandRect : rightIslandRect
    readonly property rect effectiveAnchor: Popouts.anchorRect.width > 0
        ? Popouts.anchorRect : activeIslandRect

    // Where the card is going, and where it is now. The rendered values are
    // what animate; the targets are recomputed whenever the panel or the
    // output changes.
    property real targetX: 0
    property real targetW: Theme.popWidth
    property real targetH: 0
    property real renderedX: 0
    property real renderedW: Theme.popWidth
    property real renderedH: 0
    property real openProgress: 0

    // The point the card grows out of, in its own coordinates: the horizontal
    // centre of the trigger, clamped inside the card.
    property real originX: renderedW / 2

    readonly property real bodyTop: barBottom + Theme.popGap
    // The height the layer surface is asked for. Following the animating
    // renderedH would resize the Wayland surface — and recompute the
    // compositor blur — on every frame of a panel-switch morph. Shrinking it
    // after the springs settle is just as visible: layer-shell sends another
    // configure after the card has apparently finished opening. Keep one
    // monotonically growing envelope for the whole mapped lifetime and reset
    // it only after the close animation has unmapped the surface.
    property real surfaceH: 0
    readonly property real requiredHeight: presented
        ? bodyTop + Math.max(1, surfaceH) + shadowBudget : 0
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

    // At most one slot survives a close: the most recently fronted panel that
    // is safe to keep warm. Everything else is released, so the retained tree
    // stays bounded to a single view no matter how many panels get opened.
    function latchSlot() {
        for (const slot of [frontSlot, 1 - frontSlot]) {
            if (slot < 0 || slot > 1)
                continue;
            if (warmNames.indexOf(nameFor(slot)) !== -1 && loaderFor(slot).item)
                return slot;
        }
        return -1;
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
        const anchor = effectiveAnchor;
        const contentW = item && item.implicitWidth > 0 ? item.implicitWidth : Theme.popWidth;
        const contentH = item && item.implicitHeight > 0 ? item.implicitHeight : 1;
        const maxW = Math.max(1, host.width - 2 * edgeMargin);
        const bodyW = Math.round(Math.min(contentW, maxW));

        // Centred on the trigger, then held inside the screen. A panel wider
        // than the room beside its trigger slides along the edge rather than
        // hanging off it, which is what the design's fixed right offsets do
        // for the panels that are wider than the chips that open them.
        const centred = anchor.x + anchor.width / 2 - bodyW / 2;
        const bodyX = Math.round(clamp(centred, edgeMargin,
            Math.max(edgeMargin, host.width - edgeMargin - bodyW)));

        return {
            bodyX: bodyX,
            bodyW: bodyW,
            bodyH: contentH,
            // Kept in the card's own coordinates and clamped away from the
            // corners: a scale origin sitting outside the shape reads as the
            // card sliding rather than growing.
            originX: clamp(anchor.x + anchor.width / 2 - bodyX,
                Theme.popRadius, Math.max(Theme.popRadius, bodyW - Theme.popRadius))
        };
    }

    // Every panel takes the output envelope, because every panel inherits
    // PopoutPanel. The shadow budget is removed before they calculate their
    // implicit size.
    function envelope() {
        return {
            availableWidth: Math.max(320, host.width - 2 * (edgeMargin + 8)),
            availableHeight: Math.max(280, host.outputAvailableHeight
                - host.bodyTop - host.shadowBudget)
        };
    }

    function updateAvailableSize(item) {
        const panel = item as PopoutPanel;
        if (!panel)
            return;
        const env = envelope();
        panel.availableWidth = env.availableWidth;
        panel.availableHeight = env.availableHeight;
    }

    function rememberTargets(geometry) {
        targetX = geometry.bodyX;
        targetW = geometry.bodyW;
        targetH = geometry.bodyH;
        originX = geometry.originX;
        surfaceH = Math.max(surfaceH, geometry.bodyH);
    }

    function snapClosed(geometry) {
        geometryAnimations = false;
        openProgress = 0;
        renderedX = geometry.bodyX;
        renderedW = geometry.bodyW;
        renderedH = geometry.bodyH;
        surfaceH = geometry.bodyH;
    }

    function animateToTargets() {
        geometryAnimations = true;
        closing = false;
        renderedX = targetX;
        renderedW = targetW;
        renderedH = targetH;
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
        } else if (nameFor(slot) === name && loader.status === Loader.Loading) {
            // A second Popouts.changed while this panel is still incubating —
            // the serial bump above re-armed it; another setSource would
            // restart the incubation from scratch.
        } else {
            // The envelope travels as initial properties, not as post-load
            // writes: a panel's first layout then happens against its real
            // envelope. Writing it after onLoaded made every size that
            // depends on it correct itself one polish later — a visible
            // twitch just after the content appeared.
            const env = envelope();
            loader.setSource(sources[name], {
                drawBackground: false,
                availableWidth: env.availableWidth,
                availableHeight: env.availableHeight
            });
            setNameFor(slot, name);
        }
    }

    function slotLoaded(slot) {
        // Present only once the panel's implicit size has stopped moving. A
        // freshly created panel does not measure once: nested positioners
        // propagate their heights one polish pass per frame — the GitHub
        // inbox walks 28 → 161 → 397 → 661 → 711 over ~70ms — so measuring
        // at onLoaded seated the card at a height the content then corrected
        // in view: a twitch on every cold open, a mid-morph retarget on
        // every switch. Only the newest request may present, so one timer is
        // enough; the serial checks discard anything it supersedes.
        settleLoadTimer.stop();
        settleLoadTimer.slot = slot;
        settleLoadTimer.serial = serialFor(slot);
        settleLoadTimer.lastW = -1;
        settleLoadTimer.lastH = -1;
        settleLoadTimer.checks = 0;
        settleLoadTimer.start();
    }

    Timer {
        id: settleLoadTimer
        property int slot: -1
        property int serial: -1
        property real lastW: -1
        property real lastH: -1
        property int checks: 0
        interval: 24
        repeat: true
        onTriggered: {
            if (serial !== host.serialFor(slot) || serial !== host.requestSerial
                    || !Popouts.open) {
                stop();
                return;
            }
            const item = host.loaderFor(slot).item;
            if (!item) {
                stop();
                return;
            }
            checks++;
            const stable = item.implicitWidth === lastW && item.implicitHeight === lastH;
            lastW = item.implicitWidth;
            lastH = item.implicitHeight;
            // The cap keeps a panel whose content genuinely keeps growing
            // from stalling the reveal; anything after it is an ordinary
            // animated retarget.
            if (stable || checks >= 8) {
                stop();
                host.presentSlot(slot, serial);
            }
        }
    }

    function presentSlot(slot, serial) {
        if (serial !== serialFor(slot)
                || serial !== requestSerial
                || !live || !Popouts.open
                || Popouts.currentName !== nameFor(slot))
            return;

        const loader = loaderFor(slot);
        if (!loader.item)
            return;
        const panel = loader.item as PopoutPanel;
        if (panel)
            panel.drawBackground = false;

        updateAvailableSize(loader.item);

        const geometry = geometryFor(loader.item);
        const firstOpen = frontSlot < 0 || openProgress < 0.01;
        const oldSlot = frontSlot;

        presented = true;
        closeTimer.stop();
        rememberTargets(geometry);
        if (firstOpen)
            snapClosed(geometry);

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
    }

    function retargetFront() {
        // During a cross-fade, the outgoing slot remains front until the new
        // component has completed. Ignore its late implicit-size signals or it
        // can overwrite the incoming panel's geometry.
        if (frontSlot < 0 || !Popouts.open
                || nameFor(frontSlot) !== Popouts.currentName)
            return;
        const loader = loaderFor(frontSlot);
        if (!loader.item)
            return;
        updateAvailableSize(loader.item);
        rememberTargets(geometryFor(loader.item));
        // A correction landing while the card is still fading in is seated
        // instantly: nested positioner heights can only finish settling once
        // the surface renders real frames, so the last step arrives a beat
        // after presentation no matter how long the measurement waited.
        // Springing it read as a twitch; snapping it while the card is at
        // most a third opaque — and the content not yet revealed — is
        // invisible. A switch morph runs at full progress and never takes
        // this branch, so it keeps its one continuous spring.
        if (!closing && openProgress < 0.6) {
            geometryAnimations = false;
            renderedX = targetX;
            renderedW = targetW;
            renderedH = targetH;
            geometryAnimations = true;
        }
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
        geometryAnimations = true;
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
            const loader = loaderFor(frontSlot);
            presented = true;
            // A reused slot starts from wherever the card last closed, which
            // for a latched panel may be a different module's position. Seat
            // it on its own trigger first — as a cold open does — or it sweeps
            // across the bar while it grows.
            if (openProgress < 0.01) {
                updateAvailableSize(loader.item);
                snapClosed(geometryFor(loader.item));
            }
            retargetFront();
            if (loader.opacity < 0.99) {
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

    // A freshly loaded panel settles its implicit size over several frames —
    // async images arriving, list rows binding — and every change used to
    // restart the geometry springs, which read as hitching right at the start
    // of a morph. Collapse each burst to one retarget per frame.
    property bool retargetQueued: false

    function scheduleRetarget() {
        if (retargetQueued)
            return;
        retargetQueued = true;
        Qt.callLater(() => {
            retargetQueued = false;
            retargetFront();
        });
    }

    Connections {
        target: host.frontSlot === 0 ? loaderA.item : null
        ignoreUnknownSignals: true

        function onImplicitWidthChanged() { host.scheduleRetarget(); }
        function onImplicitHeightChanged() { host.scheduleRetarget(); }
    }

    Connections {
        target: host.frontSlot === 1 ? loaderB.item : null
        ignoreUnknownSignals: true

        function onImplicitWidthChanged() { host.scheduleRetarget(); }
        function onImplicitHeightChanged() { host.scheduleRetarget(); }
    }

    onLiveChanged: sync()
    onCenterIslandRectChanged: {
        if (PanelRegistry.centerAnchored(Popouts.currentName))
            retargetFront();
    }
    onWidthChanged: retargetFront()
    onOutputAvailableHeightChanged: retargetFront()
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
        interval: Theme.popoutCloseDuration + 60
        onTriggered: {
            if (Popouts.open)
                return;
            host.presented = false;
            host.surfaceH = 0;
            host.closing = false;
            host.geometryAnimations = false;
            host.contentAnimations = false;
            // Keeping the latched slot in front is what makes the latch pay:
            // sync() reuses frontSlot when its name matches, and prepareName
            // always incubates into the *other* slot, so a different panel
            // still gets a fresh instance.
            const keep = host.latchSlot();
            if (keep !== 0)
                host.slotAName = "";
            if (keep !== 1)
                host.slotBName = "";
            host.frontSlot = keep;
            host.requestedName = keep >= 0 ? host.nameFor(keep) : "";
            host.contentAnimations = true;
        }
    }

    Behavior on openProgress {
        enabled: host.geometryAnimations
        NumberAnimation {
            duration: host.closing ? Theme.panelCloseDuration : Theme.panelMotionDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: host.closing ? Theme.easeInCurve : Theme.springCurve
        }
    }

    Behavior on renderedX {
        enabled: host.geometryAnimations && host.openProgress > 0.01
        NumberAnimation {
            duration: Theme.panelMotionDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.springCurve
        }
    }

    Behavior on renderedW {
        enabled: host.geometryAnimations && host.openProgress > 0.01
        NumberAnimation {
            duration: Theme.panelMotionDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.springCurve
        }
    }

    Behavior on renderedH {
        enabled: host.geometryAnimations && host.openProgress > 0.01
        NumberAnimation {
            duration: Theme.panelMotionDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.springCurve
        }
    }

    // ---- the card -------------------------------------------------------
    Item {
        id: card

        readonly property real settle: Format.clamp01(host.openProgress)

        x: host.renderedX
        y: host.bottomBar
            ? host.height - host.bodyTop - Math.max(1, host.renderedH)
            : host.bodyTop
        width: Math.max(1, host.renderedW)
        height: Math.max(1, host.renderedH)
        visible: host.presented && host.renderedH > 0.5
        opacity: settle

        // Grows out of the trigger: scaled toward it and nudged back against
        // the bar, with the origin pinned to the trigger's centre on the edge
        // the bar is on.
        transform: [
            Scale {
                origin.x: host.originX
                origin.y: host.bottomBar ? card.height : 0
                xScale: 0.955 + 0.045 * card.settle
                yScale: 0.955 + 0.045 * card.settle
            },
            Translate {
                y: (host.bottomBar ? 14 : -14) * (1 - card.settle)
            }
        ]

        Rectangle {
            id: surface
            anchors.fill: parent
            radius: Theme.popRadius
            color: Theme.glassStrong
            border.width: 1
            border.color: Theme.stroke
            clip: true

            Behavior on color {
                ColorAnimation { duration: Theme.surfaceDuration }
            }

            FocusScope {
                anchors.fill: parent
                focus: host.presented && Popouts.open

                Keys.onEscapePressed: event => {
                    // PopoutPanel.handleEscape() answers false by default, so
                    // a panel with nothing to go back to dismisses the popout.
                    const panel = host.frontSlot >= 0
                        ? host.loaderFor(host.frontSlot).item as PopoutPanel : null;
                    if (!panel || !panel.handleEscape())
                        Popouts.close();
                    event.accepted = true;
                }

                Loader {
                    id: loaderA
                    // The source arrives through prepareName's setSource call,
                    // never through a binding: setSource is what carries the
                    // envelope as initial properties, and a source binding
                    // would silently clear them.
                    active: host.slotAName !== ""
                    asynchronous: true
                    // Panels lay out once at their own implicit size and are
                    // revealed by the animating card; sizing them to the card
                    // would relayout the whole tree every morph frame.
                    x: 0
                    y: 0
                    width: Math.max(1, implicitWidth)
                    height: Math.max(1, implicitHeight)
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
                    active: host.slotBName !== ""
                    asynchronous: true
                    x: 0
                    y: 0
                    width: Math.max(1, implicitWidth)
                    height: Math.max(1, implicitHeight)
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

    // The layer-shell input region. Rectangular and untransformed — a mask
    // has to come from real geometry, not from the animating card — and bound
    // to the morph's *target* rather than its per-frame rendered values, so
    // the compositor is told about it once per switch instead of every frame.
    // It stays tight so the desktop around the panel keeps its clicks.
    Item {
        id: hitRegion
        x: host.targetX
        y: host.bottomBar
            ? host.height - host.bodyTop - Math.max(0, host.targetH)
            : host.bodyTop
        width: Math.max(1, host.targetW)
        height: Math.max(0, host.targetH)
        visible: host.presented && host.openProgress > 0.5 && height > 0.5
    }
}
