// Top-level game orchestration.
//
//   GameDirector FSM:  CREATION → OFFICE → CITY_EXIT → WILDS → CHOICE → FREE_ROAM
//   Nested FSM:        CharacterCreationState: ORIGIN → BODY → FACE → CLASS
//
// The director owns the SaveState, swaps scenes on origin-conditional spawn
// logic, and wires gameplay systems to UI through the EventBus.

import * as THREE from "three";
import { StateMachine } from "./StateMachine.js";
import { SaveState } from "./SaveState.js";
import { bus } from "./EventBus.js";
import { Sfx } from "./Sfx.js";

import { CharacterRig } from "../character/CharacterRig.js";
import { CreationStage } from "../scenes/CreationStage.js";
import { RecruitmentOffice } from "../scenes/RecruitmentOffice.js";
import { CityExit } from "../scenes/CityExit.js";
import { TheWilds } from "../scenes/TheWilds.js";

import { Stats } from "../gameplay/Stats.js";
import { Passives } from "../gameplay/Passives.js";
import { PlayerController } from "../gameplay/PlayerController.js";
import { MaddenedBeast } from "../gameplay/EnemyAI.js";
import { QuestTracker } from "../gameplay/QuestTracker.js";

import { CreationUI } from "../ui/CreationUI.js";
import { HUD } from "../ui/HUD.js";
import { DialogueUI } from "../ui/DialogueUI.js";
import { QuestUI } from "../ui/QuestUI.js";

import { buildRecruiterDialogue } from "../data/dialogue/contract.js";

export class GameDirector {
  constructor({ renderer, camera, uiRoot }) {
    this.renderer = renderer;
    this.camera = camera;
    this.uiRoot = uiRoot;

    this.save = new SaveState();
    this.scene = null;          // active gameplay scene wrapper
    this.enemies = [];
    this.orbitDelta = 0;
    this.turntable = 0;
    this._timers = [];          // dt-driven scheduler (immune to tab throttling)

    // ---- player rig (shared between creation viewport and gameplay) ----
    this.rig = new CharacterRig({});
    this.rig.applyPhenotype(this.save.phenotype, null);

    // ---- UI ----
    this.hud = new HUD(uiRoot);
    this.questUI = new QuestUI(uiRoot);
    this.dialogueUI = new DialogueUI(uiRoot);
    this.questTracker = new QuestTracker(this.save);

    this.fadeLayer = document.createElement("div");
    this.fadeLayer.id = "fade-layer";
    document.body.appendChild(this.fadeLayer);

    this.titleCard = document.createElement("div");
    this.titleCard.id = "title-card";
    this.titleCard.innerHTML = `<div class="tc-main"></div><div class="tc-sub"></div>`;
    uiRoot.appendChild(this.titleCard);

    // ---- nested creation FSM (the spec's CharacterCreationState) ----
    this.creationFsm = new StateMachine("creation", this);
    for (const tab of ["origin", "body", "face", "class"]) {
      this.creationFsm.add(tab, { enter: () => this.creationUI?.showTab(tab) });
    }

    // ---- top-level FSM ----
    this.fsm = new StateMachine("game", this);
    this.fsm
      .add("CREATION", this._stateCreation())
      .add("OFFICE", this._stateOffice())
      .add("CITY_EXIT", this._stateCityExit())
      .add("WILDS", this._stateWilds())
      .add("CHOICE", this._stateChoice())
      .add("FREE_ROAM", this._stateFreeRoam());

    this._wireGlobalEvents();
    this._bindInteractKey();
  }

  start() {
    this.fsm.go("CREATION");
  }

  // ==================================================================
  // CREATION
  // ==================================================================
  _stateCreation() {
    return {
      enter: () => {
        this.stage = new CreationStage();
        this.stage.scene.add(this.rig.group);
        this.rig.group.position.set(0, 0.18, 0);
        this.rig.group.rotation.y = 0.25;

        this.creationUI = new CreationUI({
          root: this.uiRoot,
          save: this.save,
          onTabChange: (tab) => this.creationFsm.go(tab),
          onOriginSelect: (origin) => {
            this.stage.setTheme(origin);
            this.creationUI.setAccent(origin.theme.accent);
            this.rig.applyPhenotype(this.save.phenotype, origin);
          },
          onPhenotypeChange: () => {
            this.rig.applyPhenotype(this.save.phenotype, this.save.origin);
          },
          onClassSelect: () => {},
          onOrbit: (dx) => (this.orbitDelta += dx),
          onConfirm: () => {
            this.save.persist();
            bus.emit("creation:complete", { save: this.save });
            this.transition(() => this.fsm.go("OFFICE"));
          },
        });
        this.creationFsm.go("origin");
      },
      update: (ctx, dt) => {
        this.stage.update(dt);
        this.rig.setMotion({ speed: 0 });
        this.rig.update(dt);
        // slow turntable + drag offset
        this.turntable += dt * 0.22 + this.orbitDelta;
        this.orbitDelta = 0;
        this.rig.group.rotation.y = 0.25 + this.turntable;
        this.camera.position.copy(this.stage.cameraPos);
        this.camera.lookAt(this.stage.cameraTarget);
      },
      exit: () => {
        this.creationUI.hide();
        this.stage.scene.remove(this.rig.group);
        this.rig.group.rotation.y = 0;
      },
    };
  }

  // ==================================================================
  // OFFICE — conditional spawn by SelectedOrigin + contract sequence
  // ==================================================================
  _stateOffice() {
    return {
      enter: () => {
        const origin = this.save.origin;

        // build the player entity: stats + origin passive applied here
        this.stats = new Stats(this.save);
        this.passives = new Passives(this.save, this.stats);
        this.controller = new PlayerController({
          rig: this.rig,
          camera: this.camera,
          stats: this.stats,
          passives: this.passives,
          save: this.save,
          dom: this.renderer.domElement,
        });

        this.scene = new RecruitmentOffice(origin);
        this.controller.setScene(this.scene);
        this.controller.enabled = true;

        this.hud.show();
        this.hud.setPassive(origin);
        this.showTitle(origin.city.name, `Recruitment Office — ${origin.recruiter.title}`);
        bus.emit("quest:toast", { text: `Speak with ${origin.recruiter.name}` });
      },
      update: (ctx, dt) => this._gameplayUpdate(dt),
    };
  }

  _startRecruiterDialogue() {
    const origin = this.save.origin;
    this.controller.enabled = false;
    this.hud.hidePrompt();
    const tree = buildRecruiterDialogue(origin, this.save.name);
    this.dialogueUI.start(tree, {
      onAction: (action) => {
        if (action === "openContract") {
          this.dialogueUI.openContract(origin, this.save.name, () => {
            // signed!
            this.save.persist();
            bus.emit("contract:signed", { origin });
            this.scene.setDoorsOpen(true);
            Sfx.doors();
            const recruiter = this.scene.interactables.find((i) => i.id === "recruiter");
            if (recruiter) recruiter.enabled = false;
            this.dialogueUI.jumpTo("signed");
          });
        } else if (action === "end") {
          this.dialogueUI.close();
          this.controller.enabled = true;
          bus.emit("quest:toast", { text: "The doors are open — deploy to The Wilds" });
        }
      },
    });
  }

  // ==================================================================
  // CITY EXIT
  // ==================================================================
  _stateCityExit() {
    return {
      enter: () => {
        const origin = this.save.origin;
        this.scene = new CityExit(origin);
        this.controller.setScene(this.scene);
        this.controller.enabled = true;
        this.showTitle("THE LAST SECURE STREET", `${origin.city.name} frontier gate`);
      },
      update: (ctx, dt) => {
        this._gameplayUpdate(dt);
        const trigger = this.controller.checkTriggers();
        if (trigger?.id === "toWilds") {
          this.transition(() => this.fsm.go("WILDS"));
        }
      },
    };
  }

  // ==================================================================
  // WILDS — encounter + core purge
  // ==================================================================
  _stateWilds() {
    return {
      enter: () => {
        const origin = this.save.origin;
        this.scene = new TheWilds(origin);
        this.controller.setScene(this.scene);
        this.controller.enabled = true;

        this.enemies = this.scene.enemySpawns.map((p) => new MaddenedBeast(p, this.scene));
        this.controller.enemies = this.enemies;

        this.questTracker.activate(origin);
        this.hud.setMarkers([
          { id: "core", icon: "▼", color: "#ff4d5e", worldPos: this.scene.corePosition },
        ]);
        this.showTitle("THE WILDS", "untamed frontier — Core resonance detected");
      },
      update: (ctx, dt) => {
        this._gameplayUpdate(dt);

        const trigger = this.controller.checkTriggers();
        if (trigger?.id === "coreSight") {
          this.questTracker.reachCoreSite();
        } else if (trigger?.id === "encounterStart") {
          for (const e of this.enemies) e.aggro = true;
          bus.emit("quest:toast", { text: "The maddened have your scent" });
        }
      },
    };
  }

  _onCoreShattered() {
    Sfx.coreShatter();
    this.scene.destroyCore();
    this.questTracker.coreDestroyed();
    this.hud.setMarkers([]);
    this.schedule(1.7, () => this.fsm.go("CHOICE"));
  }

  // ==================================================================
  // CHOICE — the macro-freedom branch
  // ==================================================================
  _stateChoice() {
    return {
      enter: () => {
        this.controller.enabled = false;
        const origin = this.save.origin;
        this.questUI.showChoice(this.questTracker.pathOptions(origin), (pathId) => {
          this.questTracker.choosePath(pathId, origin);
          this.fsm.go("FREE_ROAM");
        });
      },
      update: (ctx, dt) => this._gameplayUpdate(dt),
    };
  }

  _stateFreeRoam() {
    return {
      enter: () => {
        const pathNames = {
          kingdom: `the loyal blade of ${this.save.origin.city.name}`,
          betrayal: `a double agent for ${this.save.origin.rival}`,
          rogue: "an unbound mercenary power",
        };
        this.questUI.showEndCard(this.save, pathNames[this.save.chosenPath], () => {
          this.controller.enabled = true;
        });
      },
      update: (ctx, dt) => this._gameplayUpdate(dt),
    };
  }

  // ==================================================================
  // shared gameplay frame
  // ==================================================================
  _gameplayUpdate(dt) {
    this.scene.update(dt, this.controller.position);
    this.controller.update(dt);

    for (const enemy of this.enemies) {
      if (!enemy.dead) enemy.update(dt, { controller: this.controller, passives: this.passives });
    }

    // interact prompt
    if (this.controller.enabled && !this.dialogueUI.isOpen()) {
      const it = this.controller.nearestInteractable();
      if (it) this.hud.showPrompt(it.label);
      else this.hud.hidePrompt();
    } else {
      this.hud.hidePrompt();
    }

    this.hud.update(dt, {
      stats: this.stats,
      camYaw: this.controller.camYaw,
      playerPos: this.controller.position,
    });
  }

  _bindInteractKey() {
    window.addEventListener("keydown", (e) => {
      if (e.code !== "KeyE") return;
      if (!this.controller?.enabled || this.dialogueUI.isOpen()) return;
      const it = this.controller.nearestInteractable();
      if (!it) return;
      Sfx.uiClick();
      if (it.id === "recruiter") this._startRecruiterDialogue();
      else if (it.id === "exitDoors") this.transition(() => this.fsm.go("CITY_EXIT"));
      else if (it.id === "core") this._onCoreShattered();
    });
  }

  _wireGlobalEvents() {
    bus.on("combat:enemyDown", () => {
      this.questTracker.enemyDown();
      const alive = this.enemies.filter((e) => !e.dead && e.state !== "dying").length;
      if (alive === 0 && this.scene?.setCoreInteractable) {
        this.scene.setCoreInteractable(true);
        bus.emit("quest:toast", { text: "The Core is exposed — shatter it" });
      }
    });

    bus.on("player:died", () => {
      this.transition(() => {
        this.stats.health = this.stats.maxHealth;
        this.stats.stamina = this.stats.maxStamina;
        this.controller.position.copy(this.scene.playerSpawn.position);
        bus.emit("quest:toast", { text: "Clause V: death verified once. Resurrection invoiced." });
      });
    });
  }

  // ==================================================================
  // helpers
  // ==================================================================
  schedule(delaySeconds, fn) {
    this._timers.push({ t: delaySeconds, fn });
  }

  transition(midpoint) {
    this.fadeLayer.classList.add("dark");
    this.schedule(0.75, () => {
      midpoint?.();
      this.schedule(0.15, () => this.fadeLayer.classList.remove("dark"));
    });
  }

  showTitle(main, sub) {
    this.titleCard.querySelector(".tc-main").textContent = main;
    this.titleCard.querySelector(".tc-sub").textContent = sub;
    this.titleCard.classList.add("visible");
    clearTimeout(this._titleTimer);
    this._titleTimer = setTimeout(() => this.titleCard.classList.remove("visible"), 3000);
  }

  activeThreeScene() {
    if (this.fsm.is("CREATION")) return this.stage?.scene ?? null;
    return this.scene?.scene ?? null;
  }

  update(dt) {
    if (this._timers.length) {
      const due = [];
      for (const timer of this._timers) {
        timer.t -= dt;
        if (timer.t <= 0) due.push(timer);
      }
      this._timers = this._timers.filter((t) => t.t > 0);
      for (const timer of due) timer.fn();
    }
    this.fsm.update(dt);
  }
}
