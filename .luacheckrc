-- luacheck configuration for Incha.
--
-- SCOPE: luacheck is used here ONLY for things test/checks/globals.lua cannot
-- see. That check already owns global reads and writes, and does it with rules
-- tuned to the ESO API surface (prefix families like Get*/Is*/EVENT_*), which
-- luacheck cannot express - it wants an explicit list, and the ESO API has
-- hundreds of entries. Enabling luacheck's global diagnostics here would
-- produce a wall of false positives that duplicates a check we already pass.
--
-- So: globals off, scope analysis on. That leaves the class of bug nothing
-- else in test/checks/ looks for - unused locals, shadowed names, and code
-- after a return.

std = "luajit"

-- ESO's environment is not luajit's, and globals.lua covers it properly.
-- Treat every undefined global as allowed here.
allow_defined = true
allow_defined_top = true
ignore = {
    "11.",  -- setting/accessing undefined globals   -> globals.lua
    "12.",  -- setting/accessing global fields       -> globals.lua
    "13.",  -- setting/accessing global mutations    -> globals.lua
    "212",  -- unused argument: boss handlers share a fixed ESO signature, so
            -- unused positional args are the norm, not a defect
    "631",  -- line too long: not enforced, and the tree is consistent already
}

-- What we do want:
--   211  unused local variable
--   213  unused loop variable
--   221  local variable never set
--   231  local variable never accessed
--   311  value assigned to a local is never used
--   4..  shadowing (411 shadowing a local, 421 shadowing an upvalue, …)
--   5..  unreachable code, empty blocks, control-flow oddities

files["test/"] = {
    -- The harness deliberately defines ESO globals and reassigns them between
    -- runs; shadowing warnings there are noise.
    ignore = { "4.." },
}

files["lang/"] = {
    -- A string table is one long list of assignments to a module table.
    ignore = { "63." },
}

exclude_files = {
    ".claude/",
    "resources/",
}
