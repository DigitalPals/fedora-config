local xdg = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
local config_dir = xdg .. "/hypr"
package.path = config_dir .. "/?.lua;" .. config_dir .. "/?/init.lua;" .. package.path

for _, module in ipairs({ "monitors", "input", "bindings", "looknfeel", "autostart" }) do
  package.loaded[module] = nil
end

require("monitors")
require("input")
require("bindings")
require("looknfeel")
require("autostart")
