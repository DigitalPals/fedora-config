# T3 git actions manual verification

Use a connected T3 Code server whose token has `orchestration:operate`, plus
threads whose project checkouts can be put into each git state below.

## Visibility (options must only appear when they apply)

- [ ] Open a thread whose checkout has uncommitted changes: the ellipsis menu
  shows only `Commit & Push` (plus `View PR ↗` if a PR exists for the branch).
- [ ] Open a thread whose checkout is clean but ahead of upstream: the ellipsis
  menu shows `Push` and not `Commit & Push`.
- [ ] Open a thread whose checkout is clean and up to date with no PR: no Git
  status, action, card, or tile is visible.
- [ ] Open a thread whose branch has an open PR: `View PR ↗` appears in the
  ellipsis menu; it opens the PR in the browser and closes the popover.
- [ ] Open a thread whose project folder is not a git repository: no Git UI is
  shown.
- [ ] With a read-only pairing (token without `orchestration:operate`), confirm
  `Commit & Push`/`Push` are hidden while `View PR ↗` still works.

## Commit & Push (defaults to the current branch — main)

- [ ] Trigger `Commit & Push` on a dirty checkout on `main`: the menu closes and
  the compact line below the header follows the live phase (`Generating commit
  message…`, then the push phase); generation longer than 15 s must NOT time
  out (budget is 120 s, sliding).
- [ ] On success the compact line shows `Committed <sha7> · <subject> — pushed
  to main` for about six seconds, then disappears. Reopen the menu and confirm
  `Commit & Push` is gone. Verify on the server that the commit landed on
  `main` (no feature branch was created).
- [ ] Trigger `Push` on a clean-but-ahead checkout: the success line appears,
  then `Push` hides after the status refresh.
- [ ] Repo with a pre-commit hook: the compact line shows `Running <hook>…`
  while it runs; a failing hook leaves its message visible in red.
- [ ] Navigate to the inbox mid-action and back: the action completes (it is
  not interrupted) and the refreshed status reflects the result.
- [ ] Disconnect (stop the server or drop the network) mid-action: the compact
  line shows `Disconnected before confirmation`, the pending state clears, and
  the server-side push still completes; reopening the thread shows clean status.

## Status refresh and errors

- [ ] The status refreshes when a turn finishes with a ready checkpoint and
  after every git action; reopening a thread within 10 s reuses the last fetch.
- [ ] Point a project at a deleted folder: the compact error line shows the
  fetch error with a `Retry` action that re-requests the status.

## Activity and changed files

- [ ] Confirm routine latest-activity summaries no longer produce a card or
  tile; messages and the existing Working row remain unchanged.
- [ ] Trigger a session/activity failure and confirm only a compact red inline
  error appears in the timeline.
- [ ] Confirm a ready checkpoint with no changed files produces no UI.
- [ ] Confirm a checkpoint with changes produces one collapsed
  `N changed file(s) · +A −D` row. Expand it, verify the diff loads lazily, then
  exercise collapse, copy, retry, truncated-preview, and full-client actions.
- [ ] Switch threads or receive a newer checkpoint and confirm the expanded
  diff state resets.

## Automated and runtime checks

- [ ] Run `tests/run` (Node tests plus qmllint over the whole shell).
- [ ] Reload `quickshell.service` and inspect that invocation's journal for QML
  load failures, syntax errors, and binding loops; open the popover with
  `qs ipc call popouts toggle t3code`.
