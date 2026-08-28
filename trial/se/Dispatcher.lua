--- Sanity's Edge Dispatcher -- loaded once at addon start; delegates enable/disable to the trial.
local Factory    = require("trial.se.Factory")
local Dispatcher = {}

function Dispatcher.enable()  Factory:enable()  end
function Dispatcher.disable() Factory:disable() end

package.loaded["trial.se.Dispatcher"] = Dispatcher
return Dispatcher
