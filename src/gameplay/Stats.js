// Runtime vitals: health / magicka / stamina pools with BotW-style stamina
// exhaustion. Pure logic — no engine imports.

import { bus } from "../core/EventBus.js";

export class Stats {
  constructor(save) {
    const attrs = save.computeAttributes();
    this.maxHealth = attrs.health;
    this.maxMagicka = attrs.magicka;
    this.maxStamina = attrs.stamina;
    this.health = this.maxHealth;
    this.magicka = this.maxMagicka;
    this.stamina = this.maxStamina;

    this.skills = save.computeSkills();

    this.staminaRegen = 26;
    this.magickaRegen = 9;
    this.healthRegen = 1.5;
    this.exhausted = false;       // drained to zero → locked out of sprint until refilled
    this._regenHold = 0;          // brief pause after spending stamina
    this.physicalResist = 0;      // set by passives (Colossus Stance)
  }

  skillBonus(skillName, perPoint = 0.02) {
    const v = this.skills[skillName] ?? 15;
    return 1 + (v - 15) * perPoint;
  }

  spendStamina(amount) {
    if (this.exhausted) return false;
    this.stamina -= amount;
    this._regenHold = 0.6;
    if (this.stamina <= 0) {
      this.stamina = 0;
      this.exhausted = true;
    }
    return true;
  }

  drainStamina(perSecond, dt) {
    if (this.exhausted) return false;
    this.stamina -= perSecond * dt;
    this._regenHold = 0.4;
    if (this.stamina <= 0) {
      this.stamina = 0;
      this.exhausted = true;
      return false;
    }
    return true;
  }

  spendMagicka(amount) {
    if (this.magicka < amount) return false;
    this.magicka -= amount;
    return true;
  }

  takeDamage(amount, { physical = true } = {}) {
    const final = physical ? amount * (1 - this.physicalResist) : amount;
    this.health = Math.max(0, this.health - final);
    bus.emit("combat:playerHit", { amount: final });
    if (this.health <= 0) bus.emit("player:died");
    return final;
  }

  heal(amount) {
    this.health = Math.min(this.maxHealth, this.health + amount);
  }

  update(dt) {
    this._regenHold = Math.max(0, this._regenHold - dt);
    if (this._regenHold <= 0) {
      this.stamina = Math.min(this.maxStamina, this.stamina + this.staminaRegen * dt);
      if (this.exhausted && this.stamina >= this.maxStamina * 0.35) this.exhausted = false;
    }
    this.magicka = Math.min(this.maxMagicka, this.magicka + this.magickaRegen * dt);
    this.health = Math.min(this.maxHealth, this.health + this.healthRegen * dt);
  }
}
