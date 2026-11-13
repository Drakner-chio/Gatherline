-- Gatherline's copy of the walking search and Shortest Path Forever's own one, side by side on the same walking
-- maps, both short of memory so they keep dropping decoded strings: neither may trip over the other.
--   luajit tests/shared_data_spec.lua <shortest-path-forever checkout>
local spf = assert(arg[1], "usage: luajit tests/shared_data_spec.lua <shortest-path-forever checkout>")
assert(loadfile(spf .. "/tools/load_nav.lua"))(0, spf, nil, true)   -- packed, as in the game
assert(ShortestPathForeverPathData[0].packed, "the walking maps are packed, as in the game")

local theirs, ours = {}, {}
for _, f in ipairs({ "PathGrid.lua", "Path.lua", "PathJobs.lua" }) do
	assert(loadfile(spf .. "/Routing/" .. f))("ShortestPathForever", theirs)
	assert(loadfile("Routing/" .. f))("Gatherline", ours)
end
for _, P in ipairs({ theirs.Path, ours.Path }) do P.graphKB, P.cacheKB = 64, 256 end

-- points round Elwynn and Westfall
math.randomseed(5)
local pts = {}
for i = 1, 40 do pts[i] = { map = 0, x = -9000 - math.random() * 1600, y = 900 - math.random() * 2400 } end

local runs, found = 0, 0
for round = 1, 60 do
	for _, P in ipairs(round % 2 == 0 and { theirs.Path, ours.Path } or { ours.Path, theirs.Path }) do
		local a = pts[math.random(#pts)]
		local list = {}
		for k = 1, 6 do list[k] = pts[math.random(#pts)] end
		local costs = P.FindManySync(0, a, list)
		runs = runs + 1
		for k = 1, 6 do if costs[k] then found = found + 1 end end
		local b = pts[math.random(#pts)]
		P.FindSync(0, a, b)
	end
end
assert(found > 0, "walks found")
print(("shared_data_spec: ok (%d searches, %d walks found)"):format(runs, found))
