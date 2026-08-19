local mainMod = "SUPER"
local terminal = "kitty"
local browser = "google-chrome-stable --enable-features=TouchpadOverscrollHistoryNavigation,PipeWireCamera --restore-last-session --hide-crash-restore-bubble"
local home = os.getenv("HOME")

local previous = rawget(_G, "__fedora_hypr_binds") or {}
for _, keybind in ipairs(previous) do
  if keybind and keybind.remove then keybind:remove()
  elseif keybind and keybind.unbind then keybind:unbind() end
end
_G.__fedora_hypr_binds = {}

local function bind(keys, dispatcher, opts)
  hl.unbind(keys)
  local keybind = hl.bind(keys, dispatcher, opts)
  table.insert(_G.__fedora_hypr_binds, keybind)
  return keybind
end

local function send_shortcut_once(mods, key)
  hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down" }))
  hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up" }))
end

bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal))
bind(mainMod .. " + SHIFT + F", hl.dsp.exec_cmd(terminal .. " -e " .. home .. "/.local/bin/dev-fedora-shell"))
bind(mainMod .. " + SHIFT + A", hl.dsp.exec_cmd(terminal .. " -e " .. home .. "/.local/bin/dev-arch-shell"))
bind(mainMod .. " + SHIFT + D", hl.dsp.exec_cmd(terminal .. " -e " .. home .. "/.local/bin/dev-debian-shell"))
bind(mainMod .. " + SPACE", hl.dsp.exec_cmd("qs ipc call launcher toggle"))
bind(mainMod .. " + comma", hl.dsp.exec_cmd("qs ipc call settings toggle"))
-- Shell surfaces the menubar also opens by click. Documented in the shell's
-- own cheatsheet (Common/Session.qml), which is what Super+K raises.
bind(mainMod .. " + N", hl.dsp.exec_cmd("qs ipc call popouts toggle notifications"))
bind(mainMod .. " + A", hl.dsp.exec_cmd("qs ipc call popouts toggle control"))
bind(mainMod .. " + K", hl.dsp.exec_cmd("qs ipc call session keys"))
bind(mainMod .. " + E", hl.dsp.exec_cmd("nautilus --new-window"))
bind(mainMod .. " + B", hl.dsp.exec_cmd(browser))
bind(mainMod .. " + SHIFT + B", hl.dsp.exec_cmd(browser .. " --incognito"))
bind(mainMod .. " + M", hl.dsp.exec_cmd(browser .. " --app=https://app.slack.com/client/T0AF1HJGFAP/C0AF4GFJY4V"))
bind(mainMod .. " + P", hl.dsp.exec_cmd(home .. "/.local/bin/portal-launcher"))
bind(mainMod .. " + S", hl.dsp.exec_cmd("spotify"))
bind(mainMod .. " + SHIFT + SLASH", hl.dsp.exec_cmd("1password"))
bind(mainMod .. " + D", hl.dsp.exec_cmd(terminal .. " -e lazydocker"))
bind(mainMod .. " + T", hl.dsp.exec_cmd("t3code-desktop"))
bind(mainMod .. " + SHIFT + T", hl.dsp.exec_cmd(terminal .. " -e btop"))
bind(mainMod .. " + W", hl.dsp.exec_cmd(browser .. " --app=https://web.whatsapp.com/"))
bind(mainMod .. " + Y", hl.dsp.exec_cmd(browser .. " --app=https://youtube.com/"))
bind(mainMod .. " + SHIFT + P", hl.dsp.exec_cmd(browser .. " --app=https://photos.google.com/"))
bind(mainMod .. " + SHIFT + X", hl.dsp.exec_cmd(browser .. " --app=https://x.com/"))
bind(mainMod .. " + CTRL + X", hl.dsp.exec_cmd("voxtype --model base --language en record toggle"))
bind("F9", hl.dsp.exec_cmd("voxtype --model base --language en record toggle"))
bind("SHIFT + F9", hl.dsp.exec_cmd("voxtype --model base --language nl record toggle"))

bind(mainMod .. " + C", function() send_shortcut_once("CTRL", "Insert") end)
bind(mainMod .. " + V", function() send_shortcut_once("SHIFT", "Insert") end)
bind(mainMod .. " + X", function() send_shortcut_once("CTRL", "X") end)
bind(mainMod .. " + SHIFT + V", hl.dsp.exec_cmd(home .. "/.local/bin/clipboard-image-to-file"))

bind(mainMod .. " + Q", hl.dsp.window.close())
bind(mainMod .. " + F", hl.dsp.window.float({ action = "toggle" }))
bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))
bind(mainMod .. " + BACKSPACE", hl.dsp.window.set_prop({ prop = "alpha", value = "0.85 toggle" }))
bind(mainMod .. " + SHIFT + M", hl.dsp.exit())
bind(mainMod .. " + L", hl.dsp.exec_cmd("hyprlock --config " .. home .. "/.config/hypr/hyprlock.conf --immediate-render --no-fade-in"))

for _, direction in ipairs({ "left", "right", "up", "down" }) do
  bind(mainMod .. " + " .. direction, hl.dsp.focus({ direction = direction }))
end
for i = 1, 10 do
  local key = i % 10
  bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
  bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end
bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

bind(mainMod .. " + grave", hl.dsp.exec_cmd(home .. "/.local/bin/screenshot region"))
bind(mainMod .. " + SHIFT + grave", hl.dsp.exec_cmd(home .. "/.local/bin/screen-record"))
bind("Print", hl.dsp.exec_cmd(home .. "/.local/bin/screenshot region"))
bind("SHIFT + Print", hl.dsp.exec_cmd(home .. "/.local/bin/screenshot fullscreen"))
bind(mainMod .. " + SHIFT + O", hl.dsp.exec_cmd(home .. "/.local/bin/screen-ocr"))

bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("/usr/local/libexec/xps-speaker-tuning control up || wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("/usr/local/libexec/xps-speaker-tuning control down || wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true, repeating = true })
bind("XF86MonBrightnessUp", hl.dsp.exec_cmd(home .. "/.local/bin/brightness-control up 5"), { locked = true, repeating = true })
bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(home .. "/.local/bin/brightness-control down 5"), { locked = true, repeating = true })
bind("XF86AudioMute", hl.dsp.exec_cmd("/usr/local/libexec/xps-speaker-tuning control mute || wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
bind("XF86AudioMicMute", hl.dsp.exec_cmd("voxtype --model base --language en record toggle"), { locked = true })
bind("SHIFT + XF86AudioMicMute", hl.dsp.exec_cmd("voxtype --model base --language nl record toggle"), { locked = true })
bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })
bind("XF86Calculator", hl.dsp.exec_cmd("gnome-calculator"), { locked = true })
bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
bind(mainMod .. " + SHIFT + mouse:272", hl.dsp.window.resize(), { mouse = true })
