# Fedora Config

An opinionated Fedora Linux installation for my Dell XPS.

This repository uses Ansible to turn a clean Fedora Workstation installation
into a complete daily-driver setup. It installs and configures the desktop,
applications, development tools, shell, dotfiles, laptop services, firewall,
and update workflow. Fedora remains responsible for the kernel, drivers,
SELinux, and the base operating system.

## What it sets up

- Hyprland with the [Noctalia](https://docs.noctalia.dev/v5/) bar, launcher, control center, notifications,
  wallpaper, lock screen, and idle handling
- GDM with GNOME kept installed as a fallback session
- A curated set of desktop apps, command-line tools, fonts, and developer tools
- Fish, Kitty, Neovim, containers, Android tooling, and Rust/Node.js toolchains
- Laptop power management, firewall rules, hardware support, and a Plymouth theme
- Repeatable system and Flatpak updates through one command

## Shell font

The managed Noctalia configuration uses
[Urbanist](https://github.com/coreyhu/Urbanist). The playbook downloads a
commit-pinned variable font and license, then verifies both checksums.

## XPS 2026 hardware support

The hardware-gated `xps-2026` role supports Dell XPS 14/16 2026 SKUs `0DB9`
and `0DBA`: internal-speaker PipeWire tuning, the OVTI08F4/IPU7 camera path,
configurable Synaptics haptics, explicit Panther Lake media/firmware RPMs, and
Netherlands wireless-regulatory verification. The camera's missing PSYS/CVS
companions use signed DKMS modules; IPU7 base/ISYS and the entire kernel remain
Fedora stock. Omarchy's custom Panther Lake kernel and display patches are
intentionally not included.

See [Dell XPS 2026 / Panther Lake hardware support](docs/xps-2026-hardware.md)
for Secure Boot enrollment, source pins, diagnostics, and the remaining
Panel Replay/VRR gap.

## Before you install

> [!WARNING]
> This is a personal configuration, not a general-purpose Fedora installer. It
> makes system-wide changes and currently expects **Fedora 44 x86_64**, a
> matching **Dell XPS**, and the local user **`john`**. It also enables the
> security trade-offs configured in
> [`inventory/group_vars/all.yml`](inventory/group_vars/all.yml), including
> passwordless sudo and local Polkit access. Review that file and adapt the
> machine, user, feature, and security settings before running it elsewhere.

Start with a working Fedora 44 installation and a user that can run `sudo`.

## Install

Clone the repository:

```bash
sudo dnf install -y git
git clone https://github.com/DigitalPals/fedora-config.git
cd fedora-config
```

Review the machine-specific settings, then run the installer:

```bash
$EDITOR inventory/group_vars/all.yml
./bootstrap
```

`bootstrap` installs `ansible-core` when needed and applies the complete
configuration. It is safe to run again after changing the configuration.

When `gdm_autologin` is enabled in `inventory/group_vars/all.yml`, the next boot
automatically logs in to **Hyprland (Noctalia)**. From that session, check the
installation with:

```bash
./verify --require-hyprland
```

If `gdm_autologin` is disabled, GDM keeps presenting its normal login screen;
choose **Hyprland (Noctalia)** there to start the configured session.

## Update

Pull the latest configuration and run the updater:

```bash
cd /path/to/fedora-config
git pull --ff-only
./update
```

This updates Fedora packages and system Flatpaks. Use `./update --full` to also
reapply the Ansible configuration. Detailed logs are saved under
`~/.local/state/xps-update/logs/`. Run `./update --help` for all options.

## Commands

| Command | Purpose |
| --- | --- |
| `./bootstrap` | Install Ansible if needed and apply the full configuration |
| `./update` | Update Fedora packages and system Flatpaks |
| `./update --full` | Also update tools and reapply the managed configuration |
| `./verify` | Run non-destructive checks against the installed system |

Extra arguments to `bootstrap` are passed to `ansible-playbook`. For `update`,
use `--full` before Ansible arguments, for example `./update --full --check
--diff` or `./update --full --tags desktop,dotfiles`.

## Documentation

| Document | Purpose |
| --- | --- |
| [docs/xps-2026-hardware.md](docs/xps-2026-hardware.md) | XPS 2026 speaker, IPU7 camera, haptics, Secure Boot, and diagnostics |

The automated side is `./verify`, which validates the managed Noctalia and XPS
hardware configuration before the installed-system checks.
