---
name: fedora-config
description: Operate and customize an installed CybexOS Hyprland/Quickshell workstation. Use for CybexOS diagnostics and commands, personal widgets, shell or bar settings, managed desktop changes, screenshots, recording, OCR, reminders, or LocalSend; not for unrelated Fedora systems.
---

# CybexOS

Use this skill for the installed [CybexOS](https://github.com/DigitalPals/fedora-config)
desktop (Cybex Opinionated System, previously Fedora Config). Codex can invoke
it as `$fedora-config`; Claude Code exposes the same
skill as `/fedora-config`. It also supports implicit invocation through the
description above.

## Establish the installation

Read the active release through
`~/.local/share/fedora-config/current`. It is useful for diagnostics, command
source, schemas, and tests, but it is release-managed and read-only.

Before changing anything, choose the ownership layer:

- User shell preferences belong in
  `~/.config/fedora-config/shell.json`. Read
  [Quickshell settings](references/quickshell-settings.md) before editing it.
- Personal bar widgets belong in user-owned plugin packages. Read
  [User widgets](references/user-widgets.md); use the versioned plugin API and
  `fedora-config plugin` commands. Adding a personal widget does not require a
  distro checkout, edits to built-in modules, or Ansible deployment.
- Personal Hyprland changes belong in
  `~/.config/fedora-config/hypr/user.lua`, loaded after vendor defaults.
- Changes to distro defaults, built-in Quickshell code, services, packages,
  and other release-managed behavior belong in a writable checkout. Read
  [Managed configuration](references/managed-configuration.md).

For supported operator commands and desktop actions, read
[Commands and desktop helpers](references/commands.md).

## Non-negotiable boundaries

- Never edit `~/.local/share/fedora-config/current` or anything below it.
- Never directly edit vendor files under
  `~/.local/share/fedora-config/runtime`. Diagnose them by reading; use
  `~/.config/fedora-config`, or make source changes in a writable checkout and
  select it with `fedora-config dev enable`.
- Never add personal plugin IDs or settings to `shell.json`'s built-in `mods`
  or `modOpts`; their normalizers only recognize built-in modules. Preserve
  plugin packages, preferences, and state across updates and rollbacks.
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
