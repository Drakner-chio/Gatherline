-- Gatherline: where the nodes come from. GatherMate2, GatherLite, or both:
-- each source lists its kinds of node, the nodes of a kind on a map, the maps
-- it has nodes on, and tells us when it finds a new one. With both, a node
-- both know (same name, within DUPLICATE_YARDS) counts once.
--
-- Our kinds of node are GatherMate2's names for them ("Herb Gathering",
-- "Mining"...), so routes saved before GatherLite support still match.

local ADDON, ns = ...
local GP = ns.GP

local Sources = {}
GP.Sources = Sources
GP.DUPLICATE_YARDS = 15

---------------------------------------------------------------------------
-- GatherMate2
---------------------------------------------------------------------------
local GM = { key = "gathermate", name = "GatherMate2" }

function GM.Get()
    local gm = _G.GatherMate2
    if type(gm) == "table" and type(gm.GetNodesForZone) == "function" and type(gm.DecodeLoc) == "function" then
        return gm
    end
end

function GM.Available() return GM.Get() ~= nil end

function GM.Kinds()
    local gm = GM.Get()
    return gm and gm.db_types or {}
end

function GM.EachNode(mapID, kind, fn)
    local gm = GM.Get()
    if not gm then return end
    pcall(function()
        for coord, nodeID in gm:GetNodesForZone(mapID, kind, true) do
            local x, y = gm:DecodeLoc(coord)
            local name = gm.GetNameForNode and gm:GetNameForNode(kind, nodeID) or nil
            fn(x, y, name or ("Node " .. tostring(nodeID)))
        end
    end)
end

function GM.Zones(found)
    local gm = GM.Get()
    if not gm or type(gm.gmdbs) ~= "table" then return end
    for _, kind in ipairs(GP.KINDS) do
        local db = gm.gmdbs[kind]
        if type(db) == "table" then
            -- GatherMate2 keeps nodes in its saved variables, by map number
            local stores = {}
            if type(rawget(db, "__gm2_base_storage")) == "table" then
                stores[#stores + 1] = rawget(db, "__gm2_base_storage")
                for _, s in pairs(rawget(db, "__gm2_storage_map") or {}) do stores[#stores + 1] = s end
            else
                stores[1] = db
            end
            for _, store in ipairs(stores) do
                for mapID, nodes in pairs(store) do
                    if type(mapID) == "number" and type(nodes) == "table" and next(nodes) then found[mapID] = true end
                end
            end
        end
    end
end

function GM.Listen(added, removed)
    local gm = GM.Get()
    if not gm or GM.listening or type(gm.RegisterMessage) ~= "function" then return end
    local function decode(coord)
        local ok, x, y = pcall(gm.DecodeLoc, gm, coord)
        if ok then return x, y end
    end
    local listener = {}
    pcall(gm.RegisterMessage, listener, "GatherMate2NodeAdded", function(_, zone, kind, coord, name)
        local x, y = decode(coord)
        if x and type(name) == "string" then added(zone, kind, x, y, name) end
    end)
    pcall(gm.RegisterMessage, listener, "GatherMate2NodeDeleted", function(_, zone, kind, coord, name)
        local x, y = decode(coord)
        if x and type(name) == "string" then removed(zone, kind, x, y, name) end
    end)
    GM.listening = true
end

---------------------------------------------------------------------------
-- GatherLite (WoW Forever's own gathering addon; its nodes include the
-- predefined ones it ships with, for the kinds it shows)
---------------------------------------------------------------------------
local GLS = { key = "gatherlite", name = "GatherLite" }

-- GatherLite's types and ours
GLS.KIND_OF = { herbalism = "Herb Gathering", mining = "Mining", fishing = "Fishing", containers = "Treasure" }
GLS.TYPE_OF = {}
for t, k in pairs(GLS.KIND_OF) do GLS.TYPE_OF[k] = t end
GLS.ORDER = { "herbalism", "mining", "fishing", "containers" }

function GLS.Get()
    local stub = _G.LibStub
    if type(stub) ~= "table" and type(stub) ~= "function" then return nil end
    local ok, ace = pcall(stub, "AceAddon-3.0", true)
    if not ok or type(ace) ~= "table" or type(ace.GetAddon) ~= "function" then return nil end
    local ok2, gl = pcall(ace.GetAddon, ace, "GatherLite", true)
    if ok2 and type(gl) == "table" and type(gl.GetNodesForMap) == "function" and type(gl.GetNodeObject) == "function" then
        return gl
    end
end

function GLS.Available() return GLS.Get() ~= nil end

function GLS.Kinds()
    local list = {}
    for _, t in ipairs(GLS.ORDER) do list[#list + 1] = GLS.KIND_OF[t] end
    return list
end

-- An object's name as GatherLite shows it (in the game's language), by object ID
local names = {}
local function NameOf(gl, objectID)
    local name = names[objectID]
    if name == nil then
        local ok, object = pcall(gl.GetNodeObject, gl, objectID)
        name = false
        if ok and type(object) == "table" and type(object.name) == "string" then
            local tok, text = pcall(gl.translate, gl, "node." .. object.name)
            name = tok and type(text) == "string" and text or object.name
        end
        names[objectID] = name
    end
    return name or nil
end
GLS.NameOf = NameOf

local function Ignored(gl, objectID)
    if type(gl.IsIgnored) ~= "function" then return false end
    local ok, on = pcall(gl.IsIgnored, gl, objectID)
    return ok and on == true
end

function GLS.EachNode(mapID, kind, fn)
    local gl = GLS.Get()
    local t = GLS.TYPE_OF[kind]
    if not gl or not t then return end
    local ok, list = pcall(gl.GetNodesForMap, gl, t, mapID)
    if not ok or type(list) ~= "table" then return end
    for _, node in ipairs(list) do
        local x, y, id = node.posX, node.posY, node.object
        if type(x) == "number" and type(y) == "number" and node.mapID == mapID and not Ignored(gl, id) then
            local name = NameOf(gl, id)
            if name then fn(x, y, name) end
        end
    end
end

function GLS.Zones(found)
    local gl = GLS.Get()
    if not gl then return end
    for _, t in ipairs(GLS.ORDER) do
        local ok, list = pcall(gl.GetNodesForMap, gl, t, nil)
        if ok and type(list) == "table" then
            for _, node in ipairs(list) do
                if type(node.mapID) == "number" then found[node.mapID] = true end
            end
        end
    end
end

function GLS.Listen(added)
    local gl = GLS.Get()
    if not gl or GLS.listening or type(gl.On) ~= "function" then return end
    pcall(gl.On, gl, "nodes:added", function(node)
        if type(node) ~= "table" then return end
        local kind = GLS.KIND_OF[node.type]
        local name = kind and NameOf(gl, node.object)
        if name and type(node.posX) == "number" and type(node.mapID) == "number" then
            added(node.mapID, kind, node.posX, node.posY, name)
        end
    end)
    GLS.listening = true
end

Sources.list = { GM, GLS }
Sources.gathermate, Sources.gatherlite = GM, GLS

---------------------------------------------------------------------------
-- All of them together
---------------------------------------------------------------------------
-- The sources that are there now
function Sources.Active()
    local list = {}
    for _, s in ipairs(Sources.list) do
        if s.Available() then list[#list + 1] = s end
    end
    return list
end

function GP:HasNodeSource() return #Sources.Active() > 0 end

-- "GatherMate2", "GatherLite" or "GatherMate2 and GatherLite"
function GP:SourceNames()
    local n = {}
    for _, s in ipairs(Sources.Active()) do n[#n + 1] = s.name end
    return table.concat(n, " + ")
end

-- Every node of a kind on a map, from every source; a node a second source
-- also has (same name, within DUPLICATE_YARDS) only once
function Sources.EachNode(mapID, kind, fn)
    local active = Sources.Active()
    if #active == 1 then return active[1].EachNode(mapID, kind, fn) end
    local w, h = GP:MapYards(mapID)
    w, h = w or 1500, h or 1000
    local cell = GP.DUPLICATE_YARDS
    local seen = {}
    local function Key(cx, cy, name) return cx .. ":" .. cy .. ":" .. name end
    for i, s in ipairs(active) do
        local mine = {}
        s.EachNode(mapID, kind, function(x, y, name)
            local cx, cy = math.floor(x * w / cell), math.floor(y * h / cell)
            if i > 1 then
                for dx = -1, 1 do
                    for dy = -1, 1 do
                        for _, q in ipairs(seen[Key(cx + dx, cy + dy, name)] or {}) do
                            local ex, ey = (q[1] - x) * w, (q[2] - y) * h
                            if ex * ex + ey * ey <= cell * cell then return end
                        end
                    end
                end
            end
            local k = Key(cx, cy, name)
            mine[k] = mine[k] or {}
            table.insert(mine[k], { x, y })
            fn(x, y, name)
        end)
        for k, list in pairs(mine) do
            seen[k] = seen[k] or {}
            for _, q in ipairs(list) do table.insert(seen[k], q) end
        end
    end
end

-- Our kinds, in our order, then any a source has that we don't know
function Sources.Kinds()
    local have, any = {}, false
    for _, s in ipairs(Sources.Active()) do
        for _, k in ipairs(s.Kinds()) do have[k] = true; any = true end
    end
    local list, seen = {}, {}
    for _, k in ipairs(GP.KINDS) do
        if have[k] or not any then list[#list + 1] = k; seen[k] = true end
    end
    for _, s in ipairs(Sources.Active()) do
        for _, k in ipairs(s.Kinds()) do
            if not seen[k] then list[#list + 1] = k; seen[k] = true end
        end
    end
    return list
end

function Sources.Zones(found)
    for _, s in ipairs(Sources.Active()) do s.Zones(found) end
end

function Sources.Listen()
    for _, s in ipairs(Sources.Active()) do
        s.Listen(function(...) GP:AddNode(...) end, function(...) GP:RemoveNode(...) end)
    end
end
