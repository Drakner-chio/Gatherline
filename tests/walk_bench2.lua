-- Which extra work pays: GroundLoop's way (candidates walked leg by leg, the shortest kept) with more
-- neighbours measured and more candidates. Prints each set-up's best against the straight-line loop, on foot.
--   luajit -joff tests/walk_bench2.lua <spf checkout> <area> [nodes] [sight] [seed]
local spf = assert(arg[1])
local AREAS = {
	dunmorogh = { map = 0, top = -4800, left = -500, w = 2600, h = 1500 },
	elwynn = { map = 0, top = -8800, left = 600, w = 1600, h = 1066 },
	lochmodan = { map = 0, top = -4800, left = -2700, w = 1800, h = 1500 },
	ashenvale = { map = 1, top = 3800, left = 900, w = 2400, h = 1600 },
	barrens = { map = 1, top = 1200, left = -1000, w = 2600, h = 3000 },
}
local area = assert(AREAS[arg[2]])
local COUNT, SIGHT, SEED = tonumber(arg[3]) or 250, tonumber(arg[4]) or 185, tonumber(arg[5]) or 11
assert(loadfile(spf .. "/tools/load_nav.lua"))(area.map, spf)
local ns = { GP = { Print = print } }
for _, f in ipairs({ "Optimize.lua", "Routing/PathCeiling.lua", "Routing/PathGrid.lua", "Routing/Path.lua", "Routing/PathJobs.lua" }) do
	assert(loadfile(f))("Gatherline", ns)
end
local O, Path = ns.Optimize, ns.Path
local function World(p) return { x = area.top - p[2], y = area.left - p[1] } end

math.randomseed(SEED)
local mid = World({ area.w / 2, area.h / 2 })
local cands, targets = {}, {}
for i = 1, COUNT * 4 do cands[i] = { math.random() * area.w, math.random() * area.h }; targets[i] = World(cands[i]) end
local reach = Path.FindManySync(area.map, mid, targets)
local nodes = {}
for i, c in ipairs(cands) do
	local st = math.sqrt((targets[i].x - mid.x) ^ 2 + (targets[i].y - mid.y) ^ 2)
	if reach[i] and reach[i] <= st * 1.6 + 150 and #nodes < COUNT then nodes[#nodes + 1] = c end
end
local spots = O.GroupFor(nodes, SIGHT)

-- the game's yardstick: cost of each leg (what Walk.Cost answers), cached
local legCache, legCount = {}, 0
local function Leg(a, b)
	local ka, kb = ("%.1f,%.1f"):format(a[1], a[2]), ("%.1f,%.1f"):format(b[1], b[2])
	if ka > kb then ka, kb = kb, ka end
	local key = ka .. ">" .. kb
	local c = legCache[key]
	if c == nil then
		c = Path.FindManySync(area.map, World(a), { World(b) })[1] or false
		legCache[key] = c
		legCount = legCount + 1
	end
	return c
end
local function Loop(stops)
	local total, legs = 0, {}
	for i = 1, #stops do
		local c = Leg(stops[i], stops[i % #stops + 1])
		legs[i] = c
		total = total + (c or O.Euclid(stops[i], stops[i % #stops + 1]) * 25)
	end
	return total, legs
end
-- and the honest score: polyline yards
local function Poly(stops)
	local total = 0
	for i = 1, #stops do
		local pts = Path.FindSync(area.map, World(stops[i]), World(stops[i % #stops + 1]))
		if pts then
			for k = 2, #pts do total = total + math.sqrt((pts[k].x - pts[k - 1].x) ^ 2 + (pts[k].y - pts[k - 1].y) ^ 2) end
		end
	end
	return total
end

local function Factors(near)
	local f = {}
	for i, a in ipairs(spots) do
		local list = {}
		for j, b in ipairs(spots) do
			if j ~= i then list[#list + 1] = { j, O.Euclid(a, b) } end
		end
		table.sort(list, function(x, y) return x[2] < y[2] end)
		local tg = {}
		for k = 1, math.min(near, #list) do tg[k] = World(spots[list[k][1]]) end
		local costs = Path.FindManySync(area.map, World(a), tg)
		local row = {}
		for k = 1, #tg do row[list[k][1]] = costs[k] or false end
		f[i] = row
	end
	return O.DetourFactors(spots, f, 40, 25)
end

local function Candidate(factors, repairs)
	for _, sp in ipairs(spots) do sp.pin = nil end
	if factors then O.SetDetour(spots, factors) end
	local loop = O.Shortcut(spots, SIGHT, true)
	O.SetDetour(nil)
	local foot, legs = Loop(loop)
	for _ = 1, factors and repairs or 0 do
		O.SetDetour(spots, factors)
		local pinned = 0
		for i = 1, #loop do
			local a, b = loop[i], loop[i % #loop + 1]
			if legs[i] == false or legs[i] > O.Dist(a, b) * 1.3 + 60 then
				for _, st in ipairs({ a, b }) do
					local node = st.node or (st.anchor and spots[st.anchor])
					if node and not node.pin then node.pin = true; pinned = pinned + 1 end
				end
			end
		end
		if pinned == 0 then O.SetDetour(nil) break end
		local again = O.Shortcut(spots, SIGHT, true)
		O.SetDetour(nil)
		local f2, l2 = Loop(again)
		if f2 < foot then loop, foot, legs = again, f2, l2 else break end
	end
	return loop, foot
end
local function Pow(f, k)
	local out = {}
	for i, row in pairs(f) do
		out[i] = {}
		for j, v in pairs(row) do out[i][j] = v ^ k end
	end
	return out
end

-- polish with real legs: 2-opt and moving one stop, judged by walked legs
local function Polish(stops, passes, K)
	local n = #stops
	local order = {}
	for i = 1, n do order[i] = stops[i] end
	local function L(a, b)
		local c = Leg(a, b)
		return c or O.Euclid(a, b) * 25
	end
	for _ = 1, passes do
		local better = false
		-- near lists by straight yards
		local near = {}
		for i = 1, n do
			local list = {}
			for j = 1, n do if j ~= i then list[#list + 1] = { j, O.Euclid(order[i], order[j]) } end end
			table.sort(list, function(x, y) return x[2] < y[2] end)
			near[i] = {}
			for k = 1, math.min(K, #list) do near[i][k] = list[k][1] end
		end
		local pos = {}
		for i = 1, n do pos[order[i]] = i end
		local idx = {}
		for i = 1, n do idx[i] = order[i] end
		for i = 1, n do
			for _, jj in ipairs(near[i]) do
				local a, b = i, jj
				if a > b then a, b = b, a end
				if b - a >= 2 and not (a == 1 and b == n) then
					local A, A1, B, B1 = order[a], order[a + 1], order[b], order[b % n + 1]
					local d = L(A, B) + L(A1, B1) - L(A, A1) - L(B, B1)
					if d < -1 then
						-- reverse a+1..b, then check the whole loop really got shorter
						local before = Loop(order)
						local i1, j1 = a + 1, b
						while i1 < j1 do order[i1], order[j1] = order[j1], order[i1]; i1, j1 = i1 + 1, j1 - 1 end
						if Loop(order) < before - 1 then better = true else
							i1, j1 = a + 1, b
							while i1 < j1 do order[i1], order[j1] = order[j1], order[i1]; i1, j1 = i1 + 1, j1 - 1 end
						end
					end
				end
			end
		end
		-- move one stop to between two others
		for i = 1, n do
			local s = order[i]
			local P, N = order[i == 1 and n or i - 1], order[i % n + 1]
			local gain = L(P, s) + L(s, N) - L(P, N)
			for _, jj in ipairs(near[i]) do
				local cur = 0
				for q = 1, n do if order[q] == stops[0] then cur = q end end
				local j = 0
				for q = 1, n do if order[q] == idx[jj] then j = q end end
				if j ~= 0 then
					for _, side in ipairs({ 0, -1 }) do
						local u = j + side
						if u < 1 then u = n end
						local U, V = order[u], order[u % n + 1]
						if U ~= s and V ~= s then
							local cost = L(U, s) + L(s, V) - L(U, V)
							if cost < gain - 1 then
								local before = Loop(order)
								local copy = {}
								for q = 1, n do copy[q] = order[q] end
								local si
								for q = 1, n do if order[q] == s then si = q end end
								table.remove(order, si)
								local ui
								for q = 1, #order do if order[q] == U then ui = q end end
								table.insert(order, ui + 1, s)
								if Loop(order) < before - 1 then better = true; gain = 0 else
									for q = 1, n do order[q] = copy[q] end
								end
							end
						end
					end
				end
			end
		end
		if not better then break end
	end
	return order
end

local straight, sFoot = Candidate(nil, 0)
local sPoly = Poly(straight)
print(("%s seed %d: %d spots, straight loop %d yd on foot"):format(arg[2], SEED, #spots, sPoly))
local SETUPS = os.getenv("ALL") and {
	{ "now: near 8, k 1/0.5", 8, { 1, 0.5 }, 2 },
	{ "near 16, k 1/0.5", 16, { 1, 0.5 }, 2 },
	{ "near 8, k 1/.75/.5/.25", 8, { 1, 0.75, 0.5, 0.25 }, 2 },
	{ "near 16, k 1/.75/.5/.25", 16, { 1, 0.75, 0.5, 0.25 }, 3, true },
	{ "near 24, k 1/.75/.5/.25", 24, { 1, 0.75, 0.5, 0.25 }, 3 },
} or { { "0.3.0: near 16, k 1/.75/.5/.25", 16, { 1, 0.75, 0.5, 0.25 }, 3, true } }
local fCache = {}
for _, setup in ipairs(SETUPS) do
	local t0 = os.clock()
	legCount = 0
	local f = fCache[setup[2]] or Factors(setup[2])
	fCache[setup[2]] = f
	local best, bestFoot = straight, sFoot
	for _, k in ipairs(setup[3]) do
		local loop, foot = Candidate(Pow(f, k), setup[4])
		if foot < bestFoot then best, bestFoot = loop, foot end
	end
	local p = Poly(best)
	print(("  %-26s %+6.1f%%  (%.1f s, %d legs walked)"):format(setup[1], (p - sPoly) / sPoly * 100, os.clock() - t0, legCount))
	if setup[5] then
		t0, legCount = os.clock(), 0
		local pol = O.Polish(best, function(a, b) return Leg(a, b) or O.Euclid(a, b) * 25 end, 6, 8)
		local pp = Poly(pol)
		print(("  %-26s %+6.1f%%  (%.1f s, %d legs walked)"):format("  + polished", (pp - sPoly) / sPoly * 100, os.clock() - t0, legCount))
		t0, legCount = os.clock(), 0
		local pol2 = O.Polish(straight, function(a, b) return Leg(a, b) or O.Euclid(a, b) * 25 end, 6, 8)
		print(("  %-26s %+6.1f%%  (%.1f s, %d legs walked)"):format("  straight polished", (Poly(pol2) - sPoly) / sPoly * 100, os.clock() - t0, legCount))
	end
end
