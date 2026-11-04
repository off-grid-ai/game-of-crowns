# Shipping Game of Crowns for Mac

One script cuts a build: `build/Game of Crowns.app` and `build/Game-of-Crowns-<version>-arm64.dmg`.
A player double-clicks the app; nothing else to install.

```bash
packaging/build-mac.sh
```

`SKIP_EXPORT=1 packaging/build-mac.sh` reuses the last Godot export (handy when only the bridge changed).
After changing textures, re-import first: `cd realm && arch -arm64 godot --headless --path . --import`.

## What's in the app

| Inside `Contents/Resources` | From |
| --- | --- |
| `Game of Crowns.pck` | Godot export, preset "macOS" in `realm/export_presets.cfg` (universal template, thinned to Apple Silicon) |
| `bridge/`, `WORLD.md` | this repo, without `bridge/chronicles` |
| `runtime/node` | the official Node build from nodejs.org, pinned version and checksum in the script |
| `runtime/freeciv` | `freeciv-server` from Homebrew with its libraries copied in (`dylibbundler`), plus its data |
| `runtime/llama` | Off Grid AI Desktop's `llama-server` (`~/wednesday/off-grid-ai/desktop/resources/bin/llama`, override with `OGAD_LLAMA`) |

Build Mac needs: Godot 4.7.2 with export templates, Homebrew `freeciv`, `dylibbundler` (`arch -arm64 brew install dylibbundler`), and an OGAD checkout with its engines.

## How it runs

- `realm/scripts/app_services.gd` (an autoload) only acts in the exported app. It starts `bridge/app.js` on the bundled Node, unless a bridge is already listening on 8787. When the game quits it stops the bridge.
- `bridge/app.js` points the bridge at the bundled Freeciv and keeps everything the player makes in `~/Library/Application Support/Game of Crowns`: `chronicles/`, `records.json`, `scenarios.json`, `models/`, `logs/` (`bridge.log`, `omni.log`).
- If the game dies, the bridge sees its parent is gone within a second and shuts down Freeciv and the model.
- **Omni 2B** (text only) is fetched on first run, the way OGAD fetches models: one file (`LFM3-Omni-2B-Q8_0.gguf`, 1.8 GB) from Hugging Face, pinned to a revision and checked against its sha256. If OGAD already has an Omni 2B file, that copy is used and nothing is downloaded. Until the model is ready, the realm decides by its rules. The model is served on 127.0.0.1:8789.
- If Off Grid AI Desktop is running with Omni loaded, the bridge prefers it, because OGAD also gives the realm voices and hears spoken rulings. Without OGAD, there are no voices and no speech input.

## Signing and notarisation

The same route and secrets as Off Grid AI Desktop's release (`OGAD/.github/workflows/release.yml`):

| Variable | What |
| --- | --- |
| `CSC_LINK`, `CSC_KEY_PASSWORD` | base64 Developer ID Application `.p12` and its password (or `SIGN_IDENTITY` naming one already in the keychain) |
| `APPLE_API_KEY` | path to the App Store Connect `.p8` key |
| `APPLE_API_KEY_ID`, `APPLE_API_ISSUER` | that key's id and issuer |

With these set, the script signs everything with hardened runtime (`packaging/entitlements.plist`, OGAD's entitlements without Apple Events), notarises and staples the app, then signs, notarises and staples the dmg. Without them it signs ad hoc, which runs on the build Mac but is blocked by Gatekeeper on anyone else's.

These secrets live on the `off-grid-ai/OGAD` repo. This Mac has no Developer ID certificate, so a real release needs either the `.p12` and API key here, or the secrets copied to `off-grid-ai/game-of-crowns` and a release job there.

## Known gaps

- A **random** realm runs `python3 bridge/tools/worldgen.py`. A Mac without the Xcode command line tools will ask to install them. Aldmere, the default realm, needs no Python.
