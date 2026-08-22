--- Nahviintaas — Sunspire boss 3 (Lightning / Portal)
---
--- Phase SS-2: Cross-trial alerts delegated from SunspireCommon
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

local Nahvii = {
    id  = 3,
    key = "nahvii",
    name = "Nahviintaas",
    -- hmHealthThreshold: needs field measurement
}

Nahvii.alertList  = {}
Nahvii.inPortal   = false

function Nahvii:reset(forced)
    -- Phase SS-5: reset all timers, portal state, meteor tracking, alertList
    self.inPortal = false
    for _, cid in pairs(self.alertList) do
        if CombatAlerts and cid then CombatAlerts.CastAlertsStop(cid) end
    end
    self.alertList = {}
end

-- Phase SS-2/SS-5: onCombatEvent, onEffectChanged, onUpdate added here
-- function Nahvii:onCombatEvent(...) end
-- function Nahvii:onEffectChanged(...) end
-- function Nahvii:onUpdate(...) end

return Nahvii
