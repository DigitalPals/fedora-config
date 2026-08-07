import QtQuick
import ".."

// Base for every bar module.
//
// It exists to make the bar's contract with its modules a real one. The
// ModuleSlot that loads these used to reach into `Loader.item` and ask
// `"isle" in item` before assigning — duck-typing that no tool could check,
// and the source of the last `missing-property` warning on the bar side. With
// a shared base the slot can assert `item as BarModule` and every one of
// these becomes a typed property access.
//
// A Row rather than an Item: seven of the thirteen modules already were one
// so they could sit their content between dividers, and a Row of a single
// child lays out exactly as that child did alone.
Row {
    id: root

    // ---- assigned by the bar --------------------------------------------
    // The window this module belongs to. Modules reach the bar through this
    // rather than an outer id, because they are separate files now.
    property Bar host: null
    // The column the module actually landed in — the user can move modules
    // between columns, so this is not the panel's default island.
    property string isle: "right"
    // Whether a visible module sits before/after this one in the same column.
    property bool dividerBefore: false
    property bool dividerAfter: false

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

    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
}
