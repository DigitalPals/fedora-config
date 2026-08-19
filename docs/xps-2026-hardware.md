# Dell XPS 2026 / Panther Lake hardware support

The `xps-2026` role is intentionally narrow. It runs only when DMI reports
Dell, XPS 14/16 or DA14260/DA16260, SKU `0DB9` or `0DBA`, and a Panther Lake
Core Ultra CPU. Camera and touchpad work have additional ACPI, PCI, and I2C
gates. It does not apply these settings to other Dell laptops.

Fedora's stock kernel remains the only kernel. This role does not build or
install a kernel, `linux-ptl`, an i915/xe/DRM patch, `fred=on`, or a global
Wi-Fi 7/EHT workaround.

## Internal speakers

SKU `0DB9` (plus Quattro-listed XPS 16 SKU `0DBA`) gets Omarchy Quattro's current
13-biquad-per-channel profile and stereo lookahead limiter. A separate user
PipeWire process hosts the graph, so a broken optional profile cannot prevent
the normal PipeWire daemon from starting. Its output is pinned to the exact
`sof_sdw` internal-speaker sink. Headphones, Bluetooth, HDMI/DP, USB, and
network sinks bypass it.

The XPS 14 profile was measured on `0DB9`; `0DBA` is included on the same basis
as Quattro and has not been independently measured here. Fedora provides the
filter-chain LV2 loader and `lsp-plugins-lv2` limiter. Desktop volume keys and
the Quickshell audio UI control the physical speaker gain while the virtual
filter master stays at unity.

Useful checks:

```bash
systemctl --user status xps-speaker-tuning
/usr/local/libexec/xps-speaker-tuning check
pactl list sinks short
journalctl --user -u xps-speaker-tuning -b
```

## OVTI08F4 / IPU7 camera

The camera role additionally requires the `OVTI08F4` ACPI device and Intel PCI
ID `8086:b05d`. Fedora 44 supplies the stock IPU7 base/ISYS modules, IPU bridge,
OV08X40 sensor driver, and `intel/ipu/ipu7ptl_fw.bin`. Those remain owned by the
normal Fedora kernel and `intel-vsc-firmware` packages. Verification rejects an
out-of-tree replacement for either `intel_ipu7` or `intel_ipu7_isys`.

Two missing hardware companions use DKMS:

- Intel IPU7 PSYS, compiled in PSYS-only mode against Fedora's stock core ABI.
- Intel CVS, which acquires Panther Lake's camera power/ownership path before
  the OV08X40 sensor probes.

RPM Fusion's `akmod-v4l2loopback` supplies the third out-of-tree module. Intel's
HAL, redistributable IPU75XA libraries, and `icamerasrc` are built into the
local `xps-ipu7-camera-stack` RPM. `v4l2-relayd` publishes their processed NV12
stream as `/dev/video50`; WirePlumber hides raw Bayer ISYS nodes and the
duplicate generic libcamera endpoint, then exposes only **Hardware ISP
Camera** to PipeWire. Chrome is launched with `PipeWireCamera` enabled.

The source inputs are immutable archives with SHA-256 checksums in
[`roles/xps-2026/defaults/main.yml`](../roles/xps-2026/defaults/main.yml):

| Component | Pinned commit | Why it is needed |
| --- | --- | --- |
| [intel/ipu7-drivers](https://github.com/intel/ipu7-drivers) | `a88b19096a738d0708742a78d6540d6d4a3021ff` | PSYS companion absent from Fedora's stock module set |
| [intel/vision-drivers](https://github.com/intel/vision-drivers) | `a8d772f261bc90376944956b7bfd49b325ffa2f2` | Panther Lake CVS ownership driver |
| [intel/ipu7-camera-bins](https://github.com/intel/ipu7-camera-bins) | `403c67db6b279dd02752f11db6a34552f31a3ac5` | Intel's redistributable IPU75XA userspace interface |
| [intel/ipu7-camera-hal](https://github.com/intel/ipu7-camera-hal) | `b1f6ebef12111fb5da0133b144d69dd9b001836c` | Hardware ISP HAL and sensor configuration |
| [intel/icamerasrc](https://github.com/intel/icamerasrc) | `4fb31db76b618aae72184c59314b839dedb42689` | GStreamer source consumed by `v4l2-relayd` |

The PSYS patch is deliberately limited to the companion module: it removes an
out-of-tree debugfs structure member that is not present in Linux 7.1's stock
IPU7 core and prevents DKMS from compiling or installing base/ISYS. Camera
source or build failures are non-fatal to the rest of Ansible and are recorded
in `/var/lib/xps-hardware/ipu7/build-failed.log`.

### Secure Boot and kernel updates

DKMS and RPM Fusion akmods share `/etc/pki/akmods`. With Secure Boot enabled,
enroll that public key once:

```bash
sudo mokutil --import /etc/pki/akmods/certs/public_key.der
```

Choose a temporary password, reboot, and use the firmware MOK manager to enroll
the key. Then rerun `./update --full --tags xps-2026`. The role does not disable
Secure Boot. A DKMS update made while old camera modules are loaded is not
force-unloaded: the camera stops, stays enabled, and starts with the new signed
modules after one normal reboot.

`kernel-devel-matched` keeps builds tied to Fedora's installed kernel. Diagnose
the complete path with:

```bash
dkms status
modinfo -n intel_ipu7 intel_ipu7_isys intel_ipu7_psys intel_cvs
systemctl status xps-ipu7-camera xps-ipu7-camera-init v4l2-relayd@ipu7
journalctl -k -b | grep -Ei 'ipu7|intel_cvs|ov08x40'
/usr/local/libexec/xps-ipu7-camera-check
```

The normal check does not turn on the camera. To request a short three-frame
smoke test explicitly:

```bash
XPS_CAMERA_FRAME_TEST=1 /usr/local/libexec/xps-ipu7-camera-check
```

The suspend hook stops only the userspace relay before sleep and restarts it
after resume; it avoids fragile module unload/reprobe operations.

## Haptic touchpad

The existing Fedora controller power rules are retained. The hardware-specific
daemon now pairs the matching 06CB input and hidraw devices, applies both the
surface/physical-button feature and a configurable intensity, retries across
device disappearance/re-enumeration, responds to config changes, and reapplies
after physical clicks. It reads HID features back when the transport supports
that operation; this XPS firmware may expose them as write-only.

Set `xps_2026_haptic_intensity` to `low`, `mid`, or `high` in inventory. These
map to the controller's values 10, 50, and 100. Check it with:

```bash
systemctl status xps-haptic-touchpad
sudo /usr/local/libexec/xps-haptic-touchpad --check
journalctl -u xps-haptic-touchpad -b
```

## Media, firmware, and wireless regulation

The role explicitly installs SOF/audio, Intel GPU/VSC/Wi-Fi firmware, the Intel
media driver, oneVPL's `libvpl` dispatcher and `intel-vpl-gpu-rt`, and
`wireless-regdb`. It does not add `libvpl-devel` solely for runtime support;
source-build dependencies for the hardware-gated camera RPM are installed only
when that camera is detected.

Fedora's `/usr/sbin/setregdomain` derives the regulatory country from the
configured `Europe/Amsterdam` timezone; no Arch-style override is installed.
`./verify` requires the effective global and self-managed phy domains to be
`NL`. Wi-Fi 7/EHT remains enabled.

## Intentional stock-kernel gap

Omarchy Quattro's Panther Lake kernel and its three display patches are not
ported. Until equivalent code reaches Fedora's normal kernel, Panel Replay and
VRR behavior may lag Quattro. Closing that display-only gap would require the
custom kernel work explicitly excluded by this repository; speaker, camera,
touchpad, media firmware, and regulatory support do not require it.
