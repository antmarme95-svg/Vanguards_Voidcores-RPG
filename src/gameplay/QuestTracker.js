// Quest model + the three-path macro-freedom branch. Pure logic; the HUD's
// QuestUI renders whatever this emits on "quest:update".

import { bus } from "../core/EventBus.js";

export class QuestTracker {
  constructor(save) {
    this.save = save;
    this.quest = null;
  }

  _emit() {
    bus.emit("quest:update", { tracker: this });
  }

  activate(origin) {
    this.quest = {
      id: "purge001",
      title: "PURGE ORDER 001",
      pathLabel: `Under contract — ${origin.city.name}`,
      objectives: [
        { id: "reach", text: "Investigate the crimson resonance", done: false, visible: true },
        { id: "purge", text: "Put down the maddened beasts", count: 0, total: 3, done: false, visible: false },
        { id: "shatter", text: "Shatter the Core of the Dead God", done: false, visible: false },
      ],
    };
    bus.emit("quest:toast", { text: "Purge Order 001 — received" });
    this._emit();
  }

  _obj(id) {
    return this.quest?.objectives.find((o) => o.id === id);
  }

  reachCoreSite() {
    const o = this._obj("reach");
    if (!o || o.done) return;
    o.done = true;
    const purge = this._obj("purge");
    purge.visible = true;
    bus.emit("quest:toast", { text: "Core resonance located" });
    this._emit();
  }

  enemyDown() {
    const o = this._obj("purge");
    if (!o || o.done) return;
    o.count = Math.min(o.total, o.count + 1);
    this.save.kills += 1;
    if (o.count >= o.total) {
      o.done = true;
      const shatter = this._obj("shatter");
      shatter.visible = true;
      bus.emit("quest:toast", { text: "The maddened are silent" });
    }
    this._emit();
  }

  coreDestroyed() {
    const o = this._obj("shatter");
    if (!o || o.done) return;
    o.done = true;
    this.save.coresPurged += 1;
    this._emit();
  }

  // ---- the macro-freedom branch ----
  pathOptions(origin) {
    return [
      {
        id: "kingdom",
        letter: "PATH A — THE LOYAL BLADE",
        name: `Serve ${origin.city.name}`,
        color: origin.theme.accent,
        desc: `Fulfill the contract as written. Purge the Cores for the crown, bank the bounty, keep your name clean. The pay is steady. The leash is short.`,
      },
      {
        id: "betrayal",
        letter: "PATH B — THE DOUBLE CONTRACT",
        name: `Court ${origin.rival}`,
        color: "#ffc94d",
        desc: `Keep the badge, sell the map. ${origin.rival} pays triple for Core locations — and even more for your silence. Nobody needs to know. Yet.`,
      },
      {
        id: "rogue",
        letter: "PATH C — THE UNBOUND",
        name: "Answer to no crown",
        color: "#ff4d5e",
        desc: `Tear up the fine print. The Cores answer to whoever holds them — why not you? Every kingdom on the continent will come for your head. Let them queue.`,
      },
    ];
  }

  choosePath(pathId, origin) {
    this.save.chosenPath = pathId;
    this.save.persist();
    const titles = {
      kingdom: { title: "THE LOYAL BLADE", path: `Sworn — for now — to ${origin.city.name}`, obj: `Purge the frontier Cores in the Crown's name` },
      betrayal: { title: "THE DOUBLE CONTRACT", path: `Quietly treating with ${origin.rival}`, obj: `Map the Cores… and leak the map` },
      rogue: { title: "THE UNBOUND", path: "Independent mercenary entity", obj: "Claim the Cores for no crown but your own" },
    };
    const t = titles[pathId];
    this.quest = {
      id: "campaign",
      title: t.title,
      pathLabel: t.path,
      objectives: [
        { id: "next", text: t.obj, done: false, visible: true },
        { id: "roam", text: "Vertical slice complete — roam The Wilds", done: false, visible: true },
      ],
    };
    bus.emit("path:chosen", { path: pathId });
    this._emit();
  }
}
