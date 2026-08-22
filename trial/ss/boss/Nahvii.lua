--- Nahviintaas — Sunspire boss 3 (Lightning / Portal)
---
--- Phase SS-2: Cross-trial alerts via SunspireCommon
---             (HA, Block/Leap, ShieldCharge, Breath, FireSpit)
--- Phase SS-5: Nahvii-specific mechanics
---   - PowerfulSlam (120542): player or nearby (dist ≤ 7); HM only; countdown list
---   - Stonefist (120567): player-targeted, dedup guard; countdown list
---   - SweepingBreath (120188 >>> / 118743 <<<): directional banner
---   - Thrash (118562): bar + nudge NextMeteor −1.5 s
---   - SoulTear (117526): hardcoded 2 s banner
---   - FireStorm (118884): skip-first dedup; 13.7 s begin/end display; landing +6.6 s
---   - NextMeteor (117251/123067 EFFECT_GAINED_DURATION / 117308 BEGIN): countdown
---   - MarkForDeath (117938): nudge NextMeteor +1.5 s
---   - Portal (121676): 14 s window countdown + 98 s wipe countdown
---   - PortalInterrupt (121436): interrupt countdown → 20 s pins countdown after bash
---   - PortalEnter/Exit (121213/121254): inPortal state; suppress HP display
---   - NegateField (121411): player-targeted → 2.5 s banner
---   - Meteor targets (117251/123067): display names on info lines
---   - Boss HP thresholds: 80% / 60% / 40% → "Can fly in X%"; suppressed in portal

local SunspireCommon = require("trial.ss.SunspireCommon")

local Nahvii = {
    id   = 3,
    key  = "nahvii",
    name = "Nahviintaas",
    -- hmHealthThreshold: needs field measurement
}

Nahvii.alertList = {}
Nahvii.inPortal  = false

function Nahvii:reset(forced)
    -- Phase SS-5: reset all timers, portal state, meteor tracking
    self.inPortal = false
    for _, cid in pairs(self.alertList) do
        if CombatAlerts and cid then CombatAlerts.CastAlertsStop(cid) end
    end
    self.alertList = {}
end

function Nahvii:onCombatEvent(context, alerts, result, abilityId,
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

    -- Phase SS-5: PowerfulSlam, Stonefist, SweepBreath, Thrash, SoulTear,
    --             FireStorm, NextMeteor, MarkForDeath, Portal, Interrupt,
    --             PortalEnter/Exit, NegateField, Meteor targets
end

-- Phase SS-5: onEffectChanged for portal debuff tracking
-- function Nahvii:onEffectChanged(context, alerts, changeType, abilityId, unitTag, unitId, unitName)
-- end

-- Phase SS-5: onUpdate for timers and HP "can fly" display
-- function Nahvii:onUpdate(context, alerts) end

return Nahvii
