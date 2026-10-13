
-- Wallshift integration for Hyprland Lua
-- Starts Wallshift when the Hyprland session starts.

local wallshift = {}

function wallshift.setup(hl)
    hl.on("hyprland.start", function()
        -- Wallshift manages awww-daemon itself.
        hl.exec_cmd("wallshift --shuffle --interval 10m &")
    end)
end

return wallshift
