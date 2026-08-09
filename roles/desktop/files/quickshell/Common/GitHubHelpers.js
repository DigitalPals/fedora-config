// Pure helpers for the GitHub bar module: the watch-list grammar, the shapes
// `gh api` is asked to project, and the two time labels the popover renders.
// Keep this file free of Qt APIs so the same logic stays testable under Node.
//
// Every read goes through `gh api --jq`, so what arrives here is already a
// projection with one-letter keys rather than GitHub's own document. That is
// deliberate: the unprojected /user/repos page is ~1.5 MB of JSON for the same
// six fields, and re-parsing it every poll is the whole cost of the module.
// The projections live in GITHUB_QUERIES below so the contract this file
// parses and the contract the singleton requests cannot drift apart.

// A watch list long enough to be useful and short enough that one poll cannot
// turn into a burst of API calls — each entry costs its own `gh api` run.
var MAX_WATCH = 20;
// Commits fetched per repo. The popover shows the newest handful; the rest is
// headroom for counting what is new since you last looked.
var MAX_COMMITS = 20;

// Option bounds, shared by the settings validators and the settings rows so a
// slider and its stored value can never disagree about what is in range.
var REPOS_MIN = 3;
var REPOS_MAX = 15;
var POLL_MIN = 1;
var POLL_MAX = 30;

var BADGE_MODES = ["dot", "count", "off"];

// The `gh api` path and --jq projection for each read. `{repo}` and `{sha}`
// are substituted by the caller; nothing else in a path is interpolated.
var GITHUB_QUERIES = {
    login: {
        path: "/user",
        jq: "{l: .login}"
    },
    repos: {
        path: "/user/repos?sort=pushed&direction=desc&per_page=100"
            + "&affiliation=owner,collaborator,organization_member",
        jq: "[.[] | {n: .full_name, p: .pushed_at, pr: .private,"
            + " ar: .archived, b: .default_branch}]"
    },
    repo: {
        path: "/repos/{repo}",
        jq: "{n: .full_name, p: .pushed_at, pr: .private,"
            + " ar: .archived, b: .default_branch}"
    },
    commits: {
        path: "/repos/{repo}/commits?per_page=" + MAX_COMMITS,
        jq: "[.[] | {s: .sha, m: .commit.message,"
            + " a: (.author.login // .commit.author.name),"
            + " d: (.commit.author.date // .commit.committer.date), u: .html_url}]"
    },
    // Only the counts: the commit's own URL already came back with the list.
    commit: {
        path: "/repos/{repo}/commits/{sha}",
        jq: "{s: .sha, f: (.files | length), add: .stats.additions,"
            + " del: .stats.deletions}"
    }
};

// A repository reference the shell will accept from the settings field. The
// whole point is that pasting a browser URL works, because that is what is on
// the clipboard when someone decides to watch a repo.
var OWNER_RE = /^[A-Za-z0-9][A-Za-z0-9-]*$/;
var NAME_RE = /^[A-Za-z0-9._-]+$/;

function repoSlug(value) {
    if (typeof value !== "string")
        return "";
    var text = value.trim();
    if (text === "")
        return "";
    text = text.replace(/^[a-z]+:\/\//i, "")
        .replace(/^git@github\.com:/i, "")
        .replace(/^(www\.)?github\.com\//i, "")
        .replace(/\.git$/i, "")
        .replace(/^\/+/, "")
        .replace(/\/+$/, "");
    var parts = text.split("/");
    if (parts.length !== 2)
        return "";
    if (!OWNER_RE.test(parts[0]) || !NAME_RE.test(parts[1]))
        return "";
    // "." and ".." are legal against NAME_RE and are not repositories.
    if (parts[1] === "." || parts[1] === "..")
        return "";
    return parts[0] + "/" + parts[1];
}

// Known-good slugs only, first spelling of a duplicate wins, capped. Case is
// preserved for display but compared case-insensitively, because GitHub
// resolves owner/name that way and a list holding both spellings would poll
// the same repository twice.
function normalizeWatch(list) {
    var out = [];
    var seen = {};
    if (!Array.isArray(list))
        return out;
    for (var i = 0; i < list.length && out.length < MAX_WATCH; i++) {
        var slug = repoSlug(list[i]);
        if (slug === "")
            continue;
        var key = slug.toLowerCase();
        if (seen[key])
            continue;
        seen[key] = true;
        out.push(slug);
    }
    return out;
}

function parseJson(text) {
    if (typeof text !== "string" || text.trim() === "")
        return undefined;
    try {
        return JSON.parse(text);
    } catch (e) {
        return undefined;
    }
}

// One projected repository. Null for anything that is not that shape, so an
// unreadable response can never pass for a repository with no pushes.
function repoRow(raw) {
    if (!raw || typeof raw !== "object" || Array.isArray(raw))
        return null;
    var slug = repoSlug(raw.n);
    if (slug === "")
        return null;
    var parts = slug.split("/");
    return {
        slug: slug,
        owner: parts[0],
        name: parts[1],
        // An empty repository has never been pushed to; "" sorts it last
        // rather than throwing off every comparison against a real stamp.
        pushedAt: typeof raw.p === "string" ? raw.p : "",
        isPrivate: !!raw.pr,
        archived: !!raw.ar,
        branch: typeof raw.b === "string" && raw.b !== "" ? raw.b : "main",
        watched: false
    };
}

function parseRepos(text) {
    var body = parseJson(text);
    if (!Array.isArray(body))
        return null;
    var out = [];
    for (var i = 0; i < body.length; i++) {
        var row = repoRow(body[i]);
        if (row !== null)
            out.push(row);
    }
    return out;
}

function parseRepo(text) {
    return repoRow(parseJson(text));
}

function parseLogin(text) {
    var body = parseJson(text);
    return body && typeof body.l === "string" ? body.l : "";
}

// Newest push first. Repositories that have never been pushed to sort last
// and then alphabetically, so the tail of a long list stays stable between
// polls instead of shuffling.
function sortRepos(rows) {
    return rows.slice().sort(function (a, b) {
        if (a.pushedAt !== b.pushedAt)
            return a.pushedAt < b.pushedAt ? 1 : -1;
        return a.slug.localeCompare(b.slug);
    });
}

// Your repositories plus the watched ones, as a single feed. A watched repo
// you already have access to is not listed twice — it keeps its own row and
// gains the WATCHING mark.
function mergeRepos(own, extra, watch) {
    var watched = {};
    normalizeWatch(watch).forEach(function (slug) {
        watched[slug.toLowerCase()] = true;
    });
    var byKey = {};
    var order = [];
    function take(row) {
        if (row === null)
            return;
        var key = row.slug.toLowerCase();
        if (byKey[key] !== undefined)
            return;
        byKey[key] = {
            slug: row.slug,
            owner: row.owner,
            name: row.name,
            pushedAt: row.pushedAt,
            isPrivate: row.isPrivate,
            archived: row.archived,
            branch: row.branch,
            watched: !!watched[key]
        };
        order.push(key);
    }
    (Array.isArray(own) ? own : []).forEach(take);
    (Array.isArray(extra) ? extra : []).forEach(take);
    return sortRepos(order.map(function (key) { return byKey[key]; }));
}

// Distinct owners in your own repositories that are not you: the "across N
// orgs" the settings account card reports.
function orgCount(rows, login) {
    var seen = {};
    var me = typeof login === "string" ? login.toLowerCase() : "";
    (Array.isArray(rows) ? rows : []).forEach(function (row) {
        var owner = row.owner.toLowerCase();
        if (owner !== me)
            seen[owner] = true;
    });
    return Object.keys(seen).length;
}

// Everything pushed since the watermark. ISO-8601 UTC stamps compare
// correctly as strings, which is why they are never turned into Dates here.
// An empty watermark means "nothing has been seen yet" and reads as nothing
// unread — the singleton sets the watermark on its first poll instead, so a
// fresh install does not open with every repository lit.
function unreadRepos(rows, since) {
    if (typeof since !== "string" || since === "")
        return [];
    return (Array.isArray(rows) ? rows : []).filter(function (row) {
        return row.pushedAt !== "" && row.pushedAt > since;
    });
}

function commitRow(raw) {
    if (!raw || typeof raw !== "object" || Array.isArray(raw))
        return null;
    if (typeof raw.s !== "string" || raw.s === "")
        return null;
    var message = typeof raw.m === "string" ? raw.m : "";
    return {
        sha: raw.s,
        short: raw.s.slice(0, 7),
        subject: subject(message),
        body: messageBody(message),
        author: typeof raw.a === "string" && raw.a !== "" ? raw.a : "unknown",
        date: typeof raw.d === "string" ? raw.d : "",
        url: typeof raw.u === "string" ? raw.u : ""
    };
}

function parseCommits(text) {
    var body = parseJson(text);
    if (!Array.isArray(body))
        return null;
    var out = [];
    for (var i = 0; i < body.length; i++) {
        var row = commitRow(body[i]);
        if (row !== null)
            out.push(row);
    }
    return out;
}

// The per-commit statistics the expanded row shows. Absent counts read as
// zero rather than as a missing line, because a commit that touched nothing
// is a real thing GitHub reports.
function parseCommitStats(text) {
    var body = parseJson(text);
    if (!body || typeof body !== "object" || Array.isArray(body))
        return null;
    if (typeof body.s !== "string" || body.s === "")
        return null;
    function count(value) {
        return typeof value === "number" && isFinite(value) && value > 0
            ? Math.floor(value) : 0;
    }
    return {
        sha: body.s,
        files: count(body.f),
        additions: count(body.add),
        deletions: count(body.del)
    };
}

function newCommits(commits, since) {
    if (typeof since !== "string" || since === "")
        return 0;
    return (Array.isArray(commits) ? commits : []).filter(function (row) {
        return row.date !== "" && row.date > since;
    }).length;
}

// A commit's first line, whitespace collapsed so a wrapped subject does not
// render with the newline still in it.
function subject(message) {
    if (typeof message !== "string")
        return "";
    var first = message.split("\n")[0];
    return first.replace(/\s+/g, " ").trim();
}

// Everything after the subject, with git trailers dropped. The trailers are
// the machine-readable footer (Co-Authored-By, Signed-off-by, Reviewed-by) and
// carry nothing a person reading a bar popover wants; this repository's own
// commits all end with one.
var TRAILER = /^[A-Za-z][A-Za-z-]*:\s/;
// A line that carries its own structure and must keep its break: a list item,
// or anything indented (quoted output, code).
var STRUCTURAL = /^(\s|[-*•]\s|\d+[.)]\s)/;

// Commit bodies are hard-wrapped at about 72 columns. Re-wrapping that inside
// a 376px column turns every paragraph into alternating long and half-empty
// lines — verified against this repository's own commits. Rejoining each
// paragraph lets the popover do the wrapping once, which is the only place
// that knows how wide it is.
function reflow(text) {
    return text.split(/\n{2,}/).map(function (paragraph) {
        var lines = paragraph.split("\n");
        var out = lines[0];
        for (var i = 1; i < lines.length; i++) {
            if (STRUCTURAL.test(lines[i]) || STRUCTURAL.test(lines[i - 1]))
                out += "\n" + lines[i];
            else
                out += " " + lines[i].trim();
        }
        return out;
    }).join("\n\n");
}

function messageBody(message) {
    if (typeof message !== "string")
        return "";
    var lines = message.split("\n").slice(1);
    function dropTrailingBlanks() {
        while (lines.length > 0 && lines[lines.length - 1].trim() === "")
            lines.pop();
    }
    dropTrailingBlanks();
    // git's own definition of the trailer block: the run of "Key: value" lines
    // at the very end, set off from the body by a blank line. Anything less
    // strict eats a body that happens to end in "Note: …".
    var start = lines.length;
    while (start > 0 && TRAILER.test(lines[start - 1]))
        start--;
    if (start < lines.length && (start === 0 || lines[start - 1].trim() === "")) {
        lines = lines.slice(0, start);
        dropTrailingBlanks();
    }
    return reflow(lines.join("\n").replace(/\n{3,}/g, "\n\n").trim());
}

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

function elapsed(iso, nowMs) {
    if (typeof iso !== "string" || iso === "")
        return -1;
    var then = Date.parse(iso);
    if (!isFinite(then))
        return -1;
    return Math.max(0, nowMs - then);
}

var MINUTE_MS = 60000;
var HOUR_MS = 3600000;
var DAY_MS = 86400000;

// The right-hand column of a repository row: as few characters as the age
// allows, because the column is right-aligned against elided repository names.
function relTime(iso, nowMs) {
    var age = elapsed(iso, nowMs);
    if (age < 0)
        return "";
    if (age < MINUTE_MS)
        return "now";
    if (age < HOUR_MS)
        return Math.floor(age / MINUTE_MS) + "m";
    if (age < DAY_MS)
        return Math.floor(age / HOUR_MS) + "h";
    if (age < 30 * DAY_MS)
        return Math.floor(age / DAY_MS) + "d";
    if (age < 365 * DAY_MS)
        return Math.floor(age / (30 * DAY_MS)) + "mo";
    return Math.floor(age / (365 * DAY_MS)) + "y";
}

// The prose form, under a commit subject and beside the popover header's
// "checked …". Past a week it becomes a date: "6d ago" still means something,
// "43d ago" does not.
//
// Counted in calendar days, not in elapsed ones, so this agrees with the
// dividers recencyBucket rules between groups. Flooring elapsed hours instead
// put "3d ago" on both sides of a day boundary — the divider said the day had
// changed and the two labels said it had not.
function agoLabel(thenMs, nowMs) {
    if (typeof thenMs !== "number" || !isFinite(thenMs) || thenMs <= 0)
        return "";
    var age = Math.max(0, nowMs - thenMs);
    if (age < MINUTE_MS)
        return "just now";
    var days = calendarDaysBetween(thenMs, nowMs);
    if (days === 0) {
        return age < HOUR_MS ? Math.floor(age / MINUTE_MS) + "m ago"
            : Math.floor(age / HOUR_MS) + "h ago";
    }
    if (days === 1)
        return "yesterday";
    if (days <= 6)
        return days + "d ago";
    var date = new Date(thenMs);
    return date.getDate() + " " + MONTHS[date.getMonth()];
}

// Whole calendar days between two instants, in local time — so "yesterday"
// means yesterday rather than "more than 24 hours ago", which is what a
// commit at 23:50 and one at 00:10 would otherwise disagree about. Rounded
// rather than floored because a DST boundary makes a day 23 or 25 hours long.
function calendarDaysBetween(thenMs, nowMs) {
    function startOfDay(ms) {
        var d = new Date(ms);
        d.setHours(0, 0, 0, 0);
        return d.getTime();
    }
    return Math.max(0, Math.round((startOfDay(nowMs) - startOfDay(thenMs)) / DAY_MS));
}

function calendarDaysAgo(iso, nowMs) {
    var then = Date.parse(iso);
    if (typeof iso !== "string" || iso === "" || !isFinite(then))
        return -1;
    return calendarDaysBetween(then, nowMs);
}

// A key for the age band a timestamp falls in. Two adjacent rows in a
// newest-first list belong to the same band exactly when these match, which is
// all the list needs to know to decide where to rule a line.
//
// The bands tighten towards now, because that is where the reader's sense of
// time is finest: each of the last seven days on its own, then each week for a
// month, then each month. Never a fixed count — an old list keeps getting
// separators, just coarser ones.
function recencyBucket(iso, nowMs) {
    var days = calendarDaysAgo(iso, nowMs);
    if (days < 0)
        return "";
    if (days <= 6)
        return "d" + days;
    if (days <= 34)
        return "w" + Math.floor(days / 7);
    return "m" + Math.floor(days / 30);
}

// Whether a divider belongs above `row` in a newest-first list.
function bucketBreak(iso, previousIso, nowMs) {
    return recencyBucket(iso, nowMs) !== recencyBucket(previousIso, nowMs);
}

function agoLabelIso(iso, nowMs) {
    if (typeof iso !== "string" || iso === "")
        return "";
    var then = Date.parse(iso);
    return isFinite(then) ? agoLabel(then, nowMs) : "";
}

// The toast a watched repository earns when it moves while the popover is
// closed. Null when nothing is worth saying, so the caller never has to decide
// whether a count of zero is a notification.
function pushToast(slug, count, topSubject) {
    if (typeof slug !== "string" || slug === "" || count <= 0)
        return null;
    // Only MAX_COMMITS are ever fetched, so a full page cannot tell 20 from
    // 200. Saying "20" there would be a number this shell does not have.
    var many = count >= MAX_COMMITS ? MAX_COMMITS + "+" : String(count);
    return {
        summary: slug + " — " + many + (count === 1 ? " new commit" : " new commits"),
        body: typeof topSubject === "string" ? topSubject : ""
    };
}

var exported = {
    MAX_WATCH: MAX_WATCH,
    MAX_COMMITS: MAX_COMMITS,
    REPOS_MIN: REPOS_MIN,
    REPOS_MAX: REPOS_MAX,
    POLL_MIN: POLL_MIN,
    POLL_MAX: POLL_MAX,
    BADGE_MODES: BADGE_MODES,
    GITHUB_QUERIES: GITHUB_QUERIES,
    repoSlug: repoSlug,
    normalizeWatch: normalizeWatch,
    parseRepos: parseRepos,
    parseRepo: parseRepo,
    parseLogin: parseLogin,
    sortRepos: sortRepos,
    mergeRepos: mergeRepos,
    orgCount: orgCount,
    unreadRepos: unreadRepos,
    parseCommits: parseCommits,
    parseCommitStats: parseCommitStats,
    newCommits: newCommits,
    subject: subject,
    messageBody: messageBody,
    relTime: relTime,
    calendarDaysAgo: calendarDaysAgo,
    recencyBucket: recencyBucket,
    bucketBreak: bucketBreak,
    agoLabel: agoLabel,
    agoLabelIso: agoLabelIso,
    pushToast: pushToast
};

if (typeof module !== "undefined" && module.exports)
    module.exports = exported;
