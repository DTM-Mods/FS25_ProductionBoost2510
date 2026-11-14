-- ProductionBoost: 1x / 2x / 5x / 10x per production line.
-- The boost multiplies the line's cycles and running costs. The recipe per cycle stays the same, so materials used
-- and product made per month go up by the same factor.
-- Author: PropaineX

ProductionBoost = {}
ProductionBoost.modName = g_currentModName
ProductionBoost.modDir = g_currentModDirectory
ProductionBoost.MULTIPLIERS = {1, 2, 5, 10}
ProductionBoost.FIELDS = {
    "cyclesPerMinute", "cyclesPerHour", "cyclesPerMonth",
    "costsPerActiveMinute", "costsPerActiveHour", "costsPerActiveMonth"
}
ProductionBoost.SAVE_FILE = "productionBoost.xml"
ProductionBoost.CHECK_INTERVAL = 2000 -- ms between checks that the boost is still in place
ProductionBoost.boosted = setmetatable({}, {__mode = "k"}) -- production -> true, for lines not at 1x
ProductionBoost.checkTimer = 0

local function log(fmt, ...)
    Logging.info("[ProductionBoost] " .. fmt, ...)
end
ProductionBoost.log = log

function ProductionBoost.isValidMultiplier(mult)
    for _, m in ipairs(ProductionBoost.MULTIPLIERS) do
        if m == mult then
            return true
        end
    end
    return false
end

function ProductionBoost.getMultiplier(production)
    return production ~= nil and production.pbMultiplier or 1
end

-- Sets the line's multiplier. The original values are remembered the first time; if another mod changed a value since
-- (e.g. a factory editor), the remembered original is taken from the current value again.
function ProductionBoost.apply(production, mult)
    if production == nil or not ProductionBoost.isValidMultiplier(mult) then
        return false
    end
    local old = production.pbMultiplier or 1
    production.pbBase = production.pbBase or {}
    for _, field in ipairs(ProductionBoost.FIELDS) do
        local current = production[field]
        if type(current) == "number" then
            local base = production.pbBase[field]
            if base == nil or math.abs(base * old - current) > 0.000001 * math.max(1, math.abs(current)) then
                base = current / old
            end
            production.pbBase[field] = base
            production[field] = base * mult
        end
    end
    production.pbMultiplier = mult
    ProductionBoost.boosted[production] = mult ~= 1 or nil
    ProductionBoost.applyStorage(production.pbProductionPoint)
    return true
end

local function nearly(a, b)
    return math.abs(a - b) <= 0.000001 * math.max(1, math.abs(b))
end

-- Storage (inputs and outputs share one storage per production point): capacity x the highest boost of the point's
-- lines. Same "remember the original, re-take it if someone else changed it" rule as the line values.
function ProductionBoost.applyStorage(productionPoint)
    local storage = productionPoint ~= nil and productionPoint.storage or nil
    if storage == nil or type(storage.capacity) ~= "number" then
        return
    end
    local mult = 1
    for _, production in ipairs(productionPoint.productions or {}) do
        mult = math.max(mult, ProductionBoost.getMultiplier(production))
    end
    local old = storage.pbMultiplier or 1
    if old == 1 and mult == 1 then
        return
    end
    storage.pbBase = storage.pbBase or {capacities = {}}
    local base = storage.pbBase
    if base.capacity == nil or not nearly(base.capacity * old, storage.capacity) then
        base.capacity = storage.capacity / old
    end
    storage.capacity = base.capacity * mult
    for fillType, current in pairs(storage.capacities or {}) do
        local b = base.capacities[fillType]
        if b == nil or not nearly(b * old, current) then
            b = current / old
        end
        base.capacities[fillType] = b
        storage.capacities[fillType] = b * mult
    end
    storage.pbMultiplier = mult
end

-- Another mod may write its own (1x) value over a boosted line, e.g. FS25_FactoryProfitCalculator re-applies its
-- overrides for a while after loading. Take that value as the new original and put the boost back on top of it.
function ProductionBoost:update(dt)
    ProductionBoost.checkTimer = ProductionBoost.checkTimer + dt
    if ProductionBoost.checkTimer < ProductionBoost.CHECK_INTERVAL then
        return
    end
    ProductionBoost.checkTimer = 0
    for production in pairs(ProductionBoost.boosted) do
        local mult = production.pbMultiplier or 1
        local base = production.pbBase
        if mult ~= 1 and base ~= nil then
            for _, field in ipairs(ProductionBoost.FIELDS) do
                local current = production[field]
                local original = base[field]
                if type(current) == "number" and original ~= nil then
                    local expected = original * mult
                    if math.abs(current - expected) > 0.000001 * math.max(1, math.abs(expected)) then
                        base[field] = current
                        production[field] = current * mult
                    end
                end
            end
        end
    end
end

addModEventListener(ProductionBoost)

function ProductionBoost.getProduction(productionPoint, productionId)
    if productionPoint == nil or productionPoint.productionsIdToObj == nil then
        return nil
    end
    local production = productionPoint.productionsIdToObj[productionId]
    if production ~= nil then
        production.pbProductionPoint = productionPoint
    end
    return production
end

-- Called on the server (and on clients when the server tells them). Returns true if something changed.
function ProductionBoost.setLineMultiplier(productionPoint, productionId, mult)
    local production = ProductionBoost.getProduction(productionPoint, productionId)
    if production == nil then
        return false
    end
    local ok = ProductionBoost.apply(production, mult)
    if ok then
        ProductionBoostMenu.onLineChanged(productionPoint)
    end
    return ok
end

-- Only the farm manager of the farm that owns the production may change it. Single player: always.
function ProductionBoost.isFarmManager(farmId, userId)
    if farmId == nil or farmId == FarmManager.SPECTATOR_FARM_ID or userId == nil then
        return false
    end
    local farm = g_farmManager:getFarmById(farmId)
    return farm ~= nil and farm.isUserFarmManager ~= nil and farm:isUserFarmManager(userId)
end

function ProductionBoost.localPlayerCanEdit(productionPoint)
    local mission = g_currentMission
    if productionPoint == nil or mission == nil then
        return false
    end
    if mission.missionDynamicInfo == nil or not mission.missionDynamicInfo.isMultiplayer then
        return true
    end
    local farmId = productionPoint:getOwnerFarmId()
    if farmId ~= mission:getFarmId() then
        return false
    end
    return ProductionBoost.isFarmManager(farmId, mission.playerUserId)
end

function ProductionBoost.connectionCanEdit(productionPoint, connection)
    local mission = g_currentMission
    if mission.missionDynamicInfo == nil or not mission.missionDynamicInfo.isMultiplayer then
        return true
    end
    local user = mission.userManager:getUserByConnection(connection)
    if user == nil then
        return false
    end
    return ProductionBoost.isFarmManager(productionPoint:getOwnerFarmId(), user:getId())
end

-- Player asked for a new multiplier (menu click).
function ProductionBoost.requestChange(productionPoint, productionId, mult)
    if not ProductionBoost.localPlayerCanEdit(productionPoint) then
        return
    end
    if g_server ~= nil then
        if ProductionBoost.setLineMultiplier(productionPoint, productionId, mult) then
            g_server:broadcastEvent(ProductionBoostEvent.new(productionPoint, productionId, mult))
        end
    else
        g_client:getServerConnection():sendEvent(ProductionBoostEvent.new(productionPoint, productionId, mult))
    end
end

---------------------------------------------------------------------------------------------------------------------
-- Join sync: the server sends every boosted line with the production point's own data.
---------------------------------------------------------------------------------------------------------------------
local function boostedLines(productionPoint)
    local list = {}
    for _, production in ipairs(productionPoint.productions or {}) do
        local mult = ProductionBoost.getMultiplier(production)
        if mult ~= 1 and production.id ~= nil then
            table.insert(list, {id = production.id, mult = mult})
        end
    end
    return list
end

function ProductionBoost.writeStream(productionPoint, streamId, connection)
    if not connection:getIsServer() then
        local list = boostedLines(productionPoint)
        streamWriteUInt16(streamId, #list)
        for _, entry in ipairs(list) do
            streamWriteString(streamId, entry.id)
            streamWriteUInt8(streamId, entry.mult)
        end
    end
end

function ProductionBoost.readStream(productionPoint, streamId, connection)
    if connection:getIsServer() then
        local count = streamReadUInt16(streamId)
        for _ = 1, count do
            local id = streamReadString(streamId)
            local mult = streamReadUInt8(streamId)
            local production = ProductionBoost.getProduction(productionPoint, id)
            if production ~= nil then
                ProductionBoost.apply(production, mult)
            end
        end
    end
end

ProductionPoint.writeStream = Utils.appendedFunction(ProductionPoint.writeStream, ProductionBoost.writeStream)
ProductionPoint.readStream = Utils.appendedFunction(ProductionPoint.readStream, ProductionBoost.readStream)

---------------------------------------------------------------------------------------------------------------------
-- Saving: <savegame>/productionBoost.xml, lines matched by the placeable's unique id + production id.
---------------------------------------------------------------------------------------------------------------------
local function getPlaceableUniqueId(productionPoint)
    local placeable = productionPoint.owningPlaceable
    if placeable ~= nil and placeable.getUniqueId ~= nil then
        return placeable:getUniqueId()
    end
    return nil
end

local function getProductionPoints()
    local manager = g_currentMission ~= nil and g_currentMission.productionChainManager or nil
    return manager ~= nil and manager.productionPoints or {}
end

function ProductionBoost.saveToXMLFile(missionInfo)
    local dir = missionInfo ~= nil and missionInfo.savegameDirectory or nil
    if dir == nil or g_currentMission == nil or g_currentMission:getIsServer() ~= true then
        return
    end
    local xmlFile = createXMLFile("productionBoost", dir .. "/" .. ProductionBoost.SAVE_FILE, "productionBoost")
    if xmlFile == nil or xmlFile == 0 then
        Logging.warning("[ProductionBoost] could not write %s", ProductionBoost.SAVE_FILE)
        return
    end
    local i = 0
    for _, productionPoint in ipairs(getProductionPoints()) do
        local uniqueId = getPlaceableUniqueId(productionPoint)
        if uniqueId ~= nil then
            for _, entry in ipairs(boostedLines(productionPoint)) do
                local key = string.format("productionBoost.line(%d)", i)
                setXMLString(xmlFile, key .. "#placeable", uniqueId)
                setXMLString(xmlFile, key .. "#production", entry.id)
                setXMLInt(xmlFile, key .. "#multiplier", entry.mult)
                i = i + 1
            end
        end
    end
    saveXMLFile(xmlFile)
    delete(xmlFile)
end

-- Reads productionBoost.xml once: uniqueId -> list of {id, mult}. Server only.
function ProductionBoost.getSavedLines()
    if ProductionBoost.savedLines ~= nil then
        return ProductionBoost.savedLines
    end
    local saved = {}
    ProductionBoost.savedLines = saved
    local mission = g_currentMission
    if mission == nil or not mission:getIsServer() then
        return saved
    end
    local dir = mission.missionInfo ~= nil and mission.missionInfo.savegameDirectory or nil
    if dir == nil then
        return saved
    end
    local path = dir .. "/" .. ProductionBoost.SAVE_FILE
    if not fileExists(path) then
        return saved
    end
    local xmlFile = loadXMLFile("productionBoost", path)
    if xmlFile == nil or xmlFile == 0 then
        return saved
    end
    local i = 0
    while true do
        local key = string.format("productionBoost.line(%d)", i)
        if not hasXMLProperty(xmlFile, key) then
            break
        end
        local uniqueId = getXMLString(xmlFile, key .. "#placeable")
        local productionId = getXMLString(xmlFile, key .. "#production")
        local mult = getXMLInt(xmlFile, key .. "#multiplier") or 1
        if uniqueId ~= nil and productionId ~= nil then
            saved[uniqueId] = saved[uniqueId] or {}
            table.insert(saved[uniqueId], {id = productionId, mult = mult})
        end
        i = i + 1
    end
    delete(xmlFile)
    return saved
end

-- Before the point loads its storage from the savegame: put the boost (and so the bigger storage) on first, or the
-- game would clamp the saved fill levels to the normal capacity.
function ProductionBoost.beforePointLoad(productionPoint)
    local uniqueId = getPlaceableUniqueId(productionPoint)
    local lines = uniqueId ~= nil and ProductionBoost.getSavedLines()[uniqueId] or nil
    for _, entry in ipairs(lines or {}) do
        local production = ProductionBoost.getProduction(productionPoint, entry.id)
        if production ~= nil then
            ProductionBoost.apply(production, entry.mult)
        end
    end
end

-- After the mission starts: apply anything not applied yet (same values again do nothing).
function ProductionBoost.loadFromSavegame()
    local byPlaceable = {}
    for _, productionPoint in ipairs(getProductionPoints()) do
        local uniqueId = getPlaceableUniqueId(productionPoint)
        if uniqueId ~= nil then
            byPlaceable[uniqueId] = productionPoint
        end
    end
    local applied, missing = 0, 0
    for uniqueId, lines in pairs(ProductionBoost.getSavedLines()) do
        for _, entry in ipairs(lines) do
            local production = ProductionBoost.getProduction(byPlaceable[uniqueId], entry.id)
            if production ~= nil and ProductionBoost.apply(production, entry.mult) then
                applied = applied + 1
            else
                missing = missing + 1
            end
        end
    end
    ProductionBoost.savedLines = nil
    if applied + missing > 0 then
        log("loaded %d boosted line(s) from the savegame (%d no longer found)", applied, missing)
    end
end

ProductionPoint.loadFromXMLFile = Utils.prependedFunction(ProductionPoint.loadFromXMLFile, ProductionBoost.beforePointLoad)
FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, ProductionBoost.saveToXMLFile)
Mission00.onStartMission = Utils.appendedFunction(Mission00.onStartMission, ProductionBoost.loadFromSavegame)

log("loaded (multipliers 1x/2x/5x/10x per production line)")
