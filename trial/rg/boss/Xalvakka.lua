--- Xalvakka  -  Rockgrove boss 3

local AlertTypes      = require("core.AlertTypes")
local EventDispatcher = require("core.EventDispatcher")
local RockgroveCommon = require("trial.rg.RockgroveCommon")
local Lang            = require("core.Lang")
local Fmt             = require("core.Fmt")
local Log             = require("lib.Log")
local CA              = require("external-api.CombatAlerts")
local BossBase        = require("lib.BossBase")
local CastDur         = require("lib.CastDur")
local Colors          = require("core.Colors")

local SHIELD_EVENT_KEY = ADDON_PREFIX .. "RG_XalvakkaShield"

-- -- Ability IDs ------------------------------------------------------------
local SCATHING1       = 149180
local SCATHING2       = 153448
local SCATHING3       = 153450
local DEADSTAR1       = 149386
local DEADSTAR2       = 149075
local FLAMING_PORTAL  = 157390
local SOUL_RESONANCE  = 152993
local UNSTABLE_CHARGE = 153164
local MANIFOLD_DEBUFF = 157290

local SOUL_WINDOW = 9

local RUN1_TOP = 75
local RUN1_BOT = 70
local RUN2_TOP = 45
local RUN2_BOT = 40

local FALLBACK_SCATHING_DUR = 1500

local function fmtShield(v)
    if v >= 1000000 then
        return string.format("%.2fM", v / 1000000)
    elseif v >= 1000 then
        return string.format("%.1fk", v / 1000)
    else
        return tostring(math.floor(v))
    end
end

-- P6: module-level string constants — avoid Lang.t calls in onUpdate (60 fps)
local _STR_JUMP          = Fmt.c(Fmt.AMBER,  Lang.t("rg_xalvakka_next_jump"))
local _STR_JUMP_INC      = Fmt.c(Fmt.AMBER,  Lang.t("rg_xalvakka_next_jump")) .. " " .. Fmt.c(Fmt.RED, "INC")
local _STR_SOUL_RES      = Fmt.c(Fmt.ORANGE, Lang.t("rg_xalvakka_soul_res"))
local _STR_MANIFOLD_PFX  = Lang.t("rg_xalvakka_manifold")
local _STR_MANIFOLD_YOU  = Fmt.c(Fmt.ARCANE, "YOU")   -- cached; used in rebuildManifoldStr
local _STR_SHIELD_PFX    = Lang.t("rg_xalvakka_shield")
local _STR_ON_BLOB       = Fmt.c(Fmt.GREEN,  Lang.t("rg_xalvakka_on_blob"))
local _STR_RUN_IN_PFX    = Lang.t("rg_xalvakka_run_in")

local Xalvakka = {}
Xalvakka.__index = Xalvakka

Xalvakka.key               = "xalvakka"
Xalvakka.name              = "Xalvakka"
-- Health-pool threshold between NM and HM; re-verify after major patches.
Xalvakka.hmHealthThreshold = 100000001

Xalvakka.stateSchema = {
    nextJump       = 0,
    numJumps       = 0,
    shellShield    = 0,
    _shieldStr     = false,   -- cached formatted shield string; rebuilt on VISUAL_* events
    onBlob         = false,
    soulStart      = 0,
    selfManifold   = false,
    manifoldOthers = function() return {} end,
    _manifoldStr   = false,   -- cached display string; rebuilt on gained/faded events
}

function Xalvakka.new()
    return BossBase.fromSchema(Xalvakka)
end

function Xalvakka:onLeave(context)
    EVENT_MANAGER:UnregisterForEvent(SHIELD_EVENT_KEY, EVENT_UNIT_ATTRIBUTE_VISUAL_ADDED)
    EVENT_MANAGER:UnregisterForEvent(SHIELD_EVENT_KEY, EVENT_UNIT_ATTRIBUTE_VISUAL_UPDATED)
    EVENT_MANAGER:UnregisterForEvent(SHIELD_EVENT_KEY, EVENT_UNIT_ATTRIBUTE_VISUAL_REMOVED)
end

function Xalvakka:onEnter(context, alerts)
    EVENT_MANAGER:UnregisterForEvent(SHIELD_EVENT_KEY, EVENT_UNIT_ATTRIBUTE_VISUAL_ADDED)
    EVENT_MANAGER:UnregisterForEvent(SHIELD_EVENT_KEY, EVENT_UNIT_ATTRIBUTE_VISUAL_UPDATED)
    EVENT_MANAGER:UnregisterForEvent(SHIELD_EVENT_KEY, EVENT_UNIT_ATTRIBUTE_VISUAL_REMOVED)

    local function onShield(setter)
        return function(eventCode, unitTag, attributeType, powerType, value, max, poolIndex)
            local ok, err = pcall(function()
                if attributeType == ATTRIBUTE_VISUAL_POWER_SHIELDING then
                    local v = setter(value)
                    self.shellShield = v
                    -- Cache the formatted string here so showManifoldLine reads a
                    -- pre-built value rather than calling string.format every 200ms.
                    self._shieldStr = v > 0 and (_STR_SHIELD_PFX .. fmtShield(v)) or false
                end
            end)
            if not ok then Log.always("Xalvakka shield event: %s", tostring(err)) end
        end
    end

    local function register(event, handler)
        EVENT_MANAGER:RegisterForEvent(SHIELD_EVENT_KEY, event, handler)
        EVENT_MANAGER:AddFilterForEvent(SHIELD_EVENT_KEY, event,
            REGISTER_FILTER_UNIT_TAG, "reticleover")
    end

    register(EVENT_UNIT_ATTRIBUTE_VISUAL_ADDED,   onShield(function(v) return v or 0 end))
    register(EVENT_UNIT_ATTRIBUTE_VISUAL_UPDATED, onShield(function(v) return v or 0 end))
    register(EVENT_UNIT_ATTRIBUTE_VISUAL_REMOVED, onShield(function() return 0 end))
end

-- Rebuild the manifold display string from current selfManifold + manifoldOthers.
-- Called by gained/faded handlers so onUpdate reads a pre-built string instead
-- of running table.concat + Fmt.c on every 200 ms tick.
local function rebuildManifoldStr(boss)
    if not boss.selfManifold and not next(boss.manifoldOthers) then
        boss._manifoldStr = false
        return
    end
    local parts = {}
    if boss.selfManifold then
        parts[#parts + 1] = _STR_MANIFOLD_YOU
    end
    for _, name in pairs(boss.manifoldOthers) do
        parts[#parts + 1] = Fmt.c(Fmt.ARCANE, name)
    end
    boss._manifoldStr = _STR_MANIFOLD_PFX .. table.concat(parts, ", ")
end

function Xalvakka:onWipe(context, alerts)
    CA.border(false, 0, nil)
    BossBase.resetSchema(self, Xalvakka)
end

function Xalvakka:onCombatState(context, inCombat, alerts)
    if inCombat then
        self.nextJump = GetGameTimeMilliseconds() / 1000 + 35
        self.numJumps = 0
    end
end

-- -- Handlers ---------------------------------------------------------------

local function handleScathing(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    if not IsUnitPlayer(unitTag) then return end
    local dur = CastDur.get(abilityId, FALLBACK_SCATHING_DUR)
    CA.melee(abilityId, sourceUnitName, dur, Colors.MAGENTA)
end

local function handleDeadstar(boss, ctx, alerts, abilityId, ...)
    CA.alert(nil, "Deadstar!", 0xFFCC00D9, SOUNDS.CHAMPION_POINTS_COMMITTED, 2500)
end

local function handleFlamingPortal(boss, ctx, alerts, abilityId, ...)
    if not ctx.isHM then return end
    local now = GetGameTimeMilliseconds() / 1000
    boss.numJumps = boss.numJumps + 1
    boss.nextJump = now + 35
end

-- Soul Resonance: personal purge alert  -  effectChanged.gained
local function handleSoulResonanceGained(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if not AreUnitsEqual("player", unitTag) then return end
    boss.soulStart = GetGameTimeMilliseconds() / 1000
    CA.alert(nil, "Purge Soul Resonance!", 0xFF6600D9, SOUNDS.DUEL_START, 4000)
    PlaySound(SOUNDS.DUEL_START)
end

-- effectChanged.faded
local function handleSoulResonanceFaded(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if AreUnitsEqual("player", unitTag) then
        boss.soulStart = 0
    end
end

-- Unstable Charge / Blob: green border while standing on orb  -  effectChanged.gained
local function handleUnstableChargeGained(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if not AreUnitsEqual("player", unitTag) then return end
    boss.onBlob = true
    CA.border(true, 8000, "green")
end

-- effectChanged.faded
local function handleUnstableChargeFaded(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if not AreUnitsEqual("player", unitTag) then return end
    boss.onBlob = false
    CA.border(false, 0, nil)
end

-- Manifold Curse: purple border for self, name tracker for others  -  effectChanged.gained
local function handleManifoldDebuffGained(boss, ctx, alerts, abilityId, unitName, unitTag, unitId, stackCount)
    if AreUnitsEqual("player", unitTag) then
        boss.selfManifold = true
        CA.border(true, 20000, "purple")
        CA.alert(nil, Fmt.c(Fmt.ARCANE, "Manifold Curse") .. " on YOU  -  spread!",
            0xAA44FFD9, SOUNDS.DUEL_START, 5000)
        PlaySound(SOUNDS.DUEL_START)
    elseif IsUnitPlayer(unitTag) then
        boss.manifoldOthers[unitTag] =
            GetUnitDisplayName(unitTag) or unitName or "?"
    end
    rebuildManifoldStr(boss)
end

-- effectChanged.faded
local function handleManifoldDebuffFaded(boss, ctx, alerts, abilityId, unitName, unitTag, unitId, stackCount)
    if AreUnitsEqual("player", unitTag) then
        boss.selfManifold = false
        CA.border(false, 0, nil)
    else
        boss.manifoldOthers[unitTag] = nil
    end
    rebuildManifoldStr(boss)
end

-- -- Event tables ------------------------------------------------------------

local _beginCastEntry = {}
for k, v in pairs(RockgroveCommon.beginCastEntries) do _beginCastEntry[k] = v end
_beginCastEntry[SCATHING1]      = { type = AlertTypes.CUSTOM, fn = handleScathing }
_beginCastEntry[SCATHING2]      = { type = AlertTypes.CUSTOM, fn = handleScathing }
_beginCastEntry[SCATHING3]      = { type = AlertTypes.CUSTOM, fn = handleScathing }
_beginCastEntry[DEADSTAR1]      = { type = AlertTypes.CUSTOM, fn = handleDeadstar }
_beginCastEntry[DEADSTAR2]      = { type = AlertTypes.CUSTOM, fn = handleDeadstar }
_beginCastEntry[FLAMING_PORTAL] = { type = AlertTypes.CUSTOM, fn = handleFlamingPortal }

local _effectGainedEntry = {
    [SOUL_RESONANCE]  = { type = AlertTypes.CUSTOM, fn = handleSoulResonanceGained },
    [UNSTABLE_CHARGE] = { type = AlertTypes.CUSTOM, fn = handleUnstableChargeGained },
    [MANIFOLD_DEBUFF] = { type = AlertTypes.CUSTOM, fn = handleManifoldDebuffGained },
}

local _effectFadedEntry = {
    [SOUL_RESONANCE]  = { type = AlertTypes.CUSTOM, fn = handleSoulResonanceFaded },
    [UNSTABLE_CHARGE] = { type = AlertTypes.CUSTOM, fn = handleUnstableChargeFaded },
    [MANIFOLD_DEBUFF] = { type = AlertTypes.CUSTOM, fn = handleManifoldDebuffFaded },
}

-- Split into two independent copies so EventDispatcher.build() validates each
-- bucket separately and future per-bucket entries can't cross-contaminate.
local _beginCastInstant = {}
local _beginCastStarted = {}
for k, v in pairs(_beginCastEntry) do _beginCastInstant[k] = v; _beginCastStarted[k] = v end

Xalvakka.events = {
    beginCast     = { instant = _beginCastInstant, started = _beginCastStarted },
    effectChanged = { gained = _effectGainedEntry, faded = _effectFadedEntry, updated = {} },
    combatEvent   = { damage = {}, dodged = {}, blocked = {}, other = {} },
}

-- -- Tracker-row renderers ---------------------------------------------------

local function showJumpLine(self, alerts, now, isHM)
    if isHM and self.nextJump > 0 and self.numJumps < 4 then
        local T = self.nextJump - now
        if T > 0 then
            alerts:setRow(1, _STR_JUMP, T)
        else
            alerts:setRow(1, _STR_JUMP_INC, nil)
        end
    else
        alerts:clearRow(1)
    end
end

local function showSoulLine(self, alerts, now)
    if self.soulStart > 0 then
        local T = SOUL_WINDOW - (now - self.soulStart)
        if T > 0 then
            alerts:setRow(2, _STR_SOUL_RES, T)
        else
            self.soulStart = 0
            alerts:clearRow(2)
        end
    else
        alerts:clearRow(2)
    end
end

local function showManifoldLine(self, alerts)
    if self._manifoldStr then
        -- Use the string cached by rebuildManifoldStr on gained/faded events
        -- to avoid table.concat + Fmt.c allocations on every 200 ms tick.
        alerts:setRow(3, self._manifoldStr, nil)
    elseif self._shieldStr then
        -- Use the string cached by the onShield VISUAL_* handler to avoid
        -- string.format on every 200 ms tick while the shield is active.
        alerts:setRow(3, self._shieldStr, nil)
    else
        alerts:clearRow(3)
    end
end

local function showRunLine(self, alerts, context)
    local hp = context.healthPercent
    if hp and hp > RUN1_BOT and hp <= RUN1_TOP then
        alerts:setRow(4, Fmt.c(Fmt.YELLOW, _STR_RUN_IN_PFX .. Fmt.pct(hp - RUN1_BOT, 1)), nil)
    elseif hp and hp > RUN2_BOT and hp <= RUN2_TOP then
        alerts:setRow(4, Fmt.c(Fmt.YELLOW, _STR_RUN_IN_PFX .. Fmt.pct(hp - RUN2_BOT, 1)), nil)
    elseif self.onBlob then
        alerts:setRow(4, _STR_ON_BLOB, nil)
    else
        alerts:clearRow(4)
    end
end

function Xalvakka:onUpdate(context, alerts)
    local now  = GetGameTimeMilliseconds() / 1000
    local isHM = context.isHM
    showJumpLine(self, alerts, now, isHM)
    showSoulLine(self, alerts, now)
    showManifoldLine(self, alerts)
    showRunLine(self, alerts, context)
end

EventDispatcher.build(Xalvakka)

package.loaded["trial.rg.boss.Xalvakka"] = Xalvakka
return Xalvakka
