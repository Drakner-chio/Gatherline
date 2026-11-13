-- Gatherline: sharing routes. A route goes out as one line of text (Share on
-- its card), to paste to a friend; Import in the window takes such a line and
-- adds the route, exactly as it was: the same stops, the same lines along the
-- ground, its colour and pass distance.
--
-- The line: GL1^<check>^<fields...>, fields separated by ^, text in them with
-- % ^ ~ ; = , | and spaces written as %XX. Map positions are kept to 4 decimals (as routes
-- store them) and written 3 characters each. <check> is a short sum of the
-- rest, so a line cut short or changed is turned down instead of half read.

local ADDON, ns = ...
local L = ns.L
local GP = ns.GP
local Print = GP.Print
local floor = math.floor

local PREFIX = "GL1"
local DIGITS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local VALUE = {}
for i = 1, #DIGITS do VALUE[DIGITS:sub(i, i)] = i - 1 end

-- Text inside a field
local function Escape(s)
    return (tostring(s):gsub("[%%%^~;=,| \t\n\r]", function(c) return ("%%%02X"):format(c:byte()) end))
end
local function Unescape(s)
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

-- Map positions: -0.5 .. 1.5 in steps of 1/10000, three characters each
local function EncodePoints(list)
    if type(list) ~= "table" then return "" end
    local out = {}
    for i = 1, #list do
        local k = floor((list[i] + 0.5) * 10000 + 0.5)
        if k < 0 then k = 0 elseif k > 262143 then k = 262143 end
        local a, b, c = floor(k / 4096), floor(k / 64) % 64, k % 64
        out[i] = DIGITS:sub(a + 1, a + 1) .. DIGITS:sub(b + 1, b + 1) .. DIGITS:sub(c + 1, c + 1)
    end
    return table.concat(out)
end
local function DecodePoints(s)
    if #s % 3 ~= 0 then return nil end
    local out = {}
    for i = 1, #s, 3 do
        local a, b, c = VALUE[s:sub(i, i)], VALUE[s:sub(i + 1, i + 1)], VALUE[s:sub(i + 2, i + 2)]
        if not (a and b and c) then return nil end
        out[#out + 1] = (a * 4096 + b * 64 + c) / 10000 - 0.5
    end
    return out
end

local function Check(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 16777213 end
    return ("%06x"):format(h)
end

local function Num(v, fmt) return (fmt or "%.4f"):format(v or 0):gsub("%.?0+$", "") end

-- A route as one line of text
function GP:ExportRoute(route)
    local kinds = {}
    for kind, names in pairs(route.kinds or {}) do
        local list = {}
        for name, on in pairs(names) do if on then list[#list + 1] = Escape(name) end end
        table.sort(list)
        kinds[#kinds + 1] = Escape(kind) .. "=" .. table.concat(list, "~")
    end
    table.sort(kinds)
    local c = route.color or { 1, 0.82, 0 }
    local fields = {
        tostring(route.mapID),
        Escape(route.name or "Route"),
        Num(c[1], "%.3f") .. "," .. Num(c[2], "%.3f") .. "," .. Num(c[3], "%.3f"),
        tostring(floor(route.sight or 0)),
        tostring(floor(self:RouteNodes(route))),
        tostring(floor((route.length or self:RouteLength(route)) + 0.5)),
        route.walked and "1" or "0",
        Num(route.walkFactor or 1, "%.3f"),
        table.concat(kinds, ";"),
        EncodePoints(route.points),
        EncodePoints(route.drawn),
    }
    local body = table.concat(fields, "^")
    return PREFIX .. "^" .. Check(body) .. "^" .. body
end

-- Reads a shared line. Returns a route (not added yet), or nil and why.
function GP:ParseShared(text)
    if type(text) ~= "string" then return nil, L["that isn't a Gatherline route."] end
    text = text:gsub("%s+", "")
    local check, body = text:match("^" .. PREFIX .. "%^(%x%x%x%x%x%x)%^(.*)$")
    if not check then
        if text:match("^GL%d+%^") then return nil, L["that route is from a newer Gatherline. Update Gatherline, then try again."] end
        return nil, L["that isn't a Gatherline route."]
    end
    if Check(body) ~= check:lower() then return nil, L["that route didn't come through whole. Copy it again, all of it."] end
    local f = {}
    for part in (body .. "^"):gmatch("([^%^]*)%^") do f[#f + 1] = part end
    if #f < 11 then return nil, L["that route didn't come through whole. Copy it again, all of it."] end
    local mapID = tonumber(f[1])
    local points = DecodePoints(f[10])
    if not mapID or not points or #points < 4 or #points % 2 ~= 0 then
        return nil, L["that route didn't come through whole. Copy it again, all of it."]
    end
    local drawn = f[11] ~= "" and DecodePoints(f[11]) or nil
    if drawn and (#drawn < 4 or #drawn % 2 ~= 0) then drawn = nil end
    local r, g, b = f[3]:match("^([%d%.]+),([%d%.]+),([%d%.]+)$")
    local kinds = {}
    for entry in f[9]:gmatch("[^;]+") do
        local kind, names = entry:match("^([^=]*)=(.*)$")
        if kind then
            local set = {}
            for name in names:gmatch("[^~]+") do set[Unescape(name)] = true end
            kinds[Unescape(kind)] = set
        end
    end
    local function clamp(v) v = tonumber(v) or 0 return math.max(0, math.min(1, v)) end
    local route = {
        mapID = mapID,
        name = Unescape(f[2]),
        color = r and { clamp(r), clamp(g), clamp(b) } or { 1, 0.82, 0 },
        sight = math.max(0, math.min(200, tonumber(f[4]) or 0)),
        nodes = tonumber(f[5]),
        length = tonumber(f[6]),
        walked = f[7] == "1" or nil,
        walkFactor = f[7] == "1" and math.max(1, tonumber(f[8]) or 1) or nil,
        kinds = kinds,
        points = points,
        drawn = drawn,
        shown = true,
    }
    if route.name:match("^%s*$") then route.name = self:MapName(mapID) .. " - Route" end
    return route
end

-- Adds a shared route. Returns it, or nil (and says why in chat).
function GP:ImportShared(text)
    local route, why = self:ParseShared(text)
    if not route then Print(why) return nil end
    -- a name already in that zone gets a number
    local base, k = route.name, 2
    while self:RouteNamed(route.mapID, route.name) do
        route.name = ("%s (%d)"):format(base, k)
        k = k + 1
    end
    route.id = self.db.nextID
    self.db.nextID = self.db.nextID + 1
    table.insert(self.db.routes, route)
    route.length = self:RouteLength(route)
    Print(L["added |cffffd100%s|r in %s: %d stops, %s round."]:format(route.name, self:MapName(route.mapID),
        self:NodeCount(route), self.FormatYards(route.length)))
    self:Changed()
    return route
end

---------------------------------------------------------------------------
-- Statistics compared: the route that brings the most an hour
---------------------------------------------------------------------------
GP.BEST_MIN_SECONDS = 600   -- a route needs this long ridden to be compared

-- What a route brings an hour: gold if Auctionator priced the loot, else nodes
local function PerHour(route)
    local s = route.stats
    if type(s) ~= "table" or (s.rideTime or 0) < GP.BEST_MIN_SECONDS then return nil end
    local hours = s.rideTime / 3600
    return (s.value or 0) / hours, (s.gathered or 0) / hours
end
GP.PerHour = PerHour

-- Routes ridden long enough to compare, best first (gold an hour, then nodes an hour)
function GP:RankedRoutes(list)
    local out = {}
    for _, r in ipairs(list or self.db.routes) do
        local gold, nodes = PerHour(r)
        if gold then out[#out + 1] = { route = r, gold = gold, nodes = nodes } end
    end
    table.sort(out, function(a, b)
        if (a.gold > 0 or b.gold > 0) and a.gold ~= b.gold then return a.gold > b.gold end
        if a.nodes ~= b.nodes then return a.nodes > b.nodes end
        return a.route.name < b.route.name
    end)
    return out
end

-- The best of the routes in a zone, if two or more can be compared there
function GP:BestRouteOn(mapID)
    local ranked = self:RankedRoutes(self:RoutesOn(mapID))
    if #ranked >= 2 then return ranked[1].route end
end

function GP:PrintRanking()
    local ranked = self:RankedRoutes()
    if #ranked == 0 then
        Print(L["no route ridden long enough to compare yet (10 minutes each)."])
        return
    end
    Print(L["your routes, best first:"])
    for i = 1, math.min(#ranked, 10) do
        local e = ranked[i]
        local what = L["%d nodes/h"]:format(floor(e.nodes + 0.5))
        if e.gold > 0 then what = L["%s/h"]:format(self.FormatMoney(e.gold)) .. ", " .. what end
        print(("  %d. |cffffd100%s|r (%s): %s"):format(i, e.route.name, self:MapName(e.route.mapID), what))
    end
end

---------------------------------------------------------------------------
-- The share window: a line to copy, or a box to paste one into
---------------------------------------------------------------------------
local T = ns.Theme
function GP:ShareWindow(route)
    local C = T.C
    local f = self.shareWindow
    if not f then
        f = CreateFrame("Frame", "GatherlineShare", UIParent)
        f:SetSize(460, 150)
        f:SetPoint("CENTER", 0, 80)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetToplevel(true)
        f:EnableMouse(true)
        f:Hide()
        table.insert(UISpecialFrames, "GatherlineShare")
        T.Fill(f, C.win)
        T.Border(f, C.edge)
        f.title = T.Text(f, "", "GameFontNormal")
        f.title:SetPoint("TOPLEFT", 16, -14)
        f.text = T.Text(f, "", "GameFontHighlightSmall")
        f.text:SetPoint("TOPLEFT", 16, -36)
        f.text:SetWidth(428)
        f.text:SetWordWrap(true)
        f.box = T.EditBox(f, 428)
        f.box:SetPoint("TOPLEFT", 16, -76)
        f.box:SetMaxLetters(0)
        f.box:SetScript("OnEscapePressed", function() f:Hide() end)
        f.close = T.FlatButton(f, "Close", 100)
        f.close:SetPoint("BOTTOMRIGHT", -16, 14)
        f.close:SetScript("OnClick", function() f:Hide() end)
        f.go = T.FlatButton(f, "Import", 120)
        f.go:SetPoint("RIGHT", f.close, "LEFT", -8, 0)
        f.go:SetPrimary(true)
        f.go:SetScript("OnClick", function()
            if GP:ImportShared(f.box:GetText()) then f:Hide() end
        end)
        self.shareWindow = f
    end
    if route then
        local line = self:ExportRoute(route)
        f.mode, f.line = "share", line
        f.title:SetText(L["Share %s"]:format(route.name))
        f.text:SetText(L["Copy this line (Ctrl+C) and send it to a friend. In Gatherline they click Import and paste it."])
        f.box:SetText(line)
        f.box:SetScript("OnTextChanged", function(self, user) if user then self:SetText(f.line); self:HighlightText() end end)
        f.box:SetScript("OnEnterPressed", function() f:Hide() end)
        f.go:Hide()
        f:Show()
        f.box:SetFocus()
        f.box:HighlightText()
    else
        f.mode, f.line = "import", nil
        f.title:SetText(L["Import a route"])
        f.text:SetText(L["Paste a route a friend shared (Ctrl+V), then click Import."])
        f.box:SetScript("OnTextChanged", nil)
        f.box:SetText("")
        f.box:SetScript("OnEnterPressed", function() if GP:ImportShared(f.box:GetText()) then f:Hide() end end)
        f.go:Show()
        f:Show()
        f.box:SetFocus()
    end
    return f
end
