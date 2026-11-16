-- Gatherline: routes through your GatherMate2 / GatherLite nodes, drawn on the
-- world map and the minimap.
--
-- A route belongs to one map (zone). It's made from the kinds of node you pick
-- (Peacebloom, Copper Vein...), read from GatherMate2, put in the shortest
-- loop Optimize.lua can find, and saved as a list of map positions.

local ADDON, ns = ...
local L = ns.L
local T = ns.Theme
local O = ns.Optimize

local GP = {}
ns.GP = GP
Gatherline = GP

local sqrt, max, min, floor, cos, sin = math.sqrt, math.max, math.min, math.floor, math.cos, math.sin

local function Print(msg) print(T.CHAT_PREFIX .. ": " .. msg) end
GP.Print = Print

GP.ICON = "Interface\\AddOns\\" .. ADDON .. "\\media\\Logo"
GP.LOGO_TEXT = "|T" .. GP.ICON .. ":0|t"

GP.DEFAULTS = {
    worldMap = true,       -- draw routes on the world map
    minimap = true,        -- and on the minimap
    worldWidth = 4,        -- line width on the world map (in halves: 0.5, 1, 1.5 ...)
    minimapWidth = 3,      -- and on the minimap
    worldStyle = "line",   -- how routes are drawn there: "line", "dashes" or "dots"
    minimapStyle = "line",
    worldAlpha = 85,       -- line opacity on the world map (percent)
    minimapAlpha = 85,     -- and on the minimap
    worldRouteColor = true,    -- world map lines in each route's own color
    minimapRouteColor = true,  -- minimap lines too
    worldColor = { 1, 0.82, 0 },   -- the world map's one color when worldRouteColor is off
    minimapColor = { 1, 0.82, 0 }, -- and the minimap's
    range = false,         -- a circle round you on the minimap: how far Find Herbs/Find Minerals show nodes
    rangeYards = 100,      -- its radius
    rangeAlpha = 60,       -- its opacity (percent)
    rangeColor = { 0.25, 0.80, 1.00 },  -- its color
    arrows = true,         -- arrows along the lines show which way round to ride
    arrowsReverse = false, -- and they point the other way
    joinLine = true,       -- a dashed line on the minimap from you to the nearest point of a route
    tabooShow = true,      -- taboo areas drawn (red, hatched) on the world map
    autoAdd = true,        -- nodes GatherMate2 / GatherLite find later join the routes they belong to
    minimapButton = true,
    minimapAngle = 200,
    sight = 185,           -- where New route's "route passes within" starts (yards, 0 = go to every node)
    nextColor = 1,
    navLaps = 0,           -- laps Start rides a route (0 = until you stop it)
    navReach = 30,         -- yards from a stop at which a ride moves on to the next
    navAhead = 10,         -- stops handed to Shortest Path at once (its numbered pins)
    navRespawn = 5,
    bagWarn = 4,           -- warn while riding when bags are down to this many free slots (0 = never)
    navLearn = true,       -- smart laps use the regrowth times seen in each zone (never longer than navRespawn)
    syncGroup = true,      -- tell your group (Gatherline users) what you gather, and hear theirs        -- minutes a gathered node counts as gone: stops with only such nodes are skipped (0 = never)
    navLabel = "both",     -- what a stop is called: "number" (Wegpunkt 3/42), "nodes" (what's there), "both"
    onlyGatherable = false,   -- New route lists only the nodes your Herbalism / Mining can gather
    walkRoutes = true,     -- work routes out with walks over the ground (Shortest Path's walking maps)
}
-- The settings on the Display tab, which its Restore defaults button puts back
-- (not routes, the minimap button's place, New route's slider or the remembered speed)
GP.DISPLAY_KEYS = {
    "worldMap", "minimap", "worldWidth", "minimapWidth", "worldAlpha", "minimapAlpha", "worldStyle", "minimapStyle",
    "worldRouteColor", "minimapRouteColor", "worldColor", "minimapColor",
    "arrows", "arrowsReverse", "joinLine",
    "range", "rangeYards", "rangeAlpha", "rangeColor",
    "autoAdd", "minimapButton",
}
GP.RANGES = {
    worldWidth = { 0.5, 10 },
    minimapWidth = { 0.5, 8 },
    worldAlpha = { 10, 100 },
    minimapAlpha = { 10, 100 },
    rangeYards = { 20, 200 },
    rangeAlpha = { 10, 100 },
    sight = { 0, 200 },
    navLaps = { 0, 99 },
    navReach = { 15, 150 },
    navAhead = { 2, 25 },
    navRespawn = { 0, 30 },
    bagWarn = { 0, 20 },
}

-- New routes take these in turn
GP.COLORS = {
    { 1.00, 0.82, 0.00 },   -- gold
    { 0.25, 0.80, 1.00 },   -- blue
    { 1.00, 0.35, 0.30 },   -- red
    { 0.45, 1.00, 0.40 },   -- green
    { 1.00, 0.55, 0.10 },   -- orange
    { 0.85, 0.50, 1.00 },   -- purple
    { 1.00, 1.00, 1.00 },   -- white
}

-- GatherMate2's kinds of node, in the order they're listed, with our names for them
GP.KINDS = { "Herb Gathering", "Mining", "Fishing", "Treasure", "Extract Gas", "Archaeology", "Logging" }
GP.KIND_NAMES = {
    ["Herb Gathering"] = "Herbs", ["Mining"] = "Ore", ["Fishing"] = "Fishing",
    ["Treasure"] = "Treasure", ["Extract Gas"] = "Gas", ["Archaeology"] = "Archaeology", ["Logging"] = "Logging",
}

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
function GP:LoadSettings()
    GatherlineDB = type(GatherlineDB) == "table" and GatherlineDB or {}
    local db = GatherlineDB
    -- 1.1.0 started "pass within" at 50 yards; 1.1.1 starts it at 100
    if db.sight == 50 and not db.sight100 then db.sight = nil end
    db.sight100 = true
    db.merge = nil   -- New route's "merge nodes closer than" until 1.3.0
    -- one "Opacity" for both kinds of line until 1.5.0
    if type(db.alpha) == "number" then
        if db.worldAlpha == nil then db.worldAlpha = db.alpha end
        if db.minimapAlpha == nil then db.minimapAlpha = db.alpha end
    end
    db.alpha = nil
    -- (before 1.7.2 "Reverse direction" turned every route's arrows and rides round;
    -- now each route has its own direction: turn them round once, for good)
    if db.arrowsReverse == true and type(db.routes) == "table" then
        for _, r in ipairs(db.routes) do
            if type(r) == "table" and type(r.points) == "table" then
                r.points = GP.ReversePairs(r.points)
                if type(r.drawn) == "table" then r.drawn = GP.ReversePairs(r.drawn) end
            end
        end
        db.arrowsReverse = false
    end
    for _, k in ipairs({ "worldStyle", "minimapStyle" }) do
        local ok = false
        for _, s in ipairs(self.LINE_STYLES) do ok = ok or db[k] == s end
        if not ok then db[k] = nil end
    end
    for k, v in pairs(self.DEFAULTS) do
        if type(v) == "table" then
            local c = db[k]
            local ok = type(c) == "table"
            for i = 1, 3 do ok = ok and type(c[i]) == "number" end
            db[k] = ok and { max(0, min(1, c[1])), max(0, min(1, c[2])), max(0, min(1, c[3])) } or { unpack(v) }
        elseif db[k] == nil then
            db[k] = v
        end
    end
    for k, r in pairs(self.RANGES) do
        if type(db[k]) ~= "number" then db[k] = self.DEFAULTS[k] end
        db[k] = max(r[1], min(r[2], db[k]))
    end
    -- node names left out of every route (the skip list): { [name] = true }
    local skip = {}
    if type(db.skip) == "table" then
        for name, on in pairs(db.skip) do
            if type(name) == "string" and on == true then skip[name] = true end
        end
    end
    db.skip = skip
    if db.navLabel ~= "number" and db.navLabel ~= "nodes" and db.navLabel ~= "both" then db.navLabel = "both" end
    -- taboo areas: { [mapID] = { { x1, y1, x2, y2, ... }, ... } }, map positions 0-1
    local taboos = {}
    if type(db.taboos) == "table" then
        for mapID, list in pairs(db.taboos) do
            if type(mapID) == "number" and type(list) == "table" then
                local keep = {}
                for _, xy in ipairs(list) do
                    if type(xy) == "table" and #xy >= 6 and #xy % 2 == 0 then
                        local ok = true
                        for i = 1, #xy do ok = ok and type(xy[i]) == "number" end
                        if ok then keep[#keep + 1] = xy end
                    end
                end
                if #keep > 0 then taboos[mapID] = keep end
            end
        end
    end
    db.taboos = taboos
    db.routes = type(db.routes) == "table" and db.routes or {}
    db.nextID = db.nextID or 1
    -- drop anything that isn't a usable route
    for i = #db.routes, 1, -1 do
        local r = db.routes[i]
        if type(r) ~= "table" or type(r.mapID) ~= "number" or type(r.points) ~= "table" then
            table.remove(db.routes, i)
        else
            r.kinds = type(r.kinds) == "table" and r.kinds or {}
            r.name = type(r.name) == "string" and r.name or "Route"
            r.color = type(r.color) == "table" and r.color or { 1, 0.82, 0 }
            if r.shown == nil then r.shown = true end
            if not r.id then r.id = db.nextID; db.nextID = db.nextID + 1 end
            r.merge = nil   -- gone in 1.3.0: "route passes within" groups nearby nodes itself
            if r.drawn ~= nil then
                local ok = type(r.drawn) == "table" and #r.drawn >= 4 and #r.drawn % 2 == 0
                for k = 1, ok and #r.drawn or 0 do ok = ok and type(r.drawn[k]) == "number" end
                if not ok then r.drawn = nil end
            end
            r.working, r.walkDone, r.walkOf, r.walkLegs, r.walkTrace, r.walkTraceOf = nil, nil, nil, nil, nil, nil
        end
    end
    self.db = db
end

---------------------------------------------------------------------------
-- Bringing routes over from GatherPath Plus or GatherPath Forever (same kind
-- of saved routes). Their saved settings are only there while that addon is
-- switched on too. Routes already here (same zone and name) are left alone.
---------------------------------------------------------------------------
local function Copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = Copy(x) end
    return out
end

GP.IMPORT_SOURCES = { { "GatherPathPlusDB", "GatherPath Plus" }, { "GatherPathForeverDB", "GatherPath Forever" } }

-- The first other addon's saved routes there are: db, its name
function GP:ImportSource()
    for _, src in ipairs(self.IMPORT_SOURCES) do
        local db = _G[src[1]]
        if type(db) == "table" and type(db.routes) == "table" and #db.routes > 0 then return db, src[2] end
    end
    return nil
end

-- Returns how many routes came over (nil: nothing to bring)
function GP:ImportRoutes(quiet)
    local src, from = self:ImportSource()
    if not src then
        if not quiet then Print(L["no routes from GatherPath Plus or GatherPath Forever to bring over (that addon has to be switched on too)."]) end
        return nil
    end
    local db = self.db
    local have = {}
    for _, r in ipairs(db.routes) do have[r.mapID .. "\0" .. r.name] = true end
    local n = 0
    for _, r in ipairs(src.routes) do
        if type(r) == "table" and type(r.mapID) == "number" and type(r.points) == "table" and type(r.name) == "string"
            and not have[r.mapID .. "\0" .. r.name] then
            local c = Copy(r)
            c.id = db.nextID
            db.nextID = db.nextID + 1
            c.working = nil
            db.routes[#db.routes + 1] = c
            n = n + 1
        end
    end
    if type(src.taboos) == "table" then
        for mapID, list in pairs(src.taboos) do
            if type(mapID) == "number" and type(list) == "table" and not db.taboos[mapID] then
                db.taboos[mapID] = Copy(list)
            end
        end
    end
    if type(src.skip) == "table" then
        for name, on in pairs(src.skip) do if type(name) == "string" and on == true then db.skip[name] = true end end
    end
    db.imported = true
    local keep = self.db
    self:LoadSettings()   -- checks what came over like anything saved
    self.db = keep
    Print((n == 1 and L["brought 1 route over from %s. You can switch %s off now."]:format(from, from))
        or L["brought %d routes over from %s. You can switch %s off now."]:format(n, from, from))
    self:Changed()
    return n
end

-- The Display tab's Restore defaults: every setting on it as it was to start
function GP:RestoreDefaults()
    local db = self.db
    for _, k in ipairs(self.DISPLAY_KEYS) do
        local v = self.DEFAULTS[k]
        db[k] = type(v) == "table" and { unpack(v) } or v
    end
    db.hiddenWas = nil   -- lines hidden from the minimap button come back too
    if self.UpdateMinimapButton then self:UpdateMinimapButton() end
    self:Changed()
end

---------------------------------------------------------------------------
-- Maps
---------------------------------------------------------------------------
function GP:MapName(mapID)
    local info = mapID and C_Map.GetMapInfo(mapID)
    return info and info.name or ("Map " .. tostring(mapID))
end

function GP:PlayerMap()
    return C_Map.GetBestMapForUnit("player")
end

-- How many yards across and down a map is. Cached; nil if the game can't say.
local yardCache = {}
function GP:MapYards(mapID)
    if yardCache[mapID] then return yardCache[mapID][1], yardCache[mapID][2] end
    local w, h
    if C_Map.GetMapWorldSize then
        w, h = C_Map.GetMapWorldSize(mapID)
    end
    if not (w and h and w > 0 and h > 0) and C_Map.GetWorldPosFromMapPos and CreateVector2D then
        local _, a = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 0))
        local _, b = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(1, 1))
        if a and b then
            local ax, ay = a:GetXY()
            local bx, by = b:GetXY()
            w, h = math.abs(ay - by), math.abs(ax - bx)   -- the world's x runs north, y west
        end
    end
    if not (w and h and w > 0 and h > 0) then return nil end
    yardCache[mapID] = { w, h }
    return w, h
end

-- Yards for the route solver; a map the game can't measure is taken as 1500 x 1000
local function Yards(mapID)
    local w, h = GP:MapYards(mapID)
    return w or 1500, h or 1000
end

local function PlayerPos(mapID)
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return nil end
    local x, y = pos.x, pos.y
    if x == nil and pos.GetXY then x, y = pos:GetXY() end
    if not x or (x == 0 and y == 0) then return nil end
    return x, y
end
GP.PlayerPos = PlayerPos

---------------------------------------------------------------------------
-- GatherMate2
---------------------------------------------------------------------------
function GP:HasGatherMate()
    local gm = _G.GatherMate2
    return type(gm) == "table" and type(gm.GetNodesForZone) == "function" and type(gm.DecodeLoc) == "function"
end

-- Our kinds of node, from every node source (Sources.lua)
function GP:Kinds() return self.Sources.Kinds() end

function GP:KindName(kind) return L[self.KIND_NAMES[kind] or kind] end

-- Calls fn(x, y, nodeName) for every node of that kind on that map, from
-- GatherMate2 and/or GatherLite
function GP:EachNode(mapID, kind, fn) return self.Sources.EachNode(mapID, kind, fn) end

-- The skip list: node names (Poor Copper Ore, Wilted Peacebloom...) that no
-- route uses, in any zone. Routes that had one drop it when they're rebuilt.
function GP:IsSkipped(name) return self.db.skip[name] == true end

function GP:SetSkipped(name, on)
    if type(name) ~= "string" then return end
    self.db.skip[name] = on and true or nil
    self:Changed()
end

-- The skipped names, sorted
function GP:SkippedNames()
    local list = {}
    for name in pairs(self.db.skip) do list[#list + 1] = name end
    table.sort(list)
    return list
end

-- What the node sources know on a map: { { kind =, name =, count =, skip = }, ... }, by kind then name
function GP:ZoneNodes(mapID)
    local list = {}
    for _, kind in ipairs(self:Kinds()) do
        local counts = {}
        self:EachNode(mapID, kind, function(_, _, name) counts[name] = (counts[name] or 0) + 1 end)
        local names = {}
        for name in pairs(counts) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            list[#list + 1] = { kind = kind, name = name, count = counts[name], skip = self:IsSkipped(name) }
        end
    end
    return list
end

-- The maps there are nodes for (in any source), sorted by name
function GP:GatherZones()
    local found = {}
    self.Sources.Zones(found)
    local here = self:PlayerMap()
    if here then found[here] = true end
    local list = {}
    for mapID in pairs(found) do list[#list + 1] = mapID end
    table.sort(list, function(a, b) return self:MapName(a) < self:MapName(b) end)
    return list
end

-- The nodes a route is made from, as { x, y } map positions (none on the skip list)
function GP:CollectNodes(mapID, kinds)
    local pts = {}
    local skip = self.db.skip
    for kind, names in pairs(kinds) do
        self:EachNode(mapID, kind, function(x, y, name)
            if names[name] and not skip[name] then pts[#pts + 1] = { x, y } end
        end)
    end
    -- the same order every time, whatever order GatherMate2 gives them in
    table.sort(pts, function(a, b) if a[1] ~= b[1] then return a[1] < b[1] end return a[2] < b[2] end)
    return pts
end

-- A name for a route from what's in it: "Peacebloom", "Peacebloom and Silverleaf", "Herbs", "Herbs and Ore"...
function GP:RouteName(mapID, kinds)
    local names, whole = {}, {}
    local all = self:ZoneNodes(mapID)
    local perKind = {}
    for _, n in ipairs(all) do
        if not n.skip then perKind[n.kind] = (perKind[n.kind] or 0) + 1 end
    end
    for _, kind in ipairs(self:Kinds()) do
        local picked = kinds[kind]
        if picked and next(picked) then
            local list = {}
            for name in pairs(picked) do
                if not self:IsSkipped(name) then list[#list + 1] = name end
            end
            table.sort(list)
            if #list > 2 and #list >= (perKind[kind] or 0) then
                whole[#whole + 1] = self:KindName(kind)
            else
                for _, n in ipairs(list) do names[#names + 1] = n end
            end
        end
    end
    for _, w in ipairs(whole) do names[#names + 1] = w end
    if #names == 0 then return L["Route"] end
    if #names == 1 then return names[1] end
    if #names == 2 then return L["%s and %s"]:format(names[1], names[2]) end
    return L["%s, %s and %d more"]:format(names[1], names[2], #names - 2)
end

---------------------------------------------------------------------------
-- Routes
---------------------------------------------------------------------------
function GP:RoutesOn(mapID)
    local list = {}
    for _, r in ipairs(self.db.routes) do
        if r.mapID == mapID then list[#list + 1] = r end
    end
    return list
end

-- The maps that have routes, sorted by name
function GP:RouteZones()
    local seen, list = {}, {}
    for _, r in ipairs(self.db.routes) do
        if not seen[r.mapID] then seen[r.mapID] = true; list[#list + 1] = r.mapID end
    end
    table.sort(list, function(a, b) return self:MapName(a) < self:MapName(b) end)
    return list
end

-- Stops on the loop (fewer than nodes when the route only passes near them)
function GP:NodeCount(route) return floor(#route.points / 2) end

-- What the lines are drawn through: the way on foot between the stops
-- (route.drawn, from Build) when there is one, else the stops themselves.
-- Returns the flat list { x1, y1, ... } and how many points.
function GP:DrawPoints(route)
    local d = route.drawn
    if type(d) == "table" and #d >= 4 then return d, floor(#d / 2) end
    return route.points, floor(#route.points / 2)
end

-- Nodes the route takes you past
function GP:RouteNodes(route) return route.nodes or self:NodeCount(route) end

-- The route's length in yards, round the loop
function GP:RouteLength(route)
    local w, h = Yards(route.mapID)
    local p = route.points
    local n = floor(#p / 2)
    if n < 2 then return 0 end
    local total = 0
    for i = 1, n do
        local j = i % n + 1
        local dx, dy = (p[2 * j - 1] - p[2 * i - 1]) * w, (p[2 * j] - p[2 * i]) * h
        total = total + sqrt(dx * dx + dy * dy)
    end
    return total * (route.walkFactor or 1)   -- on foot over the ground: longer than the straight lines
end

local function Round(v) return floor(v * 10000 + 0.5) / 10000 end

---------------------------------------------------------------------------
-- Taboo areas: parts of a zone routes keep out of. No node inside one is
-- used, and a line that would cross one goes round it instead.
---------------------------------------------------------------------------
-- The taboo areas on a map: a list of flat { x1, y1, x2, y2, ... } (map positions)
function GP:Taboos(mapID)
    return self.db.taboos[mapID] or {}
end

-- The taboo areas of a map as walls for the solver (yards), or nil if none.
-- Kept until an area changes.
local wallCache = {}
GP.tabooVersion = 0
local function WallsFor(mapID)
    -- your own areas, and the ready-made ones on now (NoGo.lua)
    local list = {}
    for _, xy in ipairs(GP.db.taboos[mapID] or {}) do list[#list + 1] = xy end
    if GP.NoGoPolys then
        for _, xy in ipairs(GP:NoGoPolys(mapID)) do list[#list + 1] = xy end
    end
    if #list == 0 then return nil end
    local c = wallCache[mapID]
    if c and c.version == GP.tabooVersion then return c.walls end
    local w, h = Yards(mapID)
    local polys = {}
    for i, xy in ipairs(list) do
        local p = {}
        for k = 1, #xy, 2 do p[k], p[k + 1] = xy[k] * w, xy[k + 1] * h end
        polys[i] = p
    end
    local walls = O.Walls(polys)
    wallCache[mapID] = { version = GP.tabooVersion, walls = walls }
    return walls
end
GP.WallsFor = WallsFor

-- Is this map position inside one of the map's taboo areas?
function GP:InTaboo(mapID, x, y)
    local walls = WallsFor(mapID)
    if not walls then return false end
    local w, h = Yards(mapID)
    return walls:Inside({ x * w, y * h })
end

-- Adds a taboo area (flat list of 3 or more corners, map positions). Turned
-- down if its edges cross. Every route on that map is then worked out again.
function GP:AddTaboo(mapID, xy)
    if type(mapID) ~= "number" or type(xy) ~= "table" or #xy < 6 then
        Print(L["a no-go area needs at least 3 corners."])
        return false
    end
    local w, h = Yards(mapID)
    local yards = {}
    for k = 1, #xy, 2 do yards[k], yards[k + 1] = xy[k] * w, xy[k + 1] * h end
    if O.SelfCrossing(yards) then
        Print(L["that area's edges cross each other. Right-click to take corners back until they don't, then Finish."])
        return false
    end
    local copy = {}
    for k = 1, #xy do copy[k] = Round(xy[k]) end
    self.db.taboos[mapID] = self.db.taboos[mapID] or {}
    table.insert(self.db.taboos[mapID], copy)
    self.tabooVersion = self.tabooVersion + 1
    self:Changed()
    self:RebuildZone(mapID)
    return true
end

function GP:DeleteTaboo(mapID, index)
    local list = self.db.taboos[mapID]
    if not (list and list[index]) then return false end
    table.remove(list, index)
    if #list == 0 then self.db.taboos[mapID] = nil end
    self.tabooVersion = self.tabooVersion + 1
    self:Changed()
    self:RebuildZone(mapID)
    return true
end

-- " 3 nodes in no-go areas left out." after a route's chat line, or ""
function GP:WalkNote(route)
    if route.walked then
        if route.walkOther and route.walkOther - route.length >= 1 then
            return L[" Measured on foot over the ground; %s shorter than the straight-line loop."]
                :format(self.FormatYards(route.walkOther - route.length))
        end
        return L[" Measured on foot over the ground."]
    end
    if route.walkSkipped then return L[" Straight lines: %s."]:format(L[route.walkSkipped]) end
    return ""
end

function GP:TabooNote(route)
    local n = route.taboo or 0
    if n <= 0 then return "" end
    return n == 1 and L[" 1 node in a no-go area left out."] or L[" %d nodes in no-go areas left out."]:format(n)
end

-- Rebuilds every route on a map, one after another
function GP:RebuildZone(mapID)
    self.queue = self.queue or {}
    for _, route in ipairs(self:RoutesOn(mapID)) do
        local queued = false
        for _, r in ipairs(self.queue) do if r == route then queued = true end end
        if not queued then self.queue[#self.queue + 1] = route end
    end
    self:PumpQueue()
end

-- Starts the next queued rebuild if nothing's being worked out
function GP:PumpQueue()
    local q = self.queue
    while q and #q > 0 and not self.job do
        local route = table.remove(q, 1)
        local alive = false
        for _, r in ipairs(self.db.routes) do if r == route then alive = true end end
        if alive and not route.working then self:RebuildRoute(route) end
    end
end

-- Inside a job: wait for something worked out elsewhere (a walk), and let
-- this frame go
function GP:JobWait()
    if self.job and coroutine.running() == self.job then coroutine.yield("wait") end
end

-- Walking detours between the spots a route is made from (Walk.lua, the
-- game's walking maps): from each spot, yards on foot to its WALK_NEAR nearest,
-- WALK_PARALLEL searches at a time; the pairs not measured go by the shortest
-- way through the ones that were (O.DetourFactors). Returns f[i][j] = on foot
-- / straight for every pair, and how many were measured; or nil and why not.
GP.WALK_NEAR = 16
GP.WALK_PARALLEL = 4
GP.WALK_SLACK = 40
GP.WALK_NO_WAY = 25
GP.WALK_TIMEOUT = 300   -- seconds before giving up and going straight
GP.WALK_BUDGET_MS = 8   -- milliseconds a frame the walking search may take while a route is worked out
local function WalkDetours(route, spots, w, h)
    if not GP.db.walkRoutes then return nil, nil end
    local Walk = GP.Walk
    if not Walk then return nil, "no walking search" end
    local ok, why = Walk.Ready(route.mapID)
    if not ok then return nil, why end
    local m = #spots
    if m < 3 then return nil, nil end
    -- each spot's nearest others, straight
    local near = {}
    for i = 1, m do
        local a, list = spots[i], {}
        for j = 1, m do
            if j ~= i then list[#list + 1] = { j, O.Euclid(a, spots[j]) } end
        end
        table.sort(list, function(x, y) return x[2] < y[2] end)
        local keep = {}
        for k = 1, math.min(GP.WALK_NEAR, #list) do keep[k] = list[k] end
        near[i] = keep
        if i % 20 == 0 then O.Pause() end
    end
    local f, measured, failed, running, nextSpot = {}, 0, 0, 0, 1
    local jobs = {}
    local function Launch(i)
        local list, targets = near[i], {}
        for k, e in ipairs(list) do targets[k] = { spots[e[1]][1] / w, spots[e[1]][2] / h } end
        running = running + 1
        jobs[#jobs + 1] = Walk.Costs(route.mapID, spots[i][1] / w, spots[i][2] / h, targets, function(costs)
            running = running - 1
            route.walkDone = (route.walkDone or 0) + 1
            local any = false
            for k = 1, #list do if costs and costs[k] then any = true end end
            if not any then failed = failed + 1 return end   -- off the walking map here: leave it unknown
            local row = {}
            for k, e in ipairs(list) do
                row[e[1]] = costs[k] or false
                measured = measured + 1
            end
            f[i] = row
        end)
    end
    route.walkDone, route.walkOf = 0, m
    local began = GetTime()
    while nextSpot <= m or running > 0 do
        while running < GP.WALK_PARALLEL and nextSpot <= m do Launch(nextSpot); nextSpot = nextSpot + 1 end
        if running > 0 then
            if GetTime() - began > GP.WALK_TIMEOUT then
                for _, job in ipairs(jobs) do Walk.Cancel(job) end
                return nil, "the walking maps took too long"
            end
            if GP.RefreshConfig then GP:RefreshConfig() end
            GP:JobWait()
        end
    end
    if measured == 0 then return nil, "none of the nodes are on the walking map" end
    return O.DetourFactors(spots, f, GP.WALK_SLACK, GP.WALK_NO_WAY), measured
end
GP.WalkDetours = WalkDetours


local function DrawnLength(stops)
    local order = {}
    for i = 1, #stops do order[i] = i end
    return O.Length(stops, order)
end

-- Several loops, each measured on foot, the shortest kept: the usual one
-- (straight lines) and ones worked out with the walking detours, at full
-- strength and softened (WALK_SOFTEN: the factors to the power of each). How
-- well a detour-guided loop does varies a lot from zone to zone, so the walk
-- round each loop decides, never the guess. Then the best two are polished
-- with walked legs (O.Polish: 2-opt and moving single stops) and the shorter
-- kept. Measured on Shortest Path's real walking maps (250 random nodes,
-- passes within 185): Dun Morogh and Loch Modan about 28% shorter on foot than
-- the straight-line loop, the Barrens 15%, Ashenvale 6%, Elwynn the same.
-- Moving a stop off its spot (to cut a corner) can put it where the way on
-- foot is much longer than the spot's own walks said (up a ledge): legs that
-- come out more than WALK_WRONG times what was expected pin their stops to
-- their spots, and the loop is worked out again (WALK_REPAIRS times at most).
GP.WALK_WRONG = 1.3
GP.WALK_REPAIRS = 3
GP.WALK_SOFTEN = { 1, 0.75, 0.5, 0.25 }
GP.WALK_POLISH = 6        -- polishing passes
GP.WALK_POLISH_NEAR = 8   -- stops each one is tried against

-- Legs on foot, measured once each (either way round counts for both)
local function LegCache(route, w, h)
    local cache, queue = {}, {}
    local running = 0
    local function Key(a, b)
        local ka, kb = L["%.1f,%.1f"]:format(a[1], a[2]), L["%.1f,%.1f"]:format(b[1], b[2])
        if ka > kb then ka, kb = kb, ka end
        return ka .. ">" .. kb
    end
    local function Launch(a, b, key)
        cache[key] = "busy"
        running = running + 1
        GP.Walk.Cost(route.mapID, a[1] / w, a[2] / h, b[1] / w, b[2] / h, function(yards, why)
            running = running - 1
            if yards then
                cache[key] = yards
            elseif why == "unreachable" then
                cache[key] = O.Euclid(a, b) * GP.WALK_NO_WAY
            else
                cache[key] = O.Euclid(a, b)   -- off the walking map: count it straight
            end
            route.walkLegs = (route.walkLegs or 0) + 1
        end)
    end
    local L = {}
    function L.Get(a, b)
        local key = Key(a, b)
        local c = cache[key]
        if type(c) == "number" then return c end
        if c == nil then Launch(a, b, key) end
        local began = GetTime()
        while type(cache[key]) ~= "number" do
            if GetTime() - began > GP.WALK_TIMEOUT then cache[key] = O.Euclid(a, b) break end
            GP:JobWait()
        end
        return cache[key]
    end
    function L.Prefetch(pairs_)
        local todo = {}
        for _, pr in ipairs(pairs_) do
            local key = Key(pr[1], pr[2])
            if cache[key] == nil then cache[key] = "todo"; todo[#todo + 1] = { pr[1], pr[2], key } end
        end
        local i, began = 1, GetTime()
        while i <= #todo or running > 0 do
            while running < GP.WALK_PARALLEL * 2 and i <= #todo do
                Launch(todo[i][1], todo[i][2], todo[i][3])
                i = i + 1
            end
            if GetTime() - began > GP.WALK_TIMEOUT * 2 then break end
            GP:JobWait()
        end
        for _, t in ipairs(todo) do
            if type(cache[t[3]]) ~= "number" then cache[t[3]] = nil end
        end
    end
    function L.Loop(stops)
        local n = #stops
        local pairs_ = {}
        for i = 1, n do pairs_[i] = { stops[i], stops[i % n + 1] } end
        L.Prefetch(pairs_)
        local total, legs = 0, {}
        for i = 1, n do
            legs[i] = L.Get(stops[i], stops[i % n + 1])
            total = total + legs[i]
        end
        return total, legs
    end
    return L
end

local function GroundLoop(route, spots, radius, f, w, h)
    local legs = LegCache(route, w, h)
    local tried = {}
    local straightFoot
    for c, k in ipairs({ 0, unpack(GP.WALK_SOFTEN) }) do
        local factors
        if k > 0 then
            factors = {}
            for i, row in pairs(f) do
                factors[i] = {}
                for j, v in pairs(row) do factors[i][j] = v ^ k end
            end
        end
        for _, sp in ipairs(spots) do sp.pin = nil end
        if factors then O.SetDetour(spots, factors) end
        local loop = O.Expand(O.Shortcut(spots, radius, true))
        O.SetDetour(nil)
        local foot, each = legs.Loop(loop)
        for _ = 1, factors and GP.WALK_REPAIRS or 0 do
            O.SetDetour(spots, factors)
            local pinned = 0
            for i = 1, #loop do
                local a, b = loop[i], loop[i % #loop + 1]
                if each[i] > O.Dist(a, b) * GP.WALK_WRONG + 60 then
                    for _, st in ipairs({ a, b }) do
                        local node = st.node or (st.anchor and spots[st.anchor])
                        if node and not node.pin then node.pin = true; pinned = pinned + 1 end
                    end
                end
            end
            if pinned == 0 then O.SetDetour(nil) break end
            local again = O.Expand(O.Shortcut(spots, radius, true))
            O.SetDetour(nil)
            local foot2, each2 = legs.Loop(again)
            if foot2 < foot then loop, foot, each = again, foot2, each2 else break end
        end
        if c == 1 then straightFoot = foot end
        tried[#tried + 1] = { loop = loop, foot = foot, ground = c > 1 }
    end
    for _, sp in ipairs(spots) do sp.pin = nil end
    table.sort(tried, function(a, b) return a.foot < b.foot end)
    -- polish the best two (the best detour-guided one and the best overall, if different)
    local polish = { tried[1] }
    for i = 2, #tried do
        if tried[i].ground ~= tried[1].ground then polish[2] = tried[i] break end
    end
    -- taboo areas still hold: a leg through one costs as if there were no way
    local walls = O.GetWalls()
    local function Cost(a, b)
        if walls and walls:Blocked(a, b) then return O.Euclid(a, b) * GP.WALK_NO_WAY end
        return legs.Get(a, b)
    end
    route.walkPolish = 0
    local best
    for _, t in ipairs(polish) do
        local loop = O.Polish(t.loop, Cost, GP.WALK_POLISH, GP.WALK_POLISH_NEAR, legs.Prefetch)
        local foot = legs.Loop(loop)
        if foot < t.foot then t.loop, t.foot = loop, foot end
        if not best or t.foot < best.foot then best = t end
        route.walkPolish = route.walkPolish + 1
    end
    route.walkPolish = nil
    route.walkLegs = nil
    return best.loop, best.foot, straightFoot, best.ground
end

-- The lines along the ground: the way on foot for each leg of the loop
-- (Walk.Line, smoothed by the walking search), WALK_PARALLEL at a time.
-- Returns the loop as one flat list of map positions, stops included, or nil
-- if no leg could be traced. A leg that can't be is drawn straight. Points
-- within TRACE_KEEP yards of the line between their neighbours are dropped.
GP.TRACE_KEEP = 1.5
local function TraceLines(route, stops, w, h)
    local Walk = GP.Walk
    local n = #stops
    if not Walk or n < 2 then return nil end
    local legs, running, nextLeg, traced = {}, 0, 1, 0
    route.walkTrace, route.walkTraceOf = 0, n
    local function Launch(i)
        local a, b = stops[i], stops[i % n + 1]
        running = running + 1
        Walk.Line(route.mapID, a[1] / w, a[2] / h, b[1] / w, b[2] / h, function(xy)
            running = running - 1
            route.walkTrace = route.walkTrace + 1
            if xy and #xy >= 4 then legs[i] = xy; traced = traced + 1 end
        end)
    end
    local began = GetTime()
    while nextLeg <= n or running > 0 do
        while running < GP.WALK_PARALLEL * 2 and nextLeg <= n do Launch(nextLeg); nextLeg = nextLeg + 1 end
        if running > 0 then
            if GetTime() - began > GP.WALK_TIMEOUT then break end
            if GP.RefreshConfig then GP:RefreshConfig() end
            GP:JobWait()
        end
    end
    route.walkTrace, route.walkTraceOf = nil, nil
    if traced == 0 then return nil end
    -- yards from c to the line a-b, in map positions
    local function Off(ax, ay, bx, by, cx, cy)
        return O.SegDist({ ax * w, ay * h }, { bx * w, by * h }, { cx * w, cy * h })
    end
    local out = {}
    for i = 1, n do
        local a = stops[i]
        local sx, sy = Round(a[1] / w), Round(a[2] / h)
        out[#out + 1] = sx
        out[#out + 1] = sy
        local xy = legs[i]
        if xy then
            -- the inside of the way (its ends are the stops)
            local lx, ly = sx, sy
            local m = #xy / 2
            for k = 2, m - 1 do
                local x, y = Round(xy[2 * k - 1]), Round(xy[2 * k])
                local nx, ny = xy[2 * k + 1], xy[2 * k + 2]
                if Off(lx, ly, nx, ny, x, y) > GP.TRACE_KEEP then
                    out[#out + 1] = x
                    out[#out + 1] = y
                    lx, ly = x, y
                end
            end
        end
        if i % 10 == 0 then O.Pause() end
    end
    return out
end

-- Reads the route's nodes from GatherMate2 and finds the shortest loop.
-- Runs inside a job (it pauses now and then). Returns how many nodes it read.
local function Build(route)
    local raw = GP:CollectNodes(route.mapID, route.kinds)
    local w, h = Yards(route.mapID)
    local walls = WallsFor(route.mapID)
    local pts = {}
    for _, p in ipairs(raw) do
        local q = { p[1] * w, p[2] * h }
        if not (walls and walls:Inside(q)) then pts[#pts + 1] = q end   -- none from inside a taboo area
    end
    O.SetWalls(walls)
    local radius = route.sight or 0
    local spots = O.GroupFor(pts, radius)
    local f, measured = WalkDetours(route, spots, w, h)
    route.walkDone, route.walkOf = nil, nil
    route.walked, route.walkSkipped, route.walkFactor, route.walkGround, route.walkOther = nil, nil, nil, nil, nil
    if f then
        route.walked = measured
    elseif measured then
        route.walkSkipped = measured   -- why not
    end
    local stops
    if f then
        local foot, other, ground
        local was = ns.Path and ns.Path.budget
        if was then ns.Path.budget = GP.WALK_BUDGET_MS end
        stops, foot, other, ground = GroundLoop(route, spots, radius, f, w, h)
        if was then ns.Path.budget = was end
        local drawn = DrawnLength(stops)
        if foot and drawn > 0 then route.walkFactor = math.max(1, foot / drawn) end
        route.walkGround = ground or nil
        route.walkOther = other and math.floor(other + 0.5) or nil
    else
        stops = O.Expand(O.Shortcut(spots, radius, true))
    end
    O.SetDetour(nil)
    O.SetWalls(nil)
    local flat = {}
    for _, p in ipairs(stops) do
        flat[#flat + 1] = Round(p[1] / w)
        flat[#flat + 1] = Round(p[2] / h)
    end
    route.points = flat
    route.drawn = route.walked and TraceLines(route, stops, w, h) or nil
    route.nodes = #pts
    route.taboo = #raw - #pts   -- left out: in taboo areas
    route.length = GP:RouteLength(route)
    return #pts
end

-- One route is worked out at a time, a little each frame, so a big one
-- doesn't freeze the game
local BUDGET_MS = 10
local clock = debugprofilestop or function() return GetTime() * 1000 end

function GP:Busy() return self.job ~= nil end

function GP:RunJob(fn, done)
    if self.job then return false end
    local co = coroutine.create(fn)
    self.job = co
    O.Pause = function()
        if coroutine.running() == co then coroutine.yield() end
    end
    local driver = self.jobFrame
    if not driver then
        driver = CreateFrame("Frame")
        self.jobFrame = driver
    end
    driver:SetScript("OnUpdate", function()
        local start = clock()
        repeat
            local ok, a, b = coroutine.resume(co)
            if not ok then
                driver:SetScript("OnUpdate", nil)
                self.job = nil
                O.Pause = function() end
                O.SetWalls(nil)
                O.SetDetour(nil)
                Print(L["|cffff5050couldn't work out the route:|r %s"]:format(tostring(a)))
                if self.Changed then self:Changed() end
                return
            end
            if coroutine.status(co) == "dead" then
                driver:SetScript("OnUpdate", nil)
                self.job = nil
                O.Pause = function() end
                done(a, b)
                self:PumpQueue()
                return
            end
            if a == "wait" then return end   -- waiting on a walk: try again next frame
        until clock() - start > BUDGET_MS
    end)
    if self.Changed then self:Changed() end
    return true
end

GP.FormatYards = function(v)
    v = floor((v or 0) + 0.5)
    local sep = ns.LOCALE == "deDE" and "." or ","
    local s = tostring(v):reverse():gsub("(%d%d%d)", "%1" .. sep):reverse()
    if s:sub(1, 1) == sep then s = s:sub(2) end
    return L["%s yards"]:format(s)
end

-- How fast you travel, in yards a second, for a lap's time: the last mount
-- speed seen (db.speed), else your speed on foot (7)
GP.FOOT_SPEED = 7
function GP:Speed()
    local s = self.db and self.db.speed
    return type(s) == "number" and s > 0 and s or self.FOOT_SPEED
end

-- Remember your ground speed while it's faster than on foot (mounted). The
-- game can hide it (a secret value), then it's left alone. True if it changed.
function GP:SampleSpeed()
    if not (GetUnitSpeed and self.db) then return false end
    local ok, changed = pcall(function()
        local _, run = GetUnitSpeed("player")
        if issecretvalue and issecretvalue(run) then return false end
        if type(run) ~= "number" or run <= self.FOOT_SPEED + 0.5 or run > 100 then return false end
        run = floor(run * 10 + 0.5) / 10
        if run == self.db.speed then return false end
        self.db.speed = run
        return true
    end)
    return ok and changed or false
end

-- About how long one lap of a route takes at Speed(), in words
function GP:LapTime(route)
    local secs = (route.length or self:RouteLength(route)) / self:Speed()
    if secs < 60 then return L["under a minute"] end
    local mins = floor(secs / 60 + 0.5)
    if mins < 60 then return L["about %d min"]:format(mins) end
    return L["about %d h %02d min"]:format(floor(mins / 60), mins % 60)
end

-- The route on this map already called this (any case, spaces round it ignored), but not `except`
function GP:RouteNamed(mapID, name, except)
    local want = type(name) == "string" and name:match("^%s*(.-)%s*$"):lower()
    if not want or want == "" then return nil end
    for _, r in ipairs(self.db.routes) do
        if r ~= except and r.mapID == mapID and r.name:match("^%s*(.-)%s*$"):lower() == want then return r end
    end
end

local function NameTakenMessage(name, mapID)
    return L["there's already a route called |cffffd100%s|r in %s. Give this one another name, or Rebuild that one."]:format(name, GP:MapName(mapID))
end

-- Is any node picked in kinds ({ [kind] = { [name] = true } }) that isn't skipped?
function GP:AnyPicked(kinds)
    for _, names in pairs(kinds or {}) do
        for name, on in pairs(names) do
            if on and not self:IsSkipped(name) then return true end
        end
    end
    return false
end

-- opts: mapID, kinds = { [kind] = { [name] = true } }, name, sight
function GP:NewRoute(opts)
    if not self:HasNodeSource() then
        Print(L["needs GatherMate2 or GatherLite, where the nodes come from."])
        return nil
    end
    if not self:AnyPicked(opts.kinds) then
        Print(L["pick at least one kind of node."])
        return nil
    end
    if self.job then
        Print(L["still working out the last route. Try again in a moment."])
        return nil
    end
    local name = (type(opts.name) == "string" and opts.name:match("^%s*(.-)%s*$")) or ""
    if name == "" then name = self:RouteName(opts.mapID, opts.kinds) end
    if self:RouteNamed(opts.mapID, name) then
        Print(NameTakenMessage(name, opts.mapID))
        return nil
    end
    local route = {
        id = self.db.nextID,
        mapID = opts.mapID,
        name = name,
        kinds = opts.kinds,
        sight = opts.sight or 0,
        color = { unpack(self.COLORS[(self.db.nextColor - 1) % #self.COLORS + 1]) },
        shown = true,
        points = {},
        working = true,
    }
    self.db.nextID = self.db.nextID + 1
    self.db.nextColor = self.db.nextColor % #self.COLORS + 1
    table.insert(self.db.routes, route)
    self:RunJob(function() return Build(route) end, function(read)
        route.working = nil
        if self:NodeCount(route) < 2 then
            self:DeleteRoute(route)
            Print((read == 1 and L["there's only one node of those kinds in %s, so there's no route to make."]
                or L["there's no node of those kinds in %s, so there's no route to make."]):format(self:MapName(route.mapID)))
            return
        end
        Print(L["made |cffffd100%s|r in %s: %d nodes, %s round.%s"]:format(route.name, self:MapName(route.mapID),
            self:RouteNodes(route), self.FormatYards(route.length), self:TabooNote(route) .. self:WalkNote(route)))
        self:Changed()
    end)
    return route
end

-- Reads the nodes again (GatherMate2 may know more by now) and finds the loop again
function GP:RebuildRoute(route)
    if self.job then
        Print(L["still working out the last route. Try again in a moment."])
        return false
    end
    if not self:HasNodeSource() then
        Print(L["needs GatherMate2 or GatherLite, where the nodes come from."])
        return false
    end
    local before, oldPoints, oldNodes = self:RouteNodes(route), route.points, route.nodes
    local oldWalk = { route.walked, route.walkSkipped, route.walkFactor }
    route.working = true
    return self:RunJob(function() return Build(route) end, function()
        route.working = nil
        if self:NodeCount(route) < 2 then
            route.points, route.nodes = oldPoints, oldNodes   -- (GatherMate2's data went missing: keep what was there)
            route.walked, route.walkSkipped, route.walkFactor = oldWalk[1], oldWalk[2], oldWalk[3]
            Print(L["there are no nodes for %s now, so it was left as it was."]:format(route.name))
        else
            local after = self:RouteNodes(route)
            Print(L["%s: %d nodes (%s), %s round.%s"]:format(route.name, after,
                after == before and "no change" or ((after > before and "+" or "") .. (after - before)),
                self.FormatYards(route.length), self:TabooNote(route) .. self:WalkNote(route)))
        end
        self:Changed()
    end)
end

-- Changes a route's options (opts as for NewRoute) and finds its loop again.
-- Turned down like NewRoute; if no loop can be made, the route stays as it was.
function GP:EditRoute(route, opts)
    if not self:HasNodeSource() then
        Print(L["needs GatherMate2 or GatherLite, where the nodes come from."])
        return false
    end
    if not self:AnyPicked(opts.kinds) then
        Print(L["pick at least one kind of node."])
        return false
    end
    if self.job then
        Print(L["still working out the last route. Try again in a moment."])
        return false
    end
    local mapID = opts.mapID or route.mapID
    local name = (type(opts.name) == "string" and opts.name:match("^%s*(.-)%s*$")) or ""
    if name == "" then name = self:RouteName(mapID, opts.kinds) end
    if self:RouteNamed(mapID, name, route) then
        Print(NameTakenMessage(name, mapID))
        return false
    end
    local old = { mapID = route.mapID, name = route.name, kinds = route.kinds,
        sight = route.sight, points = route.points, nodes = route.nodes, length = route.length,
        walked = route.walked or false, walkSkipped = route.walkSkipped or false, walkFactor = route.walkFactor or false }
    route.mapID, route.name, route.kinds = mapID, name, opts.kinds
    route.sight = opts.sight or 0
    route.working = true
    self:RunJob(function() return Build(route) end, function(read)
        route.working = nil
        if self:NodeCount(route) < 2 then
            for k, v in pairs(old) do route[k] = v or nil end
            Print((read == 1 and L["there's only one node of those kinds in %s, so %s was left as it was."]
                or L["there's no node of those kinds in %s, so %s was left as it was."]):format(self:MapName(mapID), route.name))
        else
            Print(L["changed |cffffd100%s|r in %s: %d nodes, %s round.%s"]:format(route.name, self:MapName(route.mapID),
                self:RouteNodes(route), self.FormatYards(route.length), self:TabooNote(route) .. self:WalkNote(route)))
        end
        self:Changed()
    end)
    return true
end

function GP:DeleteRoute(route)
    if self.IsNavigating and self:IsNavigating(route) then self:StopNav() end
    for i, r in ipairs(self.db.routes) do
        if r == route then table.remove(self.db.routes, i) break end
    end
    self:Changed()
end

function GP:RenameRoute(route, name)
    if type(name) == "string" and name:match("%S") then
        name = name:match("^%s*(.-)%s*$")
        if self:RouteNamed(route.mapID, name, route) then
            Print(NameTakenMessage(name, route.mapID))
            return false
        end
        route.name = name
        self:Changed()
        return true
    end
    return false
end

-- Turns a route round: the same loop, ridden the other way (the arrows and
-- Start follow the order of its stops). A ride on it starts again, the new way.
local function ReversePairs(list)
    if type(list) ~= "table" then return list end
    local out, n = {}, floor(#list / 2)
    for i = 1, n do
        out[2 * i - 1], out[2 * i] = list[2 * (n - i + 1) - 1], list[2 * (n - i + 1)]
    end
    return out
end
GP.ReversePairs = ReversePairs

-- Which way a route is ridden on the map: true clockwise, false anticlockwise
-- (nil for fewer than three stops). Map y grows southward, so a positive
-- shoelace sum is clockwise as you see it.
function GP:RouteClockwise(route)
    local p = route and route.points
    local n = p and floor(#p / 2) or 0
    if n < 3 then return nil end
    local sum = 0
    for i = 1, n do
        local j = i % n + 1
        sum = sum + p[2 * i - 1] * p[2 * j] - p[2 * j - 1] * p[2 * i]
    end
    if self.db and self.db.arrowsReverse then sum = -sum end
    return sum > 0
end

function GP:ReverseRoute(route)
    if not route or route.working or self:NodeCount(route) < 2 then return false end
    local riding = self.IsNavigating and self:IsNavigating(route)
    if riding then self:StopNav(true) end
    route.points = ReversePairs(route.points)
    if route.drawn then route.drawn = ReversePairs(route.drawn) end
    Print(L["|cffffd100%s|r turned round: you ride it the other way now."]:format(route.name))
    self:Changed()
    if riding then self:StartNav(route) end
    return true
end

function GP:SetRouteShown(route, on)
    route.shown = on and true or false
    self:Changed()
end

function GP:SetRouteColor(route, r, g, b)
    route.color = { r, g, b }
    self:Changed()
end

-- A node GatherMate2 just found goes into each route of its kind on that map,
-- where it adds the least walking. One already there (within 5 yards of a stop,
-- or its "route passes within" distance of the line) is left alone.
function GP:AddNode(mapID, kind, x, y, name)
    if not self.db.autoAdd or self:IsSkipped(name) then return 0 end
    local w, h = Yards(mapID)
    local walls = WallsFor(mapID)
    if walls and walls:Inside({ x * w, y * h }) then return 0 end   -- in a taboo area
    local added = 0
    for _, route in ipairs(self:RoutesOn(mapID)) do
        if not route.working and route.kinds[kind] and route.kinds[kind][name] then
            local p, n = route.points, self:NodeCount(route)
            local near, sight = 5, route.sight or 0
            local c = { x * w, y * h }
            local pts, tour, close = {}, {}, false
            for i = 1, n do
                pts[i] = { p[2 * i - 1] * w, p[2 * i] * h }
                tour[i] = i
                if O.Dist(pts[i], c) <= near then close = true end
            end
            for i = 1, (sight > 0 and n > 1) and n or 0 do
                if O.SegDist(pts[i], pts[i % n + 1], c) <= sight then close = true end
            end
            if not close then
                O.SetWalls(walls)
                local at = O.BestInsert(pts, tour, c)
                local spot = c
                if sight > 0 and n > 1 then
                    spot = O.Place(pts[at], pts[at % n + 1], c, sight)
                end
                -- with taboo areas, the corners the new legs bend round go in too
                local add = {}
                if walls then
                    for _, v in ipairs(walls:Path(pts[at], spot)) do add[#add + 1] = v end
                end
                add[#add + 1] = spot
                if walls and n > 1 then
                    for _, v in ipairs(walls:Path(spot, pts[at % n + 1])) do add[#add + 1] = v end
                end
                O.SetWalls(nil)
                for k, v in ipairs(add) do
                    table.insert(p, 2 * (at + k - 1) + 1, Round(v[1] / w))
                    table.insert(p, 2 * (at + k - 1) + 2, Round(v[2] / h))
                end
                route.length = self:RouteLength(route)
                route.drawn = nil   -- straight lines until it's rebuilt
                if route.nodes then route.nodes = route.nodes + 1 end
                added = added + 1
            end
        end
    end
    if added > 0 then self:Changed() end
    return added
end

-- A node deleted in GatherMate2 leaves the routes that have it (not ones that
-- only pass near their nodes)
function GP:RemoveNode(mapID, kind, x, y, name)
    local w, h = Yards(mapID)
    local walls = WallsFor(mapID)
    local removed = 0
    for _, route in ipairs(self:RoutesOn(mapID)) do
        if not route.working and route.kinds[kind] and route.kinds[kind][name]
            and (route.sight or 0) == 0 then
            local p = route.points
            for i = 1, self:NodeCount(route) do
                local dx, dy = (p[2 * i - 1] - x) * w, (p[2 * i] - y) * h
                if sqrt(dx * dx + dy * dy) < 1 then
                    table.remove(p, 2 * i - 1)
                    table.remove(p, 2 * i - 1)
                    local n = self:NodeCount(route)
                    if walls and n >= 2 then
                        -- its neighbours now meet: round any taboo area between them
                        local a = (i - 2) % n + 1
                        local b = a % n + 1
                        local pa, pb = { p[2 * a - 1] * w, p[2 * a] * h }, { p[2 * b - 1] * w, p[2 * b] * h }
                        for k, v in ipairs(walls:Path(pa, pb)) do
                            table.insert(p, 2 * (a + k - 1) + 1, Round(v[1] / w))
                            table.insert(p, 2 * (a + k - 1) + 2, Round(v[2] / h))
                        end
                    end
                    route.length = self:RouteLength(route)
                    route.drawn = nil
                    if route.nodes then route.nodes = route.nodes - 1 end
                    removed = removed + 1
                    break
                end
            end
        end
    end
    if removed > 0 then self:Changed() end
    return removed
end

-- New (and deleted) nodes from every source go into (and out of) the routes
function GP:ListenToGatherMate() self.Sources.Listen() end

---------------------------------------------------------------------------
-- Lines
---------------------------------------------------------------------------
-- A pool of lines on a frame: Get() hands out the next one; Done() hides the rest
local function LinePool(frame, layer)
    local pool = { lines = {}, used = 0 }
    function pool:Begin() self.used = 0 end
    function pool:Get()
        self.used = self.used + 1
        local line = self.lines[self.used]
        if not line then
            line = frame:CreateLine(nil, layer or "OVERLAY")
            line:SetTexture("Interface\\Buttons\\WHITE8X8")
            self.lines[self.used] = line
        end
        line:Show()
        return line
    end
    function pool:Done()
        for i = self.used + 1, #self.lines do self.lines[i]:Hide() end
    end
    return pool
end
GP.LinePool = LinePool

local function Paint(line, c, alpha, width)
    line:SetVertexColor(c[1], c[2], c[3], alpha)
    line:SetThickness(width)
end

-- A pool of round dots (textures) on a frame, like LinePool
local DOT_TEXTURE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local function DotPool(frame, layer)
    local pool = { dots = {}, used = 0 }
    function pool:Begin() self.used = 0 end
    function pool:Get()
        self.used = self.used + 1
        local d = self.dots[self.used]
        if not d then
            d = frame:CreateTexture(nil, layer or "OVERLAY")
            d:SetTexture(DOT_TEXTURE)
            self.dots[self.used] = d
        end
        d:Show()
        return d
    end
    function pool:Done()
        for i = self.used + 1, #self.dots do self.dots[i]:Hide() end
    end
    return pool
end
GP.DotPool = DotPool

GP.LINE_STYLES = { "line", "dashes", "dots" }
GP.DOT_SIZE = 1.8      -- a dot is this many line widths across ...
GP.DOT_GAP = 2.6       -- ... and dots this many widths apart (centre to centre, at least 5 px)
GP.DASH = { 3, 2 }     -- a dash this many widths long, then a gap this many (at least 4 / 3 px)

-- Draws a route's leg from (ax, ay) to (bx, by) in a style. carry = how far
-- into the pattern the leg starts (so dots and dashes run on evenly round
-- corners); returns it for the next leg.
local function Stroke(lines, dots, frame, anchor, ax, ay, bx, by, color, alpha, width, style, carry, px)
    px = px or 1   -- one screen pixel in the frame's units (the world map is zoomed)
    if style ~= "dots" and style ~= "dashes" then
        local line = lines:Get()
        Paint(line, color, alpha, width)
        line:SetStartPoint(anchor, frame, ax, ay)
        line:SetEndPoint(anchor, frame, bx, by)
        return 0
    end
    local dx, dy = bx - ax, by - ay
    local len = math.sqrt(dx * dx + dy * dy)
    if len <= 0 then return carry or 0 end
    local ux, uy = dx / len, dy / len
    carry = carry or 0
    if style == "dots" then
        local gap = max(5 * px, width * GP.DOT_GAP)
        local size = max(2 * px, width * GP.DOT_SIZE)
        local t = (gap - carry) % gap
        while t <= len do
            local d = dots:Get()
            d:SetVertexColor(color[1], color[2], color[3], alpha)
            d:SetSize(size, size)
            d:ClearAllPoints()
            d:SetPoint("CENTER", frame, anchor, ax + ux * t, ay + uy * t)
            t = t + gap
        end
        return (carry + len) % gap
    end
    local on, off = max(4 * px, width * GP.DASH[1]), max(3 * px, width * GP.DASH[2])
    local period = on + off
    local t = -(carry % period)
    while t < len do
        local s, e = max(0, t), min(len, t + on)
        if e > s then
            local line = lines:Get()
            Paint(line, color, alpha, width)
            line:SetStartPoint(anchor, frame, ax + ux * s, ay + uy * s)
            line:SetEndPoint(anchor, frame, ax + ux * e, ay + uy * e)
        end
        t = t + period
    end
    return (carry + len) % period
end
GP.Stroke = Stroke

-- The color a route's line is drawn in: its own, or the one picked for that map
-- ("world" or "minimap") on the Display tab
function GP:LineColor(route, where)
    local db = self.db
    if db[where .. "RouteColor"] then return route.color end
    return db[where .. "Color"]
end

-- Display tab's color for every line on that map ("world" or "minimap")
function GP:SetLineColor(where, r, g, b)
    self.db[where .. "Color"] = { r, g, b }
    self:Changed()
end

-- Arrows along a loop whose stops are at xs[i], ys[i] (pixels, in loop order):
-- one every `spacing` pixels of the way round, the first half a spacing in,
-- each { x, y, dx, dy } with dx, dy the way to ride (length 1). reverse rides
-- the loop the other way. Fewer than 3 stops (there and back): none.
local MAX_ARROWS = 2000
local function ArrowMarks(xs, ys, n, spacing, reverse)
    local marks = {}
    if n < 3 or not (spacing > 0) then return marks end
    local nextAt, walked = spacing / 2, 0
    for k = 1, n do
        local i = reverse and (k == 1 and 1 or n - k + 2) or k
        local j = reverse and (i == 1 and n or i - 1) or i % n + 1
        local dx, dy = xs[j] - xs[i], ys[j] - ys[i]
        local len = sqrt(dx * dx + dy * dy)
        if len > 0 then
            while nextAt <= walked + len do
                local t = (nextAt - walked) / len
                marks[#marks + 1] = { xs[i] + dx * t, ys[i] + dy * t, dx / len, dy / len }
                if #marks >= MAX_ARROWS then return marks end
                nextAt = nextAt + spacing
            end
            walked = walked + len
        end
    end
    return marks
end
GP.ArrowMarks = ArrowMarks

-- One arrow (a ">" of two lines) centred on x, y, pointing along dx, dy
local function DrawArrow(pool, rel, point, x, y, dx, dy, size, color, alpha, width)
    local tx, ty = x + dx * size / 2, y + dy * size / 2
    local bx, by = tx - dx * size, ty - dy * size
    local px, py = -dy * size * 0.6, dx * size * 0.6
    for side = -1, 1, 2 do
        local line = pool:Get()
        Paint(line, color, alpha, width)
        line:SetStartPoint(point, rel, bx + px * side, by + py * side)
        line:SetEndPoint(point, rel, tx, ty)
    end
end
GP.ARROW_GAP = { world = 80, minimap = 40 }   -- pixels on screen between arrows

-- The point of a loop (xs, ys, n stops; 2 stops: one leg) nearest to px, py:
-- x, y and how far away it is
local function NearestOnLoop(xs, ys, n, px, py)
    local bx, by, best
    local legs = n == 2 and 1 or n
    for i = 1, legs do
        local j = i % n + 1
        local ax, ay = xs[i], ys[i]
        local dx, dy = xs[j] - ax, ys[j] - ay
        local len2 = dx * dx + dy * dy
        local t = len2 > 0 and max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / len2)) or 0
        local x, y = ax + dx * t, ay + dy * t
        local d = (x - px) ^ 2 + (y - py) ^ 2
        if not best or d < best then bx, by, best = x, y, d end
    end
    if best then return bx, by, sqrt(best) end
end
GP.NearestOnLoop = NearestOnLoop

-- Dashes from the middle (0, 0) toward x, y, as far as `reach` pixels at most
GP.JOIN_DASH, GP.JOIN_GAP, GP.JOIN_MIN = 6, 4, 20   -- pixels, pixels, yards (closer: no line)
local function DrawJoin(pool, rel, x, y, reach, color, alpha, width)
    local d = sqrt(x * x + y * y)
    if d <= 0 then return end
    local ux, uy = x / d, y / d
    local stop, at = min(d, reach), 0
    while at < stop do
        local to = min(at + GP.JOIN_DASH, stop)
        local line = pool:Get()
        Paint(line, color, alpha, width)
        line:SetStartPoint("CENTER", rel, ux * at, uy * at)
        line:SetEndPoint("CENTER", rel, ux * to, uy * to)
        at = to + GP.JOIN_GAP
    end
end

---------------------------------------------------------------------------
-- World map: one pin over the whole map holds the lines
---------------------------------------------------------------------------
GatherlinePinMixin = CreateFromMixins and MapCanvasPinMixin and CreateFromMixins(MapCanvasPinMixin) or {}
local Pin = GatherlinePinMixin

function Pin:OnLoad()
    self:SetIgnoreGlobalPinScale(true)
    self:UseFrameLevelType("PIN_FRAME_LEVEL_MAP_HIGHLIGHT")
    self.pool = LinePool(self, "OVERLAY")
    self.dots = DotPool(self, "OVERLAY")
    self.arrows = LinePool(self, "OVERLAY")
    self.taboo = LinePool(self, "ARTWORK")   -- taboo areas, under the routes
    self.draft = LinePool(self, "OVERLAY")   -- the area being drawn
    self:SetScript("OnUpdate", function(pin) if GP.drawing then pin:DrawDraft() end end)
end

function Pin:OnAcquired()
    self:SetPosition(0.5, 0.5)
    self:OnCanvasSizeChanged()
end

function Pin:OnCanvasSizeChanged()
    local map = self:GetMap()
    self:SetSize(map:DenormalizeHorizontalSize(1), map:DenormalizeVerticalSize(1))
end

function Pin:OnCanvasScaleChanged()
    self:Draw()
end

-- Diagonal hatching inside a polygon (xs, ys, n corners, in pixels): lines
-- along x + y = c every `spacing` pixels, as { x1, y1, x2, y2 } pieces
local MAX_HATCH = 600
local function HatchSpans(xs, ys, n, spacing)
    local out = {}
    if n < 3 or not (spacing > 0) then return out end
    local lo, hi = math.huge, -math.huge
    for i = 1, n do
        local u = xs[i] + ys[i]
        lo, hi = min(lo, u), max(hi, u)
    end
    local c = (floor(lo / spacing) + 1) * spacing
    while c < hi do
        local cuts = {}
        for i = 1, n do
            local j = i % n + 1
            local fi, fj = xs[i] + ys[i] - c, xs[j] + ys[j] - c
            if (fi > 0) ~= (fj > 0) then
                local t = fi / (fi - fj)
                cuts[#cuts + 1] = xs[i] + (xs[j] - xs[i]) * t
            end
        end
        table.sort(cuts)
        for k = 1, #cuts - 1, 2 do
            out[#out + 1] = { cuts[k], c - cuts[k], cuts[k + 1], c - cuts[k + 1] }
            if #out >= MAX_HATCH then return out end
        end
        c = c + spacing
    end
    return out
end
GP.HatchSpans = HatchSpans

GP.TABOO_COLOR = { 0.95, 0.22, 0.15 }
GP.HATCH_GAP = 12   -- pixels on screen between hatch lines

-- The taboo areas of the map shown: a red outline, hatched inside
function Pin:DrawTaboos(mapID, w, h, scale)
    local pool = self.taboo
    pool:Begin()
    local db = GP.db
    if db and (db.tabooShow or GP.drawing) and mapID then
        local shapes = {}
        for _, xy in ipairs(GP:Taboos(mapID)) do shapes[#shapes + 1] = { xy, GP.TABOO_COLOR } end
        if GP.NoGoPolys then
            for _, xy in ipairs(GP:NoGoPolys(mapID)) do shapes[#shapes + 1] = { xy, GP.NOGO_COLOR } end
        end
        for _, shape in ipairs(shapes) do
            local xy, c = shape[1], shape[2]
            local n = floor(#xy / 2)
            local xs, ys = {}, {}
            for i = 1, n do xs[i], ys[i] = xy[2 * i - 1] * w, -xy[2 * i] * h end
            for i = 1, n do
                local j = i % n + 1
                local line = pool:Get()
                Paint(line, c, 0.9, 2 / scale)
                line:SetStartPoint("TOPLEFT", self, xs[i], ys[i])
                line:SetEndPoint("TOPLEFT", self, xs[j], ys[j])
            end
            for _, sp in ipairs(HatchSpans(xs, ys, n, GP.HATCH_GAP / scale)) do
                local line = pool:Get()
                Paint(line, c, 0.4, 1 / scale)
                line:SetStartPoint("TOPLEFT", self, sp[1], sp[2])
                line:SetEndPoint("TOPLEFT", self, sp[3], sp[4])
            end
        end
    end
    pool:Done()
end

-- The area being drawn: its corners joined, and on to the cursor
function Pin:DrawDraft()
    local pool = self.draft
    if not pool then return end
    pool:Begin()
    local d = GP.drawing
    local map = self:GetMap()
    if d and map and map:GetMapID() == d.mapID then
        local w, h = self:GetWidth(), self:GetHeight()
        local scale = self:GetEffectiveScale() / max(0.01, map:GetEffectiveScale())
        local pts = d.pts
        local n = floor(#pts / 2)
        local xs, ys = {}, {}
        for i = 1, n do xs[i], ys[i] = pts[2 * i - 1] * w, -pts[2 * i] * h end
        local c, gold = GP.TABOO_COLOR, { 1, 0.82, 0 }
        local function Seg(ax, ay, bx, by, color, alpha, width)
            local line = pool:Get()
            Paint(line, color, alpha, width / scale)
            line:SetStartPoint("TOPLEFT", self, ax, ay)
            line:SetEndPoint("TOPLEFT", self, bx, by)
        end
        for i = 1, n - 1 do Seg(xs[i], ys[i], xs[i + 1], ys[i + 1], c, 1, 2) end
        -- each corner a small gold square
        for i = 1, n do
            local r = 3 / scale
            Seg(xs[i] - r, ys[i], xs[i] + r, ys[i], gold, 1, 6)
        end
        if n > 0 and map.GetNormalizedCursorPosition then
            local ok, cx, cy = pcall(map.GetNormalizedCursorPosition, map)
            if ok and cx and cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 then
                Seg(xs[n], ys[n], cx * w, -cy * h, c, 0.7, 1.5)
                if n >= 2 then Seg(cx * w, -cy * h, xs[1], ys[1], c, 0.35, 1) end
            end
        end
    end
    pool:Done()
end

-- Where a route's map sits on the map shown: offsets and sizes (0..1), or nil
local function Placement(routeMap, shownMap)
    if routeMap == shownMap then return 0, 0, 1, 1, true end
    if not C_Map.GetMapRectOnMap then return nil end
    local ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, routeMap, shownMap)
    if not ok or not minX or maxX <= minX or maxY <= minY then return nil end
    return minX, minY, maxX - minX, maxY - minY, false
end
GP.Placement = Placement

function Pin:Draw()
    local pool = self.pool
    if not pool then return end
    local arrows = self.arrows
    pool:Begin()
    arrows:Begin()
    self.dots:Begin()
    local db = GP.db
    local map = self:GetMap()
    local shownMap = map and map:GetMapID()
    if map and shownMap and map:IsShown() then
        local scale = self:GetEffectiveScale() / max(0.01, map:GetEffectiveScale())
        self:DrawTaboos(shownMap, self:GetWidth(), self:GetHeight(), scale)
        self:DrawDraft()
    end
    if db and db.worldMap and shownMap and map:IsShown() then
        local w, h = self:GetWidth(), self:GetHeight()
        -- the canvas is zoomed; keep lines the same width on screen
        local scale = self:GetEffectiveScale() / max(0.01, map:GetEffectiveScale())
        local alpha = db.worldAlpha / 100
        for _, route in ipairs(db.routes) do
            local p, n = GP:DrawPoints(route)
            if route.shown and not route.working and n >= 2 then
                local ox, oy, sx, sy, own = Placement(route.mapID, shownMap)
                if ox then
                    -- thinner on a bigger map, where the route is small
                    local width = (own and db.worldWidth or max(0.5, db.worldWidth * 0.5)) / scale
                    local color = GP:LineColor(route, "world")
                    local xs, ys = {}, {}
                    for i = 1, n do
                        xs[i], ys[i] = (ox + p[2 * i - 1] * sx) * w, -(oy + p[2 * i] * sy) * h
                    end
                    local carry = 0
                    for i = 1, n do
                        local j = i % n + 1
                        if not (n == 2 and i == 2) then
                            carry = Stroke(pool, self.dots, self, "TOPLEFT", xs[i], ys[i], xs[j], ys[j], color, alpha, width, db.worldStyle, carry, 1 / scale)
                        end
                    end
                    if db.arrows then
                        local size = max(8 / scale, width * 3)
                        for _, a in ipairs(ArrowMarks(xs, ys, n, GP.ARROW_GAP.world / scale, db.arrowsReverse)) do
                            DrawArrow(arrows, self, "TOPLEFT", a[1], a[2], a[3], a[4], size, color, alpha, width)
                        end
                    end
                end
            end
        end
    end
    pool:Done()
    arrows:Done()
    self.dots:Done()
end

local Provider = CreateFromMixins and MapCanvasDataProviderMixin and CreateFromMixins(MapCanvasDataProviderMixin) or {}

function Provider:OnAdded(map)
    MapCanvasDataProviderMixin.OnAdded(self, map)
    self.pin = map:AcquirePin("GatherlinePinTemplate")
end

function Provider:OnRemoved(map)
    map:RemoveAllPinsByTemplate("GatherlinePinTemplate")
    self.pin = nil
    MapCanvasDataProviderMixin.OnRemoved(self, map)
end

function Provider:RemoveAllData()
    if self.pin and self.pin.pool then
        self.pin.pool:Begin()
        self.pin.pool:Done()
        if self.pin.dots then self.pin.dots:Begin(); self.pin.dots:Done() end
        self.pin.arrows:Begin()
        self.pin.arrows:Done()
        self.pin.taboo:Begin()
        self.pin.taboo:Done()
    end
end

function Provider:RefreshAllData()
    if self.pin then self.pin:Draw() end
end

function Provider:OnMapChanged()
    self:RefreshAllData()
    if GP.drawing then GP:UpdateDrawBar() end
end

function GP:SetupWorldMap()
    if self.provider or not (WorldMapFrame and WorldMapFrame.AddDataProvider and MapCanvasDataProviderMixin) then return end
    self.provider = Provider
    WorldMapFrame:AddDataProvider(Provider)
end

function GP:DrawWorldMap()
    if self.provider and WorldMapFrame and WorldMapFrame:IsShown() then
        self.provider:RefreshAllData()
    end
end

---------------------------------------------------------------------------
-- Drawing a taboo area on the world map: left-click adds a corner,
-- right-click takes the last one back, Finish keeps it. The map still pans
-- and zooms; clicks only become corners on the zone being drawn in.
---------------------------------------------------------------------------
local function TabooClick(map, button, cx, cy)
    local d = GP.drawing
    if not d or not map or map:GetMapID() ~= d.mapID then return false end
    if button == "LeftButton" and cx and cy then
        d.pts[#d.pts + 1] = Round(max(0, min(1, cx)))
        d.pts[#d.pts + 1] = Round(max(0, min(1, cy)))
    elseif button == "RightButton" then
        if #d.pts == 0 then return false end   -- nothing to take back: zoom out as usual
        d.pts[#d.pts] = nil
        d.pts[#d.pts] = nil
    else
        return false
    end
    GP:UpdateDrawBar()
    GP:DrawWorldMap()
    return true
end
GP.TabooClick = TabooClick

function GP:StartTaboo(mapID)
    if not mapID then return false end
    if InCombatLockdown and InCombatLockdown() then
        Print(L["can't open the world map to draw while you're in combat."])
        return false
    end
    if not (WorldMapFrame and WorldMapFrame.AddCanvasClickHandler) then
        Print(L["can't draw on this world map."])
        return false
    end
    self:SetupWorldMap()
    if not (self.drawing and self.drawing.mapID == mapID) then
        self.drawing = { mapID = mapID, pts = {} }
    end
    if not self.clickHandler then
        self.clickHandler = TabooClick
        WorldMapFrame:AddCanvasClickHandler(TabooClick, 100)
    end
    if self.config then self.config:Hide() end
    if OpenWorldMap then
        pcall(OpenWorldMap, mapID)
    else
        if not WorldMapFrame:IsShown() and ShowUIPanel then pcall(ShowUIPanel, WorldMapFrame) end
        if WorldMapFrame.SetMapID then WorldMapFrame:SetMapID(mapID) end
    end
    self:UpdateDrawBar()
    self:DrawWorldMap()
    return true
end

local function EndDrawing(self)
    self.drawing = nil
    if self.clickHandler and WorldMapFrame and WorldMapFrame.RemoveCanvasClickHandler then
        WorldMapFrame:RemoveCanvasClickHandler(self.clickHandler, 100)
    end
    self.clickHandler = nil
    if self.drawBar then self.drawBar:Hide() end
    self:DrawWorldMap()
end

function GP:FinishTaboo()
    local d = self.drawing
    if not d then return false end
    if #d.pts < 6 then
        Print(L["a no-go area needs at least 3 corners. Left-click the map to add them."])
        return false
    end
    if not self:AddTaboo(d.mapID, d.pts) then return false end
    local mapID = d.mapID
    EndDrawing(self)
    local n = #self:RoutesOn(mapID)
    Print(L["no-go area added in %s.%s"]:format(self:MapName(mapID),
        n > 0 and " Your routes there are being worked out again to go round it." or ""))
    if self.TabooTabInWindow then self:TabooTabInWindow(mapID) end
    return true
end

function GP:CancelTaboo()
    local d = self.drawing
    if not d then return end
    EndDrawing(self)
    if self.TabooTabInWindow then self:TabooTabInWindow(d.mapID) end
end

-- The bar over the world map while drawing
function GP:UpdateDrawBar()
    local d = self.drawing
    local bar = self.drawBar
    if not d then
        if bar then bar:Hide() end
        return
    end
    if not bar then
        local parent = WorldMapFrame
        bar = CreateFrame("Frame", nil, parent)
        bar:SetSize(560, 64)
        bar:SetPoint("TOP", parent.ScrollContainer or parent, "TOP", 0, -8)
        bar:SetFrameStrata("DIALOG")
        bar:EnableMouse(true)
        T.Panel(bar, 0.92)
        bar.title = T.Text(bar, "", "GameFontNormal", T.C.gold)
        bar.title:SetPoint("TOPLEFT", 12, -10)
        bar.help = T.Text(bar, "", "GameFontHighlightSmall")
        bar.help:SetPoint("TOPLEFT", 12, -30)
        bar.help:SetWidth(400)
        bar.help:SetWordWrap(true)
        bar.finish = T.FlatButton(bar, "Finish", 110, 22)
        bar.finish:SetPoint("TOPRIGHT", -10, -8)
        bar.finish:SetScript("OnClick", function(b) if not b.disabled then GP:FinishTaboo() end end)
        T.Disabler(bar.finish, { bar.finish })
        bar.cancel = T.FlatButton(bar, "Cancel", 110, 22)
        bar.cancel:SetPoint("TOPRIGHT", -10, -34)
        bar.cancel:SetScript("OnClick", function() GP:CancelTaboo() end)
        self.drawBar = bar
    end
    local corners = floor(#d.pts / 2)
    bar.title:SetText(L["No-go area in %s  -  %d corners"]:format(self:MapName(d.mapID), corners))
    local shown = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    if shown ~= d.mapID then
        bar.help:SetText(L["Go back to %s on the map to draw there."]:format(self:MapName(d.mapID)))
    else
        bar.help:SetText(L["Left-click the map for each corner, right-click to take the last one back. Scroll to zoom, drag to move the map."])
    end
    bar.finish:SetDisabled(corners < 3)
    bar:Show()
end

---------------------------------------------------------------------------
-- Minimap
---------------------------------------------------------------------------
-- The part of the segment a-b inside a circle of radius r round 0,0
local function ClipCircle(ax, ay, bx, by, r)
    local dx, dy = bx - ax, by - ay
    local a = dx * dx + dy * dy
    if a == 0 then return nil end
    local b = 2 * (ax * dx + ay * dy)
    local c = ax * ax + ay * ay - r * r
    local disc = b * b - 4 * a * c
    if disc <= 0 then return nil end
    local s = sqrt(disc)
    local t1, t2 = (-b - s) / (2 * a), (-b + s) / (2 * a)
    if t1 >= 1 or t2 <= 0 then return nil end
    t1, t2 = max(t1, 0), min(t2, 1)
    return ax + dx * t1, ay + dy * t1, ax + dx * t2, ay + dy * t2
end
GP.ClipCircle = ClipCircle

-- The part of the segment a-b inside the square -r..r
local function ClipSquare(ax, ay, bx, by, r)
    local dx, dy = bx - ax, by - ay
    local t1, t2 = 0, 1
    local function edge(p, q)
        if p == 0 then return q >= 0 end
        local t = q / p
        if p < 0 then
            if t > t2 then return false end
            if t > t1 then t1 = t end
        else
            if t < t1 then return false end
            if t < t2 then t2 = t end
        end
        return true
    end
    if edge(-dx, ax + r) and edge(dx, r - ax) and edge(-dy, ay + r) and edge(dy, r - ay) then
        return ax + dx * t1, ay + dy * t1, ax + dx * t2, ay + dy * t2
    end
    return nil
end
GP.ClipSquare = ClipSquare

local function MinimapIsRound()
    local shape = GetMinimapShape and GetMinimapShape()
    return shape == nil or shape == "ROUND"
end

function GP:SetupMinimap()
    if self.mm or not Minimap then return end
    local f = CreateFrame("Frame", nil, Minimap)
    f:SetAllPoints(Minimap)
    f:SetFrameLevel(Minimap:GetFrameLevel() + 1)
    f.pool = LinePool(f, "ARTWORK")
    f.dots = DotPool(f, "ARTWORK")
    f.ring = LinePool(f, "ARTWORK")
    f.arrows = LinePool(f, "ARTWORK")
    f.join = LinePool(f, "ARTWORK")
    f.speedWait = 0
    f.wait = 0
    f:SetScript("OnUpdate", function(frame, elapsed)
        frame.wait = frame.wait - elapsed
        if frame.wait > 0 then return end
        frame.wait = 0.03
        self:DrawMinimap()
        frame.speedWait = frame.speedWait - 1
        if frame.speedWait <= 0 then
            frame.speedWait = 60   -- about every 2 seconds
            if self:SampleSpeed() and self.config and self.config:IsShown() and self.RefreshConfig then
                self:RefreshConfig()
            end
        end
    end)
    self.mm = f
end

-- The range circle: db.rangeYards round you (the middle of the minimap), so
-- you can see how far Find Herbs and Find Minerals show nodes. It doesn't
-- turn or move, so it's only redrawn when the zoom or a setting changes.
local RING_SIDES = 64
function GP:DrawRange(force, radius, half)
    local f, db = self.mm, self.db
    local pool = f.ring
    if not (db and db.range and radius and radius > 0 and half > 0) then
        if f.ringKey then pool:Begin(); pool:Done(); f.ringKey = nil end
        return
    end
    local rc = db.rangeColor
    local key = L["%.1f:%.1f:%d:%d:%.3f:%.3f:%.3f:%s"]:format(radius, half, db.rangeYards, db.rangeAlpha,
        rc[1], rc[2], rc[3], tostring(MinimapIsRound()))
    if not force and key == f.ringKey then return end
    f.ringKey = key
    local r = db.rangeYards * half / radius
    local clip = MinimapIsRound() and ClipCircle or ClipSquare
    local alpha = db.rangeAlpha / 100
    pool:Begin()
    for i = 1, RING_SIDES do
        local a1, a2 = (i - 1) / RING_SIDES * 2 * math.pi, i / RING_SIDES * 2 * math.pi
        local ax, ay, bx, by = clip(r * cos(a1), r * sin(a1), r * cos(a2), r * sin(a2), half - 1)
        if ax then
            local line = pool:Get()
            Paint(line, rc, alpha, 2)
            line:SetStartPoint("CENTER", f, ax, ay)
            line:SetEndPoint("CENTER", f, bx, by)
        end
    end
    pool:Done()
end

-- Redraws the minimap's lines if you've moved, turned or zoomed (or force)
function GP:DrawMinimap(force)
    local f = self.mm
    if not f then return end
    local pool = f.pool
    local db = self.db
    local radius = C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius()
    local half = Minimap:GetWidth() / 2
    self:DrawRange(force, radius, half)
    if not (db and db.minimap) then
        if f.drew then
            pool:Begin(); pool:Done()
            f.dots:Begin(); f.dots:Done()
            f.arrows:Begin(); f.arrows:Done()
            f.join:Begin(); f.join:Done()
            f.drew = false; f.last = nil
        end
        return
    end
    if not radius or radius <= 0 or half <= 0 then return end
    local rotate = GetCVar and GetCVar("rotateMinimap") == "1"
    local facing = rotate and GetPlayerFacing and GetPlayerFacing() or 0
    if rotate and not facing then facing = 0 end

    -- your place on each map that has a route showing
    local mc = db.minimapColor
    local maps, key = {}, L["%.1f:%.3f:%.1f:%.1f:%d:%s:%.3f:%.3f:%.3f:%s:%s"]:format(radius, facing, half, db.minimapWidth,
        db.minimapAlpha, tostring(db.minimapRouteColor), mc[1], mc[2], mc[3], tostring(db.arrows), tostring(db.arrowsReverse)) .. ":" .. tostring(db.joinLine)
        .. ":" .. tostring(db.minimapStyle)
    for _, route in ipairs(db.routes) do
        if route.shown and not route.working and maps[route.mapID] == nil then
            local x, y = PlayerPos(route.mapID)
            maps[route.mapID] = x and { x, y } or false
            if x then key = key .. L[":%d:%.5f:%.5f"]:format(route.mapID, x, y) end
        end
    end
    if not force and key == f.last then return end
    f.last = key

    local pxPerYard = half / radius
    local inside = half - 1
    local clip = MinimapIsRound() and ClipCircle or ClipSquare
    local c, s = cos(facing), sin(facing)
    local alpha = db.minimapAlpha / 100
    local round = MinimapIsRound()
    local size = max(7, db.minimapWidth * 3)
    local arrows = f.arrows
    local join   -- the nearest point of any route: { x, y, distance, color }
    pool:Begin()
    arrows:Begin()
    f.dots:Begin()
    for _, route in ipairs(db.routes) do
        local at = maps[route.mapID]
        local p, n = self:DrawPoints(route)
        if at and route.shown and not route.working and n >= 2 then
            local w, h = Yards(route.mapID)
            local color = self:LineColor(route, "minimap")
            -- every node, in pixels from the minimap's middle (right and up)
            local sx, sy = {}, {}
            for i = 1, n do
                local dx = (p[2 * i - 1] - at[1]) * w * pxPerYard   -- east
                local dy = (p[2 * i] - at[2]) * h * pxPerYard       -- south
                if rotate then dx, dy = dx * c - dy * s, dx * s + dy * c end
                sx[i], sy[i] = dx, -dy
            end
            local carry = 0
            for i = 1, n do
                local j = i % n + 1
                if not (n == 2 and i == 2) then
                    local ax, ay, bx, by = clip(sx[i], sy[i], sx[j], sy[j], inside)
                    if ax then
                        carry = Stroke(pool, f.dots, f, "CENTER", ax, ay, bx, by, color, alpha, db.minimapWidth, db.minimapStyle, carry)
                    end
                end
            end
            if db.joinLine then
                local x, y, d = NearestOnLoop(sx, sy, n, 0, 0)
                if x and (not join or d < join[3]) then join = { x, y, d, color } end
            end
            if db.arrows then
                -- only arrows wholly on the minimap
                local room = inside - size
                for _, a in ipairs(ArrowMarks(sx, sy, n, self.ARROW_GAP.minimap, db.arrowsReverse)) do
                    local x, y = a[1], a[2]
                    if (round and x * x + y * y <= room * room) or (not round and math.abs(x) <= room and math.abs(y) <= room) then
                        DrawArrow(arrows, f, "CENTER", x, y, a[3], a[4], size, color, alpha, db.minimapWidth)
                    end
                end
            end
        end
    end
    pool:Done()
    arrows:Done()
    f.dots:Done()
    f.join:Begin()
    -- off the route: dashes from you toward it, up to the minimap's edge
    if join and join[3] > self.JOIN_MIN * pxPerYard then
        local reach = inside
        if not round then
            -- to the square's edge in that direction
            local ax, ay = math.abs(join[1]) / join[3], math.abs(join[2]) / join[3]
            reach = inside / max(ax, ay, 0.001)
        end
        DrawJoin(f.join, f, join[1], join[2], reach, join[4], alpha, max(1, db.minimapWidth - 1))
    end
    f.join:Done()
    f.drew = true
end

---------------------------------------------------------------------------
-- Redraw everything after a change
---------------------------------------------------------------------------
function GP:Changed()
    self:DrawWorldMap()
    self:DrawMinimap(true)
    if self.RefreshConfig then self:RefreshConfig() end
end

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------
function GP:PositionMinimapButton()
    local angle = math.rad(self.db.minimapAngle or 200)
    local radius = (Minimap:GetWidth() / 2) + 10
    self.minimapButton:ClearAllPoints()
    self.minimapButton:SetPoint("CENTER", Minimap, "CENTER", cos(angle) * radius, sin(angle) * radius)
end

function GP:BuildMinimapButton()
    local b = CreateFrame("Button", "GatherlineMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(22, 22)
    icon:SetTexture(self.ICON)
    icon:SetPoint("TOPLEFT", 5, -4)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")
    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            GP:ToggleLines()
        else
            GP:OpenConfig()
        end
    end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            GP.db.minimapAngle = math.deg(math.atan2(py / scale - my, px / scale - mx))
            GP:PositionMinimapButton()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(GP.LOGO_TEXT .. " " .. T.NAME)
        GameTooltip:AddLine(L["Left-click: routes and options"], 1, 1, 1)
        GameTooltip:AddLine(L["Right-click: show or hide the lines"], 1, 1, 1)
        GameTooltip:AddLine(L["Drag: move this button"], 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.minimapButton = b
    self:PositionMinimapButton()
end

function GP:UpdateMinimapButton()
    if self.minimapButton then self.minimapButton:SetShown(self.db.minimapButton) end
end

-- Right-click on the button: all lines off, or back as they were
function GP:ToggleLines()
    local db = self.db
    if db.worldMap or db.minimap then
        db.hiddenWas = { worldMap = db.worldMap, minimap = db.minimap }
        db.worldMap, db.minimap = false, false
        Print(L["lines hidden. Right-click the button again to show them."])
    else
        local was = db.hiddenWas or {}
        db.worldMap = was.worldMap ~= false
        db.minimap = was.minimap ~= false
        db.hiddenWas = nil
        Print(L["lines shown."])
    end
    self:Changed()
end

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------
local function Help()
    Print(L["commands:"])
    print("  |cffffd100/gl|r  " .. L["routes and options"])
    print("  |cffffd100/gl new|r  " .. L["make a new route"])
    print("  |cffffd100/gl show|r, |cffffd100/gl hide|r  " .. L["show or hide all the lines"])
    print("  |cffffd100/gl skipped|r  " .. L["the nodes on your skip list"])
    print("  |cffffd100/gl start|r  " .. L["ride the route shown in your zone with Shortest Path's guidance"])
    print("  |cffffd100/gl stop|r  " .. L["stop riding it"])
    print("  |cffffd100/gl laps N|r  " .. L["laps Start rides (0 = until you stop)"])
    print("  |cffffd100/gl reach N|r  " .. L["how close (yards) to a stop before the ride moves on"])
    print("  |cffffd100/gl names number|nodes|both|r  " .. L["what the stops are called while riding"])
    print("  |cffffd100/gl reverse|r  " .. L["turn the route you ride (or the one shown in your zone) round"])
    print("  |cffffd100/gl empty N|r  " .. L["minutes a gathered stop is skipped (0 = never)"])
    print("  |cffffd100/gl stats|r, |cffffd100/gl stats reset|r  " .. L["the statistics of the route you ride (or the one shown in your zone)"])
    print("  |cffffd100/gl hud|r [compass|lens|card|preview]  " .. L["the gathering HUD: all, one part, or a preview"])
    print("  |cffffd100/gl tour|r [name]  " .. L["ride a tour (several routes, zone to zone)"])
    print("  |cffffd100/gl skill|r  " .. L["where to skill up your Herbalism and Mining"])
    print("  |cffffd100/gl regrowth|r  " .. L["how soon nodes grew back, per zone (learnt)"])
    print("  |cffffd100/gl stats all|r  " .. L["all your routes, the one that brings the most first"])
    print("  |cffffd100/gl share|r, |cffffd100/gl import|r  " .. L["share the route shown in your zone / add one a friend shared"])
    print("  |cffffd100/gl walk|r  " .. L["test: yards on foot from you to the next stops"])
end

SLASH_GATHERLINE1 = "/gl"
SLASH_GATHERLINE2 = "/gatherline"
SlashCmdList.GATHERLINE = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)")
    if cmd == "" or cmd == "options" or cmd == "config" then
        GP:OpenConfig()
    elseif cmd == "new" then
        GP:OpenConfig("new")
    elseif cmd == "skipped" or cmd == "skip" then
        local list = GP:SkippedNames()
        if #list == 0 then
            Print(L["no nodes are skipped. Right-click a node on the New route tab to skip it in every route."])
        else
            Print(L["skipped (right-click one on the New route tab to stop skipping it): %s"]:format(table.concat(list, ", ")))
        end
    elseif cmd == "start" or cmd == "go" then
        local route = GP:NavCandidate()
        if route then GP:StartNav(route) else Print(L["no route shown in your zone. Click Start on one in /gl."]) end
    elseif cmd == "stop" then
        if not GP:StopNav() then Print(L["you're not riding a route."]) end
    elseif cmd == "laps" then
        local n = tonumber((msg or ""):match("^%s*%S+%s+(%d+)"))
        if n then GP.db.navLaps = math.max(0, math.min(99, math.floor(n))) end
        local l = GP.db.navLaps
        Print((l == 0 and L["Start rides lap after lap until you stop. |cffffd100/gl laps N|r to change it."]
            or L["Start rides %d laps. |cffffd100/gl laps N|r to change it."]:format(l)))
    elseif cmd == "reverse" or cmd == "turn" then
        local route = GP:NavRoute() or GP:NavCandidate()
        if route then GP:ReverseRoute(route) else Print(L["no route shown in your zone to turn round."]) end
    elseif cmd == "names" or cmd == "labels" then
        local v = (msg or ""):lower():match("^%s*%S+%s+(%a+)")
        if v == "number" or v == "nodes" or v == "both" then GP.db.navLabel = v; GP:Changed() end
        Print(L["stops are called by %s. |cffffd100/gl names number|nodes|both|r to change it."]:format(
            ({ number = L["their number"], nodes = L["what's there"], both = L["their number and what's there"] })[GP.db.navLabel]))
    elseif cmd == "reach" then
        local n = tonumber((msg or ""):match("^%s*%S+%s+(%d+)"))
        local r = GP.RANGES.navReach
        if n then GP.db.navReach = math.max(r[1], math.min(r[2], math.floor(n))) end
        Print(L["a ride moves on to the next stop %d yards before it. |cffffd100/gl reach N|r to change it (%d-%d)."]:format(
            GP.db.navReach, r[1], r[2]))
    elseif cmd == "empty" or cmd == "respawn" then
        local n = tonumber((msg or ""):match("^%s*%S+%s+(%d+)"))
        local r = GP.RANGES.navRespawn
        if n then GP.db.navRespawn = math.max(r[1], math.min(r[2], math.floor(n))); GP:Changed() end
        local m = GP.db.navRespawn
        Print(m == 0 and L["a ride never skips stops you gathered. |cffffd100/gl empty N|r to change it."]
            or L["a ride skips stops whose nodes you all gathered in the last %d minutes. |cffffd100/gl empty N|r to change it."]:format(m))
    elseif cmd == "stats" then
        local route = GP:NavRoute() or GP:NavCandidate()
        if (msg or ""):lower():match("^%s*%S+%s+all") then
            GP:PrintRanking()
        elseif not route then
            Print(L["no route shown in your zone."])
        elseif (msg or ""):lower():match("^%s*%S+%s+reset") then
            GP:ResetStats(route)
            Print(L["statistics of %s reset."]:format(route.name))
        else
            local line = GP:StatsLine(route)
            local s = route.stats
            if line then
                Print(L["%s: laps %d, nodes gathered %d. %s"]:format(route.name, s.laps, s.gathered, line))
            else
                Print(L["%s has no laps yet. Ride it with Start; each lap counts."]:format(route.name))
            end
        end
    elseif cmd == "regrowth" or cmd == "respawn" then
        local any = false
        local list = {}
        for mapID, kinds in pairs(type(GP.db.respawn) == "table" and GP.db.respawn or {}) do
            for kind in pairs(kinds) do
                local secs, n = GP:LearntRespawn(mapID, kind)
                list[#list + 1] = { GP:MapName(mapID), GP:KindName(kind), secs, n }
            end
        end
        table.sort(list, function(a, b) return a[1] .. a[2] < b[1] .. b[2] end)
        Print(L["regrowth seen (the smart laps use it when they've seen it 3 times):"])
        for _, e in ipairs(list) do
            any = true
            print(("  |cffffd100%s|r, %s: %s"):format(e[1], e[2], e[3] and L["%s (seen %d times)"]:format(GP.FormatClock(e[3]), e[4])
                or L["seen %d times so far"]:format(e[4])))
        end
        if not any then print("  " .. L["nothing yet: it's learnt when you or your group gather a node again."]) end
    elseif cmd == "share" then
        local route = GP:NavRoute() or GP:NavCandidate()
        if route then GP:ShareWindow(route) else Print(L["no route shown in your zone."]) end
    elseif cmd == "tour" or cmd == "tours" then
        local want = (msg or ""):match("^%s*%S+%s+(.-)%s*$")
        local tours = GP:Tours()
        if not want or want == "" then
            if #tours == 1 then GP:StartTour(tours[1]) else GP:OpenConfig("tours") end
        else
            local found
            for _, t in ipairs(tours) do if t.name:lower() == want:lower() then found = t end end
            for _, t in ipairs(tours) do if not found and t.name:lower():find(want:lower(), 1, true) then found = t end end
            if found then GP:StartTour(found) else Print(L["no tour called |cffffd100%s|r."]:format(want)) end
        end
    elseif cmd == "hud" then
        local h = GP:HudSettings()
        local what = (msg or ""):lower():match("^%s*%S+%s+(%a+)")
        local keys = { compass = "compass", band = "compass", lens = "lens", card = "card", lap = "card" }
        if what and keys[what] then
            h[keys[what]] = not h[keys[what]]
        elseif what == "preview" then
            GP:SetHudPreview(not GP.hudPreview)
        else
            local any = h.compass or h.lens or h.card
            if any then
                h.was = { h.compass, h.lens, h.card }
                h.compass, h.lens, h.card = false, false, false
            else
                local w = type(h.was) == "table" and h.was or { true, false, true }
                h.compass, h.lens, h.card = w[1] == true, w[2] == true, w[3] == true
                if not (h.compass or h.lens or h.card) then h.compass, h.card = true, true end
            end
        end
        GP:UpdateHud(true)
        if GP.RefreshConfig then GP:RefreshConfig() end
        local on = {}
        if h.compass then on[#on + 1] = L["compass band"] end
        if h.lens then on[#on + 1] = L["ground lens"] end
        if h.card then on[#on + 1] = L["lap card"] end
        Print(#on == 0 and L["HUD off. |cffffd100/gl hud|r switches it on again."]
            or L["HUD: %s. |cffffd100/gl hud compass|lens|card|r switches a part."]:format(table.concat(on, ", ")))
    elseif cmd == "skill" or cmd == "skillup" then
        GP:PrintSkillUp()
    elseif cmd == "import" then
        GP:ShareWindow()
    elseif cmd == "walk" then
        GP:WalkTest()
    elseif cmd == "show" or cmd == "hide" then
        local on = cmd == "show"
        if (GP.db.worldMap or GP.db.minimap) ~= on then GP:ToggleLines() end
    else
        Help()
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
pcall(events.RegisterEvent, events, "ZONE_CHANGED_NEW_AREA")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON then
            GP:LoadSettings()
        elseif arg1 == "GatherMate2" or arg1 == "GatherLite" then
            GP:ListenToGatherMate()
        elseif arg1 == "Blizzard_WorldMap" then
            GP:SetupWorldMap()
        end
    elseif event == "PLAYER_LOGIN" then
        GP:SetupWorldMap()
        GP:SetupMinimap()
        GP:BuildMinimapButton()
        GP:UpdateMinimapButton()
        GP:ListenToGatherMate()
        if not GP:HasNodeSource() then
            Print(L["needs |cffffd100GatherMate2|r or |cffffd100GatherLite|r for its herb and ore nodes. Install one from CurseForge, then /reload."])
        end
        -- the first time, routes from GatherPath Plus or GatherPath Forever come over by themselves
        if not GP.db.imported and #GP.db.routes == 0 and GP:ImportSource() then GP:ImportRoutes(true) end
    else
        GP:DrawMinimap(true)
        if GP.RefreshConfig then GP:RefreshConfig() end
    end
end)
