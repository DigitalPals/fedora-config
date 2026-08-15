import QtQuick
import ".."

// Base for every bar module.
//
// It exists to make the bar's contract with its modules a real one. The
// ModuleSlot that loads these used to reach into `Loader.item` and ask
// `"isle" in item` before assigning — duck-typing that no tool could check.
// With a shared base the slot can assert `item as BarModule` and every one of
// these becomes a typed property access.
//
// A Row rather than an Item: several modules lay content out in one, and a Row
// of a single child lays out exactly as that child did alone.
Row {
    id: root

    // ---- assigned by the bar --------------------------------------------
    // The window this module belongs to. Modules reach the bar through this
    // rather than an outer id, because they are separate files.
    property Bar host: null
    // The column the module actually landed in — the user can move modules
    // between columns, so this is not the panel's default island.
    property string isle: "right"

    // The shared pill this module was placed inside, or null when it draws
    // its own. A module that owns a panel hangs it under this rather than
    // under its own glyph, so the panel lines up with the shape that was
    // clicked.
    property Item groupAnchor: null

    // False when the group around this module owns the pointer: the status
    // pill and the centre pill are single buttons, so the modules inside them
    // must not put a second target on top of one.
    property bool interactive: true

    // Which module this is, as named in Settings.mods. Drives `compact`, and
    // saves every module repeating its own id at the call site.
    property string moduleId: ""

    // True while the fit pass has asked this module to drop its detail text.
    // Null-safe because `host` is assigned after construction, so a binding
    // that reached through it directly would evaluate once against null.
    readonly property bool compact: host !== null && moduleId !== ""
        && host.moduleCompact(moduleId)

    // ---- reported to the bar --------------------------------------------
    // Width this module would give back if its detail text were hidden. The
    // fit pass reads it to decide what to compact; 0 means nothing to give.
    property real detailSaving: 0

    spacing: 0
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
}
