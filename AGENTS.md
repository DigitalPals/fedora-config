# Repository agent instructions

## Build and test artifact cleanup

- Clean up disposable artifacts created during your task before final handoff,
  including failed/retried image builds, test ISOs, VM disks, extracted root
  filesystems, temporary logs, and screenshots. This includes outputs outside
  the checkout, especially `~/.local/share/fedora-config/images/`.
- Use a unique task-specific output directory and track what you create.
  Arrange cleanup with traps or `finally` blocks where practical so failures
  and interruptions also clean up. Stop task-owned VMs/processes and unmount
  task-owned mounts before removing their files.
- Retain only requested deliverables and artifacts still needed for review or
  unresolved diagnostics. Remove intermediate and superseded attempts; record
  useful findings in repository documentation instead of retaining large
  images solely as evidence. Report any retained artifacts with their paths,
  sizes, and reason for keeping them in the final handoff.
- Delete only artifacts you created or have verified are disposable and within
  the user's authorized cleanup scope. Do not infer that another task's files
  are stale from their name or age alone. Never blanket-delete
  `~/.local/share/fedora-config`: it can also contain active releases, runtime
  configuration, user themes/plugins, and persistent data.
- Verify cleanup at the end of the task by checking the output directories
  and their disk usage. Do not leave orphaned build/test processes or mounts.

## Live Quickshell testing

- Keep exactly one live Quickshell menubar. The normal live instance is the
  process owned by `quickshell.service`; never leave a source-tree `qs -d` or
  `qs -p` process running beside it.
- At the start and end of every live shell test, automatically compare
  `systemctl --user show quickshell.service -p MainPID --value` with every PID
  returned by `pgrep -x qs`. Inspect each extra PID's command line and cgroup,
  then terminate only confirmed unmanaged/developer instances. Never use a
  blanket `pkill qs`.
- Prefer deploying the configuration and testing through
  `quickshell.service`. If a direct source-tree `qs -d -p ...` session is
  necessary, stop `quickshell.service` first and arrange cleanup that always
  terminates the developer process and restores the service, including when
  the test fails or is interrupted.
- A live test is not complete until `quickshell.service` is active, its
  `MainPID` is the sole remaining `qs` PID, and the current invocation's
  journal has been checked for QML errors.
