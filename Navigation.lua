-- Gatherline: riding a route with Shortest Path Forever's guidance.
--
-- Start on a route hands its stops to Shortest Path Forever through its public
-- API (ShortestPathForever.API.NavigateRoute), a few at a time: its arrow, the
-- objective tracker and numbered pins lead you round, and from anywhere else
-- (another zone, another continent) it plans the way to the route first, with
-- flights, boats and portals.
--
-- The loop is a sequence of positions p = 1, 2, 3 ... The route's stop at p is
-- counted from the stop you join at, in the direction the arrows point; p goes
-- on past the end of a lap into the next one. Shortest Path gets NAV_AHEAD
-- positions from the one you're heading for; when you head for the last of
-- them, they're sent again from there with the next ones behind. Riding past
-- a stop (close to a later one) skips the ones before it, so you aren't sent
-- back for a stop you cut.
--
-- Smart laps: a stop whose nodes you all gathered in the last db.navRespawn
-- minutes (Session.lua notes where you gather) is left out of what Shortest
-- Path gets, so a lap doesn't take you past nodes that can't be back yet.

local ADDON, ns = ...
local L = ns.L
local GP = ns.GP
local Print = GP.Print
local floor, sqrt, huge, min, max = math.floor, math.sqrt, math.huge, math.min, math.max

local OWNER = ADDON
GP.NAV_AHEAD = nil       -- stops handed to Shortest Path at once: db.navAhead unless set here (tests)
GP.NAV_CATCH = 40        -- yards: this close to a later stop and the stops before it count as done
GP.NAV_CATCH_AHEAD = 6   -- how many stops ahead that looks
GP.NAV_SAMPLES = 8       -- route stops asked about (travel time) when you aren't in the route's zone
GP.NAV_TICK = 0.25       -- seconds between checks
GP.NAV_GIVE_UP = 8       -- seconds Shortest Path may turn the stops down (outside combat) before we stop

-- Shortest Path Forever's public API, if it's there and a version we know
local function API()
    local spf = _G.ShortestPathForever
    local api = type(spf) == "table" and spf.API
    if type(api) ~= "table" then return nil end
    if api.version ~= 1 and api.version ~= 2 then return nil end
    if type(api.NavigateRoute) ~= "function" or type(api.CurrentStop) ~= "function"
        or type(api.Ended) ~= "function" or type(api.Cancel) ~= "function" then
        return nil
    end
    return api
end
GP.NavAPI = API

function GP:CanNavigate() return API() ~= nil end

-- What's being ridden: nil, or
-- { route, points (the route's list when we started), n, start, dir, laps,
--   last (final position), first/count (the positions Shortest Path has),
--   pos (heading for), pending (a position to send again), refusedAt, began, lapBegan }
local nav

function GP:NavRoute() return nav and nav.route end
function GP:IsNavigating(route) return nav ~= nil and (route == nil or nav.route == route) end

local function Yards(mapID)
    local w, h = GP:MapYards(mapID)
    return w or 1500, h or 1000
end

local function InCombat() return InCombatLockdown and InCombatLockdown() end

-- The route's stop at position p, and the lap it's in
local function Index(p)
    return (nav.start - 1 + nav.dir * (p - 1)) % nav.n + 1
end
local function Lap(p) return floor((p - 1) / nav.n) + 1 end

-- What's at each stop of a route: the nodes it takes you past (each node
-- counts for the stop nearest it, if within the route's pass distance + 40
-- yards). labels[i] = "Kupfervorkommen ×2, Zinnader", nil for a stop with none
-- (a bend round a taboo area).
GP.NAV_LABEL_NAMES = 3   -- names shown at most; more become "+N"
function GP:StopLabels(route)
    local mapID, pts, n = route.mapID, route.points, self:NodeCount(route)
    local w, h = Yards(mapID)
    local reach = (route.sight or 0) + 40
    local counts, members, kindAt = {}, {}, {}
    for kind, names in pairs(route.kinds or {}) do
        self:EachNode(mapID, kind, function(x, y, name)
            if not names[name] or self:IsSkipped(name) or self:InTaboo(mapID, x, y) then return end
            local best, bi = reach * reach, nil
            for i = 1, n do
                local dx, dy = (pts[2 * i - 1] - x) * w, (pts[2 * i] - y) * h
                local d = dx * dx + dy * dy
                if d <= best then best, bi = d, i end
            end
            if bi then
                counts[bi] = counts[bi] or {}
                counts[bi][name] = (counts[bi][name] or 0) + 1
                kindAt[bi] = kindAt[bi] or kind
                members[bi] = members[bi] or {}
                local m = members[bi]
                m[#m + 1] = x
                m[#m + 1] = y
            end
        end)
    end
    local labels = {}
    for i, c in pairs(counts) do
        local list = {}
        for name, k in pairs(c) do list[#list + 1] = { name, k } end
        table.sort(list, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
        local parts = {}
        for k = 1, math.min(#list, GP.NAV_LABEL_NAMES) do
            parts[k] = list[k][2] > 1 and (list[k][1] .. " ×" .. list[k][2]) or list[k][1]
        end
        if #list > GP.NAV_LABEL_NAMES then parts[#parts + 1] = "+" .. (#list - GP.NAV_LABEL_NAMES) end
        labels[i] = table.concat(parts, ", ")
    end
    return labels, members, kindAt
end

-- A stop's title as the rider picked (db.navLabel)
function GP:StopTitle(k, n, what)
    local number = L["Stop %d/%d"]:format(k, n)
    local style = self.db.navLabel
    if style == "nodes" then return what or number end
    if style == "both" and what then return L["%d/%d: %s"]:format(k, n, what) end
    return number
end

local function StopAt(p)
    local i = Index(p)
    local pts = nav.points
    local k = (p - 1) % nav.n + 1
    local lap = Lap(p)
    local what = nav.labels and nav.labels[i]
    local tip = { nav.route.name }
    if what and GP.db.navLabel == "number" then tip[#tip + 1] = what end
    if lap > 1 then tip[#tip + 1] = L["Lap %d"]:format(lap) end
    return {
        map = nav.route.mapID,
        x = pts[2 * i - 1],
        y = pts[2 * i],
        title = GP:StopTitle(k, nav.n, what),
        tooltip = table.concat(tip, "\n"),
    }
end

-- Whether the stop at position p is empty: it has nodes, and you gathered
-- every one of them within the last db.navRespawn minutes
local function Empty(p)
    if p >= nav.last then return false end
    local m = nav.members and nav.members[Index(p)]
    if not m or #m == 0 then return false end
    local mapID = nav.route.mapID
    local seconds = GP:SkipSeconds(mapID, nav.kindAt and nav.kindAt[Index(p)])
    if seconds <= 0 then return false end
    local now = GetTime()
    for k = 1, #m, 2 do
        if not GP:WasHarvested(mapID, m[k], m[k + 1], seconds, now) then return false end
    end
    return true
end
GP.NavStopEmpty = function(p) return nav ~= nil and Empty(p) end

-- Hand Shortest Path the positions from p on, leaving out empty stops (each
-- noted in nav.skipped). False if it turned them down (in combat, Journeys
-- switched off, no position yet); it's tried again.
local function Send(p)
    local api = API()
    if not api then return false end
    local ahead = max(2, GP.NAV_AHEAD or GP.db.navAhead or 10)
    local stops, chunk, skipped = {}, {}, {}
    local q, stop = p, min(nav.last, p + nav.n + ahead)
    while #chunk < ahead and q <= stop do
        if Empty(q) then
            skipped[#skipped + 1] = q
        else
            chunk[#chunk + 1] = q
            stops[#stops + 1] = StopAt(q)
        end
        q = q + 1
    end
    if #chunk == 0 then   -- everything's empty: go on anyway
        chunk[1], stops[1], skipped = p, StopAt(p), {}
    end
    local ok = api.NavigateRoute(OWNER, stops)
    if ok then
        for _, s in ipairs(skipped) do nav.skipped[s] = true end
        nav.chunk, nav.first, nav.count, nav.pos, nav.pending, nav.refusedAt = chunk, chunk[1], #stops, chunk[1], nil, nil
        return true
    end
    nav.pending = p
    if not InCombat() then nav.refusedAt = nav.refusedAt or GetTime() end
    return false
end

local ticker, unsubscribe

local finishing   -- set while a ride ends by itself (its laps done): a tour goes on

local function Halt()
    if not finishing and GP.tourRide then GP:EndTour() end   -- stopped some other way: the tour too
    -- the lap you stopped in counts for the riding time (an hour's nodes and gold)
    if nav and nav.lapBegan then GP:AddRideTime(nav.route, GetTime() - nav.lapBegan) end
    if ticker then ticker:Cancel(); ticker = nil end
    if unsubscribe then pcall(unsubscribe); unsubscribe = nil end
    nav = nil
    if GP.Changed then GP:Changed() end
end

local function FormatTime(seconds)
    seconds = floor(seconds + 0.5)
    if seconds < 60 then return L["%d s"]:format(seconds) end
    return L["%d:%02d min"]:format(floor(seconds / 60), seconds % 60)
end

-- Riding on: from p (the position you're heading for), the last stop you've
-- come within reach of: p itself within db.navReach yards (Shortest Path's own
-- arrival is 15 yards between stops), or a later one, so the ones you cut
-- aren't asked for again
local function CatchUp(p)
    local route = nav.route
    local px, py = GP.PlayerPos(route.mapID)
    if not px then return nil end
    local w, h = Yards(route.mapID)
    local reach = max(GP.db.navReach or 0, GP.NAV_CATCH)
    local found
    do
        local i = Index(p)
        local dx, dy = (nav.points[2 * i - 1] - px) * w, (nav.points[2 * i] - py) * h
        local r = GP.db.navReach or 0
        if r > 0 and dx * dx + dy * dy <= r * r then found = p end
    end
    for q = p + 1, min(p + GP.NAV_CATCH_AHEAD, nav.last) do
        local i = Index(q)
        local dx, dy = (nav.points[2 * i - 1] - px) * w, (nav.points[2 * i] - py) * h
        if dx * dx + dy * dy <= reach * reach then found = q end
    end
    return found
end

-- p is the position you're heading for: the ones before it are done. A lap
-- is timed from reaching its first stop to reaching the next lap's first one.
local function NoteLap(p)
    if not nav.lapBegan and p >= 2 then nav.lapBegan = GetTime() end
    -- the stops passed since last time: reached (for "found empty")
    local from = (nav.reached or 0) + 1
    if p - 1 > (nav.reached or 0) then
        for q = max(from, p - 1 - GP.NAV_CATCH_AHEAD), p - 1 do
            if not nav.skipped[q] and nav.members then GP:StopReached(nav.route, nav.members[Index(q)]) end
        end
        nav.reached = p - 1
    end
    local lap = Lap(max(1, p - 1))
    if lap > (nav.lap or 1) then
        local now = GetTime()
        local done = nav.lap or 1
        local skipped = 0
        for q = (done - 1) * nav.n + 1, done * nav.n do
            if nav.skipped[q] then skipped = skipped + 1 end
        end
        local took = now - (nav.lapBegan or now)
        GP:RecordLap(nav.route, took)
        GP:AddRideTime(nav.route, took)
        local line = L["lap %d of %s done in %s."]:format(done, nav.route.name, FormatTime(took))
        if skipped > 0 then
            line = line .. " " .. (skipped == 1 and L["1 stop skipped (still empty)."]
                or L["%d stops skipped (still empty)."]:format(skipped))
        end
        Print(line)
        nav.lap, nav.lapBegan = lap, now
    end
end

local function Finish()
    NoteLap(nav.last + 1)
    local route, laps = nav.route, nav.laps
    local took = GetTime() - (nav.began or GetTime())
    finishing = true
    Halt()
    finishing = nil
    Print((laps == 1 and L["%s done: 1 lap in %s."]:format(route.name, FormatTime(took)))
        or L["%s done: %d laps in %s."]:format(route.name, laps, FormatTime(took)))
    if GP.tourRide and GP.TourNext then
        -- on to the tour's next route, a moment later (not from inside this tick)
        if C_Timer and C_Timer.After then C_Timer.After(0, function() GP:TourNext() end) else GP:TourNext() end
    end
end

local function Tick()
    if not nav then return end
    local api = API()
    if not api then Halt(); Print(L["Shortest Path Forever is gone, so the guidance stopped."]) return end
    local route = nav.route
    local alive = false
    for _, r in ipairs(GP.db.routes) do if r == route then alive = true break end end
    if not alive then
        if api.CurrentStop(OWNER) then api.Cancel(OWNER) end
        Halt(); Print(L["the route you were riding was deleted."]) return
    end
    if route.working or route.points ~= nav.points then
        if api.CurrentStop(OWNER) then api.Cancel(OWNER) end
        Halt(); Print(L["%s changed. Click Start on it again to ride the new loop."]:format(route.name)) return
    end

    if nav.pending then
        if not Send(nav.pending) and nav.refusedAt and GetTime() - nav.refusedAt > GP.NAV_GIVE_UP then
            Halt()
            Print(L["Shortest Path Forever won't take the route. Is its Journeys guidance switched on?"])
        end
        return
    end

    local i, why = api.CurrentStop(OWNER)
    if i then
        local p = nav.chunk[i] or nav.chunk[#nav.chunk]
        if p ~= nav.pos and GP.RefreshConfig then nav.pos = p; GP:RefreshConfig() end
        nav.pos = p
        NoteLap(p)
        local skip = CatchUp(p)
        if skip then
            if skip >= nav.last then Finish() if api.CurrentStop(OWNER) then api.Cancel(OWNER) end return end
            NoteLap(skip + 1)
            Send(skip + 1)
        elseif i >= nav.count and p < nav.last then
            Send(p)   -- heading for the last one it has: send it again with the next ones behind it
        end
        return
    end
    if why == "loading" then return end
    local ended = api.Ended(OWNER)
    if ended == "arrived" then
        local done = nav.chunk[nav.count]
        if done >= nav.last then Finish() else NoteLap(done + 1); Send(done + 1) end
    elseif ended == "cleared" or ended == "replaced" or ended == "cancelled" then
        local name = route.name
        Halt()
        Print(L["stopped riding %s (%s)."]:format(name,
            ended == "replaced" and L["another journey took over"] or L["the journey was cleared"]))
    end
end

-- Where to join the loop: the nearest stop if you're in the route's zone,
-- else the stop Shortest Path says is quickest to reach (of a few)
local function EntryIndex(api, route, n)
    local pts = route.points
    local px, py = GP.PlayerPos(route.mapID)
    if px and px > -0.25 and px < 1.25 and py > -0.25 and py < 1.25 then
        local w, h = Yards(route.mapID)
        local best, bi = huge, 1
        for i = 1, n do
            local dx, dy = (pts[2 * i - 1] - px) * w, (pts[2 * i] - py) * h
            local d = dx * dx + dy * dy
            if d < best then best, bi = d, i end
        end
        return bi
    end
    local here = GP:PlayerMap()
    local hx, hy = here and GP.PlayerPos(here)
    if not (hx and type(api.Estimate) == "function") then return 1 end
    local best, bi = huge, 1
    local samples = min(n, GP.NAV_SAMPLES)
    for s = 0, samples - 1 do
        local i = floor(s * n / samples) + 1
        local ok, seconds = pcall(api.Estimate, here, hx, hy, route.mapID, pts[2 * i - 1], pts[2 * i])
        if ok and type(seconds) == "number" and seconds < best then best, bi = seconds, i end
    end
    return bi
end

-- Start riding a route: laps = how many (0 = until you stop)
function GP:StartNav(route, laps)
    local api = API()
    if not api then
        Print(L["needs |cffffd100Shortest Path Forever|r for the guidance. Install it, then /reload."])
        return false
    end
    local n = route and self:NodeCount(route) or 0
    if not route or route.working or n < 2 then
        Print(L["that route has no loop to ride yet."])
        return false
    end
    if InCombat() then Print(L["not in combat."]) return false end
    if nav then
        if api.CurrentStop(OWNER) then api.Cancel(OWNER) end
        Halt()
    end
    laps = laps or self.db.navLaps or 0
    local start = EntryIndex(api, route, n)
    local now = GetTime()
    nav = {
        route = route, points = route.points, n = n, start = start,
        dir = self.db.arrowsReverse and -1 or 1,
        laps = laps, last = laps > 0 and laps * n + 1 or huge,
        began = now, lap = 1, skipped = {},
    }
    local ok, labels, members, kindAt = pcall(self.StopLabels, self, route)
    nav.labels = ok and labels or nil
    nav.members = ok and members or nil
    nav.kindAt = ok and kindAt or nil
    if not Send(1) and not InCombat() then
        nav = nil
        Print(L["Shortest Path Forever won't take the route. Is its Journeys guidance switched on?"])
        return false
    end
    ticker = C_Timer.NewTicker(GP.NAV_TICK, Tick)
    if type(api.Subscribe) == "function" then
        -- not from inside Shortest Path's own dispatch: a frame later
        local ok, unsub = pcall(api.Subscribe, function() C_Timer.After(0, Tick) end)
        if ok then unsubscribe = unsub end
    end
    Print(L["riding %s: joining at stop %d of %d, %s. |cffffd100/gl stop|r to stop."]:format(route.name, start, n,
        laps == 1 and L["1 lap"] or laps > 0 and L["%d laps"]:format(laps) or L["lap after lap"]))
    self:Changed()
    return true
end

function GP:StopNav(quiet)
    if not nav then return false end
    local name = nav.route.name
    local api = API()
    if api and api.CurrentStop(OWNER) then api.Cancel(OWNER) end
    Halt()
    if not quiet then Print(L["stopped riding %s."]:format(name)) end
    return true
end

-- What the route rows say while one is ridden
function GP:NavStatus()
    if not nav then return nil end
    local p = nav.pos or 1
    local k = (p - 1) % nav.n + 1
    local s = L["Riding: stop %d/%d"]:format(k, nav.n)
    if nav.laps ~= 1 then s = s .. L[", lap %d"]:format(Lap(p)) .. (nav.laps > 0 and ("/" .. nav.laps) or "") end
    local t = GP.tourRide
    if t then s = s .. L[", tour %d/%d"]:format(t.stage, #t.tour.stages) end
    return s
end

-- What the HUD shows of the ride: nil when not riding, else
-- { route, mapID, n, lap, laps, k (stop number in the lap), elapsed (this lap),
--   ahead = { { x, y, what, kind, num, empty, current } ... } (the next GP.HUD_AHEAD positions),
--   states = { "done" | "skipped" | "current" | "empty" | "todo" } (one per stop of the lap),
--   skipped (this lap) }
GP.HUD_AHEAD = 8
function GP:HudState()
    if not nav then return nil end
    local p = nav.pos or 1
    local lap = Lap(p)
    local s = { route = nav.route, mapID = nav.route.mapID, n = nav.n, lap = lap, laps = nav.laps,
        k = (p - 1) % nav.n + 1, elapsed = nav.lapBegan and (GetTime() - nav.lapBegan) or nil, ahead = {}, states = {}, skipped = 0 }
    for q = p, min(p + GP.HUD_AHEAD - 1, nav.last) do
        local i = Index(q)
        s.ahead[#s.ahead + 1] = { x = nav.points[2 * i - 1], y = nav.points[2 * i], what = nav.labels and nav.labels[i],
            kind = nav.kindAt and nav.kindAt[i], num = (q - 1) % nav.n + 1, empty = q ~= p and Empty(q), current = q == p }
    end
    local first = (lap - 1) * nav.n + 1
    for q = first, first + nav.n - 1 do
        local st
        if q < p then st = nav.skipped[q] and "skipped" or "done"
        elseif q == p then st = "current"
        else st = Empty(q) and "empty" or "todo" end
        if st == "skipped" then s.skipped = s.skipped + 1 end
        s.states[#s.states + 1] = st
    end
    return s
end

-- The route ridden now, or the first shown one in your zone
function GP:NavCandidate()
    local mapID = self:PlayerMap()
    for _, r in ipairs(mapID and self:RoutesOn(mapID) or {}) do
        if r.shown and not r.working and self:NodeCount(r) >= 2 then return r end
    end
    return nil
end
