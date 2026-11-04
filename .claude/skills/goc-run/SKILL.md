---
name: goc-run
description: How to run Game of Crowns on the Mac: the bridge, Freeciv, the Godot view, the local model and screenshot renders. Load before running, rendering or measuring anything.
---

# Running it

1. **Native only.** Claude's shell runs under Rosetta: launch Godot as `arch -arm64 godot …`, always. Intel Godot is several times slower and every timing lies.
2. **The realm:** `./realm.sh` (open), `status`, `start`, `stop`. The bridge is a launch agent (`com.realm.bridge`, port 8787); it starts Freeciv (port 5556). Ali isn't playing until he says so: restart freely.
3. **Renders:** `arch -arm64 godot --path realm --resolution 2400x1380 -- --shot=<png> --wait=<s>` plus a scene: `--city=<Name> --dist=N`, `--new`, `--hero=<house>`, `--move=<move>`, `--control=<house>`, `--duel`, `--interior=<great_hall|tavern|chapel|cottage>`, `--feast`, `--handover`, `--battle`, `--siege`. Event shots time themselves; `--wait` is only the fallback.
4. **One Godot at a time, and Ali's game comes first.** Run renders in the background, in sequence, only while Ali isn't playing. Stop only your own renders, matched by their arguments (`pkill -f "godot --path realm --resolution"`), never `pkill -x Godot`: that kills Ali's game too. Metal "timeout waiting for fence" means a GPU stall: rerun it.
5. **The local model:** Off Grid AI desktop, gateway on 127.0.0.1:7878+, Omni 2B must be loaded in the app. The first call loads it (~80 s); then 1–8 s.
6. **Mind the Mac.** Check `uptime` and the top processes before timing anything; other projects' builds and the model make numbers noisy.
7. **Assets in:** Mixamo FBX (Without Skin, 30 fps, In Place) → `realm/assets/anims/mixamo/<Move>.fbx`, import, set its retarget bone map to `res://assets/retarget/mixamo_map.tres`. Interiors → `realm/assets/interiors/<room>/`.
