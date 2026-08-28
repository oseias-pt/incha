--- Dreadsail Reef Dispatcher -- loaded once at addon start; delegates enable/disable to the trial.
local Factory    = require("trial.dsr.Factory")
local Dispatcher = {}

function Dispatcher.enable()  Factory:enable()  end
function Dispatcher.disable() Factory:disable() end

package.loaded["trial.dsr.Dispatcher"] = Dispatcher
return Dispatcher
