local AlertSink = {}
AlertSink.__index = AlertSink

function AlertSink.new(handlers)
    return setmetatable({
        handlers = handlers or {},
    }, AlertSink)
end

-- File-local: internal dispatch only.  Not part of the public API.
-- text is passed straight through to the handler (no payload table wrapper)
-- since this runs on the boss-health hot path and every allocation there
-- adds up across a multi-second fight.
local function emit(self, eventType, text)
    local handler = self.handlers[eventType]
    if handler then
        handler(text)
    end
end


-- info lines take two args (slot index + text), so they can't route through
-- the single-arg emit().  Handlers receive (n, text) directly.
function AlertSink:showInfo(n, text)
    local handler = self.handlers.info
    if handler then
        handler(n, text)
    end
end

function AlertSink:showAction(text)
    emit(self, "action", text)
end

function AlertSink:showHeader(text)
    emit(self, "header", text)
end

-- Named method so callers never need to know the "hideAction" event string.
-- A typo in the channel name previously silently no-opped; now a wrong
-- method name produces a Lua error at call time.
function AlertSink:hideAction()
    emit(self, "hideAction")
end

-- Self-instability 2D icon: shown/hidden independently of the action text.
function AlertSink:showSelfInst()
    emit(self, "selfInstOn")
end
function AlertSink:hideSelfInst()
    emit(self, "selfInstOff")
end

function AlertSink:clear()
    emit(self, "clear")
end

package.loaded["core.AlertSink"] = AlertSink
return AlertSink
