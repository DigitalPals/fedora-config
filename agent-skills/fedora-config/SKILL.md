---
name: fedora-config
description: Operate and customize an installed Fedora Config Hyprland/Quickshell workstation. Use for Fedora Config diagnostics and commands, shell or bar settings, managed desktop changes, screenshots, recording, OCR, reminders, or LocalSend; not for unrelated Fedora systems.
---

# Fedora Config

Use this skill for the installed [Fedora Config](https://github.com/DigitalPals/fedora-config)
desktop. Codex can invoke it as `$fedora-config`; Claude Code exposes the same
skill as `/fedora-config`. It also supports implicit invocation through the
description above.

## Establish the installation

Read the active release through
`~/.local/share/fedora-config/current`. It is useful for diagnostics, command
source, schemas, and tests, but it is release-managed and read-only.

Before changing anything, distinguish these two paths:

- User shell preferences belong in
  `~/.local/state/quickshell/shell-settings.json`. Read
  [Quickshell settings](references/quickshell-settings.md) before editing it.
- Hyprland policy, Quickshell code, services, packages, and other persistent
  managed behavior must change in a writable Fedora Config checkout and be
  deployed with Ansible. Read
  [Managed configuration](references/managed-configuration.md).

For supported operator commands and desktop actions, read
[Commands and desktop helpers](references/commands.md).

## Non-negotiable boundaries

- Never edit `~/.local/share/fedora-config/current` or anything below it.
- Never directly edit Fedora Config-managed files under `~/.config/hypr` or
  `~/.config/quickshell`. Diagnose them by reading; make persistent changes in
  a writable checkout.
- Preserve unrelated checkout changes. Read every applicable `AGENTS.md`
  before modifying or testing a checkout.
- Do not clone a checkout unless the user agrees to the documented location.
- Require explicit user intent before reconfiguration, updates, uninstall,
  cancellation, reboot, shutdown, reset, package removal, or another
  destructive operation. A diagnostic request authorizes inspection, not a
  repair or upgrade.
- Never use `pkill qs`. Every live Quickshell check must use the checkout's
  `tests/lib/quickshell-live` start and end functions, including their PID,
  service, and current-invocation journal checks.

Prefer the least invasive diagnostic that answers the request. Report what was
observed, what was changed, the verification performed, and anything that
still needs manual confirmation.
