-- Gatherline: what happens while you gather. Each time you gather a node
-- (Herb Gathering or Mining finishes), where you stand is noted with the time:
-- a ride skips stops whose nodes were all gathered too recently to be back
-- (Navigation.lua). While you ride a route, what you gather and loot counts
-- for that route's statistics: laps, best and average lap, nodes an hour, and
-- with Auctionator what the loot is worth.

local ADDON, ns = ...
local L = ns.L
local GP = ns.GP
local floor = math.floor

GP.HARVEST_YARDS = 15        -- a node within this of where you gathered counts as gathered
GP.HARVEST_KEEP = 3600       -- seconds harvests are remembered
GP.LOOT_WINDOW = 20          -- seconds after gathering that loot counts as the node's

-- The spells a gathering cast is (their names, in the game's language)
GP.GATHER_SPELLS = { 2366, 2368, 3570, 11993, 2575, 2576, 3564, 10248 }
GP.GATHER_KIND = { [2366] = "Herb Gathering", [2368] = "Herb Gathering", [3570] = "Herb Gathering", [11993] = "Herb Gathering",
    [2575] = "Mining", [2576] = "Mining", [3564] = "Mining", [10248] = "Mining" }
local gatherNames

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, id)
        if ok and name then return name end
    end
    if GetSpellInfo then
        local ok, name = pcall(GetSpellInfo, id)
        if ok and name then return name end
    end
end

-- Which kind a gathering spell gathers ("Herb Gathering", "Mining"), by id or name
function GP:GatherKind(spellID)
    if self.GATHER_KIND[spellID] then return self.GATHER_KIND[spellID] end
    local name = SpellName(spellID)
    for id, kind in pairs(self.GATHER_KIND) do
        if name and SpellName(id) == name then return kind end
    end
end

GP.SpellName = SpellName

function GP:IsGatherSpell(spellID)
    if not gatherNames then
        gatherNames = {}
        for _, id in ipairs(self.GATHER_SPELLS) do
            gatherNames[id] = true
            local name = SpellName(id)
            if name then gatherNames[name] = true end
        end
    end
    if gatherNames[spellID] then return true end
    local name = SpellName(spellID)
    return name ~= nil and gatherNames[name] == true
end

---------------------------------------------------------------------------
-- Harvests: { mapID, x, y, t }, this session, oldest first
---------------------------------------------------------------------------
GP.harvests = {}

-- A node gathered at (x, y): by you, or (from) by someone in your group.
-- Yours count for the route's statistics and are told to your group.
function GP:RecordHarvest(mapID, x, y, t, kind, from)
    t = t or GetTime()
    self:LearnRespawn(mapID, x, y, t, kind)
    local list = self.harvests
    list[#list + 1] = { mapID, x, y, t, kind, from }
    while list[1] and t - list[1][4] > self.HARVEST_KEEP do table.remove(list, 1) end
    if not from then
        self.lastHarvest = t
        local route = self.NavRoute and self:NavRoute()
        if route then
            local s = self:RouteStats(route)
            s.gathered = s.gathered + 1
        end
        self:ResolveVisits(mapID, x, y)
        if self.SendHarvest then self:SendHarvest(mapID, x, y, kind) end
    end
    if self.Changed then self:Changed() end
end

---------------------------------------------------------------------------
-- Regrowth learnt: a node gathered again (by you or your group) came back
-- within the time since it was gathered before. Kept per zone and kind
-- (db.respawn[mapID][kind] = the last few such times, seconds); the smart
-- laps then skip a stop no longer than the 20th percentile of them, never
-- longer than the minutes set.
---------------------------------------------------------------------------
GP.RESPAWN_SAMPLES = 30
GP.RESPAWN_MIN_SAMPLES = 3
GP.RESPAWN_RANGE = { 60, 3600 }

function GP:LearnRespawn(mapID, x, y, t, kind)
    if not (self.db and kind) then return end
    local w, h = self:MapYards(mapID)
    w, h = w or 1500, h or 1000
    local r2 = self.HARVEST_YARDS * self.HARVEST_YARDS
    for i = #self.harvests, 1, -1 do
        local e = self.harvests[i]
        if e[1] == mapID and (e[5] == nil or e[5] == kind) then
            local dx, dy = (e[2] - x) * w, (e[3] - y) * h
            if dx * dx + dy * dy <= r2 then
                local took = t - e[4]
                if took >= self.RESPAWN_RANGE[1] and took <= self.RESPAWN_RANGE[2] then
                    self.db.respawn = type(self.db.respawn) == "table" and self.db.respawn or {}
                    local z = self.db.respawn[mapID] or {}
                    self.db.respawn[mapID] = z
                    local list = z[kind] or {}
                    z[kind] = list
                    list[#list + 1] = floor(took + 0.5)
                    while #list > self.RESPAWN_SAMPLES do table.remove(list, 1) end
                end
                return
            end
        end
    end
end

-- Seconds a node of this kind in this zone was seen to grow back in (20th
-- percentile of the times seen), and how many times it was seen; nil if
-- fewer than RESPAWN_MIN_SAMPLES
function GP:LearntRespawn(mapID, kind)
    local z = type(self.db.respawn) == "table" and self.db.respawn[mapID]
    local list = z and kind and z[kind]
    if type(list) ~= "table" or #list < self.RESPAWN_MIN_SAMPLES then return nil, list and #list or 0 end
    local sorted = {}
    for i, v in ipairs(list) do sorted[i] = v end
    table.sort(sorted)
    return sorted[math.max(1, math.floor(#sorted * 0.2 + 0.5))], #sorted
end

-- How long a gathered node at a stop counts as gone, in seconds (0: never)
function GP:SkipSeconds(mapID, kind)
    local set = (self.db.navRespawn or 0) * 60
    if set <= 0 then return 0 end
    if self.db.navLearn then
        local learnt = self:LearntRespawn(mapID, kind)
        if learnt then return math.min(set, learnt) end
    end
    return set
end

---------------------------------------------------------------------------
-- Picked clean: you reach a stop with nodes no one in your group gathered
-- lately, and gather nothing there within VISIT_WINDOW seconds - someone else
-- got there first (or it wasn't back). Counted per route: visits, empty.
---------------------------------------------------------------------------
GP.VISIT_WINDOW = 40
GP.VISIT_YARDS = 30
GP.visits = {}

-- Navigation: a stop reached (members = its nodes, flat x, y ...)
function GP:StopReached(route, members)
    if not (route and members and #members > 0) then return end
    local now = GetTime()
    local seconds = self:SkipSeconds(route.mapID, nil)
    if seconds <= 0 then seconds = 300 end
    local open = false
    for k = 1, #members, 2 do
        if not self:WasHarvested(route.mapID, members[k], members[k + 1], seconds, now) then open = true break end
    end
    if not open then return end   -- all gathered lately by you or your group: no surprise if empty
    self.visits[#self.visits + 1] = { route = route, members = members, t = now }
end

function GP:ResolveVisits(mapID, x, y)
    local w, h = self:MapYards(mapID)
    w, h = w or 1500, h or 1000
    local r2 = self.VISIT_YARDS * self.VISIT_YARDS
    for _, v in ipairs(self.visits) do
        if not v.found and v.route.mapID == mapID then
            local m = v.members
            for k = 1, #m, 2 do
                local dx, dy = (m[k] - x) * w, (m[k + 1] - y) * h
                if dx * dx + dy * dy <= r2 then v.found = true break end
            end
        end
    end
end

-- Visits whose time is up go into the route's statistics
function GP:SettleVisits(now)
    now = now or GetTime()
    local keep = {}
    for _, v in ipairs(self.visits) do
        if v.found or now - v.t > self.VISIT_WINDOW then
            local s = self:RouteStats(v.route)
            s.visits = (s.visits or 0) + 1
            if not v.found then s.empty = (s.empty or 0) + 1 end
        else
            keep[#keep + 1] = v
        end
    end
    self.visits = keep
end

-- Whether a node at (x, y) was gathered in the last `seconds`
function GP:WasHarvested(mapID, x, y, seconds, now)
    now = now or GetTime()
    local w, h = self:MapYards(mapID)
    w, h = w or 1500, h or 1000
    local r2 = self.HARVEST_YARDS * self.HARVEST_YARDS
    for i = #self.harvests, 1, -1 do
        local e = self.harvests[i]
        if now - e[4] > seconds then break end
        if e[1] == mapID then
            local dx, dy = (e[2] - x) * w, (e[3] - y) * h
            if dx * dx + dy * dy <= r2 then return true end
        end
    end
    return false
end

---------------------------------------------------------------------------
-- Statistics per route (saved): laps, lap seconds (best, total), riding
-- seconds, nodes gathered and loot value (copper) while riding it
---------------------------------------------------------------------------
function GP:RouteStats(route)
    local s = route.stats
    if type(s) ~= "table" then
        s = {}
        route.stats = s
    end
    for _, k in ipairs({ "laps", "lapTime", "rideTime", "gathered", "value", "visits", "empty" }) do
        if type(s[k]) ~= "number" then s[k] = 0 end
    end
    if s.best ~= nil and type(s.best) ~= "number" then s.best = nil end
    return s
end

function GP:RecordLap(route, seconds)
    if not route or type(seconds) ~= "number" or seconds <= 0 then return end
    local s = self:RouteStats(route)
    s.laps = s.laps + 1
    s.lapTime = s.lapTime + seconds
    if not s.best or seconds < s.best then s.best = seconds end
end

function GP:AddRideTime(route, seconds)
    if not route or type(seconds) ~= "number" or seconds <= 0 then return end
    local s = self:RouteStats(route)
    s.rideTime = s.rideTime + seconds
end

function GP:ResetStats(route)
    route.stats = nil
    self:Changed()
end

-- "5:58"
function GP.FormatClock(seconds)
    seconds = math.floor(seconds + 0.5)
    return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

-- "12g 34s" (copper rounded to silver)
function GP.FormatMoney(copper)
    copper = math.floor(copper + 0.5)
    local g, s = math.floor(copper / 10000), math.floor((copper % 10000) / 100)
    if g > 0 then return L["%dg %ds"]:format(g, s) end
    return L["%ds"]:format(s)
end

-- One short line of a route's statistics, or nil before its first lap
function GP:StatsLine(route)
    local s = route.stats
    if type(s) ~= "table" or (s.laps or 0) == 0 then return nil end
    local parts = { L["best lap %s"]:format(self.FormatClock(s.best or 0)),
        L["avg %s"]:format(self.FormatClock(s.lapTime / s.laps)) }
    if (s.rideTime or 0) >= 60 then
        local hours = s.rideTime / 3600
        parts[#parts + 1] = L["%d nodes/h"]:format(math.floor(s.gathered / hours + 0.5))
        if (s.value or 0) > 0 then parts[#parts + 1] = L["%s/h"]:format(self.FormatMoney(s.value / hours)) end
    end
    if (s.visits or 0) >= 5 then
        parts[#parts + 1] = L["%d%% found empty"]:format(math.floor(100 * (s.empty or 0) / s.visits + 0.5))
    end
    return table.concat(parts, "  ·  ")
end

---------------------------------------------------------------------------
-- What loot is worth: Auctionator's price, if it's there
---------------------------------------------------------------------------
function GP:ItemValue(link)
    local A = _G.Auctionator
    local api = type(A) == "table" and A.API and A.API.v1
    if not (api and type(api.GetAuctionPriceByItemLink) == "function") then return nil end
    local ok, price = pcall(api.GetAuctionPriceByItemLink, ADDON, link)
    if ok and type(price) == "number" then return price end
end

-- "You receive loot: %sx%d." as a Lua pattern
local function LootPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local p = fmt:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
    return "^" .. p .. "$"
end

function GP:ParseLoot(msg)
    if type(msg) ~= "string" then return nil end
    local multi = LootPattern(_G.LOOT_ITEM_SELF_MULTIPLE)
    if multi then
        local link, count = msg:match(multi)
        if link then return link, tonumber(count) or 1 end
    end
    local single = LootPattern(_G.LOOT_ITEM_SELF)
    if single then
        local link = msg:match(single)
        if link then return link, 1 end
    end
end

function GP:OnLoot(msg)
    local route = self.NavRoute and self:NavRoute()
    if not route or not self.lastHarvest or GetTime() - self.lastHarvest > self.LOOT_WINDOW then return end
    local link, count = self:ParseLoot(msg)
    if not link then return end
    local price = self:ItemValue(link)
    if price then
        local s = self:RouteStats(route)
        s.value = s.value + price * count
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
frame:RegisterEvent("CHAT_MSG_LOOT")
frame:SetScript("OnEvent", function(_, event, a1, a2, a3)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if a1 ~= "player" or not GP:IsGatherSpell(a3) then return end
        local mapID = GP:PlayerMap()
        if not mapID then return end
        local x, y = GP.PlayerPos(mapID)
        if x and y then GP:RecordHarvest(mapID, x, y, nil, GP:GatherKind(a3)) end
    elseif event == "CHAT_MSG_LOOT" then
        GP:OnLoot(a1)
    end
end)
GP.sessionFrame = frame
local settle = 0
frame:SetScript("OnUpdate", function(_, elapsed)
    settle = settle + (elapsed or 0)
    if settle < 1 then return end
    settle = 0
    if #GP.visits > 0 then GP:SettleVisits() end
end)

---------------------------------------------------------------------------
-- Bags filling up: free slots counted (bags 0-4); while you ride, a warning
-- in chat and on the HUD's lap card once they're down to db.bagWarn
---------------------------------------------------------------------------
function GP:FreeBagSlots()
    if self.FAKE_FREE then return self.FAKE_FREE end
    local C = _G.C_Container
    local get = C and C.GetContainerNumFreeSlots or _G.GetContainerNumFreeSlots
    if not get then return nil end
    local free = 0
    for bag = 0, 4 do
        local ok, n = pcall(get, bag)
        if ok and type(n) == "number" then free = free + n end
    end
    return free
end

GP.BAG_WARN_AGAIN = 120   -- seconds before the chat warning comes again

function GP:CheckBags()
    local warn = self.db and self.db.bagWarn or 0
    if warn <= 0 or not (self.IsNavigating and self:IsNavigating()) then return end
    local free = self:FreeBagSlots()
    if not free then return end
    if free <= warn then
        local now = GetTime()
        if not self.bagWarned or now - self.bagWarned > self.BAG_WARN_AGAIN or free < (self.bagWarnedAt or 99) then
            self.bagWarned, self.bagWarnedAt = now, free
            self.Print(free == 0 and L["|cffff6040your bags are full|r – gathering won't fit any more."]
                or L["|cffff6040only %d bag slots free|r."]:format(free))
            if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING) end
        end
    else
        self.bagWarnedAt = nil
    end
end

local bags = CreateFrame("Frame")
pcall(bags.RegisterEvent, bags, "BAG_UPDATE_DELAYED")
pcall(bags.RegisterEvent, bags, "BAG_UPDATE")
bags:SetScript("OnEvent", function() if GP.db then GP:CheckBags() end end)
GP.bagFrame = bags
