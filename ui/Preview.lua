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
-- OSI head-icon limitation:
--   SetMechanicIconForUnit only renders for players in the active group frame.
--   Solo   → no group frame → call is silently ignored, nothing appears.
--   Group  → icon appears above your character, but only OTHER players can see
--            it (default camera is behind you, so your own icon is occluded).
--
-- Preview strategy:
--   • In a group  → start the animation on self; a group member can confirm
--                   the icon appears above your head.
--   • Solo        → print an explanation; nothing visible is possible.
--
-- In a real Falgravn pull the feature works correctly:
--   other players with instability → icon visible to you (they're in your group).
--   you with instability           → panel action "Instability on you!" fires.

local INST_FRAMES   = 40
local INST_INTERVAL = 50           -- ms per frame  (2 s full loop)
local INST_KEY      = "Incha_PreviewInstAnim"

local _instFrame  = 0
local _instActive = false
local _instDn     = nil

local function instAnimTick()
    if not OSI or not _instDn then return end
    _instFrame = (_instFrame % INST_FRAMES) + 1
    local tex = string.format("Incha/resources/instability/frame_%02d.dds",
                              _instFrame)
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

--- Start the animated instability OSI icon on a nearby group member.
--- Requires OdySupportIcons; silently no-ops if OSI is not installed or solo.
function Preview.showInstability()
    local didOsi = false
    if OSI and OSI.SetMechanicIconForUnit then
        local selfDn    = string.lower(GetUnitDisplayName("player") or "")
        local targetDn  = nil
        local groupSize = GetGroupSize()
        for i = 1, groupSize do
            local dn = string.lower(GetUnitDisplayName("group" .. i) or "")
            if dn ~= "" and dn ~= selfDn then
                targetDn = dn
                break
            end
        end
        if targetDn then
            stopInstAnim()
            _instDn    = targetDn
            _instFrame = 0
            EVENT_MANAGER:RegisterForUpdate(INST_KEY, INST_INTERVAL, instAnimTick)
            _instActive = true
            didOsi = true
        end
    end

    if didOsi then
        d("[Incha] /ip inst: OSI icon above " .. _instDn .. " — /ip clear to stop")
    else
        d("[Incha] /ip inst: join a group to preview the instability head icon above others")
    end
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
