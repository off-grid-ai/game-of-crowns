#!/usr/bin/env python3 -I
"""Every asset file the game loads, generated from what names it (Mac, 2026-11-12: "standardise all of this").

Run from anywhere:  python3 -I realm/tools/asset_manifest.py [--write] [--unloaded]
  (no flag)    prints the counts and sizes;
  --write      writes docs/art/assets-loaded.txt (the manifest: one res:// path a line, with its size);
  --unloaded   prints every file under realm/assets that nothing loads (the candidates to take out), by folder.

What counts as loaded, read from the game's own sources (realm/scripts, realm/main.tscn and every .tscn/.tres, realm/data,
realm/project.godot; realm/tools are test aids, not the game):
  1. a literal "res://assets/..." path;
  2. a path built from a pattern ("res://assets/props/%s.gltf", "res://assets/fx/fire/smoke_0%d.png"): every file the
     pattern matches (a family is kept whole: which member a row names is the data's business);
  3. a string in a script or a data file naming a file or a folder under assets/ ("village/House_1",
     "armies/meshy_knight", "meshy/forge"), as the catalogues resolve them (realistic.gd: "<m>", "<m>.gltf",
     "<m>.glb", "<m>/scene.gltf"); a folder named is kept whole (a baked army's soldier.glb, offsets.exr, normals.png...);
  4. what a kept file needs: a .gltf's buffers and images (its "uri"s), a .tscn/.tres's ext_resources, an .fbx's
     .fbm folder, what Godot's import made it need (ResourceLoader.get_dependencies, through realm/tools/asset_deps.gd:
     a .glb's extracted textures), and every kept file's .import beside it.
A name in rule 3, and a pattern written without the prefix ("music/%s.ogg"), is looked for under assets/ and under every
folder a script builds paths from ("res://assets/audio/" + "ambience/market.ogg"). A folder a script lists
(DirAccess.open on a "res://assets/..." constant: the people's and the hero's animations) is loaded whole.
Where a pattern is only a folder ("res://assets/%s/"), the strings of rule 3 name which folders.
"""
import json, os, re, sys, fnmatch

REALM = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
ASSETS = os.path.join(REALM, "assets")
ROOT = os.path.dirname(REALM)
SOURCES = [os.path.join(REALM, d) for d in ("scripts", "data")] + [os.path.join(REALM, "main.tscn"), os.path.join(REALM, "project.godot")]
TEXT = (".gd", ".gdshader", ".tscn", ".tres", ".json", ".godot", ".cfg")


def walk(top):
    if os.path.isfile(top):
        yield top
        return
    for d, dirs, files in os.walk(top):
        dirs[:] = [x for x in dirs if x not in (".godot", ".git")]
        for f in files:
            yield os.path.join(d, f)


def all_assets():
    return sorted(p for p in walk(ASSETS) if not os.path.basename(p).startswith("."))


def rel(p):
    return os.path.relpath(p, ASSETS).replace(os.sep, "/")


def source_texts():
    files = [p for top in SOURCES for p in walk(top) if p.endswith(TEXT)]
    files += [p for p in walk(ASSETS) if p.endswith((".tscn", ".tres"))]
    for p in files:
        try:
            yield p, open(p, encoding="utf-8", errors="replace").read()
        except OSError:
            pass


def strings_of_json(v, out):
    if isinstance(v, str):
        out.append(v)
    elif isinstance(v, list):
        for x in v:
            strings_of_json(x, out)
    elif isinstance(v, dict):
        for k, x in v.items():
            out.append(k)
            strings_of_json(x, out)


def manifest():
    files = all_assets()
    names = {rel(p): p for p in files}
    dirs = set()
    for r in names:
        parts = r.split("/")
        for i in range(1, len(parts)):
            dirs.add("/".join(parts[:i]))
    kept = set()
    patterns = []
    strings = []
    roots = [""]
    listed = []
    for path, text in source_texts():
        for m in re.finditer(r'res://assets/([^"\'\s)\]]*)', text):
            s = m.group(1)
            if s.endswith("/") and "%" not in s:
                roots.append(s)
            if "%" in s:
                patterns.append(re.sub(r"%[0-9]*[sd]", "*", s))
            elif s:
                strings.append(s)
        for m in re.finditer(r'"([A-Za-z0-9_\-./ |]+/[A-Za-z0-9_\-./ |]+)"', text):  # "village/House_1", "armies/meshy_knight"
            strings += m.group(1).split("|")  # a sound's takes: "sfx/coins_1.ogg|sfx/coins_2.ogg"
        for m in re.finditer(r'"([A-Za-z0-9_\-/ ]*%[0-9]*[sd][A-Za-z0-9_\-/ %]*\.(?:[a-z0-9]{2,5}|%s))"', text):  # ROOT + "music/%s.ogg"
            if not m.group(1).startswith("res://"):
                patterns.append(("~", re.sub(r"%[0-9]*[sd]", "*", m.group(1))))
        if path.endswith(".gd"):
            consts = dict(re.findall(r'const ([A-Z_]+)\s*:?=\s*"res://assets/([^"]+)"', text))
            for name in re.findall(r'DirAccess\.open\(([A-Z_]+)\)', text):
                if name in consts:
                    listed.append(consts[name].rstrip("/") + "/")
        if path.endswith(".json"):
            try:
                out = []
                strings_of_json(json.loads(text), out)
                strings += [x for s in out for x in s.split("|") if "/" in x or "." in x]
            except ValueError:
                pass
        for m in re.finditer(r'path="res://assets/([^"]+)"', text):  # a scene's ext_resources
            strings.append(m.group(1))
    # 1 and 3: named files and folders, as the catalogues resolve a name.
    for s in strings:
        s = s.strip().lstrip("/")
        if s.startswith("res://assets/"):
            s = s[len("res://assets/"):]
        for root in roots:
            for c in (root + s, root + s + ".gltf", root + s + ".glb", root + s + "/scene.gltf"):
                if c in names:
                    kept.add(c)
        if s.rstrip("/") in dirs and "/" in s.rstrip("/"):
            d = s.rstrip("/") + "/"
            kept.update(r for r in names if r.startswith(d))
    # 2: patterns (a folder-only pattern names nothing by itself).
    for pat in set(patterns):
        under = [""]
        if isinstance(pat, tuple):
            under, pat = set(roots), pat[1]
        if pat.endswith("/") or len(re.sub(r"[*./_\-]", "", pat.rsplit("/", 1)[-1])) < 3:
            continue  # a pattern with no name of its own ("%s.%s", "%s/") names nothing by itself
        for root in under:
            kept.update(r for r in names if fnmatch.fnmatchcase(r, root + pat))
    for d in listed:
        kept.update(r for r in names if r.startswith(d))
    # 4: what a kept file needs, until nothing new; first what Godot's import made each scene need.
    kept |= godot_deps(names, [r for r in kept if r.endswith((".glb", ".gltf", ".fbx", ".tscn", ".tres", ".res", ".blend"))])
    todo = list(kept)
    while todo:
        r = todo.pop()
        p = names[r]
        need = []
        base = os.path.dirname(r)
        if r.endswith(".gltf"):
            try:
                g = json.load(open(p, encoding="utf-8", errors="replace"))
                for k in ("buffers", "images"):
                    for x in g.get(k, []):
                        u = x.get("uri", "")
                        if u and not u.startswith("data:"):
                            need.append(os.path.normpath(os.path.join(base, u.replace("%20", " "))).replace(os.sep, "/"))
            except ValueError:
                pass
        elif r.endswith((".tscn", ".tres")):
            for m in re.finditer(r'path="res://assets/([^"]+)"', open(p, encoding="utf-8", errors="replace").read()):
                need.append(m.group(1))
        elif r.endswith(".fbx"):
            fbm = r[:-4] + ".fbm/"
            need += [x for x in names if x.startswith(fbm)]
        need.append(r + ".import")
        for n in need:
            if n in names and n not in kept:
                kept.add(n)
                todo.append(n)
    return names, kept


def godot_deps(names, scenes):
    import subprocess, tempfile
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as f:
        f.write("\n".join("res://assets/" + r for r in scenes))
        lst = f.name
    out = subprocess.run(["arch", "-arm64", "godot", "--headless", "--path", REALM, "-s", "res://tools/asset_deps.gd", "--", lst],
                         capture_output=True, text=True, timeout=600).stdout
    os.unlink(lst)
    got = set()
    for l in out.splitlines():
        if l.startswith("DEP res://assets/"):
            r = l[len("DEP res://assets/"):].strip()
            if r in names:
                got.add(r)
    return got


def size(names, rs):
    return sum(os.path.getsize(names[r]) for r in rs)


def mb(n):
    return "%.1f MB" % (n / 1e6)


if __name__ == "__main__":
    names, kept = manifest()
    unloaded = sorted(set(names) - kept)
    print("ASSETS %d files, %s; loaded %d files, %s; unloaded %d files, %s" % (
        len(names), mb(size(names, names)), len(kept), mb(size(names, kept)), len(unloaded), mb(size(names, unloaded))))
    if "--write" in sys.argv:
        out = os.path.join(ROOT, "docs", "art", "assets-loaded.txt")
        with open(out, "w") as f:
            f.write("# Every asset file the game loads, generated by realm/tools/asset_manifest.py (don't hand-edit;\n")
            f.write("# run it with --write). One res:// path a line and its size in bytes. %d files, %s.\n" % (len(kept), mb(size(names, kept))))
            for r in sorted(kept):
                f.write("res://assets/%s\t%d\n" % (r, os.path.getsize(names[r])))
        print("WROTE", os.path.relpath(out, ROOT))
    if "--unloaded" in sys.argv:
        by = {}
        for r in unloaded:
            top = "/".join(r.split("/")[:2]) if "/" in r else r
            by.setdefault(top, []).append(r)
        for top in sorted(by, key=lambda t: -size(names, by[t])):
            print("%10s  %5d files  %s" % (mb(size(names, by[top])), len(by[top]), top))
