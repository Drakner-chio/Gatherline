-- Gatherline: what happens while you gather. Each time you gather a node
-- (Herb Gathering or Mining finishes), where you stand is noted with the time:
-- a ride skips stops whose nodes were all gathered too recently to be back
-- (Navigation.lua). While you ride a route, what you gather and loot counts
-- for that route's statistics: laps, best and average lap, nodes an hour, and
-- with Auctionator what the loot is worth.

local ADDON, ns = ...
local L = ns.L
local GP = ns.GP

GP.HARVEST_YARDS = 15        -- a node within this of where you gathered counts as gathered
GP.HARVEST_KEEP = 3600       -- seconds harvests are remembered
GP.LOOT_WINDOW = 20          -- seconds after gathering that loot counts as the node's

-- The spells a gathering cast is (their names, in the game's language)
GP.GATHER_SPELLS = { 2366, 2368, 3570, 11993, 2575, 2576, 3564, 10248 }
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

function GP:RecordHarvest(mapID, x, y, t)
    t = t or GetTime()
    local list = self.harvests
    list[#list + 1] = { mapID, x, y, t }
    while list[1] and t - list[1][4] > self.HARVEST_KEEP do table.remove(list, 1) end
    self.lastHarvest = t
    local route = self.NavRoute and self:NavRoute()
    if route then
        local s = self:RouteStats(route)
        s.gathered = s.gathered + 1
    end
    if self.Changed then self:Changed() end
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
    for _, k in ipairs({ "laps", "lapTime", "rideTime", "gathered", "value" }) do
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
        if x and y then GP:RecordHarvest(mapID, x, y) end
    elseif event == "CHAT_MSG_LOOT" then
        GP:OnLoot(a1)
    end
end)
GP.sessionFrame = frame
