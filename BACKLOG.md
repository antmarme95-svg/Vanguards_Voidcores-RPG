# Aether Bound — Sprint Backlog

> **Durable source of truth.** Updated after *every completed task* (not just sprint gates), before spawning the next executor. On any cold resume: read this file → read auto-memory `borisawa-sprint-progress` → continue from the `Next step` of the first non-`done` task. Mirrors the in-session task list; this file outlives the session.

## Locked decisions (re-read first on resume)

- **Build target:** Godot only. `godot/` is the implementation; `src/` (Three.js) is a **frozen reference** — do not edit it.
- **Class scope:** full **9 sub-class matrix** = Origin×Class cross-product (GDD §2 RECEIVED → `godot/data/substyles.json`). Vanguard=Warrior/Tank, Strategist=Mage/Support, Duelist=Thief/DPS.
- **Lighting:** baked lightmaps + few dynamic lights + "fake" day/night via ambient/skybox interpolation. **No SDFGI.**
- **Checkpoint cadence:** flush BACKLOG.md + memory after **every task**.
- **Acceptance north stars:** Origin+Class legible at ~3 m by silhouette+color (PRD-001 §8); object cel-register identical across biomes (PRD-002 §8); Run→Sprint instant + slide survives 360° camera + air control (PRD-003); frame budget (≥60 FPS) holds.

## Model tiering

| Role | Model |
|---|---|
| Orchestrator (design, gates, merges) | Opus 4.8 Ultracode |
| Primary executor (logic/shaders/VFX) | Sonnet 4.6 |
| Mechanical executor (JSON/data/boilerplate) | Haiku 4.5 |
| Always-on parallel QA | Sonnet 4.6 |

## Environment

- **Godot 4.6.3** confirmed at: `%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.6.3-stable_win64.exe` — **not on PATH**; invoke by explicit path (or via `Start-Godot.bat`).
- QA run (logic): `& $GODOT --headless --path godot --script res://tests/test_core.gd`.
- QA run (visual — MUST be windowed, headless blanks the renderer): `& $GODOT --path godot -- --autotest=res://tests/autotest_{rig,scenes,slice,ui}.gd` → PNG/JSON in `godot/test_out/`; diff vs `godot/test_out/before/`.
- **Persistent QA agent id:** `aaa5f11c8c6f485bc` (continue via SendMessage, don't re-spawn cold).

## Perf budget (measured baseline)

- **Gate: ≥60 FPS** in The Wilds (enforced in `autotest_scenes.gd`). Baseline **466 FPS** → ~7.7× headroom for VFX/atmosphere, but **overdraw** (stacked transparencies: shields/auras/trails/volumetric/alpha foliage) is the watched metric — every transparency-adding task re-checks wilds_fps stays ≥60.
- ⚠ **Watch-item (CONFIRMED persistent):** wilds_fps is steady ~310–330 across clean re-measures (Sprint-0 fix + Sprint-1 gate: 310.6) vs the singular 466 first-baseline. Still **>5× the 60 gate (NOT blocking)**. Likely (a) the 466 first-run was a cold-cache anomaly, or (b) the DayNightCycle child node added in Sprint 0. **Root-cause deferred to Sprint 5 (perf hardening):** A/B by disabling day_night + profile; first check that day_night `_process` early-returns when cycle_speed==0 and doesn't re-apply the Environment every frame.

## Lessons learned (apply to all future executor briefs)

- **NEVER use a bare `class_name` cross-script reference** — Godot's class_name registry has a CLI load-order race that intermittently breaks compilation. Always `const _X = preload("res://…")` and reference `_X` (and use `Node`/`RefCounted` for the type annotation). Hit twice already (PipelineConfig 0.2, DayNightCycle 0.5).
- **Visual autotests are windowed-only** and must run **one Godot instance at a time** — concurrent instances hang and orphan. Always kill leftover `Godot*` processes after a run.
- **`test_core` (headless) does NOT load scene/main scripts** — it can't catch the_wilds/main compile errors. Gate visual/scene changes with `autotest_scenes` + `autotest_slice` too.

## Task board

Status: ✅ done · 🔄 in-progress · ⛔ blocked · ⬜ todo

| ID | Sprint | Task | Status | Owner | Acceptance check | QA result | Next step |
|---|---|---|---|---|---|---|---|
| 0.0 | 0 | Continuity scaffold (BACKLOG.md + memory) | ✅ | Opus | BACKLOG.md + project/feedback memory exist; index updated | n/a | Done |
| 0.1 | 0 | Resolve Godot CLI availability | ✅ | Opus | `godot --version` runs | n/a | Done — path recorded above |
| 0.2 | 0 | Lock GLOBAL pipeline params as resources | ✅ | Sonnet | params centralized; PNG diff vs baseline must MATCH (no visual change) | rig 11/11 non-blank, no shader errors; test_core ALL_PASS | Done — full PNG diff at gate. Files: toon.gdshader, pipeline_config.gd, toon_materials.gd |
| 0.3 | 0 | JSON config loader (locomotion + class mult.) | ✅ | Sonnet | JSON + Config autoload load with fallback; no behavior change yet | smoke baseSpeed=3.3, warrior speedMult=1.0; test_core ALL_PASS; autoloads preserved | Done. Files: data/locomotion.json, data/class_multipliers.json, core/config.gd, project.godot |
| 0.4 | 0 | Expand class data to 9 sub-class matrix | ✅ | Haiku | substyles.json (3×3) + Config.substyle()/archetype() accessors; smoke + 4 new test_core cases pass (Chrono-Weaver/Scrap-Slinger/Vanguard); test_core ALL_PASS 27/27 | Done. Files: data/substyles.json, core/config.gd, tests/test_core.gd (+_test_config). Feeds Sprint 3 |
| 0.5 | 0 | Baked + fake day/night lighting skeleton | ✅ | Sonnet | default look == baseline; cycle lever exists; no SDFGI; FPS≥60; project compiles deterministically | Fixed via preload-const (the_wilds.gd). autotest_scenes ×2 + autotest_slice + test_core all clean; main.gd loads; scenes fresh & non-blank; orchestrator eyeballed overview render = look intact. wilds_fps 315–330 (≥60; ⚠ vs 466 baseline — watch-item) | Done. Files: scenes/day_night.gd, scenes/the_wilds.gd. Enable cycle: set DayNightCycle.cycle_speed>0 |
| 0.6 | 0 | QA baseline capture + perf harness | ✅ | Sonnet QA | test_out/before/ PNG+FPS baseline committed; budget defined | 21+ non-blank PNGs in test_out/before/; test_core 24/24; wilds_fps=466 (gate 60) | Done — re-run 4 autotests after changes, diff vs before/ |
| 1 | 1 | Locomotion FSM & physics (PRD-003) | ✅ | Sonnet | 8-state FSM + slide/air-control(0.2)/FOV-kick/landing-stutter; JSON+class-driven | INDEPENDENT QA green: test_locomotion ALL_PASS (44 checks), test_core ALL_PASS (29), autotest_slice ALL_PASS in-game, autotest_scenes clean. All 7 PRD-003 criteria verified. | Done. Files: gameplay/locomotion_state_machine.gd, tests/test_locomotion.gd, gameplay/player_controller.gd, data/locomotion.json, core/config.gd. State map: Walk=crouch-move, Run=default, Sprint=shift |
| 2.1 | 2 | Production cel ramp as GradientTexture1D resource | ✅ | Sonnet | light() samples a GLOBAL ramp resource; 4-band look matches baseline (eyeball) | 22 rig PNGs fresh+non-blank (26–58 KB); autotest_rig log clean (zero ERROR/shader errors); test_core ALL_PASS | Done. Files: rendering/toon_ramp.tres (256px, CONSTANT interp), toon.gdshader (texture sample replaces step-branch), pipeline_config.gd (RAMP_PATH + _get_ramp() + apply_to sets toon_ramp). toon_materials.gd unchanged |
| 2.2 | 2 | Rim-Fresnel + per-Origin visual language | ✅ | Sonnet | rim color per Origin; 3 origins visually DISTINCT | Eyeballed 3 origins: Aether teal-rim STRONG; Mist green-rim+fur GOOD; ⚠ Iron heat/sparks UNDER-READ (orange rim low-contrast on skin). slice ALL_PASS, wilds_fps 329.6, test_core ALL_PASS | Done (first pass). File: character/character_rig.gd. ⚠ Iron-Blooded punch-up = gate refinement question |
| 2.2b | 2 | Iron-Blooded heat/spark punch-up | ✅ | Sonnet+Haiku | Iron reads clearly warmer/hotter | Done: metal heat 0.6→1.8 + dark iron base + 30 brighter arcing sparks (Sonnet); bright hot-orange rim 0.32 across silhouette (Haiku). Eyeball: orange rim visible on dark areas/legs, warmer cast. NOTE orange-on-skin lower-contrast than teal; sparks read best in motion. wilds_fps 321; slice+test_core ALL_PASS | Done. Deeper Iron art pass (warm gear/skin tint) = optional future polish |
| 2.3 | 2 | Albedo-only grunge / zero-PBR audit | ✅ | Opus(audit) | zero PBR on characters | AUDIT PASS: all character StandardMaterial3D are UNSHADED (eyes/iris/pupil/fur/sparks/hair-stub); main surfaces = toon ShaderMaterial (ROUGHNESS=1/METALLIC=0); no metallic/roughness/normal textures. Compliant by construction — no changes needed | Done |
| 2.4 | 2 | NPC post-process edge-detect outline | ⬜ DEFERRED→S5 | Sonnet | NPCs use screen-space edge outline; principals keep inverted hull | — | DEFERRED to Sprint 5: principals already have working inverted-hull outlines; NPC edge-detect is an optimization, not core to PRD-001 §4-5 |
| 3.1 | 3 | Archetype silhouette differentiation (Vanguard/Strategist/Duelist) | ✅ | Sonnet | bulk/lean/support proportions per archetype | Eyeballed: Vanguard BULKY, Duelist LEAN, Strategist mid+floating focus orb — visibly distinct. Wired game_director (OFFICE enter + on_class_selected). slice ALL_PASS, wilds_fps 320, test_core ALL_PASS | Done. Files: character_rig.gd (_apply_build/apply_archetype/_focus_orb), game_director.gd, tests/autotest_archetype.gd. NOTE orb is white — accent-tint later |
| 3.2 | 3 | Duelist VFX (Spell-Blade trails / Scrap-Slinger muzzle+tracer / Shadow-Stalker blink) | ✅ | Sonnet | each Duelist cell has signature combat VFX | autotest_duelist ALL_PASS (3 PNGs fresh+non-blank ~68–73 KB each; 1 projectile active per case); autotest_slice ALL_PASS; wilds_fps=310 (≥60); test_core ALL_PASS. VFX visible in PNGs: spellblade dagger at arm-tip (teal glow); scrapslinger tracer at arm-tip (orange cast on rig from muzzle flash); shadowstalker purple capsule blink flash VERY clear + dark projectile visible. Muzzle-flash (0.06s) expires before frame commit — by design. | Done. Files: gameplay/player_controller.gd (_spawn_duelist_projectile + _spawn_impact_spark + _update_projectiles hook), tests/autotest_duelist.gd. Branch: save.class_id=="thief" → switch save.origin_id → aetherborn/ironblooded/miststalker. Non-thief untouched. |
| 3.3 | 3 | Vanguard VFX (Arcane Aegis shield / Juggernaut thrusters / Pack-Leader summon+stealth) | ✅ | Sonnet | each Vanguard cell signature VFX; ⚠ shield overdraw | autotest_vanguard: 3 PNGs fresh+non-blank (aegis=25.1KB, juggernaut=21.1KB, packleader=22.9KB); autotest_slice ALL_PASS; wilds_fps=315.8 (≥60, NO drop — VFX only on warrior rig, not in Wilds); test_core ALL_PASS. | Done. Files: character_rig.gd (_update_vanguard_vfx() called from _apply_build(), 5 node refs, freed on rebuild/non-warrior); tests/autotest_vanguard.gd. Cells: aetherborn=flat teal BoxMesh shield on left-arm+bob in _process; ironblooded=2×GPUParticles3D steam jets 22/arm at shoulder tops; miststalker=green wisp sphere orbiting head in _process + TorusMesh stealth ring at feet. Shield = 1 additive transparent surface (overdraw OK). |
| 3.4 | 3 | Strategist VFX (Chrono refraction / Thermite napalm AoE / Blood-Shaman heal+siphon) | ✅ | Sonnet | each Strategist cell signature VFX (screen-space refraction, decals, auras) | Eyeballed: Chrono teal refraction dome STRONG (bends bg horizon); Thermite embers+orange ring (per report); ⚠ Blood-Shaman rings/aura SUBTLE in static (live/polish). chrono_field.gdshader compiles clean; slice ALL_PASS; wilds_fps 322; test_core ALL_PASS | Done. Files: character_rig.gd (_update_strategist_vfx), rendering/chrono_field.gdshader, tests/autotest_strategist.gd |
| 3.5 | 3 | 9-sub-style legibility @3m + overdraw/fps gate | ✅ | Sonnet QA | renders all 9 at ~3m; distinguishable by silhouette+color, no UI; wilds_fps≥60 | GATE: classes_grid.png renders all 9, all-9 VFX overdraw CLEAN; orchestrator eyeball ~8/9 distinct. WEAK: ironblooded orange rim low-contrast at distance; miststalker warrior-vs-thief silhouette margin narrow. Strong cues = chrono dome/focus orbs/ground rings/teal+green rims. slice ALL_PASS; wilds_fps 314; test_core ALL_PASS | Done. tests/autotest_classes.gd. Polish candidates: stronger iron-at-distance signal; widen Vanguard↔Duelist silhouette gap |
| 3.6 | 3 | Sprint-3 legibility polish | ✅ | Sonnet | 5 fixes | Eyeballed grid: Blood-Shaman rings now PROMINENT (+siphon wisps), focus orbs accent-colored (teal/orange/green), Vanguard↔Duelist gap wider (arch_xz 1.30/0.80), blink subtler (flicker not pill), iron leather warmed (#6e3a1f). ⚠ Iron still weakest at distance (bare-skin body) → deeper art pass (more iron gear) later, not legibility tuning. slice ALL_PASS; wilds_fps 314; test_core ALL_PASS | Done. Files: character_rig.gd, player_controller.gd |
| 4.1 | 4 | Atmosphere layer: volumetric fog + far-only DOF | ✅ | Sonnet | volumetric fog + far-DOF; OBJECT shaders unchanged; threats sharp | Eyeballed: Wilds hazy at edges, near terrain crisp cel; God-Core SHARP + RED (danger by color, not blurred). vol_fog density 0.02/len 140; DOF far_distance 85/amount 0.08/near off. wilds_fps 333 (no cost); slice ALL_PASS; test_core ALL_PASS | Done. File: the_wilds.gd _build_environment |
| 4.2 | 4 | God-Core corruption hotspot (local red fog) | ✅ | Sonnet | danger reads RED; local red fog; never blurred | Red FogVolume (ellipsoid r16, albedo #ff1219, density 0.5, red emission) at each core. Cores stay sharp+vivid red. wilds_fps 353 (no regression). NOTE haze reads at player eye level; subtle in top-down autotest framing → 4.5 gate takes an eye-level render | Done. File: the_wilds.gd _build_core_site |
| 4.3 | 4 | Floating islands / verticality | ✅ | Sonnet | distant low-detail island meshes under fog (scale + verticality) | Eyeballed overview: 6 cel-shaded green-topped floating islands in the sky (y 38–72m, dist 130–185m), fog-veiled, add verticality/scale; near terrain stays crisp cel. wilds_fps 346 (no change); slice ALL_PASS; test_core ALL_PASS | Done. File: the_wilds.gd _build_floating_islands |
| 4.4 | 4 | Ambient spores/motes particles | ⬜ | Haiku | GPUParticles3D floating spores; cheap ambient life | — | (agent interrupted; redo after commit) drifting pale spore field across play area |
| 4.5 | 4 | Sprint 4 gate: two-layer + color legibility + fps | ⬜ | Sonnet QA | objects identical register; safe(blue/teal) vs danger(red) readable, no UI; threats unblurred; wilds_fps≥60 | — | Sprint 4 gate |
| 5 | 5 | Performance hardening + biome generalization | ⬜ | Sonnet+Haiku | overdraw audited; ≥1 extra biome, object register unchanged | — | Needs 2,3,4 |
| T1 | tool | Fix --skip=wilds (ignored in live boot) | ⬜ | Haiku | --skip works in live game | — | TOOLING DEBT (diagnosed): start() only goes to CREATION; --origin/--cls fast-path→OFFICE; `_apply_skip_arg()` is never called live. Fix: invoke _apply_skip_arg() after the fast-path reaches OFFICE (in start()/main.gd). Low priority |
| T2 | art | Ironblooded deeper gear/armor pass (at-distance read) | ⬜ | Sonnet | iron reads strong at 3m without rim/VFX | — | OPTIONAL art pass: add iron plating/pauldrons/greaves to the body (bare-skin default limits origin color) |

## Dependency order

`0.0/0.1 → 0.2,0.3,0.4,0.5 → (Sprint 1 ‖ Sprint 2) → Sprint 3 ; Sprint 4 ‖ 2/3 → Sprint 5`. QA runs continuously.

## Open risks

- ~~GDD §2 not yet supplied~~ → RESOLVED: received, encoded in `godot/data/substyles.json`.
- Overdraw from stacked transparencies (shields/auras/trails/volumetric/alpha foliage) — QA watches continuously; audited in Sprint 5.
- Console export needs external partner (Godot has no official console exporters) — production-planning item, out of sprint scope.
