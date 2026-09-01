--- ui/Preview.lua  -  in-game preview helpers for the Incha overlay.
--- Called from LAM panel buttons in ui/Menu.lua; no dependency on combat state.
---
--- Each function is self-contained: it builds the Panel if not already built,
--- fires the relevant UI element, then returns.  Preview.clear() undoes all
--- of them at once.

local Panel = require("ui.Panel")
local CA    = require("lib.CA")

local Preview = {}

-- -- Instability animated icon -----------------------------------------------
-- Mirrors the pattern in trial/ka/boss/Falgravn.lua so the preview uses the
-- same frame sequence and timing without coupling to that module.

local INST_FRAMES   = 40
local INST_INTERVAL = 50           -- ms per frame  (2 s full loop)
local INST_KEY      = "Incha_PreviewInstAnim"

local _instFrame  = 0
local _instActive = false
local _instDn     = nil            -- display name of the target (local player)

local function instAnimTick()
    if not OSI or not _instDn then return end
    _instFrame = (_instFrame % INST_FRAMES) + 1
    local tex = string.format("Incha/resources/instability/frame_%02d.dds",
                              _instFrame)
    if _instFrame == 1 then   -- log once per 2 s loop so chat isn't flooded
        d("[Incha] instAnimTick: dn='" .. _instDn .. "' tex=" .. tex
          .. " sz=" .. tostring(2 * OSI.GetIconSize()))
    end
    OSI.SetMechanicIconForUnit(_instDn, tex, 2 * OSI.GetIconSize())
end

local function stopInstAnim()
    if _instActive then
        EVENT_MANAGER:UnregisterForUpdate(INST_KEY)
        _instActive = false
    end
    if OSI and _instDn then
        OSI.RemoveMechanicIconForUnit(_instDn)
    end
    _instDn = nil
end

-- -- Helpers -----------------------------------------------------------------

-- Ensure the Panel controls exist (safe no-op if already built, i.e. the
-- player has already visited a trial zone this session).
local function ensurePanel()
    Panel.bridge.onEnable()
end

-- -- Public API --------------------------------------------------------------

--- Fill the overlay with realistic sample data so you can check position,
--- scale, and readability without entering combat.
function Preview.showPanel()
    ensurePanel()
    Panel.setPreviewMode(true)
    Panel.alerts.header("Falgravn [HM]")
    Panel.alerts.info(1, "Instability: 12s")
    Panel.alerts.info(2, "Blood Ball:   8s")
    Panel.alerts.action("Prison on Oseias!")
end

--- Start the animated instability icon on the local player's head.
--- Requires OdySupportIcons; silently no-ops if OSI is not installed.
--- The overlay panel is intentionally NOT shown for this preview —
--- instability is a head-icon mechanic, not a panel alert.
function Preview.showInstability()
    -- Diagnostic: dump OSI state so we can identify the failure mode.
    d("[Incha] inst: OSI=" .. tostring(OSI ~= nil)
      .. " SetMechanic=" .. tostring(OSI and OSI.SetMechanicIconForUnit ~= nil)
      .. " GetIconSize=" .. tostring(OSI and OSI.GetIconSize ~= nil))
    if not OSI then
        d("[Incha] inst: OdySupportIcons not loaded — icon unavailable")
        return
    end
    if not OSI.SetMechanicIconForUnit then
        d("[Incha] inst: OSI.SetMechanicIconForUnit missing — wrong OSI version?")
        return
    end
    local rawDn = GetUnitDisplayName and GetUnitDisplayName("player") or ""
    local dn    = string.lower(rawDn)
    d("[Incha] inst: rawDn='" .. rawDn .. "' dn='" .. dn .. "'")
    if dn == "" then
        d("[Incha] inst: empty display name — cannot set icon")
        return
    end
    stopInstAnim()
    _instDn    = dn
    _instFrame = 0
    EVENT_MANAGER:RegisterForUpdate(INST_KEY, INST_INTERVAL, instAnimTick)
    _instActive = true
    d("[Incha] inst: animation registered, first tick in " .. INST_INTERVAL .. "ms")
end

--- Flash a red CombatAlerts screen-edge border for 3 s.
--- Requires CombatAlerts; silently no-ops if CA is not installed.
function Preview.showCaBorder()
    CA.border(true, 3000, "red")
end

--- Fire a CombatAlerts text flash for 3 s.
--- Requires CombatAlerts; silently no-ops if CA is not installed.
function Preview.showCaAlert()
    CA.alert(nil, "Preview Alert!", 0xFF8800FF, SOUNDS.NONE, 3000)
end

--- Reset all preview state: stop the animation, clear the overlay,
--- and dismiss the CA border.
function Preview.clear()
    Panel.setPreviewMode(false)
    stopInstAnim()
    if Panel.bridge then Panel.bridge.onDisable() end
    CA.border(false, 0, "red")
end

package.loaded["ui.Preview"] = Preview
return Preview
