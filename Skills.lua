-- Gatherline: routes by gathering skill. Which herbs and ores you can gather
-- with your Herbalism or Mining (Skills_Data.lua: what each needs), shown in
-- the game's skill-up colours on the New route page, an "only what I can
-- gather" filter there, and where to skill up: the zones with the most nodes
-- that still raise your skill.

local ADDON, ns = ...
local L = ns.L
local GP = ns.GP
local Print = GP.Print
local floor = math.floor

-- The profession behind each kind (skill line ids), and its name as the old API calls it
GP.SKILL_LINES = { ["Herb Gathering"] = 182, ["Mining"] = 186 }
local SKILL_NAMES = {
    ["Herb Gathering"] = { herbalism = true, ["kräuterkunde"] = true, herboristerie = true, ["herboristería"] = true, erbalismo = true, herborismo = true },
    ["Mining"] = { mining = true, bergbau = true, minage = true, ["minería"] = true, estrazione = true, ["mineração"] = true },
}

-- Your skill in the profession behind a kind: a number (0 = not learned), or nil if the game can't say
function GP:ProfessionRank(kind)
    if self.FAKE_RANKS then return self.FAKE_RANKS[kind] end
    local id = self.SKILL_LINES[kind]
    if not id then return nil end
    local S = _G.C_SkillInfo
    if S and S.GetSkillLineInfoByID then
        local ok, info = pcall(S.GetSkillLineInfoByID, id)
        if ok and type(info) == "table" then return (info.rank or 0) + (info.modifier or 0) end
    end
    if S and S.GetNumSkillLines and S.GetSkillLineInfo then
        local ok, n = pcall(S.GetNumSkillLines)
        if ok and type(n) == "number" and n > 0 then
            for i = 1, n do
                local info = S.GetSkillLineInfo(i)
                if type(info) == "table" and not info.isHeader and type(info.name) == "string"
                    and SKILL_NAMES[kind][info.name:lower()] then
                    return (info.rank or 0) + (info.modifier or 0)
                end
            end
            return 0
        end
    end
    if GetNumSkillLines and GetSkillLineInfo then
        local n = GetNumSkillLines()
        if type(n) == "number" and n > 0 then
            for i = 1, n do
                local name, header, _, rank, _, modifier = GetSkillLineInfo(i)
                if not header and type(name) == "string" and SKILL_NAMES[kind][name:lower()] then
                    return (rank or 0) + (modifier or 0)
                end
            end
            return 0
        end
    end
    return nil
end

-- What a node needs: { orange, yellow, green, grey } (or { minimum }), or nil if unknown
function GP:NodeSkill(name)
    local e = ns.NODE_SKILL and ns.NODE_SKILL[name]
    if e then return { e[2], e[3], e[4], e[5] }, e[1] end
end

-- How hard a node is for you: "red" (can't yet), "orange", "yellow", "green",
-- "grey" (no more skill from it), or nil (unknown, or a kind without a skill)
function GP:Difficulty(name, kind)
    local levels, k = self:NodeSkill(name)
    if not levels or (kind and k ~= kind) then return nil end
    local rank = self:ProfessionRank(k)
    if rank == nil then return nil end
    if rank < levels[1] then return "red" end
    if not levels[2] then return "yellow" end   -- only the minimum is known
    if rank < levels[2] then return "orange" end
    if rank < levels[3] then return "yellow" end
    if rank < levels[4] then return "green" end
    return "grey"
end

GP.DIFFICULTY_HEX = { red = "ff3a3a", orange = "ff8040", yellow = "ffff00", green = "40c040", grey = "808080" }
-- how much a node of each colour helps you skill up
GP.SKILL_UP = { orange = 1, yellow = 0.75, green = 0.25 }

-- Whether you can gather it (true for anything without a known skill)
function GP:CanGather(name, kind)
    return self:Difficulty(name, kind) ~= "red"
end

-- The node's skill as a coloured number, "" if unknown
function GP:SkillTag(name, kind)
    local levels = self:NodeSkill(name)
    local d = self:Difficulty(name, kind)
    if not levels then return "" end
    local hex = d and self.DIFFICULTY_HEX[d] or "8a8070"
    return " |cff" .. hex .. levels[1] .. "|r"
end

---------------------------------------------------------------------------
-- Where to skill up: zones ranked by the nodes that still raise your skill
---------------------------------------------------------------------------
-- Returns { { mapID, score, nodes = { { kind, name, count, colour } } } }, best first,
-- and the ranks used ({ [kind] = rank } of the professions you have)
function GP:SkillUpZones()
    local ranks = {}
    for kind in pairs(self.SKILL_LINES) do
        local r = self:ProfessionRank(kind)
        if r and r > 0 then ranks[kind] = r end
    end
    local out = {}
    if not next(ranks) then return out, ranks end
    for _, mapID in ipairs(self:GatherZones()) do
        local score, list, counts = 0, {}, {}
        for kind in pairs(ranks) do
            self:EachNode(mapID, kind, function(_, _, name)
                if not self:IsSkipped(name) then counts[kind .. "\0" .. name] = (counts[kind .. "\0" .. name] or 0) + 1 end
            end)
        end
        for key, count in pairs(counts) do
            local kind, name = key:match("^(.-)%z(.*)$")
            local d = self:Difficulty(name, kind)
            local w = d and self.SKILL_UP[d]
            if w then
                score = score + w * count
                list[#list + 1] = { kind = kind, name = name, count = count, colour = d, weight = w }
            end
        end
        if score > 0 then
            table.sort(list, function(a, b)
                if a.weight * a.count ~= b.weight * b.count then return a.weight * a.count > b.weight * b.count end
                return a.name < b.name
            end)
            out[#out + 1] = { mapID = mapID, score = score, nodes = list }
        end
    end
    table.sort(out, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return self:MapName(a.mapID) < self:MapName(b.mapID)
    end)
    return out, ranks
end

GP.SKILL_ZONES_SHOWN = 5

-- Says where to skill up; returns the best zone and its useful nodes (nil if none)
function GP:PrintSkillUp()
    local zones, ranks = self:SkillUpZones()
    if not next(ranks) then
        Print(L["you have neither Herbalism nor Mining yet (or the game doesn't say)."])
        return nil
    end
    local have = {}
    for kind, r in pairs(ranks) do have[#have + 1] = ("%s %d"):format(self:KindName(kind), r) end
    table.sort(have)
    if #zones == 0 then
        Print(L["with %s, no zone %s knows has nodes that still raise your skill."]:format(table.concat(have, ", "), self:SourceNames()))
        return nil
    end
    Print(L["where to skill up with %s (orange always raises your skill, yellow usually):"]:format(table.concat(have, ", ")))
    for i = 1, math.min(#zones, self.SKILL_ZONES_SHOWN) do
        local z = zones[i]
        local parts = {}
        for k = 1, math.min(#z.nodes, 4) do
            local e = z.nodes[k]
            parts[k] = ("|cff%s%s|r ×%d"):format(self.DIFFICULTY_HEX[e.colour], e.name, e.count)
        end
        print(("  %d. |cffffd100%s|r: %s"):format(i, self:MapName(z.mapID), table.concat(parts, ", ")))
    end
    return zones[1]
end

local frame = CreateFrame("Frame")
pcall(frame.RegisterEvent, frame, "SKILL_LINES_CHANGED")
frame:SetScript("OnEvent", function()
    if GP.config and GP.config.IsShown and GP.config:IsShown() and GP.RefreshConfig then GP:RefreshConfig() end
end)

---------------------------------------------------------------------------
-- Where it pays: zones ranked by what their nodes are worth (Loot_Data.lua:
-- what gathering a node yields, priced with Auctionator)
---------------------------------------------------------------------------
-- Copper one gathering of this node is worth, or nil (no prices or no data)
function GP:NodeValue(name)
    local en = ns.NODE_EN and ns.NODE_EN[name] or name
    local loot = ns.NODE_LOOT and ns.NODE_LOOT[en]
    local A = _G.Auctionator
    local api = type(A) == "table" and A.API and A.API.v1
    if not (loot and api and type(api.GetAuctionPriceByItemID) == "function") then return nil end
    local total, any = 0, false
    for k = 1, #loot, 2 do
        local ok, price = pcall(api.GetAuctionPriceByItemID, ADDON, loot[k])
        if ok and type(price) == "number" then
            total, any = total + price * loot[k + 1], true
        end
    end
    return any and total or nil
end

function GP:HasPrices()
    local A = _G.Auctionator
    return type(A) == "table" and A.API and A.API.v1 and type(A.API.v1.GetAuctionPriceByItemID) == "function" and true or false
end

-- Zones ranked by the worth of all their nodes you can gather, best first:
-- { { mapID, value, count, nodes = { { kind, name, count, each, value } } } }
function GP:PayZones()
    local out = {}
    for _, mapID in ipairs(self:GatherZones()) do
        local total, count, list = 0, 0, {}
        for kind in pairs(self.SKILL_LINES) do
            local counts = {}
            self:EachNode(mapID, kind, function(_, _, name)
                if not self:IsSkipped(name) then counts[name] = (counts[name] or 0) + 1 end
            end)
            for name, n in pairs(counts) do
                if self:CanGather(name, kind) then
                    local each = self:NodeValue(name)
                    if each and each > 0 then
                        total, count = total + each * n, count + n
                        list[#list + 1] = { kind = kind, name = name, count = n, each = each, value = each * n }
                    end
                end
            end
        end
        if total > 0 then
            table.sort(list, function(a, b) return a.value > b.value end)
            out[#out + 1] = { mapID = mapID, value = total, count = count, nodes = list }
        end
    end
    table.sort(out, function(a, b) return a.value > b.value end)
    return out
end

-- Says where it pays; returns the best zone (nil if none)
function GP:PrintPays()
    if not self:HasPrices() then
        Print(L["needs |cffffd100Auctionator|r with prices scanned at the auction house, to know what the nodes are worth."])
        return nil
    end
    local zones = self:PayZones()
    if #zones == 0 then
        Print(L["no zone has nodes you can gather with prices Auctionator knows yet. Scan the auction house, then try again."])
        return nil
    end
    Print(L["where it pays (every node of a zone gathered once, at Auctionator's prices):"])
    for i = 1, math.min(#zones, self.SKILL_ZONES_SHOWN) do
        local z = zones[i]
        local parts = {}
        for k = 1, math.min(#z.nodes, 3) do
            local e = z.nodes[k]
            parts[k] = L["%s ×%d (%s each)"]:format(e.name, e.count, self.FormatMoney(e.each))
        end
        print(("  %d. |cffffd100%s|r: %s – %s"):format(i, self:MapName(z.mapID), self.FormatMoney(z.value), table.concat(parts, ", ")))
    end
    return zones[1]
end
