#!/usr/bin/env python3
"""Makes Loot_Data.lua: what gathering a herb or ore node yields, on average, by its English name,
from the CMaNGOS Classic database (GPL-3.0, https://github.com/cmangos/classic-db).
  ns.NODE_LOOT["Copper Vein"] = { itemID, expected count per gathering, ... }
Usage: make_loot.py <ClassicDB_*.sql.gz> <Skills_Data.lua> > Loot_Data.lua"""
import gzip, re, sys
from collections import defaultdict
sys.path.insert(0, __import__("os").path.dirname(__file__))
from make_hazards_sql import columns, rows   # noqa: E402

sql_path, skills = sys.argv[1], sys.argv[2]
wanted = set(re.findall(r'^\s+\["([^"]+)"\] = \{ "(?:Mining|Herb Gathering)"', open(skills, encoding="utf-8").read(), re.M))
text = gzip.open(sql_path, "rt", encoding="utf-8", errors="replace").read()

def table(name):
    cols = {c: k for k, c in enumerate(columns(text, name))}
    out = []
    for line in text.splitlines():
        if line.startswith("INSERT INTO `%s` VALUES" % name):
            out.extend(rows(line))
    return cols, out

gc, gos = table("gameobject_template")
lc, loot = table("gameobject_loot_template")
rc, refs = table("reference_loot_template")
del globals()["text"]

def by_entry(cols, rs):
    d = defaultdict(list)
    for r in rs:
        d[int(r[cols["entry"]])].append(r)
    return d
LOOT, REFS = by_entry(lc, loot), by_entry(rc, refs)

def expected(entries, cols, depth=0):
    """item -> expected count from one roll of this loot table"""
    out = defaultdict(float)
    groups = defaultdict(list)
    for r in entries:
        groups[int(r[cols["groupid"]])].append(r)
    for g, rs in groups.items():
        if g == 0:
            shares = [(r, abs(float(r[cols["ChanceOrQuestChance"]])) / 100) for r in rs]
        else:
            explicit = sum(abs(float(r[cols["ChanceOrQuestChance"]])) for r in rs if float(r[cols["ChanceOrQuestChance"]]) != 0)
            zero = [r for r in rs if float(r[cols["ChanceOrQuestChance"]]) == 0]
            rest = max(0.0, 100 - explicit) / len(zero) if zero else 0
            shares = [(r, (abs(float(r[cols["ChanceOrQuestChance"]])) or rest) / 100) for r in rs]
        for r, p in shares:
            mn, mx = int(r[cols["mincountOrRef"]]), int(r[cols["maxcount"]])
            if mn < 0:
                if depth < 3:
                    for item, e in expected(REFS.get(-mn, []), rc, depth + 1).items():
                        out[item] += p * mx * e
            else:
                out[int(r[cols["item"]])] += p * (mn + max(mn, mx)) / 2
    return out

per_name = defaultdict(list)
for r in gos:
    name = r[gc["name"]]
    if name not in wanted or int(r[gc["type"]]) != 3:
        continue
    lid = int(r[gc["data1"]])
    if lid in LOOT:
        uses_lo, uses_hi = int(r[gc["data4"]]), int(r[gc["data5"]])
        uses = (uses_lo + uses_hi) / 2 if uses_hi > 0 else 1
        per_name[name].append((expected(LOOT[lid], lc), uses))

print("-- Gatherline: what gathering a node yields on average, by its English name: { itemID, count, ... }.")
print("-- From the CMaNGOS Classic database (GPL-3.0, https://github.com/cmangos/classic-db).")
print("-- Made by tools/make_loot.py. Don't edit by hand.")
print("local ADDON, ns = ...")
print("ns.NODE_LOOT = {")
for name in sorted(per_name):
    tot = defaultdict(float)
    for e, uses in per_name[name]:
        for item, n in e.items():
            tot[item] += n * uses / len(per_name[name])
    items = sorted(((i, n) for i, n in tot.items() if n >= 0.02), key=lambda x: -x[1])
    if items:
        print('    ["%s"] = { %s },' % (name.replace('"', '\\"'), ", ".join("%d, %.2f" % (i, n) for i, n in items)))
print("}")
