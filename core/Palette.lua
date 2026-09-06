--- core/Palette.lua  -  Single source of truth for all colours in the addon.
---
--- Colors are defined once as linear RGB (0–1). Consumers never see raw
--- values — they receive the format their layer needs:
---
---   Fmt.c(Palette.FIRE, text)                    -- hex string, built here
---   CA.alertCast(id, name, dur, Palette.CA_FIRE)  -- CA table, built here
---
--- To add a colour: add one entry to `def`. The hex constant and any CA
--- presets that reference it update automatically.
---
--- CA table layout (for reference — callers never construct these):
---   { timing, dodge_text, interruptible, bg_rgba, fg_rgba }
---   timing      = -1 (CA auto-detects melee vs projectile from GetAbilityRange)
---   dodge_text  =  0 (no "Dodge!" overlay — use CA.alert for that)
---   interruptible: true = interrupt-prompt styling, false = normal cast bar

local Palette = {}

-- ── Colour definitions ────────────────────────────────────────────────────
-- Linear RGB (0–1).  One entry per logical colour; never referenced outside
-- this file.  Hex constants and CA presets are derived automatically below.

local def = {
    -- Elemental
    FIRE      = { 1.00, 0.35, 0.10 },   -- fire orange  (stomp / slam / blast)
    ICE       = { 0.30, 0.75, 1.00 },   -- frost blue   (ice cast / freeze)
    LIGHTNING = { 0.90, 0.90, 0.10 },   -- electric     (shock / surge / arc)
    VOID      = { 0.70, 0.20, 0.90 },   -- void / arcane purple
    POISON    = { 0.40, 0.80, 0.40 },   -- poison green (dot / corrosion)

    -- Semantic
    RED       = { 1.00, 0.00, 0.00 },   -- danger / critical / INC
    ORANGE    = { 1.00, 0.53, 0.00 },   -- caution / amber
    YELLOW    = { 1.00, 0.87, 0.00 },   -- warning / gold
    GREEN     = { 0.00, 1.00, 0.00 },   -- success / ready / clear
    CYAN      = { 0.00, 1.00, 1.00 },   -- ice / aqua label
    AQUA      = { 0.50, 1.00, 0.83 },   -- aquamarine / soft info
    GOLD      = { 1.00, 0.84, 0.00 },   -- addon tag / golden accent
    PURPLE    = { 0.80, 0.50, 1.00 },   -- light purple / arcane accent

    -- Accent
    AMBER     = { 1.00, 0.67, 0.27 },   -- warm amber (LC mechanics / phases)
    ARCANE    = { 0.67, 0.27, 1.00 },   -- deep arcane (manifold / curse)
    TEAL      = { 0.46, 0.90, 0.85 },   -- teal (shield / safe window)
    SKY       = { 0.22, 0.74, 0.97 },   -- sky-blue (portal label / teleport)
    SMOKE     = { 0.48, 0.51, 0.63 },   -- slate (in-progress / neutral timer)
    GRAY      = { 0.53, 0.53, 0.53 },   -- gray (count / secondary info)
    PINK      = { 1.00, 0.40, 0.40 },   -- pink-red (soft warning)
    CRIMSON   = { 0.80, 0.27, 0.27 },   -- dark red (fail / hard stop)
    LEAF      = { 0.33, 0.67, 0.33 },   -- medium green (skip / ok signal)
    LANDING   = { 0.36, 0.84, 0.36 },   -- light green (landing countdown)
    FLYZONE   = { 1.00, 0.65, 0.00 },   -- orange (fly-in / enter threshold)
}

-- ── Hex builder ───────────────────────────────────────────────────────────

local function toHex(rgb)
    return string.format("%02x%02x%02x",
        math.floor(rgb[1] * 255 + 0.5),
        math.floor(rgb[2] * 255 + 0.5),
        math.floor(rgb[3] * 255 + 0.5))
end

-- Expose every colour as a hex string for Fmt.c.
-- Palette.FIRE = "ff591a", Palette.ICE = "4dbfff", etc.
for name, rgb in pairs(def) do
    Palette[name] = toHex(rgb)
end

-- ── CA table builders ─────────────────────────────────────────────────────

--- Cast bar: player must dodge or move when it fires.
--- timing = -1: CA auto-detects bar duration from ability range
---   melee  (range <= 700): dodgeDuration
---   ranged (range >  700): dodgeDuration * projectileTimingAdjustment
function Palette.cast(name)
    local c = def[name]
    return { -1, 0, false, { c[1], c[2], c[3], 0.4 }, { c[1], c[2], c[3], 0.8 } }
end

--- Interruptible cast bar: player should interrupt before it fires.
function Palette.interrupt(name)
    local c = def[name]
    return { -1, 0, true, { c[1], c[2], c[3], 0.4 }, { c[1], c[2], c[3], 0.8 } }
end

-- ── Pre-built CA presets ──────────────────────────────────────────────────
-- Common cross-trial combinations.  Add a preset here when the same
-- colour+intent pair appears in two or more encounters.

Palette.CA_FIRE      = Palette.cast("FIRE")       -- fire stomp / slam / blast
Palette.CA_ICE       = Palette.cast("ICE")        -- frost cast / freeze
Palette.CA_LIGHTNING = Palette.cast("LIGHTNING")  -- shock / surge / arc
Palette.CA_VOID      = Palette.cast("VOID")       -- void / arcane cast
Palette.CA_ORANGE    = Palette.cast("ORANGE")     -- heavy melee / solar
Palette.CA_CLEAVE    = Palette.cast("RED")        -- red cleave / execute
Palette.CA_INTERRUPT = Palette.interrupt("ICE")   -- interruptible (blue bar)

package.loaded["core.Palette"] = Palette
return Palette
