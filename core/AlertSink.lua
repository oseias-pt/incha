local AlertSink = {}
AlertSink.__index = AlertSink

function AlertSink.new(handlers)
    return setmetatable({
        handlers = handlers or {},
    }, AlertSink)
end

-- text is passed straight through to the handler (no payload table wrapper)
-- since this runs on the boss-health hot path and every allocation there
-- adds up across a multi-second fight.
function AlertSink:emit(eventType, text)
    local handler = self.handlers[eventType]
    if handler then
        handler(text)
    end
end

function AlertSink:showProgress(text)
    self:emit("progress", text)
end

function AlertSink:showAction(text)
    self:emit("action", text)
end

function AlertSink:showHeader(text)
    self:emit("header", text)
end

function AlertSink:clear()
    self:emit("clear")
end

return AlertSink
