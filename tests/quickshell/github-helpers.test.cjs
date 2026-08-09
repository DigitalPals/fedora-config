const test = require("node:test");
const assert = require("node:assert/strict");
const { load } = require("./shell.cjs");

const H = load("GitHubHelpers.js");

// Everything reaching this file has already been through `gh api --jq`, so the
// parsers are checked against that projection rather than against GitHub's own
// documents. The projections themselves live in the same file, which is what
// keeps the two contracts from drifting.

const NOW = Date.parse("2026-08-09T12:00:00Z");

function iso(msAgo) {
    return new Date(NOW - msAgo).toISOString();
}

const MINUTE = 60000;
const HOUR = 3600000;
const DAY = 86400000;

test("repoSlug accepts every shape a repository reference is pasted in", () => {
    assert.equal(H.repoSlug("DigitalPals/fedora-config"), "DigitalPals/fedora-config");
    assert.equal(H.repoSlug("  hyprwm/Hyprland  "), "hyprwm/Hyprland");
    assert.equal(H.repoSlug("https://github.com/quickshell/quickshell"),
        "quickshell/quickshell");
    assert.equal(H.repoSlug("https://www.github.com/quickshell/quickshell/"),
        "quickshell/quickshell");
    assert.equal(H.repoSlug("github.com/cli/cli"), "cli/cli");
    assert.equal(H.repoSlug("git@github.com:cli/cli.git"), "cli/cli");
    assert.equal(H.repoSlug("https://github.com/cli/cli.git"), "cli/cli");
});

test("repoSlug refuses everything that is not one repository", () => {
    for (const bad of ["", "   ", "fedora-config", "a/b/c", "/leading",
                       "-owner/repo", "owner/", "/repo", "own er/repo",
                       "owner/re po", "owner/.", "owner/..", "owner/a\nb",
                       42, null, undefined, ["a/b"]])
        assert.equal(H.repoSlug(bad), "", `accepted ${JSON.stringify(bad)}`);
});

test("normalizeWatch dedupes case-insensitively, keeps order and caps", () => {
    assert.deepEqual(H.normalizeWatch([
        "hyprwm/Hyprland", "nope", "HYPRWM/hyprland",
        "https://github.com/cli/cli"
    ]), ["hyprwm/Hyprland", "cli/cli"]);
    assert.deepEqual(H.normalizeWatch(null), []);
    assert.deepEqual(H.normalizeWatch("a/b"), []);
    const many = Array.from({ length: 40 }, (_, i) => "o/r" + i);
    assert.equal(H.normalizeWatch(many).length, H.MAX_WATCH);
});

test("parseRepos reads the projection and drops rows that are not repos", () => {
    const rows = H.parseRepos(JSON.stringify([
        { n: "DigitalPals/fedora-config", p: "2026-08-08T17:26:44Z", pr: false,
            ar: false, b: "main" },
        { n: "not-a-repo", p: "2026-08-08T00:00:00Z" },
        { n: "hyprwm/Hyprland", p: null, pr: true, ar: true, b: "" }
    ]));
    assert.equal(rows.length, 2);
    assert.deepEqual(rows[0], {
        slug: "DigitalPals/fedora-config", owner: "DigitalPals", name: "fedora-config",
        pushedAt: "2026-08-08T17:26:44Z", isPrivate: false, archived: false,
        branch: "main", watched: false
    });
    // A repository with no push and no default branch still renders.
    assert.equal(rows[1].pushedAt, "");
    assert.equal(rows[1].branch, "main");
    assert.equal(rows[1].isPrivate, true);
    assert.equal(rows[1].archived, true);
});

test("an unreadable repository response is null, never an empty account", () => {
    // The distinction the Tailscale peer list already draws: a failed read
    // must not render as "you have no repositories".
    assert.equal(H.parseRepos(""), null);
    assert.equal(H.parseRepos("gh: not logged in"), null);
    assert.equal(H.parseRepos("{}"), null);
    assert.deepEqual(H.parseRepos("[]"), []);
    assert.equal(H.parseRepo("[]"), null);
    assert.equal(H.parseRepo('{"n": "x"}'), null);
    assert.equal(H.parseLogin("nonsense"), "");
    assert.equal(H.parseLogin('{"l": "DigitalPals"}'), "DigitalPals");
});

test("mergeRepos folds the watch list into one feed, newest push first", () => {
    const own = H.parseRepos(JSON.stringify([
        { n: "DigitalPals/fedora-config", p: iso(4 * MINUTE), b: "main" },
        { n: "digitalbrain/website", p: iso(3 * HOUR), b: "main" }
    ]));
    const extra = H.parseRepos(JSON.stringify([
        { n: "hyprwm/Hyprland", p: iso(HOUR), b: "main" }
    ]));
    const feed = H.mergeRepos(own, extra, ["hyprwm/Hyprland", "DigitalPals/fedora-config"]);
    assert.deepEqual(feed.map(r => r.slug),
        ["DigitalPals/fedora-config", "hyprwm/Hyprland", "digitalbrain/website"]);
    assert.deepEqual(feed.map(r => r.watched), [true, true, false]);
});

test("a watched repository the account can already see is listed once", () => {
    const own = H.parseRepos('[{"n": "a/b", "p": "2026-08-01T00:00:00Z"}]');
    const extra = H.parseRepos('[{"n": "A/B", "p": "2026-08-02T00:00:00Z"}]');
    const feed = H.mergeRepos(own, extra, ["a/b"]);
    assert.equal(feed.length, 1);
    assert.equal(feed[0].pushedAt, "2026-08-01T00:00:00Z", "your own row wins");
    assert.equal(feed[0].watched, true);
});

test("repositories with no push sort last, then alphabetically", () => {
    const rows = H.sortRepos(H.parseRepos(JSON.stringify([
        { n: "z/never", p: null },
        { n: "a/never", p: null },
        { n: "m/pushed", p: "2020-01-01T00:00:00Z" }
    ])));
    assert.deepEqual(rows.map(r => r.slug), ["m/pushed", "a/never", "z/never"]);
});

test("orgCount counts the owners that are not you", () => {
    const rows = H.parseRepos(JSON.stringify([
        { n: "DigitalPals/one", p: "" }, { n: "DigitalPals/two", p: "" },
        { n: "CybexHQ/three", p: "" }, { n: "digitalpals/four", p: "" }
    ]));
    assert.equal(H.orgCount(rows, "CybexHQ"), 1);
    assert.equal(H.orgCount(rows, "nobody"), 2);
    assert.equal(H.orgCount([], "x"), 0);
});

test("nothing is unread until a watermark exists", () => {
    const rows = H.parseRepos(JSON.stringify([
        { n: "a/new", p: "2026-08-09T10:00:00Z" },
        { n: "a/old", p: "2026-08-01T10:00:00Z" },
        { n: "a/empty", p: null }
    ]));
    // A fresh install would otherwise open with every repository lit.
    assert.deepEqual(H.unreadRepos(rows, ""), []);
    assert.deepEqual(H.unreadRepos(rows, undefined), []);
    assert.deepEqual(H.unreadRepos(rows, "2026-08-05T00:00:00Z").map(r => r.slug),
        ["a/new"]);
});

test("parseCommits splits the subject from the body and drops git trailers", () => {
    const rows = H.parseCommits(JSON.stringify([
        {
            s: "a41c9e2f0000000000000000000000000000abcd",
            m: "popouts: seat a reused slot on its own tab\n\nA latched panel swept"
                + " across the bar while it grew.\n\nCo-Authored-By: Someone <x@y>\n"
                + "Signed-off-by: Someone Else <a@b>\n",
            a: "john",
            d: "2026-08-09T11:36:00Z",
            u: "https://github.com/o/r/commit/a41c9e2"
        },
        { m: "no sha here" }
    ]));
    assert.equal(rows.length, 1);
    assert.equal(rows[0].short, "a41c9e2");
    assert.equal(rows[0].subject, "popouts: seat a reused slot on its own tab");
    assert.equal(rows[0].body, "A latched panel swept across the bar while it grew.");
    assert.equal(rows[0].author, "john");
    assert.equal(H.parseCommits("nonsense"), null);
});

test("a commit with no author falls back rather than rendering nothing", () => {
    const rows = H.parseCommits('[{"s": "abcdef1234", "m": "x", "a": null, "d": null}]');
    assert.equal(rows[0].author, "unknown");
    assert.equal(rows[0].date, "");
    assert.equal(rows[0].url, "");
});

test("subject collapses whitespace and messageBody survives odd messages", () => {
    assert.equal(H.subject("  fix:   two   spaces  "), "fix: two spaces");
    assert.equal(H.subject(""), "");
    assert.equal(H.subject(null), "");
    assert.equal(H.messageBody("subject only"), "");
    assert.equal(H.messageBody("s\n\n\n\n\nbody"), "body");
    assert.equal(H.messageBody("s\n\nSigned-off-by: a <b>"), "",
        "a message that is only trailers has no body");
});

test("messageBody rejoins the 72-column hard wrap git commits carry", () => {
    // Without this, a 376px column re-wraps an already-wrapped paragraph into
    // alternating long and half-empty lines.
    assert.equal(
        H.messageBody("subject\n\nBoth fell through to Theme.hoverFill rather\n"
            + "than \"transparent\", so they carried a permanent\npill."),
        "Both fell through to Theme.hoverFill rather than \"transparent\", "
            + "so they carried a permanent pill.");
    assert.equal(H.messageBody("s\n\none\ntwo\n\nthree\nfour"), "one two\n\nthree four",
        "paragraph breaks survive");
});

test("messageBody keeps the breaks that carry structure", () => {
    assert.equal(H.messageBody("s\n\nWhat changed:\n- one thing\n- another\n- third"),
        "What changed:\n- one thing\n- another\n- third");
    assert.equal(H.messageBody("s\n\nRan:\n    make test\n    make lint"),
        "Ran:\n    make test\n    make lint");
    assert.equal(H.messageBody("s\n\nSteps:\n1. first\n2. second"),
        "Steps:\n1. first\n2. second");
});

test("parseCommitStats defaults missing counts to zero", () => {
    assert.deepEqual(H.parseCommitStats('{"s": "abc", "f": 3, "add": 32, "del": 4}'),
        { sha: "abc", files: 3, additions: 32, deletions: 4 });
    assert.deepEqual(H.parseCommitStats('{"s": "abc", "f": null, "add": null, "del": null}'),
        { sha: "abc", files: 0, additions: 0, deletions: 0 });
    assert.equal(H.parseCommitStats("[]"), null);
    assert.equal(H.parseCommitStats('{"f": 1}'), null);
});

test("newCommits counts only what landed after the watermark", () => {
    const rows = H.parseCommits(JSON.stringify([
        { s: "aaaaaaa1", m: "new", d: "2026-08-09T11:00:00Z" },
        { s: "bbbbbbb2", m: "new", d: "2026-08-09T10:00:00Z" },
        { s: "ccccccc3", m: "old", d: "2026-08-01T10:00:00Z" }
    ]));
    assert.equal(H.newCommits(rows, "2026-08-05T00:00:00Z"), 2);
    assert.equal(H.newCommits(rows, ""), 0);
    assert.equal(H.newCommits([], "2026-08-05T00:00:00Z"), 0);
});

test("relTime stays as short as the age allows", () => {
    assert.equal(H.relTime(iso(10000), NOW), "now");
    assert.equal(H.relTime(iso(4 * MINUTE), NOW), "4m");
    assert.equal(H.relTime(iso(38 * MINUTE), NOW), "38m");
    assert.equal(H.relTime(iso(HOUR), NOW), "1h");
    assert.equal(H.relTime(iso(9 * HOUR), NOW), "9h");
    assert.equal(H.relTime(iso(2 * DAY), NOW), "2d");
    assert.equal(H.relTime(iso(60 * DAY), NOW), "2mo");
    assert.equal(H.relTime(iso(800 * DAY), NOW), "2y");
    assert.equal(H.relTime("", NOW), "");
    assert.equal(H.relTime("not a date", NOW), "");
    assert.equal(H.relTime(iso(-HOUR), NOW), "now", "a clock skewed forward reads as now");
});

test("agoLabel becomes a date once the count stops meaning anything", () => {
    assert.equal(H.agoLabel(NOW - 10000, NOW), "just now");
    assert.equal(H.agoLabel(NOW - 24 * MINUTE, NOW), "24m ago");
    assert.equal(H.agoLabel(NOW - 2 * HOUR, NOW), "2h ago");
    assert.equal(H.agoLabel(NOW - 30 * HOUR, NOW), "yesterday");
    assert.equal(H.agoLabel(NOW - 3 * DAY, NOW), "3d ago");
    assert.equal(H.agoLabel(NOW - 40 * DAY, NOW), "30 Jun");
    assert.equal(H.agoLabel(0, NOW), "", "never checked says nothing");
    assert.equal(H.agoLabelIso("2026-08-09T11:36:00Z", NOW), "24m ago");
    assert.equal(H.agoLabelIso("", NOW), "");
});

test("calendarDaysAgo counts days, not 24-hour spans", () => {
    // Local midnight, so a 23:50 commit and a 00:10 one land on the days a
    // reader would put them on rather than 20 minutes apart in one bucket.
    const lateYesterday = new Date(NOW);
    lateYesterday.setDate(lateYesterday.getDate() - 1);
    lateYesterday.setHours(23, 50, 0, 0);
    const earlyToday = new Date(NOW);
    earlyToday.setHours(0, 10, 0, 0);

    assert.equal(H.calendarDaysAgo(earlyToday.toISOString(), NOW), 0);
    assert.equal(H.calendarDaysAgo(lateYesterday.toISOString(), NOW), 1,
        "ten hours apart, but a different day");
    assert.equal(H.calendarDaysAgo("", NOW), -1);
    assert.equal(H.calendarDaysAgo("not a date", NOW), -1);
    assert.equal(H.calendarDaysAgo(iso(-2 * DAY), NOW), 0,
        "a clock skewed forward never counts negative days");
});

test("recencyBucket tightens towards now and never stops banding", () => {
    const at = days => {
        const d = new Date(NOW);
        d.setDate(d.getDate() - days);
        d.setHours(12, 0, 0, 0);
        return d.toISOString();
    };
    // Each of the last seven days on its own.
    assert.equal(H.recencyBucket(at(0), NOW), "d0");
    assert.equal(H.recencyBucket(at(1), NOW), "d1");
    assert.equal(H.recencyBucket(at(6), NOW), "d6");
    // Then a week at a time for a month.
    assert.equal(H.recencyBucket(at(7), NOW), "w1");
    assert.equal(H.recencyBucket(at(13), NOW), "w1");
    assert.equal(H.recencyBucket(at(14), NOW), "w2");
    assert.equal(H.recencyBucket(at(34), NOW), "w4");
    // Then a month at a time, with no upper bound.
    assert.equal(H.recencyBucket(at(35), NOW), "m1");
    assert.equal(H.recencyBucket(at(400), NOW), "m13");
    assert.equal(H.recencyBucket("", NOW), "");
});

test("recencyBucket keys are distinct as the age grows", () => {
    // A band that repeated an earlier key would rule a second line under a
    // group it had already closed.
    const at = days => {
        const d = new Date(NOW);
        d.setDate(d.getDate() - days);
        d.setHours(12, 0, 0, 0);
        return d.toISOString();
    };
    const seen = new Map();
    let previous = null;
    for (let days = 0; days <= 800; days++) {
        const key = H.recencyBucket(at(days), NOW);
        if (key !== previous) {
            assert.ok(!seen.has(key),
                `bucket ${key} came back at ${days}d, first seen at ${seen.get(key)}d`);
            seen.set(key, days);
            previous = key;
        }
    }
    assert.ok(seen.size > 20, `only ${seen.size} bands across two years`);
});

test("a row's label never contradicts the divider above it", () => {
    // The bug this pins: agoLabel floored elapsed hours while the bands count
    // calendar days, so a commit at Thu 07:56 and one at Wed 23:48 both read
    // "3d ago" with a divider ruled between them — the line said the day had
    // changed and both labels said it had not.
    const at = (days, hour) => {
        const d = new Date(NOW);
        d.setDate(d.getDate() - days);
        d.setHours(hour, 0, 0, 0);
        return d;
    };
    const label = d => H.agoLabel(d.getTime(), NOW);
    const bucket = d => H.recencyBucket(d.toISOString(), NOW);

    // Across a day boundary: different band, and different words for it.
    const lateThatNight = at(4, 23);
    const earlyNextDay = at(3, 0);
    assert.notEqual(bucket(lateThatNight), bucket(earlyNextDay));
    assert.notEqual(label(lateThatNight), label(earlyNextDay),
        "an hour apart, but the divider says they are different days");
    assert.equal(label(earlyNextDay), "3d ago");
    assert.equal(label(lateThatNight), "4d ago");

    // Inside a day band, every row says the same thing, so no reader looks
    // for a divider that is not there.
    for (const days of [1, 2, 3, 4, 5, 6]) {
        const labels = [0, 6, 12, 18, 23].map(hour => label(at(days, hour)));
        assert.equal(new Set(labels).size, 1,
            `day ${days} renders as ${[...new Set(labels)].join(" / ")}`);
        const buckets = [0, 6, 12, 18, 23].map(hour => bucket(at(days, hour)));
        assert.equal(new Set(buckets).size, 1);
    }
    // Today is the exception, and deliberately so: it is one band, but the
    // hours inside it are the useful part.
    assert.equal(H.recencyBucket(at(0, 2).toISOString(), NOW),
        H.recencyBucket(at(0, 13).toISOString(), NOW));
});

test("bucketBreak marks exactly the rows that open a band", () => {
    const at = days => {
        const d = new Date(NOW);
        d.setDate(d.getDate() - days);
        d.setHours(12, 0, 0, 0);
        return d.toISOString();
    };
    assert.equal(H.bucketBreak(at(0), at(0), NOW), false, "same day, no line");
    assert.equal(H.bucketBreak(at(1), at(0), NOW), true, "today → yesterday");
    assert.equal(H.bucketBreak(at(2), at(1), NOW), true, "yesterday → 2 days");
    assert.equal(H.bucketBreak(at(8), at(7), NOW), false, "both inside last week");
    assert.equal(H.bucketBreak(at(7), at(6), NOW), true, "6 days → last week");
    assert.equal(H.bucketBreak("", "", NOW), false,
        "two repositories with no push are one group, not two");
});

test("pushToast says nothing when there is nothing to say", () => {
    assert.deepEqual(H.pushToast("hyprwm/Hyprland", 2, "renderer: clamp blur passes"), {
        summary: "hyprwm/Hyprland — 2 new commits",
        body: "renderer: clamp blur passes"
    });
    assert.equal(H.pushToast("a/b", 1, "x").summary, "a/b — 1 new commit");
    assert.equal(H.pushToast("a/b", 0, "x"), null);
    assert.equal(H.pushToast("", 3, "x"), null);
    // A full page cannot tell 20 from 200, so it must not claim 20.
    assert.equal(H.pushToast("a/b", H.MAX_COMMITS, "x").summary,
        "a/b — " + H.MAX_COMMITS + "+ new commits");
});

test("the queries this file parses are the queries the singleton asks for", () => {
    // Both halves of the contract live here, so a projection cannot be widened
    // in one place and read in another.
    for (const key of ["login", "repos", "repo", "commits", "commit"]) {
        const query = H.GITHUB_QUERIES[key];
        assert.ok(query && query.path.startsWith("/"), `${key} needs an API path`);
        assert.ok(query.jq.length > 0, `${key} needs a projection`);
    }
    assert.match(H.GITHUB_QUERIES.repos.path, /sort=pushed&direction=desc/);
    assert.match(H.GITHUB_QUERIES.commits.path, /per_page=20/);
    // The two paths the singleton substitutes into, and nothing else.
    assert.ok(H.GITHUB_QUERIES.repo.path.includes("{repo}"));
    assert.ok(H.GITHUB_QUERIES.commit.path.includes("{repo}")
        && H.GITHUB_QUERIES.commit.path.includes("{sha}"));
});
