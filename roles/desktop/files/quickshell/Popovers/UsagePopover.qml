pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "../Common"

// Per-provider usage view (design 1a + 1c): brand header with mini
// provider tabs, blocked-bar window cards with status borders and
// absolute reset times, credits card, usage-history block chart.
Surface {
    id: root

    Component.onCompleted: {
        if (Usage.updatedAt > 0) {
            const elapsed = Math.floor((Date.now() - Usage.updatedAt) / 1000);
            Usage.nextPollSecs = Math.max(0, Usage.pollIntervalSecs - elapsed);
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: Usage.nextPollSecs = Math.max(0, Usage.nextPollSecs - 1)
    }

    // Right-island popouts run a touch wider (design t5).
    implicitWidth: Theme.popWideWidth
    padding: Theme.surfacePadding
    spacing: 8

    readonly property string sel: Usage.selected
    readonly property var p: Usage.provider(sel)
    readonly property var info: Usage.meta[sel]

    // 24H / 7D history range toggle.
    property string histMode: "h24"
    readonly property var histBars: {
        const h = Usage.history; // dependency: refresh on new samples
        return Usage.histBars(sel, histMode);
    }

    readonly property real cardW: (width - 2 * padding - 6) / 2

    function cardLabel(label) {
        const m = label.match(/^Weekly \((\w+)\)$/);
        return (m ? m[1] + " weekly" : label).toUpperCase();
    }

    function remainColor(rem) {
        if (rem <= 10)
            return Theme.redText;
        if (rem <= 25)
            return Theme.amber;
        return Theme.textHi;
    }

    function barColor(rem) {
        if (rem <= 10)
            return Theme.red;
        if (rem <= 25)
            return Theme.amber;
        return Theme.accent;
    }

    function errorTitle(prov) {
        const name = Usage.meta[Usage.selected].name;
        switch (prov.kind) {
        case "nocreds":
            return name + " sign-in required";
        case "expired":
            return name + " token expired";
        case "rate":
            return name + " is rate limited";
        default:
            return name + " fetch failed";
        }
    }

    function errorBody(prov) {
        const cmd = Usage.meta[Usage.selected].cmd;
        switch (prov.kind) {
        case "nocreds":
            return `No CLI credentials found. Run <font color="${Theme.textMid}" face="${Theme.fontMono}">${cmd}</font> in a terminal, complete the sign-in, then press Refresh.`;
        case "expired":
            return `The stored token has expired. Run <font color="${Theme.textMid}" face="${Theme.fontMono}">${cmd}</font> in a terminal, then press Refresh.`;
        case "rate":
            return "The usage endpoint is rate limiting requests. Polling will retry automatically.";
        default:
            return prov.message || "The usage endpoint returned an unexpected response.";
        }
    }

    // ---- Header: brand mark, meta, mini tabs, refresh ------------------
    Item {
        width: parent.width
        height: Theme.rowHeight

        Rectangle {
            id: brandSquare
            x: 4
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.controlHeight
            height: Theme.controlHeight
            radius: 7
            color: root.info.brand

            Image {
                anchors.centerIn: parent
                width: root.sel === "codex" ? 15 : 14
                height: width
                sourceSize: Qt.size(28, 28)
                source: Quickshell.shellDir + "/assets/" + root.info.icon + "-white.svg"
            }
        }

        Row {
            id: tabsRow
            anchors.right: parent.right
            anchors.rightMargin: 2
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3

            Repeater {
                model: Usage.providerKeys

                delegate: Rectangle {
                    id: miniTab

                    required property string modelData
                    readonly property bool active: Usage.selected === modelData

                    width: Theme.controlHeight
                    height: Theme.controlHeight
                    radius: 6
                    color: active ? Theme.hoverFillStrong : miniTabMouse.containsMouse ? Theme.hoverFill : "transparent"

                    Image {
                        anchors.centerIn: parent
                        width: miniTab.modelData === "codex" ? 12 : 11
                        height: width
                        sourceSize: Qt.size(24, 24)
                        source: Quickshell.shellDir + "/assets/" + Usage.meta[miniTab.modelData].icon + ".svg"
                        opacity: miniTab.active ? 1 : 0.45
                    }

                    MouseArea {
                        id: miniTabMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        // Hover-through: mirroring the bar chips, hovering a
                        // tab switches the whole view to that provider.
                        onEntered: Usage.selected = miniTab.modelData
                        onClicked: Usage.selected = miniTab.modelData
                    }
                }
            }

            Rectangle {
                width: Theme.controlHeight
                height: Theme.controlHeight
                radius: 6
                color: refreshMouse.containsMouse ? Theme.hoverFillStrong : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: ""
                    font.family: Theme.fontIcon
                    font.pixelSize: Theme.fontSecondary
                    color: refreshMouse.containsMouse ? Theme.textHi : Theme.textLow
                }

                MouseArea {
                    id: refreshMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: Usage.refresh()
                }
            }
        }

        Column {
            anchors.left: brandSquare.right
            anchors.leftMargin: 10
            anchors.right: tabsRow.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                width: parent.width
                text: root.info.title
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontBody
                font.weight: Theme.weightSemibold
                color: Theme.textHi
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: {
                    if (!root.p || root.p.status !== "ok")
                        return root.p && root.p.status !== "ok" ? root.info.cmd.split(" ")[0] + "-oauth" : "";
                    return [root.p.plan, root.p.account, root.p.source].filter(Boolean).join(" · ");
                }
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontCaption
                color: Theme.textDim
                elide: Text.ElideRight
            }
        }
    }

    // ---- Error panel ---------------------------------------------------
    Rectangle {
        visible: root.p !== null && root.p.status !== "ok"
        width: parent.width
        height: errRow.implicitHeight + 24
        radius: 10
        color: Theme.redBgSoft

        Row {
            id: errRow
            x: 12
            y: 12
            width: parent.width - 24
            spacing: 10

            Text {
                width: 18
                horizontalAlignment: Text.AlignHCenter
                text: ""
                font.family: Theme.fontIcon
                font.pixelSize: Theme.fontBody
                color: Theme.redText
            }

            Column {
                width: parent.width - 28
                spacing: 3

                Text {
                    width: parent.width
                    text: root.p ? root.errorTitle(root.p) : ""
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontBody
                    font.weight: Theme.weightMedium
                    color: Theme.textHi
                }

                Text {
                    width: parent.width
                    textFormat: Text.RichText
                    text: root.p ? root.errorBody(root.p) : ""
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontSecondary
                    color: Theme.textLow
                    wrapMode: Text.Wrap
                    lineHeight: Theme.proseLineHeight
                }
            }
        }
    }

    // ---- Usage window cards ---------------------------------------------
    Grid {
        visible: root.p !== null && root.p.status === "ok"
        columns: 2
        columnSpacing: 6
        rowSpacing: 6
        width: parent.width

        Repeater {
            model: root.p && root.p.status === "ok" ? root.p.windows : []

            delegate: Rectangle {
                id: card

                required property var modelData
                readonly property int remaining: Math.round(100 - modelData.used)
                readonly property bool crit: remaining <= 10
                readonly property bool low: remaining > 10 && remaining <= 25

                width: root.cardW
                height: cardCol.implicitHeight + 20
                radius: 10
                color: crit ? Theme.redBgSoft : Theme.cardFill
                border.width: 1
                border.color: crit ? Theme.redBorder : low ? Theme.amberBorder : "transparent"

                Column {
                    id: cardCol
                    x: 12
                    y: 10
                    width: parent.width - 24
                    spacing: 7

                    Item {
                        width: parent.width
                        height: Math.max(cardLabel.implicitHeight, badge.implicitHeight)

                        Text {
                            id: cardLabel
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.cardLabel(card.modelData.label)
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.fontCaption
                            font.weight: Theme.weightSemibold
                            font.letterSpacing: 0.6
                            color: Theme.textDim
                            width: parent.width - (badge.visible ? badge.width + 6 : 0)
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            id: badge
                            visible: card.crit || card.low
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: badgeText.implicitWidth + 10
                            implicitHeight: badgeText.implicitHeight + 4
                            radius: 4
                            color: card.crit ? Theme.redBg : Theme.amberBg

                            Text {
                                id: badgeText
                                anchors.centerIn: parent
                                text: card.crit ? "CRITICAL" : "LOW"
                                font.family: Theme.fontMenu
                                font.pixelSize: Theme.fontCaption
                                font.weight: Theme.weightSemibold
                                font.letterSpacing: 0.5
                                color: card.crit ? Theme.redText : Theme.amber
                            }
                        }
                    }

                    Row {
                        spacing: 3

                        Text {
                            anchors.baseline: remainingSuffix.baseline
                            text: card.remaining
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fontProminent
                            font.weight: Theme.weightSemibold
                            color: root.remainColor(card.remaining)
                        }

                        Text {
                            id: remainingSuffix
                            text: "% left"
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fontCaption
                            color: Theme.textLow
                        }
                    }

                    BlockMeter {
                        width: parent.width
                        height: 10
                        value: card.remaining / 100
                        fillColor: root.barColor(card.remaining)
                    }

                    Text {
                        visible: card.modelData.resetsAt !== null && card.modelData.resetsAt !== undefined
                        width: parent.width
                        textFormat: Text.RichText
                        text: `resets in <font color="${Theme.textLow}" face="${Theme.fontMono}">${Usage.formatReset(card.modelData.resetsAt)}</font> · <font color="${Theme.textFaint}">${Usage.formatResetAbs(card.modelData.resetsAt)}</font>`
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.fontCaption
                        color: Theme.textDim
                        elide: Text.ElideRight
                    }
                }
            }
        }

        // Extra usage / credits card
        Rectangle {
            id: creditsCard

            readonly property var c: root.p && root.p.status === "ok" ? root.p.credits : null
            readonly property bool hasMeter: c !== null && c !== undefined
                && c.used !== null && c.used !== undefined
                && c.limit !== null && c.limit !== undefined && c.limit > 0
            readonly property bool creditsStyle: c !== null && c !== undefined && !hasMeter
                && c.remaining !== null && c.remaining !== undefined
            readonly property string displayValue: {
                if (!c)
                    return "";
                if (c.unlimited)
                    return "Unlimited";
                if (hasMeter)
                    return "$" + c.used.toFixed(2);
                if (c.remaining !== null && c.remaining !== undefined)
                    return Number(c.remaining).toLocaleString(Qt.locale("en_US"), "f",
                        c.remaining % 1 === 0 ? 0 : 2);
                return "—";
            }
            readonly property string displaySuffix: !c || c.unlimited ? ""
                : hasMeter ? "/ $" + c.limit.toFixed(2) : "left"

            visible: root.p !== null && root.p.status === "ok" && c !== null && c !== undefined
            width: root.cardW
            height: creditsCol.implicitHeight + 20
            radius: 10
            color: Theme.cardFill

            Column {
                id: creditsCol
                x: 12
                y: 10
                width: parent.width - 24
                spacing: 7

                Item {
                    width: parent.width
                    height: creditsLabel.implicitHeight

                    Text {
                        id: creditsLabel
                        anchors.verticalCenter: parent.verticalCenter
                        text: creditsCard.creditsStyle ? "CREDITS" : "EXTRA USAGE"
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.fontCaption
                        font.weight: Theme.weightSemibold
                        font.letterSpacing: 0.6
                        color: Theme.textDim
                    }
                }

                Row {
                    spacing: 5

                    Text {
                        anchors.baseline: creditsSuffix.baseline
                        text: creditsCard.displayValue
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontHeading
                        font.weight: Theme.weightSemibold
                        color: Theme.textHi
                    }

                    Text {
                        id: creditsSuffix
                        text: creditsCard.displaySuffix
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontSecondary
                        color: Theme.textLow
                    }
                }

                BlockMeter {
                    visible: creditsCard.hasMeter
                    width: parent.width
                    height: 10
                    value: creditsCard.hasMeter ? creditsCard.c.used / creditsCard.c.limit : 0
                    fillColor: Theme.textLow
                }

                Text {
                    width: parent.width
                    text: creditsCard.creditsStyle ? "use credits beyond plan limits" : "pay-as-you-go beyond plan limits"
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontCaption
                    color: Theme.textDim
                    wrapMode: Text.Wrap
                    lineHeight: Theme.proseLineHeight
                }
            }
        }
    }

    // ---- Usage history ---------------------------------------------------
    Rectangle {
        visible: root.p !== null && root.p.status === "ok"
        width: parent.width
        height: histCol.implicitHeight + 20
        radius: 10
        color: Theme.cardFill

        Column {
            id: histCol
            x: 12
            y: 10
            width: parent.width - 24
            spacing: 8

            Item {
                width: parent.width
                height: Math.max(historyTitle.implicitHeight, historyRanges.implicitHeight)

                Text {
                    id: historyTitle
                    anchors.verticalCenter: parent.verticalCenter
                    text: "USAGE HISTORY"
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontCaption
                    font.weight: Theme.weightSemibold
                    font.letterSpacing: 0.6
                    color: Theme.textDim
                }

                Row {
                    id: historyRanges
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3

                    Repeater {
                        model: [{ key: "h24", label: "24H" }, { key: "d7", label: "7D" }]

                        delegate: Rectangle {
                            id: rangeChip

                            required property var modelData
                            readonly property bool active: root.histMode === modelData.key

                            width: rangeText.implicitWidth + 14
                            height: rangeText.implicitHeight + 4
                            radius: 5
                            color: active ? Theme.hoverFillStrong : rangeMouse.containsMouse ? Theme.hoverFill : "transparent"

                            Text {
                                id: rangeText
                                anchors.centerIn: parent
                                text: rangeChip.modelData.label
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontCaption
                                font.weight: Theme.weightSemibold
                                color: rangeChip.active ? Theme.textHi : Theme.textDim
                            }

                            MouseArea {
                                id: rangeMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.histMode = rangeChip.modelData.key
                            }
                        }
                    }
                }
            }

            // Block chart: vertical dashed bars in the provider's brand
            // color, bottom-aligned.
            Row {
                width: parent.width
                height: 52
                spacing: 2

                Repeater {
                    model: root.histBars

                    delegate: Item {
                        id: bar

                        required property var modelData
                        readonly property real barH: 4 + Math.max(0, Math.min(100, bar.modelData)) * 0.48

                        width: (parent.width - (root.histBars.length - 1) * 2) / root.histBars.length
                        height: 52

                        Repeater {
                            model: Math.ceil(bar.barH / 5)

                            delegate: Rectangle {
                                required property int index
                                readonly property real segH: Math.min(3, bar.barH - index * 5)

                                width: bar.width
                                height: segH
                                y: bar.height - index * 5 - segH
                                color: root.info.brand
                            }
                        }
                    }
                }
            }

            Item {
                width: parent.width
                height: Math.max(axisStart.implicitHeight, axisMiddle.implicitHeight,
                    axisEnd.implicitHeight)

                Text {
                    id: axisStart
                    anchors.left: parent.left
                    text: root.histMode === "h24" ? "-24h" : "-7d"
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontCaption
                    color: Theme.textFaint
                }

                Text {
                    id: axisMiddle
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.histMode === "h24" ? "-12h" : "-3d"
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontCaption
                    color: Theme.textFaint
                }

                Text {
                    id: axisEnd
                    anchors.right: parent.right
                    text: "now"
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontCaption
                    color: Theme.textFaint
                }
            }
        }
    }

    // ---- Footer -----------------------------------------------------------
    Item {
        width: parent.width
        height: Theme.controlHeight

        Text {
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            // A fetcher failure is plain text — a Python traceback can carry
            // "<module>" and would otherwise be read as markup — and elides
            // instead of running under the countdown. The journal has it in
            // full.
            width: parent.width - 12 - nextPoll.implicitWidth - 8
            elide: Text.ElideRight
            textFormat: Usage.fetchError !== "" ? Text.PlainText : Text.RichText
            text: Usage.fetchError !== ""
                ? Usage.fetchError
                : Usage.updatedAt > 0
                    ? `updated <font color="${Theme.textLow}" face="${Theme.fontMono}">${Qt.formatTime(new Date(Usage.updatedAt), "HH:mm:ss")}</font>`
                    : "Loading…"
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontCaption
            color: Usage.fetchError !== "" ? Theme.redText : Theme.textDim
        }

        Text {
            id: nextPoll
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.RichText
            text: `next poll <font color="${Theme.textLow}" face="${Theme.fontMono}">${Usage.formatCountdown(Usage.nextPollSecs)}</font>`
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontCaption
            color: Theme.textDim
        }
    }
}
