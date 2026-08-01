# Fedora 44 XPS configuration

This repository recreates the XPS experience from the
[nixos-config](https://github.com/DigitalPals/nixos-config) setup on Fedora
without installing Nix. Fedora owns boot, kernel, drivers, power management,
GNOME, SELinux, and hardware integration. Ansible owns only the files and
settings documented here. Shared assets (wallpapers, avatar, helper scripts,
prompt theme) are vendored under `assets/`.

Run from this directory:

```sh
./bootstrap                 # install Ansible and converge
./verify                    # non-destructive acceptance checks
./finalize                  # verify, then enable GDM autologin
./update                    # DNF/Flatpak/toolchains/latest upstream releases
```

All commands accept extra `ansible-playbook` arguments. Examples:

```sh
./bootstrap --check --diff
./bootstrap --tags base,dotfiles
ansible-playbook site.yml --list-tags
```

Playbook output is compact by default (roles as headers, one line per change,
one-line recap); pass `-v` to any command for the stock verbose Ansible output.

## Update behavior

`./update` runs the DNF system upgrade and the system Flatpak update
concurrently, then converges the playbook with `--skip-tags boot,finalize`
(both roles are pinned bootstrap/finalize concerns). A transient Flatpak
failure is reported as a warning and does not block the configuration run;
a DNF failure aborts. Full step logs land in
`~/.local/state/xps-update/logs/<timestamp>/`.

Package tasks in the playbook use `state: present`; keeping installed packages
current is exclusively the wrapper's single DNF transaction, so a no-change
`./update` does not re-depsolve the world. Upstream release installers run as
parallel async jobs and their GitHub API calls are ETag-cached (HTTP 304
responses do not count against the anonymous rate limit), so `GH_TOKEN` is
rarely needed for routine updates.

`finalize` intentionally remains a separate gate. Log in to **Hyprland (Lumen)**
manually first and run `./verify --pre-finalize`. Tailscale, 1Password, browser
sync, Spotify, keyring password changes, and private backup authorization remain
interactive.

No secrets or 1Password item references belong in this tree. Upstream installers
use the GitHub release API on every convergence, require the release asset's
SHA-256 digest, stage changes atomically, and retain cached/previous artifacts.
Source builds install only after a successful build of a new tag or revision.
The affected Lumen 0.7.6 release receives a pinned, version-gated Hyprland 0.56
JSON-field compatibility backport. Its last working binary is retained, and the
launcher returns to the official RPM automatically when Lumen is upgraded.

Before a Fedora major upgrade, confirm `sdegler/hyprland` has builds for the new
release. GNOME remains installed and selectable as the recovery session.

## Rollout

1. Run `./bootstrap`, then `./bootstrap --check --diff`, then `./bootstrap` a
   second time. The second real run should be unchanged unless an external
   nightly/release or Rust nightly advanced between runs.
2. Log out, select **Hyprland (Lumen)** in GDM, and run
   `./verify --pre-finalize`. Complete the manual hardware/application checklist
   printed by the verifier.
3. Run `./finalize`, reboot twice, verify autologin reaches Lumen, then log out
   once and confirm GNOME remains selectable.
4. Complete one-time interactive work: blank (do not delete) the Login keyring
   password, unlock/configure 1Password and its SSH agent, sign in to browser
   sync and Spotify, run `tailscale up`, and authorize any private backup or
   remote-service access you actually want to use.

The verifier never suspends, locks, records, transcribes, transfers files, runs
a stress test, or changes hardware state. Those acceptance tests remain manual
by design.
