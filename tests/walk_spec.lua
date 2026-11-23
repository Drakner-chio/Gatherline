-- Walk.lua with the copied walking search, on Shortest Path Forever's real walking maps.
-- Needs LuaJIT and a Shortest Path Forever checkout (its Nav/ files and tools/load_nav.lua):
--   luajit tests/walk_spec.lua ../shortest-path-forever
local spf = assert(arg[1], "usage: luajit tests/walk_spec.lua <shortest-path-forever checkout>")
assert(loadfile(spf .. "/tools/load_nav.lua"))(0, spf)

-- A made-up Elwynn Forest: its top left corner at world (x -8800, y 600), 1600 yards across (y falls going
-- east), 1066 down (x falls going south). World x runs north, y west.
local TOP, LEFT, W, H, ZONE = -8800, 600, 1600, 1066, 1429
function CreateVector2D(x, y)
	return { x = x, y = y, GetXY = function(self) return self.x, self.y end }
end
C_Map = {}
function C_Map.GetWorldPosFromMapPos(mapID, v)
	if mapID ~= ZONE then return nil end
	return 0, CreateVector2D(TOP - v.y * H, LEFT - v.x * W)
end
function C_Map.GetMapPosFromWorldPos(continent, v, mapID)
	if continent ~= 0 or mapID ~= ZONE then return nil end
	return mapID, CreateVector2D((LEFT - v.y) / W, (TOP - v.x) / H)
end
local frames = {}
C_Timer = { After = function(_, fn) frames[#frames + 1] = fn end }
function InCombatLockdown() return false end
local function drain()
	local guard = 0
	while #frames > 0 and guard < 100000 do
		table.remove(frames, 1)()
		guard = guard + 1
	end
end

local ns = { GP = { Print = print } }
for _, f in ipairs({ "Routing/PathCeiling.lua", "Routing/PathGrid.lua", "Routing/Path.lua", "Routing/PathJobs.lua", "Walk.lua" }) do
	assert(loadfile(f))("Gatherline", ns)
end
local Walk = ns.GP.Walk

local function MapPos(wx, wy) return (LEFT - wy) / W, (TOP - wx) / H end
local GOLDSHIRE = { MapPos(-9459, 43) }
local NORTHSHIRE = { MapPos(-8914, -135) }
local EAST = { MapPos(-9300, -700) }   -- east along the forest
local LAKE = { MapPos(-9400, -1100) }   -- toward Stone Cairn Lake / the east end

assert(Walk.Ready(ZONE), "walking maps ready")
local p = Walk.Point(ZONE, GOLDSHIRE[1], GOLDSHIRE[2])
assert(math.abs(p.x + 9459) < 0.01 and math.abs(p.y - 43) < 0.01 and p.map == 0, "map position to world yards")
local bx, by = Walk.MapPos(ZONE, p)
assert(math.abs(bx - GOLDSHIRE[1]) < 1e-9 and math.abs(by - GOLDSHIRE[2]) < 1e-9, "and back")

local function straight(a, b) return math.sqrt(((a[1] - b[1]) * W) ^ 2 + ((a[2] - b[2]) * H) ^ 2) end

local got
Walk.Cost(ZONE, GOLDSHIRE[1], GOLDSHIRE[2], NORTHSHIRE[1], NORTHSHIRE[2], function(y, why) got = { y, why } end)
drain()
assert(got and got[1], "Goldshire to Northshire on foot: " .. tostring(got and got[2]))
local s = straight(GOLDSHIRE, NORTHSHIRE)
print(("Goldshire -> Northshire: %d yards on foot, %d straight (x%.2f)"):format(got[1], s, got[1] / s))
assert(got[1] >= s * 0.97, "never shorter than a straight line")

local many
Walk.Costs(ZONE, GOLDSHIRE[1], GOLDSHIRE[2], { NORTHSHIRE, EAST, LAKE }, function(c, why) many = { c, why } end)
drain()
assert(many and many[1], "costs to several stops: " .. tostring(many and many[2]))
for i, t in ipairs({ NORTHSHIRE, EAST, LAKE }) do
	local c = many[1][i]
	print(("  stop %d: %s yards on foot, %d straight"):format(i, c and ("%d"):format(c) or "no way", straight(GOLDSHIRE, t)))
	assert(c == false or c >= straight(GOLDSHIRE, t) * 0.97)
end
assert(math.abs(many[1][1] - got[1]) < 1, "one-to-many agrees with one-to-one")

local line
Walk.Line(ZONE, GOLDSHIRE[1], GOLDSHIRE[2], NORTHSHIRE[1], NORTHSHIRE[2], function(xy, c) line = { xy, c } end)
drain()
assert(line and line[1] and #line[1] >= 4, "the way on foot as map positions")
local fx, fy, lx, ly = line[1][1], line[1][2], line[1][#line[1] - 1], line[1][#line[1]]
assert(straight({ fx, fy }, GOLDSHIRE) < 15 and straight({ lx, ly }, NORTHSHIRE) < 15, "from start to goal")
print(("  the line: %d bends"):format(#line[1] / 2))

-- a spot off the walking map (far out at sea) gives a reason, not an error
local off
Walk.Cost(ZONE, GOLDSHIRE[1], GOLDSHIRE[2], 40, 40, function(y, why) off = { y, why } end)
drain()
assert(off and off[1] == nil and off[2], "off the map: no yards, a reason (" .. tostring(off and off[2]) .. ")")

print("walk_spec: ok")
