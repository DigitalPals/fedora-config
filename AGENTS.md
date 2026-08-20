# Repository agent instructions

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
