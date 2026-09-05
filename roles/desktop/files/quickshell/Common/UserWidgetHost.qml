import QtQuick

// The public v1 contract is the injected pluginApi object, not any shell type.
Item {
    id: root

    required property var descriptor
    required property var themeValues
    property string screenName: ""
    property var component: null
    property Item widget: null
    property string loadError: ""
    readonly property string error: descriptor.error || loadError
    readonly property bool ready: widget !== null
    signal settingRequested(string pluginId, string key, string value)

    clip: true
    implicitWidth: descriptor.width

    QtObject {
        id: api
        readonly property int version: 1
        readonly property string id: root.descriptor.id
        readonly property var settings: root.descriptor.settings
        readonly property var theme: root.themeValues
        readonly property string packagePath: root.descriptor.packagePath || ""
        readonly property string dataPath: root.descriptor.dataPath || ""
        readonly property string screenName: root.screenName
        readonly property real width: root.width
        readonly property real height: root.height

        function setSetting(key, value) {
            root.settingRequested(id, String(key), JSON.stringify(value));
        }
    }

    function finishLoad() {
        if (!component)
            return;
        if (component.status === Component.Error) {
            loadError = component.errorString();
        } else if (component.status === Component.Ready && !widget) {
            const object = component.createObject(root, { pluginApi: api });
            const item = object as Item;
            if (!item) {
                if (object)
                    object.destroy();
                loadError = "Widget must be a QtQuick Item with a pluginApi property";
                return;
            }
            widget = item;
            widget.width = Qt.binding(() => root.width);
            widget.height = Qt.binding(() => root.height);
        }
    }

    function unload() {
        if (widget) {
            widget.destroy();
            widget = null;
        }
        if (component) {
            component.destroy();
            component = null;
        }
    }

    function reload() {
        unload();
        loadError = "";
        if (descriptor.error || !descriptor.source)
            return;
        component = Qt.createComponent(descriptor.source, Component.Asynchronous);
        if (component.status === Component.Loading)
            component.statusChanged.connect(finishLoad);
        finishLoad();
    }

    Component.onCompleted: reload()
    Component.onDestruction: unload()

    Rectangle {
        anchors.fill: parent
        visible: root.error !== ""
        color: root.themeValues.background
        radius: 5
        Text {
            anchors.fill: parent
            anchors.margins: 4
            verticalAlignment: Text.AlignVCenter
            text: root.descriptor.name + " !"
            elide: Text.ElideRight
            color: root.themeValues.foreground
            font.pixelSize: root.themeValues.fontSize
        }
        Accessible.role: Accessible.StaticText
        Accessible.name: root.descriptor.name + ": " + root.error
    }
}
