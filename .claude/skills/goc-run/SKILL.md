---
name: goc-run
description: How to run Game of Crowns on the Mac: the bridge, Freeciv, the Godot view, the local model and screenshot renders. Load before running, rendering or measuring anything.
---

# Running it

1. **Native only.** Claude's shell runs under Rosetta: launch Godot as `arch -arm64 godot …`, always. Intel Godot is several times slower and every timing lies.
2. **The realm:** `./realm.sh` (open), `status`, `start`, `stop`. The bridge is a launch agent (`com.realm.bridge`, port 8787); it starts Freeciv (port 5556). Mac isn't playing until he says so: restart freely.
3. **Renders:** `arch -arm64 godot --path realm --resolution 2400x1380 -- --shot=<png> --wait=<s>` plus a scene: `--city=<Name> --dist=N`, `--new`, `--hero=<house>`, `--move=<move>`, `--control=<house>`, `--duel`, `--interior=<great_hall|tavern|chapel|cottage>`, `--feast`, `--handover`, `--battle`, `--siege`. Event shots time themselves; `--wait` is only the fallback.
4. **One Godot at a time, and Mac's game comes first.** Every session renders through `realm/tools/render.sh <out.png> <args>`: it queues for the GPU (a shared lock) and waits while Mac's game is open, so sessions never render over each other or lag his game. Never kill `render.sh` or `--shot` processes to make room: other sessions' renders are waiting in that queue, and Mac's game already comes first. Run renders in the background, in sequence, only while Mac isn't playing. Stop only your own renders, matched by their arguments (`pkill -f "godot --path realm --resolution"`), never `pkill -x Godot`: that kills Mac's game too. Metal "timeout waiting for fence" means a GPU stall: rerun it.
   **Headless checks are not renders (supervisor, 2026-11-12, Mac: "many threads are idle").** `--check-only` and
   headless probes (`--headless -s res://tools/*_probe.gd`) don't use the GPU: up to 3 may run at once across all
   sessions (`pgrep -fc "godot --headless"` < 3), and every one is bounded so a probe that never quits can't hold the queue. This Mac has no `timeout`/`gtimeout`:
   wrap the command as `perl -e 'alarm shift; exec @ARGV' 180 arch -arm64 godot --headless ...`, and give each probe
   `realm/tools/watchdog.gd` (a9afe4b9: exits 2 after 150 s with no verdict). A probe must call `quit()` on
   every path. Never wait behind a headless run with `pgrep -x godot`; only windowed renders queue through render.sh.
   (A hung before-run held every thread for 15 minutes on 12 Nov; the 10-core machine sat at load 5.)
5. **The local model:** Off Grid AI desktop, gateway on 127.0.0.1:7878+, Omni 2B must be loaded in the app. The first call loads it (~80 s); then 1–8 s.
6. **Mind the Mac.** Check `uptime` and the top processes before timing anything; other projects' builds and the model make numbers noisy.
7. **Assets in:** Mixamo FBX (Without Skin, 30 fps, In Place) → `realm/assets/anims/mixamo/<Move>.fbx`, import, set its retarget bone map to `res://assets/retarget/mixamo_map.tres`. Interiors → `realm/assets/interiors/<room>/`.
8. **On Linux** (a cloud box, CI): `packaging/linux-setup.sh` once (Godot 4.7.1, Freeciv 3.2.6, an `arch` stand-in, a virtual screen with software Vulkan), then `packaging/linux-bridge.sh`. Everything else is as above: `realm.sh status`, `render.sh`, `reign_measure.py`. Renders are slow on software Vulkan; reigns measured through the bridge are not. The third-party art isn't in git, so a fresh clone needs it copied in before Godot can open the realm.
