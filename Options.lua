-- Gatherline: the window (/gl), in Gatherline's look (Theme.lua).
-- Menu down the left in three groups: Routes (My routes, New route), On the
-- way (Guidance, Map & lines, No-go areas) and Gatherline (About).
--
-- Layout rules: rows 26 apart; a dropdown after a row label starts at DROP_X;
-- lists that can grow (routes, kinds of node) scroll.

local ADDON, ns = ...
local L = ns.L
local GP = ns.GP
local T = ns.Theme
local C, Text, FlatButton, Card = T.C, T.Text, T.FlatButton, T.Card

local PAGE_W = T.WINDOW.PAGE_W
local WINDOW_H = T.WINDOW.H + 120   -- taller than the other addons' windows: room for more nodes
local BODY_H = T.BodyHeight(WINDOW_H)
local DROP_X = 52
local COL2 = 270

local refreshers = {}
local function AddRefresher(fn) table.insert(refreshers, fn) end

-- The window's widgets the tests look at
local refs = {}
GP.ui = refs

-- A colored square that opens the game's color picker. get(self) is the color
-- now ({ r, g, b }, nil = nothing to pick), set(self, r, g, b) keeps a new one.
local function Swatch(parent, get, set, title, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(22, 22)
    b.fill = T.Fill(b, { 1, 1, 1, 1 }, "ARTWORK")
    T.Border(b, C.edge)
    function b:Paint(c) self.fill:SetColorTexture(c[1], c[2], c[3], 1) end
    T.Disabler(b, { b })
    b:SetScript("OnClick", function(self)
        local now = not self.disabled and get(self)
        local picker = ColorPickerFrame
        if not (now and picker and picker.SetupColorPickerAndShow) then return end
        local before = { unpack(now) }
        picker:SetupColorPickerAndShow({
            r = before[1], g = before[2], b = before[3], hasOpacity = false,
            swatchFunc = function()
                local r, g, bl = picker:GetColorRGB()
                set(self, r, g, bl)
            end,
            cancelFunc = function()
                set(self, before[1], before[2], before[3])
            end,
        })
    end)
    T.Tooltip(b, title, tip)
    return b
end

---------------------------------------------------------------------------
-- A small "are you sure" window
---------------------------------------------------------------------------
function GP:Confirm(text, yesLabel, onYes)
    local f = self.confirmWindow
    if not f then
        f = CreateFrame("Frame", "GatherlineConfirm", UIParent)
        f:SetSize(380, 130)
        f:SetPoint("CENTER", 0, 80)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetToplevel(true)
        f:EnableMouse(true)
        f:Hide()
        table.insert(UISpecialFrames, "GatherlineConfirm")   -- Escape is Cancel
        T.Fill(f, C.win)
        T.Border(f, C.edge)
        f.text = Text(f, "", "GameFontHighlight")
        f.text:SetPoint("TOPLEFT", 16, -16)
        f.text:SetWidth(348)
        f.text:SetWordWrap(true)
        f.no = FlatButton(f, "Cancel", 100)
        f.no:SetPoint("BOTTOMRIGHT", -16, 14)
        f.no:SetScript("OnClick", function() f:Hide() end)
        f.yes = FlatButton(f, "", 120)
        f.yes:SetPoint("RIGHT", f.no, "LEFT", -8, 0)
        self.confirmWindow = f
    end
    f.text:SetText(text)
    f.yes:SetText(L[yesLabel])
    f.yes:SetPrimary(true)
    f.yes:SetScript("OnClick", function()
        f:Hide()
        onYes()
    end)
    f:Show()
    return f
end

---------------------------------------------------------------------------
-- Routes tab
---------------------------------------------------------------------------
local ROW_H = 104
local INFO_W = PAGE_W - 16 - 100 - 16 - 10   -- from the left to Show
local routesZone   -- the map whose routes are listed

local function RoutesZoneChoices()
    local list = GP:RouteZones()
    local here = GP:PlayerMap()
    local has = false
    for _, m in ipairs(list) do if m == here then has = true end end
    if here and not has then table.insert(list, 1, here) end
    return list
end

local function PickRoutesZone()
    local list = RoutesZoneChoices()
    for _, m in ipairs(list) do if m == routesZone then return end end
    local here = GP:PlayerMap()
    if here and #GP:RoutesOn(here) > 0 then routesZone = here return end
    routesZone = GP:RouteZones()[1] or here
end

local function BuildRoutes(p)
    T.RowLabel(p, "Zone", 0, 0)
    local zone = T.Dropdown(p, 250, {}, function(k) return GP:MapName(k) end,
        function() return routesZone end, function(k) routesZone = k; GP:RefreshConfig() end)
    zone:SetPoint("TOPLEFT", DROP_X, 0)
    zone.menuScroll = 300
    refs.routesZone = zone

    local make = FlatButton(p, "New route", 110)
    make:SetPoint("TOPRIGHT", 0, 0)
    make:SetScript("OnClick", function() GP:NewRouteInWindow(routesZone) end)
    T.Tooltip(make, "New route", "Make a route in the zone picked here.")
    refs.routesNew = make
    local import = FlatButton(p, "Import", 96)
    import:SetPoint("RIGHT", make, "LEFT", -6, 0)
    import:SetScript("OnClick", function() GP:ShareWindow() end)
    T.Tooltip(import, "Import", "Add a route a friend shared with you: paste the line they sent.")
    refs.routesImport = import

    local holder = CreateFrame("Frame", nil, p)
    holder:SetPoint("TOPLEFT", 0, -34)
    holder:SetSize(PAGE_W, BODY_H - 34)
    local scroll = T.ScrollArea(holder, BODY_H - 34)
    local list = scroll.child
    local empty = T.Note(p, "", 0, -44, PAGE_W)
    refs.routesEmpty = empty
    local rows = {}
    refs.routeRows = rows

    local function Row(i)
        if rows[i] then return rows[i] end
        local r = CreateFrame("Frame", nil, list)
        r:SetSize(PAGE_W - 16, ROW_H - 8)
        T.Fill(r, C.card)
        T.Border(r, C.line)
        -- left edge: the line's color (click to change); top: name, then Start
        -- and the small actions at the right; below: what it is, and Show
        r.swatch = Swatch(r,
            function(b) return b.route and b.route.color end,
            function(b, cr, cg, cb) GP:SetRouteColor(b.route, cr, cg, cb) end,
            "Line color", "Click to pick the color of this route's line.")
        r.swatch:ClearAllPoints()
        r.swatch:SetPoint("TOPLEFT", 1, -1)
        r.swatch:SetPoint("BOTTOMLEFT", 1, 1)
        r.swatch:SetWidth(5)
        r.name = T.EditBox(r, 200)
        r.name:SetPoint("TOPLEFT", 16, -10)
        local function rename(self)
            if r.route and self:GetText() ~= r.route.name then GP:RenameRoute(r.route, self:GetText()) end
            if r.route then self:SetText(r.route.name) end
        end
        r.name:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        r.name:SetScript("OnEditFocusLost", rename)

        local function Action(texture, title, tip, onClick)
            local b = T.IconButton(r, texture, 24)
            b:SetScript("OnClick", function(self)
                if self.disabled == true or not r.route then return end
                onClick(r.route)
            end)
            T.Disabler(b, { b })
            T.Tooltip(b, title, tip)
            return b
        end
        r.delete = Action("Interface\\Buttons\\UI-StopButton", "Delete", "Delete this route.", function(route)
            GP:Confirm(L["Delete the route |cff3fd0a0%s|r?"]:format(route.name), L["Delete"],
                function() GP:DeleteRoute(route) end)
        end)
        r.delete:SetPoint("TOPRIGHT", -10, -10)
        r.rebuild = Action("Interface\\Buttons\\UI-RefreshButton", "Rebuild",
            "Reads this route's nodes again (GatherMate2 or GatherLite may know more by now) and finds the shortest loop again.",
            function(route) GP:RebuildRoute(route) end)
        r.rebuild:SetPoint("RIGHT", r.delete, "LEFT", -4, 0)
        r.edit = Action("Interface\\Buttons\\UI-GuildButton-PublicNote-Up", "Edit",
            "Change this route's zone, nodes, name and pass distance, then find its loop again.",
            function(route) GP:EditRouteInWindow(route) end)
        r.edit:SetPoint("RIGHT", r.rebuild, "LEFT", -4, 0)
        r.turn = Action("Interface\\Buttons\\UI-RotationRight-Button-Up", "Turn round",
            "Ride this loop the other way round. The arrows turn with it, and a ride on it carries on the new way.",
            function(route) GP:ReverseRoute(route) end)
        r.turn:SetPoint("RIGHT", r.edit, "LEFT", -4, 0)
        r.share = Action("Interface\\Icons\\INV_Letter_15", "Share",
            "A line of text with this route in it, to send to a friend: they click Import and get exactly this loop.",
            function(route) GP:ShareWindow(route) end)
        r.share:SetPoint("RIGHT", r.turn, "LEFT", -4, 0)
        refs.shareButtons = refs.shareButtons or {}
        refs.shareButtons[i] = r.share
        r.ride = FlatButton(r, "Start", 72, 24)
        r.ride:SetPrimary(true)
        r.ride:SetPoint("RIGHT", r.share, "LEFT", -8, 0)
        r.ride:SetScript("OnClick", function(self)
            if self.disabled or not r.route then return end
            if GP:IsNavigating(r.route) then GP:StopNav() else GP:StartNav(r.route) end
        end)
        T.Disabler(r.ride, { r.ride })
        T.Tooltip(r.ride, "Start / Stop", "Ride this loop with Shortest Path Forever's arrow and tracker. From another zone it leads you to the route first (flights, boats, portals), then round it, from the nearest stop in the way the arrows point.")
        refs.turnButtons = refs.turnButtons or {}
        refs.turnButtons[i] = r.turn
        refs.rideButtons = refs.rideButtons or {}
        refs.rideButtons[i] = r.ride

        r.info = Text(r, "", "GameFontDisableSmall")
        r.info:SetPoint("TOPLEFT", 16, -42)
        r.info:SetWidth(INFO_W)
        r.info:SetWordWrap(true)
        r.show = T.LabeledSwitch(r, "Show", PAGE_W - 16 - 100, -46)
        r.show:SetScript("OnClick", function(self)
            if r.route then GP:SetRouteShown(r.route, not self:IsOn()) end
        end)
        T.Tooltip(r.show, "Show", "Draw this route on the world map and the minimap.")
        rows[i] = r
        return r
    end

    AddRefresher(function()
        PickRoutesZone()
        zone.keys = RoutesZoneChoices()
        zone:Refresh()
        local routes = routesZone and GP:RoutesOn(routesZone) or {}
        local best = routesZone and GP:BestRouteOn(routesZone)
        for i, route in ipairs(routes) do
            local r = Row(i)
            r.route = route
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
            r:Show()
            r.swatch.route = route
            r.swatch:Paint(route.color)
            if not r.name:HasFocus() then r.name:SetText(route.name) end
            r.show:SetOn(route.shown)
            if route.working then
                if route.walkOf and route.walkDone and route.walkDone < route.walkOf then
                    r.info:SetText(L["Measuring the ways on foot between stops: %d of %d..."]:format(route.walkDone, route.walkOf))
                elseif route.walkTrace then
                    r.info:SetText(L["Tracing the lines along the ground: %d of %d legs..."]:format(route.walkTrace, route.walkTraceOf))
                elseif route.walkLegs then
                    r.info:SetText(L["Walking the loops leg by leg to find the shortest: %d legs so far..."]:format(route.walkLegs))
                else
                    r.info:SetText(L["Working out the shortest loop..."])
                end
            else
                local kinds = {}
                for kind, names in pairs(route.kinds) do
                    if next(names) then kinds[#kinds + 1] = GP:KindName(kind) end
                end
                table.sort(kinds)
                -- two short lines: what it is, then how it rides
                local dot = "  |cff4a4f58\226\128\162|r  "
                local line1 = L["%d nodes"]:format(GP:RouteNodes(route)) .. dot
                    .. L["%s round"]:format(GP.FormatYards(route.length or GP:RouteLength(route))) .. dot
                    .. table.concat(kinds, ", ")
                local lap = (GP.db.speed and L["%s a lap"] or L["%s a lap on foot"]):format(GP:LapTime(route))
                local parts = { (lap:gsub("^%l", string.upper)) }
                if (route.sight or 0) > 0 then parts[#parts + 1] = L["passes within %d yards"]:format(route.sight) end
                if route.walked then parts[#parts + 1] = "|cff" .. T.ACCENT_HEX .. L["over the ground"] .. "|r" end
                local text = line1 .. "\n" .. table.concat(parts, dot)
                local stats = GP:StatsLine(route)
                if stats then
                    if best == route then stats = stats .. "  |cffffd100" .. L["best here"] .. "|r" end
                    text = text .. "\n|cffb8bcc4" .. stats .. "|r"
                end
                r.info:SetText(text)
            end
            r.rebuild:SetDisabled(GP:Busy())
            local riding = GP:IsNavigating(route)
            r.ride:SetText(riding and L["Stop"] or L["Start"])
            r.ride:SetDisabled(not riding and (route.working or GP:NodeCount(route) < 2 or not GP:CanNavigate()))
            r.turn:SetDisabled(route.working or GP:NodeCount(route) < 2)
            r.share:SetDisabled(route.working or GP:NodeCount(route) < 2)
            if riding and not route.working then
                local first, rest = r.info:GetText():match("^([^\n]*)\n[^\n]*(.*)$")
                r.info:SetText((first or r.info:GetText()) .. "\n|cff" .. T.ACCENT_HEX .. GP:NavStatus() .. "|r" .. (rest or ""))
            end
            r.edit:SetDisabled(route.working)
        end
        for i = #routes + 1, #rows do rows[i]:Hide(); rows[i].route = nil end
        scroll:SetContent(PAGE_W - 16, math.max(1, #routes * ROW_H), true)
        if #routes == 0 then
            empty:SetText(GP:HasNodeSource()
                and L["No routes in this zone yet. Click New route to make one."]
                or L["Gatherline needs GatherMate2 or GatherLite, where the herb and ore nodes come from. Install one from CurseForge, then /reload."])
        else
            empty:SetText(L[""])
        end
    end)
end

---------------------------------------------------------------------------
-- New route tab (also where a route is edited)
---------------------------------------------------------------------------
-- What's picked. Opening the tab starts it blank (ResetNew); Edit fills it
-- from a route (EditInWindow) and Save changes that route.
local newZone, picked, newSight, editing = nil, {}, nil, nil
local nameBox
local prefixZone   -- the zone whose "Zone - " the name box was started with

-- A new route's name starts with its zone: "The Barrens - "
local function Prefix(mapID) return mapID and (GP:MapName(mapID) .. " - ") or "" end
local function Trim(text) return (text or ""):match("^%s*(.-)%s*$") end
-- Only the zone (or nothing) typed: the rest is made from the nodes picked
local function OnlyPrefix(text, mapID)
    local t = Trim(text)
    return t == "" or (mapID and t == Trim(Prefix(mapID)))
end

local function Sight() return newSight or GP.DEFAULTS.sight end

local function ResetNew()
    newZone, picked, newSight, editing, prefixZone = nil, {}, nil, nil, nil
    if nameBox then nameBox:SetText(L[""]); nameBox:ClearFocus() end
end

local function EditInWindow(route)
    newZone, newSight, editing, prefixZone = route.mapID, route.sight or 0, route, route.mapID
    picked = {}
    for kind, names in pairs(route.kinds) do
        for n in pairs(names) do
            picked[kind] = picked[kind] or {}
            picked[kind][n] = true
        end
    end
    nameBox:SetText(route.name)
    nameBox:ClearFocus()
end

local function BuildNew(p, page)
    T.RowLabel(p, "Zone", 0, 0)
    local zone = T.Dropdown(p, 240, {}, function(k) return k and GP:MapName(k) or "Pick a zone" end,
        function() return newZone end, function(k)
            if k ~= newZone then newZone, picked = k, {} end
            GP:RefreshConfig()
        end)
    zone:SetPoint("TOPLEFT", DROP_X, 0)
    zone.menuScroll = 300
    refs.newZone = zone
    local here = FlatButton(p, "My zone", 90)
    here:SetPoint("LEFT", zone, "RIGHT", 8, 0)
    here:SetScript("OnClick", function()
        local m = GP:PlayerMap()
        if m and m ~= newZone then newZone, picked = m, {} end
        GP:RefreshConfig()
    end)
    T.Tooltip(here, "My zone", "Pick the zone you're in.")
    refs.myZone = here
    local skill = FlatButton(p, "Where to skill up", 132)
    skill:SetPoint("TOPRIGHT", 0, 0)
    skill:SetScript("OnClick", function()
        local best = GP:PrintSkillUp()
        if not best then return end
        -- that zone, with the nodes that still raise your skill picked
        newZone, picked = best.mapID, {}
        for _, e in ipairs(best.nodes) do
            if e.colour == "orange" or e.colour == "yellow" then
                picked[e.kind] = picked[e.kind] or {}
                picked[e.kind][e.name] = true
            end
        end
        GP:RefreshConfig()
    end)
    T.Tooltip(skill, "Where to skill up",
        "Looks through every zone for the herbs and ores that still raise your Herbalism or Mining (orange and yellow), lists the best zones in chat, and picks the best one here with those nodes on.")
    refs.skillUp = skill

    local LIST_H = 210 + (WINDOW_H - T.WINDOW.H)
    local holder = CreateFrame("Frame", nil, p)
    holder:SetPoint("TOPLEFT", 0, -34)
    holder:SetSize(PAGE_W, LIST_H)
    T.Fill(holder, C.card)
    T.Border(holder, C.line)
    local inner = CreateFrame("Frame", nil, holder)
    inner:SetPoint("TOPLEFT", 10, -8)
    inner:SetPoint("BOTTOMRIGHT", -4, 8)
    local scroll = T.ScrollArea(inner, LIST_H - 16)
    local list = scroll.child
    local note = T.Note(holder, "", 12, -12, PAGE_W - 24)
    refs.newNote = note
    local heads, switches = {}, {}
    refs.kindSwitches = switches
    refs.kindHeads = heads

    -- below the list: name, passes within, make (or save and cancel)
    local y = -34 - LIST_H - 14
    T.RowLabel(p, "Name", 0, y)
    local name = T.EditBox(p, 300)
    name:SetPoint("TOPLEFT", DROP_X, y)
    nameBox = name
    -- grey hint after the zone: the rest of the name, made from what's picked
    local hint = Text(name, "", "GameFontDisableSmall")
    local measure = Text(name, "", "GameFontHighlightSmall")
    measure:Hide()
    local function ShowHint()
        local text = name:GetText()
        local on = not name:HasFocus() and OnlyPrefix(text, newZone)
        if on then
            measure:SetText(text)
            local w = measure:GetStringWidth()
            hint:ClearAllPoints()
            hint:SetPoint("LEFT", 6 + (type(w) == "number" and w or 0), 0)
        end
        hint:SetShown(on)
    end
    name:SetScript("OnEditFocusGained", function() hint:Hide() end)
    name:SetScript("OnEditFocusLost", ShowHint)
    name:SetScript("OnTextChanged", ShowHint)
    refs.newName = name
    refs.newHint = hint

    local sight = T.Slider(p, "Route passes within", 0, y - 36, 300, Sight,
        function(v) newSight = v end,
        GP.RANGES.sight[1], GP.RANGES.sight[2], " yards", 5, nil, "Off")
    T.Tooltip(sight, "Route passes within",
        "With Find Herbs or Find Minerals on, you see a node on the minimap before you reach it. The route only has to come this close to each node, so it cuts corners and is shorter, and nodes close together become one stop. Off takes you right up to every node.")
    AddRefresher(sight.Refresh)
    refs.sightSlider = sight

    local ground = T.LabeledSwitch(p, "Follow the ground", 0, y - 92)
    ground:SetScript("OnClick", function(self)
        GP.db.walkRoutes = not self:IsOn()
        self:SetOn(GP.db.walkRoutes)
    end)
    T.Tooltip(ground, "Follow the ground",
        "Work the loop out with the ways on foot from Shortest Path Forever's walking maps, so it goes round mountains, cliffs and water instead of over them. Takes a little longer. Off: straight lines, as GatherPath Forever does.")
    AddRefresher(function()
        ground:SetOn(GP.db.walkRoutes)
        local ok = GP.Walk and GP.Walk.Ready(newZone or GP:PlayerMap() or 0)
        ground:SetDisabled(not ok)
    end)
    refs.groundSwitch = ground

    local only = T.LabeledSwitch(p, "Only what I can gather", 0, y - 122)
    only:SetScript("OnClick", function(self)
        GP.db.onlyGatherable = not self:IsOn()
        GP:RefreshConfig()
    end)
    T.Tooltip(only, "Only what I can gather",
        "List only the herbs and ores your Herbalism or Mining is high enough for. The number after each node is the skill it needs, in the game's colours: red you can't gather yet, orange and yellow raise your skill, green a little, grey no more.")
    AddRefresher(function() only:SetOn(GP.db.onlyGatherable) end)
    refs.onlySwitch = only

    local make = FlatButton(p, "Make route", 130, 26)
    make:SetPoint("TOPRIGHT", 0, y - 40)
    refs.makeButton = make
    make:SetScript("OnClick", function(self)
        if self.disabled then return end
        local kinds = {}
        for kind, names in pairs(picked) do
            for n, on in pairs(names) do
                if on and not GP:IsSkipped(n) and not (GP.db.onlyGatherable and not GP:CanGather(n, kind)) then
                    kinds[kind] = kinds[kind] or {}
                    kinds[kind][n] = true
                end
            end
        end
        local typed = name:GetText()
        if OnlyPrefix(typed, newZone) then typed = Prefix(newZone) .. GP:RouteName(newZone, kinds) end
        local opts = { mapID = newZone, kinds = kinds, name = typed, sight = Sight() }
        local route
        if editing then
            route = GP:EditRoute(editing, opts) and editing
        else
            route = GP:NewRoute(opts)
        end
        if route then
            ResetNew()
            routesZone = route.mapID
            GP:OpenConfig("routes")
        end
    end)
    T.Disabler(make, { make })

    local cancel = FlatButton(p, "Cancel", 130, 22)
    cancel:SetPoint("TOPRIGHT", 0, y - 74)
    cancel:SetScript("OnClick", function()
        local route = editing
        ResetNew()
        if route then routesZone = route.mapID end
        GP:OpenConfig("routes")
    end)
    T.Tooltip(cancel, "Cancel", "Leave the route as it was.")
    refs.cancelButton = cancel

    -- a kind's heading, with Select all (Clear all once every node of it is on)
    local function Head(i)
        if heads[i] then return heads[i] end
        local h = Text(list, "", "GameFontNormalSmall", C.orange)
        local all = FlatButton(list, "Select all", 84, 18)
        all:SetScript("OnClick", function(self)
            local kind, entries = self.kind, self.entries
            if not kind then return end
            local on = not self.allOn
            picked[kind] = picked[kind] or {}
            for _, e in ipairs(entries) do
                if not e.skip then picked[kind][e.name] = on or nil end
            end
            GP:RefreshConfig()
        end)
        T.Tooltip(all, "Select all", "Switch on every node of this kind (click again to switch them all off). Nodes on your skip list stay off.")
        h.all = all
        heads[i] = h
        return h
    end
    local function Switch(i)
        if switches[i] then return switches[i] end
        local sw = T.LabeledSwitch(list, "", 0, 0, 200)
        sw:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        sw:SetScript("OnClick", function(self, button)
            local e = self.entry
            if not e then return end
            picked[e.kind] = picked[e.kind] or {}
            if button == "RightButton" then
                -- on or off the skip list (in every zone)
                local skip = not GP:IsSkipped(e.name)
                if skip then picked[e.kind][e.name] = nil end
                GP:SetSkipped(e.name, skip)
                GP.Print(skip and L["|cffffd100%s|r is skipped: no route uses it. Routes that had it drop it when you Rebuild them. Right-click it again to stop skipping it."]:format(e.name)
                    or L["|cffffd100%s|r is no longer skipped."]:format(e.name))
                return
            end
            if GP:IsSkipped(e.name) then
                GP:SetSkipped(e.name, false)   -- clicking a skipped node takes it off the list and picks it
                picked[e.kind][e.name] = true
            else
                picked[e.kind][e.name] = not self:IsOn() or nil
            end
            GP:RefreshConfig()
        end)
        T.Tooltip(sw, nil, "Click to put this node in the route. Right-click to skip it everywhere (for poor or wilted nodes): Select all, new nodes and rebuilt routes leave it out.")
        switches[i] = sw
        return sw
    end

    AddRefresher(function()
        -- the route being edited was deleted meanwhile
        if editing then
            local found = false
            for _, r in ipairs(GP.db.routes) do if r == editing then found = true end end
            if not found then ResetNew() end
        end
        page.title:SetText(editing and L["Edit route"] or L["New route"])
        zone.keys = GP:GatherZones()
        zone:Refresh()
        local nodes = newZone and GP:ZoneNodes(newZone) or {}
        if GP.db.onlyGatherable then
            local keep = {}
            for _, e in ipairs(nodes) do if GP:CanGather(e.name, e.kind) then keep[#keep + 1] = e end end
            nodes = keep
        end
        local yy, nh, ns_, col = 0, 0, 0, 0
        local lastKind
        for _, e in ipairs(nodes) do
            if e.kind ~= lastKind then
                if col == 1 then yy = yy - 26 end
                col = 0
                nh = nh + 1
                local h = Head(nh)
                h:ClearAllPoints()
                local top = yy - (nh > 1 and 6 or 0)
                h:SetPoint("TOPLEFT", 0, top - 4)
                h:SetText(GP:KindName(e.kind):upper())
                h:Show()
                h.all:ClearAllPoints()
                h.all:SetPoint("TOPLEFT", PAGE_W - 30 - 84 - 8, top)   -- inside the list, not above its top
                h.all.kind, h.all.entries = e.kind, {}
                h.all:Show()
                yy = top - 24
                lastKind = e.kind
            end
            local hl = heads[nh].all.entries
            hl[#hl + 1] = e
            ns_ = ns_ + 1
            local sw = Switch(ns_)
            sw.entry = e
            sw:ClearAllPoints()
            sw:SetPoint("TOPLEFT", col == 0 and 0 or COL2 - 10, yy)
            if e.skip then
                sw.label:SetText(L["|cff8a8070%s (%d) - skipped|r"]:format(e.name, e.count))
            else
                sw.label:SetText(L["%s |cff8a8070(%d)|r"]:format(e.name, e.count) .. GP:SkillTag(e.name, e.kind))
            end
            T.ClickableLabel(sw, sw.label)
            sw:SetOn(not e.skip and picked[e.kind] and picked[e.kind][e.name] or false)
            sw:Show()
            sw.label:Show()
            if col == 1 then yy = yy - 26 end
            col = 1 - col
        end
        if col == 1 then yy = yy - 26 end
        for i = 1, nh do
            local b = heads[i].all
            b.allOn = true
            for _, e in ipairs(b.entries) do
                if not e.skip and not (picked[b.kind] and picked[b.kind][e.name]) then b.allOn = false end
            end
            b:SetText(b.allOn and L["Clear all"] or L["Select all"])
        end
        for i = nh + 1, #heads do heads[i]:Hide(); heads[i].all:Hide(); heads[i].all.kind = nil end
        for i = ns_ + 1, #switches do switches[i]:Hide(); switches[i].label:Hide(); switches[i].entry = nil end
        scroll:SetContent(PAGE_W - 30, math.max(1, -yy), true)

        if not GP:HasNodeSource() then
            note:SetText(L["Gatherline needs GatherMate2 or GatherLite, where the herb and ore nodes come from. Install one from CurseForge, then /reload."])
        elseif not newZone then
            note:SetText(L["Pick a zone above, or click My zone for the one you're in."])
        elseif #nodes == 0 then
            note:SetText(L["%s has no nodes in %s yet. Gather there, then come back."]:format(GP:SourceNames(), GP:MapName(newZone)))
        else
            note:SetText(L[""])
        end

        local any = GP:AnyPicked(picked)
        local kinds = {}
        for kind, names in pairs(picked) do if next(names) then kinds[kind] = names end end
        -- start the name with the zone, and follow a zone change while only that's there
        if not editing and newZone ~= prefixZone then
            if OnlyPrefix(name:GetText(), prefixZone) then name:SetText(Prefix(newZone)) end
            prefixZone = newZone
        end
        if newZone then
            hint:SetText(any and GP:RouteName(newZone, kinds) or L["(made from what you pick)"])
        else
            hint:SetText(L["Name (made from what you pick)"])
        end
        ShowHint()
        make:SetDisabled(not any or GP:Busy())
        make:SetText(GP:Busy() and L["Working..."] or editing and L["Save changes"] or L["Make route"])
        cancel:SetShown(editing ~= nil)
    end)
end

---------------------------------------------------------------------------
-- Taboo areas tab: the areas in a zone, Draw a taboo area, Delete
---------------------------------------------------------------------------
local tabooZone   -- the map whose taboo areas are listed
local TABOO_ROW = 30

local function TabooZoneChoices()
    local seen, list = {}, {}
    local function Add(m) if m and not seen[m] then seen[m] = true; list[#list + 1] = m end end
    for _, m in ipairs(GP:GatherZones()) do Add(m) end
    for m in pairs(GP.db.taboos) do Add(m) end
    for _, m in ipairs(GP:RouteZones()) do Add(m) end
    Add(GP:PlayerMap())
    table.sort(list, function(a, b) return GP:MapName(a) < GP:MapName(b) end)
    return list
end

-- About how big an area is, in yards across and down
local function AreaSize(mapID, xy)
    local w, h = GP:MapYards(mapID)
    w, h = w or 1500, h or 1000
    local x1, y1, x2, y2 = 1, 1, 0, 0
    for k = 1, #xy, 2 do
        x1, x2 = math.min(x1, xy[k]), math.max(x2, xy[k])
        y1, y2 = math.min(y1, xy[k + 1]), math.max(y2, xy[k + 1])
    end
    return math.floor((x2 - x1) * w + 0.5), math.floor((y2 - y1) * h + 0.5)
end

local function BuildTaboo(p)
    T.RowLabel(p, "Zone", 0, 0)
    local zone = T.Dropdown(p, 300, {}, function(k) return k and GP:MapName(k) or "Pick a zone" end,
        function() return tabooZone end, function(k) tabooZone = k; GP:RefreshConfig() end)
    zone:SetPoint("TOPLEFT", DROP_X, 0)
    zone.menuScroll = 300
    refs.tabooZone = zone
    local here = FlatButton(p, "My zone", 90)
    here:SetPoint("LEFT", zone, "RIGHT", 8, 0)
    here:SetScript("OnClick", function()
        tabooZone = GP:PlayerMap()
        GP:RefreshConfig()
    end)
    T.Tooltip(here, "My zone", "Pick the zone you're in.")
    refs.tabooMyZone = here

    T.Note(p, "A no-go area is a part of a zone your routes stay out of, like the mountains in Eastern Plaguelands. No node inside it is used, and the route's line goes round it. Draw one on the world map: the routes in that zone are then worked out again.", 0, -34, PAGE_W)

    local draw = FlatButton(p, "Draw a no-go area", 180, 24)
    draw:SetPoint("TOPLEFT", 0, -92)
    draw:SetScript("OnClick", function(self)
        if self.disabled then return end
        GP:StartTaboo(tabooZone)
    end)
    T.Tooltip(draw, "Draw a no-go area", "Opens the world map on this zone. Left-click for each corner of the area, right-click to take the last one back, then click Finish at the top of the map.")
    T.Disabler(draw, { draw })
    refs.tabooDraw = draw

    local show = T.LabeledSwitch(p, "Show on the world map", COL2, -96)
    show:SetScript("OnClick", function(self)
        GP.db.tabooShow = not self:IsOn()
        GP:Changed()
    end)
    T.Tooltip(show, "Show on the world map", "Draw the no-go areas on the world map, red and hatched. They're always shown while you're drawing one.")
    refs.tabooShow = show

    local LIST_Y = -130
    local holder = CreateFrame("Frame", nil, p)
    holder:SetPoint("TOPLEFT", 0, LIST_Y)
    holder:SetSize(PAGE_W, BODY_H + LIST_Y)
    T.Fill(holder, C.card)
    T.Border(holder, C.line)
    local inner = CreateFrame("Frame", nil, holder)
    inner:SetPoint("TOPLEFT", 10, -8)
    inner:SetPoint("BOTTOMRIGHT", -4, 8)
    local scroll = T.ScrollArea(inner, BODY_H + LIST_Y - 16)
    local list = scroll.child
    local empty = T.Note(holder, "", 12, -12, PAGE_W - 24)
    refs.tabooEmpty = empty
    local rows = {}
    refs.tabooRows = rows

    local function Row(i)
        if rows[i] then return rows[i] end
        local r = CreateFrame("Frame", nil, list)
        r:SetSize(PAGE_W - 30, TABOO_ROW - 4)
        r.text = Text(r, "", "GameFontHighlight")
        r.text:SetPoint("LEFT", 4, 0)
        r.del = FlatButton(r, "Delete", 80, 20)
        r.del:SetPoint("RIGHT", 0, 0)
        r.del:SetScript("OnClick", function(self)
            local m, idx = self.mapID, self.index
            if not (m and idx) then return end
            GP:Confirm(L["Delete no-go area %d in |cffffd100%s|r? Your routes there are worked out again."]:format(
                idx, GP:MapName(m)), "Delete", function() GP:DeleteTaboo(m, idx) end)
        end)
        T.Tooltip(r.del, "Delete", "Delete this no-go area. The routes in this zone are worked out again without it.")
        r.view = FlatButton(r, "Show", 80, 20)
        r.view:SetPoint("RIGHT", r.del, "LEFT", -8, 0)
        r.view:SetScript("OnClick", function(self)
            if not self.mapID then return end
            if GP.config then GP.config:Hide() end
            if OpenWorldMap then pcall(OpenWorldMap, self.mapID) end
        end)
        T.Tooltip(r.view, "Show", "Open the world map on this zone.")
        rows[i] = r
        return r
    end

    AddRefresher(function()
        if not tabooZone then tabooZone = GP:PlayerMap() end
        zone.keys = TabooZoneChoices()
        zone:Refresh()
        show:SetOn(GP.db.tabooShow)
        draw:SetDisabled(not tabooZone)
        draw:SetText(GP.drawing and GP.drawing.mapID == tabooZone and L["Keep drawing"] or L["Draw a no-go area"])
        local areas = tabooZone and GP:Taboos(tabooZone) or {}
        for i, xy in ipairs(areas) do
            local r = Row(i)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, -(i - 1) * TABOO_ROW)
            local aw, ah = AreaSize(tabooZone, xy)
            r.text:SetText(L["Area %d  |cff8a8070-  %d corners, about %d x %d yards|r"]:format(i, #xy / 2, aw, ah))
            r.del.mapID, r.del.index = tabooZone, i
            r.view.mapID = tabooZone
            r:Show()
        end
        for i = #areas + 1, #rows do rows[i]:Hide(); rows[i].del.index = nil end
        scroll:SetContent(PAGE_W - 30, math.max(1, #areas * TABOO_ROW), true)
        if not tabooZone then
            empty:SetText(L["Pick a zone above, or click My zone for the one you're in."])
        elseif #areas == 0 then
            empty:SetText(L["No no-go areas in %s yet. Click Draw a no-go area."]:format(GP:MapName(tabooZone)))
        else
            empty:SetText(L[""])
        end
    end)
end

-- Opens the Taboo areas tab on this zone (after drawing or cancelling)
function GP:TabooTabInWindow(mapID)
    tabooZone = mapID
    self:OpenConfig("taboo")
end

---------------------------------------------------------------------------
-- Display tab
---------------------------------------------------------------------------
local function Setting(parent, text, x, y, key, tip, after)
    local sw = T.LabeledSwitch(parent, text, x, y)
    sw:SetScript("OnClick", function(self)
        GP.db[key] = not self:IsOn()
        if after then after() end
        GP:Changed()
    end)
    if tip then T.Tooltip(sw, text, tip) end
    AddRefresher(function() sw:SetOn(GP.db[key]) end)
    return sw
end

local function Slider(parent, text, x, y, key, suffix, tip)
    local r = GP.RANGES[key]
    local s = T.Slider(parent, text, x, y, 244,
        function() return GP.db[key] end,
        function(v) GP.db[key] = v; GP:Changed() end,
        r[1], r[2], suffix)
    if tip then T.Tooltip(s, text, tip) end
    AddRefresher(s.Refresh)
    return s
end

-- "Each route's own color" and, under it, the one color for every line on
-- that map ("world" or "minimap"), greyed out while routes keep their own
local function LineColor(parent, x, y, where, place)
    local key = where .. "RouteColor"
    local sw = Setting(parent, "Each route's own color", x, y, key,
        where == "world" and "Draw each route on the world map in the color it has on the Routes tab. Turn this off to draw every route there in the color below."
            or "Draw each route on the minimap in the color it has on the Routes tab. Turn this off to draw every route there in the color below.")
    local swatch = Swatch(parent,
        function() return GP.db[where .. "Color"] end,
        function(_, r, g, b) GP:SetLineColor(where, r, g, b) end,
        "Line color", where == "world" and "Click to pick the color of every route's line on the world map. Turn off Each route's own color to use it."
            or "Click to pick the color of every route's line on the minimap. Turn off Each route's own color to use it.")
    swatch:SetPoint("TOPLEFT", x, y - 28)
    local label = Text(parent, "Line color", "GameFontHighlight")
    label:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
    AddRefresher(function()
        swatch:Paint(GP.db[where .. "Color"])
        swatch:SetDisabled(GP.db[key])
        label:SetAlpha(GP.db[key] and 0.4 or 1)
    end)
    return sw, swatch
end

local function BuildDisplay(p)
    local card = Card(p, "Lines", 0, 0, PAGE_W, 214)
    refs.worldSwitch = Setting(card, "On the world map", 12, -30, "worldMap",
        "Draw the routes on the world map, on their zone's map (and thinner on the continent's).")
    refs.minimapSwitch = Setting(card, "On the minimap", COL2, -30, "minimap",
        "Draw the routes on the minimap, round you.")
    Slider(card, "World map line width", 12, -64, "worldWidth")
    Slider(card, "Minimap line width", COL2, -64, "minimapWidth")
    refs.worldAlpha = Slider(card, "World map opacity", 12, -108, "worldAlpha", "%")
    refs.minimapAlpha = Slider(card, "Minimap opacity", COL2, -108, "minimapAlpha", "%")
    refs.worldRouteColor, refs.worldColor = LineColor(card, 12, -152, "world", "on the world map")
    refs.minimapRouteColor, refs.minimapColor = LineColor(card, COL2, -152, "minimap", "on the minimap")

    local card3 = Card(p, "Range circle", 0, -220, PAGE_W, 98)
    refs.rangeSwitch = Setting(card3, "On the minimap", 12, -30, "range",
        "A circle round you on the minimap, as far as Find Herbs and Find Minerals show nodes, so you can see how close you need to get. Set the yards below.")
    local swatch = Swatch(card3,
        function() return GP.db.rangeColor end,
        function(_, r, g, b) GP.db.rangeColor = { r, g, b }; GP:Changed() end,
        "Circle color", "Click to pick the range circle's color.")
    swatch:SetPoint("TOPLEFT", COL2, -30)
    local label = Text(card3, "Circle color", "GameFontHighlight")
    label:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
    AddRefresher(function() swatch:Paint(GP.db.rangeColor) end)
    refs.rangeColor = swatch
    refs.rangeYards = Slider(card3, "Circle radius", 12, -58, "rangeYards", " yards",
        "How far round you the circle is drawn. Find Herbs and Find Minerals show nodes about 100 yards away.")
    refs.rangeAlpha = Slider(card3, "Circle opacity", COL2, -58, "rangeAlpha", "%")

    local card2 = Card(p, "More", 0, -324, PAGE_W, 78)
    Setting(card2, "Add new nodes to routes", 12, -30, "autoAdd",
        "When GatherMate2 or GatherLite records a node you just found, it joins the routes in that zone that have its kind, where it adds the least walking.")
    Setting(card2, "Minimap button", COL2, -30, "minimapButton",
        "The Gatherline button on the minimap: left-click opens this window, right-click shows or hides the lines.",
        function() GP:UpdateMinimapButton() end)
    T.Note(card2, "Right-click the minimap button (or type /gl hide, /gl show) to hide every line for a while.",
        12, -56, PAGE_W - 24)

    local restore = FlatButton(p, "Restore defaults", 150, 22)
    restore:SetPoint("TOPLEFT", 0, -410)
    T.Tooltip(restore, "Restore defaults", "Put every setting on this tab back as it was to start. Your routes are kept.")
    restore:SetScript("OnClick", function()
        GP:Confirm(L["Put every setting on the Display tab back as it was to start? Your routes are kept."],
            "Restore", function() GP:RestoreDefaults() end)
    end)
    refs.restoreDefaults = restore
end

---------------------------------------------------------------------------
-- Tours tab: several routes one after the other, zone to zone
---------------------------------------------------------------------------
local TOUR_ROW, STAGE_ROW = 92, 26
local tourDraft, tourEditing   -- the tour being made or changed (nil: the list)

local function NewDraft(tour)
    tourEditing = tour
    tourDraft = {
        name = tour and tour.name or "",
        stages = tour and { unpack(tour.stages) } or {},
        laps = tour and tour.laps or 1,
        loop = tour and tour.loop or false,
    }
    GP:RefreshConfig()
end
function GP:EditTourInWindow(tour)
    self:OpenConfig("tours")
    NewDraft(tour)
end

local function BuildTours(p)
    -- the list
    local listView = CreateFrame("Frame", nil, p)
    listView:SetAllPoints(p)
    T.Note(listView, "Ride several routes one after the other: the laps of one, then Shortest Path Forever leads you to the next, in another zone too.", 0, 0, PAGE_W - 130)
    local make = FlatButton(listView, "New tour", 110)
    make:SetPoint("TOPRIGHT", 0, 0)
    make:SetScript("OnClick", function(self) if not self.disabled then NewDraft(nil) end end)
    T.Tooltip(make, "New tour", "Put routes you've made together into a tour.")
    T.Disabler(make, { make })
    refs.tourNew = make
    local holder = CreateFrame("Frame", nil, listView)
    holder:SetPoint("TOPLEFT", 0, -42)
    holder:SetSize(PAGE_W, BODY_H - 42)
    local scroll = T.ScrollArea(holder, BODY_H - 42)
    local empty = T.Note(listView, "", 0, -52, PAGE_W)
    refs.toursEmpty = empty
    local rows = {}
    refs.tourRows = rows
    local function Row(i)
        if rows[i] then return rows[i] end
        local r = CreateFrame("Frame", nil, scroll.child)
        r:SetSize(PAGE_W - 16, TOUR_ROW - 8)
        T.Fill(r, C.card)
        T.Border(r, C.line)
        r.name = Text(r, "", "GameFontHighlight")
        r.name:SetPoint("TOPLEFT", 16, -14)
        r.name:SetWidth(240)
        r.name:SetJustifyH("LEFT")
        r.info = Text(r, "", "GameFontDisableSmall")
        r.info:SetPoint("TOPLEFT", 16, -40)
        r.info:SetWidth(PAGE_W - 48)
        r.info:SetJustifyH("LEFT")
        r.info:SetWordWrap(true)
        local function Action(texture, title, tip, onClick)
            local b = T.IconButton(r, texture, 24)
            b:SetScript("OnClick", function(self)
                if self.disabled == true or not r.tour then return end
                onClick(r.tour)
            end)
            T.Disabler(b, { b })
            T.Tooltip(b, title, tip)
            return b
        end
        r.delete = Action("Interface\\Buttons\\UI-StopButton", "Delete", "Delete this tour (its routes stay).", function(tour)
            GP:Confirm(L["Delete the tour |cff3fd0a0%s|r? Its routes stay."]:format(tour.name), L["Delete"],
                function() GP:DeleteTour(tour) end)
        end)
        r.delete:SetPoint("TOPRIGHT", -10, -10)
        r.edit = Action("Interface\\Buttons\\UI-GuildButton-PublicNote-Up", "Edit",
            "Change this tour's routes, their order and laps.", function(tour) NewDraft(tour) end)
        r.edit:SetPoint("RIGHT", r.delete, "LEFT", -4, 0)
        r.ride = FlatButton(r, "Start", 72, 24)
        r.ride:SetPrimary(true)
        r.ride:SetPoint("RIGHT", r.edit, "LEFT", -8, 0)
        r.ride:SetScript("OnClick", function(self)
            if self.disabled or not r.tour then return end
            if GP:IsTouring(r.tour) then GP:StopNav() else GP:StartTour(r.tour) end
        end)
        T.Disabler(r.ride, { r.ride })
        T.Tooltip(r.ride, "Start / Stop", "Ride the tour: its route in your zone first if it has one, else its first; then on to the next with Shortest Path Forever, flights, boats and portals included.")
        refs.tourRide = refs.tourRide or {}
        refs.tourRide[i] = r.ride
        rows[i] = r
        return r
    end

    -- making or changing one
    local editView = CreateFrame("Frame", nil, p)
    editView:SetAllPoints(p)
    T.RowLabel(editView, "Name", 0, 0)
    local nameBox = T.EditBox(editView, 300)
    nameBox:SetPoint("TOPLEFT", DROP_X, 0)
    nameBox:SetScript("OnTextChanged", function(self, user) if user and tourDraft then tourDraft.name = self:GetText() end end)
    refs.tourName = nameBox
    local laps = T.Slider(editView, "Laps on each route", 0, -40, 244,
        function() return tourDraft and tourDraft.laps or 1 end,
        function(v) if tourDraft then tourDraft.laps = v end end,
        GP.TOUR_LAPS[1], GP.TOUR_LAPS[2], "", 1)
    AddRefresher(laps.Refresh)
    refs.tourLaps = laps
    local loop = T.LabeledSwitch(editView, "Start over at the end", COL2, -48)
    loop:SetScript("OnClick", function(self)
        if tourDraft then tourDraft.loop = not self:IsOn(); self:SetOn(tourDraft.loop) end
    end)
    T.Tooltip(loop, "Start over at the end", "After the last route, back to the first, until you stop.")
    refs.tourLoop = loop

    local STAGES_H = GP.TOUR_MAX_STAGES * STAGE_ROW + 40
    local card = Card(editView, "Routes, in the order you ride them", 0, -92, PAGE_W, STAGES_H)
    local stageNote = T.Note(card, "", 12, -34, PAGE_W - 24)
    local stageRows = {}
    refs.stageRows = stageRows
    local function Move(i, by)
        local s = tourDraft.stages
        local j = i + by
        if j < 1 or j > #s then return end
        s[i], s[j] = s[j], s[i]
        GP:RefreshConfig()
    end
    local function StageRow(i)
        if stageRows[i] then return stageRows[i] end
        local r = CreateFrame("Frame", nil, card)
        r:SetSize(PAGE_W - 24, STAGE_ROW)
        r:SetPoint("TOPLEFT", 12, -30 - (i - 1) * STAGE_ROW)
        r.text = Text(r, "", "GameFontHighlightSmall")
        r.text:SetPoint("LEFT", 0, 0)
        r.text:SetWidth(PAGE_W - 24 - 100)
        r.text:SetJustifyH("LEFT")
        local function Btn(texture, title, fn)
            local b = T.IconButton(r, texture, 22)
            b:SetScript("OnClick", function(self) if self.disabled ~= true then fn() end end)
            T.Disabler(b, { b })
            T.Tooltip(b, title)
            return b
        end
        r.remove = Btn("Interface\\Buttons\\UI-StopButton", "Take out", function()
            table.remove(tourDraft.stages, i); GP:RefreshConfig()
        end)
        r.remove:SetPoint("RIGHT", 0, 0)
        r.down = Btn("Interface\\Buttons\\Arrow-Down-Up", "Later", function() Move(i, 1) end)
        r.down:SetPoint("RIGHT", r.remove, "LEFT", -4, 0)
        r.up = Btn("Interface\\Buttons\\Arrow-Up-Up", "Earlier", function() Move(i, -1) end)
        r.up:SetPoint("RIGHT", r.down, "LEFT", -4, 0)
        stageRows[i] = r
        return r
    end

    local y = -92 - STAGES_H - 10
    local add = T.Dropdown(editView, 300, {}, function(k)
            local r = k and GP:RouteByID(k)
            return r and (r.name .. " |cff8a8070(" .. GP:MapName(r.mapID) .. ")|r") or L["Add a route..."]
        end,
        function() return nil end,
        function(k)
            if tourDraft and k and #tourDraft.stages < GP.TOUR_MAX_STAGES then
                table.insert(tourDraft.stages, k)
                GP:RefreshConfig()
            end
        end)
    add:SetPoint("TOPLEFT", 0, y)
    add.menuScroll = 300
    refs.tourAdd = add

    local save = FlatButton(editView, "Save tour", 130, 26)
    save:SetPrimary(true)
    save:SetPoint("TOPRIGHT", 0, y)
    save:SetScript("OnClick", function(self)
        if self.disabled or not tourDraft then return end
        if GP:SaveTour(tourDraft, tourEditing) then tourDraft, tourEditing = nil, nil; GP:RefreshConfig() end
    end)
    T.Disabler(save, { save })
    refs.tourSave = save
    local cancel = FlatButton(editView, "Cancel", 100, 26)
    cancel:SetPoint("RIGHT", save, "LEFT", -8, 0)
    cancel:SetScript("OnClick", function() tourDraft, tourEditing = nil, nil; GP:RefreshConfig() end)
    refs.tourCancel = cancel

    AddRefresher(function()
        if tourEditing then
            local found = false
            for _, t in ipairs(GP:Tours()) do if t == tourEditing then found = true end end
            if not found then tourDraft, tourEditing = nil, nil end
        end
        listView:SetShown(tourDraft == nil)
        editView:SetShown(tourDraft ~= nil)
        if tourDraft then
            if not nameBox:HasFocus() then nameBox:SetText(tourDraft.name) end
            loop:SetOn(tourDraft.loop)
            -- routes that are gone drop out
            local s = {}
            for _, id in ipairs(tourDraft.stages) do if GP:RouteByID(id) then s[#s + 1] = id end end
            tourDraft.stages = s
            for i, id in ipairs(s) do
                local row = StageRow(i)
                local r = GP:RouteByID(id)
                row.text:SetText(("%d.  %s  |cff8a8070%s|r"):format(i, r.name, GP:MapName(r.mapID)))
                row.up:SetDisabled(i == 1)
                row.down:SetDisabled(i == #s)
                row:Show()
            end
            for i = #s + 1, #stageRows do stageRows[i]:Hide() end
            stageNote:SetText(#s == 0 and L["No routes yet. Add them below, in the order you want to ride them."] or L[""])
            local inTour, keys = {}, {}
            for _, id in ipairs(s) do inTour[id] = true end
            local routes = {}
            for _, r in ipairs(GP.db.routes) do
                if not inTour[r.id] and not r.working and GP:NodeCount(r) >= 2 then routes[#routes + 1] = r end
            end
            table.sort(routes, function(a, b)
                local ma, mb = GP:MapName(a.mapID), GP:MapName(b.mapID)
                if ma ~= mb then return ma < mb end
                return a.name < b.name
            end)
            for _, r in ipairs(routes) do keys[#keys + 1] = r.id end
            add.keys = keys
            add:Refresh()
            add:SetDisabled(#keys == 0 or #s >= GP.TOUR_MAX_STAGES)
            save:SetDisabled(#s < 2)
            return
        end
        local tours = GP:Tours()
        for i, tour in ipairs(tours) do
            local r = Row(i)
            r.tour = tour
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, -(i - 1) * TOUR_ROW)
            r:Show()
            r.name:SetText(tour.name)
            local dot = "  |cff4a4f58\226\128\162|r  "
            local parts = { L["%d routes"]:format(#tour.stages),
                tour.laps == 1 and L["1 lap each"] or L["%d laps each"]:format(tour.laps),
                L["about %s riding"]:format(GP.FormatClock(GP:TourTime(tour))) }
            if tour.loop then parts[#parts + 1] = L["starts over"] end
            local line2 = table.concat(parts, dot)
            if GP:IsTouring(tour) and GP:NavStatus() then line2 = "|cff" .. T.ACCENT_HEX .. GP:NavStatus() .. "|r" end
            r.info:SetText(GP:TourLine(tour) .. "\n" .. line2)
            local riding = GP:IsTouring(tour)
            r.ride:SetText(riding and L["Stop"] or L["Start"])
            r.ride:SetDisabled(not riding and (#tour.stages < 2 or not GP:CanNavigate()))
        end
        for i = #tours + 1, #rows do rows[i]:Hide(); rows[i].tour = nil end
        scroll:SetContent(PAGE_W - 16, math.max(1, #tours * TOUR_ROW), true)
        local enough = 0
        for _, r in ipairs(GP.db.routes) do if not r.working and GP:NodeCount(r) >= 2 then enough = enough + 1 end end
        if #tours == 0 then
            empty:SetText(enough >= 2 and L["No tours yet. Click New tour and put two or more of your routes together."]
                or L["A tour is made of routes. Make at least two routes first (New route), then come back."])
        else
            empty:SetText(L[""])
        end
        make:SetDisabled(enough < 2)
    end)
end

---------------------------------------------------------------------------
-- HUD tab: the gathering HUD's parts, look and place
---------------------------------------------------------------------------
local function BuildHud(p)
    local function HudSwitch(parent, text, x, y, key, tip, invert)
        local sw = T.LabeledSwitch(parent, text, x, y)
        sw:SetScript("OnClick", function(self)
            GP:HudSettings()[key] = not self:IsOn()
            GP:UpdateHud(true)
            GP:RefreshConfig()
        end)
        T.Tooltip(sw, text, tip)
        AddRefresher(function() sw:SetOn(GP:HudSettings()[key]) end)
        return sw
    end
    local card = Card(p, "Show while riding", 0, 0, PAGE_W, 124)
    refs.hudCompass = HudSwitch(card, "Compass band", 12, -30, "compass",
        "A band at the top: the way you face, the stop you head for as a diamond and the next ones numbered, empty ones hollow. Under it the stop's name, how far, which way, and the lap so far. When Shortest Path Forever shows its own compass, the band moves under it; switch one of them off (Shortest Path's: \"Show the compass\" in its settings) if one is enough.")
    refs.hudLens = HudSwitch(card, "Ground lens", 12, -60, "lens",
        "A tilted disc round you that turns with you: the route's line along the ground for the next few yards and the stops on it.")
    refs.hudCard = HudSwitch(card, "Lap card", 12, -90, "card",
        "A card at the bottom: the stop you head for (how far, how many seconds), a dot for every stop of the lap, the lap time against your best, nodes and gold an hour.")
    refs.hudCombat = HudSwitch(card, "Show in combat", COL2, -30, "combat",
        "Off: the HUD steps aside while you fight.")

    local card2 = Card(p, "Look", 0, -130, PAGE_W, 112)
    local function HudSlider(text, x, y, key, suffix, step)
        local r = GP.HUD_RANGES[key]
        local sl = T.Slider(card2, text, x, y, 244,
            function() return GP:HudSettings()[key] end,
            function(v) GP:HudSettings()[key] = v; GP:UpdateHud() end,
            r[1], r[2], suffix, step)
        AddRefresher(sl.Refresh)
        return sl
    end
    refs.hudScale = HudSlider("Size", 12, -30, "scale", "%", 5)
    refs.hudAlpha = HudSlider("Opacity", COL2, -30, "alpha", "%", 5)
    refs.hudRange = HudSlider("Lens reach", 12, -74, "lensRange", " yards", 10)
    T.Tooltip(refs.hudRange, "Lens reach", "How far round you the ground lens shows the route.")

    local card3 = Card(p, "Place", 0, -248, PAGE_W, 112)
    refs.hudMove = T.LabeledSwitch(card3, "Move the parts", 12, -30)
    refs.hudMove:SetScript("OnClick", function(self)
        local h = GP:HudSettings()
        h.locked = self:IsOn()
        if not h.locked and not GP.hudPreview then GP:SetHudPreview(true) end
        GP:UpdateHud(true)
        GP:RefreshConfig()
    end)
    T.Tooltip(refs.hudMove, "Move the parts", "Drag each part where you like (they show tinted). Switch it off again to fix them and let clicks through.")
    AddRefresher(function() refs.hudMove:SetOn(not GP:HudSettings().locked) end)
    local preview = FlatButton(card3, "Preview", 120, 24)
    preview:SetPoint("TOPLEFT", 12, -70)
    preview:SetScript("OnClick", function()
        GP:SetHudPreview(not GP.hudPreview)
        GP:RefreshConfig()
    end)
    T.Tooltip(preview, "Preview", "Shows the HUD with made-up stops round you, to try it out and place it without riding.")
    AddRefresher(function()
        preview:SetText(GP.hudPreview and L["End preview"] or L["Preview"])
        preview:SetPrimary(GP.hudPreview)
    end)
    refs.hudPreview = preview
    local reset = FlatButton(card3, "Back to their places", 170, 24)
    reset:SetPoint("LEFT", preview, "RIGHT", 8, 0)
    reset:SetScript("OnClick", function()
        GP:HudSettings().pos = {}
        GP:UpdateHud(true)
    end)
    T.Tooltip(reset, "Back to their places", "Puts every part back where it started.")
    refs.hudReset = reset
    T.Note(card3, "The HUD shows while you ride a route or a tour. /gl hud switches it all off and on.", COL2, -30, PAGE_W - COL2 - 12)
end

---------------------------------------------------------------------------
-- Riding tab: how Start leads you round (with Shortest Path Forever)
---------------------------------------------------------------------------
local LABELS = {
    number = "Number: Stop 3/42",
    nodes = "What's there: Copper Vein ×2",
    both = "Both: 3/42: Copper Vein ×2",
}
local function BuildRiding(p)
    local card = Card(p, "Moving on", 0, 0, PAGE_W, 112)
    refs.navReach = T.Slider(card, "Next stop when this close", 12, -30, 244,
        function() return GP.db.navReach end,
        function(v) GP.db.navReach = v end,
        GP.RANGES.navReach[1], GP.RANGES.navReach[2], " yards", 5)
    T.Tooltip(refs.navReach, "Next stop when this close",
        "How close you need to get to a stop before the arrow moves on to the next one. Shortest Path Forever on its own moves on at 15 yards; more than that and Gatherline moves you on sooner, so you don't have to ride right up to it. Riding past a stop toward a later one moves on too.")
    AddRefresher(refs.navReach.Refresh)
    refs.navAhead = T.Slider(card, "Stops shown ahead", COL2, -30, 244,
        function() return GP.db.navAhead end,
        function(v) GP.db.navAhead = v end,
        GP.RANGES.navAhead[1], GP.RANGES.navAhead[2], "", 1)
    T.Tooltip(refs.navAhead, "Stops shown ahead",
        "How many stops Shortest Path Forever gets at a time: its numbered pins on the map, and the \"Stop 2 of 10\" in its tracker counts these. More are handed over as you go.")
    AddRefresher(refs.navAhead.Refresh)
    refs.navLaps = T.Slider(card, "Laps", 12, -74, 244,
        function() return GP.db.navLaps end,
        function(v) GP.db.navLaps = v end,
        GP.RANGES.navLaps[1], GP.RANGES.navLaps[2], "", 1, nil, "Until I stop")
    T.Tooltip(refs.navLaps, "Laps", "How many laps Start rides before it stops by itself.")
    AddRefresher(refs.navLaps.Refresh)

    local card2 = Card(p, "Stop names", 0, -118, PAGE_W, 96)
    T.RowLabel(card2, "Call stops by", 12, -32)
    local drop = T.Dropdown(card2, 300, { "number", "nodes", "both" }, function(k) return LABELS[k] end,
        function() return GP.db.navLabel end,
        function(k) GP.db.navLabel = k; GP:RefreshConfig() end)
    drop:SetPoint("TOPLEFT", 110, -30)
    refs.navLabel = drop
    AddRefresher(drop.Refresh)
    T.Note(card2, "What the arrow and the tracker call each stop. \"What's there\" names the nodes the stop takes you past (as GatherMate2 or GatherLite names them); a stop with none keeps its number. Changes show from the next stops handed over.", 12, -60, PAGE_W - 24)

    local card4 = Card(p, "On the map while you ride", 0, -220, PAGE_W, 90)
    refs.arrowsSwitch = Setting(card4, "Show arrows", 12, -30, "arrows",
        "Small arrows along every route's line, on the world map and the minimap, showing which way round to ride the loop.")
    refs.arrowsReverse = Setting(card4, "Reverse direction", COL2, -30, "arrowsReverse",
        "Turn the arrows round, to ride every loop the other way.")
    AddRefresher(function() refs.arrowsReverse:SetAlpha(GP.db.arrows and 1 or 0.4) end)
    refs.joinSwitch = Setting(card4, "Line to the route", 12, -60, "joinLine",
        "A dashed line on the minimap from you to the nearest point of a route showing in your zone, so you know where to join it. Gone once you're on the route.")

    local card5 = Card(p, "Smart laps", 0, -316, PAGE_W, 90)
    refs.navRespawn = T.Slider(card5, "Skip gathered stops for", 12, -30, 244,
        function() return GP.db.navRespawn end,
        function(v) GP.db.navRespawn = v end,
        GP.RANGES.navRespawn[1], GP.RANGES.navRespawn[2], " min", 1, nil, "Never")
    T.Tooltip(refs.navRespawn, "Skip gathered stops for",
        "When you gather a node, Gatherline notes where. A stop whose nodes you all gathered within this many minutes is left out of the next laps, until they can be back. Nodes someone else took aren't known, so those stops stay in.")
    AddRefresher(refs.navRespawn.Refresh)
    T.Note(card5, "Each lap counts towards the route's statistics: best and average lap, nodes an hour, and with Auctionator what it's worth an hour. /gl stats shows them.", COL2, -30, PAGE_W - COL2 - 12)
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- About: what Gatherline needs and whether it's there, bringing routes over,
-- and what it's made from
---------------------------------------------------------------------------
local function StatusLine(parent, y, name, what)
    local dot = parent:CreateTexture(nil, "ARTWORK")
    dot:SetSize(8, 8)
    dot:SetPoint("TOPLEFT", 14, y - 4)
    local title = Text(parent, name, "GameFontHighlight")
    title:SetPoint("TOPLEFT", 30, y)
    local state = Text(parent, "", "GameFontHighlight")
    state:SetPoint("TOPRIGHT", parent, "TOPLEFT", PAGE_W - 14, y)
    state:SetJustifyH("RIGHT")
    local note = T.Note(parent, what, 30, y - 18, PAGE_W - 60)
    return function(ok, text)
        local c = ok and C.accent or C.danger
        dot:SetColorTexture(c[1], c[2], c[3], 1)
        state:SetText(text)
        state:SetTextColor(c[1], c[2], c[3])
    end, note
end

local function BuildAbout(p)
    local card = Card(p, "Needs", 0, 0, PAGE_W, 196)
    local gm = StatusLine(card, -32, "GatherMate2 or GatherLite", "Where the herb and ore nodes come from: either, or both (a node both know counts once). Without one there's nothing to make routes of.")
    local spf = StatusLine(card, -82, "Shortest Path Forever", "The guidance (arrow and tracker) for Start, and the walking maps routes are measured on. It needs ForeverCore.")
    local maps = StatusLine(card, -132, "Walking map here", "Shortest Path's walking maps for the continent you're on: routes here follow the ground.")
    AddRefresher(function()
        local has = GP:HasNodeSource()
        gm(has, has and GP:SourceNames() or L["missing"])
        local hasSPF = GP:CanNavigate()
        spf(hasSPF, hasSPF and L["found"] or L["missing"])
        local mapID = GP:PlayerMap()
        local ok = GP.Walk and mapID and GP.Walk.Ready(mapID)
        maps(ok and true or false, ok and L["yes"] or L["no"])
    end)
    refs.aboutStatus = { gm = gm, spf = spf, maps = maps }

    local card2 = Card(p, "Routes from GatherPath", 0, -202, PAGE_W, 96)
    local note = T.Note(card2, "", 12, -30, PAGE_W - 180)
    local bring = FlatButton(card2, "Bring routes over", 150, 24)
    bring:SetPoint("TOPRIGHT", -12, -30)
    bring:SetScript("OnClick", function(self)
        if self.disabled == true then return end
        GP:ImportRoutes()
    end)
    T.Disabler(bring, { bring })
    T.Tooltip(bring, "Bring routes over", "Copies the routes, no-go areas and skip list of GatherPath Plus or GatherPath Forever into Gatherline. Routes already here (same zone and name) are left alone.")
    refs.importButton = bring
    AddRefresher(function()
        local src, from = GP:ImportSource()
        bring:SetDisabled(not src)
        note:SetText(src and L["%s is switched on and has %d routes. Bring them over, then switch it off: both drawing the same routes is just clutter."]:format(from, #src.routes)
            or L["To bring over routes from GatherPath Plus or GatherPath Forever, switch that addon on for one login, then come back here. (It happens by itself the first time, when Gatherline has no routes yet.)"])
    end)

    local card3 = Card(p, "Made from", 0, -304, PAGE_W, 130)
    T.Note(card3, "Gatherline grew out of GatherPath Forever by severd8 (MIT licence), whose route solver it still uses. The walking search in Routing/ is Shortest Path Forever's, by cjber (GPL-3.0), and its walking maps come from Shortest Path Forever itself. So Gatherline is under GPL-3.0 too. The skill each herb and ore needs comes from GatherLite by Wuild (MIT licence).", 12, -30, PAGE_W - 24)
end

local TABS = {
    { key = "routes",  group = "Routes", label = "My routes", sub = "Your gathering loops, zone by zone.", icon = "Interface\\Icons\\INV_Misc_Map_01", build = BuildRoutes },
    { key = "tours",   label = "Tours", sub = "Several routes one after the other, zone to zone.", icon = "Interface\\Icons\\INV_Misc_Map02", build = BuildTours },
    { key = "new",     label = "New route", sub = "Pick a zone and what to gather; Gatherline finds the loop.", icon = "Interface\\Icons\\INV_Pick_02", build = BuildNew },
    { key = "riding",  group = "On the way", label = "Guidance", sub = "How Start leads you round, with Shortest Path Forever.", icon = "Interface\\Icons\\Ability_Mount_RidingHorse", build = BuildRiding },
    { key = "hud",     label = "Gathering HUD", sub = "What you see on screen while you ride: compass, ground lens, lap card.", icon = "Interface\\Icons\\INV_Misc_Spyglass_02", build = BuildHud },
    { key = "display", label = "Map & lines", sub = "How routes are drawn on the world map and the minimap.", icon = "Interface\\Icons\\INV_Misc_Spyglass_03", build = BuildDisplay },
    { key = "taboo",   label = "No-go areas", sub = "Places a route must keep out of.", icon = "Interface\\Icons\\INV_Misc_Bone_Skull_01", build = BuildTaboo },
    { key = "about",   group = "Gatherline", label = "About", sub = "What Gatherline needs, and where it comes from.", icon = "Interface\\Icons\\INV_Misc_Note_01", build = BuildAbout },
}
GP.CONFIG_TABS = TABS

function GP:BuildConfig()
    if self.config then return self.config end
    self.config = T.Window({
        name = "GatherlineConfig",
        height = WINDOW_H,
        tabs = TABS,
        hint = "/gl opens this window  ·  /gl help lists the commands",
        version = function()
            local get = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
            local v = get and get(ADDON, "Version")
            if v and v:find("@") then return nil end
            return v and v:gsub("^v", "")
        end,
        onShow = function()
            if GP.config and GP.config.currentTab == "new" then ResetNew() end
            GP:RefreshConfig()
        end,
        onTab = function(key)
            if key == "new" then ResetNew() end
            GP:RefreshConfig()
        end,
    })
    return self.config
end

-- Opens New route blank but on this zone (the Routes tab's New route button)
function GP:NewRouteInWindow(mapID)
    self:OpenConfig("new")
    newZone = mapID
    self:RefreshConfig()
end

-- Opens New route filled in from this route; Save changes then changes it
function GP:EditRouteInWindow(route)
    self:OpenConfig("new")
    EditInWindow(route)
    self:RefreshConfig()
end

function GP:RefreshConfig()
    if not (self.config and self.config:IsShown()) then return end
    for _, fn in ipairs(refreshers) do fn() end
end

function GP:OpenConfig(tab)
    local win = self:BuildConfig()
    if tab then
        win:Show()
        win:ShowTab(tab)
    elseif win:IsShown() then
        win:Hide()
    else
        win:Show()
    end
    self:RefreshConfig()
end
