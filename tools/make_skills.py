#!/usr/bin/env python3
"""Makes Skills_Data.lua: the gathering skill each herb and ore needs, by its
name in every language GatherLite (MIT, (c) 2019 Wuild) has.
Usage: make_skills.py <gatherlite checkout> > Skills_Data.lua"""
import re, sys, os
src = sys.argv[1]
nodes = open(os.path.join(src, "scripts/nodes.lua"), encoding="utf-8").read()
nodes = re.sub(r"\n\s+", " ", nodes)
objs = []
for m in re.finditer(r'InsertObject\("(ore|herb)",\s*\{[^}]*\},\s*"(\w+)",\s*"[^"]*",\s*\{([^}]*)\}(?:,\s*\{([^}]*)\})?', nodes):
    kind, key, levels, aliases = m.groups()
    lv = [int(x) for x in re.findall(r"\d+", levels)]
    keys = [key] + (re.findall(r'"(\w+)"', aliases) if aliases else [])
    objs.append((kind, keys, lv))
names = {}
for f in sorted(os.listdir(os.path.join(src, "scripts/locales"))):
    text = open(os.path.join(src, "scripts/locales", f), encoding="utf-8").read()
    for k, v in re.findall(r'''L\[["']node\.(\w+)["']\]\s*=\s*"((?:[^"\\]|\\.)*)"''', text):
        names.setdefault(k, set()).add(v)
out = ["-- Gatherline: the gathering skill each herb and ore needs { orange, yellow,",
       "-- green, grey } (only the first if that's all that's known), by name in every",
       "-- language. Made by tools/make_skills.py from GatherLite's node list",
       "-- (MIT, (c) 2019 Wuild). Don't edit by hand.",
       "local ADDON, ns = ...",
       "ns.NODE_SKILL = {"]
seen = {}
for kind, keys, lv in objs:
    k = "Mining" if kind == "ore" else "Herb Gathering"
    for key in keys:
        for n in sorted(names.get(key, ())):
            if n in seen: continue
            seen[n] = True
            out.append('    ["%s"] = { "%s", %s },' % (n.replace('\\','\\\\').replace('"','\\"'), k, ", ".join(map(str, lv))))
out.append("}")
print("\n".join(out))
