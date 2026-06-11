// Quest tracker widget + the three-path Choice overlay + slice end card.

import { bus } from "../core/EventBus.js";
import { Sfx } from "../core/Sfx.js";

export class QuestUI {
  constructor(root) {
    this.tracker = document.createElement("div");
    this.tracker.className = "quest-tracker hidden";
    root.appendChild(this.tracker);

    this.choiceOverlay = document.createElement("div");
    this.choiceOverlay.id = "choice-overlay";
    root.appendChild(this.choiceOverlay);

    this.endCard = document.createElement("div");
    this.endCard.id = "end-card";
    root.appendChild(this.endCard);

    bus.on("quest:update", ({ tracker }) => this.render(tracker));
  }

  render(questTracker) {
    const q = questTracker.quest;
    if (!q) {
      this.tracker.classList.add("hidden");
      return;
    }
    this.tracker.classList.remove("hidden");
    const objectives = q.objectives
      .filter((o) => o.visible)
      .map((o) => {
        const count = o.total ? ` (${o.count}/${o.total})` : "";
        return `<div class="quest-obj${o.done ? " done" : ""}">${o.text}${count}</div>`;
      })
      .join("");
    this.tracker.innerHTML = `
      <div class="quest-title">${q.title}</div>
      ${objectives}
      <div class="quest-path"><b>⛨</b> ${q.pathLabel}</div>
    `;
  }

  // ---- the macro-freedom branch overlay ----
  showChoice(options, onPick) {
    this.choiceOverlay.innerHTML = `
      <div class="choice-heading">THE CONQUEROR'S CHOICE</div>
      <div class="choice-sub">The Core is ash and the contract is fulfilled — this time.
        But a mercenary's loyalty is a market, and three buyers are already bidding.
        How will you handle the purges to come?</div>
      <div class="choice-cards"></div>
    `;
    const cardsEl = this.choiceOverlay.querySelector(".choice-cards");
    for (const opt of options) {
      const card = document.createElement("button");
      card.className = "path-card";
      card.style.setProperty("--path-color", opt.color);
      card.innerHTML = `
        <div class="path-letter">${opt.letter}</div>
        <div class="path-name">${opt.name}</div>
        <div class="path-desc">${opt.desc}</div>
      `;
      card.addEventListener("click", () => {
        Sfx.choice();
        this.choiceOverlay.classList.remove("visible");
        onPick(opt.id);
      });
      cardsEl.appendChild(card);
    }
    this.choiceOverlay.classList.add("visible");
  }

  // ---- slice complete ----
  showEndCard(save, pathName, onContinue) {
    const minutes = Math.max(1, Math.round((Date.now() - save.startedAt) / 60000));
    this.endCard.innerHTML = `
      <div class="ec-title">CONTRACT: ACTIVE</div>
      <div class="ec-body">
        <b>${save.name}</b> of the ${save.origin.name} walks The Wilds under a signed
        Conqueror's Contract — and a private agenda: <b>${pathName}</b>.<br/><br/>
        The vertical slice ends here. The continent doesn't.
      </div>
      <div class="ec-stats">
        <div class="ec-stat"><b>${minutes}m</b> field time</div>
        <div class="ec-stat"><b>${save.kills}</b> maddened purged</div>
        <div class="ec-stat"><b>${save.coresPurged}</b> core shattered</div>
      </div>
      <button class="btn-primary">Keep Roaming The Wilds</button>
    `;
    this.endCard.querySelector("button").addEventListener("click", () => {
      Sfx.uiClick();
      this.endCard.classList.remove("visible");
      onContinue?.();
    });
    this.endCard.classList.add("visible");
  }
}
