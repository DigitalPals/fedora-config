# Fedora Config live image

The live image packages the existing Hyprland/Quickshell desktop, boots into
a temporary account, and opens a welcome window with **Install Fedora Config**
and **Try the desktop first**. Installation uses Fedora 44's Anaconda Web UI.
Anaconda owns disk selection, partitioning, encryption, account creation,
installation progress, and its final destructive confirmation. The welcome
application never runs a partitioning command.

The core desktop is carried in the ISO and installs offline. Online services
and optional third-party applications are not part of this initial image.

## Try the image

In the build output directory, run `sha256sum --check SHA256SUMS`. Open
`FC-LIVE-44.iso` in a virtual machine, or choose **Custom image** in Fedora
Media Writer and follow its prompts to write the ISO to your chosen USB drive.
Writing an image replaces the contents of that USB drive.

Boot the image and choose **Install Fedora Config** in the welcome window.
Anaconda walks through language, timezone, storage, optional disk encryption,
and your account. Review the selected disk before confirming installation.
When installation finishes, restart and remove the USB drive. Log in to your
new account to open the Hyprland/Quickshell desktop and its first-login welcome.

## Build on Debian or Fedora

On Debian, the host prerequisites are `qemu-system-x86`, `qemu-utils`,
`cloud-image-utils`, and `openssh-client`, plus read/write access to `/dev/kvm`.
Python 3.11 or later is required. The host does not need Anaconda, RPM build
tools, privileged containers, loop devices, or Fedora installed.

```bash
./image/build --output "$HOME/.local/share/fedora-config/images/alpha-01"
```

Use a new, empty output directory for each build. Allow approximately 40 GiB
of free disk space and 12 GiB of RAM. The builder:

1. Downloads and SHA-256-verifies the same Fedora Cloud 44 base used by the
   existing VM convergence test.
2. Boots an isolated KVM guest with a new 100 GiB sparse overlay and temporary
   SSH credentials. Only those virtual disks are attached.
3. Transfers an explicit allowlist of source files, builds the desktop RPM,
   and composes the live ISO with the `livecd-tools` image library.
4. Copies the ISO, RPM, payload manifest, and checksums to the output directory.
5. Stops its VM and removes the temporary disk and credentials on success,
   failure, or a normal interruption. Build and console logs are retained.

The builder uses Fedora's moving security-update repositories, so successive
builds are not byte-for-byte reproducible. The Cloud base, COPR key, and font
downloads are checksum-verified. All upstream RPM repositories retain package
signature checks. Fedora 44 ships an older `livecd-tools` whose transaction
implementation skips signature checking; `image/compose` supplies a DNF
adapter that checks every upstream RPM before any installation script runs.
Only the freshly built private alpha desktop RPM is allowed to be unsigned.

## Runtime and accounts

`fedora-config-desktop` owns shared files under `/usr/share/fedora-config`,
session units under `/usr/lib/systemd/user`, and commands under `/usr/bin` and
`/usr/libexec`. It reuses the existing QML, Hyprland modules, helper scripts,
and checksum-pinned fonts. The image packaging step adapts system helper paths
in its staging directory; the Ansible installation is unchanged.

At login, `fedora-config-user-init` creates only absent runtime/helper links
and empty customization directories. Existing files and even dangling links
are preserved. Shell preferences, plugins, themes, and Hyprland overrides
remain per-user. The system keyboard choice is read through locale1 at login.

The live account is created at boot in the writable overlay, not baked into
the packaged desktop. It has temporary autologin and administrative access.
Anaconda's post-install script explicitly removes that account, its privilege
rules, and live-only startup files from the destination, and restores GDM
without autologin. It records Hyprland as the new accounts' GDM session so the
first login opens the intended desktop. The installed user sees a separate
first-login welcome.
Locking and idle lock are disabled in the passwordless live session.

On image installations, `fedora-config update` uses the existing durable DNF
and Flatpak updater. Desktop RPM updates will require a signed RPM repository;
the Ansible source-release updater is not used to replace RPM-owned files.
The original checkout-based installer and its update channel remain available
for existing installations.

## Checks

### Graphics coverage

The image includes Fedora's kernel driver sets, Mesa OpenGL/EGL and Vulkan
drivers, and explicit AMD, Intel, and NVIDIA GPU firmware packages. These
firmware packages must be listed separately: the compose disables weak
dependencies, so `linux-firmware` alone does not install them. Composition
checks that the required graphics packages are installed before packaging.
The generic live initramfs explicitly includes kernel modesetting (`drm`);
hardware detection chooses the driver, and Hyprland requests each display's
preferred mode. No GPU vendor is forced or blacklisted.

This covers Intel (`i915`/`xe`), AMD (`radeon`/`amdgpu`), NVIDIA through
Nouveau/Mesa (including NVK on supported GPUs), and Fedora's virtual display
drivers such as virtio and VMware. Kernel driver availability does not imply
that every older GPU supports the graphics features Hyprland requires.
Proprietary NVIDIA drivers are not bundled: they require selecting a branch
for the GPU, matching kernel modules, and Secure Boot signing/enrollment when
applicable. Firmware is not a replacement for those drivers on GPUs that need
them. Physical GPU compatibility still needs testing after the next rebuild.

For an unexpected low resolution, `lspci -nnk` (included in the image) shows
the GPU and bound kernel driver, `hyprctl monitors all` shows display modes,
and `sudo journalctl -b -k` exposes firmware, modesetting, and EDID failures.
Boot the normal menu entry when testing graphics; a basic-graphics entry with
`nomodeset` intentionally disables normal kernel modesetting.

### Validation

The first private alpha's completed VM tests and exact ISO checksum are
recorded in [VALIDATION.md](VALIDATION.md).

```bash
# In Fedora with python3-pyside6 installed:
QT_QPA_PLATFORM=offscreen python3 image/tests

# Or use the isolated test container on Debian:
docker build -f image/Containerfile.tests -t fedora-config-image-tests:44 image
docker run --rm -v "$PWD:/source:ro" fedora-config-image-tests:44

# Boot and check an image (UEFI testing on Debian also requires ovmf):
./image/test-live "$HOME/.local/share/fedora-config/images/alpha-01/FC-LIVE-44.iso" \
  --output "$HOME/.local/share/fedora-config/images/test-01"
```

These exercise two-user isolation, preservation during vendor updates,
installed-system installer gating, startup failure reporting, and real Qt QML
loading for both welcome modes. A booted ISO additionally needs graphical
login, Anaconda installation onto a blank virtual disk, and a successful boot
from that installed disk. A passing package build alone does not prove those.

`image/test-live --hold` keeps its VM available for interacting with Anaconda.
The generated `vm.json` records its loopback-only VNC port, SSH command, and
QMP socket. The test boots the ISO through UEFI by default (`--firmware bios`
selects BIOS), opens the live user's terminal through virtual keyboard events,
and adds an ephemeral SSH key to that live session. The ISO itself is not
modified. Interrupting the test audits Quickshell, stops its VM, and removes
the host test key. The virtual disk is retained for inspecting an installation.
The smoke test does not install the system. After a manual installation, stop
the live VM and boot its retained `installed.qcow2` without a CD-ROM, using
the same `OVMF_VARS.fd` for UEFI. Verify disk unlocking, GDM login, and the
installed welcome. Secure Boot requires separate testing.
`image/vm-control` can take screenshots, send clicks/keys, and execute the
recorded SSH command for this disposable VM.

Use `image/build --debug-on-failure` to retain a running failed builder for
inspection. Its `builder.json` contains the SSH command. Interrupt the build
when finished to stop the VM and remove its temporary disk and credentials.

`packages.txt` lists the installed RPM versions. `package-manifest.json` hashes
the staged desktop payload before RPM's normal build transformations (such as
Python shebang changes); it is not an extracted-RPM manifest. `SHA256SUMS`
contains the hashes of the actual ISO and RPM artifacts.

## Release boundary

This is a private alpha image. The repository has no software license yet;
the RPM's `LicenseRef-Not-Licensed` records that fact and grants no rights.
Before public distribution, select the repository license, review redistributed
dependencies and Fedora branding, establish RPM signing and update hosting,
and qualify BIOS/UEFI installation and recovery on supported hardware.
Do not describe a local build as a signed or production-ready release.

Upstream implementation references:

- <https://github.com/livecd-tools/livecd-tools>
- <https://github.com/rhinstaller/anaconda/tree/main/data/liveinst>
- <https://github.com/rhinstaller/anaconda-webui>
