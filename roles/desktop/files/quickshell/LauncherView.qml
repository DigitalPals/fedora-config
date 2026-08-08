pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "Common"
import "Popovers"

// Eight-result launcher with explicit prefix modes:
// / files, > shell command, = calculator, @ web, $ windows.
Surface {
    id: root

    implicitWidth: 600

    readonly property int maxResults: 8
    property int selected: 0
    readonly property string query: search.text
    readonly property string mode: ["/", ">", "=", "@", "$"].includes(query.charAt(0)) ? query.charAt(0) : ""
    readonly property string term: mode === "" ? query.trim() : query.slice(1).trim()

    property var fileResults: []
    property bool fileLoading: false
    property string fileError: ""
    property string calcResult: ""
    property bool calcLoading: false
    property string calcError: ""

    // The instance survives across opens, so each open must restore the
    // fresh state a create-per-open Loader used to provide implicitly.
    // Clearing the query also clears results and errors via onQueryChanged.
    Connections {
        target: Launcher

        function onOpenChanged() {
            if (!Launcher.open)
                return;
            search.text = "";
            root.selected = 0;
            search.forceActiveFocus();
        }
    }

    function words(value) {
        return (value || "").toLowerCase().split(/[^a-z0-9]+/).filter(Boolean);
    }

    function appScore(app) {
        const q = term.toLowerCase();
        const name = (app.name || "").toLowerCase();
        const generic = (app.genericName || "").toLowerCase();
        const id = (app.id || "").replace(/\.desktop$/i, "").toLowerCase();
        const haystack = [name, generic, id, (app.keywords || []).join(" ").toLowerCase()];
        let match = q === "" ? 1 : -1;
        if (q !== "") {
            if (name === q || generic === q || id === q)
                match = 10000;
            else if (name.startsWith(q) || generic.startsWith(q) || id.startsWith(q))
                match = 8000;
            else if (haystack.some(value => root.words(value).some(word => word.startsWith(q))))
                match = 6000;
            else if (name.includes(q) || generic.includes(q) || id.includes(q))
                match = 4000;
            else if (haystack.some(value => value.includes(q)))
                match = 2000;
        }
        return match < 0 ? match : match + Launcher.usageBoost(app);
    }

    readonly property var appRows: {
        if (mode !== "")
            return [];
        return DesktopEntries.applications.values
            .filter(app => !app.noDisplay)
            .map(app => ({ kind: "app", app: app, score: root.appScore(app) }))
            .filter(row => row.score >= 0)
            .sort((a, b) => b.score - a.score || a.app.name.localeCompare(b.app.name))
            .slice(0, maxResults);
    }

    function windowScore(win) {
        const q = term.toLowerCase();
        const ipc = win.lastIpcObject || {};
        const title = (win.title || "").toLowerCase();
        const cls = (ipc.class || ipc.initialClass || "").toLowerCase();
        if (q === "")
            return win.activated ? 100 : 1;
        if (title === q || cls === q)
            return 10000;
        if (title.startsWith(q) || cls.startsWith(q))
            return 8000;
        if (root.words(title + " " + cls).some(word => word.startsWith(q)))
            return 6000;
        if (title.includes(q) || cls.includes(q))
            return 4000;
        return -1;
    }

    readonly property var windowRows: {
        if (mode !== "$")
            return [];
        return Hyprland.toplevels.values
            .map(win => ({ kind: "window", win: win, score: root.windowScore(win) }))
            .filter(row => row.score >= 0)
            .sort((a, b) => b.score - a.score || a.win.title.localeCompare(b.win.title))
            .slice(0, maxResults);
    }

    readonly property var rows: {
        switch (mode) {
        case "/":
            return fileResults.slice(0, maxResults).map(path => ({ kind: "file", path: path }));
        case ">":
            return term === "" ? [] : [{ kind: "command", command: term }];
        case "=":
            return calcResult === "" ? [] : [{ kind: "calc", result: calcResult }];
        case "@":
            return term === "" ? [] : [{ kind: "web", query: term }];
        case "$":
            return windowRows;
        default:
            return appRows;
        }
    }

    onRowsChanged: selected = Math.min(selected, Math.max(0, rows.length - 1))
    onQueryChanged: {
        selected = 0;
        fileError = "";
        calcError = "";
        if (mode === "/" && term.length >= 2) {
            fileResults = [];
            fileLoading = true;
            fileDebounce.restart();
        } else {
            fileDebounce.stop();
            fileLoading = false;
            fileResults = [];
        }
        if (mode === "=" && term !== "") {
            calcResult = "";
            calcLoading = true;
            calcDebounce.restart();
        } else {
            calcDebounce.stop();
            calcLoading = false;
            calcResult = "";
        }
    }

    function activate(row) {
        if (!row)
            return;
        switch (row.kind) {
        case "app":
            Launcher.recordLaunch(row.app);
            row.app.execute();
            Launcher.close();
            break;
        case "file":
            Quickshell.execDetached(["xdg-open", row.path]);
            Launcher.close();
            break;
        case "command":
            Launcher.executeCommand(row.command);
            break;
        case "calc":
            Quickshell.clipboardText = row.result;
            Launcher.close();
            break;
        case "web":
            Quickshell.execDetached(["xdg-open", "https://duckduckgo.com/?q=" + encodeURIComponent(row.query)]);
            Launcher.close();
            break;
        case "window":
            Hyprland.dispatch("focuswindow address:" + row.win.address);
            Launcher.close();
            break;
        }
    }

    function esc(value) {
        return (value || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    function highlight(value) {
        if (term === "")
            return esc(value);
        const index = (value || "").toLowerCase().indexOf(term.toLowerCase());
        if (index < 0)
            return esc(value);
        return esc(value.slice(0, index))
            + `<font color="${Theme.accent}">` + esc(value.slice(index, index + term.length)) + "</font>"
            + esc(value.slice(index + term.length));
    }

    function titleFor(row) {
        switch (row.kind) {
        case "app": return highlight(row.app.name);
        case "file": return highlight(row.path.split("/").pop());
        case "command": return "Run <font face=\"" + Theme.fontMono + "\">" + esc(row.command) + "</font>";
        case "calc": return esc(row.result);
        case "web": return "Search DuckDuckGo for “" + esc(row.query) + "”";
        case "window": return highlight(row.win.title || "Untitled window");
        }
        return "";
    }

    function subtitleFor(row) {
        switch (row.kind) {
        case "app": return row.app.genericName || row.app.comment || "Application";
        case "file": return row.path;
        case "command": return "Explicit shell command";
        case "calc": return "Press Enter to copy result";
        case "web": return "DuckDuckGo";
        case "window": {
            const ipc = row.win.lastIpcObject || {};
            return ipc.class || ipc.initialClass || "Hyprland window";
        }
        }
        return "";
    }

    function glyphFor(kind) {
        return ({ file: "\uf07b", command: "\uf120", calc: "\uf1ec", web: "\uf0ac", window: "\uf2d0" })[kind] || "\uf135";
    }

    Timer {
        id: fileDebounce
        interval: 180
        onTriggered: {
            fileProc.running = false;
            fileProc.command = ["fd", "--absolute-path", "--color", "never", "--hidden", "--fixed-strings",
                "--max-results", String(root.maxResults), "--exclude", ".cache", "--exclude", ".git", "--", root.term,
                Quickshell.env("HOME")];
            fileProc.running = true;
        }
    }

    Process {
        id: fileProc
        property string request: ""
        onRunningChanged: {
            if (running)
                request = root.term;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                if (fileProc.request === root.term)
                    root.fileResults = text.trim() === "" ? [] : text.trim().split("\n").slice(0, root.maxResults);
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (fileProc.request === root.term)
                    root.fileError = text.trim();
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (request === root.term) {
                root.fileLoading = false;
                if (exitCode !== 0 && root.fileError === "")
                    root.fileError = `File search exited with status ${exitCode}`;
            }
        }
    }

    Timer {
        id: calcDebounce
        interval: 120
        onTriggered: {
            calcProc.running = false;
            calcProc.command = ["qalc", "-t", root.term];
            calcProc.running = true;
        }
    }

    Process {
        id: calcProc
        property string request: ""
        onRunningChanged: {
            if (running)
                request = root.term;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                if (calcProc.request === root.term)
                    root.calcResult = text.trim().split("\n").pop() || "";
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (calcProc.request === root.term)
                    root.calcError = text.trim();
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (request === root.term) {
                root.calcLoading = false;
                if (exitCode !== 0 && root.calcError === "")
                    root.calcError = `Calculator exited with status ${exitCode}`;
            }
        }
    }

    Rectangle {
        width: parent.width
        height: 44
        radius: 10
        color: Theme.hoverFill

        Row {
            anchors.verticalCenter: parent.verticalCenter
            x: 12
            spacing: 10

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.mode === "" ? "\uf002" : root.glyphFor(({ "/": "file", ">": "command", "=": "calc", "@": "web", "$": "window" })[root.mode])
                font.family: Theme.fontIcon
                font.pixelSize: Theme.fontBody
                color: Theme.textLow
            }

            TextInput {
                id: search
                anchors.verticalCenter: parent.verticalCenter
                width: root.width - 72
                font.family: Theme.fontSans
                font.pixelSize: Theme.fontBody
                color: Theme.textHi
                clip: true
                focus: true

                Text {
                    visible: search.text === ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Search applications…"
                    font: search.font
                    color: Theme.textDim
                }

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        Launcher.close();
                        event.accepted = true;
                    } else if (event.modifiers & Qt.AltModifier && event.key >= Qt.Key_1 && event.key <= Qt.Key_8) {
                        root.activate(root.rows[event.key - Qt.Key_1]);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.activate(root.rows[root.selected]);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                        root.selected = Math.min(root.rows.length - 1, root.selected + 1);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Up) {
                        root.selected = Math.max(0, root.selected - 1);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Home) {
                        root.selected = 0;
                        event.accepted = true;
                    } else if (event.key === Qt.Key_End) {
                        root.selected = Math.max(0, root.rows.length - 1);
                        event.accepted = true;
                    }
                }
            }
        }
    }

    Item { width: 1; height: 8 }

    ListView {
        id: resultList
        width: parent.width
        height: Math.min(root.maxResults, root.rows.length) * 52
        interactive: false
        model: root.rows

        delegate: Rectangle {
            id: resultRow

            required property var modelData
            required property int index
            readonly property bool isSelected: index === root.selected

            width: resultList.width
            height: 52
            radius: 10
            color: isSelected ? Theme.activeFill : rowMouse.containsMouse ? Theme.hoverFill : "transparent"

            Item {
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 24
                height: 24

                Image {
                    anchors.fill: parent
                    visible: resultRow.modelData.kind === "app" && source !== ""
                    source: resultRow.modelData.kind === "app" ? Quickshell.iconPath(resultRow.modelData.app.icon, true) : ""
                    sourceSize: Qt.size(24, 24)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }

                Text {
                    anchors.centerIn: parent
                    visible: resultRow.modelData.kind !== "app"
                    text: root.glyphFor(resultRow.modelData.kind)
                    font.family: Theme.fontIcon
                    font.pixelSize: 15
                    color: resultRow.isSelected ? Theme.textHi : Theme.textMid
                }
            }

            Column {
                x: 48
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 104
                spacing: 1

                Text {
                    width: parent.width
                    textFormat: Text.StyledText
                    text: root.titleFor(resultRow.modelData)
                    font.family: Theme.fontSans
                    font.pixelSize: Theme.fontSecondary
                    font.weight: Theme.weightMedium
                    color: resultRow.isSelected ? Theme.textHi : Theme.textMid
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: root.subtitleFor(resultRow.modelData)
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                    color: resultRow.isSelected ? Theme.textLow : Theme.textDim
                    elide: Text.ElideMiddle
                }
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: resultRow.isSelected ? "↵" : "alt+" + (resultRow.index + 1)
                font.family: Theme.fontMono
                font.pixelSize: 11
                color: resultRow.isSelected ? Theme.textDim : Theme.textFaint
            }

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.selected = resultRow.index
                onClicked: root.activate(resultRow.modelData)
            }
        }
    }

    Text {
        visible: root.rows.length === 0
        width: parent.width
        topPadding: 14
        bottomPadding: 14
        horizontalAlignment: Text.AlignHCenter
        text: {
            if (root.mode === "/" && root.term.length < 2)
                return "Type at least two characters to search files";
            if (root.fileLoading || root.calcLoading)
                return "Searching…";
            if (root.fileError !== "")
                return "File search failed: " + root.fileError;
            if (root.calcError !== "")
                return "Calculation failed: " + root.calcError;
            if (root.mode === ">")
                return "Enter a shell command";
            if (root.mode === "@")
                return "Enter a web query";
            return "No matching results";
        }
        font.family: Theme.fontSans
        font.pixelSize: 11
        color: root.fileError !== "" || root.calcError !== "" ? Theme.redText : Theme.textDim
        elide: Text.ElideRight
    }

    HDivider {}

    Item {
        width: parent.width
        height: 28

        Text {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "/ files · > command · = calculate · @ web · $ windows"
            font.family: Theme.fontSans
            font.pixelSize: 10
            color: Theme.textDim
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "↑↓ · ↵ · esc"
            font.family: Theme.fontMono
            font.pixelSize: 10
            color: Theme.textDim
        }
    }
}
