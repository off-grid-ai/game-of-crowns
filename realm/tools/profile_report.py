# profile_report.py <prof.txt> [min process ms]: Godot profiler frames (tools/profiler.gd) ranked by self time per frame
import sys, re, collections
sig = {}
agg = collections.defaultdict(lambda: [0, 0.0, 0.0])
frames = []
first = -1
floor = float(sys.argv[2]) / 1000.0 if len(sys.argv) > 2 else 0.0
tok = re.compile(r'&"[^"]*"|"[^"]*"|[-0-9.e+]+')
for line in open(sys.argv[1]):
    t, name, data = line.rstrip('\n').split('\t', 2)
    if name == 'servers:function_signature':
        a = tok.findall(data)
        sig[int(float(a[1]))] = a[0].strip('&"')
    elif name == 'servers:profile_frame':
        a = tok.findall(data)
        fn = int(float(a[0]))
        ft, pt, ph, phf, st = map(float, a[1:6])
        first = first if first >= 0 else fn
        if pt < floor:
            continue
        i = 6
        ns = int(float(a[i])); i += 1
        for _ in range(ns):
            i += 1
            nf = int(float(a[i])); i += 1
            i += nf
        n = int(float(a[i])); i += 1
        if fn <= first + 2: continue
        frames.append((fn, ft, pt, ph, st))
        for k in range(n // 5):
            s_, c, self_, tot, intl = a[i:i + 5]; i += 5
            g = agg[int(float(s_))]
            g[0] += int(float(c)); g[1] += float(self_); g[2] += float(tot)
nf = len(frames) or 1
avg = lambda j: sum(f[j] for f in frames) * 1000 / nf
srt = sorted(f[1] for f in frames) or [0]
print("frames %d  avg frame %.1f ms (%.0f fps)  median %.1f ms  p95 %.1f ms  process %.1f  physics %.1f  script %.1f" % (
    len(frames), avg(1), 1000 / max(avg(1), 0.001), srt[len(srt) // 2] * 1000, srt[int(len(srt) * 0.95)] * 1000, avg(2), avg(3), avg(4)))
print("\nTOP BY SELF TIME (ms per frame, total ms per frame, calls per frame)")
for k, v in sorted(agg.items(), key=lambda kv: -kv[1][1])[:45]:
    print("%7.2f self %7.2f total %7d calls  %s" % (v[1] * 1000 / nf, v[2] * 1000 / nf, v[0] // nf, sig.get(k, k)))
