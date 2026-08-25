--- Bridge — documented no-op base for the five lifecycle hooks Trial uses.
---
--- Trial.create defaults to BridgeBase when no bridge option is supplied,
--- so every hook can be called unconditionally — no nil-guard needed in
--- Trial.lua.
---
--- Panel.bridge is wrapped with BridgeBase.extend so it inherits the no-op
--- for any hook it doesn't override (currently checkHardmode).

local BridgeBase = {}
BridgeBase.__index = BridgeBase

--- Called when the trial zone is entered and the trial is enable()d.
function BridgeBase.onEnable() end

--- Called when the trial is disable()d (zone exit, settings off).
function BridgeBase.onDisable() end

--- Called when a boss becomes active (after BossRegistry detects it).
--- @param boss  table   the fresh boss instance
--- @param ctx   table   TrialContext
function BridgeBase.onBossEnter(boss, ctx) end

--- Called when the active boss is cleared (wipe, death, zone change).
function BridgeBase.onBossExit() end

--- Called on every onPowerUpdate tick while out of combat, so the bridge
--- can verify / update HM state (e.g. compare max HP against hmThreshold).
--- @param ctx table   TrialContext
function BridgeBase.checkHardmode(ctx) end

--- Wrap a plain handler table so BridgeBase provides no-op defaults for any
--- hook the table does not override.
function BridgeBase.extend(impl)
    return setmetatable(impl, BridgeBase)
end

return BridgeBase
