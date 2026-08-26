pragma Singleton
import QtQuick
import Quickshell

// The allow-list for product marks bundled with the shell.
//
// Generic interface glyphs belong in Sym, and installed applications belong
// to the desktop icon theme. Only an identity that must keep its own mark is
// admitted here. Keeping the filenames behind this boundary also prevents
// provider/service data from becoming an arbitrary asset path.
Singleton {
    id: root

    readonly property var names: [
        "claude", "github", "kimi", "openai",
        "t3", "tailscale", "whatsapp", "youtube"
    ]
    readonly property var files: ({
        claude: "claude.svg",
        github: "github.svg",
        kimi: "kimi.svg",
        openai: "openai.svg",
        t3: "t3.svg",
        tailscale: "tailscale.svg",
        whatsapp: "whatsapp.svg",
        youtube: "youtube.svg"
    })
    readonly property var labels: ({
        claude: "Claude",
        github: "GitHub",
        kimi: "Kimi",
        openai: "OpenAI",
        t3: "T3 Code",
        tailscale: "Tailscale",
        whatsapp: "WhatsApp",
        youtube: "YouTube"
    })

    function key(value) {
        return String(value ?? "").trim().toLowerCase();
    }

    function has(value) {
        return names.indexOf(key(value)) >= 0;
    }

    function source(value) {
        const name = key(value);
        return has(name) ? Quickshell.shellDir + "/assets/" + files[name] : "";
    }

    function label(value) {
        const name = key(value);
        return has(name) ? labels[name] : "";
    }
}
