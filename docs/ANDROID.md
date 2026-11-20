# Game of Crowns on Android and iOS

Spike, 2026-11-20. Can the game run on phones, and what's the cheapest working path?

**Answer: yes, on both.** Every piece of the game now builds for Android: the Godot game, Node and Freeciv. iOS needs the same pieces running inside the game's own process. Effort to a playable phone build is about **18 days for Android, then about 12 more for iOS**. That includes the mobile controls.

## What the spike proved

| Piece | Result |
|---|---|
| Godot 4.7.2 Android export of `realm/` | Exports, signs and installs (a 2.5 GB debug APK, textures capped at 1024 px). It starts on the emulator and draws Godot's splash screen. The emulator can't draw the game itself: its software graphics fail on Vulkan and run out of shader slots on OpenGL. **A real phone is the next test.** |
| LimboAI and Terrain3D add-ons | Both already ship Android arm64 builds. |
| freeciv-server 3.2.6 built with the Android NDK (ICU, curl, sqlite and zstd linked in) | Builds in about 4 minutes, 6.8 MB. Runs on the emulator. |
| Node 18.20 (nodejs-mobile) | Runs on Android and can start other programs. The real bridge loads and listens on 8787. Making a new realm stops at zstd, which needs Node 22.15 or later. |
| Node 26.13 (the desktop's version) built for Android | Gets past V8 with NDK r30 plus two fixes in `packaging/android/node-android.sh`. Not finished, because the workstation overheated during the build. |

The build scripts are in `packaging/android/`. The mockups are in `docs/art/mobile/`. The work files are on the workstation in `~/goc-android/`.

## The path

### Android: three processes, the same as desktop
1. **Godot** exports arm64 only, on the Mobile renderer.
2. **Node** is Node 26 built from source, shipped as `lib/arm64-v8a/libnode_exec.so`. Android runs programs only from the app's native library folder, so the files must be named `lib*.so`, and the export must use a Gradle build with `extractNativeLibs=true`.
3. **Freeciv** ships the same way, as `libfreeciv_server.so`. The bridge starts it exactly as on desktop.
4. `app_services.gd` gets an Android branch that finds the native library folder and starts Node with `OS.create_process`. On first launch the bridge and the rules unpack into the app's files folder.

### iOS: one process
Apple doesn't allow apps to start other programs, so both companions run as threads inside the game:
- **Node:** nodejs-mobile's iOS framework, which is Node 18, started from a small GDExtension. The bridge needs a thin compatibility layer: a WebAssembly zstd, and one `\p{L}` regex in `royals.js` written out as letter ranges.
- **Freeciv:** built as a static library, with its server main started on a second thread. They still talk over 127.0.0.1, so the bridge barely changes.
- **Size:** about 310 MB before the game's art (engine 80, Node 45, Freeciv and ICU 35, bridge and rules 150).

### Size: a small install, the rest downloaded after
The first export was 5.8 GB, over Android's 4 GB limit. Capping textures at 1024 px brought it to 2.5 GB: textures 1.86 GB, meshes 0.53, audio 0.10, engine 0.09.
- The store build carries the engine, the title screen, Kingsmere and one house's lands, aiming for under 200 MB. The rest of Aldmere downloads on first launch as resource packs loaded with `ProjectSettings.load_resource_pack()`. That's how Call of Duty Mobile does it, and it works the same on iOS.
- A 512 px cap on small props and ASTC 6x6 on the ground would roughly halve the textures again.

## Blockers and risks
1. **Size** (above) is the biggest piece of work.
2. **Editor-only code in every exported build:** `addons/godot_vat/vat_multi_mesh_instance_3d.gd` uses `EditorFileDialog`. In an exported build `army.gd` and `world_clock.gd` then fail to compile. This probably affects the desktop builds too, so check it there.
3. **Shaders:** 4 errors on the Mobile renderer, and the OpenGL fallback goes over the fragment uniform limit. Fix them on a real phone.
4. **Look:** the Mobile renderer has no SDFGI, SSIL or volumetric fog, so Kingsmere will look flatter. Plan a look pass against the approved autumn frame.
5. **Heat and battery:** cap at 30 fps, with fewer soldiers and thinner crowds on a battery-saver setting.
6. **Background:** save when the app is paused (`NOTIFICATION_APPLICATION_PAUSED`).
7. **Workstation:** it hard-reset three times today under heavy load (emulator, VM, builds). Long phone builds should run in CI.

## Mobile play (design)
Mockups: `docs/art/mobile/` (title, realm map, Kingsmere, battle, siege, court).
- **Landscape only**, with both thumbs on the bottom corners (Total War mobile, Civ VI, Northgard).
- **One pinch through three zoom stops:** realm (about 55°), region (about 45°), roof height (about 35°). Never top-down. It opens on Kingsmere with the royal host in view. Pinch already works, because the camera handles the gestures phones send.
- **Five gestures:** tap, drag, pinch, twist, tap-and-hold.
- **March by dragging** from a host to its target. The order word ("March", "Attack", "Besiege") shows under the finger, and time slows while the finger is down (Rome: Total War's Command Slowdown).
- **Form up:** tap-and-hold a troop and drag the front line. Buttons for Line, Shield wall and Wedge (Total War).
- **Siege card:** Starve, Build rams, Assault (Stronghold).
- **Court:** one card with two buttons, and the houses that gain or lose shown in words (Reigns).
- **Read at the top, act at the bottom.** Touch targets at least 48 dp, text at least 15 pt, and every state shown in words or shapes, never colour alone.
- **Cut:** keyboard shortcuts, hover tips (tap-and-hold instead), box select and dense tables (shown one card at a time).

## Effort (days, one builder)
| Work | Android | iOS |
|---|---|---|
| Gradle export, native libs, launch from `app_services.gd` | 2 | |
| Unpack bridge and rules on first launch | 1 | 1 |
| Freeciv as a library on a thread; bridge "already running" mode | | 3 |
| Node in-process GDExtension | | 2 |
| Texture cap, base and extra packs, download screen | 4 | 1 |
| Mobile renderer look pass, shader fixes, 30 fps | 3 | 1 |
| Touch controls and mobile HUD | 5 | 1 |
| Background save, pause, resume | 1 | 1 |
| CI build and signing (Play, TestFlight) | 2 | 2 |
| **Total** | **~18** | **~12** |

## Next step
Run the APK on a real Android phone to see the title screen, then build the Gradle export with Node and Freeciv inside it.
