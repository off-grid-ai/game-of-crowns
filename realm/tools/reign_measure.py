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
    except urllib.error.HTTPError as e:
        try:
            return json.loads(e.read())  # the realm's own reason ("once a year: again in 2 seasons")
        except Exception:
            return {"error": str(e)}
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
# The next thing (bridge next.js): time by kind, time covered by a goal a minute away
# or one he can take now, and how often it turns over.
nx_time, nx_covered, nx_turns, nx_text, nx_last = collections.Counter(), 0.0, 0, None, start
# The royal seal (bridge seals.js), when the reign has it: this King spends one whenever he
# holds one and no court is up, on one of the worthwhile uses at random (the line's pick or another).
seal_acts, seal_hand, seal_fail, seal_last, multi_time = collections.Counter(), 0, 0, 0.0, 0.0
# SEAL_POLICY=hand: a King who always takes the Hand's pick (the line's act), to see whether the advice dominates.
import os
SEAL_POLICY = os.environ.get("SEAL_POLICY", "random")
crown_towns = lambda w: [c["id"] for c in w.get("cities", []) if any(p.get("id") == c.get("owner") and (p.get("house") or {}).get("crown") for p in w.get("players", []))]
towns_at_start = None
seal_refused_now = []  # refused since the last seal spent: tried again only once all have been
ev_seen, ev_done, events_answered = {}, set(), 0
seal_seasons, choice_seasons, reach_at_seal = set(), set(), {}  # seasons with a seal in hand; those with 2+ uses on offer  # event cards (bridge events.js) seen and answered
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
    if towns_at_start is None:
        towns_at_start = crown_towns(w)
    nx = (w.get("reign") or {}).get("next")
    if isinstance(nx, dict):
        nx_time[nx.get("kind")] += now - nx_last
        if nx.get("kind") != "court" or (nx.get("seconds") or 999) <= 60:
            nx_covered += now - nx_last
        if nx.get("text") != nx_text:
            nx_turns += 1 if nx_text is not None else 0
            nx_text = nx.get("text")
        if (nx.get("options") or 0) >= 2:
            multi_time += now - nx_last
        # PLAN.md's seals row, per season: of the seasons he holds a seal, those offering 2+ uses at some point.
        if ((w.get("reign") or {}).get("seals") or {}).get("n", 0) >= 1:
            seal_seasons.add(w.get("turn"))
            if (nx.get("options") or 0) >= 2:
                choice_seasons.add(w.get("turn"))
            rc = nx.get("reach") or {}
            if rc.get("of"):
                reach_at_seal[w.get("turn")] = f"{rc.get('can')}/{rc.get('of')}"  # the season's last look with a seal in hand
    # An event card (bridge events.js): read for 3 s, then answered at random, as one more decision.
    ev = ((w.get("reign") or {}).get("event") or {}).get("up")
    if isinstance(ev, dict) and not court:
        k = f"{ev.get('id')}@{ev.get('turn')}"
        ev_seen.setdefault(k, now)
        if now - ev_seen[k] >= 3 and k not in ev_done:
            ev_done.add(k)
            r = post("/event/answer", {"choice": random.randrange(len(ev.get("choices") or [1]))})
            if r.get("ok"):
                events_answered += 1
                decisions.append((round(now - start), "event:" + str(ev.get("id")), None, None))
                events.append(now - start)
    sl = (w.get("reign") or {}).get("seals")
    if isinstance(sl, dict) and sl.get("n", 0) >= 1 and not court and not (inter and not inter.get("seen")) and now - seal_last >= 6 \
            and isinstance(nx, dict) and nx.get("alts"):
        tried = [a for a in nx["alts"] if a not in seal_refused_now]
        # hand / marshal: always the first / second voice's pick (next.js voices), to see whether one way dominates.
        vo = {v.get("who", ""): v.get("act") for v in (nx.get("voices") or [])}
        want = nx.get("act") if SEAL_POLICY == "hand" else (list(vo.values())[1] if SEAL_POLICY == "marshal" and len(vo) > 1 else None)
        pick = want if want and want not in seal_refused_now else random.choice(tried or nx["alts"])
        body = {k: pick[k] for k in ("action", "city", "building", "to") if pick.get(k) is not None}
        r = post("/decree", body)
        seal_last = now
        if r.get("ok"):
            seal_refused_now.clear()
            seal_acts[pick["action"]] += 1
            seal_hand += 1 if pick == nx.get("act") else 0
            decisions.append((round(now - start), "seal:" + pick["action"], None, None))
            events.append(now - start)
            log.write(f"{now-start:.0f} sealed {body} -> {str(r.get('text'))[:100]}\n")
        else:
            seal_fail += 1
            seal_refused_now.append(pick)
            log.write(f"{now-start:.0f} seal refused {body}: {r.get('error')}\n")
    nx_last = now
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
    "next_covered_share": round(nx_covered / (mins * 60), 2),
    "next_turnover_per_minute": round(nx_turns / mins, 2),
    "next_his_share": round(sum(v for k, v in nx_time.items() if k != "court") / max(1e-9, sum(nx_time.values())), 2) if nx_time else 0,
    "next_kinds_share": {k: round(v / max(1e-9, sum(nx_time.values())), 2) for k, v in nx_time.items()},
    "seal_policy": SEAL_POLICY,
    "name_earned": ((w.get("reign") or {}).get("readings") or {}).get("name"),
    # Strength (the Marshal's ground): the King's own fighting men at the end, and his towns held.
    "crown_soldiers_end": sum(1 for u in w.get("units", []) if u.get("type") not in ("Settlers", "Workers", "Trireme", "Caravan", "Explorer") and any(p.get("id") == u.get("owner") and (p.get("house") or {}).get("crown") for p in w.get("players", []))),
    "crown_towns_end": len(crown_towns(w)),
    "crown_towns_lost": len(set(towns_at_start or []) - set(crown_towns(w))),
    "crown_towns_gained": len(set(crown_towns(w)) - set(towns_at_start or [])),
    "peace_end": round(((w.get("reign") or {}).get("readings") or {}).get("peace", {}).get("now", 0), 2),
    "events_answered": events_answered,
    "seals_spent": sum(seal_acts.values()),
    "seals_refused": seal_fail,
    "seal_acts": dict(seal_acts),
    "seal_top_share": round(max(seal_acts.values()) / sum(seal_acts.values()), 2) if seal_acts else 0,
    "seal_hand_pick_share": round(seal_hand / sum(seal_acts.values()), 2) if seal_acts else 0,
    "two_or_more_worth_a_seal_share": round(multi_time / (mins * 60), 2),
    "seasons_with_seal": len(seal_seasons),
    "reach_at_seal": dict(collections.Counter(reach_at_seal.values())),  # of the 3 best uses, how many the treasury covers (aim: 2/3)
    "seasons_with_a_choice_share": round(len(choice_seasons) / max(1, len(seal_seasons)), 2),
    "reign_clock_minutes": round(((w.get("reign") or {}).get("elapsedMs") or 0) / 60000, 1),
}
json.dump(res, open(OUT, "w"), indent=1)
log.write(json.dumps(res) + "\n")
