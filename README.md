# BORISAWA — Aetherpunk High-Fantasy ARPG (Vertical Slice Prototype)

An original open-world Action RPG prototype: **Vox Machina** irreverence ×
**Breath of the Wild** cel-shaded exploration. You are not a chosen one — you
are a mercenary with a freshly signed **Conqueror's Contract** and three bad
ideas about loyalty.

The slice delivers: full **character creation** (Origin Factions → live
phenotype editor → Class) and a playable **~10-minute narrative arc**
(Contract Signing → frontier deployment → The Wilds → a Core of the Dead Gods
encounter → the three-path Conqueror's Choice).

---

## ▶ How to run (zero installs)

**Double-click `Start-Game.bat`.**

That launches `tools/serve.ps1` — a dependency-free PowerShell static server
on `http://localhost:8420` — and opens your browser. Three.js loads from a
pinned CDN; everything else (3D models, textures, audio) is generated
procedurally at runtime. Internet is required on first load for the CDN.

> ES modules can't load over `file://`, which is the only reason a local
> server exists at all.

### Controls

| Input | Action |
|---|---|
| WASD / arrows | Move |
| Shift (hold) | Sprint — drains the stamina wheel |
| Space | Jump |
| Mouse drag | Orbit camera · wheel zooms |
| Click / F | Attack (class-flavored: greatblade / bolt / bow) |
| C | Crouch / sneak |
| E | Interact (talk · sign · shatter) |
| Q (hold) | **Mana-Overload** (Aether-Born passive) |
| N | **Night-vision** (Mist-Stalker passive) |

### Debug fast-forward (for testing)

`?origin=aetherborn|ironblooded|miststalker&cls=warrior|mage|thief&name=X&skip=office|exit|wilds`

e.g. `http://localhost:8420/?origin=miststalker&cls=thief&skip=wilds`
`window.__BORISAWA` exposes `{ director, bus, THREE }` in the console.

---

## Architecture

```
src/
├── main.js                  boot, render loop, debug hooks
├── core/                    ENGINE-AGNOSTIC (no three.js imports)
│   ├── StateMachine.js      generic FSM
│   ├── GameDirector.js      top FSM: CREATION → OFFICE → CITY_EXIT → WILDS → CHOICE → FREE_ROAM
│   │                        + nested CharacterCreationState FSM (origin/body/face/class)
│   ├── EventBus.js          pub/sub: creation:complete, contract:signed, core:destroyed…
│   ├── SaveState.js         unified player record (origin, class, phenotype, path)
│   └── Sfx.js               zero-asset WebAudio synth
├── data/                    PURE DATA — ports to Godot Resources verbatim
│   ├── origins.js           3 factions: passives, cities, rivals, scene themes
│   ├── classes.js           Warrior/Mage/Thief attribute + skill tables
│   ├── phenotype.js         slider/pick definitions (single source of truth for UI + rig)
│   ├── palette.js           neon-adjacent cel palettes
│   └── dialogue/contract.js recruiter dialogue trees + contract clauses
├── character/
│   ├── CharacterRig.js      parametric humanoid; applyPhenotype() live-edits transforms,
│   │                        materials, hair/beard swaps, mana veins, prosthetics
│   ├── HairLibrary.js       10 procedural anime hairstyles + 4 beards
│   └── WarpaintAtlas.js     canvas-generated cel warpaint head textures
├── rendering/
│   ├── ToonMaterials.js     shared stepped-ramp MeshToonMaterial factory + wind sway
│   └── OutlinePass.js       inverted-hull outlines (inherit phenotype scaling)
├── scenes/                  each: { scene, playerSpawn, getHeight, clampPosition,
│   │                                interactables, triggers, update }
│   ├── props.js             shared prop kit (pipes, lamps, banners, gears, ribs, trees)
│   ├── CreationStage.js     turntable viewport, origin-retinted 3-point lighting
│   ├── RecruitmentOffice.js one interior kit, three kingdom themes
│   ├── CityExit.js          guarded street + rising frontier gate
│   └── TheWilds.js          analytic terrain, instanced wind grass, the red Core site
├── gameplay/
│   ├── PlayerController.js  3rd-person movement, stamina sprint/jump, attacks, projectiles
│   ├── Stats.js             health/magicka/stamina pools, BotW exhaustion, skill bonuses
│   ├── Passives.js          Mana-Overload / Colossus Stance / Feral Instinct
│   ├── EnemyAI.js           Maddened Gloomfang FSM: roam→chase→windup→lunge→recover
│   └── QuestTracker.js      objectives + the Path A/B/C macro-freedom branch
└── ui/
    ├── CreationUI.js        split layout: left tab rail (Origin/Body/Face/Class), right viewport
    ├── HUD.js               compass bar, vitals, stamina wheel, prompts, hit FX
    ├── DialogueUI.js        letterboxed dialogue + hold-to-sign contract parchment
    └── QuestUI.js           tracker widget, Choice overlay, end card
```

### Flow of the slice

1. **CREATION** — nested FSM drives the four tabs; every slider tick calls
   `CharacterRig.applyPhenotype()` so the model updates the same frame.
   "Sign On" freezes the `SaveState` and emits `creation:complete`.
2. **OFFICE** — the director reads `SelectedOrigin` and spawns the matching
   themed Recruitment Office; `Stats` + `Passives` attach the origin passive
   to the player entity. Talk to the recruiter, read the Conqueror's
   Contract, hold-to-sign → `contract:signed` → the doors slide open.
3. **CITY_EXIT** — walk the last secure street; the frontier portcullis
   rises; crossing the boundary fades into…
4. **WILDS** — quest *PURGE ORDER 001* activates. A red **Core of the Dead
   Gods** pulses on the compass; three maddened beasts (red crystal
   corruption, stealth-aware aggro) guard it. Purge them, shatter the Core.
5. **CHOICE** — the tracker branches: **Path A** serve your kingdom ·
   **Path B** court the rival power · **Path C** go rogue. The pick rewrites
   the quest tracker and the save record, then free roam + end card.

---

## Godot 4 migration map (the planned final destination)

The port boundary is enforced by the import graph: `core/`, `data/`, and
`gameplay/QuestTracker|Stats|Passives` have **no three.js imports**.

| Here | In Godot 4 |
|---|---|
| `data/*.js` tables | `Resource` scripts (.tres) |
| `EventBus` | autoload singleton with signals |
| `StateMachine` / `GameDirector` | node-based FSM (or `LimboHSM`) |
| `SaveState` | `Resource` + `FileAccess` JSON |
| scene classes | `.tscn` scenes; `getHeight` → `HeightMapShape3D`/raycast |
| `ToonMaterials` ramp | one toon `.gdshader` (stepped ramp + rim) |
| `OutlinePass` inverted hull | second material pass, `cull_front` grow shader |
| `CharacterRig` primitives | rigged mesh + blendshapes; sliders → blendshape weights |
| `PlayerController` | `CharacterBody3D` + spring-arm camera |
| DOM UI | `Control` nodes; compass = scrolling `TextureRect` |
| `Sfx` synth | `AudioStreamGenerator` or baked .wav |

## Known prototype cut-lines

- Recruitment Offices share one interior kit (data-themed), not full cities.
- Skills are stored/displayed; combat hooks use the key skill per class
  (+ Sneak affecting detection). The rest is progression scaffolding.
- Persistence = `localStorage` snapshot only.
- No save/load menu, no map screen, no inventory — out of slice scope.
