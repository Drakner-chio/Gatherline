-- Gatherline: ready-made no-go areas (Hazards_Data.lua), on top of the ones
-- you draw yourself:
--
--  * hostile towns: the other faction's towns with a flight master, the
--    ground the game calls each town (Shortest Path Forever's data);
--  * elite camps: open-world elites, rare elites and bosses (CMaNGOS Classic
--    database), unless they're well below your level.
--
-- Each one can be switched on or off by hand, all of a zone at once, or each
-- kind as a whole. Routes keep out of the ones that are on, like your own
-- areas: no node inside is used and the line goes round.
--
-- db.nogo = { towns, camps, below (levels), areas = { [id] = true | false }, zones = { [mapID] = true } (off) }

local ADDON, ns = ...
local L = ns.L
local GP = ns.GP
local floor, min, max = math.floor, math.min, math.max

GP.NOGO_DEFAULTS = { towns = true, camps = true, below = 5 }
GP.NOGO_BELOW = { 0, 20 }
GP.NOGO_COLOR = { 0.98, 0.58, 0.16 }

function GP:NoGoSettings()
    local db = self.db
    if type(db.nogo) ~= "table" then db.nogo = {} end
    local n = db.nogo
    for k, v in pairs(self.NOGO_DEFAULTS) do
        if type(n[k]) ~= type(v) then n[k] = v end
    end
    n.below = max(self.NOGO_BELOW[1], min(self.NOGO_BELOW[2], floor(n.below)))
    if type(n.areas) ~= "table" then n.areas = {} end
    if type(n.zones) ~= "table" then n.zones = {} end
    return n
end

local function Faction()
    if GP.FAKE_FACTION then return GP.FAKE_FACTION end
    local f = UnitFactionGroup and UnitFactionGroup("player")
    return f
end
local function Level()
    if GP.FAKE_LEVEL then return GP.FAKE_LEVEL end
    return UnitLevel and UnitLevel("player") or 1
end

-- Something changed (a switch, your level): routes worked out from now on use it
function GP:NoGoChanged()
    self.tabooVersion = (self.tabooVersion or 0) + 1
    self:Changed()
end

---------------------------------------------------------------------------
-- The areas touching a zone, their outlines turned into the zone's map
-- positions once (kept per zone)
---------------------------------------------------------------------------
local outlines = {}   -- [mapID] = { { id, kind, name, low, high, spawns, faction, polys } }

local function ZoneBox(mapID)
    local Walk = GP.Walk
    if not Walk then return nil end
    local a, b = Walk.Point(mapID, 0, 0), Walk.Point(mapID, 1, 1)
    if not (a and b) or a.map ~= b.map then return nil end
    return a.map, min(a.x, b.x), min(a.y, b.y), max(a.x, b.x), max(a.y, b.y)
end

-- World outline (flat x, y ...) to map positions; nil if it isn't on this map at all
local function ToMap(mapID, continent, xy)
    local out, inside = {}, false
    for k = 1, #xy, 2 do
        local x, y = GP.Walk.MapPos(mapID, { map = continent, x = xy[k], y = xy[k + 1] })
        if not x then return nil end
        out[k], out[k + 1] = x, y
        if x >= 0 and x <= 1 and y >= 0 and y <= 1 then inside = true end
    end
    return inside and out or nil
end

local function Overlaps(xy, x0, y0, x1, y1)
    for k = 1, #xy, 2 do
        if xy[k] >= x0 and xy[k] <= x1 and xy[k + 1] >= y0 and xy[k + 1] <= y1 then return true end
    end
    return false
end

local function Outlines(mapID)
    local c = outlines[mapID]
    if c then return c end
    c = {}
    local continent, x0, y0, x1, y1 = ZoneBox(mapID)
    if continent then
        for _, t in ipairs(ns.HAZARD_TOWNS or {}) do
            if t[3] == continent then
                local xy = {}
                for k = 5, #t do xy[#xy + 1] = t[k] end
                if Overlaps(xy, x0, y0, x1, y1) then
                    local poly = ToMap(mapID, continent, xy)
                    if poly then
                        c[#c + 1] = { id = "t" .. t[1], kind = "town", faction = t[2], name = t[4], polys = { poly } }
                    end
                end
            end
        end
        for _, e in ipairs(ns.HAZARD_CAMPS or {}) do
            if e[1] == continent and e[6] >= x0 - 300 and e[6] <= x1 + 300 and e[7] >= y0 - 300 and e[7] <= y1 + 300 then
                local polys = {}
                for k = 8, #e do
                    if Overlaps(e[k], x0, y0, x1, y1) then
                        local poly = ToMap(mapID, continent, e[k])
                        if poly then polys[#polys + 1] = poly end
                    end
                end
                if #polys > 0 then
                    c[#c + 1] = { id = ("c%d:%d:%d"):format(e[1], e[6], e[7]), kind = "camp", name = e[4],
                        low = e[2], high = e[3], spawns = e[5], polys = polys }
                end
            end
        end
        table.sort(c, function(a, b)
            if a.kind ~= b.kind then return a.kind == "town" end
            if (a.low or 0) ~= (b.low or 0) then return (a.low or 0) < (b.low or 0) end
            return a.name < b.name
        end)
    end
    outlines[mapID] = c
    return c
end

-- Whether an area keeps routes out on its own (before any switch by hand), and why
function GP:NoGoAuto(a)
    local n = self:NoGoSettings()
    if a.kind == "town" then
        local mine = Faction()
        if not n.towns then return false, "off" end
        if not mine or a.faction == mine then return false, "friendly" end
        return true
    end
    if not n.camps then return false, "off" end
    if a.high <= Level() - n.below then return false, "low" end
    return true
end

-- The ready-made areas of a zone, each with on (keeps routes out now), auto
-- (what it'd be left alone) and by hand (true, false or nil)
function GP:NoGoAreas(mapID)
    local n = self:NoGoSettings()
    local list = {}
    for _, a in ipairs(Outlines(mapID)) do
        local auto, why = self:NoGoAuto(a)
        local hand = n.areas[a.id]
        local on = hand
        if on == nil then on = auto end
        if n.zones[mapID] then on = false end
        list[#list + 1] = { area = a, on = on, auto = auto, why = why, hand = hand }
    end
    return list
end

-- The outlines (map positions) of the ready-made areas on now in a zone
function GP:NoGoPolys(mapID)
    local out = {}
    for _, e in ipairs(self:NoGoAreas(mapID)) do
        if e.on then
            for _, poly in ipairs(e.area.polys) do out[#out + 1] = poly end
        end
    end
    return out
end

-- Switches one area by hand (on or off); back to automatic if that's what it'd be anyway
function GP:SetNoGo(mapID, id, on)
    local n = self:NoGoSettings()
    for _, a in ipairs(Outlines(mapID)) do
        if a.id == id then
            local auto = self:NoGoAuto(a)
            if on == auto then n.areas[id] = nil else n.areas[id] = on end
        end
    end
    self:NoGoChanged()
end

function GP:SetNoGoZone(mapID, on)
    self:NoGoSettings().zones[mapID] = (not on) and true or nil
    self:NoGoChanged()
end

-- Every switch by hand in a zone back to automatic
function GP:ResetNoGoZone(mapID)
    local n = self:NoGoSettings()
    for _, a in ipairs(Outlines(mapID)) do n.areas[a.id] = nil end
    n.zones[mapID] = nil
    self:NoGoChanged()
end

-- A short line about an area: "hostile town", "elite, level 26-28, 12 spawns"
function GP:NoGoDetail(e)
    local a = e.area
    if a.kind == "town" then
        return a.faction == "Alliance" and L["Alliance town"] or L["Horde town"]
    end
    local lv = a.low == a.high and tostring(a.low) or (a.low .. "-" .. a.high)
    return a.spawns == 1 and L["elite, level %s"]:format(lv) or L["elite, level %s, %d spawns"]:format(lv, a.spawns)
end

-- You level up: elite camps well below you open up
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:SetScript("OnEvent", function()
    if GP.db then GP:NoGoChanged() end
end)
GP.noGoOutlines = outlines
