"""Stand in for the Godot editor's debugger: accept the game's remote-debug
connection, ask for the Video RAM list (what Debugger > Video RAM shows) at
given seconds, and save each reply as JSON: [count, path, format, type, bytes, ...].
Godot's own numbers, no accounting of ours. A script error the game breaks on is
printed and continued. Usage (start this first, then the game):
  python3 -I realm/tools/vram_list.py 6017 /tmp/vram 50 80 &
  GODOT_ARGS="--remote-debug tcp://127.0.0.1:6017" realm/tools/render.sh out.png --city=Kingsmere --dist=0.6 --wait=95"""
import socket, struct, sys, time, select

port = int(sys.argv[1]); prefix = sys.argv[2]; times = [float(t) for t in sys.argv[3:]]

class R:
    def __init__(s, b): s.b = b; s.o = 0
    def u32(s): v = struct.unpack_from('<I', s.b, s.o)[0]; s.o += 4; return v
    def i32(s): v = struct.unpack_from('<i', s.b, s.o)[0]; s.o += 4; return v
    def i64(s): v = struct.unpack_from('<q', s.b, s.o)[0]; s.o += 8; return v
    def f(s, wide):
        if wide: v = struct.unpack_from('<d', s.b, s.o)[0]; s.o += 8
        else: v = struct.unpack_from('<f', s.b, s.o)[0]; s.o += 4
        return v
    def s(s):
        n = s.u32(); v = s.b[s.o:s.o+n].decode('utf8', 'replace'); s.o += n + ((4 - n % 4) % 4); return v

FLOATS = {5: 2, 7: 4, 9: 3, 11: 6, 12: 4, 14: 4, 15: 4, 16: 6, 17: 9, 18: 12, 19: 16, 20: 4}
INTS = {6: 2, 8: 4, 10: 3, 13: 4}

def dec(r):
    h = r.u32(); t = h & 0xFF; wide = bool(h & (1 << 16))
    if t == 0: return None
    if t == 1: return bool(r.i32())
    if t == 2: return r.i64() if wide else r.i32()
    if t == 3: return r.f(wide)
    if t in (4, 21): return r.s()
    if t in FLOATS: return [r.f(wide and t != 20) for _ in range(FLOATS[t])]
    if t in INTS: return [r.i32() for _ in range(INTS[t])]
    if t == 22:
        n = r.u32()
        if n & 0x80000000:
            sub = r.u32(); fl = r.u32(); names = n & 0x7FFFFFFF
            return '/'.join(r.s() for _ in range(names + sub))
        return r.s()
    if t == 23: return ('RID', r.i64())
    if t == 24:
        if wide: return ('OBJ', r.i64())
        cls = r.s()
        if not cls: return None
        n = r.u32(); return {cls: {r.s(): dec(r) for _ in range(n)}}
    if t == 27:
        kt = (h >> 16) & 3; vt = (h >> 18) & 3
        for x in (kt, vt):
            if x == 1: r.i32()
            elif x in (2, 3): r.s()
        n = r.u32() & 0x7FFFFFFF; d = {}
        for _ in range(n):
            k = dec(r); d[str(k)] = dec(r)
        return d
    if t == 28:
        at = (h >> 16) & 3
        if at == 1: r.i32()
        elif at in (2, 3): r.s()
        n = r.u32() & 0x7FFFFFFF
        return [dec(r) for _ in range(n)]
    if t == 29:
        n = r.u32(); v = r.b[r.o:r.o+n]; r.o += n + ((4 - n % 4) % 4); return v
    if t == 30: n = r.u32(); return [r.i32() for _ in range(n)]
    if t == 31: n = r.u32(); return [r.i64() for _ in range(n)]
    if t == 32: n = r.u32(); return [r.f(False) for _ in range(n)]
    if t == 33: n = r.u32(); return [r.f(True) for _ in range(n)]
    if t == 34: n = r.u32(); return [r.s() for _ in range(n)]
    per = {35: 2, 36: 3, 37: 4, 38: 4}.get(t)
    if per: n = r.u32(); return [[r.f(False) for _ in range(per)] for _ in range(n)]
    raise ValueError('variant type %d' % t)

def enc(v):
    if v is None: return struct.pack('<I', 0)
    if isinstance(v, bool): return struct.pack('<Ii', 1, int(v))
    if isinstance(v, int): return struct.pack('<Iq', 2 | (1 << 16), v)
    if isinstance(v, str):
        b = v.encode(); return struct.pack('<II', 4, len(b)) + b + b'\0' * ((4 - len(b) % 4) % 4)
    if isinstance(v, list): return struct.pack('<II', 28, len(v)) + b''.join(enc(x) for x in v)
    raise ValueError(v)

def send(c, name, tid, data):
    p = enc([name, tid, data]); c.sendall(struct.pack('<I', len(p)) + p)

srv = socket.socket(); srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(('127.0.0.1', port)); srv.listen(1); srv.settimeout(600)
c, _ = srv.accept(); t0 = time.time(); print('game connected', flush=True)
buf = b''; tid = 1; asked = 0; got = 0; names = {}
while True:
    if asked < len(times) and time.time() - t0 >= times[asked]:
        send(c, 'servers:memory', tid, []); asked += 1; print('asked at %.0f s' % (time.time() - t0), flush=True)
    rd, _, _ = select.select([c], [], [], 0.5)
    if not rd: continue
    chunk = c.recv(1 << 20)
    if not chunk: break
    buf += chunk
    while len(buf) >= 4:
        n = struct.unpack_from('<I', buf)[0]
        if len(buf) < 4 + n: break
        pkt = buf[4:4+n]; buf = buf[4+n:]
        try: msg = dec(R(pkt))
        except Exception as e: print('undecoded', e, flush=True); continue
        name = msg[0]; tid = msg[1] if isinstance(msg[1], int) else tid
        names[name] = names.get(name, 0) + 1
        if name == 'debug_enter':
            print('debug break:', str(msg[2])[:300], flush=True)
            send(c, 'continue', tid, [])
        if name == 'servers:memory_usage':
            got += 1; arr = msg[2]; out = '%s-%d.json' % (prefix, got)
            import json; json.dump(arr, open(out, 'w'), default=str)
            print('wrote', out, 'items', len(arr), flush=True)
print('closed; messages seen:', names, flush=True)
