# T3 git actions manual verification

Use a connected T3 Code server whose token has `orchestration:operate`, plus
threads whose project checkouts can be put into each git state below.

## Visibility (options must only appear when they apply)

- [ ] Open a thread whose checkout has uncommitted changes: the GIT card shows
  `branch · N changed · +A −D` and only `Commit & Push` (plus `View PR ↗` if a
  PR exists for the branch).
- [ ] Open a thread whose checkout is clean but ahead of upstream: only `Push`
  is shown, and the status line ends with `↑n`.
- [ ] Open a thread whose checkout is clean and up to date with no PR: the GIT
  card shows only the status line (`branch · clean`) with no action buttons.
- [ ] Open a thread whose branch has an open PR: `View PR ↗` is shown; it opens
  the PR in the browser and closes the popover.
- [ ] Open a thread whose project folder is not a git repository: no GIT card.
- [ ] With a read-only pairing (token without `orchestration:operate`), confirm
  `Commit & Push`/`Push` are hidden while `View PR ↗` still works.

## Commit & Push (defaults to the current branch — main)

- [ ] Trigger `Commit & Push` on a dirty checkout on `main`: the button label
  swaps to the live phase (`Generating commit message…`, then the push phase);
  generation longer than 15 s must NOT time out (budget is 120 s, sliding).
- [ ] On success the card shows `Committed <sha7> · <subject> — pushed to
  main`, the status line goes `clean`, and the `Commit & Push` button
  disappears. Verify on the server that the commit landed on `main` (no
  feature branch was created).
- [ ] Trigger `Push` on a clean-but-ahead checkout: `↑n` clears; a second push
  reports `Already up to date` (the button hides after the refresh).
- [ ] Repo with a pre-commit hook: the label shows `Running <hook>…` while it
  runs; a failing hook surfaces its message in red inside the card.
- [ ] Navigate to the inbox mid-action and back: the action completes (it is
  not interrupted) and the refreshed status reflects the result.
- [ ] Disconnect (stop the server or drop the network) mid-action: the card
  shows `Disconnected before confirmation`, the pending state clears, and the
  server-side push still completes; reopening the thread shows clean status.

## Status refresh and errors

- [ ] The status refreshes when a turn finishes with a ready checkpoint and
  after every git action; reopening a thread within 10 s reuses the last fetch.
- [ ] Point a project at a deleted folder: the card shows the fetch error with
  a `Retry` action that re-requests the status.

## Automated and runtime checks

- [ ] Run `node --test roles/desktop/files/quickshell/Common/tests/t3code-helpers.test.cjs`.
- [ ] Reload `quickshell.service` and inspect that invocation's journal for QML
  load failures, syntax errors, and binding loops; open the popover with
  `qs ipc call popouts toggle t3code`.
