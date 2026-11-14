Independent foundation audit — 12 November 2026

Recommendation: test Unity 6 with Classic City Builder Kit first. Compare it with 0 A.D. as a complete RTS foundation. Treat Unity Strategy Kit: RTS Engine as an alternative starting point if combat needs dominate the technical scope. Do not assume that combining both Unity kits is cheap.

This is a source and documentation audit. I inspected selected project files and current supplier documentation. I did not run the alternative engines, buy packages, or reproduce the reported 3 FPS result. Recommendations and effort ranges below are engineering estimates. Package compatibility and performance remain test gates.

The user accepts 600 soldiers if 6,000 is a real obstacle. This is an acceptable fallback, not evidence that soldier count caused the current slowdown. The existing 10 FPS minimum remains the stated floor; I recommend measuring against 30 FPS as an additional practical target.

**What the current approach gets wrong**

The project uses many reusable parts, but much of the behaviour connecting them is custom. The strongest evidence is the split between simulation and presentation:

- [project.godot](/Users/user/wednesday/civilization/realm/project.godot:24) already selects Jolt Physics. A missing general physics engine is not the immediate problem.
- [townsfolk.js](/Users/user/wednesday/civilization/bridge/townsfolk.js:68) generates a sample of 8–54 townsfolk. Ages and family descriptions are generated there. This function does not implement persistent households, births or ageing. Other character systems exist; this finding is specific to commoner generation.
- [battle_ai.gd](/Users/user/wednesday/civilization/realm/scripts/battle_ai.gd:2) explicitly states that the world supplies the battle outcome. Its local soldiers produce the visible fight around that outcome. That is a valid presentation design, but it does not establish one continuous physical simulation.
- [field_work.gd](/Users/user/wednesday/civilization/realm/scripts/field_work.gd:2) describes nearby field workers and their movement. More visible work does not by itself establish a worker-to-inventory production chain.
- [BUILDING_BLOCKS.md](/Users/user/wednesday/civilization/BUILDING_BLOCKS.md:6) claims 70% reuse without a measured feature or integration breakdown. It also claims Godot has the most game plugins without comparative evidence. Those claims are unsuitable as decision criteria.

My assessment: the project selected useful low-level pieces, then accepted a large amount of custom world logic and visual reconstruction. A complete city or RTS framework can remove more of that work than a better renderer alone.

The earlier free-kit survey also excludes paid options. The user's current instruction permits paid components. That opens alternatives the earlier research did not fairly compare.

**What each type of component supplies**

| Component | Main responsibility | What still needs another system |
|---|---|---|
| Game engine | Rendering, scenes, input, audio, platform builds | The rules of a medieval society |
| Physics engine | Collision and body motion | Ownership, jobs, prices, families |
| Navigation system | Reachable areas, routes and movement | Why a worker travels and what they carry |
| City or RTS framework | Connected buildings, workers, resources and commands | Features outside the framework's model |
| Asset pack | Models, materials, sometimes rigs and animations | Production rules and economic meaning |
| Project-specific simulation | House ownership, genealogy, succession and economic policies | Rendering and low-level physics |

This division is the proposed architecture. For example, a river needs terrain plus navigation restrictions; a wall needs a damage rule, visual damage states and a navigation update when breached. Full physical fracture is an optional presentation feature.

**Ranked foundations**

| Rank | Foundation | Reusable value | Main limit | Decision |
|---|---|---|---|---|
| 1 | Unity 6 + Classic City Builder Kit | Connected settlement and production systems | Large armies, genealogy and multiple noble houses remain unproved | First technical trial |
| 2 | 0 A.D. / Pyrogenesis | Complete 3D RTS, units, buildings, resources, combat and editing | Ancient setting; deep civilian society requires extensions | Best complete open-source comparator |
| 3 | Unity 6 + Strategy Kit: RTS Engine | Factions, collection, construction and combat | Household life and detailed commerce require extensions | Prefer if army systems dominate |
| 4 | Existing Godot project | Existing code and imported assets; scriptable workflow | Much custom simulation and integration remains | Retain only if a measured comparison favours it |
| 5 | Unreal + a verified RTS framework | Rendering and specialist simulation tools | Template maturity, platform support and integration vary | Reserve candidate |
| 6 | Recoil | Dedicated RTS infrastructure | Apple Silicon deployment and medieval content need more validation | Reserve for battle-heavy scope |

The ranking is my judgement for this team's reuse goal, not a measured performance ranking.

**Unity's city kit is the most relevant discovery**

Classic City Builder Kit documents buildings, population, employment, services, risks and resource systems. Its resource interfaces cover storage, production, distribution, retrieval and tax collection. These are connected systems you otherwise have to implement. [Manual](https://citybuilder.softleitner.com/manual), [resources](https://citybuilder.softleitner.com/manual/resources), [people](https://citybuilder.softleitner.com/manual/people).

Its 3D Colony Sim example includes job assignment, construction deliveries, food, warmth, farms, forestry and markets. Farming tasks vary by season. The task system lets a worker find and execute work in the world. This is particularly close to the user's examples. It is still a demo foundation; the documentation does not establish a full genealogy, price market, multi-house economy or 600-soldier combat system. [Colony manual](https://citybuilder.softleitner.com/manual/town), [playable example page](https://citybuilder.softleitner.com/demos/town).

The store lists **US$60**, Standard Unity Asset Store EULA, Single Entity, version 1.10.1, released 25 September 2026. Its release notes specify Unity 6000.0.76 as the minimum recommended version for 1.10.0 and conversion of demos to URP. That is useful maintenance evidence, not proof of defect-free operation. [Store](https://assetstore.unity.com/packages/templates/systems/classic-city-builder-kit-187814), [release notes](https://citybuilder.softleitner.com/manual/releases).

Unity provides an Apple Silicon editor and command-line execution of build scripts. The kit's published downloadable demo is Windows; Mac package compatibility must be tested separately. AI agents can write C# setup and validation scripts, but editor-based package workflows still need automation work. [Unity requirements](https://docs.unity.com/en-us/engine/6000.0/manual/get-started/install-and-upgrade/getting-started-installing-unity/system-requirements), [command line](https://docs.unity.com/en-us/engine/6000.0/manual/unity-editor/command-line-arguments/editor).

Unity Personal is free subject to its revenue and funding eligibility rules; do not infer eligibility from this game's revenue alone. [Plans](https://unity.com/products).

**The RTS alternatives**

Strategy Kit: RTS Engine documents units, buildings, factions, gathering, drop-off points, construction, combat and custom component APIs. Its store shows **US$93.50 per seat**, Extension Asset, Standard Asset Store EULA, and Unity 6000.0.51 compatibility. The displayed release is 3 August 2025. This is a credible trial candidate, but I found no verified 600-unit Mac benchmark. [Store](https://assetstore.unity.com/packages/tools/game-toolkits/strategy-kit-rts-engine-79732), [manual](https://docs.gamedevspice.com/rtsengine/manual/index.html).

CCBK and RTS Engine are separate frameworks. Both can own workers, resources, buildings and movement. Installing both does not settle which one controls those facts. Test them separately, then choose one primary owner. Any later adapter must carry commands and state changes across a narrow interface.

0 A.D. already combines gathering, construction, formations and combat, with an editor and open-format modding. The official download page provides a native M1+ build. Code is GPL and art/sound use CC BY-SA, subject to the project's detailed licence files. Its existing game is the integration example. Modifying it is a serious alternative to creating a new renderer around Freeciv. Its ancient art and RTS rules still need adaptation, and its performance must be measured. [Features](https://play0ad.com/game-info/features/), [Mac build](https://play0ad.com/download/mac/), [project and licensing](https://play0ad.com/game-info/project-overview/).

Godot Open RTS describes itself as a simple template and educational project. Its README targets Godot 4.3. It is MIT-licensed, but should not be counted as a complete living-world system or assumed compatible with this project's 4.7 build without a test. [Repository](https://github.com/lampe-games/godot-open-rts).

Unreal deserves consideration if a complete compatible project wins the comparison. Its engine features alone do not settle reuse. For example, Pioneer Mass Strategy System documents flat-ground-only movement and requires C++/Mass knowledge; its published performance example uses a Windows PC with an RTX 4070. The older open ue4-rts project lists UE4 and early UE5 compatibility. Neither proves an easy current Mac path. [Pioneer developer description](https://forums.unrealengine.com/t/pioneer-games-pioneer-mass-strategy-system/2523485), [ue4-rts](https://github.com/npruehs/ue4-rts).

Epic's current Mac documentation lists feature-specific GPU restrictions and experimental/beta features. Check against the chosen stable engine version and exact Mac. Standard game royalties generally begin above US$1 million lifetime gross revenue at 5%, with exclusions and possible reductions. [Mac requirements](https://dev.epicgames.com/documentation/en-us/unreal-engine/macos-development-requirements-for-unreal-engine), [release terms](https://www.unrealengine.com/release).

Recoil has dedicated RTS APIs, Lua scripting and headless operation. A community Apple Silicon port exists, but its additional platform work reduces its appeal for the lowest-integration route. [Official documentation](https://recoilengine.org/docs/), [Apple Silicon port](https://github.com/benbreen/RecoilEngine-AppleSilicon).

OpenRA explicitly targets classic 2D/2.5D RTS games. Widelands has useful economy code, but extracting that economy into a new 3D world is another integration project. Bevy is a code-first ECS engine, and O3DE's distribution page focuses on Windows and Linux. I found no reason to put those ahead of the complete foundations above for this Mac-based team. This is a scope decision, not a claim that they cannot be used. [OpenRA](https://www.openra.net/about/), [Widelands economy source](https://github.com/widelands/widelands/blob/master/src/economy/economy.cc), [Bevy](https://bevy.org/learn/quick-start/getting-started/ecs/), [O3DE](https://o3de.org/create/).

**Assets and their behaviour**

Use one coherent asset family in the trial. Accept a model only after checking scale, materials, animation rig, collision, navigation footprint, worker positions, damage states and level of detail. An attractive model alone is an incomplete building component.

Synty Fantasy Kingdom supplies buildings, characters, props and modular interiors in one family. Its store showed US$175 against a US$349.99 list price, with availability messaging; confirm the payable price and supply before purchase. It is low-poly art and does not prove a match to the painted target. Unity's Fantasy Kingdom sample is a useful complete lighting/rendering reference, but carries non-commercial terms. Commercial assets require the appropriate licence; buying the art does not automatically change all sample-project terms. [Synty pack](https://syntystore.com/products/polygon-fantasy-kingdom), [Unity sample and terms](https://activation.unity3d.com/demos/fantasy-kingdom).

The existing Quaternius assets are sufficient to test behaviour without another purchase. Final art selection should follow an in-engine comparison at the actual camera distance.

**Gold mine implementation using the recommended foundation**

This is a proposed mapping, not a claim that the kit includes a finished gold mine.

| Required part | Reuse | Configuration or custom work |
|---|---|---|
| Deposit and mine appearance | Existing meshes; kit building system | Collision, worker positions, navigation footprint |
| Finite ore | Kit items and harvest/task patterns | Persistent deposit amount and extraction task |
| Workers | Colony job/task system | Miner role and work animation |
| Carrying and storage | Delivery tasks and item storage | Capacity, route and receiving building |
| Refining | Resource production components | Ore-to-gold recipe and work requirement |
| House ownership | Project data extension | House ID on mine, store and treasury |
| Income | Storage accounting and collection patterns | Decide when stored gold becomes treasury income; prevent double counting |
| Scarcity and trade | Reusable inventory and delivery primitives | Prices, contracts and inter-house transfers remain custom until proven otherwise |

Use one authoritative inventory. Camera movement must not create or remove ore, workers or income. Persist deposits, carried goods, storage and ownership together. Births, ageing and family links need persistent person IDs and explicit rules; the inspected kits do not establish the complete requested family model.

**600 versus 6,000 soldiers**

The reduction makes conventional framework trials more reasonable. It does not prove a tenfold frame-rate gain. Rendering, pathfinding, avoidance, combat updates, shadows and effects must be measured separately.

Godot already has instanced rendering. Its documentation notes that a MultiMesh has all-or-nothing visibility and recommends spatial splitting when needed. Therefore, the presence of vertex animation and instancing is not enough to diagnose performance. [Godot MultiMesh guidance](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html).

Test 100, 300 and 600 fully active soldiers first. Preserve 6,000 as an optional later test. Record exact Mac model, resolution, build type, camera, CPU/GPU time and worst frame times. Compare stationary rendering, movement, combat and effects. A moving-unit demo on a different GPU is not an equivalent result.

**Proof of concept and effort**

These are test budgets for one developer supported by agents, not delivery promises.

| Order | Test | Estimated effort | Pass condition |
|---|---|---|---|
| 1 | Profile existing Godot at 100/300/600 units | 0.5–1 day | Identify measured CPU/GPU costs; establish baseline |
| 2 | Run unmodified CCBK examples on native Mac; automate one build | 1–2 days | Stable standalone build, save/load and scriptable setup |
| 3 | Add one mine, storage, workers and house treasury | 2–4 days | Goods conserved; work stops when workers or access disappear; reload preserves state |
| 4 | Compare 0 A.D.; separately test RTS Engine if needed | 1–3 days each | Working collection/combat with recorded Mac performance and extension effort |
| 5 | Wall damage and river crossing test | 1–2 days | River blocks routes; bridge enables them; breach updates navigation and persists |
| 6 | Apply one existing art family to a small scene | 1–2 days | Consistent scale/materials at the intended camera distance |

Do not merge both Unity frameworks during the first trial. Select the foundation that passes the most required behaviours with the least new code and the clearest state ownership.

The two Unity framework listings total US$153.50 before taxes and engine subscriptions, if both are purchased for evaluation under the displayed terms. No purchase was made during this audit.

Full migration is likely measured in weeks to months. GDScript scenes and shaders need porting; data, original art and some Node rules may remain usable. Existing saves need explicit conversion. A narrower estimate requires the prototype results and a module inventory.

Confidence is high in the documented component capabilities and the cited source observations. Confidence is medium in the recommended ranking. Mac performance, combined-framework compatibility, complete family simulation and final visual quality remain unverified.
