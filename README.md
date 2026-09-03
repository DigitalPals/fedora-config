# Fedora Config

An opinionated Hyprland and Quickshell desktop for Fedora Linux, installed and
kept current with Ansible. The core configuration is hardware-neutral. A
separate, precisely gated role preserves extra support for the 2026 Dell XPS
14 and 16.

The current release target is Fedora 44 on x86_64. Fedora remains responsible
for the kernel, drivers, SELinux, and base operating system.

## What it installs

- Hyprland, a custom Quickshell menubar, GDM, portals, notifications, and
  desktop services
- a portable Fedora package, Flatpak, shell, font, firewall, and recovery
  baseline
- optional developer/Android tools, Steam, Docker, Podman/Distrobox,
  Tailscale, connected-service widgets, and proprietary applications
- automatically detected XPS 2026 speaker, camera, haptic, fingerprint,
  backlight, firmware, and power support
- a persistent installer configuration, verifier, uninstaller, and verified
  GitHub release updater

There is no desktop-preset selection: every installation gets the same core
Hyprland/Quickshell desktop. The installer asks only about the target machine,
security decisions, personal dotfiles, and optional components.

## Install

Start with Fedora 44 and a user that can run `sudo`:

```bash
sudo dnf install -y git
git clone https://github.com/DigitalPals/fedora-config.git
cd fedora-config
./install
```

No inventory or configuration file needs to be edited first. The installer
detects the current desktop user, home directory, hostname, timezone, locale,
and keyboard settings and offers them as defaults. It asks about optional
software and explicitly asks whether to enable passwordless sudo, passwordless
local Polkit authorization, and GDM autologin. The two passwordless choices
have no implicit answer.

Answers are saved in `/etc/fedora-config/config.yml`, outside versioned release
trees, and are reused by later installs and updates. Run
`fedora-config configure` to ask the questions again. `./bootstrap` remains a
compatibility alias for `./install`. The first successful install snapshots
the runtime source under `~/.local/share/fedora-config/releases/`, so the
cloned checkout can then be moved or removed.

Before any role adopts configuration, the installer creates a one-time backup
under `~/.local/state/fedora-config/backups/initial/`. Existing Hyprland and
Quickshell trees are always preserved; personal application files are added
when the optional dotfiles integration is selected. Uninstall restores those
pre-existing files. Managed Fish, Kitty, Git, and SSH settings use
fragments/includes where those applications support them. No wallpapers or
avatar are imposed; choose a wallpaper folder in Shell Settings after
installation.

## Update

After the first install, use:

```bash
fedora-config update
```

The updater follows the saved `stable` channel by default (`--channel beta`
selects and saves prereleases). It resolves an immutable GitHub release,
verifies GitHub's release and asset attestations, checks the API SHA-256
digest, validates Fedora/architecture/config-schema compatibility, and
extracts into a versioned staging directory. It migrates a backed-up copy of
the saved answers, applies the candidate through the durable updater, and
changes the `current` symlink only after success. A failed apply restores the
previous configuration. The active release and two recent fallbacks are kept.

The same durable worker updates Fedora packages and system Flatpaks. It uses a
transient system unit when sudo requires authentication, so a terminal or
Quickshell restart does not interrupt package work. On Btrfs, package work
first creates a paired read-only root snapshot and `/boot` archive.

Useful commands:

| Command | Purpose |
| --- | --- |
| `fedora-config update --check` | Check the configured GitHub channel |
| `fedora-config update --system-only` | Update Fedora and Flatpak only |
| `fedora-config verify` | Run source and installed-system checks |
| `fedora-config doctor` | Alias for `verify` |
| `fedora-config configure` | Re-run the installer questions |
| `fedora-config uninstall` | Remove project-managed configuration; retain applications |

Detailed updater status, logs, cancellation, Btrfs recovery, and advanced
Ansible tags are documented in [the operations guide](docs/operations.md).

## Hardware support

Generic systems skip every XPS workaround. The `xps-2026` role activates only
for Dell vendor/product identifiers, supported SKUs `0DB9` or `0DBA`, and the
expected Panther Lake CPU family; individual devices are gated again before
their configuration is installed. See
[Dell XPS 2026 hardware support](docs/xps-2026-hardware.md).

## Development and releases

```bash
./verify --source
./tests/fedora-vm-convergence
```

CI runs the complete source contract in Fedora 44 and converges a generic
Fedora Cloud VM twice to enforce idempotence. A `vX.Y.Z` tag publishes only
after both gates pass. Repository release immutability must be enabled before
the first public tag.

Key documentation:

- [Operations and recovery](docs/operations.md)
- [Release process](docs/releasing.md)
- [Dependency and pinning policy](docs/dependency-policy.md)
- [Fedora major upgrades](docs/fedora-major-upgrade.md)
- [Licensing and asset provenance](docs/licensing.md)
- [Quickshell development notes](docs/quickshell-notes.md)

> [!IMPORTANT]
> The repository does not yet contain a repository-wide software license.
> Select one before calling the project open source or publishing a public
> release. Undocumented bundled raster assets were removed from the release
> payload; `assets/PROVENANCE.json` enforces that boundary.
