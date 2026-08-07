pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

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

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    // A node exists before its audio group arrives, so "there is a sink"
    // and "the sink can be read" are different questions.
    readonly property bool ready: sink !== null && sink.audio !== null
    readonly property bool sourceReady: source !== null && source.audio !== null

    readonly property int volume: ready ? Math.round(sink.audio.volume * 100) : 0
    readonly property bool muted: ready && sink.audio.muted
    readonly property bool sourceMuted: sourceReady && source.audio.muted

    // Fraction, 0..1, clamped — the wheel handlers all stepped and clamped
    // this identically.
    function setVolume(fraction) {
        if (!ready)
            return;
        sink.audio.volume = Math.max(0, Math.min(1, fraction));
    }

    function stepVolume(delta) {
        if (ready)
            setVolume(sink.audio.volume + delta);
    }

    function toggleMuted() {
        if (ready)
            sink.audio.muted = !sink.audio.muted;
    }

    function toggleSourceMuted() {
        if (sourceReady)
            source.audio.muted = !source.audio.muted;
    }

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }
}
