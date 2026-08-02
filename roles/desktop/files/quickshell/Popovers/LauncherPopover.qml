import QtQuick
import Quickshell
import Quickshell.Widgets
import "../Common"

// Centered SUPER+SPACE launcher (design 4a): search field, app results
// with match highlighting, file/web search rows, alt+N shortcuts.
Surface {
    id: root

    implicitWidth: 560

    readonly property int maxApps: 5
    property int selected: 0
    readonly property string query: search.text

    readonly property var apps: {
        const all = DesktopEntries.applications.values.filter(a => !a.noDisplay);
        const q = query.toLowerCase();
        const filtered = q === "" ? all : all.filter(a => a.name.toLowerCase().includes(q)
            || (a.genericName && a.genericName.toLowerCase().includes(q))
            || (a.keywords && a.keywords.join(" ").toLowerCase().includes(q)));
        return filtered.sort((a, b) => {
            const ap = a.name.toLowerCase().startsWith(q) ? 0 : 1;
            const bp = b.name.toLowerCase().startsWith(q) ? 0 : 1;
            return ap - bp || a.name.localeCompare(b.name);
        }).slice(0, maxApps);
    }

    // Combined row model: apps, then file/web search when there is a query.
    readonly property var rows: {
        const list = apps.map(a => ({ kind: "app", app: a }));
        if (query !== "") {
            list.push({ kind: "files" });
            list.push({ kind: "web" });
        }
        return list;
    }

    onRowsChanged: selected = Math.min(selected, Math.max(0, rows.length - 1))
    onQueryChanged: selected = 0

    function activate(row) {
        if (!row)
            return;
        if (row.kind === "app")
            row.app.execute();
        else if (row.kind === "files")
            Quickshell.execDetached(["nautilus", "--new-window"]);
        else if (row.kind === "web")
            Quickshell.execDetached(["xdg-open", "https://duckduckgo.com/?q=" + encodeURIComponent(query)]);
        Popovers.close();
    }

    function esc(s) {
        return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    // Highlight the matched part of a name in accent.
    function highlight(name) {
        if (query === "")
            return esc(name);
        const idx = name.toLowerCase().indexOf(query.toLowerCase());
        if (idx < 0)
            return esc(name);
        return esc(name.slice(0, idx))
            + `<font color="${Theme.accent}">` + esc(name.slice(idx, idx + query.length)) + "</font>"
            + esc(name.slice(idx + query.length));
    }

    // ---- Search field -----------------------------------------------
    Rectangle {
        width: parent.width
        height: 42
        radius: 10
        color: Theme.hoverFill

        Row {
            anchors.verticalCenter: parent.verticalCenter
            x: 12
            spacing: 10

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf002"
                font.family: Theme.fontIcon
                font.pixelSize: 14
                color: Theme.textLow
            }

            TextInput {
                id: search
                anchors.verticalCenter: parent.verticalCenter
                width: root.width - 70
                font.family: Theme.fontSans
                font.pixelSize: 14
                color: Theme.textHi
                clip: true
                focus: true

                Text {
                    visible: search.text === ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Search apps…"
                    font: search.font
                    color: Theme.textDim
                }

                Keys.onPressed: event => {
                    if (event.modifiers & Qt.AltModifier && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                        root.activate(root.rows[event.key - Qt.Key_1]);
                        event.accepted = true;
                        return;
                    }
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.activate(root.rows[root.selected]);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Down || (event.key === Qt.Key_Tab)) {
                        root.selected = Math.min(root.rows.length - 1, root.selected + 1);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Up) {
                        root.selected = Math.max(0, root.selected - 1);
                        event.accepted = true;
                    }
                }
            }
        }
    }

    Item {
        width: 1
        height: 8
    }

    // ---- Result rows ------------------------------------------------
    Repeater {
        model: root.rows

        delegate: Rectangle {
            required property var modelData
            required property int index
            readonly property bool isSel: index === root.selected

            width: parent.width
            height: 52
            radius: 10
            color: isSel ? Theme.activeFill : rowMouse.containsMouse ? Theme.hoverFill : "transparent"

            Row {
                anchors.verticalCenter: parent.verticalCenter
                x: 12
                spacing: 12

                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24
                    height: 24

                    IconImage {
                        visible: modelData.kind === "app" && source != ""
                        anchors.fill: parent
                        source: modelData.kind === "app" ? Quickshell.iconPath(modelData.app.icon, true) : ""
                    }

                    Text {
                        visible: modelData.kind !== "app"
                        anchors.centerIn: parent
                        text: modelData.kind === "files" ? "\uf07b" : "\uf0ac"
                        font.family: Theme.fontIcon
                        font.pixelSize: 16
                        color: isSel ? Theme.textHi : Theme.textMid
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.width - 110
                    spacing: 1

                    Text {
                        width: parent.width
                        textFormat: Text.StyledText
                        text: {
                            if (modelData.kind === "app")
                                return root.highlight(modelData.app.name);
                            if (modelData.kind === "files")
                                return "Search files for “" + root.esc(root.query) + "”";
                            return "Search the web for “" + root.esc(root.query) + "”";
                        }
                        font.family: Theme.fontSans
                        font.pixelSize: 13
                        font.weight: 500
                        color: isSel ? Theme.textHi : Theme.textMid
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: {
                            if (modelData.kind === "app")
                                return modelData.app.genericName || modelData.app.comment || "Application";
                            if (modelData.kind === "files")
                                return "Files";
                            return "DuckDuckGo";
                        }
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                        color: isSel ? Theme.textLow : Theme.textDim
                        elide: Text.ElideRight
                    }
                }
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: isSel ? "↵" : "alt+" + (index + 1)
                font.family: Theme.fontMono
                font.pixelSize: 11
                font.weight: 500
                color: isSel ? Theme.textDim : Theme.textFaint
            }

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                onEntered: root.selected = index
                onClicked: root.activate(modelData)
            }
        }
    }

    Text {
        visible: root.rows.length === 0
        width: parent.width
        topPadding: 14
        bottomPadding: 10
        text: "No matching apps"
        horizontalAlignment: Text.AlignHCenter
        font.family: Theme.fontSans
        font.pixelSize: 11
        color: Theme.textDim
    }

    HDivider {}

    // ---- Footer -----------------------------------------------------
    Item {
        width: parent.width
        height: 24

        Text {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "↑↓ navigate · ↵ launch · esc close"
            font.family: Theme.fontSans
            font.pixelSize: 11
            color: Theme.textDim
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "super+space"
            font.family: Theme.fontMono
            font.pixelSize: 11
            font.weight: 500
            color: Theme.textDim
        }
    }
}
