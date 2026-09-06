Name:           fedora-config-desktop
Version:        0.1.0
Release:        0.1.alpha%{?dist}
Summary:        Fedora Config Hyprland and Quickshell desktop
# No repository license has been selected. These are private evaluation
# artifacts; this label does not grant redistribution rights.
License:        LicenseRef-Not-Licensed
URL:            https://github.com/DigitalPals/fedora-config
Source0:        desktop.tar.gz
BuildArch:      noarch
AutoReqProv:    no
Requires:       bash coreutils util-linux systemd python3
Requires:       hyprland hyprland-guiutils quickshell hypridle hyprlock hyprpolkitagent hyprsunset
Requires:       xdg-desktop-portal-hyprland xdg-desktop-portal-gtk xdg-utils
Requires:       qt6-qtwebsockets-devel qt6-qt5compat qt6-qtsvg
Requires:       python3-pyside6 python3-websockets python3-gobject
Requires:       kitty firefox nautilus jq curl NetworkManager iw qrencode iproute iputils
Requires:       pipewire pipewire-pulseaudio wireplumber bluez brightnessctl playerctl
Requires:       gnome-keyring polkit dbus-daemon dnf5-plugins flatpak sudo
Requires:       gnome-online-accounts evolution-data-server gnome-control-center zenity
Requires:       grim slurp satty wl-clipboard cliphist wf-recorder libnotify
Requires:       ImageMagick tesseract tesseract-langpack-eng btop matugen
Requires:       btrfs-progs tar zstd
Requires:       rsms-inter-fonts google-noto-sans-fonts google-noto-color-emoji-fonts
Requires:       jetbrains-mono-fonts

%description
Shared desktop defaults, session services, and first-login welcome application.
Personal settings and overrides remain in each user's home directory.
Private alpha image integration; not a public distribution release.

%prep
%setup -q -c -n desktop

%build

%install
mkdir -p %{buildroot}
cp -a usr %{buildroot}/

%files
/usr/bin/fedora-config*
/usr/bin/hyprland-quickshell
/usr/libexec/fedora-config-*
/usr/lib/systemd/user/*.service
/usr/lib/systemd/user/hypridle.service.d/
/usr/lib/systemd/user/hyprpolkitagent.service.d/
/usr/lib/systemd/user/hyprland-session.target
/usr/share/fedora-config/
/usr/share/applications/fedora-config-welcome.desktop
/usr/share/wayland-sessions/hyprland-quickshell.desktop
/usr/share/fonts/fedora-config/
/usr/share/licenses/fedora-config-fonts/

%changelog
* Sat Sep 05 2026 Fedora Config <noreply@localhost> - 0.1.0-0.1.alpha
- Initial private live-image desktop package.
