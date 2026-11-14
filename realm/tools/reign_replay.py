#!/usr/bin/env python3 -I
"""A recorded reign served as the bridge (a test aid for READY.md line 10, the army half).

The Freeciv thread's reign harness (bridge/tools/reign_harness.mjs) plays one reign and writes each season's /world
to <run>/world.jsonl ({"turn", "at", "world"} a line) and the land to <run>/map.json. This serves them to the real
game as the bridge would: GET /map, GET /world (the season it stands on), GET /chronicle, /court and /mood (nothing new,
none sitting, none standing); anything else answers {}. The probe (tools/reign_army_probe.gd) steps it: POST /replay/step goes to the next season; GET /replay
says where it stands. turnSeconds is served as the realm's own pace (bridge/data/pace.json season), so the figures
march as they do in play, whatever pace the harness ran at.
  python3 -I realm/tools/reign_replay.py <run dir> [port=8871]
"""
import json, os, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

RUN = sys.argv[1]
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8871
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
SEASON = json.load(open(os.path.join(ROOT, "bridge", "data", "pace.json")))["season"]
WORLDS = [json.loads(l)["world"] for l in open(os.path.join(RUN, "world.jsonl")) if l.strip()]
MAP = open(os.path.join(RUN, "map.json"), "rb").read()
at = 0


class Replay(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, body, code=200):
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        p = self.path.split("?")[0]
        if p == "/map":
            return self._send(MAP)
        if p == "/world":
            w = dict(WORLDS[at])
            w["turnSeconds"] = SEASON
            return self._send(w)
        if p in ("/chronicle", "/court", "/mood"):
            return self._send([])  # nothing new, no court sitting, no decrees standing (the view asks /mood for them)
        if p == "/replay":
            return self._send({"at": at, "of": len(WORLDS), "turn": WORLDS[at].get("turn")})
        return self._send({})

    def do_POST(self):
        global at
        n = int(self.headers.get("Content-Length") or 0)
        if n:
            self.rfile.read(n)
        if self.path.split("?")[0] == "/replay/step":
            at = min(at + 1, len(WORLDS) - 1)
            return self._send({"at": at, "of": len(WORLDS), "turn": WORLDS[at].get("turn"), "last": at == len(WORLDS) - 1})
        return self._send({})


print(f"REPLAY {len(WORLDS)} seasons from {RUN} on {PORT}, season {SEASON} s", flush=True)
ThreadingHTTPServer(("127.0.0.1", PORT), Replay).serve_forever()
