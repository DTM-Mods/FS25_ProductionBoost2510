-- ProductionBoostEvent: client asks the server for a new multiplier; the server checks the farm manager rule,
-- applies it and sends it to every player.
-- Author: PropaineX

ProductionBoostEvent = {}
local ProductionBoostEvent_mt = Class(ProductionBoostEvent, Event)
InitEventClass(ProductionBoostEvent, "ProductionBoostEvent")

function ProductionBoostEvent.emptyNew()
    return Event.new(ProductionBoostEvent_mt)
end

function ProductionBoostEvent.new(productionPoint, productionId, mult)
    local self = ProductionBoostEvent.emptyNew()
    self.productionPoint = productionPoint
    self.productionId = productionId
    self.mult = mult
    return self
end

function ProductionBoostEvent:readStream(streamId, connection)
    self.productionPoint = NetworkUtil.readNodeObject(streamId)
    self.productionId = streamReadString(streamId)
    self.mult = streamReadUInt8(streamId)
    self:run(connection)
end

function ProductionBoostEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.productionPoint)
    streamWriteString(streamId, self.productionId)
    streamWriteUInt8(streamId, self.mult)
end

function ProductionBoostEvent:run(connection)
    if self.productionPoint == nil then
        return
    end
    if not connection:getIsServer() then
        -- on the server, from a client
        if not ProductionBoost.connectionCanEdit(self.productionPoint, connection) then
            ProductionBoost.log("refused a change from a player who is not the farm manager")
            return
        end
        if ProductionBoost.setLineMultiplier(self.productionPoint, self.productionId, self.mult) then
            g_server:broadcastEvent(ProductionBoostEvent.new(self.productionPoint, self.productionId, self.mult))
        end
    else
        -- on a client, from the server
        ProductionBoost.setLineMultiplier(self.productionPoint, self.productionId, self.mult)
    end
end
