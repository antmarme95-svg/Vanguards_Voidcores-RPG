// The unified player record assembled during character creation and carried
// through the slice. Pure data — no engine imports.

import { ORIGINS } from "../data/origins.js";
import { CLASSES, BASE_ATTRIBUTE, BASE_SKILL, SKILL_LIST } from "../data/classes.js";
import { defaultPhenotype } from "../data/phenotype.js";

export class SaveState {
  constructor() {
    this.name = "";
    this.originId = null;
    this.classId = null;
    this.phenotype = defaultPhenotype();
    this.chosenPath = null; // "kingdom" | "betrayal" | "rogue"
    this.kills = 0;
    this.coresPurged = 0;
    this.startedAt = Date.now();
  }

  get origin() {
    return ORIGINS.find((o) => o.id === this.originId) ?? null;
  }

  get charClass() {
    return CLASSES.find((c) => c.id === this.classId) ?? null;
  }

  // Final attribute pools: class table + origin passive modifiers.
  computeAttributes() {
    const cls = this.charClass;
    const attrs = cls
      ? { ...cls.attributes }
      : { health: BASE_ATTRIBUTE, magicka: BASE_ATTRIBUTE, stamina: BASE_ATTRIBUTE };
    const origin = this.origin;
    if (origin?.passive?.attributeMods) {
      for (const [k, v] of Object.entries(origin.passive.attributeMods)) {
        attrs[k] = (attrs[k] ?? BASE_ATTRIBUTE) + v;
      }
    }
    return attrs;
  }

  // Skills: every skill at 15, class bonuses applied on top.
  computeSkills() {
    const skills = {};
    for (const s of SKILL_LIST) skills[s] = BASE_SKILL;
    const cls = this.charClass;
    if (cls) {
      for (const [skill, bonus] of Object.entries(cls.skillBonuses)) {
        skills[skill] = BASE_SKILL + bonus;
      }
    }
    return skills;
  }

  isCreationComplete() {
    return Boolean(this.originId && this.classId && this.name.trim().length > 0);
  }

  persist() {
    try {
      localStorage.setItem(
        "borisawa.save",
        JSON.stringify({
          name: this.name,
          originId: this.originId,
          classId: this.classId,
          phenotype: this.phenotype,
          chosenPath: this.chosenPath,
          kills: this.kills,
          coresPurged: this.coresPurged,
        })
      );
    } catch {
      /* storage unavailable (private mode) — slice still playable */
    }
  }
}
