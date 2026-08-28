local Difficulty = require("core.Difficulty")

local TrialContext = {}
TrialContext.__index = TrialContext

function TrialContext.new(trialId)
    return setmetatable({
        trialId       = trialId,
        bossId        = nil,
        bossKey       = nil,
        difficulty    = Difficulty.NONE,
        isHM          = false,   -- pre-computed; kept in sync with difficulty
        stage         = 1,
        inCombat      = false,
        healthPercent = 0,
    }, TrialContext)
end

function TrialContext:setBoss(boss)
    if boss then
        self.bossId = boss.id
        self.bossKey = boss.key
        self.stage = boss.stage or 1
    else
        self.bossId = nil
        self.bossKey = nil
        self.stage = 1
    end
end

function TrialContext:setDifficulty(difficulty)
    self.difficulty = difficulty or Difficulty.NONE
    self.isHM       = (self.difficulty == Difficulty.HARDMODE)
end

package.loaded["core.TrialContext"] = TrialContext
return TrialContext
