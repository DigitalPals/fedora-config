import QtQuick
import ".."
import "../../Common"

// Grouped per-provider model usage chips.
BarModule {
    id: usageModule

    moduleId: "usage"
    spacing: 1
    detailSaving: usageChips.detailSaving

    Divider {
        visible: usageModule.dividerBefore
    }

    // Keep one anchor for the grouped provider module: changing
    // Claude/Codex/Kimi content must not slide the panel.
    UsageChips {
        id: usageChips
        host: usageModule.host
        panelName: "usage"
        isle: usageModule.isle
        displayMode: usageModule.compact ? 0 : 2
        onChipClicked: key => {
            if (usageModule.host.popoutOpen("usage") && Usage.selected === key) {
                Popouts.close();
            } else {
                Usage.selected = key;
                Popouts.openPanel("usage", usageModule.isle,
                    usageModule.host.anchorOf(usageChips));
            }
        }
        onChipEntered: key => {
            if (Popouts.open)
                Usage.selected = key;
            usageModule.host.hoverOpen("usage", usageModule.isle, usageChips);
        }
        onChipExited: usageModule.host.cancelHover("usage")
    }

    Divider {
        visible: usageModule.dividerAfter
    }
}
