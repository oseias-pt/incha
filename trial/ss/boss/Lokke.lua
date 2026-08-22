--- Lokkestiiz — Sunspire boss 1 (Ice)
---
--- Phase SS-2: Cross-trial alerts via SunspireCommon
---             (HA, Block/Leap, ShieldCharge, Breath, FireSpit)
--- Phase SS-3: Lokke-specific mechanics
---   - GlacialFist (120838): countdown list, player or nearby group (dist ≤ 4.5)
---   - IceTomb state machine (119632 + effects 124687/119638):
---       2-slot state (cast→armed→taken→cleared), double-tomb detection
---   - InIce (116044): EFFECT_GAINED/FADED → which player holds which tomb
---   - LokkeLaser (122820/822/821): 3 flight patterns, hardcoded landing times
---       #1: laser 40 s → landing +12.8 s
---       #2: laser 10 s → landing +54.6 s
---       #3: laser 32 s → landing +32.1 s
---   - Boss HP thresholds: 81% / 51% / 21% → "Can fly in X%" display

local SunspireCommon = require("trial.ss.SunspireCommon")

local Lokke = {
    id   = 1,
    key  = "lokke",
    name = "Lokkestiiz",
    -- hmHealthThreshold: needs field measurement
}

-- Phase SS-3: alertList stores [unitId] → CA cast bar ID for GlacialFist bars.
Lokke.alertList = {}

function Lokke:reset(forced)
    -- Phase SS-3: reset IceTomb state, laser/landing timers
    for _, cid in pairs(self.alertList) do
        if CombatAlerts and cid then CombatAlerts.CastAlertsStop(cid) end
    end
    self.alertList = {}
end

function Lokke:onCombatEvent(context, alerts, result, abilityId,
                              unitTag, sourceUnitTag, sourceUnitId, unitId,
                              sourceUnitName, unitName)
    -- Phase SS-2: cross-trial alerts (HA, Block, Leap, Charge, Breath, Spit)
    if SunspireCommon.handle(alerts, result, abilityId, unitTag, sourceUnitName) then
        return
    end

    -- alertList cleanup on unit death
    if result == ACTION_RESULT_DIED then
        if unitId then
            if CombatAlerts and self.alertList[unitId] then
                CombatAlerts.CastAlertsStop(self.alertList[unitId])
            end
            self.alertList[unitId] = nil
        end
        return
    end

    -- Phase SS-3: GlacialFist, IceTomb, LokkeLaser, HP thresholds
end

-- Phase SS-3: onEffectChanged for IceTomb effects 124687 / 119638
-- function Lokke:onEffectChanged(context, alerts, changeType, abilityId, unitTag, unitId, unitName)
-- end

-- Phase SS-3: onUpdate for landing/laser countdown and HP "can fly" display
-- function Lokke:onUpdate(context, alerts) end

return Lokke
