-- Gatherline: gathering together. Gatherline users in a group tell each other
-- what they gather (addon messages, prefix "Gatherline"), so the smart laps
-- skip the stops a friend just picked clean too, and regrowth is learnt from
-- both. Routes can be sent straight to the group or to one player: they're
-- asked whether to add it.
--
-- Messages: "H1:<map>:<x>:<y>:<h|m|->" a node gathered (map positions x 10000),
--           "R1:<id>:<part>:<parts>:<text>" a route (GL1 line, in parts of 200).

local ADDON, ns = ...
local L = ns.L
local GP = ns.GP
local Print = GP.Print

GP.SYNC_PREFIX = "Gatherline"
GP.SYNC_PART = 200
GP.SYNC_GAP = 0.15        -- seconds between the parts of a route

local function Me()
    local name, realm = UnitName and UnitName("player")
    return name
end

local function Send(msg, channel, target)
    local C = _G.C_ChatInfo
    local send = C and C.SendAddonMessage or _G.SendAddonMessage
    if not send then return false end
    local ok = pcall(send, GP.SYNC_PREFIX, msg, channel, target)
    return ok
end

local function GroupChannel()
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
end

local KIND_CODE = { ["Herb Gathering"] = "h", ["Mining"] = "m" }
local CODE_KIND = { h = "Herb Gathering", m = "Mining" }

-- Session.lua: you gathered something
function GP:SendHarvest(mapID, x, y, kind)
    if not (self.db and self.db.syncGroup) then return end
    local channel = GroupChannel()
    if not channel then return end
    Send(("H1:%d:%d:%d:%s"):format(mapID, math.floor(x * 10000 + 0.5), math.floor(y * 10000 + 0.5), KIND_CODE[kind] or "-"), channel)
end

-- A route to your group, or to one player (name): sent in parts
function GP:SendRoute(route, target)
    local channel = target and "WHISPER" or GroupChannel()
    if not channel then
        Print(L["you're not in a group. Type a player's name to send it to them."])
        return false
    end
    local line = self:ExportRoute(route)
    local parts = math.ceil(#line / self.SYNC_PART)
    local id = math.random(1000, 9999)
    local k = 0
    local function Next()
        k = k + 1
        Send(("R1:%d:%d:%d:%s"):format(id, k, parts, line:sub((k - 1) * self.SYNC_PART + 1, k * self.SYNC_PART)), channel, target)
        return k < parts
    end
    if C_Timer and C_Timer.NewTicker then
        local ticker
        ticker = C_Timer.NewTicker(self.SYNC_GAP, function() if not Next() then ticker:Cancel() end end)
    else
        while Next() do end
    end
    Print(target and L["sending |cffffd100%s|r to %s."]:format(route.name, target)
        or L["sending |cffffd100%s|r to your group."]:format(route.name))
    return true
end

-- Routes coming in: [sender .. id] = { parts = n, got = { ... } }
local incoming = {}

function GP:OnSync(msg, sender)
    if type(msg) ~= "string" then return end
    local who = sender and sender:match("^([^%-]+)") or sender
    if who == Me() then return end
    local kind, rest = msg:match("^(%u%d):(.*)$")
    if kind == "H1" then
        if not self.db.syncGroup then return end
        local m, x, y, k = rest:match("^(%d+):(%d+):(%d+):([hm%-])$")
        m, x, y = tonumber(m), tonumber(x), tonumber(y)
        if m and x and y then self:RecordHarvest(m, x / 10000, y / 10000, nil, CODE_KIND[k], who or "?") end
    elseif kind == "R1" then
        local id, k, n, text = rest:match("^(%d+):(%d+):(%d+):(.*)$")
        k, n = tonumber(k), tonumber(n)
        if not (id and k and n) or n > 400 or k > n then return end
        local key = tostring(sender) .. id
        local e = incoming[key] or { parts = n, got = {}, count = 0, t = GetTime() }
        incoming[key] = e
        if not e.got[k] then e.got[k], e.count = text, e.count + 1 end
        if e.count == e.parts then
            incoming[key] = nil
            local line = table.concat(e.got)
            local route = self:ParseShared(line)
            if not route then return end
            self:Confirm(L["|cffffd100%s|r sent you the route |cff3fd0a0%s|r (%s). Add it?"]:format(who or "?", route.name,
                self:MapName(route.mapID)), L["Add"], function() self:ImportShared(line) end)
        end
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, event, prefix, msg, channel, sender)
    if event == "PLAYER_LOGIN" then
        local C = _G.C_ChatInfo
        local reg = C and C.RegisterAddonMessagePrefix or _G.RegisterAddonMessagePrefix
        if reg then pcall(reg, GP.SYNC_PREFIX) end
    elseif prefix == GP.SYNC_PREFIX and GP.db then
        GP:OnSync(msg, sender)
    end
end)
GP.syncFrame = frame
