-- How much walking detours help: routes through random walkable nodes, worked out with straight lines and with
-- detours measured on Shortest Path Forever's real walking maps, both then measured on foot.
--   luajit -joff tests/walk_bench.lua <shortest-path-forever checkout> [area] [nodes] [sight]
-- area: dunmorogh (mountains, default), elwynn (gentle), or anything in AREAS below.
local spf = assert(arg[1], "usage: luajit -joff tests/walk_bench.lua <spf checkout> [area] [nodes] [sight]")
local AREAS = {
	-- top = the north edge's world x, left = the west edge's world y, w/h yards across/down
	dunmorogh = { map = 0, top = -4800, left = -500, w = 2600, h = 1500 },
	elwynn = { map = 0, top = -8800, left = 600, w = 1600, h = 1066 },
	lochmodan = { map = 0, top = -4800, left = -2700, w = 1800, h = 1500 },
	ashenvale = { map = 1, top = 3800, left = 900, w = 2400, h = 1600 },
}
local area = AREAS[arg[2] or "dunmorogh"] or error("unknown area")
local COUNT, SIGHT = tonumber(arg[3]) or 150, tonumber(arg[4]) or 100
assert(loadfile(spf .. "/tools/load_nav.lua"))(area.map, spf)

local ns = { GP = { Print = print } }
for _, f in ipairs({ "Optimize.lua", "Routing/PathGrid.lua", "Routing/Path.lua", "Routing/PathJobs.lua" }) do
	assert(loadfile(f))("Gatherline", ns)
end
local O, Path = ns.Optimize, ns.Path
local clock = os.clock

-- yards on the made-up zone map <-> world
local function World(p) return { x = area.top - p[2], y = area.left - p[1] } end

-- random nodes the walking map can reach from the middle
math.randomseed(11)
local mid = World({ area.w / 2, area.h / 2 })
local cands = {}
for i = 1, COUNT * 4 do cands[i] = { math.random() * area.w, math.random() * area.h } end
local targets = {}
for i, c in ipairs(cands) do targets[i] = World(c) end
local reach = Path.FindManySync(area.map, mid, targets)
local nodes = {}
for i, c in ipairs(cands) do
	local st = math.sqrt((targets[i].x - mid.x) ^ 2 + (targets[i].y - mid.y) ^ 2)
	-- leave out spots only reached the long way round (on ledges, behind walls): gathering nodes stand where
	-- players get to
	if reach[i] and reach[i] <= st * 1.6 + 150 and #nodes < COUNT then nodes[#nodes + 1] = c end
end
print(("%d nodes on foot from the middle (of %d tried)"):format(#nodes, #cands))

local spots = O.GroupFor(nodes, SIGHT)
print(("%d spots (passes within %d)"):format(#spots, SIGHT))

-- on foot: the loop's real length, leg by leg
local function OnFoot(stops)
	local total, none = 0, 0
	for i = 1, #stops do
		local a, b = stops[i], stops[i % #stops + 1]
		local pts = Path.FindSync(area.map, World(a), World(b))
		if pts then
			for k = 2, #pts do total = total + math.sqrt((pts[k].x - pts[k - 1].x) ^ 2 + (pts[k].y - pts[k - 1].y) ^ 2) end
		else
			none = none + 1
		end
	end
	return total, none
end
local function Straight(stops)
	local order = {}
	for i = 1, #stops do order[i] = i end
	return O.Length(stops, order)
end

-- 1: straight lines (GatherPath Forever)
local t0 = clock()
local plain = O.Shortcut(spots, SIGHT, true)
local tPlain = clock() - t0

-- 2: detours to the 12 nearest, measured
local NEAR, SLACK, RATIO, NO_WAY = tonumber(os.getenv("NEAR") or 12), tonumber(os.getenv("SLACK") or 40), tonumber(os.getenv("RATIO") or 1.25), 25
t0 = clock()
local f, measured = {}, 0
for i, a in ipairs(spots) do
	local list = {}
	for j, b in ipairs(spots) do
		if j ~= i then list[#list + 1] = { j, O.Euclid(a, b) } end
	end
	table.sort(list, function(x, y) return x[2] < y[2] end)
	local tg = {}
	for k = 1, math.min(NEAR, #list) do tg[k] = World(spots[list[k][1]]) end
	local costs = Path.FindManySync(area.map, World(a), tg)
	if os.getenv("REV") then
		local back = Path.FindManySync(area.map, World(a), tg, nil, true)
		for k = 1, #tg do
			if costs[k] and back[k] then costs[k] = math.max(costs[k], back[k]) else costs[k] = false end
		end
	end
	local row, any = {}, false
	for k = 1, #tg do
		if costs[k] then any = true end
	end
	if any then
		for k = 1, #tg do
			row[list[k][1]] = costs[k] or false
			measured = measured + 1
		end
		f[i] = row
	end
end
f = O.DetourFactors(spots, f, SLACK, NO_WAY)
local tMeasure = clock() - t0
t0 = clock()
O.SetDetour(spots, f)
local walked = O.Shortcut(spots, SIGHT, true)
O.SetDetour(nil)
local tWalked = clock() - t0
-- repair: legs much longer on foot than the model thought pin their stops' spots, and it's worked out again
for round = 1, tonumber(os.getenv("REPAIR") or 0) do
	O.SetDetour(spots, f)
	local bad = 0
	for i = 1, #walked do
		local a, b = walked[i], walked[i % #walked + 1]
		local c = Path.FindManySync(area.map, World(a), { World(b) })[1]
		local model = O.Dist(a, b)
		if not c or c > model * 1.3 + 60 then
			for _, s in ipairs({ a, b }) do
				local node = s.node or (s.anchor and spots[s.anchor])
				if node and not node.pin then node.pin = true; bad = bad + 1 end
			end
		end
	end
	if bad == 0 then O.SetDetour(nil) break end
	walked = O.Shortcut(spots, SIGHT, true)
	O.SetDetour(nil)
	print(("repair %d: %d spots pinned"):format(round, bad))
end

O.SetDetour(spots, f)
print(("model (detours): straight route %d, walking route %d"):format(Straight(plain), Straight(walked)))
O.SetDetour(nil)
-- variant: the loop through the spots themselves, not moved (no placing)
O.SetDetour(spots, f)
local tour = O.Solve(spots)
O.SetDetour(nil)
local still = {}
for i, k in ipairs(tour) do still[i] = spots[k] end
local sFoot = OnFoot(still)
print(("walking, stops not moved: %d stops, %d yd drawn, %d yd on foot"):format(#still, Straight(still), sFoot))
local pFoot, pNone = OnFoot(plain)
local wFoot, wNone = OnFoot(walked)
print(("straight-line route: %d stops, %d yd drawn, %d yd on foot%s (solve %.2f s)"):format(
	#plain, Straight(plain), pFoot, pNone > 0 and (", " .. pNone .. " legs with no way") or "", tPlain))
print(("walking route:       %d stops, %d yd drawn, %d yd on foot%s (measure %.2f s for %d pairs, solve %.2f s)"):format(
	#walked, Straight(walked), wFoot, wNone > 0 and (", " .. wNone .. " legs with no way") or "", tMeasure, measured, tWalked))
if os.getenv("LEGS") then
	O.SetDetour(spots, f)
	local R = os.getenv("LEGS") == "w" and walked or plain
	for i = 1, #R do
		local a, b = R[i], R[i % #R + 1]
		local pts = Path.FindSync(area.map, World(a), World(b))
		local L = 0
		if pts then for k = 2, #pts do L = L + math.sqrt((pts[k].x - pts[k - 1].x) ^ 2 + (pts[k].y - pts[k - 1].y) ^ 2) end end
		local model = O.Dist(a, b)
		if L > model * 1.5 + 50 or model > L * 1.5 + 50 then
			print(("leg %2d: straight %5.0f  model %5.0f  foot %5.0f  anchors %s,%s  pts %d"):format(i, O.Euclid(a, b), model, L, tostring(a.anchor), tostring(b.anchor), pts and #pts or 0))
		end
	end
	O.SetDetour(nil)
end
if os.getenv("SOFT") then
	local soft = {}
	for i, row in pairs(f) do
		soft[i] = {}
		for j, v in pairs(row) do soft[i][j] = v ^ tonumber(os.getenv("SOFT")) end
	end
	for _, sp in ipairs(spots) do sp.pin = nil end
	O.SetDetour(spots, soft)
	local r = O.Shortcut(spots, SIGHT, true)
	O.SetDetour(nil)
	local sf = OnFoot(r)
	print(("soft %s: %+.1f%%"):format(os.getenv("SOFT"), (sf - pFoot) / pFoot * 100))
end
print(("on foot: %+.1f%%"):format((wFoot - pFoot) / pFoot * 100))
