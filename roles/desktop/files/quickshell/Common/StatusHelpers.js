// Pure status helpers shared by the bar and its popovers: percentage
// normalization, battery charge semantics, media player selection and marks.
// Keep this file free of Qt APIs so the same logic stays testable under Node.
//
// The battery and media functions take the service object itself (or null)
// rather than pre-read values: QML captures property reads made inside an
// imported helper, so a binding on `chargeState(device)` still re-evaluates
// when the device's state changes.

// ---- percentages ---------------------------------------------------------

// UPower reports 0..100 while some devices report 0..1, and Networking's
// signalStrength arrives 0..1 in this backend, so a value at or below 1 is
// read as a fraction. A literal 1% therefore reads as 100% — the same trade
// the three call sites each made separately before this was shared.
function normalizePercent(value) {
    var number = Number(value);
    if (!isFinite(number))
        return NaN;
    return number <= 1 ? number * 100 : number;
}

// Charge level of a UPower device, unrounded. No device (or an unreadable
// reading) is 0, so consumers can bind this straight to a real property.
function batteryPercent(device) {
    if (!device)
        return 0;
    var pct = normalizePercent(device.percentage);
    return isFinite(pct) ? pct : 0;
}

// Wi-Fi signal as whole percent, with -1 for "no reading" so callers can
// tell an unknown strength from a genuine 0%.
function signalPercent(strength) {
    if (strength === undefined || strength === null)
        return -1;
    var pct = normalizePercent(strength);
    return isFinite(pct) ? Math.round(pct) : -1;
}

// ---- battery -------------------------------------------------------------

// org.freedesktop.UPower.Device's published State values, which Quickshell's
// UPowerDeviceState enum mirrors. Kept numeric so this module needs no Qt
// import; status-helpers.test.cjs pins them against the installed qmltypes.
var BATTERY_STATE = {
    Unknown: 0,
    Charging: 1,
    Discharging: 2,
    Empty: 3,
    FullyCharged: 4,
    PendingCharge: 5,
    PendingDischarge: 6
};

// The single definition of charge semantics for bar and popover. "full" is
// deliberately distinct from "charging" — the popover names the two states
// apart while the bar draws both as plugged in — and everything else,
// including having no battery at all, counts as running on battery.
function chargeState(device) {
    var state = device ? device.state : undefined;
    if (state === BATTERY_STATE.Charging || state === BATTERY_STATE.PendingCharge)
        return "charging";
    if (state === BATTERY_STATE.FullyCharged)
        return "full";
    return "discharging";
}

// Charging or already full: what the bar's glyph and accent color mean.
function isPluggedIn(device) {
    return chargeState(device) !== "discharging";
}

// ---- media ---------------------------------------------------------------

// Quickshell's MprisPlaybackState enum; pinned by the same qmltypes test as
// BATTERY_STATE above.
var PLAYBACK_STATE = {
    Stopped: 0,
    Playing: 1,
    Paused: 2
};

// Nerd Font marks: fa-spotify, fa-firefox, fa-chrome, fa-edge,
// fa-youtube-play, fa-video-camera, fa-music.
var PLAYER_GLYPH = {
    spotify: "",
    firefox: "",
    chromium: "",
    edge: "",
    youtube: "",
    video: "",
    generic: ""
};

// Which mark a player gets in the bar chip and in the popover's source
// switcher. Order matters: a browser playing a YouTube tab keeps its browser
// mark, and only players naming YouTube themselves take the YouTube one.
function playerGlyph(player) {
    if (!player)
        return PLAYER_GLYPH.generic;
    var id = (player.identity + " " + player.desktopEntry).toLowerCase();
    if (id.includes("spotify"))
        return PLAYER_GLYPH.spotify;
    if (id.includes("firefox") || id.includes("zen"))
        return PLAYER_GLYPH.firefox;
    if (id.includes("chromium") || id.includes("chrome") || id.includes("brave"))
        return PLAYER_GLYPH.chromium;
    if (id.includes("edge"))
        return PLAYER_GLYPH.edge;
    if (id.includes("youtube"))
        return PLAYER_GLYPH.youtube;
    if (id.includes("mpv") || id.includes("vlc") || id.includes("video"))
        return PLAYER_GLYPH.video;
    return PLAYER_GLYPH.generic;
}

// The player the shell speaks for: whatever is playing, else whatever is
// paused, else the first one known. The popover prepends its own manual
// source override and falls back to exactly this.
function activePlayer(players) {
    if (!players || players.length === 0)
        return null;
    var playing = players.find(function (player) {
        return player.isPlaying;
    });
    if (playing !== undefined)
        return playing;
    var paused = players.find(function (player) {
        return player.playbackState === PLAYBACK_STATE.Paused;
    });
    return paused !== undefined ? paused : players[0];
}

var exported = {
    normalizePercent: normalizePercent,
    batteryPercent: batteryPercent,
    signalPercent: signalPercent,
    BATTERY_STATE: BATTERY_STATE,
    chargeState: chargeState,
    isPluggedIn: isPluggedIn,
    PLAYBACK_STATE: PLAYBACK_STATE,
    PLAYER_GLYPH: PLAYER_GLYPH,
    playerGlyph: playerGlyph,
    activePlayer: activePlayer
};

if (typeof module !== "undefined" && module.exports)
    module.exports = exported;
