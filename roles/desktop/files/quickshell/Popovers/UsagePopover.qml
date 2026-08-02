import QtQuick
import Quickshell
import "../Common"

Surface {
    id: root

    // Right-island popouts run a touch wider (design t5).
    implicitWidth: 380

    readonly property string sel: Usage.selected
    readonly property var p: Usage.provider(sel)
    readonly property var info: Usage.meta[sel]

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

    // Provider tabs
    Row {
        width: parent.width
        spacing: 4

        Repeater {
            model: Usage.providerKeys

            delegate: Rectangle {
                required property string modelData
                readonly property bool active: Usage.selected === modelData
                readonly property var prov: Usage.provider(modelData)
                readonly property int remaining: Usage.minRemaining(modelData)
                readonly property bool errored: prov !== null && prov.status !== "ok"

                width: (root.width - 16 - 8) / 3
                height: 32
                radius: Theme.rowRadius
                color: active ? Theme.activeFill : tabMouse.containsMouse ? Theme.hoverFill : "transparent"

                Row {
                    anchors.centerIn: parent
                    spacing: 6

                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        width: modelData === "codex" ? 12 : 11
                        height: width
                        sourceSize: Qt.size(24, 24)
                        source: Quickshell.shellDir + "/assets/" + Usage.meta[modelData].icon + ".svg"
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Usage.meta[modelData].name
                        font.family: Theme.fontSans
                        font.pixelSize: 12
                        font.weight: active ? 600 : 500
                        color: active ? Theme.textHi : Theme.textLow
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: errored || remaining < 0 ? "--%" : remaining + "%"
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                        font.weight: active ? 600 : 500
                        color: errored ? (active ? Theme.redText : Theme.textDim) : active ? Theme.accent : Theme.textDim
                    }
                }

                MouseArea {
                    id: tabMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: Usage.selected = modelData
                }
            }
        }
    }

    // Title + refresh
    Item {
        width: parent.width
        height: 34

        Text {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            text: root.info.title
            font.family: Theme.fontSans
            font.pixelSize: 13
            font.weight: 600
            color: Theme.textHi
        }

        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            width: 26
            height: 22
            radius: 6
            color: refreshMouse.containsMouse ? Theme.hoverFillStrong : "transparent"

            Text {
                anchors.centerIn: parent
                text: "\uf021"
                font.family: Theme.fontIcon
                font.pixelSize: 11
                color: refreshMouse.containsMouse ? Theme.textHi : Theme.textLow

                RotationAnimation on rotation {
                    running: Usage.loading
                    from: 0
                    to: 360
                    duration: 900
                    loops: Animation.Infinite
                }
            }

            MouseArea {
                id: refreshMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: Usage.refresh()
            }
        }
    }

    // Plan / account / source meta
    Text {
        visible: text !== ""
        x: 10
        bottomPadding: 8
        width: parent.width - 20
        text: {
            if (!root.p || root.p.status !== "ok")
                return root.p && root.p.status !== "ok" ? root.info.cmd.split(" ")[0] + "-oauth" : "";
            return [root.p.plan, root.p.account, root.p.source].filter(Boolean).join(" · ");
        }
        font.family: Theme.fontSans
        font.pixelSize: 11
        color: Theme.textDim
        elide: Text.ElideRight
    }

    // Error panel
    Rectangle {
        visible: root.p !== null && root.p.status !== "ok"
        width: parent.width - 4
        x: 2
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
                text: "\uf071"
                font.family: Theme.fontIcon
                font.pixelSize: 13
                color: Theme.redText
            }

            Column {
                width: parent.width - 28
                spacing: 3

                Text {
                    width: parent.width
                    text: root.p ? root.errorTitle(root.p) : ""
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                    font.weight: 500
                    color: Theme.textHi
                }

                Text {
                    width: parent.width
                    textFormat: Text.RichText
                    text: root.p ? root.errorBody(root.p) : ""
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                    lineHeight: 1.35
                    color: Theme.textLow
                    wrapMode: Text.Wrap
                }
            }
        }
    }

    // Usage window cards
    Grid {
        visible: root.p !== null && root.p.status === "ok"
        columns: 2
        columnSpacing: 6
        rowSpacing: 6
        width: parent.width - 4
        x: 2

        Repeater {
            model: root.p && root.p.status === "ok" ? root.p.windows : []

            delegate: Rectangle {
                required property var modelData
                readonly property int remaining: Math.round(100 - modelData.used)

                width: (root.width - 16 - 4 - 6) / 2
                height: 92
                radius: 10
                color: Theme.cardFill

                Column {
                    x: 12
                    y: 10
                    width: parent.width - 24
                    spacing: 0

                    Text {
                        width: parent.width
                        text: root.cardLabel(modelData.label)
                        font.family: Theme.fontSans
                        font.pixelSize: 10
                        font.weight: 600
                        font.letterSpacing: 0.63
                        color: Theme.textDim
                        elide: Text.ElideRight
                    }

                    Item {
                        width: 1
                        height: 4
                    }

                    Text {
                        textFormat: Text.RichText
                        text: `<span style="font-size:20px">${remaining}</span><span style="font-size:12px;color:${Theme.textLow}">%</span> <span style="font-size:10.5px;color:${Theme.textLow};font-weight:400">left</span>`
                        font.family: Theme.fontMono
                        font.weight: 600
                        color: root.remainColor(remaining)
                    }

                    Item {
                        width: 1
                        height: 8
                    }

                    Rectangle {
                        width: parent.width
                        height: 4
                        radius: 2
                        color: Qt.rgba(1, 1, 1, 0.08)

                        Rectangle {
                            width: parent.width * remaining / 100
                            height: parent.height
                            radius: 2
                            color: root.barColor(remaining)
                        }
                    }

                    Item {
                        width: 1
                        height: 6
                    }

                    Text {
                        visible: modelData.resetsAt !== null && modelData.resetsAt !== undefined
                        textFormat: Text.RichText
                        text: `resets in <font color="${Theme.textLow}" face="${Theme.fontMono}">${Usage.formatReset(modelData.resetsAt)}</font>`
                        font.family: Theme.fontSans
                        font.pixelSize: 10
                        color: Theme.textDim
                    }
                }
            }
        }

        // Extra usage / credits card
        Rectangle {
            visible: root.p !== null && root.p.status === "ok" && root.p.credits !== null && root.p.credits !== undefined
            width: (root.width - 16 - 4 - 6) / 2
            height: 92
            radius: 10
            color: Theme.cardFill

            Column {
                x: 12
                y: 10
                width: parent.width - 24

                Text {
                    text: "EXTRA USAGE"
                    font.family: Theme.fontSans
                    font.pixelSize: 10
                    font.weight: 600
                    font.letterSpacing: 0.63
                    color: Theme.textDim
                }

                Item {
                    width: 1
                    height: 6
                }

                Text {
                    textFormat: Text.RichText
                    text: {
                        const c = root.p && root.p.credits ? root.p.credits : null;
                        if (!c)
                            return "";
                        if (c.unlimited)
                            return "Unlimited";
                        if (c.used !== null && c.used !== undefined && c.limit !== null && c.limit !== undefined)
                            return `$${c.used.toFixed(2)} <span style="font-size:11px;color:${Theme.textLow}">/ $${c.limit.toFixed(2)}</span>`;
                        if (c.remaining !== null && c.remaining !== undefined)
                            return `${c.remaining.toFixed(2)} <span style="font-size:11px;color:${Theme.textLow}">left</span>`;
                        return "—";
                    }
                    font.family: Theme.fontMono
                    font.pixelSize: 17
                    font.weight: 600
                    color: Theme.textHi
                }

                Item {
                    width: 1
                    height: 9
                }

                Text {
                    width: parent.width
                    text: "Pay-as-you-go on top of the plan limits"
                    font.family: Theme.fontSans
                    font.pixelSize: 10
                    color: Theme.textDim
                    wrapMode: Text.Wrap
                }
            }
        }
    }

    HDivider {}

    // Footer
    Item {
        width: parent.width
        height: 24

        Text {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            text: Usage.updatedAt > 0 ? "Updated " + Qt.formatTime(new Date(Usage.updatedAt), "h:mm:ss AP") : "Loading…"
            font.family: Theme.fontSans
            font.pixelSize: 11
            color: Theme.textDim
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.RichText
            text: `next poll <font color="${Theme.textLow}" face="${Theme.fontMono}">${Usage.formatCountdown(Usage.nextPollSecs)}</font>`
            font.family: Theme.fontSans
            font.pixelSize: 11
            color: Theme.textDim
        }
    }
}
