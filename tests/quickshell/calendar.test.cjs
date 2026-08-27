const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const { shellDir, load } = require("./shell.cjs");

const Calendar = load("CalendarHelpers.js");

function read(relative) {
    return fs.readFileSync(path.join(shellDir, relative), "utf8");
}

function event(summary, startMs, endMs, extra = {}) {
    return {
        id: summary,
        uid: summary,
        calendarUid: "work",
        calendar: "Work",
        color: "#123456",
        summary,
        startMs,
        endMs,
        ...extra
    };
}

test("calendar payloads are bounded, sorted and deduplicated", () => {
    const payload = Calendar.normalizePayload({
        available: true,
        googleAccounts: 1.8,
        googleCalendarAccounts: 1,
        calendars: [
            { uid: "work", name: "Work", color: "#abc123", isGoogle: true },
            null
        ],
        events: [
            event("Later", 3000, 4000, { color: "not-a-color" }),
            event("First", 1000, 2000),
            event("First", 1000, 2000),
            event("Broken", 5000, 4000)
        ],
        sourceErrors: [{ calendar: "Private", message: "offline" }]
    });

    assert.equal(payload.googleAccounts, 1);
    assert.equal(payload.googleCalendarAccounts, 1);
    assert.deepEqual(payload.events.map(item => item.summary), ["First", "Later"]);
    assert.equal(payload.events[1].color, Calendar.DEFAULT_COLOR);
    assert.deepEqual(payload.calendars, [
        { uid: "work", name: "Work", color: "#abc123", isGoogle: true }
    ]);
    assert.deepEqual(payload.sourceErrors,
        [{ calendar: "Private", message: "offline" }]);
    assert.equal(Calendar.normalizePayload([]), null);
});

test("event windows use half-open boundaries", () => {
    const midnight = Date.UTC(2026, 7, 28);
    const next = midnight + Calendar.DAY_MS;
    const previousAllDay = event("Previous", midnight - Calendar.DAY_MS, midnight,
        { allDay: true });
    const currentAllDay = event("Current", midnight, next, { allDay: true });
    const crossing = event("Crossing", midnight - 1000, midnight + 1000);

    assert.equal(Calendar.overlaps(previousAllDay, midnight, next), false);
    assert.equal(Calendar.overlaps(currentAllDay, midnight, next), true);
    assert.equal(Calendar.overlaps(crossing, midnight, next), true);
    assert.deepEqual(
        Calendar.eventsInRange([previousAllDay, currentAllDay, crossing], midnight, next, 1)
            .map(item => item.summary),
        ["Current"]
    );
});

test("upcoming events retain ongoing items and obey the configured limit", () => {
    const now = 10_000;
    const rows = Calendar.upcoming([
        event("Past", 1000, 9000),
        event("Ongoing", 5000, 20_000),
        event("Soon", 12_000, 13_000),
        event("Outside", 50_000, 60_000)
    ], now, 40_000, 2);
    assert.deepEqual(rows.map(item => item.summary), ["Ongoing", "Soon"]);
});

test("the calendar bridge delegates credentials and recurrence to GNOME", () => {
    const service = read("Common/Calendar.qml");
    const helper = read("scripts/calendar-events.py");
    const popover = read("Popovers/CalendarPopover.qml");
    const settings = read("Common/SettingsHelpers.js");
    const tasks = fs.readFileSync(path.resolve(shellDir, "../../tasks/main.yml"), "utf8");

    assert.match(service,
        /"env", "XDG_CURRENT_DESKTOP=GNOME",\s*"gnome-control-center", "online-accounts"/);
    assert.match(service, /scripts\/calendar-events\.py/);
    assert.match(service, /gnome-calendar", "--date"/);
    assert.match(helper, /SourceRegistry\.new_sync/);
    assert.match(helper, /generate_instances_sync/);
    assert.match(helper, /get_selected\(\)/);
    assert.match(helper, /Goa\.Client\.new_sync/);
    assert.doesNotMatch(helper, /get_oauth2_access_token|password|secret\.get/i,
        "the bridge must never retrieve credentials into the shell process");
    assert.match(popover, /CalendarHelpers\.upcoming/);
    assert.match(popover, /Connect Google Calendar/);
    assert.match(popover, /Calendar\.manageAccounts\(\)/);
    assert.match(settings,
        /showEvents: true, daysAhead: 14, pollMins: 15/);
    for (const packageName of ["gnome-online-accounts", "gnome-control-center",
        "gnome-calendar", "evolution-data-server", "python3-gobject"])
        assert.match(tasks, new RegExp(`- ${packageName.replaceAll("-", "\\-")}`));

    const syntax = spawnSync("python3", ["-c",
        "import ast,sys; ast.parse(sys.stdin.read())"], {
        input: helper,
        encoding: "utf8"
    });
    assert.equal(syntax.status, 0, syntax.stderr);
});

test("invalid helper ranges still return a machine-readable envelope", () => {
    const script = path.join(shellDir, "scripts", "calendar-events.py");
    const run = spawnSync("python3", [script, "20", "10"], { encoding: "utf8" });
    assert.equal(run.status, 0, run.stderr);
    const payload = JSON.parse(run.stdout);
    assert.equal(payload.available, false);
    assert.match(payload.error, /window is not valid/);
    assert.deepEqual(payload.events, []);
});
