// Pure presentation and grouping helpers for PipeWire sinks. Keep this free
// of Qt APIs so the same rules can be exercised by the Node unit tests.

function nodeName(node) {
    return node && typeof node.name === "string" ? node.name : "";
}

function rawLabel(node) {
    if (!node)
        return "No output device";
    return String(node.description || node.nickname || node.name || "Unknown output");
}

function sinkLabel(node) {
    var name = nodeName(node);
    var label = rawLabel(node);

    if (name === "xps_speaker_tuning")
        return "Laptop Speakers";
    if (/ADAM_Audio_D3V/i.test(name) || /PCM2704.*stereo audio DAC/i.test(label))
        return "ADAM D3V";
    if (/Studio_Display_XDR/i.test(name) || /Studio Display XDR/i.test(label))
        return "Studio Display XDR";
    if (/HiFi__Headphones__sink$/.test(name))
        return "Headphones";

    var hdmi = label.match(/HD Audio HDMI \/ DisplayPort ([0-9]+) Output/i);
    if (hdmi)
        return "HDMI / DisplayPort " + hdmi[1];

    return label;
}

function isNetworkSink(node) {
    var name = nodeName(node).toLowerCase();
    return name.indexOf("raop_sink.") === 0
        || name.indexOf("rtp_sink.") === 0
        || name.indexOf("roc_sink.") === 0
        || name.indexOf("tunnel_sink.") === 0;
}

function sortSinks(sinks, current) {
    return (Array.isArray(sinks) ? sinks : []).slice().sort(function(a, b) {
        if (a === current)
            return -1;
        if (b === current)
            return 1;
        return sinkLabel(a).localeCompare(sinkLabel(b));
    });
}

function localSinks(sinks, current) {
    return sortSinks((Array.isArray(sinks) ? sinks : []).filter(function(node) {
        return !isNetworkSink(node);
    }), current);
}

function networkSinks(sinks, current) {
    return sortSinks((Array.isArray(sinks) ? sinks : []).filter(isNetworkSink), current);
}

var exported = {
    sinkLabel: sinkLabel,
    isNetworkSink: isNetworkSink,
    sortSinks: sortSinks,
    localSinks: localSinks,
    networkSinks: networkSinks
};

if (typeof module !== "undefined" && module.exports)
    module.exports = exported;
