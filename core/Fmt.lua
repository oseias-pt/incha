--- core/Fmt.lua  -  ESO colour-markup and number-format helpers.
---
--- Colour constants are sourced from core/Palette and re-exported here
--- so that files which only need Fmt do not need a second require.
---
--- Usage:
---   local Fmt = require("core.Fmt")
---
---   Fmt.c(Fmt.RED, "INC")                       -- "|cff0000INC|r"
---   Fmt.c(Palette.FIRE, "Stomp inbound!")        -- via Palette directly
---   Fmt.colored(Fmt.CYAN, "Ice Tomb", Fmt.RED, " INC")

local Palette = require("core.Palette")
local Fmt = {}

-- ── Colour re-exports ─────────────────────────────────────────────────────
-- Aliases kept for files that import Fmt rather than Palette.
-- Source of truth is core/Palette.lua.

Fmt.RED    = Palette.RED
Fmt.ORANGE = Palette.ORANGE
Fmt.YELLOW = Palette.YELLOW
Fmt.GREEN  = Palette.GREEN
Fmt.CYAN   = Palette.CYAN
Fmt.AQUA   = Palette.AQUA
Fmt.GOLD   = Palette.GOLD
Fmt.PURPLE = Palette.PURPLE

-- ── API ───────────────────────────────────────────────────────────────────

--- Wrap text in a single ESO colour segment.
--- @param color string  6-char hex colour code
--- @param text  string  text to colour
--- @return string       "|cCOLORtext|r"
function Fmt.c(color, text)
    return "|c" .. color .. tostring(text) .. "|r"
end

--- Build a multi-segment coloured string from alternating (color, text) pairs.
--- Fmt.colored(Fmt.CYAN, "Ice Tomb", Fmt.RED, " 2 INC")
--- An odd trailing arg (colour without text) is silently ignored.
function Fmt.colored(...)
    local args = { ... }
    local parts = {}
    for i = 1, #args - 1, 2 do
        parts[#parts + 1] = "|c" .. args[i] .. tostring(args[i + 1]) .. "|r"
    end
    return table.concat(parts)
end

--- Format a timer value as a human-readable string.
--- Fmt.timer(3.7)    → "4s"   (0 decimals, default)
--- Fmt.timer(3.7, 1) → "3.7s"
function Fmt.timer(n, d)
    return string.format("%." .. (d or 0) .. "f", n) .. "s"
end

--- Format a percentage value as a human-readable string.
--- Fmt.pct(54.3)     → "54%"  (0 decimals, default)
--- Fmt.pct(37.5, 1)  → "37.5%"
function Fmt.pct(n, d)
    return string.format("%." .. (d or 0) .. "f%%", n)
end

package.loaded["core.Fmt"] = Fmt
return Fmt
