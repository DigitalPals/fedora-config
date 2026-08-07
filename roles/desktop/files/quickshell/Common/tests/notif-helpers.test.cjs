const test = require("node:test");
const assert = require("node:assert/strict");

const H = require("../NotifHelpers.js");

function chromeNotification(overrides = {}) {
    return {
        appName: "Google Chrome",
        desktopEntry: "google-chrome",
        appIcon: "google-chrome",
        image: "/tmp/site-icon.png",
        summary: "Alice",
        body: "Hello",
        hints: {},
        ...overrides,
    };
}

test("browser detection accepts browser names and desktop entries only", () => {
    assert.equal(H.isBrowser("Google Chrome", ""), true);
    assert.equal(H.isBrowser("Web app", "chromium-browser"), true);
    assert.equal(H.isBrowser("Signal", "signal-desktop"), false);
});

test("WhatsApp resolves from the advertised origin hint", () => {
    const result = H.derivePresentation(chromeNotification({
        hints: { "x-kde-origin-name": "https://web.whatsapp.com/" },
    }));
    assert.equal(result.displayAppName, "WhatsApp");
    assert.equal(result.webOrigin, "web.whatsapp.com");
    assert.equal(result.displayBody, "Hello");
    assert.equal(result.brandIcon, "whatsapp");
});

test("WhatsApp resolves from Chromium's legacy body prefix", () => {
    const result = H.derivePresentation(chromeNotification({
        body: '<a href="https://web.whatsapp.com/">web.whatsapp.com</a>\n\nHello &amp; welcome',
    }));
    assert.equal(result.displayAppName, "WhatsApp");
    assert.equal(result.webOrigin, "web.whatsapp.com");
    assert.equal(result.displayBody, "Hello & welcome");
});

test("generic browser origins use a normalized hostname", () => {
    const result = H.derivePresentation(chromeNotification({
        hints: { "x-kde-origin-name": "HTTPS://News.Example.COM:443/story?id=1" },
    }));
    assert.equal(result.displayAppName, "news.example.com");
    assert.equal(result.webOrigin, "news.example.com");
    assert.equal(result.brandIcon, "");
});

test("native notifications keep their application identity", () => {
    const result = H.derivePresentation({
        appName: "Signal", desktopEntry: "signal-desktop", summary: "Alice",
        body: "Hello", hints: { "x-kde-origin-name": "Personal" },
    });
    assert.equal(result.browser, false);
    assert.equal(result.displayAppName, "Signal");
    assert.equal(result.webOrigin, "");
    assert.equal(result.displayBody, "Hello");
});

test("markup cleanup preserves paragraphs and decodes common entities", () => {
    assert.equal(H.stripMarkup("<b>Hello</b><br>one&nbsp;&amp;&nbsp;two<p>next</p>"),
        "Hello\none & two\nnext");
});

test("body text duplicated by the summary is suppressed", () => {
    const result = H.derivePresentation({
        appName: "Calendar", summary: "Stand-up in 10 minutes",
        body: "<b>Stand-up in 10 minutes</b>",
    });
    assert.equal(result.displaySummary, "Stand-up in 10 minutes");
    assert.equal(result.displayBody, "");
});

test("icon precedence favors brands and never falls back to Chrome for web sources", () => {
    assert.deepEqual(H.iconPreference({
        brandIcon: "whatsapp", webOrigin: "web.whatsapp.com",
        appIcon: "google-chrome", desktopEntry: "google-chrome", image: "avatar.png",
    }), [
        { kind: "brand", value: "whatsapp" },
        { kind: "image", value: "avatar.png" },
        { kind: "web-fallback", value: "" },
    ]);
    assert.deepEqual(H.iconPreference({
        appIcon: "signal", desktopEntry: "signal-desktop", image: "avatar.png",
    }).map((choice) => choice.kind),
    ["app-icon", "desktop-entry", "image", "generic-fallback"]);
});

test("default and close actions do not become secondary pills", () => {
    const actions = [
        { identifier: "default", text: "Open" },
        { identifier: "reply", text: "Reply" },
        { identifier: "close", text: "Close" },
        { identifier: "mute", text: "Mute" },
        { identifier: "later", text: "Later" },
    ];
    assert.equal(H.defaultAction(actions), actions[0]);
    assert.deepEqual(H.secondaryActions(actions).map((action) => action.identifier),
        ["reply", "mute"]);
});

test("adaptive timing uses 8 seconds through 80 characters and caps at 12", () => {
    assert.equal(H.timeoutMs(0, -1), 8000);
    assert.equal(H.timeoutMs(80, 0), 8000);
    assert.equal(H.timeoutMs(81, 0), 9000);
    assert.equal(H.timeoutMs(120, 0), 9000);
    assert.equal(H.timeoutMs(121, 0), 10000);
    assert.equal(H.timeoutMs(240, 0), 12000);
    assert.equal(H.timeoutMs(1000, 0), 12000);
});

test("requested application timeouts are clamped into the same range", () => {
    assert.equal(H.timeoutMs(20, 2), 8000);
    assert.equal(H.timeoutMs(20, 9.4), 9400);
    assert.equal(H.timeoutMs(20, 30), 12000);
});

test("the configured duration shifts the adaptive window and the clamp", () => {
    assert.equal(H.timeoutMs(0, -1, 4000), 4000);
    assert.equal(H.timeoutMs(81, 0, 4000), 5000);
    assert.equal(H.timeoutMs(1000, 0, 4000), 8000);
    assert.equal(H.timeoutMs(20, 2, 4000), 4000);
    assert.equal(H.timeoutMs(20, 30, 20000), 24000);
    assert.equal(H.timeoutMs(0, -1, 20000), 20000);
    // Invalid bases fall back to the historical 8–12 second window.
    assert.equal(H.timeoutMs(0, -1, NaN), 8000);
    assert.equal(H.timeoutMs(240, 0, undefined), 12000);
});
