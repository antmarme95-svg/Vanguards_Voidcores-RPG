// Origin passive abilities, attached to the player entity at spawn.
// Mana-Overload (aetherborn) · Colossus Stance (ironblooded) · Feral Instinct (miststalker)

import { bus } from "../core/EventBus.js";

export class Passives {
  constructor(save, stats) {
    this.originId = save.originId;
    this.stats = stats;
    this.overclockActive = false;   // aetherborn, held
    this.nightVision = false;       // miststalker, toggled

    if (this.originId === "ironblooded") {
      stats.physicalResist = 0.25; // Colossus Stance
    }
  }

  // --- Mana-Overload: hold to overclock casting, drains stamina ---
  setOverclock(held, dt) {
    if (this.originId !== "aetherborn") return;
    let active = false;
    if (held) active = this.stats.drainStamina(16, dt);
    if (active !== this.overclockActive) {
      this.overclockActive = active;
      bus.emit("passive:toggled", { active, id: "manaOverload" });
    }
  }

  castCooldownMult() {
    return this.overclockActive ? 0.45 : 1;
  }

  // --- Colossus Stance: faster heavy swings (resist handled in Stats) ---
  attackCooldownMult() {
    return this.originId === "ironblooded" ? 0.8 : 1;
  }

  // --- Feral Instinct ---
  grassSpeedMult(inGrass) {
    return this.originId === "miststalker" && inGrass ? 1.35 : 1;
  }

  detectionMult() {
    return this.originId === "miststalker" ? 0.55 : 1;
  }

  toggleNightVision() {
    if (this.originId !== "miststalker") return;
    this.nightVision = !this.nightVision;
    bus.emit("passive:toggled", { active: this.nightVision, id: "feralInstinct" });
  }
}
