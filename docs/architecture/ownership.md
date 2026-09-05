# Fedora Config ownership boundary

Fedora Config updates replace vendor runtime and integration files. They do
not merge into user customization trees. This is the machine-enforced boundary
for the transitional, pre-RPM layout.

| Owner | Path | Update behavior |
| --- | --- | --- |
| Vendor | `~/.local/share/fedora-config/runtime/quickshell/` | Reconciled exactly from a verified release |
| Vendor | `~/.local/share/fedora-config/runtime/hypr/` | Reconciled from rendered defaults in a verified release |
| Vendor | `~/.local/share/fedora-config/releases/` and `current` | Staged and atomically selected by the release updater |
| User | `~/.config/fedora-config/shell.json` | Read and written by the shell; never written by Ansible after a one-time, non-overwriting legacy copy |
| User | `~/.config/fedora-config/hypr/` | Optional `user.lua`, `hypridle.conf`, and `hyprlock.conf` overrides |
| User | `~/.local/share/fedora-config/themes/` | Reserved user theme packages; never reconciled or pruned |
| User | `~/.local/share/fedora-config/plugins/` | Reserved user extensions; never reconciled or pruned |
| State | `~/.local/state/fedora-config/` | Health, update, migration, and shell runtime state |

The session always starts Hyprland with the vendor entry point. Vendor modules
load first; `~/.config/fedora-config/hypr/user.lua`, when present, loads last.
The idle and lock services prefer their same-named user configuration files
and otherwise use vendor defaults. A bad user override may break that component
but is never silently replaced by an update.

Quickshell starts with an explicit `qs -p` path. The legacy
`~/.config/quickshell` and `~/.config/hypr` trees are not runtime inputs after
the transition. On the first layered convergence, their entries are classified
against the previously active release. Customized and unrecognized entries are
copied into a timestamped migration directory, a JSON report is written, and
the legacy trees themselves are left untouched. No ambiguous QML or Lua is
translated automatically.

## Development source switch

`fedora-config dev enable /absolute/path/to/checkout` selects live Quickshell
sources and static Hyprland modules from a validated, user-owned Git checkout.
Rendered machine modules continue to come from the installed runtime. The
command records only the canonical path and reloads managed desktop components;
it never fetches, resets, merges, commits, or writes inside the checkout.

Use `fedora-config dev status` to show the active source and
`fedora-config dev disable` to return to the verified vendor runtime. Internet
updates continue to stage and activate releases while development mode is on;
they do not modify the selected checkout or user-owned paths.

## Enforcement rules

- Deployment may prune only a vendor-owned runtime root.
- Normal convergence must not copy, template, link, or remove children below
  the user-owned roots in the table, except to create an absent directory or
  perform an explicitly non-overwriting legacy migration.
- Uninstall removes vendor runtime and integration artifacts, not user-owned
  Quickshell, Hyprland, theme, or plugin trees.
- The ownership-preservation test runs in the source and release gates and
  simulates an N to N+1 update with byte-for-byte user sentinels.
