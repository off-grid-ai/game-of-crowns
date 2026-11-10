#!/usr/bin/env python3 -I
"""A 15-minute reign on a private bridge, played by a hasty King: polls /world
like a watching window, answers every court item 4 s after it appears (a
middling option), and counts the fun bar's measurable lines."""
import json, sys, time, urllib.request, random, collections

B = sys.argv[1]
INTERLUDE = "/interlude/close"
MIN = float(sys.argv[2]) if len(sys.argv) > 2 else 15.0
OUT = sys.argv[3]
random.seed(7)

def get(path):
    with urllib.request.urlopen(f"http://{B}{path}", timeout=20) as r:
        return json.loads(r.read())

def post(path, body):
    req = urllib.request.Request(f"http://{B}{path}", data=json.dumps(body).encode(), method="POST")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.loads(r.read())
    except Exception as e:
        return {"error": str(e)}

start = time.time()
seen = {}          # item id -> first seen time
decisions = []     # (t, kind, name, place, weighed)
up_time = 0.0      # seconds with a card up
last = start
kinds = collections.Counter()
names = set()
returns = 0
intrigue_max = 0
intrigue_ids = set()
places = 0
weighed = 0
log = open(OUT + ".log", "w")
# Dead time (the judge): stretches with no decision, no visible event at a place
# (a scene, a scheme, a threat's change) and no news in the chronicle.
events = [0.0]
scene_ids, scheme_sig, threat_sig, news_seq = set(), None, None, 0
while time.time() - start < MIN * 60:
    now = time.time()
    try:
        w = get("/world")
        court = get("/court")
    except Exception as e:
        log.write(f"{now-start:.0f} fetch error {e}\n"); time.sleep(2); continue
    if (w.get("reign") or {}).get("status") not in (None, "running"):
        log.write(f"{now-start:.0f} reign over: {(w.get('reign') or {}).get('status')}\n"); break
    # An act's interlude holds the realm until it's read: the King reads it (4 s) and goes on.
    inter = (w.get("reign") or {}).get("interlude") or {}
    if inter and not inter.get("seen"):
        seen.setdefault("interlude:%s" % inter.get("q"), now)
        if now - seen["interlude:%s" % inter.get("q")] >= 4:
            post(INTERLUDE, {})
            log.write(f"{now-start:.0f} read the interlude {inter.get('title')}\n")
    if court or (inter and not inter.get("seen")):
        up_time += now - last
    last = now
    t_now = now - start
    new = [x.get("id") for x in (w.get("scenes") or []) if x.get("id") not in scene_ids]
    if new:
        scene_ids.update(new); events.append(t_now)
    sig = json.dumps(sorted((x["id"], x.get("line")) for x in (w.get("intrigue") or [])))
    if sig != scheme_sig:
        scheme_sig = sig; events.append(t_now)
    tsig = json.dumps((w.get("crown") or {}).get("threat"), sort_keys=True)
    if tsig != threat_sig:
        threat_sig = tsig; events.append(t_now)
    try:
        ch = get(f"/chronicle?since={news_seq}")
        evs = ch.get("events", ch) if isinstance(ch, dict) else ch
        if evs:
            news_seq = max(int(e.get("seq", news_seq)) for e in evs); events.append(t_now)
    except Exception:
        pass
    for s in w.get("intrigue") or []:
        intrigue_ids.add(s["id"])
    intrigue_max = max(intrigue_max, len(w.get("intrigue") or []))
    for x in court:
        seen.setdefault(x["id"], now)
        if now - seen[x["id"]] < 4:
            continue
        if x.get("hand"):
            # A King acts on the Hand's matter: its first order he can pay for, then the matter is answered.
            acts = [a for a in (x.get("acts") or []) if a.get("action") and not (a.get("weighs") or {}).get("short")]
            if acts:
                a0 = acts[0]
                r = post("/decree", {k: a0[k] for k in ("action", "city", "building", "to", "house") if a0.get(k) is not None})
            r = post("/counsel/answer", {"key": x["key"]}) if x.get("acts") else post("/court/close", {})
            kind = "hand"
        else:
            opts = x.get("options") or []
            if not opts:
                continue
            # A middling answer; one the crown can't give (refused) gives way to the next, none counted twice.
            r = {"error": "none"}
            for o in [opts[len(opts) // 2]] + [o for o in opts if o is not opts[len(opts) // 2]]:
                r = post("/court/answer", {"id": x["id"], "option": o["id"]})
                if not r.get("error"):
                    break
            if r.get("error"):
                seen[x["id"]] = now + 10 ** 9  # unanswerable by this King: leave it, count it once
                log.write(f"{now-start:.0f} could not answer {x.get('kind')}: {r}\n")
                continue
            kind = x.get("kind")
            if any(op.get("weighs") for op in opts):
                weighed += 1
        if x.get("place"):
            places += 1
        if kind == "remembers":
            returns += 1
        kinds[kind] += 1
        names.add(x.get("name"))
        events.append(now - start)
        decisions.append((round(now - start), kind, x.get("name"), (x.get("place") or {}).get("name")))
        log.write(f"{now-start:.0f} answered {kind} {x.get('name')} @ {(x.get('place') or {}).get('name')} -> {str(r)[:120]}\n")
        log.flush()
    time.sleep(1.5)

mins = (time.time() - start) / 60
events = sorted(events + [mins * 60])
gaps = [b - a for a, b in zip(events, events[1:])]
dead = [g for g in gaps if g > 60]
rep = sum(n - 1 for k, n in kinds.items() if k not in ("hand", "remembers") and n > 1)
res = {
    "minutes": round(mins, 1),
    "decisions": len(decisions),
    "decisions_per_minute": round(len(decisions) / mins, 2),
    "quiet_share": round(1 - up_time / (mins * 60), 2),
    "repeated_kinds": rep,
    "kinds": dict(kinds),
    "distinct_petitioners": len(names),
    "lords_returning": returns,
    "with_place": places,
    "plea_answers_weighed": weighed,
    "schemes_seen": len(intrigue_ids),
    "longest_dead_s": round(max(gaps) if gaps else 0),
    "dead_share": round(sum(dead) / (mins * 60), 2),
    "schemes_at_once_max": intrigue_max,
    "reign_clock_minutes": round(((w.get("reign") or {}).get("elapsedMs") or 0) / 60000, 1),
}
json.dump(res, open(OUT, "w"), indent=1)
log.write(json.dumps(res) + "\n")
