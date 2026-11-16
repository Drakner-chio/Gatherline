"""SQL dump helpers for make_hazards.py and make_loot.py."""
import re


def columns(text, table):
    m = re.search(r"CREATE TABLE `%s` \((.*?)\n\) ENGINE" % table, text, re.S)
    return [c for c in re.findall(r"^\s+`(\w+)`", m.group(1), re.M)]

def rows(line):
    """The tuples of one INSERT ... VALUES (...),(...); line."""
    i = line.index("VALUES ") + 7
    n = len(line)
    while i < n:
        if line[i] != "(":
            i += 1
            continue
        i += 1
        row, cur, quoted = [], [], False
        while True:
            ch = line[i]
            if quoted:
                if ch == "\\":
                    cur.append(line[i + 1]); i += 2; continue
                if ch == "'":
                    quoted = False; i += 1; continue
                cur.append(ch); i += 1; continue
            if ch == "'":
                quoted = True; i += 1; continue
            if ch == "," :
                row.append("".join(cur)); cur = []; i += 1; continue
            if ch == ")":
                row.append("".join(cur)); i += 1; break
            cur.append(ch); i += 1
        yield row

