--- Asylum Sanctorium Dispatcher -- loaded once at addon start; delegates enable/disable to the trial.
local Factory    = require("trial.as.Factory")
local Dispatcher = {}

function Dispatcher.enable()  Factory:enable()  end
function Dispatcher.disable() Factory:disable() end

package.loaded["trial.as.Dispatcher"] = Dispatcher
return Dispatcher
