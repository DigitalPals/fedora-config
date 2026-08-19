pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "Format.js" as Format

// Default audio devices for the whole shell. Pipewire only populates a
// node's `audio` group while something tracks it, and the bar is
// instantiated once per output — four separate PwObjectTrackers used to
// bind the same two nodes, one of them multiplied by the monitor count.
// This is the single tracker; consumers read the derived values.
//
// Volume is exposed both ways on purpose: `volume` is the rounded percent
// every label and meter wants, while `setVolume`/`toggleMuted` take the
// 0..1 scale Pipewire stores, so no consumer has to convert twice or
// repeat the null guards.
Singleton {
    id: root

    // The XPS speaker filter is a virtual sink in front of the physical
    // speakers. Keep the virtual node at unity gain and expose the underlying
    // speaker as the control sink; external outputs continue to use the normal
    // PipeWire default directly.
    readonly property var outputSink: Pipewire.defaultAudioSink
    readonly property var tuningSink: Pipewire.nodes.values.find(n =>
        n.isSink && !n.isStream && n.name === "xps_speaker_tuning") ?? null
    readonly property var speakerSink: Pipewire.nodes.values.find(n =>
        n.isSink && !n.isStream
            && /^alsa_output.*sof_sdw.*HiFi__Speaker__sink$/.test(n.name || "")) ?? null
    readonly property bool tuningPresent: tuningSink !== null
    readonly property var sink: outputSink === tuningSink && speakerSink !== null
        ? speakerSink : outputSink
    readonly property var source: Pipewire.defaultAudioSource

    // A node exists before its audio group arrives, so "there is a sink"
    // and "the sink can be read" are different questions.
    readonly property bool ready: sink !== null && sink.audio !== null
    readonly property bool sourceReady: source !== null && source.audio !== null

    // Percent for labels and glyph thresholds; `level` is the same reading on
    // Pipewire's own 0..1 scale, for sliders that would otherwise snap to
    // whole percents on read-back.
    readonly property int volume: ready ? Math.round(sink.audio.volume * 100) : 0
    readonly property real level: ready ? sink.audio.volume : 0
    readonly property bool muted: ready && sink.audio.muted

    readonly property int sourceVolume: sourceReady ? Math.round(source.audio.volume * 100) : 0
    readonly property real sourceLevel: sourceReady ? source.audio.volume : 0
    readonly property bool sourceMuted: sourceReady && source.audio.muted

    // Setters take the 0..1 scale and clamp — the wheel handlers all stepped
    // and clamped this identically.
    function setVolume(fraction) {
        if (!ready)
            return;
        sink.audio.volume = Format.clamp01(fraction);
    }

    function stepVolume(delta) {
        if (ready)
            setVolume(sink.audio.volume + delta);
    }

    function toggleMuted() {
        if (ready)
            sink.audio.muted = !sink.audio.muted;
    }

    // Pipewire remembers this as a preference, so it survives the node
    // disappearing and coming back.
    function setDefaultSink(node) {
        Pipewire.preferredDefaultAudioSink = node;
    }

    function setSourceVolume(fraction) {
        if (!sourceReady)
            return;
        source.audio.volume = Format.clamp01(fraction);
    }

    function toggleSourceMuted() {
        if (sourceReady)
            source.audio.muted = !source.audio.muted;
    }

    PwObjectTracker {
        objects: [root.outputSink, root.sink, Pipewire.defaultAudioSource]
    }
}
