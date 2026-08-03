# Fedora Config

An opinionated Fedora Linux installation for my Dell XPS.

This repository uses Ansible to turn a clean Fedora Workstation installation
into a complete daily-driver setup. It installs and configures the desktop,
applications, development tools, shell, dotfiles, laptop services, firewall,
and update workflow. Fedora remains responsible for the kernel, drivers,
SELinux, and the base operating system.

![Fedora running Hyprland and Quickshell](assets/fedora-hyprland-desktop.png)

## What it sets up

- Hyprland with a custom Quickshell bar, launcher, notifications, and popovers
- GDM with GNOME kept installed as a fallback session
- A curated set of desktop apps, command-line tools, fonts, and developer tools
- Fish, Kitty, Neovim, containers, Android tooling, and Rust/Node.js toolchains
- Laptop power management, firewall rules, hardware support, and a Plymouth theme
- Repeatable system and Flatpak updates through one command

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

When it finishes, log out and choose **Hyprland (Quickshell)** in GDM. From that
session, check the installation with:

```bash
./verify --pre-finalize
```

If everything works and you want GDM to log in automatically, run the optional
final step and reboot:

```bash
./finalize
systemctl reboot
```

## Update

Pull the latest configuration and run the updater:

```bash
cd /path/to/fedora-config
git pull --ff-only
./update
```

This updates Fedora packages and system Flatpaks, then reapplies the Ansible
configuration. Detailed logs are saved under
`~/.local/state/xps-update/logs/`.

## Commands

| Command | Purpose |
| --- | --- |
| `./bootstrap` | Install Ansible if needed and apply the full configuration |
| `./update` | Update Fedora, Flatpaks, tools, and the managed configuration |
| `./verify` | Run non-destructive checks against the installed system |
| `./finalize` | Verify Hyprland and enable the configured GDM autologin |

Extra arguments are passed to `ansible-playbook`, so commands such as
`./bootstrap --check --diff` and `./bootstrap --tags desktop,dotfiles` also
work.
