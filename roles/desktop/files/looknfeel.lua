hl.config({
  general = {
    gaps_in = 5,
    gaps_out = 10,
    border_size = 0,
    layout = "dwindle",
    col = { active_border = "rgb(131419)", inactive_border = "rgb(131419)" },
  },
  cursor = { no_hardware_cursors = false },
  decoration = {
    rounding = 10,
    blur = { enabled = true, size = 3, passes = 1 },
    shadow = { enabled = true, range = 4, render_power = 3, color = "rgba(1a1a1aee)" },
  },
  animations = { enabled = true },
  misc = { force_default_wallpaper = 0, disable_hyprland_logo = true, focus_on_activate = false },
  xwayland = { force_zero_scaling = true },
  group = {
    col = {
      border_active = "rgb(9ecbeb)", border_inactive = "rgb(131419)",
      border_locked_active = "rgb(e8837a)", border_locked_inactive = "rgb(131419)",
    },
    groupbar = { col = {
      active = "rgb(9ecbeb)", inactive = "rgb(131419)",
      locked_active = "rgb(e8837a)", locked_inactive = "rgb(131419)",
    } },
  },
  dwindle = { preserve_split = true, split_width_multiplier = 1.0 },
})

hl.curve("myBezier", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.05 } } })
hl.animation({ leaf = "windows", enabled = true, speed = 7, bezier = "myBezier" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 7, bezier = "default", style = "popin 80%" })
hl.animation({ leaf = "border", enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "borderangle", enabled = true, speed = 8, bezier = "default" })
hl.animation({ leaf = "fade", enabled = true, speed = 7, bezier = "default" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 6, bezier = "default" })

hl.window_rule({ match = { class = [[xdg-desktop-portal-gtk]] }, float = true })
hl.window_rule({ match = { class = [[org\.gnome\.Nautilus]], title = [[Properties]] }, float = true })
hl.window_rule({ match = { class = [[org\.gnome\.Nautilus]], title = [[Open.*]] }, float = true })
hl.window_rule({ match = { class = [[org\.gnome\.Nautilus]], title = [[Save.*]] }, float = true })
hl.workspace_rule({ workspace = "m[desc:GIGA-BYTE TECHNOLOGY CO. LTD. AORUS FO32U2] w[t1]", gaps_out = { top = 10, right = 480, bottom = 10, left = 480 } })
hl.workspace_rule({ workspace = "m[desc:Apple Computer Inc Studio XDR] w[t1]", gaps_out = { top = 10, right = 320, bottom = 10, left = 320 } })
hl.window_rule({ match = { class = [[.*]] }, suppress_event = "maximize" })
hl.window_rule({ match = { class = [[.*]] }, opacity = "1.0 1.0" })
hl.window_rule({ match = { class = [[1[pP]assword]] }, float = true, center = true, size = { 875, 600 }, no_screen_share = true })
hl.window_rule({ match = { class = [[org\.gnome\.NautilusPreviewer]] }, float = true, center = true, size = { "60%", "70%" } })
hl.window_rule({ match = { class = [[localsend_app]] }, float = true, center = true, size = { 875, 600 } })
hl.window_rule({ match = { class = [[org\.gnome\.Calculator]] }, float = true })
hl.window_rule({ match = { class = [[(imv|mpv)]] }, float = true, center = true })
hl.window_rule({ match = { class = [[google-chrome]], title = [[^Notification.*]] }, float = true, no_initial_focus = true, pin = true })
hl.window_rule({ match = { class = [[(vlc|mpv|imv|zoom)]] }, opacity = "1 1" })
