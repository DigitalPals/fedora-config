pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import "../Common"

// V1 occupies a bounded region before the built-in right-hand widgets.
Row {
    id: root

    property string screenName: ""
    property real availableWidth: 320
    readonly property var themeValues: ({
        foreground: String(Theme.barTextHi), background: String(Theme.barChip),
        accent: String(Theme.barAccent), fontFamily: Theme.fontMenu,
        fontSize: Theme.barLabelSize, reducedMotion: Settings.reducedMotion
    })
    spacing: Theme.barSpacing
    visible: UserPlugins.enabled.length > 0 || UserPlugins.error !== ""
    readonly property var hiddenWidgets: UserPlugins.enabled.filter((plugin, index) => !fits(index))

    function fits(index) {
        let used = 0;
        for (let i = 0; i <= index; i++)
            used += UserPlugins.enabled[i].width + (i > 0 ? spacing : 0);
        // Reserve space for an overflow count so hidden widgets are discoverable.
        return used <= Math.max(0, availableWidth - 36);
    }

    Repeater {
        model: UserPlugins.enabled
        delegate: UserWidgetHost {
            id: widgetHost
            required property var modelData
            required property int index
            descriptor: modelData
            themeValues: root.themeValues
            screenName: root.screenName
            width: descriptor.width
            height: Theme.chipHeight
            visible: root.fits(index)
            onSettingRequested: (pluginId, key, value) => UserPlugins.setSetting(pluginId, key, value)

            HoverHandler { id: hover }
            ToolTip.visible: hover.hovered && widgetHost.error !== ""
            ToolTip.text: widgetHost.error
        }
    }

    Text {
        visible: root.hiddenWidgets.length > 0
        text: "+" + root.hiddenWidgets.length
        color: Theme.barTextHi
        font.pixelSize: Theme.barLabelSize
        height: Theme.chipHeight
        verticalAlignment: Text.AlignVCenter
        readonly property string description: "Widgets hidden for space: "
            + root.hiddenWidgets.map(plugin => plugin.name).join(", ")
        Accessible.name: description
        HoverHandler { id: overflowHover }
        ToolTip.visible: overflowHover.hovered
        ToolTip.text: description
    }

    Text {
        visible: UserPlugins.error !== ""
        text: "Widgets !"
        color: Theme.barTextHi
        font.pixelSize: Theme.barLabelSize
        height: Theme.chipHeight
        verticalAlignment: Text.AlignVCenter
        Accessible.name: UserPlugins.error
        HoverHandler { id: registryHover }
        ToolTip.visible: registryHover.hovered
        ToolTip.text: UserPlugins.error
    }
}
