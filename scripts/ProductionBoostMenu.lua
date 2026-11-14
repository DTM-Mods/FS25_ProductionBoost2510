-- ProductionBoostMenu: draws "PRODUCTION LINE BOOST %" and the 1x / 2x / 5x / 10x tick boxes in the Production Chains
-- menu, in the empty space above "RECIPE: ...", and handles mouse clicks on them.
-- The menu's own Lua/XML is not readable (encrypted), so the recipe heading is found at runtime by its text and
-- everything is placed relative to it. Sizes are multiples of the heading's text size so they follow the UI scale.
-- Author: PropaineX

ProductionBoostMenu = {}
ProductionBoostMenu.hitAreas = {}
ProductionBoostMenu.activeFrame = nil
ProductionBoostMenu.loggedNoAnchor = false

-- layout, in multiples of the recipe heading's text size (measured on the approved mockups)
local L = {
    headingOffset = 5.1,  -- heading centre above the recipe heading centre
    boxesOffset = 2.7,    -- tick box centre above the recipe heading centre
    centreX = 18.4,       -- block centre, right of the recipe heading's left edge
    headingSize = 1.1,
    labelSize = 1.33,
    box = 1.48,
    boxLabelGap = 0.52,
    groupGap = 2.2,
    border = 0.12
}

local GREEN = {0.65, 0.78, 0.18, 1}
local GREEN_DIM = {0.40, 0.45, 0.25, 1}
local BOX_OFF = {0.27, 0.27, 0.27, 1}
local WHITE = {0.92, 0.92, 0.92, 1}
local GREY_TEXT = {0.55, 0.55, 0.55, 1}
local TICK = {0.08, 0.08, 0.08, 1}

local function walk(element, fn)
    if element == nil or element.elements == nil then
        return nil
    end
    for _, child in ipairs(element.elements) do
        local found = fn(child) or walk(child, fn)
        if found ~= nil then
            return found
        end
    end
    return nil
end

-- the "RECIPE: <production name>" text element
local function findRecipeHeading(frame, production)
    local name = production ~= nil and production.name or nil
    if type(name) ~= "string" or name == "" then
        return nil
    end
    local wanted = string.upper(name)
    return walk(frame, function(element)
        local text = element.text
        if type(text) == "string" and element.textSize ~= nil and text:find(":", 1, true) ~= nil then
            local upper = string.upper(text)
            if upper:sub(-#wanted) == wanted and #upper > #wanted and element:getIsVisible() then
                return element
            end
        end
        return nil
    end)
end

-- visible area of the heading (intersection of every clipping parent)
local function getClip(element)
    local x1, y1, x2, y2 = 0, 0, 1, 1
    local e = element.parent
    while e ~= nil do
        if e.clipping then
            x1 = math.max(x1, e.absPosition[1])
            y1 = math.max(y1, e.absPosition[2])
            x2 = math.min(x2, e.absPosition[1] + e.absSize[1])
            y2 = math.min(y2, e.absPosition[2] + e.absSize[2])
        end
        e = e.parent
    end
    return x1, y1, x2, y2
end

local function rect(x, y, w, h, c)
    drawFilledRect(x, y, w, h, c[1], c[2], c[3], c[4])
end

-- tick mark made of small squares along two lines
local function drawTick(x, y, w, h)
    local s = h * 0.13
    local sx = s / g_screenAspectRatio
    local function line(ax, ay, bx, by)
        local steps = 8
        for i = 0, steps do
            local t = i / steps
            rect(x + (ax + (bx - ax) * t) * w - sx / 2, y + (ay + (by - ay) * t) * h - s / 2, sx, s, TICK)
        end
    end
    line(0.22, 0.52, 0.42, 0.28)
    line(0.42, 0.28, 0.80, 0.76)
end

function ProductionBoostMenu.draw(frame)
    ProductionBoostMenu.activeFrame = frame
    ProductionBoostMenu.hitAreas = {}

    if frame.getSelectedProduction == nil then
        return
    end
    local ok, production, productionPoint = pcall(frame.getSelectedProduction, frame)
    if not ok or production == nil or productionPoint == nil or production.id == nil then
        return
    end

    local heading = findRecipeHeading(frame, production)
    if heading == nil then
        if not ProductionBoostMenu.loggedNoAnchor then
            ProductionBoostMenu.loggedNoAnchor = true
            ProductionBoost.log("could not find the recipe heading for '%s'; boost boxes not shown", tostring(production.name))
        end
        return
    end

    local T = heading.textSize
    local aspect = g_screenAspectRatio
    local headingCentreY = heading.absPosition[2] + heading.absSize[2] / 2
    local titleY = headingCentreY + L.headingOffset * T
    local boxY = headingCentreY + L.boxesOffset * T
    local centreX = heading.absPosition[1] + L.centreX * T / aspect

    local boxH = L.box * T
    local boxW = boxH / aspect
    local labelSize = L.labelSize * T
    local headingSize = L.headingSize * T

    -- only draw when the whole block is inside the visible part of the panel
    local cx1, cy1, cx2, cy2 = getClip(heading)
    if boxY - boxH / 2 < cy1 or titleY + headingSize / 2 > cy2 then
        return
    end

    local canEdit = ProductionBoost.localPlayerCanEdit(productionPoint)
    local current = ProductionBoost.getMultiplier(production)

    setTextBold(true)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_MIDDLE)

    -- heading
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextColor(WHITE[1], WHITE[2], WHITE[3], WHITE[4])
    renderText(centreX, titleY, headingSize, g_i18n:getText("pb_heading"))

    -- boxes
    local labels, widths, total = {}, {}, 0
    for i, mult in ipairs(ProductionBoost.MULTIPLIERS) do
        labels[i] = string.format("%dx", mult)
        widths[i] = boxW + L.boxLabelGap * T / aspect + getTextWidth(labelSize, labels[i])
        total = total + widths[i]
    end
    total = total + L.groupGap * T / aspect * (#ProductionBoost.MULTIPLIERS - 1)

    local x = math.max(cx1, centreX - total / 2)
    local border = L.border * T
    local borderX = border / aspect
    setTextAlignment(RenderText.ALIGN_LEFT)
    for i, mult in ipairs(ProductionBoost.MULTIPLIERS) do
        local on = mult == current
        local edge = canEdit and GREEN or GREEN_DIM
        local by = boxY - boxH / 2
        rect(x, by, boxW, boxH, edge)
        if not on then
            rect(x + borderX, by + border, boxW - 2 * borderX, boxH - 2 * border, BOX_OFF)
        else
            drawTick(x, by, boxW, boxH)
        end
        local textColor = canEdit and WHITE or GREY_TEXT
        setTextColor(textColor[1], textColor[2], textColor[3], textColor[4])
        renderText(x + boxW + L.boxLabelGap * T / aspect, boxY, labelSize, labels[i])

        if canEdit then
            table.insert(ProductionBoostMenu.hitAreas, {
                x1 = x, y1 = by, x2 = x + widths[i], y2 = by + boxH,
                productionPoint = productionPoint, productionId = production.id, mult = mult
            })
        end
        x = x + widths[i] + L.groupGap * T / aspect
    end

    -- reset text state for whatever draws next
    setTextBold(false)
    setTextColor(1, 1, 1, 1)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BASELINE)
end

function ProductionBoostMenu.mouseEvent(frame, superFunc, posX, posY, isDown, isUp, button, eventUsed)
    if not eventUsed and isDown and button == Input.MOUSE_BUTTON_LEFT and frame:getIsVisible() then
        for _, area in ipairs(ProductionBoostMenu.hitAreas) do
            if posX >= area.x1 and posX <= area.x2 and posY >= area.y1 and posY <= area.y2 then
                local production = ProductionBoost.getProduction(area.productionPoint, area.productionId)
                if production ~= nil and ProductionBoost.getMultiplier(production) ~= area.mult then
                    ProductionBoost.requestChange(area.productionPoint, area.productionId, area.mult)
                end
                return true
            end
        end
    end
    return superFunc(frame, posX, posY, isDown, isUp, button, eventUsed)
end

-- after a change, re-run the menu's own "product selected" handler so Cycles / Costs per month show the new numbers
function ProductionBoostMenu.onLineChanged(productionPoint)
    local frame = ProductionBoostMenu.activeFrame
    if frame == nil or not frame:getIsVisible() or frame.productsList == nil or frame.onListSelectionChanged == nil then
        return
    end
    if frame.selectedProductionPoint ~= nil and frame.selectedProductionPoint ~= productionPoint then
        return
    end
    local detailsList = frame.detailsList
    local viewOffset = detailsList ~= nil and detailsList.viewOffset or nil
    local section, index = frame.productsList:getSelectedPath()
    local ok, err = pcall(frame.onListSelectionChanged, frame, frame.productsList, section, index)
    if not ok then
        ProductionBoost.log("refreshing the production details failed: %s", tostring(err))
        return
    end
    if detailsList ~= nil and viewOffset ~= nil and detailsList.updateView ~= nil then
        detailsList.viewOffset, detailsList.targetViewOffset = viewOffset, viewOffset
        detailsList:updateView(true, true)
    end
end

if InGameMenuProductionFrame ~= nil then
    InGameMenuProductionFrame.draw = Utils.appendedFunction(InGameMenuProductionFrame.draw, ProductionBoostMenu.draw)
    InGameMenuProductionFrame.mouseEvent = Utils.overwrittenFunction(InGameMenuProductionFrame.mouseEvent, ProductionBoostMenu.mouseEvent)
    InGameMenuProductionFrame.onFrameOpen = Utils.prependedFunction(InGameMenuProductionFrame.onFrameOpen, function()
        ProductionBoostMenu.loggedNoAnchor = false
    end)
    ProductionBoost.log("hooked the Production Chains menu")
else
    Logging.warning("[ProductionBoost] InGameMenuProductionFrame not found, boost boxes will not be shown")
end
