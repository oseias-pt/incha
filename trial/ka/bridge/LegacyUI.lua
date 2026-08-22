local Difficulty = require("core.Difficulty")

local LegacyUI = {}

local function resetInfoPanel(hidden)
    if not BSCHTKAHelperInfoUI then
        return
    end

    BSCHTKAHelperInfoUI:SetHidden(hidden)
    BSCHTKAHelperInfoUI:GetNamedChild("InfoTOP"):SetText("")
    BSCHTKAHelperInfoUI:GetNamedChild("Info1"):SetText("")
    BSCHTKAHelperInfoUI:GetNamedChild("Info2"):SetText("")
    BSCHTKAHelperInfoUI:GetNamedChild("Info3"):SetText("")
    BSCHTKAHelperInfoUI:GetNamedChild("Info4"):SetText("")
end

function LegacyUI.onEnable()
    if BSCHTKA and BSCHTKA.CreateAllIcons then
        zo_callLater(function() BSCHTKA.CreateAllIcons() end, 10000)
    end
end

function LegacyUI.onDisable()
    if not BSCHTKA then
        return
    end

    BSCHTKA.bYandir = false
    BSCHTKA.bVrol = false
    BSCHTKA.bFalgraven = false
    BSCHTKA.bStartListening = false

    resetInfoPanel(true)

    if BSCHTKAUIBossP then
        BSCHTKAUIBossP:SetHidden(true)
    end

    if BSCHTKA.DisableAllTorturerIcons then
        BSCHTKA.DisableAllTorturerIcons()
    end

    if BSCHTKA.DeleteAllIcons then
        zo_callLater(function() BSCHTKA.DeleteAllIcons() end, 1000)
    end
end

function LegacyUI.onBossEnter(boss, context)
    if not BSCHTKA then
        return
    end

    BSCHTKA.bYandir = boss.key == "yandir"
    BSCHTKA.bVrol = boss.key == "vrol"
    BSCHTKA.bFalgraven = boss.key == "falgravn"

    if BSCHTKA.SV_ACC and BSCHTKA.SV_ACC.SHOW_UI_BOSS then
        local hmStatus = context.difficulty == Difficulty.HARDMODE and "ON" or "OFF"
        local bossName = GetUnitName("boss1")
        resetInfoPanel(false)
        BSCHTKAHelperInfoUI:GetNamedChild("InfoTOP"):SetText(zo_strformat("<<1>> HM[<<2>>]", bossName, hmStatus))
    end
end

function LegacyUI.onBossExit()
    if BSCHTKA then
        BSCHTKA.bYandir = false
        BSCHTKA.bVrol = false
        BSCHTKA.bFalgraven = false

        if BSCHTKA.RemovePortalIcon then
            BSCHTKA.RemovePortalIcon()
        end
    end

    resetInfoPanel(true)
end

function LegacyUI.checkHardmode(context)
    if CheckHM then
        CheckHM()
    end
end

LegacyUI.alerts = {
    header = function(text)
        if BSCHTKAHelperInfoUI then
            BSCHTKAHelperInfoUI:GetNamedChild("InfoTOP"):SetText(text)
        end
    end,
    progress = function(text)
        if BSCHTKAHelperInfoUI then
            BSCHTKAHelperInfoUI:GetNamedChild("Info1"):SetText(text)
        end
    end,
    action = function(text)
        if not BSCHTKAUIBossP then
            return
        end

        BSCHTKAUIBossP:SetHidden(false)
        BSCHTKAUIBossP:GetNamedChild("BossPercent"):SetText(text)
    end,
    hideAction = function()
        if BSCHTKAUIBossP and not BSCHTKAUIBossP:IsHidden() then
            BSCHTKAUIBossP:SetHidden(true)
        end
    end,
    clear = function()
        resetInfoPanel(true)
        if BSCHTKAUIBossP then
            BSCHTKAUIBossP:SetHidden(true)
        end
    end,
}

return LegacyUI
