-- dumps SPF's taxi nodes, zones and town areas as Python literals
local spf = arg[1]
local ns = {}
for _, f in ipairs({ "Data/Taxi.lua", "Data/Zones.lua", "Data/TownAreas.lua" }) do
  assert(loadfile(spf .. "/" .. f))("ShortestPathForever", ns)
end
local function q(s) return (string.format("%q", tostring(s)):gsub("\\\n", "\\n")) end
io.write("TAXI = {\n")
for id, n in pairs(ns.TaxiNodes) do
  io.write(("  %d: dict(map=%d, x=%.1f, y=%.1f, faction=%s, name=%s),\n"):format(id, n.map, n.x, n.y,
    n.faction and q(n.faction) or "None", n.name and q(n.name) or "None"))
end
io.write("}\nZONES = {\n")
for id, z in pairs(ns.Zones) do
  io.write(("  %d: dict(map=%s, minX=%s, minY=%s, maxX=%s, maxY=%s, city=%s, low=%s),\n"):format(id, tostring(z.map), tostring(z.minX), tostring(z.minY), tostring(z.maxX), tostring(z.maxY), z.city and q(z.city) or "None", tostring(z.low or "None")))
end
io.write("}\nTOWNS = {\n")
for id, t in pairs(ns.TownAreas) do
  io.write(("  %d: dict(area=%d, map=%d, i0=%d, j0=%d, w=%d, h=%d, cells=%s),\n"):format(id, t.area, t.map, t.i0, t.j0, t.w, t.h, q(t.cells)))
end
io.write("}\n")
