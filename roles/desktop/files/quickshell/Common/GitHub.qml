pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "GitHubHelpers.js" as Helpers
import "ProcHelpers.js" as ProcHelpers

// The repository feed behind the GitHub bar module.
//
// Every read is a `gh api` run against the CLI's existing login, so this owns
// no credentials of its own — `gh auth status` is the whole authentication
// story, and a shell that cannot read anything says so rather than asking for
// a token. The projections live in GitHubHelpers.GITHUB_QUERIES.
//
// One Process, one queue. A poll is a handful of calls (the account, your
// repositories, then one per watched repository the account cannot already
// see), and the popover adds a commit list on demand; running them
// concurrently would need a Process per job, since a Process is a QML object
// with one command. Serialising through a single queue keeps that to one
// object and, more usefully, keeps the module to one `gh` at a time.
Singleton {
    id: root

    readonly property var opts: Settings.modOpts.gh
    readonly property var watch: Helpers.normalizeWatch(opts.watch)
    // Comparable identity for the watch list: Settings.modOpts is replaced
    // wholesale on every module-option edit, so `watch` alone changes when an
    // unrelated module is tuned. This does not.
    readonly property string watchKey: watch.join(",")
    readonly property int pollMins: opts.pollMins
    readonly property bool toastsEnabled: opts.toasts

    // The feed only exists for the bar module; with the module off, polling
    // GitHub every few minutes is pure idle churn. Mirrors Usage.pollEnabled.
    readonly property bool pollEnabled: {
        const mods = Settings.mods;
        for (const col of ["left", "center", "right"]) {
            const hit = mods[col].find(m => m.id === "gh");
            if (hit)
                return hit.on;
        }
        return false;
    }

    // ---- published state -------------------------------------------------
    property var repos: []
    property string login: ""
    property int orgCount: 0
    // Why the last poll produced nothing usable, "" when it worked. The
    // previous feed is kept on screen either way: a failed poll is not news
    // about the repositories, only about this shell's ability to read them.
    property string error: ""
    property double checkedAt: 0
    property bool polling: false
    // True once a poll has completed, so "no repositories" can be told apart
    // from "not asked yet".
    property bool ready: false

    // Per-repository commit lists and per-commit statistics, both filled on
    // demand from the popover. { slug: { rows, error, at } } and
    // { sha: { files, additions, deletions, url } }.
    property var commitCache: ({})
    property var statsCache: ({})
    readonly property int commitCacheMs: 60000

    // Everything pushed since the popover was last open. The watermark only
    // advances when the popover closes, so the rows you opened it to read stay
    // marked while you read them.
    property string seenAt: ""
    readonly property var unread: Helpers.unreadRepos(repos, seenAt)
    readonly property int unreadCount: unread.length

    readonly property string badgeMode: opts.badge
    readonly property bool badgeVisible: badgeMode !== "off" && unreadCount > 0

    function repoUrl(slug) {
        return "https://github.com/" + slug;
    }

    function open(url) {
        if (typeof url === "string" && url !== "")
            Quickshell.execDetached(["xdg-open", url]);
    }

    function copy(text) {
        if (typeof text === "string" && text !== "")
            Quickshell.execDetached(["wl-copy", text]);
    }

    // ---- watermark -------------------------------------------------------
    function nowIso() {
        return new Date().toISOString();
    }

    function markSeen() {
        seenAt = nowIso();
        persist();
    }

    // What each watched repository's push stamp was at the end of the last
    // poll, so the next one can tell "moved" from "still there". Separate from
    // the watermark: toasts fire whether or not you have opened the popover.
    property var lastPush: ({})

    function persist() {
        // FileView.adapter has an incomplete type in the qmltypes, so qmllint
        // cannot see ids declared under it. The id resolves normally at
        // runtime — the same exemption Usage's history file carries.
        // qmllint disable unqualified
        stateData.seenAt = root.seenAt;
        stateData.lastPush = root.lastPush;
        // qmllint enable unqualified
        stateFile.writeAdapter();
    }

    FileView {
        id: stateFile
        path: Quickshell.env("HOME") + "/.local/state/quickshell-github.json"
        printErrors: false
        // Read during construction, so the first poll — which the timer fires
        // as soon as this singleton exists — can tell "never seen" from a
        // watermark that is simply still loading. Getting that wrong lights
        // the badge for every repository once per session.
        blockLoading: true
        // qmllint disable unqualified
        onLoaded: {
            root.seenAt = typeof stateData.seenAt === "string" ? stateData.seenAt : "";
            root.lastPush = stateData.lastPush && typeof stateData.lastPush === "object"
                ? stateData.lastPush : ({});
        }
        // qmllint enable unqualified

        JsonAdapter {
            id: stateData
            property string seenAt: ""
            property var lastPush: ({})
        }
    }

    // ---- job queue -------------------------------------------------------
    // A job is { kind, slug?, sha?, toast?, since? }. The path and projection
    // come from GITHUB_QUERIES, so nothing here builds a URL by hand.
    property var queue: []
    property var active: null

    function enqueue(job) {
        queue = queue.concat([job]);
        pump();
    }

    function pump() {
        if (active !== null || queue.length === 0 || ghProc.running)
            return;
        const job = queue[0];
        queue = queue.slice(1);
        active = job;
        const query = Helpers.GITHUB_QUERIES[job.kind === "watch" ? "repo"
            : job.kind === "stats" ? "commit" : job.kind];
        const path = query.path.replace("{repo}", job.slug ?? "")
            .replace("{sha}", job.sha ?? "");
        ghProc.command = ["gh", "api", path, "--jq", query.jq];
        ghProc.running = true;
    }

    // ---- polling ---------------------------------------------------------
    // Repositories this account can see, and the watched ones it cannot,
    // accumulated across a poll's jobs and merged once they have all landed.
    property var ownRepos: []
    property var extraRepos: []
    property int pendingWatch: 0

    function refresh() {
        // A poll already in flight is the poll you wanted; stacking a second
        // one would only duplicate every call in it.
        if (polling)
            return;
        polling = true;
        ownRepos = [];
        extraRepos = [];
        pendingWatch = 0;
        if (login === "")
            enqueue({ kind: "login" });
        enqueue({ kind: "repos" });
    }

    // Opening the popover asks for fresh figures, but hover-switching across
    // the bar opens and closes it repeatedly — so only a feed old enough to be
    // worth re-reading costs a poll.
    function refreshIfStale(maxAgeMs) {
        if (checkedAt <= 0 || Date.now() - checkedAt > maxAgeMs)
            refresh();
    }

    function failPoll(label, exitCode, errText) {
        error = ProcHelpers.commandError(label, exitCode, errText);
        polling = false;
        pendingWatch = 0;
        checkedAt = Date.now();
        if (error !== lastLogged) {
            console.warn("github:", error);
            lastLogged = error;
        }
    }

    // A persistent failure polls on the same schedule as a working one, so
    // logging on change is what keeps it out of the journal.
    property string lastLogged: ""

    function fanOutWatched() {
        const known = {};
        ownRepos.forEach(row => known[row.slug.toLowerCase()] = true);
        const missing = watch.filter(slug => !known[slug.toLowerCase()]);
        pendingWatch = missing.length;
        if (pendingWatch === 0) {
            publish();
            return;
        }
        missing.forEach(slug => enqueue({ kind: "watch", slug: slug }));
    }

    function publish() {
        repos = Helpers.mergeRepos(ownRepos, extraRepos, watch);
        orgCount = Helpers.orgCount(ownRepos, login);
        checkedAt = Date.now();
        error = "";
        lastLogged = "";
        polling = false;
        ready = true;
        // Nothing is retroactively unread: the first poll of a fresh install
        // sets the watermark rather than lighting the badge for every
        // repository that ever moved.
        if (seenAt === "") {
            seenAt = nowIso();
            queueToasts(true);
        } else {
            queueToasts(false);
        }
    }

    // One toast per watched repository whose push stamp advanced since the
    // last poll. The commit list it needs is fetched rather than guessed, so
    // the toast can name what actually landed.
    function queueToasts(silent) {
        const seen = lastPush ?? ({});
        const next = {};
        for (const row of repos) {
            if (!row.watched)
                continue;
            const previous = seen[row.slug];
            next[row.slug] = row.pushedAt;
            if (silent || !toastsEnabled || previous === undefined
                    || row.pushedAt === "" || row.pushedAt <= previous)
                continue;
            enqueue({ kind: "commits", slug: row.slug, toast: true, since: previous });
        }
        lastPush = next;
        persist();
    }

    // ---- commits ---------------------------------------------------------
    function commitsFor(slug) {
        return commitCache[slug] ?? null;
    }

    function requestCommits(slug, force) {
        if (typeof slug !== "string" || slug === "")
            return;
        const cached = commitCache[slug];
        if (!force && cached && cached.error === ""
                && Date.now() - cached.at < commitCacheMs)
            return;
        if (queue.some(job => job.kind === "commits" && job.slug === slug)
                || (active !== null && active.kind === "commits" && active.slug === slug))
            return;
        patchCommits(slug, { rows: cached ? cached.rows : [], error: "", loading: true,
            at: cached ? cached.at : 0 });
        enqueue({ kind: "commits", slug: slug, toast: false, since: "" });
    }

    function patchCommits(slug, entry) {
        const next = {};
        for (const key of Object.keys(commitCache))
            next[key] = commitCache[key];
        next[slug] = entry;
        commitCache = next;
    }

    function statsFor(sha) {
        return statsCache[sha] ?? null;
    }

    function requestStats(slug, sha) {
        if (typeof sha !== "string" || sha === "" || statsCache[sha] !== undefined)
            return;
        if (queue.some(job => job.kind === "stats" && job.sha === sha)
                || (active !== null && active.kind === "stats" && active.sha === sha))
            return;
        enqueue({ kind: "stats", slug: slug, sha: sha });
    }

    function patchStats(sha, entry) {
        const next = {};
        for (const key of Object.keys(statsCache))
            next[key] = statsCache[key];
        next[sha] = entry;
        statsCache = next;
    }

    // ---- results ---------------------------------------------------------
    function settle(exitCode, body, errText) {
        const job = active;
        active = null;
        if (job === null) {
            pump();
            return;
        }
        const failed = exitCode !== 0;
        switch (job.kind) {
        case "login":
            // A login this shell could not read is not fatal — it only costs
            // the settings page a name — so the poll carries on either way.
            if (!failed)
                login = Helpers.parseLogin(body);
            break;
        case "repos": {
            const rows = failed ? null : Helpers.parseRepos(body);
            if (rows === null) {
                failPoll("gh api /user/repos", exitCode, errText);
                break;
            }
            ownRepos = rows;
            fanOutWatched();
            break;
        }
        case "watch": {
            const row = failed ? null : Helpers.parseRepo(body);
            // A watched repository that has been renamed, made private or
            // typo'd fails on its own without taking the feed with it.
            if (row !== null)
                extraRepos = extraRepos.concat([row]);
            else
                console.warn("github: cannot read watched repo", job.slug + ":",
                    ProcHelpers.commandError("gh api", exitCode, errText));
            pendingWatch = Math.max(0, pendingWatch - 1);
            if (pendingWatch === 0)
                publish();
            break;
        }
        case "commits": {
            const rows = failed ? null : Helpers.parseCommits(body);
            patchCommits(job.slug, {
                rows: rows ?? [],
                error: rows === null
                    ? ProcHelpers.commandError("gh api commits", exitCode, errText) : "",
                loading: false,
                at: Date.now()
            });
            if (job.toast && rows !== null)
                raiseToast(job.slug, rows, job.since);
            break;
        }
        case "stats": {
            const stats = failed ? null : Helpers.parseCommitStats(body);
            // A failed count still caches, so a commit whose statistics
            // cannot be read stops asking for them every time it is expanded.
            patchStats(job.sha,
                stats ?? ({ sha: job.sha, files: 0, additions: 0, deletions: 0 }));
            break;
        }
        }
        pump();
    }

    function raiseToast(slug, rows, since) {
        const toast = Helpers.pushToast(slug, Helpers.newCommits(rows, since),
            rows.length > 0 ? rows[0].subject : "");
        if (toast === null)
            return;
        Notifs.send({
            appName: "GitHub",
            appIcon: "github",
            image: Quickshell.shellDir + "/assets/github.svg",
            summary: toast.summary,
            body: toast.body
        });
    }

    Process {
        id: ghProc
        // `gh api` writes its complaint to stderr and exits nonzero for every
        // failure this shell can hit — no login, no network, a repository that
        // is gone. Both streams close before exited(), and the falling edge of
        // `running` is the only signal there is when gh is not installed at
        // all, which is why the exit code is defaulted to NOT_STARTED there.
        property string body: ""
        property string errText: ""
        property bool exitSeen: false
        property int lastExit: 0

        stdout: StdioCollector {
            onStreamFinished: ghProc.body = text
        }
        stderr: StdioCollector {
            onStreamFinished: ghProc.errText = text
        }
        onExited: (exitCode, exitStatus) => {
            ghProc.exitSeen = true;
            ghProc.lastExit = exitCode;
        }
        onRunningChanged: {
            if (running) {
                body = "";
                errText = "";
                exitSeen = false;
                lastExit = 0;
                return;
            }
            root.settle(exitSeen ? lastExit : ProcHelpers.NOT_STARTED, body, errText);
        }
    }

    Timer {
        id: pollTimer
        interval: root.pollMins * 60000
        running: root.pollEnabled
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // Editing the watch list changes what the feed contains, so it applies
    // straight away rather than at the next poll. Debounced because the
    // settings list is edited a row at a time, and deferred past a poll
    // already in flight, which refresh() would otherwise decline to replace.
    Timer {
        id: watchApply
        interval: 500
        onTriggered: {
            if (root.polling)
                restart();
            else
                root.refresh();
        }
    }

    onWatchKeyChanged: {
        if (pollEnabled && ready)
            watchApply.restart();
    }
}
