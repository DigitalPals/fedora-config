# Private alpha validation — 2026-09-05

Validated ISO: `FC-LIVE-44.iso`, Fedora 44, desktop RPM
`fedora-config-desktop-0.1.0-0.1.alpha.fc44.noarch`.

SHA-256:

```text
3358a9dc418154b1ccfa809d00ccf8624d9c706b3571a34c6ddcfc401a2172e1
```

The final artifacts are in `~/.local/share/fedora-config/images/alpha-01/`.
This record applies to this ISO; rebuilds use moving upstream repositories.

| Check | Result |
| --- | --- |
| Six account-isolation and welcome/QML tests | Passed |
| Kickstart validation, including the interactive cleanup hook | Passed |
| ShellCheck and application desktop-file validation | Passed |
| Upstream RPM signature checks during composition | Passed |
| BIOS live boot, welcome and Quickshell audit | Passed |
| UEFI live boot, welcome and Quickshell audit | Passed |
| Graphical Anaconda installation, internet route removed before confirmation | Passed |
| Whole-disk installation with encrypted Btrfs root/home | Passed |
| Installed target cleanup and account/session configuration | Passed |
| UEFI boot from the installed disk without an ISO | Passed |
| Disk unlock, GDM login and installed Hyprland welcome | Passed |
| Installed personalization button and Quickshell audit | Passed |
| ISO/RPM checksums after copying to the delivery directory | Passed |

The installation test used QEMU/KVM with a q35 machine, four virtual CPUs,
8 GiB RAM, virtio graphics, a blank 48 GiB virtual disk, and OVMF without
Secure Boot. The actual Anaconda Web UI was driven through a private SSH
tunnel. Temporary SSH access was added for inspection after boot; the ISO
and installer were not patched during the final test.

Before the first installed boot, the target had no live account, live sudo
or Polkit grants, live startup unit, live dracut configuration, autologin, or
test SSH key. Root was locked and SSH disabled. The installed account had
Hyprland selected in AccountsService. The installed system booted with
SELinux enforcing and encrypted Btrfs mounted at `/` and `/home`.

Each live shell test checked the service MainPID against every `qs` PID and
checked the current invocation's journal for QML errors. The final installed
test began and ended with one healthy service-owned Quickshell process.
Hyprland reported no configuration errors. Qt emitted software-rendering and
portal-registration warnings in the VM; the tested welcome and settings
interfaces rendered and worked.

Diagnostic logs and screenshots are retained under
`~/.local/state/fedora-config/iso-research/`. The delivery directory includes
selected evidence in `validation/`. Test VMs are stopped; temporary host SSH
keys are removed. The final installed test disk is retained separately under
`images/live-test-08/installed.qcow2` for inspection.

Not qualified by this test: physical hardware, Secure Boot, BIOS installation
to disk, dual boot, manual partitioning, recovery, and hardware-specific
graphics or networking. Public distribution also needs a repository license,
redistribution/branding review, and signed desktop RPM update hosting, as
described in [README.md](README.md).
