--- core/Fmt.lua  -  ESO color-markup helpers.
---
--- Keeps |cRRGGBB...|r codes out of the string table and call sites.
--- Colors are expressed as plain 6-char hex strings; markup is built here.
---
--- Usage:
---   local Fmt = require("core.Fmt")
---
---   Fmt.c(Fmt.RED, "INC")          -- "|cff0000INC|r"
---   Fmt.c("ff6030", "Blitz: 12s")  -- inline hex also accepted
---
---   -- Alternating (color, text) pairs:
---   Fmt.colored(Fmt.CYAN, "Ice Tomb", Fmt.RED, " 2 INC")

local Fmt = {}

-- ── Common semantic colors ────────────────────────────────────────────────────
-- Use these for cross-trial reusable semantics.  Trial-specific or one-off
-- colors belong as local constants in the encounter file that uses them.

Fmt.RED    = "ff0000"   -- danger / critical / INC
Fmt.ORANGE = "ff8800"   -- caution / amber
Fmt.YELLOW = "ffdd00"   -- warning / gold
Fmt.GREEN  = "00ff00"   -- success / ready / clear
Fmt.CYAN   = "00ffff"   -- ice / aqua label
Fmt.AQUA   = "7fffd4"   -- aquamarine / soft info
Fmt.GOLD   = "FFD700"   -- addon tag / golden accent

-- ── API ──────────────────────────────────────────────────────────────────────

--- Wrap text in a single ESO color segment.
--- @param color string  6-char hex color code, e.g. "ff0000"
--- @param text  string  text to color
--- @return string       "|cCOLORtext|r"
function Fmt.c(color, text)
    return "|c" .. color .. tostring(text) .. "|r"
end

--- Build a multi-segment colored string from alternating (color, text) pairs.
--- Fmt.colored(Fmt.CYAN, "Ice Tomb", Fmt.RED, " 2 INC")
--- → "|c00ffffIce Tomb|r|cff0000 2 INC|r"
--- An odd trailing arg (color without text) is silently ignored.
function Fmt.colored(...)
    local args = { ... }
    local parts = {}
    for i = 1, #args - 1, 2 do
        parts[#parts + 1] = "|c" .. args[i] .. tostring(args[i + 1]) .. "|r"
    end
    return table.concat(parts)
end

--- Format a timer value as a human-readable string.
--- Keeps %.Nf specifiers out of the string table.
--- Fmt.timer(3.7)    → "4s"   (0 decimals, default)
--- Fmt.timer(3.7, 1) → "3.7s"
function Fmt.timer(n, d)
    return string.format("%." .. (d or 0) .. "f", n) .. "s"
end

--- Format a percentage value as a human-readable string.
--- Keeps %.Nf%% specifiers out of the string table.
--- Fmt.pct(54.3)     → "54%"  (0 decimals, default)
--- Fmt.pct(37.5, 1)  → "37.5%"
function Fmt.pct(n, d)
    return string.format("%." .. (d or 0) .. "f%%", n)
end

package.loaded["core.Fmt"] = Fmt
return Fmt
