--- Lokkestiiz — Sunspire boss 1 (Ice)
---
--- Phase SS-2: Cross-trial alerts delegated from SunspireCommon
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

-- Boss name must match GetUnitName("boss1") exactly (used for name-based detection).
local Lokke = {
    id  = 1,
    key = "lokke",
    name = "Lokkestiiz",
    -- hmHealthThreshold: needs field measurement (skip HM detection for now)
}

-- Phase 4.2-style CA helpers (added in Phase SS-3 along with alertList).
-- Stubs here keep the module loadable without errors now.
Lokke.alertList = {}

function Lokke:reset(forced)
    -- Phase SS-3: reset IceTomb state, laser/landing timers, alertList
    for _, cid in pairs(self.alertList) do
        if CombatAlerts and cid then CombatAlerts.CastAlertsStop(cid) end
    end
    self.alertList = {}
end

-- Phase SS-2/SS-3: onCombatEvent, onEffectChanged, onUpdate added here
-- function Lokke:onCombatEvent(...) end
-- function Lokke:onEffectChanged(...) end
-- function Lokke:onUpdate(...) end

return Lokke
