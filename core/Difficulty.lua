local Difficulty = {
    --- Transient: health sample not yet received; re-resolved on next power tick.
    NONE     = 0,
    NORMAL   = 1,
    HARDMODE = 2,
    --- Permanent: this encounter declares no hard mode (hmHealthThreshold is nil).
    --- Distinct from NONE so callers can stop re-resolving instead of looping forever.
    NO_HM    = 3,
}

package.loaded["core.Difficulty"] = Difficulty
return Difficulty
