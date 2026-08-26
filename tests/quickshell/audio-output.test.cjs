const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir, load } = require("./shell.cjs");

const H = load("AudioHelpers.js");

const laptop = { name: "xps_speaker_tuning", description: "Laptop Speakers" };
const adam = {
    name: "alsa_output.usb-Vendor_strings_are_placed_here._ADAM_Audio_D3V-00.analog-stereo",
    description: "PCM2704 16-bit stereo audio DAC Analog Stereo",
};
const studio = {
    name: "alsa_output.usb-Apple_Inc._Studio_Display_XDR_123.analog-stereo",
    description: "Studio Display XDR Analog Stereo",
};
const hdmi = {
    name: "alsa_output.pci.HiFi__HDMI2__sink",
    description: "Core Ultra Processors (Series 3) HD Audio HDMI / DisplayPort 2 Output",
};
const airplay = { name: "raop_sink.Sonos.local", description: "Living Room" };

test("dock and built-in outputs get concise labels", () => {
    assert.equal(H.sinkLabel(laptop), "Laptop Speakers");
    assert.equal(H.sinkLabel(adam), "ADAM D3V");
    assert.equal(H.sinkLabel(studio), "Studio Display XDR");
    assert.equal(H.sinkLabel(hdmi), "HDMI / DisplayPort 2");
});

test("local outputs remain complete while network outputs are grouped separately", () => {
    const sinks = [airplay, studio, hdmi, adam, laptop];
    assert.deepEqual(H.localSinks(sinks, laptop), [laptop, adam, hdmi, studio]);
    assert.deepEqual(H.networkSinks(sinks, laptop), [airplay]);
    assert.equal(H.isNetworkSink({ name: "bluez_output.headphones" }), false);
});

test("the current output sorts first inside its own group", () => {
    assert.deepEqual(H.localSinks([laptop, adam, studio], studio), [studio, adam, laptop]);
    assert.deepEqual(H.networkSinks([
        airplay,
        { name: "raop_sink.Kitchen.local", description: "Kitchen" },
    ], airplay)[0], airplay);
});

test("Control Panel exposes audio detail and the picker has no arbitrary sink cap", () => {
    const control = fs.readFileSync(path.join(shellDir,
        "Popovers/ControlCenterPopover.qml"), "utf8");
    const picker = fs.readFileSync(path.join(shellDir,
        "Popovers/AudioPopover.qml"), "utf8");
    const audio = fs.readFileSync(path.join(shellDir, "Common/Audio.qml"), "utf8");

    assert.match(control, /Accessible\.name:\s*"Choose audio output"/);
    assert.match(control, /Popouts\.openPanel\("audio",\s*"right"\)/);
    assert.doesNotMatch(picker, /\.slice\(0,\s*6\)/);
    assert.doesNotMatch(picker, /parent\.width\s*-\s*84/);
    assert.match(picker, /inputRow\.width[\s\S]{0,180}inputMute\.width[\s\S]{0,80}inputValue\.width/);
    assert.match(picker, /AudioHelpers\.localSinks/);
    assert.match(picker, /Network \/ AirPlay/);
    assert.match(audio, /scripts\/audio-route/);
    assert.match(audio, /readonly property var sinkAudio:\s*sink && sink\.audio/);
    assert.match(audio, /readonly property var sourceAudio:\s*source && source\.audio/);
    assert.doesNotMatch(audio, /ready \?[^\n]*sink\.audio/,
        "a stale ready binding must not dereference a disappearing PipeWire group");
});

test("the routing helper moves named application streams, not filter internals", () => {
    const route = fs.readFileSync(path.join(shellDir, "scripts/audio-route"), "utf8");
    assert.match(route, /pactl set-default-sink "\$target"/);
    assert.match(route, /application\[\.\]name/);
    assert.match(route, /pactl move-sink-input "\$input" "\$target"/);
    assert.doesNotMatch(route, /pactl list sink-inputs short/);
});
