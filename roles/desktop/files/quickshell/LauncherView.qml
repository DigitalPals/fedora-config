pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "Common"
import "Popovers"

// Eight-result launcher with explicit prefix modes:
// / files, > shell command, = calculator, @ web, $ windows.
//
// Visual shape from the "QuickShell Menubar" design: a recessed search tile,
// 48px result rows with a 32px icon, the selected row lifted on the accent,
// and a hairline footer carrying the count and the key hints.
Surface {
    id: root

    implicitWidth: 560

    readonly property int maxResults: 8
    readonly property int rowHeight: 48
    property int selected: 0
    readonly property string query: search.text
    readonly property bool inputActiveFocus: search.activeFocus
    readonly property string mode: ["/", ">", "=", "@", "$"].includes(query.charAt(0)) ? query.charAt(0) : ""
    readonly property string term: mode === "" ? query.trim() : query.slice(1).trim()

    property var fileResults: []
    property bool fileLoading: false
    property string fileError: ""
    property string calcResult: ""
    property bool calcLoading: false
    property string calcError: ""

    // The view is permanently warm. Reset synchronously on open and ask for
    // focus both now and on the next event-loop turn: the second request
    // covers the layer-surface mapping without clearing any text typed in the
    // meantime.
    function focusInput(): void {
        search.forceActiveFocus();
    }

    function prepareOpen(): void {
        search.text = "";
        selected = 0;
        focusInput();
        Qt.callLater(() => {
            if (Launcher.open)
                root.focusInput();
        });
    }

    Component.onCompleted: {
        if (Launcher.open)
            prepareOpen();
    }

    Connections {
        target: Launcher

        function onOpenChanged() {
            if (Launcher.open)
                root.prepareOpen();
        }
    }

    function words(value) {
        return (value || "").toLowerCase().split(/[^a-z0-9]+/).filter(Boolean);
    }

    function appScore(app) {
        const q = term.toLowerCase();
        // With no query the launcher is an alphabetical app directory. Launch
        // history only breaks relevance ties after the user starts searching.
        if (q === "")
            return 1;
        const name = (app.name || "").toLowerCase();
        const generic = (app.genericName || "").toLowerCase();
        const id = (app.id || "").replace(/\.desktop$/i, "").toLowerCase();
        const haystack = [name, generic, id, (app.keywords || []).join(" ").toLowerCase()];
        let match = -1;
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
        return match < 0 ? match : match + Launcher.usageBoost(app);
    }

    readonly property int appTotal: DesktopEntries.applications.values.filter(app => !app.noDisplay).length

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

    // Shared by the TextInput and by LauncherWindow's one-frame focus-race
    // fallback. Enter is intentionally handled regardless of modifiers, so
    // it can launch the selected first row even if Super has not yet lifted.
    function handleCommandKey(event): bool {
        if (event.key === Qt.Key_Escape) {
            Launcher.close();
        } else if (event.modifiers & Qt.AltModifier && event.key >= Qt.Key_1 && event.key <= Qt.Key_8) {
            activate(rows[event.key - Qt.Key_1]);
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            activate(rows[selected]);
        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
            selected = Math.min(Math.max(0, rows.length - 1), selected + 1);
        } else if (event.key === Qt.Key_Up) {
            selected = Math.max(0, selected - 1);
        } else if (event.key === Qt.Key_Home) {
            selected = 0;
        } else if (event.key === Qt.Key_End) {
            selected = Math.max(0, rows.length - 1);
        } else {
            return false;
        }
        return true;
    }

    function handleEarlyKey(event): bool {
        if (handleCommandKey(event))
            return true;
        const commandModifiers = Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier;
        if (event.text === "" || event.modifiers & commandModifiers)
            return false;
        focusInput();
        search.insert(search.cursorPosition, event.text);
        return true;
    }

    function esc(value) {
        return (value || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    function highlight(value, muted) {
        if (term === "" || muted)
            return esc(value);
        const index = (value || "").toLowerCase().indexOf(term.toLowerCase());
        if (index < 0)
            return esc(value);
        return esc(value.slice(0, index))
            + `<font color="${Theme.accent}">` + esc(value.slice(index, index + term.length)) + "</font>"
            + esc(value.slice(index + term.length));
    }

    // `muted` suppresses the accent match highlight — on the selected row the
    // accent is the background.
    function titleFor(row, muted) {
        switch (row.kind) {
        case "app": return highlight(row.app.name, muted);
        case "file": return highlight(row.path.split("/").pop(), muted);
        case "command": return "Run <font face=\"" + Theme.fontMono + "\">" + esc(row.command) + "</font>";
        case "calc": return esc(row.result);
        case "web": return "Search DuckDuckGo for “" + esc(row.query) + "”";
        case "window": return highlight(row.win.title || "Untitled window", muted);
        }
        return "";
    }

    function subtitleFor(row) {
        switch (row.kind) {
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
        return ({ file: "folder", command: "terminal", calc: "calculate", web: "public", window: "web_asset" })[kind] || "rocket_launch";
    }

    readonly property var modeMeta: ({
        "/": { label: "FILES", enter: "open" },
        ">": { label: "RUN", enter: "run" },
        "=": { label: "CALC", enter: "copy" },
        "@": { label: "WEB", enter: "search" },
        "$": { label: "WINDOWS", enter: "focus" }
    })

    readonly property string footerLeft: {
        switch (mode) {
        case "/": return fileLoading ? "fd · searching" : "fd · " + rows.length + " results";
        case ">": return "runs with sh -c";
        case "=": return "libqalculate";
        case "@": return "duckduckgo.com";
        case "$": return rows.length + (rows.length === 1 ? " window" : " windows");
        }
        if (term === "")
            return "/ files · > command · = calculate · @ web · $ windows";
        return rows.length + " of " + appTotal + " apps";
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

    // ---- Search tile -----------------------------------------------------
    Rectangle {
        width: parent.width
        height: 48
        radius: 22
        color: Theme.tile

        Behavior on color {
            ColorAnimation { duration: Theme.surfaceDuration }
        }

        Sym {
            id: searchGlyph
            x: 16
            anchors.verticalCenter: parent.verticalCenter
            name: root.mode === "" ? "search" : root.glyphFor(({ "/": "file", ">": "command", "=": "calc", "@": "web", "$": "window" })[root.mode])
            size: 18
            color: Theme.textDim
        }

        TextInput {
            id: search
            anchors.verticalCenter: parent.verticalCenter
            x: 44
            width: parent.width - x - (modeChip.visible ? modeChip.width + 24 : 16)
            font.family: Theme.fontSans
            font.pixelSize: Theme.fontBody
            font.weight: Theme.weightSemibold
            color: Theme.textHi
            clip: true
            focus: Launcher.open

            Text {
                visible: search.text === ""
                anchors.verticalCenter: parent.verticalCenter
                text: "Search apps"
                font: search.font
                color: Theme.textDim
            }

            Keys.onPressed: event => event.accepted = root.handleCommandKey(event)
        }

        // Active prefix mode, as the design draws its tab pill; clicking it
        // drops back to app search while keeping the typed term.
        Rectangle {
            id: modeChip
            visible: root.mode !== ""
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: modeLabel.implicitWidth + 20
            height: 22
            radius: Theme.pillRadius
            color: modeMouse.containsMouse ? Theme.hoverFillStrong : Theme.chipHover

            Text {
                id: modeLabel
                anchors.centerIn: parent
                text: root.mode !== "" ? root.modeMeta[root.mode].label : ""
                font.family: Theme.fontSans
                font.pixelSize: Theme.fontMicro
                font.weight: Theme.weightHeavy
                font.letterSpacing: 0.5
                color: Theme.textHi
            }

            MouseArea {
                id: modeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: search.text = root.term
            }
        }
    }

    // ---- Results ---------------------------------------------------------
    ListView {
        id: resultList
        width: parent.width
        height: Math.min(root.maxResults, root.rows.length) * root.rowHeight
        interactive: false
        model: root.rows

        delegate: Rectangle {
            id: resultRow

            required property var modelData
            required property int index
            readonly property bool isSelected: index === root.selected
            readonly property string subtitle: root.subtitleFor(modelData)
            width: resultList.width
            height: root.rowHeight
            radius: Theme.rowRadius
            color: isSelected ? Theme.accent : "transparent"

            Behavior on color {
                ColorAnimation { duration: Theme.chipFadeDuration }
            }

            Item {
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 32
                height: 32

                Image {
                    anchors.fill: parent
                    visible: resultRow.modelData.kind === "app" && source !== ""
                    source: resultRow.modelData.kind === "app" ? Quickshell.iconPath(resultRow.modelData.app.icon, true) : ""
                    sourceSize: Qt.size(64, 64)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }

                Rectangle {
                    visible: resultRow.modelData.kind !== "app"
                    anchors.fill: parent
                    radius: 10
                    color: Theme.chip

                    Sym {
                        anchors.centerIn: parent
                        name: root.glyphFor(resultRow.modelData.kind)
                        size: Theme.iconMedium
                        color: resultRow.isSelected ? Theme.textOnAccent : Theme.textMid
                    }
                }
            }

            Column {
                x: 54
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - x - 46
                spacing: 1

                Text {
                    width: parent.width
                    textFormat: Text.StyledText
                    text: root.titleFor(resultRow.modelData, resultRow.isSelected)
                    font.family: Theme.fontSans
                    font.pixelSize: Theme.fontSecondary
                    font.weight: Theme.weightBold
                    color: resultRow.isSelected ? Theme.textOnAccent : Theme.textHi
                    elide: Text.ElideRight
                }

                Text {
                    visible: resultRow.subtitle !== ""
                    width: parent.width
                    text: resultRow.subtitle
                    font.family: Theme.fontSans
                    font.pixelSize: Theme.fontMicro
                    font.weight: Theme.weightSemibold
                    color: resultRow.isSelected ? Qt.rgba(1, 1, 1, 0.78) : Theme.textDim
                    elide: Text.ElideMiddle
                }
            }

            Rectangle {
                visible: resultRow.isSelected
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: enterGlyph.implicitWidth + 12
                height: 18
                radius: 6
                color: Qt.rgba(1, 1, 1, 0.22)

                Text {
                    id: enterGlyph
                    anchors.centerIn: parent
                    text: "↵"
                    font.family: Theme.fontSans
                    font.pixelSize: Theme.fontMicro
                    font.weight: Theme.weightHeavy
                    color: Theme.textOnAccent
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.selected = resultRow.index
                onClicked: root.activate(resultRow.modelData)
            }
        }
    }

    // ---- Empty state -----------------------------------------------------
    Column {
        visible: root.rows.length === 0
        width: parent.width
        topPadding: 18
        bottomPadding: 12
        spacing: 6

        Sym {
            anchors.horizontalCenter: parent.horizontalCenter
            name: "search_off"
            size: Theme.iconLarge + 2
            color: Theme.textDim
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 40
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
            font.pixelSize: Theme.fontTiny
            font.weight: Theme.weightBold
            color: root.fileError !== "" || root.calcError !== "" ? Theme.redText : Theme.textDim
            elide: Text.ElideRight
        }
    }

    HDivider {}

    // ---- Footer ----------------------------------------------------------
    Item {
        width: parent.width
        height: 20

        Text {
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - hints.width - 32
            text: root.footerLeft
            font.family: Theme.fontSans
            font.pixelSize: Theme.fontMicro
            font.weight: Theme.weightBold
            color: Theme.textDim
            elide: Text.ElideRight
        }

        Row {
            id: hints
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12

            Repeater {
                model: [
                    "↑↓ select",
                    "↵ " + (root.mode === "" ? "launch" : root.modeMeta[root.mode].enter),
                    "esc close"
                ]

                delegate: Text {
                    required property string modelData
                    text: modelData
                    font.family: Theme.fontSans
                    font.pixelSize: Theme.fontMicro
                    font.weight: Theme.weightBold
                    color: Theme.textDim
                }
            }
        }
    }
}
