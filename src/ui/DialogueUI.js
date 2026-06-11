// Letterboxed dialogue system + the interactive Conqueror's Contract panel
// with a hold-to-sign flourish.

import { Sfx } from "../core/Sfx.js";
import { getContractClauses } from "../data/dialogue/contract.js";

const CHARS_PER_SEC = 64;

export class DialogueUI {
  constructor(root) {
    this.root = root;

    this.letterTop = document.createElement("div");
    this.letterTop.className = "letterbox-top";
    this.letterBottom = document.createElement("div");
    this.letterBottom.className = "letterbox-bottom";
    root.appendChild(this.letterTop);
    root.appendChild(this.letterBottom);

    this.box = document.createElement("div");
    this.box.id = "dialogue-box";
    this.box.innerHTML = `
      <div class="dlg-speaker"></div>
      <div class="dlg-text"></div>
      <div class="dlg-choices"></div>
      <div class="dlg-continue">E / click — continue</div>
    `;
    root.appendChild(this.box);
    this.speakerEl = this.box.querySelector(".dlg-speaker");
    this.textEl = this.box.querySelector(".dlg-text");
    this.choicesEl = this.box.querySelector(".dlg-choices");
    this.continueEl = this.box.querySelector(".dlg-continue");

    this.contractPanel = document.createElement("div");
    this.contractPanel.id = "contract-panel";
    root.appendChild(this.contractPanel);

    this.tree = null;
    this.nodeId = null;
    this.onAction = null;
    this._typing = null;
    this._fullText = "";

    const advance = () => this._advance();
    this.box.addEventListener("click", advance);
    window.addEventListener("keydown", (e) => {
      if (!this.isOpen()) return;
      if (e.code === "KeyE" || e.code === "Enter" || e.code === "Space") {
        e.preventDefault();
        advance();
      }
    });
  }

  isOpen() {
    return this.box.classList.contains("visible");
  }

  start(tree, { onAction }) {
    this.tree = tree;
    this.onAction = onAction;
    this.root.classList.add("letterboxed");
    document.getElementById("ui-root").classList.add("letterboxed");
    this.box.classList.add("visible");
    this._showNode(tree.start);
  }

  jumpTo(nodeId) {
    this.box.classList.add("visible");
    this._showNode(nodeId);
  }

  close() {
    this.box.classList.remove("visible");
    document.getElementById("ui-root").classList.remove("letterboxed");
    clearInterval(this._typing);
    this._typing = null;
  }

  _showNode(id) {
    const node = this.tree.nodes[id];
    if (!node) {
      console.error(`[Dialogue] missing node "${id}"`);
      return this.close();
    }
    this.nodeId = id;
    this.node = node;
    this.speakerEl.textContent = node.speaker;
    this.choicesEl.innerHTML = "";
    this.continueEl.style.display = "none";

    // typewriter
    clearInterval(this._typing);
    this._fullText = node.text;
    this.textEl.textContent = "";
    let i = 0;
    this._typing = setInterval(() => {
      i = Math.min(this._fullText.length, i + 2);
      this.textEl.textContent = this._fullText.slice(0, i);
      if (i >= this._fullText.length) {
        clearInterval(this._typing);
        this._typing = null;
        this._onTextDone();
      }
    }, 2000 / CHARS_PER_SEC);
  }

  _onTextDone() {
    const node = this.node;
    if (node.choices) {
      for (const choice of node.choices) {
        const btn = document.createElement("button");
        btn.className = "dlg-choice";
        btn.textContent = choice.label;
        btn.addEventListener("click", (e) => {
          e.stopPropagation();
          Sfx.uiClick();
          this._showNode(choice.next);
        });
        this.choicesEl.appendChild(btn);
      }
    } else {
      this.continueEl.style.display = "block";
    }
  }

  _advance() {
    // fast-forward typewriter first
    if (this._typing) {
      clearInterval(this._typing);
      this._typing = null;
      this.textEl.textContent = this._fullText;
      this._onTextDone();
      return;
    }
    const node = this.node;
    if (!node || node.choices) return; // choices advance themselves
    if (node.action) {
      this.box.classList.remove("visible");
      this.onAction?.(node.action);
    } else if (node.next) {
      this._showNode(node.next);
    }
  }

  // ------------------------------------------------------------------
  // The Conqueror's Contract — parchment review + hold-to-sign.
  openContract(origin, playerName, onSigned) {
    const clauses = getContractClauses(origin, playerName);
    this.contractPanel.innerHTML = `
      <div class="contract-doc">
        <div class="contract-head">THE CONQUEROR'S CONTRACT</div>
        <div class="contract-sub">${origin.city.name} · ${origin.recruiter.title}</div>
        <div class="contract-body">
          ${clauses.map((c) => `<h3>${c.h}</h3><div class="clause">${c.body}</div>`).join("")}
        </div>
        <div class="contract-sign-zone">
          <div class="sign-line">
            <svg viewBox="0 0 220 54" preserveAspectRatio="none">
              <path class="sig-path" d=""></path>
              <text x="6" y="34" font-family="Cinzel, serif" font-size="20" fill="#1d3a8f" opacity="0">${playerName}</text>
            </svg>
            <div class="sign-hint">signature of the asset</div>
          </div>
          <button class="btn-sign"><div class="hold-fill"></div><span>HOLD TO SIGN</span></button>
        </div>
      </div>
    `;
    this.contractPanel.classList.add("visible");

    const btn = this.contractPanel.querySelector(".btn-sign");
    const fill = this.contractPanel.querySelector(".hold-fill");
    const sigPath = this.contractPanel.querySelector(".sig-path");
    const sigName = this.contractPanel.querySelector("text");

    let holding = false;
    let progress = 0;
    let raf = null;
    let last = 0;
    let done = false;

    const tick = (ts) => {
      if (done) return;
      const dt = last ? (ts - last) / 1000 : 0;
      last = ts;
      progress += (holding ? dt : -dt * 1.6) / 1.1;
      progress = Math.max(0, Math.min(1, progress));
      fill.style.width = `${progress * 100}%`;
      if (progress >= 1) {
        done = true;
        this._completeSignature(sigPath, sigName, btn, onSigned);
        return;
      }
      raf = requestAnimationFrame(tick);
    };
    const startHold = (e) => {
      e.preventDefault();
      if (done) return;
      holding = true;
      last = 0;
      cancelAnimationFrame(raf);
      raf = requestAnimationFrame(tick);
    };
    const endHold = () => {
      holding = false;
    };
    btn.addEventListener("mousedown", startHold);
    btn.addEventListener("touchstart", startHold);
    window.addEventListener("mouseup", endHold);
    window.addEventListener("touchend", endHold);
  }

  _completeSignature(sigPath, sigName, btn, onSigned) {
    Sfx.sign();
    btn.disabled = true;
    btn.querySelector("span").textContent = "SIGNED";
    // ink flourish: scrawl + name fade-in
    const d = "M8,38 C30,12 44,46 62,28 S96,40 118,24 S160,42 186,26 S204,34 212,30";
    sigPath.setAttribute("d", d);
    const len = sigPath.getTotalLength();
    sigPath.style.strokeDasharray = len;
    sigPath.style.strokeDashoffset = len;
    sigPath.getBoundingClientRect(); // flush layout so the transition runs
    sigPath.style.transition = "stroke-dashoffset 0.9s ease-out";
    sigPath.style.strokeDashoffset = "0";
    setTimeout(() => {
      sigName.style.transition = "opacity 0.5s ease";
      sigName.setAttribute("opacity", "0.85");
    }, 700);
    setTimeout(() => {
      this.contractPanel.classList.remove("visible");
      onSigned?.();
    }, 1700);
  }
}
