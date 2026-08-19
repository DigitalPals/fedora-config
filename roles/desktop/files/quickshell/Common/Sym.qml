import QtQuick

// One Material Symbols Rounded glyph.
//
// The face is a four-axis variable font and the glyph is selected by ligature
// name ("power_settings_new"), so drawing one by hand means remembering to set
// the family, the axes, and to keep `opsz` in step with the pixel size or the
// stroke reads too heavy at small sizes. This wraps all of that.
//
// `fill` animates: the design lights a toggle by filling its icon rather than
// swapping glyphs, and the axis interpolates continuously, so the transition
// is a real morph rather than a cross-fade between two shapes.
Text {
    id: root

    // Ligature name from the Material Symbols set, e.g. "wifi", "coffee".
    property alias name: root.text
    property real size: 16
    // 0 outline, 1 solid. Fractional values are valid and are what the
    // Behavior below animates through.
    property real fill: 0
    // Stroke weight, 100..700 on the font's own axis.
    property real symWeight: 500
    // Emphasis correction for dark backgrounds, -25..200.
    property real grade: 0
    property bool animateFill: true

    font.family: Theme.fontIcon
    font.pixelSize: size
    // The optical-size axis is defined over 20..48; clamping rather than
    // extrapolating keeps hairlines honest on the 11px marks in a panel.
    font.variableAxes: ({
        "FILL": root.fill,
        "wght": root.symWeight,
        "GRAD": root.grade,
        "opsz": Math.max(20, Math.min(48, root.size))
    })
    color: Theme.icon
    // These marks live inside controls and panels that scale during their
    // transitions. Qt's native renderer rasterizes text for one size and can
    // look pixelated under transforms; QtRendering keeps those animated edges
    // stable while retaining hinting at the small resting sizes.
    renderType: Text.QtRendering
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignHCenter
    // Ink overflows the advance box on several marks; letting the Text size
    // itself and centring the wrapper is what keeps a row of icons aligned.
    lineHeight: 1.0

    Behavior on fill {
        enabled: root.animateFill
        NumberAnimation {
            duration: Theme.chipFadeDuration
            easing.type: Easing.OutCubic
        }
    }

    Behavior on color {
        ColorAnimation { duration: Theme.chipFadeDuration }
    }
}
