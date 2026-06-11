// BotW-inspired HUD: compass bar (top center), health/magicka bars,
// stamina wheel near the player, passive chip, interact prompt, hit FX.

import { bus } from "../core/EventBus.js";

const COMPASS_LABELS = [
  { deg: 0, txt: "N", cls: "cardinal-n" }, { deg: 45, txt: "NE" },
  { deg: 90, txt: "E" }, { deg: 135, txt: "SE" }, { deg: 180, txt: "S" },
  { deg: 225, txt: "SW" }, { deg: 270, txt: "W" }, { deg: 315, txt: "NW" },
];
const PX_PER_DEG = 3.4;
const WHEEL_R = 30;
const WHEEL_C = 2 * Math.PI * WHEEL_R;

const wrapDeg = (d) => ((d + 180) % 360 + 360) % 360 - 180;

export class HUD {
  constructor(root) {
    this.el = document.createElement("div");
    this.el.id = "hud";
    this.el.classList.add("hidden");
    this.el.innerHTML = `
      <div class="compass-wrap"><div class="compass-strip"></div><div class="compass-needle"></div></div>
      <div class="vitals">
        <div class="vital-bar"><div class="bar-label">Health</div>
          <div class="bar-track"><div class="bar-fill health"></div></div></div>
        <div class="vital-bar"><div class="bar-label">Magicka</div>
          <div class="bar-track"><div class="bar-fill magicka"></div></div></div>
      </div>
      <div class="stamina-wheel">
        <svg viewBox="0 0 74 74">
          <circle class="wheel-bg" cx="37" cy="37" r="${WHEEL_R}"></circle>
          <circle class="wheel-fill" cx="37" cy="37" r="${WHEEL_R}"
            stroke-dasharray="${WHEEL_C}" stroke-dashoffset="0"></circle>
        </svg>
      </div>
      <div class="passive-chip"><span class="key"></span><span class="passive-name"></span></div>
      <div class="interact-prompt"><span class="key">E</span><span class="interact-label"></span></div>
      <div class="controls-help">
        <b>WASD</b> move · <b>Shift</b> sprint · <b>Space</b> jump<br/>
        <b>Click/F</b> attack · <b>C</b> crouch · <b>E</b> interact · <b>drag</b> camera
      </div>
      <div id="fx-nightvision"></div>
      <div id="fx-vignette"></div>
    `;
    root.appendChild(this.el);

    this.strip = this.el.querySelector(".compass-strip");
    this.healthFill = this.el.querySelector(".bar-fill.health");
    this.magickaFill = this.el.querySelector(".bar-fill.magicka");
    this.wheel = this.el.querySelector(".stamina-wheel");
    this.wheelFill = this.el.querySelector(".wheel-fill");
    this.passiveChip = this.el.querySelector(".passive-chip");
    this.prompt = this.el.querySelector(".interact-prompt");
    this.promptLabel = this.el.querySelector(".interact-label");
    this.vignette = this.el.querySelector("#fx-vignette");
    this.nightvision = this.el.querySelector("#fx-nightvision");

    this._buildCompass();
    this.markers = []; // { id, icon, worldPos | bearingDeg }
    this._hitFlash = 0;

    // toast
    this.toast = document.createElement("div");
    this.toast.id = "toast";
    root.appendChild(this.toast);
    this._toastTimer = null;
    bus.on("quest:toast", ({ text }) => this.showToast(text));

    bus.on("combat:playerHit", () => (this._hitFlash = 1));
    bus.on("passive:toggled", ({ active, id }) => {
      this.passiveChip.classList.toggle("active", active);
      if (id === "feralInstinct") this.nightvision.style.opacity = active ? 1 : 0;
    });
  }

  _buildCompass() {
    this.compassItems = [];
    for (let deg = 0; deg < 360; deg += 15) {
      const label = COMPASS_LABELS.find((l) => l.deg === deg);
      let el;
      if (label) {
        el = document.createElement("div");
        el.className = "compass-label" + (label.cls ? ` ${label.cls}` : "");
        el.textContent = label.txt;
      } else {
        el = document.createElement("div");
        el.className = "compass-tick" + (deg % 45 === 0 ? " major" : "");
      }
      this.strip.appendChild(el);
      this.compassItems.push({ deg, el });
    }
  }

  setPassive(origin) {
    if (!origin) return;
    const [key, ...rest] = origin.passive.hint.split("—");
    this.el.querySelector(".passive-chip .key").textContent = key.trim();
    this.el.querySelector(".passive-chip .passive-name").textContent =
      `${origin.passive.name} · ${rest.join("—").trim()}`;
  }

  setMarkers(markers) {
    // wipe DOM markers and rebuild
    for (const m of this.strip.querySelectorAll(".compass-marker")) m.remove();
    this.markers = markers.map((m) => {
      const el = document.createElement("div");
      el.className = "compass-marker";
      el.textContent = m.icon;
      this.strip.appendChild(el);
      return { ...m, el };
    });
  }

  showPrompt(label) {
    this.promptLabel.textContent = label;
    this.prompt.classList.add("visible");
  }

  hidePrompt() {
    this.prompt.classList.remove("visible");
  }

  showToast(text) {
    this.toast.textContent = text;
    this.toast.classList.add("visible");
    clearTimeout(this._toastTimer);
    this._toastTimer = setTimeout(() => this.toast.classList.remove("visible"), 2600);
  }

  show() { this.el.classList.remove("hidden"); }
  hide() { this.el.classList.add("hidden"); }

  update(dt, { stats, camYaw, playerPos }) {
    // ---- vitals ----
    const hp = stats.health / stats.maxHealth;
    const mp = stats.magicka / stats.maxMagicka;
    this.healthFill.style.width = `${hp * 100}%`;
    this.magickaFill.style.width = `${mp * 100}%`;
    this.healthFill.classList.toggle("low", hp < 0.28);

    // ---- stamina wheel ----
    const sp = stats.stamina / stats.maxStamina;
    this.wheel.classList.toggle("visible", sp < 0.995);
    this.wheel.classList.toggle("exhausted", stats.exhausted);
    this.wheelFill.style.strokeDashoffset = `${(1 - sp) * WHEEL_C}`;

    // ---- compass (world North = -Z) ----
    const heading = (Math.atan2(-Math.sin(camYaw), Math.cos(camYaw)) * 180) / Math.PI;
    const center = this.strip.parentElement.clientWidth / 2;
    for (const item of this.compassItems) {
      const off = wrapDeg(item.deg - heading);
      if (Math.abs(off) > 75) {
        item.el.style.display = "none";
      } else {
        item.el.style.display = "block";
        item.el.style.left = `${center + off * PX_PER_DEG}px`;
      }
    }
    for (const m of this.markers) {
      let bearing = m.bearingDeg;
      if (m.worldPos && playerPos) {
        bearing = (Math.atan2(m.worldPos.x - playerPos.x, -(m.worldPos.z - playerPos.z)) * 180) / Math.PI;
      }
      const off = wrapDeg((bearing ?? 0) - heading);
      if (Math.abs(off) > 70) {
        m.el.style.display = "none";
      } else {
        m.el.style.display = "block";
        m.el.style.left = `${center + off * PX_PER_DEG}px`;
      }
    }

    // ---- hit vignette decay ----
    if (this._hitFlash > 0) {
      this._hitFlash = Math.max(0, this._hitFlash - dt * 2.2);
      this.vignette.style.opacity = this._hitFlash;
    }
  }
}
