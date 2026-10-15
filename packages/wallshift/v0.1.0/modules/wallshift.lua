-- Wallshift integration for Hyprland Lua

local wallshift = {}

function wallshift.setup(hl)
    local home = os.getenv("HOME")

    hl.on("hyprland.start", function()
        hl.exec_cmd(
            "sh -lc '" .. home ..
            "/.local/bin/wallshift --shuffle --interval 10m >> /tmp/wallshift.log 2>&1 &'"
        )
    end)
end

return wallshift
