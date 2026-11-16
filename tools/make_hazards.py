#!/usr/bin/env python3
"""Makes Hazards_Data.lua: ready-made no-go areas for routes.

 * Elite camps: open-world elite, rare elite and boss creatures from the CMaNGOS Classic database
   (GPL-3.0, https://github.com/cmangos/classic-db), spawns near each other joined into one area,
   with the levels they have.
 * Hostile towns: each faction's towns with a flight master, from Shortest Path Forever's data
   (GPL-3.0, cjber): its flight masters (Data/Taxi.lua) and the ground the game calls each town
   (Data/TownAreas.lua); a circle round the flight master where it has none.

Everything is in world yards (map = continent 0/1); Gatherline turns it into zone map positions in
the game. Usage:
  make_hazards.py <ClassicDB_*.sql.gz> <spf data dump (tools/dump_spf.lua output)> > Hazards_Data.lua
"""
import gzip, math, re, sys
from collections import Counter, defaultdict

sql_path, spf_dump = sys.argv[1], sys.argv[2]
env = {}
exec(open(spf_dump).read(), {"dict": dict, "None": None}, env)
TAXI, ZONES, TOWNS = env["TAXI"], env["ZONES"], env["TOWNS"]

# ---------------------------------------------------------------- SQL
import os
sys.path.insert(0, os.path.dirname(__file__))
from make_hazards_sql import columns, rows   # noqa: E402

text = gzip.open(sql_path, "rt", encoding="utf-8", errors="replace").read()
tcols, ccols = columns(text, "creature_template"), columns(text, "creature")
T = {c: k for k, c in enumerate(tcols)}
Cc = {c: k for k, c in enumerate(ccols)}
templates = {}
for line in text.splitlines():
    if line.startswith("INSERT INTO `creature_template` VALUES"):
        for r in rows(line):
            rank = int(r[T["Rank"]])
            if rank not in (1, 2, 3):          # elite, rare elite, boss
                continue
            if int(r[T["NpcFlags"]]) != 0:       # vendors, trainers, guards that talk
                continue
            if int(r[T["UnitFlags"]]) & (0x2 | 0x2000000):   # can't be attacked or selected
                continue
            templates[int(r[T["Entry"]])] = (r[T["Name"]], int(r[T["MinLevel"]]), int(r[T["MaxLevel"]]))
spawns = []
for line in text.splitlines():
    if line.startswith("INSERT INTO `creature` VALUES"):
        for r in rows(line):
            t = templates.get(int(r[Cc["id"]]))
            m = int(r[Cc["map"]])
            if t and m in (0, 1):
                spawns.append((m, float(r[Cc["position_x"]]), float(r[Cc["position_y"]]), t))
del text

# ---------------------------------------------------------------- where not to look
cities = [z for z in ZONES.values() if z["city"]]
def in_city(m, x, y):
    return any(z["map"] == m and z["minX"] <= x <= z["maxX"] and z["minY"] <= y <= z["maxY"] for z in cities)
def near_flight_master(m, x, y, r=300):
    return any(n["map"] == m and (n["x"] - x) ** 2 + (n["y"] - y) ** 2 <= r * r for n in TAXI.values())
spawns = [s for s in spawns if not in_city(s[0], s[1], s[2]) and not near_flight_master(s[0], s[1], s[2])]

# ---------------------------------------------------------------- geometry
def hull(points):
    pts = sorted(set(points))
    if len(pts) <= 2:
        return pts
    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]

def padded(points, pad, sides=8):
    ring = []
    for x, y in points:
        for k in range(sides):
            a = 2 * math.pi * (k + 0.5) / sides
            ring.append((round(x + pad * math.cos(a)), round(y + pad * math.sin(a))))
    return hull(ring)

def simplify(poly, most=16):
    """Drop the corners that matter least until at most `most` are left."""
    poly = list(poly)
    while len(poly) > most:
        best, bi = None, None
        for i in range(len(poly)):
            a, b, c = poly[i - 1], poly[i], poly[(i + 1) % len(poly)]
            area = abs((b[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (b[1] - a[1]))
            if best is None or area < best:
                best, bi = area, i
        poly.pop(bi)
    return poly

# ---------------------------------------------------------------- elite camps
JOIN, PAD = 45, 25      # spawns this close are one camp; the area reaches this far past them
TILE = 120              # a long camp is outlined in squares of this many yards
camps = []
for m in (0, 1):
    pts = [s for s in spawns if s[0] == m]
    grid = defaultdict(list)
    for k, s in enumerate(pts):
        grid[(int(s[1] // JOIN), int(s[2] // JOIN))].append(k)
    seen = [False] * len(pts)
    for k in range(len(pts)):
        if seen[k]:
            continue
        seen[k] = True
        group, stack = [], [k]
        while stack:
            a = stack.pop()
            group.append(pts[a])
            gx, gy = int(pts[a][1] // JOIN), int(pts[a][2] // JOIN)
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    for b in grid[(gx + dx, gy + dy)]:
                        if not seen[b] and (pts[a][1] - pts[b][1]) ** 2 + (pts[a][2] - pts[b][2]) ** 2 <= JOIN * JOIN:
                            seen[b] = True
                            stack.append(b)
        names = Counter(s[3][0] for s in group)
        low = min(s[3][1] for s in group)
        high = max(s[3][2] for s in group)
        # a camp strung out a long way (a town, a valley) is cut in tiles, each its own outline,
        # so the empty ground between its ends stays open
        tiles = defaultdict(list)
        for s in group:
            tiles[(int(s[1] // TILE), int(s[2] // TILE))].append((s[1], s[2]))
        polys = [simplify(padded(t, PAD)) for _, t in sorted(tiles.items())]
        cx = sum(s[1] for s in group) / len(group)
        cy = sum(s[2] for s in group) / len(group)
        camps.append((m, low, high, names.most_common(1)[0][0], len(group), round(cx), round(cy), polys))
camps.sort(key=lambda c: (c[0], c[5], c[6]))

# ---------------------------------------------------------------- hostile towns
B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
CELL = 100 / 3
def town_poly(area):
    corners, cell = [], 0
    for ch in area["cells"]:
        v = B64.index(ch)
        for bit in range(5, -1, -1):
            if v >> bit & 1:
                i, j = cell // area["h"], cell % area["h"]
                x0, y0 = (area["i0"] + i) * CELL, (area["j0"] + j) * CELL
                corners += [(round(x0), round(y0)), (round(x0 + CELL), round(y0)), (round(x0), round(y0 + CELL)), (round(x0 + CELL), round(y0 + CELL))]
            cell += 1
    return simplify(hull(corners), 20)

towns = []
for fid, n in sorted(TAXI.items()):
    if not n["faction"] or in_city(n["map"], n["x"], n["y"]):
        continue
    # a town both sides use (Booty Bay) has a flight master of each: not hostile to anyone
    shared = any(o["map"] == n["map"] and o["faction"] and o["faction"] != n["faction"]
                 and (o["x"] - n["x"]) ** 2 + (o["y"] - n["y"]) ** 2 <= 400 ** 2 for o in TAXI.values())
    if shared:
        continue
    area = TOWNS.get(fid)
    poly = town_poly(area) if area else simplify(padded([(n["x"], n["y"])], 150, 12))
    name = (n["name"] or "?").split(",")[0]
    towns.append((fid, n["faction"], n["map"], name, poly))

# ---------------------------------------------------------------- write
def q(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'
out = [
    "-- Gatherline: ready-made no-go areas, in world yards (map 0 = Eastern Kingdoms, 1 = Kalimdor).",
    "-- Made by tools/make_hazards.py. Don't edit by hand.",
    "-- Elite camps from the CMaNGOS Classic database (GPL-3.0, https://github.com/cmangos/classic-db):",
    "--   { map, lowest level, highest level, name, spawns, centre x, centre y, { x1, y1, x2, y2, ... }, ... }",
    "-- Hostile towns from Shortest Path Forever's flight masters and town ground (GPL-3.0, cjber):",
    "--   { flight master, faction, map, name, x1, y1, x2, y2, ... }",
    "local ADDON, ns = ...",
    "ns.HAZARD_CAMPS = {",
]
for m, low, high, name, n, cx, cy, polys in camps:
    out.append("    { %d, %d, %d, %s, %d, %d, %d, %s }," % (m, low, high, q(name), n, cx, cy,
        ", ".join("{ " + ", ".join("%d, %d" % p for p in poly) + " }" for poly in polys)))
out.append("}")
out.append("ns.HAZARD_TOWNS = {")
for fid, fac, m, name, poly in towns:
    out.append("    { %d, %s, %d, %s, %s }," % (fid, q(fac), m, q(name), ", ".join("%d, %d" % p for p in poly)))
out.append("}")
print("\n".join(out))
print("-- %d camps, %d towns" % (len(camps), len(towns)), file=sys.stderr)
