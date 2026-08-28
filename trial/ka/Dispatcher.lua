--- Kyne's Aegis Dispatcher -- loaded once at addon start; delegates enable/disable to the trial.
local Factory    = require("trial.ka.Factory")
local Dispatcher = {}

function Dispatcher.enable()  Factory:enable()  end
function Dispatcher.disable() Factory:disable() end

package.loaded["trial.ka.Dispatcher"] = Dispatcher
return Dispatcher
