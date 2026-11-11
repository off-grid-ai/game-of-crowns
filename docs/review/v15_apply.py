#!/usr/bin/env python3 -I
"""Review v15: put batch 7's frames on the review page, each beside its reference.

  python3 -I docs/review/v15_apply.py <batch OUT folder> [--check]

For each shot in v15.json whose still exists under OUT: the still becomes screens/v15/<id>.jpg
(at most 2000 px wide) and its clip screens/v15/<id>.mp4; the screen is added to screens.json
(or given a new version if it's there) with the target image as the version before ours, so the
page's Side by side shows target and ours together. Run again after a re-render: a shot whose
file changed gets a new version, the old one kept under screens/v15/<id>-<n>.jpg.
Writes v15-publish.json: the files map to publish with index.html. --check only lists
which shots are there and which are missing; nothing is written.
"""
import datetime, hashlib, json, os, shutil, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
out = os.path.abspath(sys.argv[1])
check = "--check" in sys.argv
spec = json.load(open(os.path.join(HERE, "v15.json")))
notes = open(os.path.join(out, "notes.txt")).read().strip() if os.path.exists(os.path.join(out, "notes.txt")) else ""

have, missing = [], []
for s in spec["shots"]:
    (have if os.path.exists(os.path.join(out, s["still"])) else missing).append(s)
if check:
    for s in have:
        clip = s.get("clip")
        print("  ok       %-22s %s%s" % (s["id"], s["still"], "" if not clip else ("  + clip" if os.path.exists(os.path.join(out, clip)) else "  (clip missing: %s)" % clip)))
    for s in missing:
        print("  MISSING  %-22s %s" % (s["id"], s["still"]))
    print("  %d of %d shots" % (len(have), len(spec["shots"])))
    sys.exit(0)

manifest_path = os.path.join(HERE, "screens.json")
screens = json.load(open(manifest_path))
by = {s["id"]: s for s in screens}
os.makedirs(os.path.join(HERE, "screens", "v15"), exist_ok=True)
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
publish = {"screens.json": "screens.json"}
digest = lambda p: hashlib.sha1(open(p, "rb").read()).hexdigest()
added = 0
new = 0
for s in have:
    ref = "screens/ref/%s.jpg" % s["ref"]
    publish[ref] = ref
    scr = by.get(s["id"])
    if scr is None:
        scr = {"id": s["id"], "name": s["name"], "group": spec["group"], "what": s["what"],
               "versions": [{"v": 1, "label": "Target: %s" % s["ref"], "at": "2026-11-11T00:00:00Z", "file": ref,
                             "what": "The target (docs/art/target/%s). Copy sheet card %s." % (s["ref"], s["card"])}]}
        screens.insert(new, scr)  # in the shot list's order, ahead of the older screens
        new += 1
        by[s["id"]] = scr
    n = scr["versions"][-1]["v"] + 1
    # The still, shrunk to the page's width; unchanged since the last run: nothing to add.
    tmp = os.path.join(HERE, "screens", "v15", ".tmp.jpg")
    subprocess.run(["sips", "-s", "format", "jpeg", "-Z", "2000", os.path.join(out, s["still"]), "--out", tmp], check=True, capture_output=True)
    last = scr["versions"][-1]
    last_path = os.path.join(HERE, last["file"])
    if last.get("label") == spec["label"] and os.path.exists(last_path) and digest(last_path) == digest(tmp):
        os.remove(tmp)
        for k in ("file", "clip"):
            if last.get(k):
                publish[last[k]] = last[k]
        continue
    name = "%s-%d" % (s["id"], n)
    file = "screens/v15/%s.jpg" % name
    os.replace(tmp, os.path.join(HERE, file))
    v = {"v": n, "label": spec["label"], "at": now, "file": file}
    what = s["what"]
    if s.get("needs") and ("'%s' step" % s["needs"]) in notes:
        what += " (Framed without the '%s' step: check what's in frame.)" % s["needs"]
    v["what"] = what
    publish[file] = file
    scr["file"] = file
    scr.pop("clip", None)
    clip = s.get("clip")
    if clip and os.path.exists(os.path.join(out, clip)):
        cfile = "screens/v15/%s.mp4" % name
        shutil.copyfile(os.path.join(out, clip), os.path.join(HERE, cfile))
        v["clip"] = cfile
        scr["clip"] = cfile
        publish[cfile] = cfile
    scr["versions"].append(v)
    added += 1
json.dump(screens, open(manifest_path, "w"), indent=2, ensure_ascii=False)
json.dump(publish, open(os.path.join(HERE, "v15-publish.json"), "w"), indent=1)
print("v15: %d screens added or updated, %d shots missing (%s); %d files to publish (v15-publish.json)" % (
    added, len(missing), ", ".join(s["id"] for s in missing) or "none", len(publish)))
