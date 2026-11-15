-- Gatherline: walking distances over the game's terrain.
--
-- Routing/PathGrid.lua, Path.lua and PathJobs.lua are Shortest Path Forever's
-- walking search, copied unchanged (GPL-3.0-or-later). They read the walking
-- maps Shortest Path Forever loads into the global ShortestPathForeverPathData,
-- so Shortest Path Forever has to be installed for any of this to work.
--
-- Gatherline works in a zone's map positions (0-1); the search works in the
-- continent's world yards (x north, y west), so everything here converts.
-- Roads are left out (their data is Shortest Path's own, not global): walks
-- take the shortest way over the ground, not the road.

local ADDON, ns = ...
local L = ns.L
local GP = ns.GP
local Path = ns.Path

local Walk = {}
GP.Walk = Walk

-- Our copy keeps its own decoded tiles next to Shortest Path's: a smaller cache
-- is plenty for one zone's gathering route.
if Path then Path.cacheKB = 8192 end

-- A zone map position as a point of the search: { map = continent, x, y }
function Walk.Point(mapID, x, y)
    if not (C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local continent, world = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
    if not (continent and world) then return nil end
    local wx, wy = world:GetXY()
    if not (wx and wy) then return nil end
    return { map = continent, x = wx, y = wy }
end

-- Back from the search's world yards to a position on the zone's map
function Walk.MapPos(mapID, point)
    if not (C_Map.GetMapPosFromWorldPos and CreateVector2D) then return nil end
    -- returns the map it placed the point on, then the position there
    local placed, pos = C_Map.GetMapPosFromWorldPos(point.map, CreateVector2D(point.x, point.y), mapID)
    if type(placed) == "table" and pos == nil then pos = placed end   -- (an older client returning only the position)
    if not pos then return nil end
    return pos:GetXY()
end

-- Whether walks can be worked out on this zone's continent now
-- A walking search that errors (Shortest Path Forever's walking maps in a shape
-- this copy can't read) switches walks off for the session, said once in chat;
-- routes then use straight lines.
Walk.broken = nil
ns.OnWalkError = function(err)
    if not Walk.broken then
        Walk.broken = tostring(err)
        GP.Print(L["can't read Shortest Path Forever's walking maps (is Gatherline up to date?). Routes use straight lines until /reload."])
        if GP.DEBUG then geterrorhandler()(err) end
    end
end

function Walk.Ready(mapID)
    if Walk.broken then return false, "Shortest Path Forever's walking maps can't be read" end
    if not (Path and ShortestPathForeverPathData) then return false, "Shortest Path Forever isn't loaded" end
    local p = Walk.Point(mapID, 0.5, 0.5)
    if not p then return false, "the game can't place this zone" end
    if not Path.HasData(p.map) then return false, "there's no walking map for this continent" end
    return true
end

-- Yards on foot from a to b (zone map positions), worked out over the next
-- frames: done(yards) or done(nil, reason). Returns a handle for Walk.Cancel.
function Walk.Cost(mapID, ax, ay, bx, by, done)
    local ok, why = Walk.Ready(mapID)
    if not ok then done(nil, why) return nil end
    local a, b = Walk.Point(mapID, ax, ay), Walk.Point(mapID, bx, by)
    if not (a and b) or a.map ~= b.map then done(nil, "invalid") return nil end
    return Path.FindCost(a.map, a, b, function(cost, reason)
        if type(cost) == "number" then done(cost) else done(nil, reason or tostring(cost)) end
    end)
end

-- Yards on foot from (ax, ay) to each of targets ({ { x, y }, ... }, zone map
-- positions), in one search: done(costs) with costs[i] = yards or false
-- (no way there), or done(nil, reason).
function Walk.Costs(mapID, ax, ay, targets, done)
    local ok, why = Walk.Ready(mapID)
    if not ok then done(nil, why) return nil end
    local from = Walk.Point(mapID, ax, ay)
    if not from then done(nil, "invalid") return nil end
    local list = {}
    for i, t in ipairs(targets) do
        local p = Walk.Point(mapID, t[1], t[2])
        if not p or p.map ~= from.map then done(nil, "invalid") return nil end
        list[i] = p
    end
    return Path.FindMany(from.map, from, list, function(costs, reason)
        if reason then done(nil, reason) else done(costs) end
    end)
end

-- The way on foot from a to b as zone map positions { x1, y1, x2, y2, ... }:
-- done(xy, yards) or done(nil, reason)
function Walk.Line(mapID, ax, ay, bx, by, done)
    local ok, why = Walk.Ready(mapID)
    if not ok then done(nil, why) return nil end
    local a, b = Walk.Point(mapID, ax, ay), Walk.Point(mapID, bx, by)
    if not (a and b) or a.map ~= b.map then done(nil, "invalid") return nil end
    return Path.Find(a.map, a, b, function(points, cost)
        if not points then done(nil, cost) return end
        local xy = {}
        for _, p in ipairs(points) do
            local x, y = Walk.MapPos(mapID, p)
            if x then xy[#xy + 1] = x; xy[#xy + 1] = y end
        end
        done(xy, cost)
    end)
end

function Walk.Cancel(job)
    if job and Path then Path.Cancel(job) end
end

---------------------------------------------------------------------------
-- /gl walk: a check that the copied search works in the game. From where you
-- stand, yards on foot to the next few stops of the nearest route shown in
-- your zone, against yards in a straight line.
---------------------------------------------------------------------------
function GP:WalkTest()
    local Print = GP.Print
    local mapID = GP:PlayerMap()
    local px, py = mapID and GP.PlayerPos(mapID)
    if not px then Print(L["can't tell where you are."]) return end
    local ok, why = Walk.Ready(mapID)
    if not ok then Print(L["walking maps not ready: %s."]:format(L[why])) return end
    local route
    for _, r in ipairs(GP:RoutesOn(mapID)) do
        if r.shown and not r.working and GP:NodeCount(r) >= 2 then route = r break end
    end
    if not route then Print(L["no route shown in this zone to test with."]) return end
    local w, h = GP:MapYards(mapID)
    w, h = w or 1500, h or 1000
    local p, n = route.points, GP:NodeCount(route)
    local best, bi = math.huge, 1
    for i = 1, n do
        local dx, dy = (p[2 * i - 1] - px) * w, (p[2 * i] - py) * h
        local d = dx * dx + dy * dy
        if d < best then best, bi = d, i end
    end
    local targets, idx = {}, {}
    for k = 0, math.min(4, n - 1) do
        local i = (bi - 1 + k) % n + 1
        idx[#idx + 1] = i
        targets[#targets + 1] = { p[2 * i - 1], p[2 * i] }
    end
    Print(L["working out walks to %d stops of %s..."]:format(#targets, route.name))
    local started = debugprofilestop and debugprofilestop()
    Walk.Costs(mapID, px, py, targets, function(costs, reason)
        if not costs then Print(L["|cffff5050no walks:|r %s"]:format(tostring(reason))) return end
        for k, t in ipairs(targets) do
            local dx, dy = (t[1] - px) * w, (t[2] - py) * h
            local straight = math.sqrt(dx * dx + dy * dy)
            local c = costs[k]
            if c then
                print(L["  stop %d: %d yards on foot, %d straight (x%.2f)"]:format(idx[k], c + 0.5, straight + 0.5,
                    straight > 1 and c / straight or 1))
            else
                print(L["  stop %d: no way there on foot (%d straight)"]:format(idx[k], straight + 0.5))
            end
        end
        if started then Print(L["done in %.0f ms."]:format(debugprofilestop() - started)) end
    end)
end
