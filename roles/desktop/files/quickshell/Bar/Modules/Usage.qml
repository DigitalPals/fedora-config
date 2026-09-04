import QtQuick
import ".."
import "../../Common"

// Grouped per-provider model usage chips.
BarModule {
    id: root

    moduleId: "usage"
    detailSaving: usageChips.detailSaving

    // One popout anchor for the whole group: changing Claude/Codex/Kimi
    // content must not slide the panel out from under the pointer.
    UsageChips {
        id: usageChips
        host: root.host
        panelName: "usage"
        isle: root.isle
        anchorItem: root.groupAnchor ?? usageChips
        displayMode: root.compact ? 0 : 2
        onChipClicked: key => {
            if (root.host.popoutOpen("usage")
                    && (key === "" || Usage.selected === key)) {
                Popouts.close();
            } else {
                if (key !== "")
                    Usage.selected = key;
                root.host.openPopout("usage", root.isle, usageChips.anchorItem);
            }
        }
        // Usage joins the bar-wide latched menu session while retaining its
        // per-provider selection. Selecting first means a switch from another
        // panel presents the right provider on its first rendered frame.
        onChipEntered: key => {
            if (!Popouts.open)
                return;
            if (key !== "")
                Usage.selected = key;
            root.host.hoverPopout("usage", root.isle, usageChips.anchorItem);
        }
    }
}
