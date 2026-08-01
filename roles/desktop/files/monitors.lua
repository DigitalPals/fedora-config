-- XPS internal panel and known external display policy.
hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = "auto" })
hl.monitor({
  output = "desc:GIGA-BYTE TECHNOLOGY CO. LTD. AORUS FO32U2",
  mode = "3840x2160@120", position = "auto", scale = "auto",
})
hl.monitor({
  output = "desc:Apple Computer Inc Studio XDR",
  mode = "preferred", position = "auto", scale = "auto",
  bitdepth = 8, cm = "srgb", vrr = 0,
})
hl.monitor({
  output = "desc:Apple Computer Inc Pro Display XDR",
  mode = "preferred", position = "auto", scale = "auto",
  bitdepth = 8, cm = "srgb", vrr = 0,
})
hl.monitor({
  output = "desc:Nreal XREAL One Pro",
  mode = "1920x1080@120", position = "auto", scale = "auto", vrr = 0,
})
hl.monitor({
  output = "desc:XREAL XREAL One Pro",
  mode = "1920x1080@120", position = "auto", scale = "auto", vrr = 0,
})

for _, display in ipairs({
  "desc:GIGA-BYTE TECHNOLOGY CO. LTD. AORUS FO32U2",
  "desc:Apple Computer Inc Studio XDR",
  "desc:Apple Computer Inc Pro Display XDR",
  "desc:Nreal XREAL One Pro",
  "desc:XREAL XREAL One Pro",
}) do
  hl.workspace_rule({ workspace = "1", monitor = display, default = true })
end

hl.env("GDK_SCALE", "2")
