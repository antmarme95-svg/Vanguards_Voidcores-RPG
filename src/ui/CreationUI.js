// Character creation split-screen: left = categorized tabs (Origin / Body /
// Face / Class), right = the live 3D viewport (canvas renders behind the UI).
// Generated entirely from the data tables — no hand-written slider markup.

import { ORIGINS } from "../data/origins.js";
import { CLASSES } from "../data/classes.js";
import { PHENOTYPE_FIELDS } from "../data/phenotype.js";
import { SKIN_TONES, HAIR_COLORS, PAINT_COLORS } from "../data/palette.js";
import { Sfx } from "../core/Sfx.js";

const PALETTES = { skin: SKIN_TONES, hair: HAIR_COLORS, paint: PAINT_COLORS };
const TABS = [
  { id: "origin", label: "Origin" },
  { id: "body", label: "Body" },
  { id: "face", label: "Face" },
  { id: "class", label: "Class" },
];

export class CreationUI {
  constructor({ root, save, onOriginSelect, onPhenotypeChange, onClassSelect, onConfirm, onTabChange, onOrbit }) {
    this.save = save;
    this.onOriginSelect = onOriginSelect;
    this.onPhenotypeChange = onPhenotypeChange;
    this.onClassSelect = onClassSelect;
    this.onConfirm = onConfirm;
    this.onTabChange = onTabChange;
    this._nameTouched = false;

    this.el = document.createElement("div");
    this.el.id = "creation-screen";
    this.el.innerHTML = `
      <div class="creation-left">
        <div class="creation-header">
          <div class="sub">Conqueror's Contract · Intake Form 7-C</div>
          <h1>FORGE YOUR MERCENARY</h1>
        </div>
        <div class="tab-rail"></div>
        <div class="tab-body"></div>
        <div class="creation-footer">
          <div class="name-row">
            <label>Name</label>
            <input id="char-name" maxlength="18" spellcheck="false" placeholder="Sign-in name…" />
          </div>
          <button class="btn-primary" id="btn-begin" disabled>Sign On</button>
        </div>
      </div>
      <div class="creation-right"></div>
      <div class="viewport-hint">drag viewport to rotate · live preview</div>
    `;
    root.appendChild(this.el);

    this.tabRail = this.el.querySelector(".tab-rail");
    this.tabBody = this.el.querySelector(".tab-body");
    this.nameInput = this.el.querySelector("#char-name");
    this.beginBtn = this.el.querySelector("#btn-begin");

    this.nameInput.addEventListener("input", () => {
      this._nameTouched = this.nameInput.value.trim().length > 0;
      this.save.name = this.nameInput.value.trim();
      this._refreshBegin();
    });
    this.beginBtn.addEventListener("click", () => {
      if (this.beginBtn.disabled) return;
      Sfx.uiClick();
      this.onConfirm?.(this.nameInput.value.trim());
    });

    // drag-to-rotate on the viewport half
    const right = this.el.querySelector(".creation-right");
    right.style.pointerEvents = "auto";
    let drag = null;
    right.addEventListener("mousedown", (e) => (drag = e.clientX));
    window.addEventListener("mousemove", (e) => {
      if (drag == null) return;
      onOrbit?.((e.clientX - drag) * 0.012);
      drag = e.clientX;
    });
    window.addEventListener("mouseup", () => (drag = null));

    for (const tab of TABS) {
      const btn = document.createElement("button");
      btn.className = "tab-btn";
      btn.dataset.tab = tab.id;
      btn.textContent = tab.label;
      btn.addEventListener("click", () => {
        Sfx.uiTab();
        this.onTabChange?.(tab.id);
      });
      this.tabRail.appendChild(btn);
    }

    this.showTab("origin");
  }

  // ------------------------------------------------------------------
  showTab(tabId) {
    this.activeTab = tabId;
    for (const btn of this.tabRail.children) {
      btn.classList.toggle("active", btn.dataset.tab === tabId);
    }
    this.tabBody.innerHTML = "";
    if (tabId === "origin") this._buildOriginTab();
    else if (tabId === "class") this._buildClassTab();
    else this._buildPhenotypeTab(tabId);
  }

  _section(label) {
    const s = document.createElement("div");
    s.className = "section-label";
    s.textContent = label;
    this.tabBody.appendChild(s);
  }

  _buildOriginTab() {
    this._section("Choose your lineage — it picks your kingdom, your passive, and your enemies");
    for (const origin of ORIGINS) {
      const card = document.createElement("button");
      card.className = "choice-card" + (this.save.originId === origin.id ? " selected" : "");
      card.innerHTML = `
        <div class="card-tag">${origin.tag}</div>
        <div class="card-name">${origin.name}</div>
        <div class="card-desc">${origin.lore}</div>
        <div class="card-passive"><b>${origin.passive.name}</b> — ${origin.passive.desc}</div>
        <div class="card-desc" style="margin-top:6px">⌂ <b style="color:var(--ink)">${origin.city.name}</b> · ${origin.city.desc}</div>
      `;
      card.addEventListener("click", () => {
        Sfx.uiClick();
        this.save.originId = origin.id;
        if (!this._nameTouched) {
          this.nameInput.value = origin.defaultName;
          this.save.name = origin.defaultName;
        }
        this.onOriginSelect?.(origin);
        this.showTab("origin");
        this._refreshBegin();
      });
      this.tabBody.appendChild(card);
    }
  }

  _buildClassTab() {
    this._section("Background training — attributes & skill bonuses");
    for (const cls of CLASSES) {
      const skills = Object.entries(cls.skillBonuses)
        .map(([s, b]) => `${s} +${b}`)
        .join(" · ");
      const card = document.createElement("button");
      card.className = "choice-card" + (this.save.classId === cls.id ? " selected" : "");
      card.innerHTML = `
        <div class="card-tag">${cls.tag}</div>
        <div class="card-name">${cls.name}</div>
        <div class="card-desc">${cls.desc}</div>
        <div class="stat-row">
          <span class="stat-chip">HP <b>${cls.attributes.health}</b></span>
          <span class="stat-chip">MP <b>${cls.attributes.magicka}</b></span>
          <span class="stat-chip">SP <b>${cls.attributes.stamina}</b></span>
        </div>
        <div class="card-passive" style="font-size:12px">${skills}</div>
      `;
      card.addEventListener("click", () => {
        Sfx.uiClick();
        this.save.classId = cls.id;
        this.onClassSelect?.(cls);
        this.showTab("class");
        this._refreshBegin();
      });
      this.tabBody.appendChild(card);
    }
  }

  _buildPhenotypeTab(tabId) {
    const fields = PHENOTYPE_FIELDS.filter((f) => f.tab === tabId);
    let currentSection = null;
    for (const field of fields) {
      if (field.section !== currentSection) {
        currentSection = field.section;
        this._section(currentSection);
      }
      if (field.kind === "float") this._buildSlider(field);
      else if (field.kind === "pick") this._buildPicker(field);
      else if (field.kind === "color") this._buildSwatches(field);
    }
  }

  _buildSlider(field) {
    const row = document.createElement("div");
    row.className = "slider-row";
    const value = this.save.phenotype[field.id] ?? field.default;
    row.innerHTML = `
      <label title="${field.hint ?? ""}">${field.label}</label>
      <input type="range" min="0" max="1" step="0.01" value="${value}" />
      <span class="val">${Math.round(value * 100)}</span>
    `;
    const input = row.querySelector("input");
    const val = row.querySelector(".val");
    const paint = () => input.style.setProperty("--fill", `${input.value * 100}%`);
    paint();
    input.addEventListener("input", () => {
      const v = parseFloat(input.value);
      val.textContent = Math.round(v * 100);
      paint();
      this.save.phenotype[field.id] = v;
      this.onPhenotypeChange?.(field.id, v);
    });
    this.tabBody.appendChild(row);
    if (field.hint) {
      const hint = document.createElement("div");
      hint.style.cssText = "font-size:11px;color:var(--ink-dim);margin:-7px 0 10px 2px;letter-spacing:0.05em";
      hint.textContent = field.hint;
      this.tabBody.appendChild(hint);
    }
  }

  _buildPicker(field) {
    const grid = document.createElement("div");
    grid.className = "pick-grid";
    field.options.forEach((name, i) => {
      const btn = document.createElement("button");
      btn.className = "pick-btn" + ((this.save.phenotype[field.id] ?? field.default) === i ? " selected" : "");
      btn.textContent = name;
      btn.title = `${field.label}: ${name}`;
      btn.addEventListener("click", () => {
        Sfx.uiClick();
        this.save.phenotype[field.id] = i;
        this.onPhenotypeChange?.(field.id, i);
        for (const b of grid.children) b.classList.remove("selected");
        btn.classList.add("selected");
      });
      grid.appendChild(btn);
    });
    this.tabBody.appendChild(grid);
    const spacer = document.createElement("div");
    spacer.style.height = "10px";
    this.tabBody.appendChild(spacer);
  }

  _buildSwatches(field) {
    const grid = document.createElement("div");
    grid.className = "swatch-grid";
    const palette = PALETTES[field.paletteKey] ?? [];
    palette.forEach((hex, i) => {
      const sw = document.createElement("button");
      sw.className = "swatch" + ((this.save.phenotype[field.id] ?? field.default) === i ? " selected" : "");
      sw.style.background = hex;
      sw.title = `${field.label}`;
      sw.addEventListener("click", () => {
        Sfx.uiClick();
        this.save.phenotype[field.id] = i;
        this.onPhenotypeChange?.(field.id, i);
        for (const b of grid.children) b.classList.remove("selected");
        sw.classList.add("selected");
      });
      grid.appendChild(sw);
    });
    this.tabBody.appendChild(grid);
  }

  _refreshBegin() {
    const ready = this.save.originId && this.save.classId && this.save.name.trim().length > 0;
    this.beginBtn.disabled = !ready;
    this.beginBtn.textContent = ready
      ? "Sign On — Deploy to " + (this.save.origin?.city.name ?? "")
      : "Select Origin · Look · Class";
  }

  setAccent(hex) {
    document.documentElement.style.setProperty("--accent", hex);
    document.documentElement.style.setProperty("--accent-dim", hex + "2e");
  }

  hide() {
    this.el.classList.add("hidden");
  }

  show() {
    this.el.classList.remove("hidden");
  }
}
