--- core/Colors.lua  -  Colour palette: the single source of truth.
---
--- Defines named colours and their linear RGB (0-1) values.
--- Boss files only ever reference colours by name:
---
---   local Colors = require("core.Colors")
---   CA.melee(id, name, dur, Colors.FIRE)
---   Fmt.c(Colors.PURPLE, "next curse")
---
--- Layers (Fmt, CombatAlerts, MechanicIcons, PositionIcons) import the
--- RGB table via Colors.build() to pre-compute their own lookup tables
--- at module-load time, giving O(1) name→native-format conversion.
--- Boss files never call Colors.build() or read Colors._rgb.

local Colors = {}

-- ── Colour definitions ─────────────────────────────────────────────────────
-- Linear RGB (0-1).  One entry per logical colour; never read by boss files.

local _rgb = {
    -- Elemental
    FIRE      = { 1.00, 0.35, 0.10 },   -- fire orange  (stomp / slam / blast)
    ICE       = { 0.30, 0.75, 1.00 },   -- frost blue   (ice cast / freeze)
    LIGHTNING = { 0.90, 0.90, 0.10 },   -- electric     (shock / surge / arc)
    VOID      = { 0.70, 0.20, 0.90 },   -- void / arcane purple
    POISON    = { 0.40, 0.80, 0.40 },   -- poison green (dot / corrosion)

    -- Semantic
    RED       = { 1.00, 0.00, 0.00 },   -- danger / critical / INC
    ORANGE    = { 1.00, 0.53, 0.00 },   -- caution
    YELLOW    = { 1.00, 0.87, 0.00 },   -- warning / gold
    GREEN     = { 0.00, 1.00, 0.00 },   -- success / ready / clear
    CYAN      = { 0.00, 1.00, 1.00 },   -- aqua label
    AQUA      = { 0.50, 1.00, 0.83 },   -- aquamarine (laser / portal labels)
    GOLD      = { 1.00, 0.84, 0.00 },   -- addon tag / golden accent
    PURPLE    = { 0.80, 0.50, 1.00 },   -- light purple / arcane accent
    FROST     = { 0.60, 0.80, 1.00 },   -- light frost blue (paired-boss ice-side)

    -- Accent
    AMBER     = { 1.00, 0.67, 0.27 },   -- warm amber (LC mechanics / phases)
    ARCANE    = { 0.67, 0.27, 1.00 },   -- deep arcane (manifold / curse)
    TEAL      = { 0.46, 0.90, 0.85 },   -- teal (shield / safe window)
    SKY       = { 0.22, 0.74, 0.97 },   -- sky-blue (portal label / teleport)
    SMOKE     = { 0.48, 0.51, 0.63 },   -- slate (in-progress / neutral timer)
    GRAY      = { 0.53, 0.53, 0.53 },   -- gray (count / secondary info)
    PINK      = { 1.00, 0.40, 0.40 },   -- pink-red (soft warning / fog-end)
    CRIMSON   = { 0.80, 0.27, 0.27 },   -- dark red (fail / hard stop)
    LEAF      = { 0.33, 0.67, 0.33 },   -- medium green (skip / ok signal)
    LANDING   = { 0.36, 0.84, 0.36 },   -- light green (landing countdown)
    FLYZONE   = { 1.00, 0.65, 0.00 },   -- orange (fly-in / enter threshold)
}

-- ── Enum ───────────────────────────────────────────────────────────────────
-- Each name is exported as a string constant equal to itself so boss
-- files get type-safe, autocomplete-friendly colour references.
-- Colors.FIRE == "FIRE", Colors.ICE == "ICE", etc.

for name in pairs(_rgb) do
    Colors[name] = name
end

-- ── Layer builder ──────────────────────────────────────────────────────────
--- Build a lookup table (name → value) from the RGB definitions.
--- Layers call this once at module load; boss files never call it.
---
--- @param fn function  fn(r, g, b) → value stored under Colors[name]
--- @return table        { [colorName] = fn(r,g,b), ... }
function Colors.build(fn)
    local t = {}
    for name, c in pairs(_rgb) do
        t[name] = fn(c[1], c[2], c[3])
    end
    return t
end

package.loaded["core.Colors"] = Colors
return Colors
