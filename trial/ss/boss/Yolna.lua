--- Yolnahkriin — Sunspire boss 2 (Fire)
---
--- Phase SS-2: Cross-trial alerts via SunspireCommon
---             (HA, Block/Leap, ShieldCharge, Breath, FireSpit)
--- Phase SS-4: Yolna-specific mechanics
---   - AtroSpawn (119549): BEGIN → "Kill Atro!" 4.5 s
---   - LavaGeyser (124546): player or nearby group (dist ≤ 2.8) → Dodge! bar
---   - NextFlare timer (121722/121459): 32 s / 30 s; 6 s at fight start
---   - Cataclysm (122598): duration bar + landing timer (+6.8 s after cast ends)
---   - TakeFlight (124910/915/916): track flight # for landing calculation
---   - Boss HP thresholds: 76% / 51% / 26% → "Can fly in X%" display

local SunspireCommon = require("trial.ss.SunspireCommon")

local Yolna = {
    id   = 2,
    key  = "yolna",
    name = "Yolnahkriin",
    -- hmHealthThreshold: needs field measurement
}

Yolna.alertList = {}

function Yolna:reset(forced)
    -- Phase SS-4: reset Cata/NextFlare/landing timers
    for _, cid in pairs(self.alertList) do
        if CombatAlerts and cid then CombatAlerts.CastAlertsStop(cid) end
    end
    self.alertList = {}
end

function Yolna:onCombatEvent(context, alerts, result, abilityId,
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

    -- Phase SS-4: AtroSpawn, LavaGeyser, NextFlare, Cata, TakeFlight
end

-- Phase SS-4: onUpdate for NextFlare / landing countdown and HP "can fly" display
-- function Yolna:onUpdate(context, alerts) end

return Yolna
