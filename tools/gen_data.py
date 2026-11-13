#!/usr/bin/env python3
"""Generate Data/Families.lua, Data/Skills.lua and Data/Beasts.lua for UltimatePet.

Python 3, standard library only. Run from anywhere:

    python3 -I tools/gen_data.py [--petopia FILE] [--tl DIR] [--wowhead DIR] [--out DIR]

Inputs (local snapshots, nothing is fetched):
  --petopia  Petopia Forever abilities page saved as HTML (abilities-YYYY-MM-DD.html).
             Ranks, pet level, TP cost, source type, teaching beasts, family matrix, icon names.
  --tl       TrueshotLodge checkout (MIT). data/Abilities.lua (spell ids, TP, npc ids per rank,
             learned_by) and data/NPCs.lua (names, families, levels, class, map points).
  --wowhead  Directory with Wowhead abilities-*.html snapshots. Spell id / level cross-check,
             the "New" (Forever) flag per rank, and icon names for abilities Petopia lacks.

Writes the three Lua files and tools/DATA_NOTES.md, and prints the same report to stdout.
"""

import argparse
import glob
import html
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_PETOPIA = os.path.join(REPO, ".ai", "petopia", "abilities-2026-11-13.html")
DEFAULT_WOWHEAD = os.path.join(REPO, ".ai", "wowhead")
# Vendored copy of TrueshotLodge's data files (MIT); tools/sources/trueshotlodge/COMMIT pins the upstream commit.
DEFAULT_TL = os.environ.get("TRUESHOTLODGE", os.path.join(REPO, "tools", "sources", "trueshotlodge"))

FAMILIES = [
    "Bat", "Bear", "Bird of Prey", "Boar", "Carrion Bird", "Cat", "Core Hound", "Crab",
    "Crocolisk", "Fox", "Gorilla", "Hyena", "Raptor", "Scorpid", "Spider", "Tallstrider",
    "Turtle", "Wind Serpent", "Wolf",
]
PASSIVES = [
    "Great Stamina", "Natural Armor", "Arcane Resistance", "Fire Resistance",
    "Frost Resistance", "Nature Resistance", "Shadow Resistance",
]
# Display order: the attacks most families share first, then the rest alphabetically, then passives.
LEADING_ACTIVES = ["Bite", "Claw", "Dash", "Dive", "Charge", "Prowl", "Growl", "Cower"]
# Abilities added or reworked in WoW: Forever. A TP cost of 0 or 1 on these is a placeholder in the
# sources (Petopia shows 0 on all of them; TrueshotLodge shows 0, 1 or a guess) -> stored as unknown.
NEW_IN_FOREVER = [
    "Sonic Blast", "Swipe", "Mine!", "Demoralizing Screech", "Pinch", "Dismember", "Tendon Rip",
    "Savage Rend", "Web", "Dust Cloud", "Trickster's Dance", "Lava Breath",
]
# Two-letter export codes.
SKILL_CODES = {
    "Bite": "Bi", "Claw": "Cl", "Dash": "Da", "Prowl": "Pr", "Growl": "Gr", "Cower": "Co",
    "Swipe": "Sw", "Dive": "Dv", "Mine!": "Mi", "Lava Breath": "LB",
    "Great Stamina": "GS", "Natural Armor": "NA", "Arcane Resistance": "AR",
    "Fire Resistance": "FR", "Frost Resistance": "FT", "Nature Resistance": "NR",
    "Shadow Resistance": "SR",
    "Charge": "Ch", "Demoralizing Screech": "DS", "Dismember": "Di", "Dust Cloud": "DC",
    "Furious Howl": "FH", "Lightning Breath": "Li", "Pinch": "Pi", "Savage Rend": "Sv",
    "Scorpid Poison": "SP", "Shell Shield": "SS", "Sonic Blast": "SB", "Tendon Rip": "TR",
    "Thunderstomp": "Th", "Trickster's Dance": "TD", "Web": "We",
}
CLASS_TIER = {None: 0, "Rare": 1, "Elite": 2, "Rare Elite": 2}


def family_id(name):
    """Petopia's family id: lower case, no spaces ("Core Hound" -> "corehound")."""
    return name.lower().replace(" ", "")


def skill_key(name):
    """Stable key, the same style TrueshotLodge uses ("Trickster's Dance" -> "tricksters-dance")."""
    return re.sub(r"[^a-z0-9 ]", "", name.lower()).strip().replace(" ", "-")


# --------------------------------------------------------------------------------------------
# Lua table reader (enough for TrueshotLodge's generated data files)
# --------------------------------------------------------------------------------------------

LUA_TOKEN = re.compile(r"""\s*(?:(--[^\n]*)|("(?:[^"\\]|\\.)*")|(-?\d+(?:\.\d+)?)|([A-Za-z_][A-Za-z0-9_.]*)|(\S))""")


def lua_tokens(text):
    pos = 0
    while pos < len(text):
        m = LUA_TOKEN.match(text, pos)
        if not m or m.end() == pos:
            break
        pos = m.end()
        comment, string, number, name, sym = m.groups()
        if comment:
            continue
        if string is not None:
            yield ("str", string[1:-1].encode().decode("unicode_escape"))
        elif number is not None:
            yield ("num", float(number) if "." in number else int(number))
        elif name is not None:
            yield ("name", name)
        elif sym is not None:
            yield ("sym", sym)


class LuaReader:
    def __init__(self, text):
        self.toks = list(lua_tokens(text))
        self.i = 0

    def peek(self, k=0):
        return self.toks[self.i + k] if self.i + k < len(self.toks) else (None, None)

    def take(self):
        tok = self.toks[self.i]
        self.i += 1
        return tok

    def expect(self, value):
        tok = self.take()
        if tok[1] != value:
            raise ValueError("expected %r, got %r at token %d" % (value, tok, self.i))

    def value(self):
        kind, val = self.take()
        if kind in ("str", "num"):
            return val
        if kind == "name":
            return {"true": True, "false": False, "nil": None}.get(val, val)
        if val == "{":
            return self.table()
        raise ValueError("unexpected %r" % (val,))

    def table(self):
        items, arr = {}, []
        while self.peek()[1] != "}":
            if self.peek()[1] == "[":
                self.take()
                key = self.value()
                self.expect("]")
                self.expect("=")
                items[key] = self.value()
            elif self.peek()[0] == "name" and self.peek(1)[1] == "=":
                key = self.take()[1]
                self.take()
                items[key] = self.value()
            else:
                arr.append(self.value())
            if self.peek()[1] in (",", ";"):
                self.take()
        self.take()
        if arr and not items:
            return arr
        for n, v in enumerate(arr, 1):
            items[n] = v
        return items

    def assignments(self):
        """Top-level `Addon.X = {...}` statements -> {"X": table}."""
        out = {}
        while self.i < len(self.toks):
            kind, val = self.take()
            if kind == "name" and val.startswith("Addon.") and self.peek()[1] == "=":
                self.take()
                out[val.split(".", 1)[1]] = self.value()
        return out


def read_lua(path):
    with open(path, encoding="utf-8") as fh:
        return LuaReader(fh.read()).assignments()


PACK_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
PACK_VALUE = {c: i for i, c in enumerate(PACK_ALPHABET)}


def unpack_points(packed):
    """TrueshotLodge UnpackPoints (src/data.lua): 3 base-64 chars per point, n = x*501 + y."""
    points = []
    for i in range(0, len(packed) - 2, 3):
        a, b, c = packed[i:i + 3]
        n = PACK_VALUE[a] * 4096 + PACK_VALUE[b] * 64 + PACK_VALUE[c]
        points.append(((n // 501) / 5, (n % 501) / 5))
    return points


def representative_point(points, radius=5.0):
    """The spawn point at the centre of the densest cluster: the point with the most neighbours
    within `radius` (map percent), then the actual point nearest the centroid of that neighbourhood."""
    if not points:
        return None
    r2 = radius * radius

    def near(p):
        return [q for q in points if (q[0] - p[0]) ** 2 + (q[1] - p[1]) ** 2 <= r2]

    best = max(points, key=lambda p: (len(near(p)), -p[0], -p[1]))
    hood = near(best)
    cx = sum(q[0] for q in hood) / len(hood)
    cy = sum(q[1] for q in hood) / len(hood)
    return min(hood, key=lambda q: ((q[0] - cx) ** 2 + (q[1] - cy) ** 2, q))


# --------------------------------------------------------------------------------------------
# Petopia
# --------------------------------------------------------------------------------------------

PET_RANK = re.compile(
    r"[^']+' class='abilityrank[^']*'><span class='abilityrankname[^']*'>([^<]+)</span>:\s*"
    r"Pet Level (\d+), Cost (\d+) TP\.")
PET_NPC = re.compile(r"npc=(\d+)'>([^<]+)</a> \(([^,]+), ([^,]+), (.*?)\)</li>")
PET_SOURCE = {
    "Can be learned by taming:": "tame",
    "Can be learned from trainers.": "trainer",
    "No known training source.": "none",
}


def parse_level_range(text):
    parts = [int(x) for x in text.split("-")]
    return parts[0], parts[-1]


def read_petopia(path):
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    abilities = {}
    by_fid = {family_id(f): f for f in FAMILIES}
    sections = re.split(r"(?=<h3 class='guide_heading)", text)[1:]
    for sec in sections:
        head = re.match(r"<h3[^>]*id='([^']+)'><img[^>]*src='/images/icons/([^'.]+)\.png'>([^<]+)</h3>", sec)
        if not head:
            continue
        name = html.unescape(head.group(3)).strip()
        fams_html = re.search(r"ability_family_list [^>]*>(.*?)</span>", sec, re.S)
        fids = re.findall(r"family\.php\?id=([a-z]+)", fams_html.group(1)) if fams_html else []
        if fams_html and fams_html.group(1).strip() == "All Families":
            fids = list(by_fid)
        unknown = [f for f in fids if f not in by_fid]
        if unknown:
            raise SystemExit("Petopia lists an unknown family id: %s (%s)" % (unknown, name))
        ab = {"name": name, "icon": head.group(2), "families": {by_fid[f] for f in fids}, "ranks": {}}
        for chunk in sec.split("<li id='")[1:]:
            m = PET_RANK.match(chunk)
            if not m:
                continue
            chunk = re.split(r"<h3 |<li id=", chunk)[0]
            rname, rank = html.unescape(m.group(1)).rsplit(" ", 1)
            if rname != name:
                raise SystemExit("rank %r under ability %r" % (rname, name))
            heads = re.findall(r"abilitysourceheading[^>]*>([^<]+)<", chunk)
            if len(heads) != 1 or heads[0].strip() not in PET_SOURCE:
                raise SystemExit("unexpected source heading for %s %s: %r" % (name, rank, heads))
            npcs = []
            for nid, nname, fam, lv, zone in PET_NPC.findall(chunk):
                lo, hi = parse_level_range(lv)
                npcs.append({"id": int(nid), "name": html.unescape(nname), "family": fam,
                             "min": lo, "max": hi, "zone": html.unescape(zone)})
            if chunk.count("abilityranknpc ") != len(npcs):
                raise SystemExit("unparsed teacher entries in %s %s" % (name, rank))
            ab["ranks"][int(rank)] = {"level": int(m.group(2)), "tp": int(m.group(3)),
                                      "source": PET_SOURCE[heads[0].strip()], "npcs": npcs}
        abilities[name] = ab
    return abilities


# --------------------------------------------------------------------------------------------
# Wowhead
# --------------------------------------------------------------------------------------------

def read_wowhead(directory):
    """spell id -> {name, rank, level, new, icon} from the saved listview pages."""
    rows, icons = {}, {}
    for path in sorted(glob.glob(os.path.join(directory, "abilities-*.html"))):
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        for sid, icon in re.findall(r'"(\d+)":\{"name_enus":"[^"]*","icon":"([^"]*)"', text):
            icons[int(sid)] = icon
        for tr in re.findall(r'<tr class="listview-row">(.*?)</tr>', text, re.S):
            env = re.search(r'listview-env-change"><span>([^<]*)', tr)
            m = re.search(r'listview-cleartext[^"]*" href="[^"]*spell=(\d+)/[^"]*">([^<]*)</a>'
                          r'(?:<div class="small2">([^<]*)</div>)?', tr)
            if not m:
                continue
            tds = re.findall(r"<td[^>]*>(.*?)</td>", tr, re.S)
            lvl = re.sub("<[^>]+>", "", tds[3]).strip() if len(tds) > 3 else ""
            rank = re.search(r"(\d+)", m.group(3) or "")
            rows[int(m.group(1))] = {
                "name": html.unescape(m.group(2)), "rank": int(rank.group(1)) if rank else None,
                "level": int(lvl) if lvl.isdigit() else None, "new": bool(env and env.group(1) == "New"),
            }
    for sid, row in rows.items():
        row["icon"] = icons.get(sid)
    return rows


# --------------------------------------------------------------------------------------------
# Lua output
# --------------------------------------------------------------------------------------------

def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def lua_key(k):
    return k if re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", k) else "[" + lua_str(k) + "]"


def fmt_num(v):
    return ("%.1f" % v).rstrip("0").rstrip(".") if isinstance(v, float) else str(v)


def header(title, meta):
    return "\n".join([
        "-- UltimatePet: Data/%s" % title,
        "-- luacheck: ignore 631",
        "-- GENERATED by tools/gen_data.py - do not edit. Re-run the generator instead.",
        "-- Sources:",
        "--   Petopia Forever abilities page, snapshot %s (facts only: names, numbers, ids, icon names)" % meta["petopia_date"],
        "--   TrueshotLodge %s (MIT, (c) 2026 chazlander, github.com/chazlander/TrueshotLodge)" % meta["tl_sha"],
        "--   Wowhead Forever ability list snapshot (spell id cross-check)",
        "-- Decisions and gaps: tools/DATA_NOTES.md",
        "local _, UP = ...",
        "",
    ])


# --------------------------------------------------------------------------------------------
# Build
# --------------------------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--petopia", default=DEFAULT_PETOPIA)
    ap.add_argument("--tl", default=DEFAULT_TL)
    ap.add_argument("--wowhead", default=DEFAULT_WOWHEAD)
    ap.add_argument("--out", default=REPO)
    args = ap.parse_args()

    date = re.search(r"(\d{4}-\d{2}-\d{2})", os.path.basename(args.petopia))
    commit_file = os.path.join(args.tl, "COMMIT")
    if os.path.exists(commit_file):
        with open(commit_file) as fh:
            tl_sha = fh.read().strip()
    else:
        try:
            tl_sha = subprocess.run(["git", "-C", args.tl, "rev-parse", "HEAD"], check=True,
                                    capture_output=True, text=True).stdout.strip()
        except (OSError, subprocess.CalledProcessError):
            tl_sha = "unknown commit"
    meta = {"petopia_date": date.group(1) if date else "unknown date", "tl_sha": tl_sha}

    pet = read_petopia(args.petopia)
    wh = read_wowhead(args.wowhead)
    tl_ab = {a["name"]: a for a in read_lua(os.path.join(args.tl, "data", "Abilities.lua"))["TameableAbilities"].values()}
    tl_npc_file = read_lua(os.path.join(args.tl, "data", "NPCs.lua"))
    tl_npcs = tl_npc_file["TameableNPCs"]
    tl_hidden = set(tl_npc_file.get("TameableHidden", {}))
    wh_by_name = {(r["name"], r["rank"]): (sid, r) for sid, r in wh.items()}

    rep = {k: [] for k in ("conflicts", "tp_unknown", "teach_diff", "family_diff", "no_coords",
                           "spell", "source", "zone", "decisions")}

    names = sorted(set(pet) | set(tl_ab))
    skills = {}
    for name in names:
        p, t = pet.get(name), tl_ab.get(name)
        if name not in SKILL_CODES:
            raise SystemExit("no export code for %s" % name)
        if not p:
            rep["decisions"].append("%s: not on the Petopia page; ranks, TP, teachers and families from TrueshotLodge only." % name)
        if not t:
            rep["decisions"].append("%s: not in TrueshotLodge; ranks and families from Petopia only, no spell ids." % name)

        # Families: union of Petopia's matrix and TrueshotLodge learned_by (empty there = all families).
        pf = p["families"] if p else set()
        tf = set(t.get("learned_by") or []) if t else set()
        if t and not tf:
            tf = set(FAMILIES) - {"Core Hound"}  # TL lists no Core Hound family
        fams = pf | tf
        if p and t and pf != tf:
            extra_p, extra_t = sorted(pf - tf), sorted(tf - pf)
            if extra_p != ["Core Hound"] or extra_t:
                rep["family_diff"].append("%s: Petopia only %s, TrueshotLodge only %s" % (name, extra_p or "-", extra_t or "-"))

        pr = p["ranks"] if p else {}
        tr = {r["rank"]: r for r in (t["ranks"] if t else [])}
        ranks = {}
        for r in sorted(set(pr) | set(tr)):
            a, b = pr.get(r), tr.get(r)
            if not a or not b:
                if p and t:
                    rep["conflicts"].append("%s %d: only in %s" % (name, r, "Petopia" if a else "TrueshotLodge"))
            level = a["level"] if a else b["pet_level"]
            if a and b and a["level"] != b["pet_level"]:
                rep["conflicts"].append("%s %d: level Petopia %d, TrueshotLodge %d (kept Petopia)" % (name, r, a["level"], b["pet_level"]))
            spell = b["spell_id"] if b else None
            whrow = wh_by_name.get((name, r))
            if spell is None and whrow:
                spell = whrow[0]
                rep["spell"].append("%s %d: spell id %d from Wowhead only" % (name, r, spell))
            elif spell is None:
                rep["spell"].append("%s %d: no spell id in any source (stored nil)" % (name, r))
            elif whrow and whrow[0] != spell:
                rep["spell"].append("%s %d: spell id TrueshotLodge %d, Wowhead %d (kept TrueshotLodge)" % (name, r, spell, whrow[0]))
            elif not whrow:
                rep["spell"].append("%s %d: spell id %d not in the Wowhead snapshot" % (name, r, spell))
            if whrow and whrow[1]["level"] is not None and whrow[1]["level"] != level:
                rep["conflicts"].append("%s %d: level Wowhead %d vs %d" % (name, r, whrow[1]["level"], level))

            # TP cost.
            tp_p = a["tp"] if a else None
            tp_t = b.get("training_cost") if b else None
            vals = [v for v in (tp_p, tp_t) if v is not None]
            if a and b and tp_p != tp_t:
                rep["conflicts"].append("%s %d: TP Petopia %d, TrueshotLodge %d" % (name, r, tp_p, tp_t))
            wh_new = bool(whrow and whrow[1]["new"])
            if name == "Growl":
                tp = vals[0]  # Growl is free at every rank
            elif name in NEW_IN_FOREVER or wh_new:
                # Kept only when every source agrees on a real (> 1) number.
                if vals and len(set(vals)) == 1 and vals[0] > 1:
                    tp = vals[0]
                else:
                    tp = None
                    rep["tp_unknown"].append("%s %d: Petopia %s, TrueshotLodge %s" % (
                        name, r, "-" if tp_p is None else tp_p, "-" if tp_t is None else tp_t))
            elif len(set(vals)) == 1 and vals[0] > 0:
                tp = vals[0]
            else:
                tp = None
                rep["tp_unknown"].append("%s %d: Petopia %s, TrueshotLodge %s" % (
                    name, r, "-" if tp_p is None else tp_p, "-" if tp_t is None else tp_t))

            # Source type and teachers.
            p_ids = [n["id"] for n in a["npcs"]] if a else []
            t_ids = list(b.get("npc_ids") or []) if b else []
            if a:
                source = a["source"]
            elif b.get("trainer_cost"):
                source = "trainer"
            else:
                source = "tame" if t_ids else "none"
            teachers = list(dict.fromkeys(p_ids + t_ids))
            if a and b:
                only_p = sorted(set(p_ids) - set(t_ids))
                only_t = sorted(set(t_ids) - set(p_ids))
                if only_p or only_t:
                    rep["teach_diff"].append((name, r, only_p, only_t))
            if teachers and source != "tame":
                rep["source"].append("%s %d: Petopia says %s but TrueshotLodge lists teachers %s; stored as tame" % (name, r, source, t_ids))
                source = "tame"
            ranks[r] = {"spellId": spell, "level": level, "tp": tp, "source": source, "teachers": teachers}

        icon = p["icon"] if p else None
        first_spell = ranks[min(ranks)]["spellId"]
        if not icon and first_spell in wh and wh[first_spell]["icon"]:
            icon = wh[first_spell]["icon"]
            rep["decisions"].append("%s: icon name %s from Wowhead (not on Petopia)." % (name, icon))
        if p and first_spell in wh and wh[first_spell]["icon"] and wh[first_spell]["icon"] != icon:
            rep["conflicts"].append("%s: icon Petopia %s, Wowhead %s" % (name, icon, wh[first_spell]["icon"]))
        active = name not in PASSIVES
        if t and bool(t.get("passive")) == active:
            rep["conflicts"].append("%s: TrueshotLodge passive flag disagrees" % name)
        skills[name] = {"key": skill_key(name), "active": active, "unique": len(fams) == 1,
                        "icon": icon, "families": fams, "ranks": ranks}

    # ---------------------------------------------------------------- beasts
    pet_npcs = {}
    for ab in pet.values():
        for rk in ab["ranks"].values():
            for n in rk["npcs"]:
                pet_npcs.setdefault(n["id"], n)
    teach_ids = sorted({i for s in skills.values() for rk in s["ranks"].values() for i in rk["teachers"]})

    # English zone names for npcs Petopia does not list, learned from the npcs it does list:
    # TrueshotLodge area id (zones) -> Petopia zone text, and uiMapID -> Petopia zone text.
    area_votes, map_votes = {}, {}

    def vote(table, key, zone):
        table.setdefault(key, {}).setdefault(zone, 0)
        table[key][zone] += 1

    npcs = {}
    for nid in teach_ids:
        t = tl_npcs.get(nid, {})
        p = pet_npcs.get(nid)
        if not t and not p:
            raise SystemExit("teacher %d unknown to both sources" % nid)
        best = None
        for mid, packed in (t.get("maps") or {}).items():
            pts = unpack_points(packed)
            if pts and (best is None or len(pts) > len(best[1]) or (len(pts) == len(best[1]) and mid < best[0])):
                best = (mid, pts)
        tl_map = best[0] if best else t.get("map")
        entry = {
            "name": (t or p)["name"], "family": (t or p)["family"],
            "min": p["min"] if p else t.get("min"), "max": p["max"] if p else t.get("max", t.get("min")),
            "class": t.get("class"), "zone": p["zone"] if p else None, "instance": None,
            "map": None, "x": None, "y": None, "tl_map": tl_map, "areas": t.get("zones") or [],
        }
        if p and t:
            for fld in ("name", "family"):
                if p[fld] != t.get(fld):
                    rep["conflicts"].append("npc %d %s: Petopia %r, TrueshotLodge %r (kept TrueshotLodge)" % (nid, fld, p[fld], t.get(fld)))
            if t.get("min") is not None and (p["min"], p["max"]) != (t.get("min"), t.get("max", t.get("min"))):
                rep["conflicts"].append("npc %d %s levels: Petopia %d-%d, TrueshotLodge %s-%s (kept Petopia)" % (
                    nid, p["name"], p["min"], p["max"], t.get("min"), t.get("max", t.get("min"))))
        if nid in tl_hidden:
            rep["decisions"].append("npc %d %s is in TrueshotLodge's hidden list; kept because a source lists it as a teacher." % (nid, entry["name"]))
        if best:
            pt = representative_point(best[1])
            entry["map"], entry["x"], entry["y"] = best[0], round(pt[0], 1), round(pt[1], 1)
        zone = entry["zone"]
        if zone and ";" not in zone:
            if len(entry["areas"]) == 1:
                vote(area_votes, entry["areas"][0], zone)
            if tl_map is not None and not zone.endswith(")"):
                vote(map_votes, tl_map, zone)
        npcs[nid] = entry

    def winner(votes):
        return {k: max(v.items(), key=lambda kv: (kv[1], kv[0]))[0] for k, v in votes.items()}

    area_zone, map_zone = winner(area_votes), winner(map_votes)
    for nid, e in npcs.items():
        if e["zone"] is None:
            areas = [area_zone[a] for a in e["areas"] if a in area_zone]
            if len(areas) == 1:
                e["zone"] = areas[0]
                rep["zone"].append("npc %d %s: zone %r from its TrueshotLodge area id %s" % (nid, e["name"], e["zone"], e["areas"]))
            elif e["tl_map"] in map_zone:
                e["zone"] = map_zone[e["tl_map"]]
                rep["zone"].append("npc %d %s: zone %r from its TrueshotLodge map %d" % (nid, e["name"], e["zone"], e["tl_map"]))
            else:
                rep["zone"].append("npc %d %s: no zone name in any source (nil; TrueshotLodge area ids %s)" % (nid, e["name"], e["areas"] or "none"))
        m = re.match(r"^(.*) \((Dungeon|Raid)\)$", e["zone"] or "")
        if m:
            e["instance"] = m.group(1)
        if e["map"] is None:
            rep["no_coords"].append("npc %d %s (%s)" % (nid, e["name"], e["zone"] or "zone unknown"))

    for name, s in skills.items():
        for r, rk in s["ranks"].items():
            for nid in list(rk["teachers"]):
                if npcs[nid]["family"] not in s["families"]:
                    rk["teachers"].remove(nid)
                    rep["conflicts"].append("%s %d: dropped teacher %d %s, a %s cannot learn %s" % (
                        name, r, nid, npcs[nid]["name"], npcs[nid]["family"], name))

    def teach_sort(nid):
        e = npcs[nid]
        return (e["instance"] is not None, CLASS_TIER.get(e["class"], 2), e["min"] or 0, e["name"], nid)

    for s in skills.values():
        for rk in s["ranks"].values():
            rk["teachers"].sort(key=teach_sort)

    # ---------------------------------------------------------------- families
    families = {f: sorted(n for n, s in skills.items() if f in s["families"]) for f in FAMILIES}
    order = ([n for n in LEADING_ACTIVES if n in skills]
             + sorted(n for n in skills if n not in LEADING_ACTIVES and n not in PASSIVES)
             + [n for n in PASSIVES if n in skills])
    codes = {n: SKILL_CODES[n] for n in skills}
    if len(set(codes.values())) != len(codes):
        raise SystemExit("duplicate export codes")

    write_families(args.out, meta, families)
    write_skills(args.out, meta, skills, order, codes)
    write_beasts(args.out, meta, npcs, skills)
    notes = report(meta, pet, tl_ab, skills, npcs, families, rep)
    print(notes)
    with open(os.path.join(args.out, "tools", "DATA_NOTES.md"), "w", encoding="utf-8") as fh:
        fh.write(notes)


def write_families(out, meta, families):
    lines = [header("Families.lua", meta),
             "-- Pet family -> the abilities it can learn (sorted). petopiaId is the family id on Petopia.",
             "UP.Families = {"]
    for f in FAMILIES:
        abil = ", ".join(lua_str(a) for a in families[f])
        lines.append("  [%s] = { petopiaId = %s, abilities = { %s } }," % (lua_str(f), lua_str(family_id(f)), abil))
    lines.append("}")
    lines.append("")
    lines.append("UP.FamilyOrder = { %s }" % ", ".join(lua_str(f) for f in sorted(FAMILIES)))
    lines.append("")
    write(out, "Families.lua", lines)


def write_skills(out, meta, skills, order, codes):
    lines = [header("Skills.lua", meta),
             "-- ranks[r].tp is the TP cost of that rank (not cumulative); nil = unknown (see DATA_NOTES.md).",
             "-- ranks[r].source: \"tame\" (learned from a beast), \"trainer\" (pet trainer), \"none\" (no known source).",
             "UP.Skills = {"]
    for name in order:
        s = skills[name]
        fams = ", ".join("[%s] = true" % lua_str(f) for f in sorted(s["families"]))
        icon = lua_str("Interface\\Icons\\" + s["icon"]) if s["icon"] else "nil"
        lines.append("  [%s] = {" % lua_str(name))
        lines.append("    key = %s, active = %s, unique = %s, icon = %s," % (
            lua_str(s["key"]), str(s["active"]).lower(), str(s["unique"]).lower(), icon))
        lines.append("    families = { %s }," % fams)
        lines.append("    ranks = {")
        for r in sorted(s["ranks"]):
            rk = s["ranks"][r]
            lines.append("      [%d] = { spellId = %s, level = %d, tp = %s, source = %s }," % (
                r, "nil" if rk["spellId"] is None else rk["spellId"], rk["level"],
                "nil" if rk["tp"] is None else rk["tp"], lua_str(rk["source"])))
        lines.append("    },")
        lines.append("  },")
    lines.append("}")
    lines.append("")
    lines.append("-- Display order: actives, then passives.")
    lines.append("UP.SkillOrder = {")
    for i in range(0, len(order), 6):
        lines.append("  " + " ".join(lua_str(n) + "," for n in order[i:i + 6]))
    lines.append("}")
    lines.append("")
    lines.append("-- Two-letter codes used in export strings (UP1:<Family>:<Lvl>-<Loy>:<Code><rank>,...).")
    lines.append("UP.SkillCodes = {")
    for name in order:
        lines.append("  [%s] = %s," % (lua_str(name), lua_str(codes[name])))
    lines.append("}")
    lines.append("")
    write(out, "Skills.lua", lines)


def write_beasts(out, meta, npcs, skills):
    lines = [header("Beasts.lua", meta),
             "-- npcs[id]: name, family, min/max level, class (nil = normal), zone (English), instance (dungeon or",
             "-- raid name, nil in the open world), map (uiMapID) and x, y (0-100) of one representative spawn.",
             "-- map/x/y are nil when no source has coordinates (mostly dungeon mobs).",
             "UP.Beasts = UP.Beasts or {}",
             "UP.Beasts.npcs = {"]
    for nid in sorted(npcs):
        e = npcs[nid]
        parts = ["name = %s" % lua_str(e["name"]), "family = %s" % lua_str(e["family"])]
        if e["min"] is not None:
            parts.append("min = %d" % e["min"])
        if e["max"] is not None:
            parts.append("max = %d" % e["max"])
        if e["class"]:
            parts.append("class = %s" % lua_str(e["class"]))
        if e["zone"]:
            parts.append("zone = %s" % lua_str(e["zone"]))
        if e["instance"]:
            parts.append("instance = %s" % lua_str(e["instance"]))
        if e["map"] is not None:
            parts.append("map = %d, x = %s, y = %s" % (e["map"], fmt_num(e["x"]), fmt_num(e["y"])))
        lines.append("  [%d] = { %s }," % (nid, ", ".join(parts)))
    lines.append("}")
    lines.append("")
    lines.append("-- teach[skill][rank] = npc ids, sorted: open world before instance, normal before rare/elite,")
    lines.append("-- then by minimum level. Ranks nobody teaches are absent.")
    lines.append("UP.Beasts.teach = {")
    for name in sorted(skills):
        ranks = skills[name]["ranks"]
        taught = [r for r in sorted(ranks) if ranks[r]["teachers"]]
        if not taught:
            continue
        lines.append("  [%s] = {" % lua_str(name))
        for r in taught:
            lines.append("    [%d] = { %s }," % (r, ", ".join(str(i) for i in ranks[r]["teachers"])))
        lines.append("  },")
    lines.append("}")
    lines.append("")
    write(out, "Beasts.lua", lines)


def write(out, name, lines):
    with open(os.path.join(out, "Data", name), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines))


def report(meta, pet, tl_ab, skills, npcs, families, rep):
    nranks = sum(len(s["ranks"]) for s in skills.values())
    links = sum(len(rk["teachers"]) for s in skills.values() for rk in s["ranks"].values())
    pet_links = sum(len(rk["npcs"]) for a in pet.values() for rk in a["ranks"].values())
    src = {}
    for s in skills.values():
        for rk in s["ranks"].values():
            src[rk["source"]] = src.get(rk["source"], 0) + 1
    with_coords = sum(1 for e in npcs.values() if e["map"] is not None)
    tl_only_links = sum(len(d[3]) for d in rep["teach_diff"])
    pet_only_links = sum(len(d[2]) for d in rep["teach_diff"])

    out = ["# UltimatePet data notes", "",
           "Generated by `tools/gen_data.py`. Do not edit by hand; re-run the generator.",
           "", "## Sources", "",
           "- Petopia Forever abilities page, snapshot %s: families per ability, ranks, pet level, TP cost, source type, teaching beasts (id, name, family, levels, zone), icon names. Facts only." % meta["petopia_date"],
           "- TrueshotLodge (MIT, (c) 2026 chazlander), commit `%s`: spell ids, TP, teaching npc ids per rank, learned_by, beast class and map points." % meta["tl_sha"],
           "- Wowhead Forever ability list snapshot: spell id and level cross-check, icon names for abilities Petopia lacks.",
           "", "## Counts", "",
           "| | |", "|---|---|",
           "| Families | %d |" % len(families),
           "| Skills | %d (%d active, %d passive) |" % (len(skills), sum(s["active"] for s in skills.values()), sum(not s["active"] for s in skills.values())),
           "| Ranks | %d (tame %d, trainer %d, none %d) |" % (nranks, src.get("tame", 0), src.get("trainer", 0), src.get("none", 0)),
           "| Ranks with unknown TP | %d |" % len(rep["tp_unknown"]),
           "| Petopia abilities / ranks / teacher links | %d / %d / %d |" % (len(pet), sum(len(a["ranks"]) for a in pet.values()), pet_links),
           "| TrueshotLodge abilities | %d |" % len(tl_ab),
           "| Teach links (union) | %d (Petopia only %d, TrueshotLodge only %d) |" % (links, pet_only_links, tl_only_links),
           "| Teaching npcs | %d (with coordinates %d, without %d) |" % (len(npcs), with_coords, len(npcs) - with_coords),
           "", "## Rules applied", "",
           "- Families per ability: union of Petopia's \"Can be learned by\" list and TrueshotLodge `learned_by` (empty there means every family; TrueshotLodge has no Core Hound).",
           "- Pet level: Petopia (all sources agree, see conflicts below).",
           "- Spell ids: TrueshotLodge, checked against Wowhead. No source has Lava Breath spell ids, so they are nil; the UI falls back to the stored icon.",
           "- TP cost: kept when the sources agree and it is above 0. Growl is free at every rank (0 kept). For abilities new in Forever (%s, plus any rank Wowhead flags New) a cost of 0 or 1 is a placeholder and is stored as nil (unknown, shown as `?`). Trickster's Dance: TrueshotLodge 10 vs Petopia 0, stored nil." % ", ".join(NEW_IN_FOREVER),
           "- Source type: Petopia's heading per rank (tame / trainer / none). Petopia lists every Growl rank, rank 1 included, as trainer; kept as is. TrueshotLodge-only ranks: trainer when it has a trainer cost, tame when it lists npcs, otherwise none. A rank with teachers in either source is tame.",
           "- Teachers: union of Petopia and TrueshotLodge npc ids per rank, minus any npc whose family cannot learn the ability (listed under conflicts). Sorted open world before dungeon/raid, then normal before rare/elite, then by minimum level.",
           "- Beast name and family: TrueshotLodge (collected in game) when it has the npc, otherwise Petopia. Levels and zone text: Petopia when it lists the npc, otherwise TrueshotLodge. Class (Rare/Elite) from TrueshotLodge.",
           "- Coordinates: TrueshotLodge map points. The map with the most points, then the spawn nearest the centre of the densest cluster (5% radius). Npcs without points keep map/x/y nil; nothing is invented. Dungeon/raid mobs carry `instance` so the waypoint code can say \"inside <instance>\".",
           "- Zone text for npcs Petopia does not list: the English zone that Petopia's npcs on the same uiMapID use; nil if none.",
           "- Export codes: two letters, from the approved UI mock where it defined them; Lightning Breath is `Li` (Lava Breath has `LB`), Savage Rend `Sv` (Shadow Resistance has `SR`).",
           ""]

    def section(title, items):
        out.append("## %s (%d)" % (title, len(items)))
        out.append("")
        out.extend("- " + i for i in items) if items else out.append("None.")
        out.append("")

    section("Ranks with unknown TP (stored nil)", rep["tp_unknown"])
    section("Conflicts between sources", rep["conflicts"])
    section("Family list differences", rep["family_diff"])
    section("Source type changes", rep["source"])
    section("Spell id notes", rep["spell"])
    section("Other decisions", rep["decisions"])
    td = []
    for name, r, only_p, only_t in rep["teach_diff"]:
        parts = []
        if only_p:
            parts.append("Petopia only " + ", ".join("%d %s" % (i, npcs[i]["name"]) for i in only_p))
        if only_t:
            parts.append("TrueshotLodge only " + ", ".join("%d %s" % (i, npcs[i]["name"]) for i in only_t))
        td.append("%s %d: %s" % (name, r, "; ".join(parts)))
    section("Teacher list differences per rank (union stored)", td)
    section("Teaching npcs without coordinates", rep["no_coords"])
    section("Zone names", rep["zone"])
    return "\n".join(out)


if __name__ == "__main__":
    sys.exit(main())
