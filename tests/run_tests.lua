-- Gatherline tests. Run from the repo root: lua5.1 tests/run.lua

local function STEP(name) LOG[#LOG + 1] = "STEP " .. name end
local function check(cond, msg) if not cond then error(msg or "check failed", 2) end end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end
local function logHas(text)
    for i = #LOG, 1, -1 do if LOG[i]:find(text, 1, true) then return true end end
    return false
end

---------------------------------------------------------------------------
STEP("route solver")
local O = loadfile("Optimize.lua")("Gatherline", {})
math.randomseed(7)
local function perms(a, n, f)
    if n == 0 then f(a) return end
    for i = 1, n do a[n], a[i] = a[i], a[n]; perms(a, n - 1, f); a[n], a[i] = a[i], a[n] end
end
local function isTour(t, n)
    if #t ~= n then return false end
    local seen = {}
    for _, v in ipairs(t) do if seen[v] or v < 1 or v > n then return false end seen[v] = true end
    return true
end
for _ = 1, 25 do
    local pts = {}
    for i = 1, 8 do pts[i] = { math.random() * 1000, math.random() * 700 } end
    local tour = O.Solve(pts)
    check(isTour(tour, 8), "the tour visits every node once")
    local best = math.huge
    local rest = { 2, 3, 4, 5, 6, 7, 8 }
    perms(rest, 7, function(p)
        local t = { 1 }
        for i = 1, 7 do t[i + 1] = p[i] end
        best = math.min(best, O.Length(pts, t))
    end)
    check(O.Length(pts, tour) <= best * 1.02, "8 nodes: within 2% of the shortest loop")
end
do
    -- a ring of nodes, shuffled: the answer is the ring
    local pts = {}
    for i = 1, 40 do
        local a = (i / 40) * 2 * math.pi
        pts[i] = { 500 + 300 * math.cos(a), 500 + 300 * math.sin(a) }
    end
    for i = #pts, 2, -1 do local j = math.random(i); pts[i], pts[j] = pts[j], pts[i] end
    local tour = O.Solve(pts)
    check(isTour(tour, 40))
    local ring = 40 * 2 * 300 * math.sin(math.pi / 40)
    check(near(O.Length(pts, tour), ring, 0.01), "a shuffled ring comes back as the ring")
    -- bigger sets still come back whole
    local big = {}
    for i = 1, 250 do big[i] = { math.random() * 2000, math.random() * 1500 } end
    check(isTour(O.Solve(big), 250), "250 nodes")
    check(#O.Solve({}) == 0 and #O.Solve({ { 1, 1 } }) == 1, "0 and 1 nodes")
end
do
    -- every size from 2 up comes back whole
    for n = 2, 30 do
        local pts = {}
        for i = 1, n do pts[i] = { math.random() * 500, math.random() * 500 } end
        check(isTour(O.Solve(pts), n), n .. " nodes come back whole")
    end
    -- quick: on 600 nodes the old solver handed the frame back 1816 times
    local pts = {}
    for i = 1, 600 do pts[i] = { math.random() * 2000, math.random() * 1500 } end
    local pauses = 0
    O.Pause = function() pauses = pauses + 1 end
    local tour = O.Solve(pts)
    O.Pause = function() end
    check(isTour(tour, 600), "600 nodes")
    check(pauses < 700, "600 nodes take well under half the work they used to (" .. pauses .. ")")
    -- and no longer than untangling every crossing the slow way
    pts = {}
    for i = 1, 250 do pts[i] = { math.random() * 2000, math.random() * 1500 } end
    tour = O.Solve(pts)
    local plain = {}
    for i = 1, #pts do plain[i] = i end
    local better = true
    while better do
        better = false
        for i = 1, #plain - 2 do
            for j = i + 2, #plain do
                if not (i == 1 and j == #plain) then
                    local a, b = pts[plain[i]], pts[plain[i + 1]]
                    local c, d = pts[plain[j]], pts[plain[j % #plain + 1]]
                    if O.Dist(a, c) + O.Dist(b, d) < O.Dist(a, b) + O.Dist(c, d) - 1e-6 then
                        local x, y = i + 1, j
                        while x < y do plain[x], plain[y] = plain[y], plain[x]; x, y = x + 1, y - 1 end
                        better = true
                    end
                end
            end
        end
    end
    -- (0.891 now; 0.906 without the shakes, 0.910 keeping shakes that didn't help)
    check(O.Length(pts, tour) < O.Length(pts, plain) * 0.90, "a tenth shorter than untangling every crossing")
    -- the same nodes give the same route every time
    local again = O.Solve(pts)
    local same = true
    for i = 1, #pts do same = same and again[i] == tour[i] end
    check(same, "the same route every time")
end
do
    local g = O.Group({ { 0, 0 }, { 10, 0 }, { 20, 0 }, { 200, 0 } }, 12)
    check(#g == 3, "nodes within 12 yards of the first group together (not a whole chain)")
    check(near(g[1][1], 5) and g[1].count == 2 and near(g[1].reach, 5), "in the middle of them")
    check(g[3].count == 1 and g[3].reach == 0, "a lone node is its own spot")
    g = O.Group({ { 0, 0 }, { 10, 0 }, { 10, 0 }, { 10, 0 }, { -10, 0 } }, 10)
    check(#g == 1 and g[1].reach <= 10, "never leaves a node further than the radius from its spot")
    check(#O.Group({ { 0, 0 }, { 10, 0 } }, 0) == 2, "radius 0 keeps every node")
    local pts = { { 0, 0 }, { 100, 0 }, { 100, 100 }, { 0, 100 } }
    local at, cost = O.BestInsert(pts, { 1, 2, 3, 4 }, { 50, -10 })
    check(at == 1 and cost > 0 and cost < 5, "a new node goes in the leg it's beside")
end
do
    -- passing within a distance of each node
    local function covered(nodes, stops, r)
        for _, c in ipairs(nodes) do
            local best = math.huge
            for i = 1, #stops do
                best = math.min(best, O.SegDist(stops[i], stops[i % #stops + 1], c))
            end
            if best > r + 0.5 then return false end
        end
        return true
    end
    local function loopLength(stops)
        local t = {}
        for i = 1, #stops do t[i] = i end
        return O.Length(stops, t)
    end
    local p = O.Place({ 0, 0 }, { 100, 0 }, { 50, 30 }, 40)
    check(near(p[1], 50) and near(p[2], 0), "a line that passes close enough is walked straight")
    p = O.Place({ 0, 0 }, { 100, 0 }, { 50, 100 }, 40)
    check(near(p[1], 50, 0.01) and near(p[2], 60, 0.01), "else the closest spot on the circle")
    check(near(O.SegDist({ 0, 0 }, { 10, 0 }, { 20, 0 }), 10) and near(O.SegDist({ 0, 0 }, { 10, 0 }, { 5, 3 }), 3))
    -- a square of nodes 200 apart, 40 yards: each corner cut
    local sq = { { 0, 0 }, { 200, 0 }, { 200, 200 }, { 0, 200 } }
    local stops = O.Shortcut(sq, 40)
    check(#stops == 4 and covered(sq, stops, 40), "every node still within reach")
    check(near(loopLength(stops), 4 * (200 - 80 / math.sqrt(2)), 1), "each corner cut 40 yards in")
    check(near(loopLength(O.Shortcut(sq, 0)), 800, 0.01), "off: right up to every node")
    -- a zigzag along a line: one straight run instead
    local zig = {}
    for i = 0, 10 do zig[#zig + 1] = { i * 50, (i % 2 == 0) and 0 or 60 } end
    stops = O.Shortcut(zig, 40)
    check(covered(zig, stops, 40), "zigzag covered")
    check(#stops < #zig, "stops on a straight line are dropped")
    check(loopLength(stops) < O.Length(zig, O.Solve(zig)) * 0.9, "and it's shorter")
    -- random fields: always covered, never longer
    for _ = 1, 15 do
        local f = {}
        for i = 1, 60 do f[i] = { math.random() * 1200, math.random() * 900 } end
        local full = O.Length(f, O.Solve(f))
        for _, r in ipairs({ 20, 50, 120 }) do
            local s2 = O.Shortcut(f, r)
            check(#s2 >= 2 and covered(f, s2, r), "random nodes covered at " .. r)
            -- clustered too (herbs grow in patches)
            local patch = {}
            for c = 1, 15 do
                local cx, cy = math.random() * 1200, math.random() * 900
                for _ = 1, 4 do patch[#patch + 1] = { cx + math.random() * 30, cy + math.random() * 30 } end
            end
            check(covered(patch, O.Shortcut(patch, r), r), "patches covered at " .. r)
            check(loopLength(s2) <= full + 0.01, "never longer than going to every node")
        end
    end
    check(#O.Shortcut({ { 0, 0 }, { 10, 0 } }, 50) == 2, "two nodes stay two stops")
    -- patches of nodes: one stop each, and the route only comes within reach of them
    local patches = {}
    for c = 0, 4 do
        for k = 0, 4 do patches[#patches + 1] = { c * 400 + (k % 2) * 12, (c % 2) * 300 + math.floor(k / 2) * 12 } end
    end
    local ps = O.Shortcut(patches, 60)
    check(#ps <= 5 and covered(patches, ps, 60), "a patch of nodes is one stop")
    check(loopLength(ps) < O.Length(patches, O.Solve(patches)) - 300, "and cuts the corners")
end

---------------------------------------------------------------------------
STEP("no-go areas in the solver")
do
    -- a tall block in the middle of a 1000 x 1000 field
    local block = { 450, -10, 550, -10, 550, 900, 450, 900 }
    local W = O.Walls({ block })
    check(W and #W.verts == 4, "its four corners to go round")
    check(O.Walls({}) == nil and O.Walls({ { 0, 0, 1, 1 } }) == nil, "no areas (or one with 2 corners): no walls")
    check(W:Inside({ 500, 500 }) and not W:Inside({ 400, 500 }), "inside and outside")
    check(W:Blocked({ 100, 500 }, { 900, 500 }) and not W:Blocked({ 100, 950 }, { 900, 950 }), "a line through it is blocked")
    check(not W:Blocked({ 100, 500 }, { 300, 500 }), "a line beside it isn't")
    -- round the top: (100,500) -> (447,903) -> (553,903) -> (900,500)
    local d = W:Dist({ 100, 500 }, { 900, 500 })
    local over = 2 * math.sqrt(347 ^ 2 + 403 ^ 2) + 106
    check(near(d, over, 0.01), "the way round is the distance (" .. d .. ")")
    local path = W:Path({ 100, 500 }, { 900, 500 })
    check(#path == 2 and near(path[1][1], 450 - O.WALL_MARGIN) and near(path[1][2], 900 + O.WALL_MARGIN)
        and near(path[2][1], 550 + O.WALL_MARGIN), "bending round the two top corners, a little out from them")
    check(#W:Path({ 100, 950 }, { 900, 950 }) == 0, "no bends on a clear line")
    -- a U: from inside its pocket out under it goes up, over an arm and down
    local U = { 300, 200, 700, 200, 700, 1000, 600, 1000, 600, 300, 400, 300, 400, 1000, 300, 1000 }
    local WU = O.Walls({ U })
    check(not WU:Inside({ 500, 600 }) and WU:Inside({ 350, 600 }), "the pocket isn't inside, the arm is")
    local up = WU:Path({ 500, 600 }, { 500, 100 })
    check(#up == 3 and up[1][2] > 1000 and up[3][2] < 200, "out of the pocket and round an arm")
    check(near(WU:Dist({ 500, 600 }, { 500, 100 }), WU:Dist({ 500, 100 }, { 500, 600 })), "the same both ways")
    check(O.SelfCrossing({ 0, 0, 10, 10, 10, 0, 0, 10 }) and not O.SelfCrossing(U), "edges that cross are found")
    -- random fields round the block, every way: no leg goes through it
    local function covered(nodes, stops, r)
        for _, c in ipairs(nodes) do
            local best = math.huge
            for i = 1, #stops do best = math.min(best, O.SegDist(stops[i], stops[i % #stops + 1], c)) end
            if best > r + 0.5 then return false end
        end
        return true
    end
    local function blockedLegs(stops, w)
        local bad = 0
        for i = 1, #stops do if w:Blocked(stops[i], stops[i % #stops + 1]) then bad = bad + 1 end end
        return bad
    end
    for _, r in ipairs({ 0, 60 }) do
        for _ = 1, 4 do
            local pts = {}
            while #pts < 80 do
                local q = { math.random() * 1000, math.random() * 1000 }
                if not W:Inside(q) then pts[#pts + 1] = q end
            end
            O.SetWalls(W)
            local stops = O.Expand(O.Shortcut(pts, r))
            O.SetWalls(nil)
            check(blockedLegs(stops, W) == 0, "no leg crosses the area (passes within " .. r .. ")")
            local bends, inside = 0, 0
            for _, st in ipairs(stops) do
                if st.bend then bends = bends + 1 end
                if W:Inside(st) then inside = inside + 1 end
            end
            check(bends > 0 and inside == 0, "it bends round, and no stop is in it")
            if r == 0 then check(#stops - bends == 80, "every node is still a stop") end
            if r > 0 then check(covered(pts, stops, r), "every node is still passed within reach") end
            -- without the area the same nodes go straight through
            check(blockedLegs(O.Shortcut(pts, r), W) > 0, "(which they would without it)")
        end
    end
    check(O.GetWalls() == nil and O.Dist({ 0, 0 }, { 3, 4 }) == 5, "walls off again: straight lines")
    -- a stop that passes within reach never stands behind the area from its node
    O.SetWalls(W)
    local spot = O.Place({ 400, 500 }, { 400, 600 }, { 560, 550 }, 120)
    O.SetWalls(nil)
    check(not W:Inside(spot) and not W:Blocked(spot, { 560, 550 }), "the stop stays on the node's side")
end

---------------------------------------------------------------------------
STEP("load with GatherMate2")
local E, W = 1429, 1436
local gm = FakeGatherMate({
    -- Peacebloom round a square in Elwynn
    { E, "Herb Gathering", 1, 0.40, 0.40 }, { E, "Herb Gathering", 1, 0.60, 0.40 },
    { E, "Herb Gathering", 1, 0.60, 0.60 }, { E, "Herb Gathering", 1, 0.40, 0.60 },
    { E, "Herb Gathering", 1, 0.50, 0.40 },
    { E, "Herb Gathering", 2, 0.45, 0.50 }, { E, "Herb Gathering", 2, 0.55, 0.50 },
    { E, "Mining", 10, 0.30, 0.30 }, { E, "Mining", 10, 0.70, 0.70 }, { E, "Mining", 10, 0.30, 0.70 },
    { W, "Mining", 11, 0.5, 0.5 },
})
local ns = LoadAddon(".")
local GP = ns.GP
FireEvent("ADDON_LOADED", "Gatherline")
FireEvent("PLAYER_LOGIN")
check(GP.db and GP.db.worldMap and GP.db.minimap, "defaults are in")
check(GP:HasGatherMate(), "GatherMate2 found")
check(not logHas("needs |cffffd100GatherMate2"), "no warning with GatherMate2 there")
check(GP.provider and #WorldMapFrame.__providers == 1, "the world map has our lines")
check(GP.mm and GP.minimapButton, "minimap lines and button")

STEP("what GatherMate2 knows")
local nodes = GP:ZoneNodes(E)
check(#nodes == 3, "Elwynn: Peacebloom, Silverleaf, Copper Vein")
check(nodes[1].name == "Peacebloom" and nodes[1].count == 5 and nodes[1].kind == "Herb Gathering", "herbs first, by name")
check(nodes[2].name == "Silverleaf" and nodes[2].count == 2)
check(nodes[3].name == "Copper Vein" and nodes[3].kind == "Mining" and nodes[3].count == 3)
local zones = GP:GatherZones()
check(#zones == 2 and zones[1] == E and zones[2] == W, "zones with nodes, by name")
check(GP:RouteName(E, { ["Herb Gathering"] = { Peacebloom = true } }) == "Peacebloom")
check(GP:RouteName(E, { ["Herb Gathering"] = { Peacebloom = true, Silverleaf = true } }) == "Peacebloom and Silverleaf")
check(GP:RouteName(E, { ["Herb Gathering"] = { Peacebloom = true, Silverleaf = true }, Mining = { ["Copper Vein"] = true } })
    == "Peacebloom, Silverleaf and 1 more")

---------------------------------------------------------------------------
STEP("make a route from the window")
local function RunJobs()
    for _ = 1, 10000 do
        if not GP:Busy() then return end
        Tick(0.016)
    end
    error("the job never finished")
end
GP:OpenConfig("new")
check(GP.config:IsShown() and GP.config.currentTab == "new")
local ui = GP.ui
check(ui.makeButton.disabled, "Make route waits for a pick")
local function SwitchFor(name)
    for _, sw in ipairs(ui.kindSwitches) do
        local e = rawget(sw, "entry")
        if e and e.name == name and sw:IsShown() then return sw end
    end
end
check(ui.newZone.getter() == nil and not SwitchFor("Peacebloom") and ui.newNote:GetText():find("Pick a zone", 1, true),
    "starts with no zone picked")
check(not ui.cancelButton:IsShown(), "no Cancel when making a new route")
Click(ui.myZone)
check(ui.newZone.getter() == E, "My zone picks the zone you're in")
check(SwitchFor("Peacebloom") and SwitchFor("Copper Vein") and SwitchFor("Silverleaf"), "a switch per kind of node")
check(SwitchFor("Peacebloom").label:GetText():find("(5)", 1, true), "with how many there are")
Click(SwitchFor("Peacebloom"))
Click(SwitchFor("Silverleaf"))
check(SwitchFor("Peacebloom"):IsOn() and not ui.makeButton.disabled)
check(ui.sightSlider:GetValue() == 185, "new routes pass within 185 yards unless you change it")
check(ui.sightSlider.valueText:GetText() == "185 yards", "185 stays 185 (not rounded to 190 by the slider's steps)")
ui.sightSlider:SetValue(200)
check(ui.sightSlider:GetValue() == 200 and ui.sightSlider.valueText:GetText() == "200 yards", "the slider goes up to 200 yards")
ui.sightSlider:SetValue(0)   -- this route goes right up to every node
check(ui.mergeSlider == nil, "no Combine nodes within slider (Route passes within groups nodes itself)")
ui.newName:SetText("Picked")

STEP("New route always opens blank")
GP:OpenConfig("routes")
GP.db.sight = 90   -- what 1.1.0 remembered from the last route
GP:OpenConfig("new")
check(ui.newZone.getter() == nil and ui.newName:GetText() == "" and not SwitchFor("Peacebloom"), "no zone, name or picks")
check(ui.sightSlider:GetValue() == 185, "slider back at its default")
GP.config:Hide()
GP:OpenConfig("new")
Click(ui.myZone)
check(not SwitchFor("Peacebloom"):IsOn(), "closing the window clears the picks too")
Click(SwitchFor("Peacebloom"))
GP.config:Hide()
GP.config:Show()
check(ui.newZone.getter() == nil, "and showing it again on New route")
GP:OpenConfig("routes")
ui.routesZone.Choose(E)
Click(ui.routesNew)
check(GP.config.currentTab == "new" and ui.newZone.getter() == E, "New route on Routes starts on the zone picked there")
check(not SwitchFor("Peacebloom"):IsOn() and ui.newName:GetText() == "Elwynn Forest - " and ui.sightSlider:GetValue() == 185,
    "the rest blank, the name started with the zone")
GP.config.tabButtons.new:GetScript("OnClick")()
check(ui.newZone.getter() == nil, "the New route tab itself still starts with no zone")
check(ui.newName:GetText() == "" and ui.newHint:IsShown(), "no zone, no name yet")
Click(ui.myZone)
check(ui.newName:GetText() == "Elwynn Forest - ", "the name starts with the zone")
ui.newZone.Choose(W)
check(ui.newName:GetText() == "Westfall - ", "and follows a zone change")
ui.newName:SetText("Westfall - mine")
ui.newZone.Choose(E)
check(ui.newZone.getter() == E and ui.newName:GetText() == "Westfall - mine", "but not over a name you typed")
ui.newName:SetText("Elwynn Forest - ")

STEP("Select all")
local herbHead
for _, h in ipairs(ui.kindHeads) do if h:IsShown() and h:GetText() == "HERBS" then herbHead = h end end
check(herbHead and herbHead.all:IsShown() and herbHead.all:GetText() == "Select all", "a Select all by each kind")
Click(herbHead.all)
check(SwitchFor("Peacebloom"):IsOn() and SwitchFor("Silverleaf"):IsOn() and not SwitchFor("Copper Vein"):IsOn(),
    "switches on every node of that kind, no other")
check(herbHead.all:GetText() == "Clear all", "then reads Clear all")
for _, h in ipairs(ui.kindHeads) do
    local pt = h.all.__points[#h.all.__points]
    check(pt[3] <= 0 and pt[2] + 84 <= 540 - 30, "Select all sits inside the list (not cut off at its top)")
end
check(GP.config.__h == 556 + 120, "the window is taller than the other addons', for a longer list")
Click(herbHead.all)
check(not SwitchFor("Peacebloom"):IsOn() and not SwitchFor("Silverleaf"):IsOn(), "which switches them off")
check(herbHead.all:GetText() == "Select all")
check(ui.makeButton.disabled, "nothing picked again")

STEP("make a route from the window, named after its zone")
Click(SwitchFor("Peacebloom"))
Click(SwitchFor("Silverleaf"))
check(ui.newHint:IsShown() and ui.newHint:GetText() == "Peacebloom and Silverleaf", "the rest of the name greyed after the zone")
ui.sightSlider:SetValue(0)
Click(ui.makeButton)
check(GP:Busy(), "working it out over a few frames")
check(GP.config.currentTab == "routes", "then shows the routes")
RunJobs()
local route = GP.db.routes[1]
check(#GP.db.routes == 1 and route.name == "Elwynn Forest - Peacebloom and Silverleaf", "named from the zone and what was picked")
check(GP:NodeCount(route) == 7, "7 nodes")
check(logHas("made |cffffd100Elwynn Forest - Peacebloom and Silverleaf|r in Elwynn Forest: 7 nodes"), "says so in chat")
check(route.shown and route.color and route.mapID == E)
-- the length is the loop's, in yards
local pts, tour = {}, {}
for i = 1, 7 do pts[i] = { route.points[2 * i - 1] * 1600, route.points[2 * i] * 1066 }; tour[i] = i end
check(near(route.length, O.Length(pts, tour), 0.01), "length in yards")
check(ui.routeRows[1]:IsShown() and ui.routeRows[1].route == route, "listed")
check(ui.routeRows[1].info:GetText():find("7 nodes", 1, true))
check(ui.routeRows[1].name:GetText() == route.name)

STEP("with a route listed, the rest of the window still fills in")
-- 1.2.0: the routes list stopped on Rebuild (it had no SetDisabled), so New route
-- was left with an empty zone menu and sliders without their values
GP:OpenConfig("new")
check(#ui.newZone.keys > 0, "New route's zone menu has the zones")
check(ui.newZone:GetText() == "Pick a zone", "and reads Pick a zone")
check(ui.sightSlider.valueText:GetText() == "185 yards", "passes within shows its value")
check(ui.newNote:GetText():find("Pick a zone above", 1, true), "the list says what to do")
GP:NewRoute({ mapID = E, kinds = { Herb = { Peacebloom = true } }, name = "busy" })
GP:OpenConfig("routes")
check(ui.routeRows[1].rebuild.disabled, "Rebuild greys out while a loop is worked out")
Click(ui.routeRows[1].rebuild)
RunJobs()
for i = #GP.db.routes, 1, -1 do if GP.db.routes[i].name == "busy" then GP:DeleteRoute(GP.db.routes[i]) end end
GP:OpenConfig("routes")
check(not ui.routeRows[1].rebuild.disabled, "and comes back after")

STEP("a second route takes the next color")
GP:NewRoute({ mapID = E, kinds = { Mining = { ["Copper Vein"] = true } } })
RunJobs()
local ore = GP.db.routes[2]
check(ore.name == "Copper Vein" and GP:NodeCount(ore) == 3)
check(ore.color[1] ~= route.color[1] or ore.color[3] ~= route.color[3], "a different color")
check(not GP:NewRoute({ mapID = E, kinds = {} }) and logHas("pick at least one"), "nothing picked: no route")
GP:NewRoute({ mapID = E, kinds = { Mining = { ["Tin Vein"] = true } } })
RunJobs()
check(#GP.db.routes == 2 and logHas("no node of those kinds"), "no nodes there: no route")

STEP("one name per route in a zone")
check(GP:NewRoute({ mapID = E, kinds = { Mining = { ["Copper Vein"] = true } } }) == nil and #GP.db.routes == 2
    and logHas("already a route called |cffffd100Copper Vein|r in Elwynn Forest"), "the same made-up name: no copy")
check(GP:NewRoute({ mapID = E, kinds = { Mining = { ["Tin Vein"] = true } }, name = "  copper VEIN " }) == nil
    and #GP.db.routes == 2, "a typed name, any case: no copy")
GP:OpenConfig("new")
ui.newZone.setter(E)
Click(SwitchFor("Copper Vein"))
ui.newName:SetText("Copper Vein")
Click(ui.makeButton)
check(#GP.db.routes == 2 and not GP:Busy() and GP.config.currentTab == "new"
    and ui.newName:GetText() == "Copper Vein", "from the window: stays on New route with the name kept")
Click(SwitchFor("Copper Vein"))
ui.newName:SetText("")
local away = GP:NewRoute({ mapID = W, kinds = { Mining = { ["Copper Vein"] = true } } })
check(away and away.name == "Copper Vein", "the same name in another zone is fine")
RunJobs()

---------------------------------------------------------------------------
STEP("world map lines")
local pin = GP.provider.pin
WorldMapFrame:Show()
GP:DrawWorldMap()
local function Shown(pool)
    local list = {}
    for _, l in ipairs(pool.lines) do if l.__shown then list[#list + 1] = l end end
    return list
end
local lines = Shown(pin.pool)
check(#lines == 7 + 3, "one line per leg of each loop")
-- every line is between two of the route's nodes, on the 1000 x 667 canvas
local first = lines[1]
check(near(first.__from[1], route.points[1] * 1000, 0.01) and near(first.__from[2], -route.points[2] * 667, 0.01))
check(near(first.__to[1], route.points[3] * 1000, 0.01))
check(near(first.__color[4], 0.85) and first.__color[1] == route.color[1], "the route's color, at the opacity")
check(first.__thickness == 4)
GP:SetRouteShown(ore, false)
check(#Shown(pin.pool) == 7, "a hidden route isn't drawn")
WorldMapFrame:SetMapID(W)
check(#Shown(pin.pool) == 0, "not on another zone's map")
WorldMapFrame:SetMapID(1415)
lines = Shown(pin.pool)
check(#lines == 7, "on the continent's map")
check(near(lines[1].__from[1], (0.40 + route.points[1] * 0.08) * 1000, 0.01), "placed where Elwynn is on it")
check(lines[1].__thickness == 2, "thinner there")
GP:SetRouteShown(ore, true)
WorldMapFrame:SetMapID(E)
GP.db.worldMap = false
GP:Changed()
check(#Shown(pin.pool) == 0, "world map lines off")
GP.db.worldMap = true
GP:Changed()

---------------------------------------------------------------------------
STEP("minimap lines")
-- the minimap is 140 wide (70 round), showing 150 yards round you
PLAYER.x, PLAYER.y = 0.5, 0.5
GP.db.routes[2].shown = false
GP:DrawMinimap(true)
local mm = Shown(GP.mm.pool)
check(#mm > 0, "lines near you")
local function inside(x, y) return math.sqrt(x * x + y * y) <= 69.01 end
for _, l in ipairs(mm) do
    check(inside(l.__from[1], l.__from[2]) and inside(l.__to[1], l.__to[2]), "kept inside the round minimap")
end
check(mm[1].__thickness == 3)
-- straight east of you, 100 yards: 100 * 70/150 pixels to the right
route.points = { 0.5 + 100 / 1600, 0.5, 0.5 + 100 / 1600, 0.5 + 50 / 1066 }
route.length = GP:RouteLength(route)
GP:DrawMinimap(true)
mm = Shown(GP.mm.pool)
check(#mm == 1, "two nodes: one line")
check(near(mm[1].__from[1], 100 * 70 / 150, 0.01) and near(mm[1].__from[2], 0, 0.01), "east is right")
check(near(mm[1].__to[2], -50 * 70 / 150, 0.01), "south is down")
-- turning: the minimap turns with you, so facing west puts the east node below you
CVARS.rotateMinimap = "1"
FACING = math.pi / 2
GP:DrawMinimap(true)
mm = Shown(GP.mm.pool)
check(near(mm[1].__from[1], 0, 0.01) and near(mm[1].__from[2], -100 * 70 / 150, 0.01), "facing west: east is behind you")
FACING = math.pi
GP:DrawMinimap(true)
mm = Shown(GP.mm.pool)
check(near(mm[1].__from[1], -100 * 70 / 150, 0.01), "facing south: east is on your left")
CVARS.rotateMinimap, FACING = "0", 0
-- far away: nothing
route.points = { 0.9, 0.9, 0.95, 0.9 }
GP:DrawMinimap(true)
check(#Shown(GP.mm.pool) == 0, "a route out of sight draws nothing")
-- a line crossing the minimap is cut at the edge
check(GP.ClipCircle(-100, 0, 100, 0, 50) == -50, "cut at the circle")
local ax, ay, bx, by = GP.ClipSquare(-100, 10, 100, 10, 50)
check(ax == -50 and bx == 50 and ay == 10, "and at a square minimap's edge")
check(GP.ClipCircle(-100, 60, 100, 60, 50) == nil, "a line passing by isn't drawn")
-- you in another zone
PLAYER.map = W
GP:DrawMinimap(true)
check(#Shown(GP.mm.pool) == 0, "not while you're in another zone")
PLAYER.map = E
GP.db.routes[2].shown = true
GP:RebuildRoute(route)
RunJobs()
check(GP:NodeCount(route) == 7 and logHas("Elwynn Forest - Peacebloom and Silverleaf: 7 nodes"), "Rebuild reads the nodes again")

---------------------------------------------------------------------------
STEP("nodes GatherMate2 finds later")
gm:Add(E, "Herb Gathering", 1, 0.62, 0.50)
check(GP:NodeCount(route) == 8, "a new Peacebloom joins the route")
local found = false
for i = 1, 8 do
    if near(route.points[2 * i - 1], 0.62) and near(route.points[2 * i], 0.5) then found = true end
end
check(found)
check(near(route.length, GP:RouteLength(route)), "length kept up to date")
gm:Add(E, "Herb Gathering", 3, 0.62, 0.55)
check(GP:NodeCount(route) == 8, "Earthroot isn't in that route")
gm:Add(E, "Herb Gathering", 1, 0.6201, 0.5001)
check(GP:NodeCount(route) == 8, "one on top of a node already there isn't added twice")
gm:Add(W, "Herb Gathering", 1, 0.3, 0.3)
check(GP:NodeCount(route) == 8, "nor one in another zone")
gm:Delete(E, "Herb Gathering", 0.62, 0.50)
check(GP:NodeCount(route) == 7, "a node deleted in GatherMate2 leaves")
GP.db.autoAdd = false
gm:Add(E, "Herb Gathering", 1, 0.66, 0.66)
check(GP:NodeCount(route) == 7, "Add new nodes off")
GP.db.autoAdd = true

---------------------------------------------------------------------------
STEP("skip list")
GP:OpenConfig("new")
Click(ui.myZone)
check(not GP:IsSkipped("Silverleaf") and #GP:SkippedNames() == 0, "nothing skipped to start")
Click(SwitchFor("Silverleaf"))
check(SwitchFor("Silverleaf"):IsOn())
Click(SwitchFor("Silverleaf"), "RightButton")
check(GP:IsSkipped("Silverleaf") and GP.db.skip.Silverleaf == true, "right-click puts it on the skip list")
check(logHas("|cffffd100Silverleaf|r is skipped"), "says so in chat")
check(not SwitchFor("Silverleaf"):IsOn() and SwitchFor("Silverleaf").label:GetText():find("skipped", 1, true),
    "shown off and marked skipped")
check(ui.makeButton.disabled, "a skipped node alone can't make a route")
for _, e in ipairs(GP:ZoneNodes(E)) do
    if e.name == "Silverleaf" then check(e.skip, "ZoneNodes marks it") end
end
herbHead = nil
for _, h in ipairs(ui.kindHeads) do if h:IsShown() and h:GetText() == "HERBS" then herbHead = h end end
Click(herbHead.all)
check(SwitchFor("Peacebloom"):IsOn() and not SwitchFor("Silverleaf"):IsOn(), "Select all leaves it off")
check(herbHead.all:GetText() == "Clear all", "and every node that isn't skipped counts as all")
check(ui.newHint:GetText() == "Earthroot and Peacebloom", "the made-up name leaves it out")
Click(herbHead.all)
local herbsBoth = { ["Herb Gathering"] = { Peacebloom = true, Silverleaf = true } }
local peace = 0
for _, e in ipairs(GP:ZoneNodes(E)) do if e.name == "Peacebloom" then peace = e.count end end
check(peace > 0 and #GP:CollectNodes(E, herbsBoth) == peace, "no route reads its nodes")
check(GP:RouteName(E, herbsBoth) == "Peacebloom")
check(not GP:AnyPicked({ ["Herb Gathering"] = { Silverleaf = true } }), "picking only skipped nodes picks nothing")
check(GP:NewRoute({ mapID = E, kinds = { ["Herb Gathering"] = { Silverleaf = true } } }) == nil
    and logHas("pick at least one kind of node"), "so no route is made from them")
local before = GP:NodeCount(route)
local kept = { points = { unpack(route.points) }, nodes = route.nodes, length = route.length }
gm:Add(E, "Herb Gathering", 2, 0.66, 0.44)
check(GP:NodeCount(route) == before, "a new skipped node doesn't join a route that has its kind")
gm:Delete(E, "Herb Gathering", 0.66, 0.44)
check(GP:RebuildRoute(route))
RunJobs()
check(route.nodes == peace, "rebuilding a route drops the skipped nodes")
SlashCmdList.GATHERLINE("skipped")
check(logHas("skipped (right-click one on the New route tab to stop skipping it): Silverleaf"), "/gl skipped lists them")
GP:OpenConfig("new")
Click(ui.myZone)
Click(SwitchFor("Silverleaf"))
check(not GP:IsSkipped("Silverleaf") and SwitchFor("Silverleaf"):IsOn(), "clicking a skipped node unskips and picks it")
Click(SwitchFor("Silverleaf"), "RightButton")
Click(SwitchFor("Silverleaf"), "RightButton")
check(not GP:IsSkipped("Silverleaf") and logHas("is no longer skipped"), "right-click again stops skipping it")
check(GP:RebuildRoute(route))
RunJobs()
check(route.nodes == peace + 2, "and a rebuild brings it back")
GatherlineDB.skip = { Silverleaf = true, [5] = true, Junk = "yes" }
GP:LoadSettings()
check(GP:IsSkipped("Silverleaf") and #GP:SkippedNames() == 1, "the saved list comes back, junk dropped")
GP.db.skip = {}
route.points, route.nodes, route.length = kept.points, kept.nodes, kept.length   -- as the later steps expect
GP:OpenConfig("routes")

STEP("a route that passes near its nodes")
GP:NewRoute({ mapID = E, kinds = { ["Herb Gathering"] = { Peacebloom = true } }, name = "Every" })
RunJobs()
local every = GP.db.routes[#GP.db.routes]
GP:NewRoute({ mapID = E, kinds = { ["Herb Gathering"] = { Peacebloom = true } }, name = "Near", sight = 50 })
RunJobs()
local nearRoute = GP.db.routes[#GP.db.routes]
check(nearRoute.sight == 50 and nearRoute.nodes == 7, "7 nodes")
check(nearRoute.length < every.length - 100, "shorter than going to every node")
check(logHas("made |cffffd100Near|r in Elwynn Forest: 7 nodes"), "counts nodes, not stops")
GP:DeleteRoute(every)
GP:OpenConfig("routes")
local nearRow
for _, r in ipairs(ui.routeRows) do if r.route == nearRoute then nearRow = r end end
check(nearRow and nearRow.info:GetText():find("7 nodes", 1, true)
    and nearRow.info:GetText():find("a lap on foot", 1, true) and nearRow.info:GetText():find("passes within 50 yards", 1, true)
    and nearRow.info:GetText():find("\n", 1, true), "listed with its distance, on a second line")
local stopsBefore = GP:NodeCount(nearRoute)
gm:Add(E, "Herb Gathering", 1, 0.5, 0.43)
check(GP:NodeCount(nearRoute) == stopsBefore, "a new node the route already passes near isn't added")
gm:Add(E, "Herb Gathering", 1, 0.5, 0.9)
check(GP:NodeCount(nearRoute) == stopsBefore + 1 and nearRoute.nodes == 8, "a far one is")
local w, h = 1600, 1066
local added
for i = 1, GP:NodeCount(nearRoute) do
    local dx, dy = (nearRoute.points[2 * i - 1] - 0.5) * w, (nearRoute.points[2 * i] - 0.9) * h
    local d = math.sqrt(dx * dx + dy * dy)
    if d <= 50.5 and d > 1 then added = true end
end
check(added, "a stop within 50 yards of it, not on it")
gm:Delete(E, "Herb Gathering", 0.5, 0.9)
check(GP:NodeCount(nearRoute) == stopsBefore + 1, "deleting leaves it for Rebuild")
GP:DeleteRoute(nearRoute)
gm:Delete(E, "Herb Gathering", 0.5, 0.43)
check(GP:NodeCount(route) == 7, "the route to every node is back as it was")

---------------------------------------------------------------------------
STEP("rename, hide, delete")
GP:OpenConfig("routes")
local row = ui.routeRows[1]
row.name:SetFocus()
row.name:SetText("  Elwynn herbs ")
row.name:ClearFocus()
check(route.name == "Elwynn herbs", "renamed (spaces trimmed)")
row.name:SetFocus()
row.name:SetText("   ")
row.name:ClearFocus()
check(route.name == "Elwynn herbs" and row.name:GetText() == "Elwynn herbs", "a blank name is ignored")
row.name:SetFocus()
row.name:SetText("copper vein")
row.name:ClearFocus()
check(route.name == "Elwynn herbs" and row.name:GetText() == "Elwynn herbs"
    and logHas("already a route called |cffffd100copper vein|r"), "not to another route's name")
check(GP:RenameRoute(route, "ELWYNN HERBS") and route.name == "ELWYNN HERBS", "its own name in new case is fine")
GP:RenameRoute(route, "Elwynn herbs")
Click(row.show)
check(route.shown == false and not row.show:IsOn(), "hidden")
Click(row.show)
check(route.shown)
Click(ui.routeRows[2].delete)
check(GP.confirmWindow:IsShown() and #GP.db.routes == 2, "asks first")
Click(GP.confirmWindow.yes)
check(#GP.db.routes == 1 and GP.db.routes[1] == route, "deleted")
check(not ui.routeRows[2]:IsShown(), "and gone from the list")

STEP("edit a route")
GP:OpenConfig("routes")
local color, id = route.color, route.id
Click(ui.routeRows[1].edit)
local newPage = GP.config.pages.new
check(GP.config.currentTab == "new" and newPage.title:GetText() == "Edit route", "Edit opens the route's options")
check(ui.newZone.getter() == E and ui.newName:GetText() == "Elwynn herbs", "its zone and name")
check(SwitchFor("Peacebloom"):IsOn() and SwitchFor("Silverleaf"):IsOn() and not SwitchFor("Copper Vein"):IsOn(), "its nodes")
check(ui.sightSlider:GetValue() == 0, "its pass within")
check(ui.makeButton:GetText() == "Save changes" and ui.cancelButton:IsShown())
Click(SwitchFor("Silverleaf"))
Click(ui.cancelButton)
check(GP.config.currentTab == "routes" and route.kinds["Herb Gathering"].Silverleaf and not GP:Busy(), "Cancel leaves it")
GP:OpenConfig("new")
check(newPage.title:GetText() == "New route" and ui.newZone.getter() == nil and ui.newName:GetText() == ""
    and ui.makeButton:GetText() == "Make route", "New route is blank again after an edit")

GP:NewRoute({ mapID = E, kinds = { Mining = { ["Copper Vein"] = true } } })
RunJobs()
local copper = GP.db.routes[2]
GP:OpenConfig("routes")
Click(ui.routeRows[1].edit)
ui.newName:SetText("copper vein")
Click(ui.makeButton)
check(GP.config.currentTab == "new" and not GP:Busy() and route.name == "Elwynn herbs"
    and logHas("already a route called |cffffd100copper vein|r"), "not to another route's name")
check(SwitchFor("Peacebloom"):IsOn() and ui.newName:GetText() == "copper vein", "and keeps what was picked")

ui.newName:SetText("Just Peacebloom")
Click(SwitchFor("Silverleaf"))
ui.sightSlider:SetValue(50)
Click(ui.makeButton)
check(GP:Busy() and route.working and GP.config.currentTab == "routes", "Save changes works it out again")
check(ui.routeRows[1].edit.disabled, "no Edit while it's being worked out")
RunJobs()
check(#GP.db.routes == 2 and route.name == "Just Peacebloom" and route.sight == 50 and route.nodes == 7
    and not route.kinds["Herb Gathering"].Silverleaf, "changed in place")
check(route.id == id and route.color == color and GP.db.routes[1] == route, "the same route, same color")
check(logHas("changed |cffffd100Just Peacebloom|r in Elwynn Forest: 7 nodes"), "says so in chat")
check(not ui.routeRows[1].edit.disabled)

Click(ui.routeRows[1].edit)
ui.newName:SetText("")
Click(SwitchFor("Silverleaf"))
ui.sightSlider:SetValue(0)
Click(ui.makeButton)
RunJobs()
check(route.name == "Elwynn Forest - Peacebloom and Silverleaf" and GP:NodeCount(route) == #GP:CollectNodes(E, route.kinds),
    "a blank name is made from the nodes")
check(GP:EditRoute(route, { kinds = route.kinds, name = "Elwynn herbs", sight = 0 }))
RunJobs()
check(route.name == "Elwynn herbs" and route.mapID == E, "its own zone when none is given")
check(GP:EditRoute(route, { kinds = route.kinds, name = " elwynn HERBS", sight = 0 }), "keeping its own name is fine")
RunJobs()
check(route.name == "elwynn HERBS")
GP:RenameRoute(route, "Elwynn herbs")

local before = route.points
check(GP:EditRoute(route, { mapID = E, kinds = { Mining = { ["Tin Vein"] = true } }, name = "Tin" }))
RunJobs()
check(route.points == before and route.name == "Elwynn herbs" and route.kinds["Herb Gathering"].Peacebloom
    and route.sight == 0 and logHas("was left as it was"), "no nodes there: left as it was")
check(not GP:EditRoute(route, { kinds = {} }) and logHas("pick at least one"), "nothing picked: no change")

GP:OpenConfig("routes")
Click(ui.routeRows[2].edit)
GP:DeleteRoute(copper)
check(ui.newZone.getter() == nil and newPage.title:GetText() == "New route", "the route deleted meanwhile: blank")
GP:OpenConfig("routes")

STEP("hide every line from the minimap button")
Click(GP.minimapButton, "RightButton")
check(not GP.db.worldMap and not GP.db.minimap, "all off")
Click(GP.minimapButton, "RightButton")
check(GP.db.worldMap and GP.db.minimap, "back on")
GP.db.minimap = false
SlashCmdList.GATHERLINE("hide")
check(not GP.db.worldMap and not GP.db.minimap)
SlashCmdList.GATHERLINE("show")
check(GP.db.worldMap and GP.db.minimap == false, "back as they were")
GP.db.minimap = true

STEP("display tab")
GP:OpenConfig("display")
Click(ui.minimapSwitch)
check(GP.db.minimap == false)
Click(ui.minimapSwitch)
check(GP.db.minimap == true)

STEP("restore defaults on the display tab")
local routesBefore, angleBefore = #GP.db.routes, GP.db.minimapAngle
GP.db.minimapAngle = 123
GP.db.sight = 40
Click(GP.minimapButton, "RightButton")   -- lines hidden from the minimap button
GP.db.worldWidth, GP.db.minimapAlpha, GP.db.rangeYards = 9, 20, 180
GP.db.worldRouteColor, GP.db.arrows, GP.db.arrowsReverse, GP.db.joinLine = false, false, true, false
GP.db.range, GP.db.autoAdd, GP.db.minimapButton = true, false, false
GP:SetLineColor("minimap", 0.1, 0.2, 0.3)
GP.db.rangeColor = { 0, 0, 0 }
GP:UpdateMinimapButton()
check(ui.restoreDefaults, "a Restore defaults button")
Click(ui.restoreDefaults)
check(GP.confirmWindow:IsShown() and GP.db.worldWidth == 9, "asks first")
Click(GP.confirmWindow.no)
check(GP.db.worldWidth == 9, "Cancel changes nothing")
Click(ui.restoreDefaults)
Click(GP.confirmWindow.yes)
for _, k in ipairs(GP.DISPLAY_KEYS) do
    local v, d = GP.db[k], GP.DEFAULTS[k]
    if type(d) == "table" then
        check(v ~= d and v[1] == d[1] and v[2] == d[2] and v[3] == d[3], k .. " back to its default (a copy)")
    else
        check(v == d, k .. " back to its default")
    end
end
local listed = {}
for _, k in ipairs(GP.DISPLAY_KEYS) do listed[k] = true end
local notOnTab = { minimapAngle = true, sight = true, nextColor = true, tabooShow = true, navLaps = true, walkRoutes = true, navReach = true, navAhead = true, navLabel = true, navRespawn = true, onlyGatherable = true }
for k in pairs(GP.DEFAULTS) do
    check(listed[k] or notOnTab[k], k .. ": every setting on the tab is restored")
end
check(GP.db.hiddenWas == nil and GP.db.worldMap and GP.db.minimap, "hidden lines shown again")
check(GP.minimapButton:IsShown(), "the minimap button back")
check(#GP.db.routes == routesBefore and GP.db.minimapAngle == 123 and GP.db.sight == 40,
    "routes, the button's place and New route's slider kept")
GP.db.minimapAngle, GP.db.sight = angleBefore, GP.DEFAULTS.sight
GP:SetLineColor("minimap", 0.5, 0.5, 0.5)
check(GP.DEFAULTS.minimapColor[1] == 1, "changing a color after doesn't touch the defaults")
GP:RestoreDefaults()

STEP("range circle on the minimap")
check(GP.db.range == false and #Shown(GP.mm.ring) == 0, "off to start")
check(GP.db.rangeYards == 100 and ui.rangeYards and ui.rangeAlpha, "100 yards, with sliders")
Click(ui.rangeSwitch)
check(GP.db.range == true)
local ring = Shown(GP.mm.ring)
check(#ring == 64, "a full circle: the minimap shows 150 yards, so 100 fits")
local r = 100 * 70 / 150
for _, l in ipairs(ring) do
    check(near(math.sqrt(l.__from[1] ^ 2 + l.__from[2] ^ 2), r, 0.01), "100 yards from you")
end
local rc = GP.db.rangeColor
check(ring[1].__color[1] == rc[1] and near(ring[1].__color[4], 0.6), "in its color and opacity")
check(ui.rangeColor.fill.__color[1] == rc[1], "the square shows the color")
GP.db.rangeColor, GP.db.rangeAlpha = { 1, 0, 0.5 }, 30
GP:Changed()
ring = Shown(GP.mm.ring)
check(ring[1].__color[1] == 1 and ring[1].__color[3] == 0.5 and near(ring[1].__color[4], 0.3), "a new color and opacity")
check(ui.rangeColor.fill.__color[3] == 0.5)
Click(ui.minimapSwitch)
check(#Shown(GP.mm.pool) == 0 and #Shown(GP.mm.ring) == 64, "stays with the route lines off")
Click(ui.minimapSwitch)
GP.db.rangeYards = 200
GP:Changed()
check(#Shown(GP.mm.ring) == 0, "beyond the minimap's edge: nothing drawn")
VIEW_RADIUS = 300
GP:DrawMinimap()
check(#Shown(GP.mm.ring) == 64, "zoomed out it's back without forcing a redraw")
VIEW_RADIUS = 150
GP.db.rangeYards = 100
Click(ui.rangeSwitch)
check(#Shown(GP.mm.ring) == 0, "and off again")
GP.db.rangeColor, GP.db.rangeAlpha = { 0.25, 0.80, 1.00 }, 60

STEP("line color and opacity, each map on its own")
WorldMapFrame:SetMapID(E)
PLAYER.x, PLAYER.y = 0.5, 0.5
local herbs = GP.db.routes[1]
local function firstLine(pool) return Shown(pool)[1] end
GP:Changed()
check(GP.db.worldRouteColor and GP.db.minimapRouteColor, "routes keep their own color to start")
check(ui.worldColor.disabled and ui.minimapColor.disabled, "so the one-color squares are greyed out")
check(firstLine(pin.pool).__color[1] == herbs.color[1], "world map: the route's color")
Click(ui.worldRouteColor)
check(GP.db.worldRouteColor == false and not ui.worldColor.disabled, "own color off: the square can be clicked")
GP:SetLineColor("world", 0.1, 0.2, 0.3)
local c = firstLine(pin.pool).__color
check(c[1] == 0.1 and c[2] == 0.2 and c[3] == 0.3, "world map lines take the picked color")
check(ui.worldColor.fill.__color[1] == 0.1, "and the square shows it")
local m = firstLine(GP.mm.pool)
check(m and m.__color[1] == herbs.color[1], "the minimap keeps the route's color")
GP.db.worldAlpha = 40
GP:Changed()
check(near(firstLine(pin.pool).__color[4], 0.4), "world map opacity")
check(near(firstLine(GP.mm.pool).__color[4], 0.85), "the minimap's opacity is its own")
Click(ui.minimapRouteColor)
GP:SetLineColor("minimap", 0.9, 0.8, 0.7)
GP.db.minimapAlpha = 60
GP:Changed()
c = firstLine(GP.mm.pool).__color
check(c[1] == 0.9 and c[3] == 0.7 and near(c[4], 0.6), "minimap lines take their own color and opacity")
check(firstLine(pin.pool).__color[1] == 0.1, "world map unchanged")
Click(ui.worldRouteColor)
check(firstLine(pin.pool).__color[1] == herbs.color[1], "own color back on")
Click(ui.minimapRouteColor)
GP.db.worldAlpha, GP.db.minimapAlpha = 85, 85
GP:Changed()

STEP("direction arrows")
-- spacing along the loop, pure: a 100 x 100 square, an arrow every 100 pixels
local marks = GP.ArrowMarks({ 0, 100, 100, 0 }, { 0, 0, 100, 100 }, 4, 100)
check(#marks == 4, "one arrow per 100 pixels of the way round")
check(marks[1][1] == 50 and marks[1][2] == 0 and marks[1][3] == 1 and marks[1][4] == 0, "half a spacing in, pointing along the leg")
check(marks[2][1] == 100 and marks[2][2] == 50 and marks[2][4] == 1, "then round the corner")
check(marks[4][1] == 0 and marks[4][2] == 50 and marks[4][4] == -1, "and back to the start")
marks = GP.ArrowMarks({ 0, 100, 100, 0 }, { 0, 0, 100, 100 }, 4, 100, true)
check(#marks == 4 and marks[1][1] == 0 and marks[1][2] == 50 and marks[1][4] == 1, "reversed: the other way round")
check(#GP.ArrowMarks({ 0, 100, 100, 0 }, { 0, 0, 100, 100 }, 4, 40) == 10, "closer together")
check(#GP.ArrowMarks({ 0, 100 }, { 0, 0 }, 2, 10) == 0, "there and back (two stops): no arrows")
check(#GP.ArrowMarks({ 0, 0, 0 }, { 0, 0, 0 }, 3, 10) == 0, "stops on top of each other: no arrows")

check(GP.db.arrows == true and GP.db.arrowsReverse == false, "on to start, not reversed")
check(ui.arrowsSwitch and ui.arrowsReverse, "two switches on Display")
local herbPoints = herbs.points
herbs.points = { 0.4, 0.4, 0.6, 0.4, 0.6, 0.7, 0.4, 0.7 }
local wasShown = {}
for i, r in ipairs(GP.db.routes) do wasShown[i] = r.shown; r.shown = (r == herbs) end
WorldMapFrame:SetMapID(E)
GP:Changed()
local wa = Shown(pin.arrows)
check(#wa == 20, "world map: an arrow (two lines) every 80 pixels of an 800-pixel loop")
check(#Shown(pin.pool) == 4, "and the route's own lines are unchanged")
-- the first arrow sits 40 pixels along the top edge, pointing east (right)
check(near(wa[1].__to[1], 440 + 6, 0.01) and near(wa[1].__to[2], -266.8, 0.01), "the tip, ahead of its middle")
check(near(wa[1].__from[1], 440 - 6, 0.01) and near(math.abs(wa[1].__from[2] + 266.8), 7.2, 0.01), "the wings behind it")
check(wa[1].__to[1] == wa[2].__to[1] and wa[1].__to[2] == wa[2].__to[2], "two lines meeting at the tip")
check(wa[1].__color[1] == herbs.color[1] and near(wa[1].__color[4], 0.85) and wa[1].__thickness == 4,
    "in the line's color, opacity and width")
Click(ui.arrowsReverse)
check(GP.db.arrowsReverse == true)
wa = Shown(pin.arrows)
-- reversed, the first leg runs from the first stop down the west edge
check(#wa == 20 and near(wa[1].__to[1], 400, 0.01) and wa[1].__to[2] < wa[1].__from[2], "reversed: pointing down (south)")
Click(ui.arrowsReverse)

-- minimap: a square 50 yards round you, 23.3 pixels each way
local a, b = 50 / 1600, 50 / 1066
herbs.points = { 0.5 - a, 0.5 - b, 0.5 + a, 0.5 - b, 0.5 + a, 0.5 + b, 0.5 - a, 0.5 + b }
PLAYER.x, PLAYER.y = 0.5, 0.5
GP:Changed()
local ma = Shown(GP.mm.arrows)
local edge = 50 * 70 / 150
check(#ma == 10, "minimap: an arrow every 40 pixels of a 187-pixel loop")
check(near(ma[1].__to[1], -edge + 20 + 4.5, 0.01) and near(ma[1].__to[2], edge, 0.01), "the first along the north edge, pointing east")
check(ma[1].__thickness == 3, "as wide as the minimap's lines")
for _, l in ipairs(ma) do check(inside(l.__from[1], l.__from[2]) and inside(l.__to[1], l.__to[2]), "inside the minimap") end
GP.db.arrowsReverse = true
GP:DrawMinimap()
ma = Shown(GP.mm.arrows)
check(near(ma[1].__to[1], -edge, 0.01) and ma[1].__to[2] < ma[1].__from[2], "reversed without forcing a redraw: pointing south")
GP.db.arrowsReverse = false
-- an arrow that would stick out past the edge isn't drawn
herbs.points = { 0.5 - 3 * a, 0.5 - b, 0.5 + 3 * a, 0.5 - b, 0.5, 0.5 + b }
GP:Changed()
for _, l in ipairs(Shown(GP.mm.arrows)) do
    check(inside(l.__from[1], l.__from[2]) and inside(l.__to[1], l.__to[2]), "only arrows wholly on the minimap")
end
check(#Shown(GP.mm.arrows) > 0, "the ones inside still are")
Click(ui.arrowsSwitch)
check(GP.db.arrows == false and #Shown(GP.mm.arrows) == 0 and #Shown(pin.arrows) == 0, "off: no arrows anywhere")
check(#Shown(GP.mm.pool) > 0 and #Shown(pin.pool) > 0, "the lines stay")
Click(ui.arrowsSwitch)
check(#Shown(GP.mm.arrows) > 0, "back on")
Click(ui.minimapSwitch)
check(#Shown(GP.mm.arrows) == 0, "minimap lines off: its arrows go too")
Click(ui.minimapSwitch)
herbs.points = herbPoints
for i, r in ipairs(GP.db.routes) do r.shown = wasShown[i] end
GP:Changed()

STEP("time for a lap")
local lapRoute = { mapID = E, points = {}, length = 700 }
GP.db.speed = nil
check(GP:Speed() == 7 and GP:LapTime(lapRoute) == "about 2 min", "on foot: 7 yards a second")
lapRoute.length = 300
check(GP:LapTime(lapRoute) == "under a minute")
lapRoute.length = 7 * 60 * 75
check(GP:LapTime(lapRoute) == "about 1 h 15 min", "hours and minutes")
UNIT_SPEED = 7
check(GP:SampleSpeed() == false and GP.db.speed == nil, "on foot: nothing remembered")
UNIT_SPEED = 14
check(GP:SampleSpeed() == true and GP.db.speed == 14, "mounted: its speed is remembered")
check(GP:SampleSpeed() == false, "the same speed again: no change")
lapRoute.length = 14 * 60 * 6
check(GP:LapTime(lapRoute) == "about 6 min", "laps at that speed")
UNIT_SPEED = 7
GP:SampleSpeed()
check(GP.db.speed == 14, "kept after you get off")
UNIT_SPEED = SECRET
check(GP:SampleSpeed() == false and GP.db.speed == 14, "a hidden speed is left alone")
UNIT_SPEED = 7
GP:OpenConfig("routes")
local lapRow = ui.routeRows[1]
check(lapRow.info:GetText():find("\nAbout %d+ min a lap") or lapRow.info:GetText():find("\nUnder a minute a lap"),
    "the Routes tab shows it on the second line")
check(not lapRow.info:GetText():find("on foot", 1, true), "mounted speed known: no 'on foot'")
GP.db.speed = nil
GP:RefreshConfig()
check(lapRow.info:GetText():find("a lap on foot", 1, true), "otherwise it says on foot")

STEP("line to the route on the minimap")
local nx, ny, nd = GP.NearestOnLoop({ 0, 100, 100 }, { 10, 10, 50 }, 3, 50, 0)
check(nx == 50 and ny == 10 and nd == 10, "the nearest point can be along a leg")
nx, ny, nd = GP.NearestOnLoop({ 0, 100 }, { 10, 10 }, 2, -30, 50)
check(nx == 0 and ny == 10 and nd == 50, "or a stop")
check(GP.db.joinLine == true and ui.joinSwitch, "on to start, with a switch")
local wasShown2 = {}
for i, r in ipairs(GP.db.routes) do wasShown2[i] = r.shown; r.shown = (r == herbs) end
local herbPoints2 = herbs.points
-- a loop 100 yards north of you: 46.7 pixels up
local yn = 100 / 1066
herbs.points = { 0.45, 0.5 - yn, 0.55, 0.5 - yn, 0.5, 0.5 - 3 * yn }
PLAYER.x, PLAYER.y = 0.5, 0.5
GP:Changed()
local jl = Shown(GP.mm.join)
check(#jl > 2, "dashes toward the route")
local up = 100 * 70 / 150
for _, l in ipairs(jl) do
    check(near(l.__from[1], 0, 0.01) and near(l.__to[1], 0, 0.01) and l.__to[2] > l.__from[2], "straight up (north)")
    check(l.__to[2] <= up + 0.01, "no further than the route")
end
check(near(jl[1].__from[2], 0, 0.01) and near(jl[1].__to[2], 6, 0.01) and near(jl[2].__from[2], 10, 0.01), "6 on, 4 off")
check(jl[1].__color[1] == herbs.color[1] and jl[1].__thickness == 2, "the route's color, a little thinner")
-- far away (500 yards north): dashes go to the minimap's edge
yn = 500 / 1066
herbs.points = { 0.45, 0.5 - yn, 0.55, 0.5 - yn, 0.5, 0.5 - 2 * yn }
GP:Changed()
jl = Shown(GP.mm.join)
check(#jl > 0 and jl[#jl].__to[2] > 69 - 10 and jl[#jl].__to[2] <= 69.01, "a route off the minimap: up to its edge")
-- on the route: no line
yn = 10 / 1066
herbs.points = { 0.45, 0.5 - yn, 0.55, 0.5 - yn, 0.5, 0.5 - 30 * yn }
GP:Changed()
check(#Shown(GP.mm.join) == 0, "within 20 yards of the route: no line")
herbs.points = { 0.45, 0.5 - 100 / 1066, 0.55, 0.5 - 100 / 1066, 0.5, 0.5 - 300 / 1066 }
GP:Changed()
check(#Shown(GP.mm.join) > 0)
Click(ui.joinSwitch)
check(GP.db.joinLine == false and #Shown(GP.mm.join) == 0, "switched off")
GP.db.joinLine = true
GP:DrawMinimap()
check(#Shown(GP.mm.join) > 0, "back on, without forcing a redraw")
Click(ui.minimapSwitch)
check(#Shown(GP.mm.join) == 0, "minimap lines off: it goes too")
Click(ui.minimapSwitch)
PLAYER.x = 0.5 + 0.0005
GP:DrawMinimap()
check(#Shown(GP.mm.join) > 0, "follows you as you move")
PLAYER.x = 0.5
herbs.points = herbPoints2
for i, r in ipairs(GP.db.routes) do r.shown = wasShown2[i] end
GP:Changed()

---------------------------------------------------------------------------
STEP("no-go areas")
do
    local r1 = GP.db.routes[1]
    local kept = { points = { unpack(r1.points) }, nodes = r1.nodes, length = r1.length, kinds = r1.kinds, sight = r1.sight }
    -- a route to every Peacebloom and Silverleaf, straight through the middle
    r1.kinds, r1.sight = { ["Herb Gathering"] = { Peacebloom = true, Silverleaf = true } }, 0
    check(GP:RebuildRoute(r1))
    RunJobs()
    local before = r1.nodes
    local function legsThrough(route, mapID)
        local walls = GP.WallsFor(mapID)
        local w, h = GP:MapYards(mapID)
        local p, n, bad = route.points, GP:NodeCount(route), 0
        for i = 1, n do
            local j = i % n + 1
            if walls:Blocked({ p[2 * i - 1] * w, p[2 * i] * h }, { p[2 * j - 1] * w, p[2 * j] * h }) then bad = bad + 1 end
        end
        return bad
    end

    -- the window: a Taboo areas tab
    GP:OpenConfig("taboo")
    check(GP.config.currentTab == "taboo" and ui.tabooZone.getter() == E, "a No-go areas tab, on your zone")
    check(ui.tabooEmpty:GetText():find("No no-go areas in Elwynn Forest", 1, true), "none yet")
    check(ui.tabooShow:IsOn(), "shown on the world map to start")

    -- draw one: a band down the middle, over the Peacebloom at 0.5, 0.4
    IN_COMBAT = true
    check(not GP:StartTaboo(E) and logHas("in combat"), "not in combat")
    IN_COMBAT = false
    Click(ui.tabooDraw)
    check(GP.drawing and GP.drawing.mapID == E, "drawing in Elwynn")
    check(WorldMapFrame:IsShown() and WorldMapFrame:GetMapID() == E, "on the world map, on that zone")
    check(not GP.config:IsShown(), "the window gets out of the way")
    check(GP.drawBar:IsShown() and GP.drawBar.finish.disabled, "a bar on the map; Finish waits for 3 corners")
    check(ClickMap("LeftButton", 0.47, 0.30) and ClickMap("LeftButton", 0.53, 0.30), "left-clicks are corners")
    check(GP.drawBar.title:GetText():find("2 corners", 1, true))
    check(ClickMap("LeftButton", 0.9, 0.9) and ClickMap("RightButton"), "right-click takes the last one back")
    check(#GP.drawing.pts == 4)
    ClickMap("LeftButton", 0.53, 0.58)
    ClickMap("LeftButton", 0.47, 0.58)
    check(not GP.drawBar.finish.disabled and GP.drawBar.title:GetText():find("4 corners", 1, true), "Finish with 3 or more")
    check(#Shown(GP.provider.pin.draft) >= 3, "the corners so far are drawn, on to the cursor")
    WorldMapFrame:SetMapID(W)
    check(not ClickMap("LeftButton", 0.2, 0.2), "on another map clicks work as usual")
    check(GP.drawBar.help:GetText():find("Go back to Elwynn Forest", 1, true), "and the bar says where to go")
    WorldMapFrame:SetMapID(E)
    Click(GP.drawBar.finish)
    check(not GP.drawing and not GP.drawBar:IsShown() and #(WorldMapFrame.__clickHandlers or {}) == 0,
        "Finish keeps it and stops taking clicks")
    check(#GP:Taboos(E) == 1 and #GP:Taboos(E)[1] == 8, "saved with its 4 corners")
    check(GP.config:IsShown() and GP.config.currentTab == "taboo", "back on the No-go areas tab")
    check(ui.tabooRows[1]:IsShown() and ui.tabooRows[1].text:GetText():find("Area 1", 1, true)
        and ui.tabooRows[1].text:GetText():find("4 corners, about 96 x 298 yards", 1, true), "listed with its size")
    check(GP:Busy() or #(GP.queue or {}) > 0, "the zone's routes are worked out again")
    RunJobs()
    check(r1.nodes == before - 1 and r1.taboo == 1, "the node inside is left out")
    check(logHas("1 node in a no-go area left out"), "and chat says so")
    check(legsThrough(r1, E) == 0, "no leg goes through the area")
    check(GP:NodeCount(r1) > r1.nodes, "it bends round its corners instead")
    check(GP:InTaboo(E, 0.5, 0.45) and not GP:InTaboo(E, 0.4, 0.45) and not GP:InTaboo(W, 0.5, 0.45))
    check(near(r1.length, GP:RouteLength(r1)), "the length is the way round")

    -- on the world map: outline and hatching
    GP:DrawWorldMap()
    local hatch = #Shown(GP.provider.pin.taboo)
    check(hatch > 4, "drawn red and hatched on the world map (" .. hatch .. " lines)")
    Click(ui.tabooShow)
    check(not GP.db.tabooShow and #Shown(GP.provider.pin.taboo) == 0, "or not")
    Click(ui.tabooShow)
    local spans = GP.HatchSpans({ 0, 100, 100, 0 }, { 0, 0, -100, -100 }, 4, 10)
    check(#spans >= 18, "hatch lines across a square")
    for _, sp in ipairs(spans) do
        check(sp[1] >= -0.01 and sp[3] <= 100.01 and near(sp[1] + sp[2], sp[3] + sp[4]), "inside it, on the diagonal")
    end

    -- nodes found later
    local stops = GP:NodeCount(r1)
    gm:Add(E, "Herb Gathering", 1, 0.50, 0.50)
    check(GP:NodeCount(r1) == stops, "a node found inside an area doesn't join")
    gm:Add(E, "Herb Gathering", 1, 0.56, 0.35)
    check(GP:NodeCount(r1) > stops and legsThrough(r1, E) == 0, "one outside does, going round")
    gm:Delete(E, "Herb Gathering", 0.56, 0.35)
    check(legsThrough(r1, E) == 0, "and when it's deleted the line still goes round")
    gm:Delete(E, "Herb Gathering", 0.50, 0.50)

    -- a node deleted between two stops on either side: they meet round the area
    local hand = { id = 900, mapID = E, name = "By hand", kinds = { ["Herb Gathering"] = { Peacebloom = true } }, sight = 0,
        color = { 1, 1, 1 }, shown = true, points = { 0.30, 0.45, 0.50, 0.75, 0.70, 0.45, 0.50, 0.15 } }
    table.insert(GP.db.routes, hand)
    check(legsThrough(hand, E) == 0, "(clear to start)")
    gm:Add(E, "Herb Gathering", 1, 0.50, 0.75, true)
    gm:Delete(E, "Herb Gathering", 0.50, 0.75)
    check(GP:NodeCount(hand) > 3 and legsThrough(hand, E) == 0, "a deleted node's neighbours meet round the area")
    -- a new node whose cheapest place is across the area: its leg bends round too
    hand.points = { 0.30, 0.45, 0.50, 0.15 }
    gm:Add(E, "Herb Gathering", 1, 0.70, 0.50)
    check(GP:NodeCount(hand) > 3 and legsThrough(hand, E) == 0, "a new node's legs go round the area")
    gm:Delete(E, "Herb Gathering", 0.70, 0.50)
    GP:DeleteRoute(hand)

    -- one whose edges cross is turned down; Cancel keeps nothing
    check(not GP:AddTaboo(E, { 0.1, 0.1, 0.2, 0.2, 0.2, 0.1, 0.1, 0.2 }) and logHas("edges cross"), "a bow tie isn't an area")
    check(not GP:AddTaboo(E, { 0.1, 0.1, 0.2, 0.2 }), "nor 2 corners")
    GP:StartTaboo(E)
    ClickMap("LeftButton", 0.1, 0.1); ClickMap("LeftButton", 0.2, 0.1); ClickMap("LeftButton", 0.2, 0.2)
    Click(GP.drawBar.cancel)
    check(not GP.drawing and #GP:Taboos(E) == 1 and #(WorldMapFrame.__clickHandlers or {}) == 0, "Cancel keeps nothing")
    check(not ClickMap("RightButton"), "right-click on the map zooms out again")

    -- saved, and junk dropped
    GatherlineDB.taboos[99] = { { 0.1, 0.1 }, "junk", { 0.1, 0.1, 0.2, "x", 0.3, 0.3 } }
    GatherlineDB.taboos.junk = { { 0.1, 0.1, 0.2, 0.1, 0.2, 0.2 } }
    GP:LoadSettings()
    check(#GP:Taboos(E) == 1 and GP.db.taboos[99] == nil and GP.db.taboos.junk == nil, "the area comes back, junk doesn't")

    -- delete it from the tab
    GP:OpenConfig("taboo")
    Click(ui.tabooRows[1].del)
    check(GP.confirmWindow:IsShown())
    Click(GP.confirmWindow.yes)
    check(#GP:Taboos(E) == 0 and GP.db.taboos[E] == nil, "deleted")
    RunJobs()
    check(r1.nodes == before and (r1.taboo or 0) == 0, "and the route takes the node in again")
    check(not ui.tabooRows[1]:IsShown() and ui.tabooEmpty:GetText():find("No no-go areas", 1, true))

    r1.points, r1.nodes, r1.length, r1.kinds, r1.sight, r1.taboo = kept.points, kept.nodes, kept.length, kept.kinds, kept.sight, nil
    GP:OpenConfig("routes")
end

---------------------------------------------------------------------------
STEP("saved routes come back, and junk is dropped")
local saved = GatherlineDB
saved.routes[#saved.routes + 1] = "junk"
saved.routes[#saved.routes + 1] = { mapID = E }
saved.worldWidth = 99
GP:LoadSettings()
check(#GP.db.routes == 1 and GP.db.routes[1].name == "Elwynn herbs", "the real route stays")
check(GP.db.worldWidth == 10, "out-of-range settings are kept in range")
saved.rangeYards, saved.rangeColor = 999, "junk"
GP:LoadSettings()
check(GP.db.rangeYards == 200 and GP.db.rangeColor[2] == 0.80, "the range circle's settings too")
saved.sight, saved.sight100 = 50, nil
GP:LoadSettings()
check(GP.db.sight == GP.DEFAULTS.sight, "1.1.0's 50 yards becomes the default")
GP.db.sight = 50
GP:LoadSettings()
check(GP.db.sight == 50, "but 50 picked later stays")
local points = #GP.db.routes[1].points
GP.db.routes[1].merge, GP.db.merge = 20, 20   -- from before 1.3.0
GP:LoadSettings()
check(GP.db.routes[1].merge == nil and GP.db.merge == nil, "the old merge setting is gone")
check(#GP.db.routes[1].points == points, "and the route's loop is left as it was")
saved.alpha, saved.worldAlpha, saved.minimapAlpha = 50, nil, nil   -- one Opacity before 1.5.0
saved.worldColor, saved.minimapColor = "junk", { 2, -1, 0.5 }
GP:LoadSettings()
check(GP.db.worldAlpha == 50 and GP.db.minimapAlpha == 50 and GP.db.alpha == nil, "the old opacity carries over to both")
check(GP.db.worldColor[1] == 1 and GP.db.worldColor[2] == 0.82, "a broken color goes back to gold")
local mc = GP.db.minimapColor
check(mc[1] == 1 and mc[2] == 0 and mc[3] == 0.5, "a color is kept between 0 and 1")
saved.alpha = 30
GP:LoadSettings()
check(GP.db.worldAlpha == 50, "but only once")

STEP("riding a route with Shortest Path Forever")
do
    local route = GP.db.routes[1]
    local n = GP:NodeCount(route)
    check(n >= 6, "a route with a few stops to ride")
    check(not GP:CanNavigate() and not GP:StartNav(route) and logHas("needs |cffffd100Shortest Path Forever"),
        "without Shortest Path: no guidance")

    local tickers = {}
    C_Timer = C_Timer or {}
    C_Timer.NewTicker = function(_, fn)
        local t = { fn = fn }
        function t:Cancel() self.cancelled = true end
        tickers[#tickers + 1] = t
        return t
    end
    local function Tick() for _, t in ipairs(tickers) do if not t.cancelled then t.fn() end end end

    local fake = { sent = 0 }
    local api = { version = 2 }
    function api.NavigateRoute(owner, stops)
        if IN_COMBAT then return false end
        fake.owner, fake.stops, fake.cur, fake.ended = owner, stops, 1, nil
        fake.sent = fake.sent + 1
        return true
    end
    function api.CurrentStop(owner)
        if fake.cur and owner == fake.owner then return fake.cur end
        return nil, "none"
    end
    function api.Ended() if fake.ended then return fake.ended, 0 end return nil, "none" end
    function api.Cancel(owner)
        if fake.cur and owner == fake.owner then fake.cur, fake.ended = nil, "cancelled" return true end
        return false
    end
    function api.Estimate(fm, fx, fy, tm, tx, ty) return math.abs(tx - 0.9) * 1000 + math.abs(ty - 0.1) * 1000 end
    function api.Subscribe(cb) fake.cb = cb return function() fake.cb = nil end end
    ShortestPathForever = { API = api }
    local function Arrive()
        if fake.cur < #fake.stops then fake.cur = fake.cur + 1 else fake.cur, fake.ended = nil, "arrived" end
        Tick()
    end
    local function Stop(k) return fake.stops[k].x, fake.stops[k].y end
    local function Same(ax, ay, bx, by) return near(ax, bx) and near(ay, by) end
    local pts = route.points
    local function StopXY(i) return pts[2 * i - 1], pts[2 * i] end

    check(GP:CanNavigate(), "Shortest Path's API found")
    PLAYER.map = route.mapID
    -- stand on stop 3: that's where you join
    PLAYER.x, PLAYER.y = StopXY(3)
    GP.db.arrowsReverse = false
    GP.db.navLabel = "number"
    check(GP:StartNav(route, 1), "start one lap")
    check(GP:IsNavigating(route) and fake.owner == "Gatherline", "riding, as Gatherline")
    local ahead = math.min(GP.db.navAhead, n + 1)
    check(#fake.stops == ahead, "the first stops handed over")
    check(Same(fake.stops[1].x, fake.stops[1].y, StopXY(3)), "joining at the nearest stop")
    check(Same(fake.stops[2].x, fake.stops[2].y, StopXY(4)), "then on the way the arrows point")
    check(fake.stops[1].map == route.mapID and fake.stops[1].title == ("Stop 1/%d"):format(n)
        and fake.stops[1].tooltip:find(route.name, 1, true) == 1, "stops on the route's map, called Wegpunkt k/n")
    -- called by what's there: the node names nearest each stop
    local labels = GP:StopLabels(route)
    local any = false
    for i = 1, n do if labels[i] then any = true; check(labels[i]:find("Peacebloom") or labels[i]:find("Silverleaf"), "herb names") end end
    check(any, "stops name what's there")
    GP.db.navLabel = "nodes"
    check(GP:StopTitle(3, 9, "Kupfervorkommen ×2") == "Kupfervorkommen ×2" and GP:StopTitle(3, 9, nil) == "Stop 3/9",
        "what's there, or the number for a stop with nothing")
    GP.db.navLabel = "both"
    check(GP:StopTitle(3, 9, "Kupfervorkommen ×2") == "3/9: Kupfervorkommen ×2", "both")
    GP.db.navLabel = "number"
    check(GP:StopTitle(3, 9, "Kupfervorkommen ×2") == "Stop 3/9", "number")
    GP:OpenConfig("riding")
    check(GP.config.currentTab == "riding" and GP.ui.navLabel and GP.ui.navReach, "the Riding tab")
    GP:OpenConfig("routes")
    check(GP.ui.rideButtons[1]:GetText() == "Stop", "the row's button says Stop")

    -- move away from every stop, ride round; one lap is n + 1 positions (back to the start)
    PLAYER.x, PLAYER.y = -5, -5
    local visited = 1
    local guard = 0
    while GP:IsNavigating() and guard < 200 do
        Arrive(); guard = guard + 1
        if GP:IsNavigating() then visited = visited + 1 end
    end
    check(not GP:IsNavigating() and logHas("done: 1 lap"), "one lap ridden, then it stops")
    check(fake.sent >= 1 and guard == n + 1, "every stop of the lap, back to the start")
    check(GP.ui.rideButtons[1]:GetText() == "Start", "the row's button says Start again")

    -- lap after lap, a few stops at a time: the last one handed over is sent again with the next behind it
    local was = GP.NAV_AHEAD
    GP.NAV_AHEAD = 4
    PLAYER.x, PLAYER.y = StopXY(1)
    check(GP:StartNav(route, 0) and #fake.stops == 4, "endless: four at a time")
    PLAYER.x, PLAYER.y = -5, -5
    Arrive(); Arrive(); Arrive()
    check(fake.cur == 1 and fake.sent >= 3, "heading for the 4th: sent again")
    check(Same(fake.stops[1].x, fake.stops[1].y, StopXY(4)) and Same(fake.stops[2].x, fake.stops[2].y, StopXY(5)),
        "from the stop you head for, with the next ones")
    -- ride past the next stop to the one after: the skipped one isn't asked for again
    PLAYER.x, PLAYER.y = StopXY(6)
    Tick()
    check(Same(fake.stops[1].x, fake.stops[1].y, StopXY(7)), "close to a later stop: on from the one after it")
    PLAYER.x, PLAYER.y = -5, -5
    for _ = 1, 3 * n do Arrive() end
    check(GP:IsNavigating() and logHas("lap 1 of"), "laps go on, and each is reported")
    check(GP:NavStatus():find("lap"), "the row shows the lap")

    -- within "Next stop when this close" of the stop you head for: on to the next
    do
        local w = GP:MapYards(route.mapID)
        local tx, ty = fake.stops[fake.cur].x, fake.stops[fake.cur].y
        local nextX, nextY = fake.stops[fake.cur + 1].x, fake.stops[fake.cur + 1].y
        GP.db.navReach = 30
        PLAYER.x, PLAYER.y = tx + 25 / w, ty
        Tick()
        check(Same(fake.stops[fake.cur].x, fake.stops[fake.cur].y, nextX, nextY), "25 yards off with 30 set: moved on")
        local cx, cy = fake.stops[fake.cur].x, fake.stops[fake.cur].y
        GP.db.navReach = 15
        PLAYER.x, PLAYER.y = cx + 25 / w, cy
        Tick()
        check(Same(fake.stops[fake.cur].x, fake.stops[fake.cur].y, cx, cy), "with 15 set: not yet")
        GP.db.navReach = GP.DEFAULTS.navReach
        PLAYER.x, PLAYER.y = -5, -5
    end

    -- within reach of the stop you head for: on to the next
    GP.db.navReach = 30
    local i0 = fake.cur
    local x0, y0 = fake.stops[i0].x, fake.stops[i0].y
    local w0 = GP:MapYards(route.mapID)
    PLAYER.x, PLAYER.y = x0 + 25 / w0, y0
    Tick()
    check(Same(fake.stops[1].x, fake.stops[1].y, StopXY((function()
        for i = 1, n do local x, y = StopXY(i) if Same(x, y, x0, y0) then return i % n + 1 end end
    end)())), "25 yards from the stop: heading for the next one")
    GP.db.navReach = 15
    local i1 = fake.cur
    x0, y0 = fake.stops[i1].x, fake.stops[i1].y
    PLAYER.x, PLAYER.y = x0 + 25 / w0, y0
    local sent = fake.sent
    Tick()
    check(fake.sent == sent, "reach 15: 25 yards isn't close enough")
    SlashCmdList.GATHERLINE("reach 500")
    check(GP.db.navReach == 150, "/gl reach is kept between 15 and 150")
    GP.db.navReach = 30
    PLAYER.x, PLAYER.y = -5, -5

    -- the player clears the journey: we stop
    fake.cur, fake.ended = nil, "cleared"
    Tick()
    check(not GP:IsNavigating() and logHas("journey was cleared"), "cleared by the player: stops")

    -- in combat it waits, then hands the stops over
    IN_COMBAT = true
    fake.sent = 0
    check(not GP:StartNav(route) and logHas("not in combat"), "can't start in combat")
    IN_COMBAT = false
    check(GP:StartNav(route), "started")
    IN_COMBAT = true
    local before = fake.sent
    fake.cur = #fake.stops; Tick()   -- wants to send more, can't
    check(fake.sent == before, "nothing sent in combat")
    IN_COMBAT = false
    Tick()
    check(fake.sent == before + 1, "sent once combat is over")

    -- /gl stop
    SlashCmdList.GATHERLINE("stop")
    check(not GP:IsNavigating() and fake.ended == "cancelled", "/gl stop ends the journey")

    -- from another zone: the stop Shortest Path says is quickest to reach
    PLAYER.map, PLAYER.x, PLAYER.y = 1436, 0.5, 0.5
    check(GP:StartNav(route, 1), "started from Westfall")
    local best, bi = math.huge, 1
    local samples = math.min(n, GP.NAV_SAMPLES)
    for s = 0, samples - 1 do
        local i = math.floor(s * n / samples) + 1
        local x, y = StopXY(i)
        local t = api.Estimate(0, 0, 0, 0, x, y)
        if t < best then best, bi = t, i end
    end
    check(Same(fake.stops[1].x, fake.stops[1].y, StopXY(bi)), "joining at the quickest stop to reach")

    -- reversed arrows ride the other way
    GP:StopNav(true)
    GP.db.arrowsReverse = true
    PLAYER.map = route.mapID
    PLAYER.x, PLAYER.y = StopXY(3)
    GP:StartNav(route)
    check(Same(fake.stops[2].x, fake.stops[2].y, StopXY(2)), "arrows reversed: the other way round")
    GP.db.arrowsReverse = false

    -- smart laps: a stop whose nodes you all gathered lately is left out
    GP:StopNav(true)
    GP:ResetStats(route)
    GP.harvests = {}
    GP.NAV_AHEAD = n + 2
    local _, members = GP:StopLabels(route)
    local j
    for i = 3, n do if members[i] and #members[i] > 0 then j = i break end end
    check(j ~= nil, "a stop with nodes to gather")
    -- gathering is seen from the spell cast, where you stand
    check(GP:IsGatherSpell(2366) and not GP:IsGatherSpell(133), "Herb Gathering is gathering, Fireball isn't")
    local onEvent = GP.sessionFrame:GetScript("OnEvent")
    for k = 1, #members[j], 2 do
        PLAYER.x, PLAYER.y = members[j][k], members[j][k + 1]
        onEvent(GP.sessionFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 2366)
    end
    check(#GP.harvests == #members[j] / 2, "every node gathered noted")
    onEvent(GP.sessionFrame, "UNIT_SPELLCAST_SUCCEEDED", "target", "cast", 2366)
    check(#GP.harvests == #members[j] / 2, "someone else's cast isn't")
    check(GP:WasHarvested(route.mapID, members[j][1], members[j][2], 300), "a gathered node counts as gone")
    PLAYER.x, PLAYER.y = StopXY(1)
    GP.db.arrowsReverse = false
    GP.db.navRespawn = 5
    check(GP:StartNav(route, 1), "started a lap")
    check(#fake.stops == n, "one stop fewer handed over")
    local jx, jy = StopXY(j)
    local found = false
    for _, st in ipairs(fake.stops) do if Same(st.x, st.y, jx, jy) then found = true end end
    check(not found, "the gathered stop isn't one of them")
    -- ride it, a minute a stop; loot from a node counts what it's worth with Auctionator
    LOOT_ITEM_SELF = "You receive loot: %s."
    LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
    Auctionator = { API = { v1 = { GetAuctionPriceByItemLink = function(_, link)
        return link:find("Peacebloom") and 2500 or nil end } } }
    local link = "|cffffffff|Hitem:2447::::::::|h[Peacebloom]|h|r"
    local link2, count = GP:ParseLoot("You receive loot: " .. link .. "x3.")
    check(link2 == link and count == 3, "loot read from the chat line")
    PLAYER.x, PLAYER.y = -5, -5
    local guard = 0
    while GP:IsNavigating() and guard < 200 do
        FAKE_TIME = FAKE_TIME + 60
        if guard == 2 then
            GP:RecordHarvest(route.mapID, 0.01, 0.01)
            onEvent(GP.sessionFrame, "CHAT_MSG_LOOT", "You receive loot: " .. link .. "x3.")
        end
        Arrive(); guard = guard + 1
    end
    check(logHas("1 stop skipped (still empty)"), "the lap says it skipped one")
    local st = route.stats
    check(st and st.laps == 1 and st.best and st.best > 0 and st.best == st.lapTime, "a lap counted for the route")
    check(st.gathered == 1 and st.value == 7500, "what was gathered and what it's worth")
    check(st.rideTime > 0, "and how long it was ridden")
    local line = GP:StatsLine(route)
    check(line and line:find("best lap") and line:find("nodes/h") and line:find("/h"), "a line of statistics: " .. tostring(line))
    GP:OpenConfig("routes")
    check(GP.ui.rideButtons[1] and true, "the route list still draws")
    SlashCmdList.GATHERLINE("stats")
    check(logHas("laps 1"), "/gl stats")
    -- 0 minutes: nothing's skipped
    GP.db.navRespawn = 0
    PLAYER.x, PLAYER.y = StopXY(1)
    GP:StartNav(route, 1)
    check(#fake.stops == n + 1, "skipping off: every stop")
    GP:StopNav(true)
    -- every stop gathered: it goes on anyway
    GP.db.navRespawn = 5
    for i = 1, n do
        for k = 1, #(members[i] or {}), 2 do GP:RecordHarvest(route.mapID, members[i][k], members[i][k + 1]) end
    end
    GP:StartNav(route, 1)
    check(#fake.stops >= 1, "all empty: still somewhere to go")
    GP:StopNav(true)
    -- long enough later they're back
    FAKE_TIME = FAKE_TIME + 600
    GP:StartNav(route, 1)
    check(#fake.stops == n + 1, "after the minutes: every stop again")
    GP:StopNav(true)
    SlashCmdList.GATHERLINE("stats reset")
    check(route.stats == nil and GP:StatsLine(route) == nil, "/gl stats reset")
    SlashCmdList.GATHERLINE("empty 99")
    check(GP.db.navRespawn == 30, "/gl empty is kept between 0 and 30")
    GP.db.navRespawn = GP.DEFAULTS.navRespawn
    GP:OpenConfig("riding")
    check(GP.ui.navRespawn ~= nil, "Smart laps on the Guidance tab")
    Auctionator = nil
    GP.harvests = {}

    -- deleting the route stops the ride
    GP:DeleteRoute(route)
    check(not GP:IsNavigating() and fake.cur == nil, "deleting the route stops it")
    table.insert(GP.db.routes, 1, route)

    GP.NAV_AHEAD = was
    ShortestPathForever = nil
end

STEP("routes worked out on foot over the ground")
do
    -- Elwynn has a wall down the middle (x = 0.5) with a gate at the bottom (y 0.85 to 0.95): crossing it
    -- anywhere else on foot means going round by the gate. A fake walking search answers a frame later.
    local w, h = GP:MapYards(E)
    local GATE = { 0.5, 0.9 }
    local function Y(a, b) return math.sqrt(((a[1] - b[1]) * w) ^ 2 + ((a[2] - b[2]) * h) ^ 2) end
    local function Crosses(a, b)
        if (a[1] - 0.5) * (b[1] - 0.5) >= 0 then return false end
        local t = (0.5 - a[1]) / (b[1] - a[1])
        local y = a[2] + t * (b[2] - a[2])
        return y < 0.85 or y > 0.95
    end
    local function Foot(a, b)
        if Crosses(a, b) then return Y(a, GATE) + Y(GATE, b) end
        return Y(a, b)
    end
    local queue, searches = {}, 0
    local pump = CreateFrame("Frame")
    pump:SetScript("OnUpdate", function()
        local q = queue
        queue = {}
        for _, fn in ipairs(q) do fn() end
    end)
    local Walk = GP.Walk
    local was = { Ready = Walk.Ready, Cost = Walk.Cost, Costs = Walk.Costs, Line = Walk.Line }
    Walk.Line = function(_, ax, ay, bx, by, done)
        searches = searches + 1
        local xy = { ax, ay }
        if Crosses({ ax, ay }, { bx, by }) then xy[3], xy[4] = GATE[1], GATE[2] end
        xy[#xy + 1], xy[#xy + 2] = bx, by
        queue[#queue + 1] = function() done(xy, Foot({ ax, ay }, { bx, by })) end
        return {}
    end
    Walk.Ready = function() return true end
    Walk.Cost = function(_, ax, ay, bx, by, done)
        searches = searches + 1
        queue[#queue + 1] = function() done(Foot({ ax, ay }, { bx, by })) end
        return {}
    end
    Walk.Costs = function(_, ax, ay, targets, done)
        searches = searches + 1
        local costs = {}
        for i, t in ipairs(targets) do costs[i] = Foot({ ax, ay }, t) end
        queue[#queue + 1] = function() done(costs) end
        return {}
    end

    -- iron on both sides of the wall, high up, far from the gate
    gm.names.Mining[12] = "Iron Deposit"
    math.randomseed(3)
    for _ = 1, 24 do gm:Add(E, "Mining", 12, 0.30 + math.random() * 0.15, 0.10 + math.random() * 0.6, true) end
    for _ = 1, 24 do gm:Add(E, "Mining", 12, 0.55 + math.random() * 0.15, 0.10 + math.random() * 0.6, true) end
    GP.db.walkRoutes = true
    local route = GP:NewRoute({ mapID = E, kinds = { Mining = { ["Iron Deposit"] = true } }, name = "iron", sight = 60 })
    check(route and route.working, "worked out")
    GP:OpenConfig("routes")
    Tick(0.016); Tick(0.016)
    check(GP.ui.routeRows[1] and true, "rows")
    RunJobs()
    check(not route.working and GP:NodeCount(route) >= 2, "a loop came out")
    check(route.walked and route.walked > 0, "walks measured")
    check(searches > 0, "the walking search was asked")
    -- what it says is the length on foot, and it's honest
    local n, p = GP:NodeCount(route), route.points
    local foot = 0
    for i = 1, n do
        local j = i % n + 1
        foot = foot + Foot({ p[2 * i - 1], p[2 * i] }, { p[2 * j - 1], p[2 * j] })
    end
    check(math.abs(route.length - foot) < foot * 0.02 + 5, ("the length is the length on foot (%d / %d)"):format(route.length, foot))
    check(route.walkOther and foot < route.walkOther,
        "the loop kept is shorter on foot than GatherPath Forever's straight-line one")
    -- the wall crossed as few times as it must: twice, at the gate
    local crossings = 0
    for i = 1, n do
        local j = i % n + 1
        if Crosses({ p[2 * i - 1], p[2 * i] }, { p[2 * j - 1], p[2 * j] }) then crossings = crossings + 1 end
    end
    check(crossings <= 2, "over the wall only on the way there and back (" .. crossings .. ")")
    check(logHas("Measured on foot over the ground; "), "chat says so, and how much shorter")
    -- the lines go along the ground: through the gate, and through every stop in order
    local d, dn = GP:DrawPoints(route)
    check(d == route.drawn and dn > n, "drawn along the ways on foot, more points than stops")
    local gate, at = 0, 1
    for k = 1, dn do
        if math.abs(d[2 * k - 1] - GATE[1]) < 1e-4 and math.abs(d[2 * k] - GATE[2]) < 1e-4 then gate = gate + 1 end
        if at <= n and math.abs(d[2 * k - 1] - p[2 * at - 1]) < 1e-4 and math.abs(d[2 * k] - p[2 * at]) < 1e-4 then
            at = at + 1
        end
    end
    check(gate == crossings and at == n + 1, "through the gate each time, and every stop in order")
    for k = 1, dn do
        local j = k % dn + 1
        check(not Crosses({ d[2 * k - 1], d[2 * k] }, { d[2 * j - 1], d[2 * j] }), "no drawn line over the wall")
    end
    -- a node found later joins with straight lines until it's rebuilt
    GP:AddNode(E, "Mining", 0.62, 0.95, "Iron Deposit")
    check(route.drawn == nil and select(1, GP:DrawPoints(route)) == route.points, "straight lines after a node joins")
    check(GP.ui.routeRows[1].info:GetText():find("on foot"), "and the row")

    -- turned off: straight lines, as before
    GP.db.walkRoutes = false
    local before = searches
    GP:RebuildRoute(route)
    RunJobs()
    check(searches == before and not route.walked and not route.walkFactor, "off: no walks, straight lines")

    -- no walking maps: straight lines, and chat says why
    GP.db.walkRoutes = true
    Walk.Ready = function() return false, "there's no walking map for this continent" end
    GP:RebuildRoute(route)
    RunJobs()
    check(not route.walked and logHas("Straight lines: there's no walking map"), "no maps: straight, and why")

    for k, v in pairs(was) do Walk[k] = v end
    pump:SetScript("OnUpdate", nil)
    GP:DeleteRoute(route)
end

STEP("turning a route round")
do
    GP:OpenConfig("routes")
    local route = GP.ui.routeRows[1].route
    check(route and not route.working, "a route on the Routes tab")
    PLAYER.map = route.mapID
    local before, drawnBefore = { unpack(route.points) }, { 1, 2, 3, 4, 5, 6 }
    route.drawn = { unpack(drawnBefore) }
    local n = GP:NodeCount(route)
    GP:RefreshConfig()
    check(not GP.ui.turnButtons[1].disabled, "the button can be clicked")
    Click(GP.ui.turnButtons[1])
    check(logHas("turned round"), "chat says so")
    for i = 1, n do
        local j = n - i + 1
        check(route.points[2 * i - 1] == before[2 * j - 1] and route.points[2 * i] == before[2 * j], "stops the other way")
    end
    check(route.drawn[1] == 5 and route.drawn[2] == 6 and route.drawn[5] == 1 and route.drawn[6] == 2, "lines too")
    SlashCmdList.GATHERLINE("reverse")   -- the shown route in your zone: this one
    for i = 1, #before do check(route.points[i] == before[i], "twice: as it was") end
    route.drawn = nil
end

STEP("bringing routes over from GatherPath Plus")
do
    local mine = #GP.db.routes
    local src = GP.db.routes[1]
    GatherPathPlusDB = {
        routes = {
            { id = 1, mapID = src.mapID, name = src.name, kinds = {}, points = { unpack(src.points) }, color = { 1, 0, 0 }, shown = true },
            { id = 7, mapID = W, name = "Westfall copper", kinds = { Mining = { ["Copper Vein"] = true } },
              points = { 0.1, 0.1, 0.2, 0.2, 0.3, 0.1 }, color = { 0, 1, 0 }, shown = true, sight = 100 },
        },
        taboos = { [W] = { { 0.4, 0.4, 0.6, 0.4, 0.5, 0.6 } } },
        skip = { ["Poor Copper"] = true },
    }
    GP:OpenConfig("about")
    check(not GP.ui.importButton.disabled, "About offers to bring them over")
    Click(GP.ui.importButton)
    check(#GP.db.routes == mine + 1, "one new route: the one with the same zone and name is left alone")
    local got = GP.db.routes[#GP.db.routes]
    check(got.name == "Westfall copper" and got.mapID == W and got.sight == 100 and got.id ~= 7, "copied, with its own id")
    check(got.points ~= GatherPathPlusDB.routes[2].points, "a copy, not the same table")
    check(#GP:Taboos(W) == 1 and GP:IsSkipped("Poor Copper"), "no-go areas and skip list too")
    check(logHas("brought 1 route over from GatherPath Plus"), "chat says so")
    Click(GP.ui.importButton)
    check(#GP.db.routes == mine + 1, "again: nothing twice")
    GP:DeleteRoute(got)
    GP:DeleteTaboo(W, 1)
    GP:SetSkipped("Poor Copper", false)
    RunJobs()
    GatherPathPlusDB = nil
    GP:RefreshConfig()
    check(GP.ui.importButton.disabled, "nothing to bring: greyed out")
end

STEP("nodes from GatherLite")
do
    -- a fake GatherLite, as LibStub's AceAddon hands it out: nodes per type and map, objects by id, names translated
    local glNodes = { herbalism = {}, mining = {}, fishing = {}, containers = {} }
    local objects = {
        [1618] = { type = "herb", id = { 1618 }, name = "peacebloom" },
        [1617] = { type = "herb", id = { 1617 }, name = "silverleaf" },
        [1731] = { type = "ore", id = { 1731 }, name = "copper_vein" },
        [2055] = { type = "ore", id = { 2055 }, name = "copper_vein" },
        [9999] = { type = "ore", id = { 9999 }, name = "poor_copper" },
    }
    local translated = { ["node.peacebloom"] = "Peacebloom", ["node.silverleaf"] = "Silverleaf",
        ["node.copper_vein"] = "Copper Vein", ["node.poor_copper"] = "Poor Copper" }
    local ignored, handlers = { [9999] = true }, {}
    local GL = {}
    function GL:GetNodesForMap(t, mapID)
        if not mapID then return glNodes[t] end
        local out = {}
        for _, n in ipairs(glNodes[t]) do if n.mapID == mapID then out[#out + 1] = n end end
        return out
    end
    function GL:GetNodeObject(id) return objects[id] end
    function GL:translate(key) return translated[key] or key end
    function GL:IsIgnored(id) return ignored[id] or false end
    function GL:On(event, fn) handlers[event] = handlers[event] or {}; table.insert(handlers[event], fn) end
    local function Add(t, id, mapID, x, y, quiet)
        local node = { type = t, object = id, mapID = mapID, posX = x, posY = y }
        table.insert(glNodes[t], node)
        if not quiet then for _, fn in ipairs(handlers["nodes:added"] or {}) do fn(node) end end
        return node
    end
    local ace = { GetAddon = function(_, name) if name == "GatherLite" then return GL end end }
    local hadStub = LibStub
    LibStub = setmetatable({}, { __call = function(_, lib) if lib == "AceAddon-3.0" then return ace end end })

    -- GatherLite alone
    local gmWas = GatherMate2
    GatherMate2 = nil
    check(not GP:HasGatherMate() and GP:HasNodeSource() and GP:SourceNames() == "GatherLite", "GatherLite on its own is enough")
    local MAP = 1438   -- Teldrassil
    for i = 0, 5 do Add("herbalism", 1618, MAP, 0.30 + i * 0.05, 0.40 + (i % 2) * 0.05, true) end
    Add("herbalism", 1617, MAP, 0.60, 0.60, true)
    Add("mining", 2055, MAP, 0.50, 0.30, true)
    Add("mining", 9999, MAP, 0.55, 0.35, true)
    local zone = {}
    for _, n in ipairs(GP:ZoneNodes(MAP)) do zone[n.kind .. "/" .. n.name] = n.count end
    check(zone["Herb Gathering/Peacebloom"] == 6 and zone["Herb Gathering/Silverleaf"] == 1, "its herbs, by their names")
    check(zone["Mining/Copper Vein"] == 1 and not zone["Mining/Poor Copper"], "its ore, without what it ignores")
    local zones = {}
    for _, m in ipairs(GP:GatherZones()) do zones[m] = true end
    check(zones[MAP], "its zones are listed")
    local route = GP:NewRoute({ mapID = MAP, kinds = { ["Herb Gathering"] = { Peacebloom = true } }, sight = 0 })
    RunJobs()
    check(route and GP:NodeCount(route) == 6, "a route from GatherLite's nodes")
    GP:OpenConfig("about")
    check(GP.ui.aboutStatus, "About shows where nodes come from")

    -- a node GatherLite finds later joins the route (Gatherline listens from login on)
    FireEvent("PLAYER_LOGIN")
    GP.db.autoAdd = true
    Add("herbalism", 1618, MAP, 0.45, 0.70)
    check(GP:NodeCount(route) == 7, "GatherLite's new node joined the route")

    -- both: a node both know counts once, the rest all count
    GatherMate2 = gmWas
    check(GP:SourceNames() == "GatherMate2 + GatherLite", "both")
    local before = 0
    for _, n in ipairs(GP:ZoneNodes(E)) do if n.name == "Copper Vein" then before = n.count end end
    local gmX, gmY
    GP:EachNode(E, "Mining", function(x, y, name) if name == "Copper Vein" and not gmX then gmX, gmY = x, y end end)
    check(gmX, "GatherMate2 has copper in Elwynn")
    local w = GP:MapYards(E)
    Add("mining", 1731, E, gmX + 5 / w, gmY, true)        -- 5 yards off GatherMate2's: the same node
    Add("mining", 1731, E, 0.95, 0.95, true)               -- far from any: a new one
    local after = 0
    for _, n in ipairs(GP:ZoneNodes(E)) do if n.name == "Copper Vein" then after = n.count end end
    check(after == before + 1, ("the same node counts once, a new one adds (%d -> %d)"):format(before, after))

    GP:DeleteRoute(route)
    RunJobs()
    for t in pairs(glNodes) do glNodes[t] = {} end
    LibStub = hadStub
    check(GP:SourceNames() == "GatherMate2", "GatherLite gone again")
end

STEP("sharing a route")
do
    local route
    for _, r in ipairs(GP.db.routes) do if not r.working and GP:NodeCount(r) >= 4 then route = r break end end
    check(route ~= nil, "a route to share")
    local before = #GP.db.routes
    route.drawn = { 0.1234, 0.5678, 0.2, 0.3, 0.9999, 0, -0.05, 1.02 }
    route.walked, route.walkFactor = 3, 1.25
    route.kinds = { ["Herb Gathering"] = { ["Peacebloom"] = true, ["Odd^Name; x=1|y"] = true } }
    local line = GP:ExportRoute(route)
    check(line:sub(1, 4) == "GL1^" and not line:find("|", 1, true) and not line:find("%s"), "one line, nothing that breaks in chat: " .. #line)
    local got = GP:ParseShared(line)
    check(got and got.mapID == route.mapID and got.name == route.name, "comes back with its zone and name")
    check(#got.points == #route.points, "every stop")
    local same = true
    for i = 1, #route.points do same = same and near(got.points[i], route.points[i], 1e-9) end
    check(same, "at exactly the same places")
    same = #got.drawn == #route.drawn
    for i = 1, #route.drawn do same = same and near(got.drawn[i], route.drawn[i], 1e-9) end
    check(same, "and the lines along the ground")
    check(got.kinds["Herb Gathering"]["Odd^Name; x=1|y"] and got.kinds["Herb Gathering"]["Peacebloom"], "node names, odd ones too")
    check(near(got.color[1], route.color[1], 0.001) and got.sight == route.sight and got.walked and near(got.walkFactor, 1.25, 0.001),
        "its colour, pass distance and walking")
    -- broken lines are turned down
    check(GP:ParseShared("hello") == nil, "not a route")
    check(GP:ParseShared(line:sub(1, #line - 9)) == nil, "cut short")
    local changed = line:sub(1, 40) .. (line:sub(41, 41) == "A" and "B" or "A") .. line:sub(42)
    check(GP:ParseShared(changed) == nil, "changed")
    check(select(2, GP:ParseShared("GL2^abcdef^x")):find("newer"), "from a newer Gatherline")
    check(GP:ParseShared("  " .. line:sub(1, 30) .. "\n" .. line:sub(31) .. " ") ~= nil, "spaces and line breaks from pasting don't matter")
    -- importing: a name that's taken gets a number
    local added = GP:ImportShared(line)
    check(added and #GP.db.routes == before + 1 and added.name == route.name .. " (2)", "added as " .. tostring(added and added.name))
    check(added.id ~= route.id and added.shown and not added.working and added.points ~= route.points, "its own route")
    check(logHas("added |cffffd100"), "and said so")
    local again = GP:ImportShared(line)
    check(again.name == route.name .. " (3)", "and again")
    GP:DeleteRoute(again)
    -- in the window: Share on the card, Import on the page
    GP:OpenConfig("routes")
    ui.routesZone.Choose(route.mapID)
    GP:RefreshConfig()
    local k
    for i, row in ipairs(GP.ui.routeRows) do if row.route == route then k = i end end
    Click(GP.ui.shareButtons[k])
    local f = GP.shareWindow
    check(f and f:IsShown() and f.box:GetText() == line and f.mode == "share", "Share shows the line")
    Click(f.close)
    Click(GP.ui.routesImport)
    check(f:IsShown() and f.mode == "import" and f.box:GetText() == "", "Import shows an empty box")
    f.box:SetText("nonsense")
    Click(f.go)
    check(f:IsShown() and logHas("isn't a Gatherline route"), "nonsense: says so, the box stays")
    f.box:SetText(line)
    Click(f.go)
    check(not f:IsShown() and #GP.db.routes == before + 2, "a good line: added")
    GP:DeleteRoute(GP.db.routes[#GP.db.routes])
    -- the best route: the most an hour, once two are ridden long enough
    route.stats = { laps = 3, lapTime = 900, best = 290, rideTime = 900, gathered = 60, value = 30000 }
    added.stats = { laps = 2, lapTime = 600, best = 280, rideTime = 600, gathered = 50, value = 10000 }
    local ranked = GP:RankedRoutes()
    check(ranked[1].route == route and ranked[2].route == added, "gold an hour decides")
    check(GP:BestRouteOn(route.mapID) == route, "the best in its zone")
    GP:RefreshConfig()
    check(GP.ui.routeRows[k].info:GetText():find("best here"), "marked on its card")
    route.stats.value, added.stats.value = 0, 0
    check(GP:RankedRoutes()[1].route == added, "without prices: nodes an hour")
    added.stats.rideTime = 100
    check(GP:BestRouteOn(route.mapID) == nil, "a route ridden only a moment isn't compared")
    SlashCmdList.GATHERLINE("stats all")
    check(logHas("best first"), "/gl stats all")
    route.stats, route.drawn, route.walked, route.walkFactor = nil, nil, nil, nil
    GP:DeleteRoute(added)
    check(#GP.db.routes == before, "all tidied up")
end

STEP("routes by gathering skill")
do
    check(GP:NodeSkill("Kupfervorkommen")[1] == 1 and select(2, GP:NodeSkill("Copper Vein")) == "Mining", "what a node needs, in any language")
    check(GP:NodeSkill("Black Lotus")[1] == 300 and GP:NodeSkill("Nothing at all") == nil, "Black Lotus 300, unknown nodes nothing")
    -- the skill as the game says it
    C_SkillInfo = { GetSkillLineInfoByID = function(id) return id == 182 and { rank = 30, modifier = 0 } or { rank = 0 } end }
    check(GP:ProfessionRank("Herb Gathering") == 30 and GP:ProfessionRank("Mining") == 0, "Herbalism 30, no Mining")
    C_SkillInfo = nil
    GP.FAKE_RANKS = { ["Herb Gathering"] = 30, Mining = 70 }
    check(GP:Difficulty("Peacebloom") == "yellow" and GP:Difficulty("Earthroot") == "orange"
        and GP:Difficulty("Mageroyal") == "red" and GP:Difficulty("Tin Vein") == "orange"
        and GP:Difficulty("Copper Vein") == "green", "the game's colours")
    GP.FAKE_RANKS.Mining = 100
    check(GP:Difficulty("Copper Vein") == "grey" and GP:CanGather("Copper Vein") and not GP:CanGather("Mageroyal"), "grey, and what you can't gather")
    check(GP:SkillTag("Peacebloom"):find("ffff00") and GP:SkillTag("Nothing") == "", "a coloured number after the name")
    -- New route: the numbers, and only what you can gather
    GP.FAKE_RANKS = { ["Herb Gathering"] = 30, Mining = 0 }
    GP:OpenConfig("new")
    ui.newZone.Choose(E)
    local function Label(name)
        for _, sw in ipairs(GP.ui.kindSwitches) do
            local e = rawget(sw, "entry")
            if e and e.name == name and sw:IsShown() then return sw.label:GetText() end
        end
    end
    check(Label("Peacebloom") and Label("Peacebloom"):find("ffff00"), "Peacebloom yellow for Herbalism 30")
    check(Label("Copper Vein") and Label("Copper Vein"):find("ff3a3a"), "Copper Vein red without Mining")
    Click(GP.ui.onlySwitch)
    check(GP.db.onlyGatherable and Label("Peacebloom") and not Label("Copper Vein"), "only what I can gather: no Copper Vein")
    Click(GP.ui.onlySwitch)
    check(not GP.db.onlyGatherable and Label("Copper Vein"), "and back")
    -- where to skill up: the zone with the most orange and yellow nodes, picked
    local zones = GP:SkillUpZones()
    check(#zones >= 1 and zones[1].nodes[1].kind == "Herb Gathering", "zones with herbs that raise Herbalism 30")
    for _, z in ipairs(zones) do
        for _, e in ipairs(z.nodes) do check(e.kind ~= "Mining", "nothing for a profession you don't have") end
    end
    Click(GP.ui.skillUp)
    check(logHas("where to skill up"), "listed in chat")
    local on = 0
    for _, sw in ipairs(GP.ui.kindSwitches) do if rawget(sw, "entry") and sw:IsShown() and sw:IsOn() then on = on + 1 end end
    check(on > 0 and ui.newZone.getter() == zones[1].mapID, "the best zone with its nodes picked")
    GP.FAKE_RANKS = { ["Herb Gathering"] = 0, Mining = 0 }
    Click(GP.ui.skillUp)
    check(logHas("neither Herbalism nor Mining"), "no profession: says so")
    GP.FAKE_RANKS = nil
    SlashCmdList.GATHERLINE("skill")
    GP:OpenConfig("routes")
end

STEP("tours: routes one after the other, zone to zone")
do
    local a
    for _, r in ipairs(GP.db.routes) do if r.mapID == E and not r.working and GP:NodeCount(r) >= 4 then a = r break end end
    check(a ~= nil, "a route in Elwynn")
    local b = {}
    for k, v in pairs(a) do b[k] = v end
    b.mapID, b.id, b.name, b.stats = W, GP.db.nextID, "Westfall - Test", nil
    GP.db.nextID = GP.db.nextID + 1
    table.insert(GP.db.routes, b)
    -- the page: make one
    GP:OpenConfig("tours")
    check(GP.config.currentTab == "tours" and #GP:Tours() == 0 and ui.toursEmpty:GetText():find("New tour"), "no tours yet")
    Click(ui.tourNew)
    check(ui.tourSave.disabled == true, "can't save with no routes")
    ui.tourAdd.Choose(b.id)
    ui.tourAdd.Choose(a.id)
    check(ui.stageRows[1].text:GetText():find("Westfall - Test", 1, true) and ui.stageRows[2]:IsShown(), "two routes in")
    Click(ui.stageRows[2].up)
    check(ui.stageRows[1].text:GetText():find(a.name, 1, true), "moved up")
    check(ui.stageRows[1].up.disabled == true and ui.stageRows[2].down.disabled == true, "no further up or down")
    Click(ui.tourSave)
    local tour = GP:Tours()[1]
    check(tour and #tour.stages == 2 and tour.stages[1] == a.id and tour.laps == 1 and not tour.loop, "saved, in that order")
    check(tour.name == GP:MapName(E) .. " – " .. GP:MapName(W), "named after its zones: " .. tour.name)
    check(ui.tourRows[1]:IsShown() and ui.tourRows[1].info:GetText():find(" → ", 1, true), "listed with its zones")
    check(GP:SaveTour({ stages = { a.id } }) == nil and logHas("at least two routes"), "one route is no tour")

    -- riding it with a fake Shortest Path
    local tickers = {}
    C_Timer = { NewTicker = function(_, fn) local t = { fn = fn } function t:Cancel() self.cancelled = true end tickers[#tickers + 1] = t return t end,
        After = function(_, fn) fn() end }
    local function Tick() for _, t in ipairs(tickers) do if not t.cancelled then t.fn() end end end
    local fake = {}
    local api = { version = 2 }
    function api.NavigateRoute(owner, stops) fake.owner, fake.stops, fake.cur, fake.ended = owner, stops, 1, nil return true end
    function api.CurrentStop(owner) if fake.cur and owner == fake.owner then return fake.cur end return nil, "none" end
    function api.Ended() if fake.ended then return fake.ended, 0 end return nil, "none" end
    function api.Cancel(owner) if fake.cur then fake.cur, fake.ended = nil, "cancelled" return true end return false end
    ShortestPathForever = { API = api }
    local function Arrive()
        if fake.cur < #fake.stops then fake.cur = fake.cur + 1 else fake.cur, fake.ended = nil, "arrived" end
        Tick()
    end
    local function RideOut(guard)
        local route = GP:NavRoute()
        local n = 0
        while GP:NavRoute() == route and n < (guard or 300) do FAKE_TIME = FAKE_TIME + 10; Arrive(); n = n + 1 end
    end
    PLAYER.map, PLAYER.x, PLAYER.y = E, -5, -5
    GP:RefreshConfig()
    Click(ui.tourRide[1])
    check(GP:IsTouring(tour) and GP:NavRoute() == a and fake.stops[1].map == E, "starts with its first route")
    check(GP:NavStatus():find("tour 1/2", 1, true), "the ride says where in the tour")
    RideOut()
    check(GP:NavRoute() == b and fake.stops[1].map == W and logHas("on to |cffffd100Westfall - Test"), "then on to Westfall")
    check(GP:NavStatus():find("tour 2/2", 1, true), "tour 2/2")
    RideOut()
    check(not GP:IsNavigating() and not GP:IsTouring() and logHas("done."), "the last one done: the tour too")
    -- starting in Westfall: its route there first; starting over at the end
    tour.loop = true
    PLAYER.map = W
    check(GP:StartTour(tour) and GP:NavRoute() == b, "in Westfall: its Westfall route first")
    RideOut()
    check(GP:NavRoute() == a and GP:IsTouring(tour), "starts over")
    SlashCmdList.GATHERLINE("stop")
    check(not GP:IsNavigating() and not GP:IsTouring(), "/gl stop ends the tour")
    -- starting another route stops the tour
    GP:StartTour(tour)
    GP:StartNav(a, 1)
    check(GP:IsNavigating(a) and not GP:IsTouring(), "Start on a route: the tour stops")
    GP:StopNav(true)
    SlashCmdList.GATHERLINE("tour " .. GP:MapName(E):sub(1, 4))
    check(GP:IsTouring(tour), "/gl tour <name>")
    GP:StopNav(true)
    -- edit: three laps; then a route deleted drops out
    GP:EditTourInWindow(tour)
    check(ui.tourName:GetText() == tour.name and ui.stageRows[2]:IsShown(), "Edit shows the tour")
    Click(ui.tourCancel)
    GP:DeleteRoute(b)
    check(#GP:Tours()[1].stages == 1, "a deleted route drops out of the tour")
    check(not GP:StartTour(tour) and logHas("fewer than two"), "and one route left can't be ridden")
    GP:DeleteTour(tour)
    check(#GP:Tours() == 0, "tour deleted")
    ShortestPathForever = nil
    GP:OpenConfig("routes")
end

STEP("the gathering HUD")
do
    -- which way things are from you
    local w, h = GP:MapYards(E)
    local function Rel(dx, dy, f) return GP.HudRelative(E, 0.5, 0.5, 0.5 + dx / w, 0.5 + dy / h, f) end
    local r, a, ang = Rel(0, -50, 0)
    check(near(r, 0, 1e-6) and near(a, 50, 1e-6) and near(ang, 0, 1e-6), "facing north: north is ahead")
    r, a, ang = Rel(50, 0, 0)
    check(near(r, 50, 1e-6) and near(a, 0, 1e-6) and ang > 0, "east is to the right")
    r, a = Rel(-50, 0, math.pi / 2)
    check(near(a, 50, 1e-6) and near(r, 0, 1e-6), "facing west: west is ahead")
    r, a = Rel(0, -50, math.pi / 2)
    check(near(r, 50, 1e-6), "and north to the right")

    local parts = GP.hudParts
    local hs = GP:HudSettings()
    check(hs.compass and hs.card and not hs.lens and hs.scale == 100, "compass and lap card on to start with")
    PLAYER.map, PLAYER.x, PLAYER.y = E, 0.5, 0.5
    GetPlayerFacing = function() return 0.3 end
    -- nothing while not riding
    GP.HudTick()
    check(not parts.compass:IsShown() and not parts.card:IsShown(), "not riding: no HUD")
    -- preview: made-up stops round you
    GP:SetHudPreview(true)
    GP.HudTick()
    check(parts.compass:IsShown() and parts.card:IsShown() and not parts.lens:IsShown(), "preview: the parts switched on")
    check(parts.compass.what:GetText():find("Tin Vein", 1, true) and parts.compass.what:GetText():find(" yd", 1, true), "the band names the next stop and how far")
    check(parts.compass.lap:GetText():find("Lap 2", 1, true) and parts.compass.lap:GetText():find("best 5:58", 1, true), "and the lap")
    check(parts.card.time:GetText() == "3:12" and parts.card.delta:GetText():find("to your best", 1, true), "the card: lap time against the best")
    local shown = 0
    for _, d in ipairs(parts.card.dots) do if d:IsShown() then shown = shown + 1 end end
    check(shown == 23, "a dot per stop")
    check(parts.card.foot:GetText():find("nodes/h", 1, true) and parts.card.foot:GetText():find("2 skipped", 1, true), "nodes an hour, stops skipped")
    hs.lens = true
    GP.HudTick()
    local lines = 0
    for _, l in ipairs(parts.lens.lines) do if l:IsShown() then lines = lines + 1 end end
    check(parts.lens:IsShown() and lines >= 3, "the lens draws the line round you: " .. lines)
    -- Shortest Path's own compass at the top: the band moves under it, and back
    ShortestPathForeverCompass = CreateFrame("Frame")
    GP.HudTick()
    check(rawget(parts.compass, "underSpf") == true, "under Shortest Path's compass")
    ShortestPathForeverCompass:Hide()
    GP.HudTick()
    check(rawget(parts.compass, "underSpf") == nil, "back to the top once it's gone")
    ShortestPathForeverCompass = nil
    -- stops lined up far off: one mark, not a pile
    local marks = 0
    for _, m in ipairs(parts.compass.marks) do if m:IsShown() then marks = marks + 1 end end
    check(marks <= 5, "marks on the band")
    -- no facing (some places hide it): no HUD
    GetPlayerFacing = nil
    GP.HudTick()
    check(not parts.compass:IsShown(), "no way to know which way you face: hidden")
    GetPlayerFacing = function() return 0.3 end
    -- in combat, if asked
    hs.combat = false
    IN_COMBAT = true
    GP.HudTick()
    check(not parts.card:IsShown(), "steps aside in combat")
    IN_COMBAT = false
    hs.combat = true
    -- the page
    GP:OpenConfig("hud")
    check(GP.config.currentTab == "hud" and ui.hudCompass:IsOn() and ui.hudLens:IsOn(), "the HUD page")
    Click(ui.hudCard)
    check(not hs.card, "a part switched off there")
    Click(ui.hudCard)
    Click(ui.hudMove)
    check(not hs.locked and GP.hudPreview, "moving: unlocked, with the preview")
    parts.card:GetScript("OnDragStop")(parts.card)
    check(type(hs.pos.card) == "table", "a dragged part keeps its place")
    Click(ui.hudReset)
    check(next(hs.pos) == nil, "and goes back")
    Click(ui.hudMove)
    check(hs.locked, "fixed again")
    Click(ui.hudPreview)
    check(not GP.hudPreview, "preview ended")
    -- /gl hud
    SlashCmdList.GATHERLINE("hud")
    check(not hs.compass and not hs.lens and not hs.card and logHas("HUD off"), "/gl hud: all off")
    SlashCmdList.GATHERLINE("hud")
    check(hs.compass and hs.lens and hs.card, "and back as it was")
    SlashCmdList.GATHERLINE("hud lens")
    check(not hs.lens, "/gl hud lens")

    -- a real ride feeds it
    local tickers = {}
    C_Timer = { NewTicker = function(_, fn) local t = { fn = fn } function t:Cancel() self.cancelled = true end tickers[#tickers + 1] = t return t end,
        After = function(_, fn) fn() end }
    local fake = {}
    local api = { version = 2 }
    function api.NavigateRoute(owner, stops) fake.owner, fake.stops, fake.cur = owner, stops, 1 return true end
    function api.CurrentStop(owner) if fake.cur then return fake.cur end return nil, "none" end
    function api.Ended() return nil, "none" end
    function api.Cancel() fake.cur = nil return true end
    ShortestPathForever = { API = api }
    local route
    for _, rr in ipairs(GP.db.routes) do if rr.mapID == E and GP:NodeCount(rr) >= 4 then route = rr break end end
    check(GP:StartNav(route, 1), "riding")
    local st = GP:HudState()
    check(st and st.n == GP:NodeCount(route) and st.k == 1 and st.ahead[1].current and #st.states == st.n
        and st.states[1] == "current", "the HUD's view of the ride")
    GP.HudTick()
    check(parts.card:IsShown() and parts.card.top:GetText() == ("STOP 1/%d"):format(st.n), "the card follows the ride")
    GP:StopNav(true)
    GP.HudTick()
    check(not parts.card:IsShown(), "ride over: gone")
    ShortestPathForever = nil
    GetPlayerFacing = nil
    GP:OpenConfig("routes")
end

STEP("line styles and half widths")
do
    local f = CreateFrame("Frame")
    local lines, dots = GP.LinePool(f), GP.DotPool(f)
    local function Count(pool, key)
        local n = 0
        for _, o in ipairs(pool[key]) do if o:IsShown() then n = n + 1 end end
        return n
    end
    local red = { 1, 0, 0 }
    lines:Begin(); dots:Begin()
    local carry = GP.Stroke(lines, dots, f, "CENTER", 0, 0, 100, 0, red, 1, 2, "line", 0)
    lines:Done(); dots:Done()
    check(Count(lines, "lines") == 1 and Count(dots, "dots") == 0 and carry == 0, "a line: one line")
    lines:Begin(); dots:Begin()
    carry = GP.Stroke(lines, dots, f, "CENTER", 0, 0, 100, 0, red, 1, 2, "dots", 0)
    lines:Done(); dots:Done()
    -- 2 wide: dots 5.2 apart (min 5), from 0 to 100: 20 of them
    check(Count(dots, "dots") == 20 and Count(lines, "lines") == 0, "dots along it: " .. Count(dots, "dots"))
    check(near(dots.dots[1].__w, 3.6, 1e-9), "each dot 1.8 widths across")
    -- the pattern runs on round a corner
    lines:Begin(); dots:Begin()
    local c1 = GP.Stroke(lines, dots, f, "CENTER", 0, 0, 7, 0, red, 1, 2, "dots", 0)
    GP.Stroke(lines, dots, f, "CENTER", 7, 0, 7, 10, red, 1, 2, "dots", c1)
    lines:Done(); dots:Done()
    check(Count(dots, "dots") == 4, "even round corners (0, 5.2, 10.4, 15.6 along it): " .. Count(dots, "dots"))
    lines:Begin(); dots:Begin()
    GP.Stroke(lines, dots, f, "CENTER", 0, 0, 100, 0, red, 1, 2, "dashes", 0)
    lines:Done(); dots:Done()
    -- 2 wide: dashes 6 long, gaps 4: 10 of them
    check(Count(lines, "lines") == 10 and Count(dots, "dots") == 0, "dashes: " .. Count(lines, "lines"))
    -- the page: half widths and the style
    GP:OpenConfig("display")
    ui.worldWidth:SetValue(1.5)
    check(GP.db.worldWidth == 1.5, "world line width 1.5")
    ui.minimapWidth:SetValue(0.5)
    check(GP.db.minimapWidth == 0.5, "minimap 0.5")
    ui.minimapStyle.Choose("dots")
    check(GP.db.minimapStyle == "dots", "minimap in dots")
    GP:DrawMinimap(true)
    ui.worldStyle.Choose("dashes")
    check(GP.db.worldStyle == "dashes", "world map in dashes")
    GP.db.worldStyle, GP.db.minimapStyle, GP.db.worldWidth, GP.db.minimapWidth = "line", "line", 4, 3
    GP:OpenConfig("routes")
end

STEP("without GatherMate2")
GatherMate2 = nil
check(not GP:HasGatherMate())
check(GP:NewRoute({ mapID = E, kinds = { Mining = { ["Copper Vein"] = true } } }) == nil and logHas("needs GatherMate2 or GatherLite"))
GP:OpenConfig("new")
check(#GP:ZoneNodes(E) == 0)
GP:OpenConfig("routes")
check(GP:NodeCount(GP.db.routes[1]) == 9, "routes already made still work")

LOG[#LOG + 1] = "PASSED"
