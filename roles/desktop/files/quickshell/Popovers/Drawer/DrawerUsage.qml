pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "../../Common"
import ".."

// The drawer's Usage tab: one provider at a time — its quota windows with
// remaining percentage, meter and reset times, its credits, and the upcoming
// resets — behind a provider switcher. The bar's usage pill deep-links here
// with Usage.selected already set.
Column {
    id: root

    readonly property string selected: Usage.selected
    readonly property var record: Usage.provider(selected)
    readonly property bool ok: record !== null && record.status === "ok"
    readonly property var windows: ok && Array.isArray(record.windows)
        ? record.windows : []
    readonly property var credits: ok ? (record.credits ?? null) : null
    readonly property var resetRows: windows.filter(w => w.resetsAt)

    width: parent ? parent.width : 0
    spacing: Theme.scaled(14)

    Claim {
        active: root.visible
        onClaimed: Usage.acquireCountdown()
        onReleased: Usage.releaseCountdown()
    }

    function windowSpan(w) {
        if (!w.windowSecs)
            return w.label;
        const hours = w.windowSecs / 3600;
        if (hours < 24)
            return Math.round(hours) + "-hour window";
        return Math.round(hours / 24) + "-day window";
    }

    // ---- provider switch -------------------------------------------------
    Rectangle {
        width: parent.width
        height: 36
        radius: 9
        color: Theme.chip

        Row {
            anchors.fill: parent
            anchors.margins: 3
            spacing: 2

            Repeater {
                model: Usage.providerKeys

                delegate: Rectangle {
                    id: providerChoice

                    required property string modelData
                    readonly property bool on: root.selected === modelData

                    width: (parent.width - 2 * (Usage.providerKeys.length - 1))
                        / Usage.providerKeys.length
                    height: parent.height
                    radius: 7
                    color: on ? Theme.chipHover : "transparent"

                    Behavior on color {
                        ColorAnimation { duration: Theme.chipFadeDuration }
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: 7

                        BrandIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 12
                            height: 12
                            name: Usage.meta[providerChoice.modelData].icon
                            opacity: providerChoice.on ? 1 : 0.55
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Usage.meta[providerChoice.modelData].name
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.fontCaption
                            font.weight: Theme.weightSemibold
                            color: providerChoice.on ? Theme.textHi : Theme.textFaint
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Usage.selected = providerChoice.modelData
                    }

                    Accessible.role: Accessible.PageTab
                    Accessible.name: Usage.meta[providerChoice.modelData].name
                }
            }
        }
    }

    // ---- header ----------------------------------------------------------
    Item {
        width: parent.width
        height: 36

        Column {
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.right: refreshButton.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                width: parent.width
                text: {
                    const title = Usage.meta[root.selected].title;
                    if (root.ok && root.record.plan)
                        return title + " · " + root.record.plan;
                    return title;
                }
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontHeading - 1
                font.weight: Theme.weightSemibold
                color: Theme.textHi
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: {
                    const parts = [];
                    if (Usage.updatedAt > 0)
                        parts.push("updated " + Qt.formatDateTime(
                            new Date(Usage.updatedAt), "HH:mm:ss"));
                    if (Usage.loading)
                        parts.push("refreshing…");
                    else
                        parts.push("next poll in "
                            + Usage.formatCountdown(Usage.nextPollSecs));
                    return parts.join(" · ");
                }
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontCaption
                color: Theme.textFaint
                elide: Text.ElideRight
            }
        }

        DrawerIconButton {
            id: refreshButton
            anchors.right: parent.right
            anchors.rightMargin: 2
            anchors.verticalCenter: parent.verticalCenter
            width: 28
            height: 28
            glyph: "refresh"
            glyphSize: 16
            enabled: !Usage.loading
            accessibleName: "Refresh usage"
            onClicked: Usage.refresh()
        }
    }

    // ---- signed-out / error ----------------------------------------------
    Rectangle {
        visible: !root.ok
        width: parent.width
        height: signedOutColumn.implicitHeight + 24
        radius: 10
        color: Theme.chip

        Column {
            id: signedOutColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            Text {
                width: parent.width
                text: Usage.fetchError !== "" ? "Usage unavailable"
                    : root.record && root.record.kind === "auth"
                    ? "Sign-in required" : "No usage data"
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontSecondary
                font.weight: Theme.weightSemibold
                color: Theme.textHi
            }

            Text {
                width: parent.width
                text: Usage.fetchError !== "" ? Usage.fetchError
                    : root.record && root.record.message
                    ? root.record.message
                    : Usage.loading ? "Fetching…" : "Nothing reported yet."
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontCaption
                color: Theme.textFaint
                wrapMode: Text.WordWrap
            }

            Text {
                visible: Usage.meta[root.selected].cmd !== ""
                    && root.record !== null && root.record.kind === "auth"
                width: parent.width
                text: "Run " + Usage.meta[root.selected].cmd + " in a terminal."
                font.family: Theme.fontNumeric
                font.pixelSize: Theme.fontCaption
                color: Theme.textLow
                wrapMode: Text.WordWrap
            }
        }
    }

    // ---- quota windows ---------------------------------------------------
    Column {
        visible: root.ok
        width: parent.width
        spacing: 4

        Repeater {
            model: root.windows

            delegate: Rectangle {
                id: windowCard

                required property var modelData
                readonly property int remaining: Math.max(0,
                    Math.round(100 - Number(modelData.used)))
                readonly property bool low:
                    remaining <= Settings.modOpts.usage.warnAt
                readonly property bool exhausted:
                    remaining <= Settings.modOpts.usage.critAt

                width: parent ? parent.width : 0
                height: cardColumn.implicitHeight + 20
                radius: 10
                color: Theme.chip

                Column {
                    id: cardColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Item {
                        width: parent.width
                        height: 30

                        Column {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1

                            Text {
                                text: windowCard.modelData.label
                                font.family: Theme.fontMenu
                                font.pixelSize: Theme.fontSecondary
                                font.weight: Theme.weightSemibold
                                color: Theme.textHi
                            }

                            Text {
                                text: root.windowSpan(windowCard.modelData)
                                font.family: Theme.fontMenu
                                font.pixelSize: Theme.fontMicro
                                color: Theme.textFaint
                            }
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            spacing: 3

                            Text {
                                text: windowCard.remaining
                                font.family: Theme.fontNumeric
                                font.pixelSize: Theme.fontProminent
                                font.weight: Theme.weightSemibold
                                font.letterSpacing: -0.5
                                font.features: Theme.tabularNumberFeatures
                                color: windowCard.exhausted ? Theme.redText
                                    : windowCard.low ? Theme.amber : Theme.textHi
                            }

                            Text {
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 3
                                text: "% left"
                                font.family: Theme.fontMenu
                                font.pixelSize: Theme.fontMicro
                                color: Theme.textFaint
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 6
                        radius: 3
                        color: Qt.rgba(1, 1, 1, 0.10)

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: parent.width * windowCard.remaining / 100
                            radius: 3
                            color: windowCard.exhausted ? Theme.red
                                : windowCard.low ? Theme.amber : Theme.accent
                        }
                    }

                    Item {
                        visible: windowCard.modelData.resetsAt ? true : false
                        width: parent.width
                        height: 14

                        Text {
                            anchors.left: parent.left
                            text: windowCard.modelData.resetsAt
                                ? "resets in " + Usage.formatReset(
                                    windowCard.modelData.resetsAt) : ""
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.fontMicro
                            color: Theme.textMid
                        }

                        Text {
                            anchors.right: parent.right
                            text: windowCard.modelData.resetsAt
                                ? Usage.formatResetAbs(
                                    windowCard.modelData.resetsAt) : ""
                            font.family: Theme.fontNumeric
                            font.pixelSize: Theme.fontMicro
                            font.features: Theme.tabularNumberFeatures
                            color: Theme.textFaint
                        }
                    }
                }
            }
        }

        // Pay-as-you-go / banked credits, when the provider reports them.
        Item {
            visible: root.credits !== null
            width: parent.width
            height: 44

            Column {
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.right: creditsValue.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Text {
                    width: parent.width
                    text: root.credits && root.credits.label
                        ? root.credits.label : "Extra usage"
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontSecondary
                    font.weight: Theme.weightMedium
                    color: Theme.textHi
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: "beyond plan limits"
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontMicro
                    color: Theme.textFaint
                }
            }

            Text {
                id: creditsValue
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.StyledText
                text: {
                    if (!root.credits)
                        return "";
                    const used = root.credits.used !== null
                        && root.credits.used !== undefined
                        ? "$" + Number(root.credits.used).toFixed(2) : "--";
                    const limit = root.credits.limit !== null
                        && root.credits.limit !== undefined
                        ? " / $" + Number(root.credits.limit) : "";
                    return "<b>" + used + "</b>" + limit;
                }
                font.family: Theme.fontNumeric
                font.pixelSize: Theme.fontSecondary
                font.features: Theme.tabularNumberFeatures
                color: Theme.textHi
            }
        }
    }

    // ---- upcoming resets -------------------------------------------------
    Column {
        visible: root.ok && root.resetRows.length > 0
        width: parent.width
        spacing: 2

        SectionLabel {
            width: parent.width
            text: "UPCOMING RESETS"
        }

        Repeater {
            model: root.resetRows

            delegate: Item {
                id: resetRow

                required property var modelData

                width: parent ? parent.width : 0
                height: 28

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: resetRow.modelData.label
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontCaption
                    color: Theme.textMid
                }

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: Usage.formatResetAbs(resetRow.modelData.resetsAt)
                    font.family: Theme.fontNumeric
                    font.pixelSize: Theme.fontCaption
                    font.weight: Theme.weightSemibold
                    font.features: Theme.tabularNumberFeatures
                    color: Theme.textHi
                }
            }
        }
    }

    DrawerFooter {
        info: root.ok && root.record.source
            ? "via " + root.record.source
            : "source · " + Settings.modOpts.usage.source
        actionText: Settings.modOpts.usage.cliproxyUrl !== ""
            ? "Open dashboard" : ""
        onActionClicked: {
            Popouts.close();
            Quickshell.execDetached(["xdg-open",
                Settings.modOpts.usage.cliproxyUrl]);
        }
    }
}
