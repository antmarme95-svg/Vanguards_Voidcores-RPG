// Parametric anime-proportioned humanoid built from primitives, with named
// pivots so phenotype sliders can live-edit transforms, materials and parts.
// Used for the player (creation + gameplay) and for NPCs (recruiter, guards).

import * as THREE from "three";
import { toonMat, glowMat, flatMat } from "../rendering/ToonMaterials.js";
import { addOutline } from "../rendering/OutlinePass.js";
import { buildHeadTexture } from "./WarpaintAtlas.js";
import { HAIR_BUILDERS, BEARD_BUILDERS } from "./HairLibrary.js";
import { SKIN_TONES, HAIR_COLORS, PAINT_COLORS } from "../data/palette.js";

const lerp = (a, b, t) => a + (b - a) * t;

function capsule(r, len, mat) {
  return new THREE.Mesh(new THREE.CapsuleGeometry(r, len, 4, 10), mat);
}
function box(w, h, d, mat) {
  return new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat);
}

export class CharacterRig {
  constructor({ accent = "#46e6ff", outline = true } = {}) {
    this.group = new THREE.Group();
    this.group.name = "CharacterRig";

    this.accent = new THREE.Color(accent);
    this.t = 0;
    this.phase = 0;
    this.motion = { speed: 0, crouch: false };
    this.attackTimer = 0;
    this.attackStyle = "melee";
    this._headTexKey = null;
    this._hairKey = null;
    this._beardKey = null;
    this._originId = null;

    // ---- materials (per-rig instances so colors are independent) ----
    this.skinMat = toonMat("#f2b186");
    this.headMat = toonMat("#ffffff");
    this.hairMat = toonMat("#b8451f");
    this.leatherMat = toonMat("#5b4632");
    this.darkLeatherMat = toonMat("#3a2d22");
    this.metalMat = toonMat("#6f7a88");
    this.accentGlowMat = glowMat(this.accent, 1.2);
    this.veinMat = glowMat(this.accent, 0.8);
    this.eyeWhiteMat = flatMat("#f8f6f2");
    this.irisMat = flatMat(this.accent);
    this.pupilMat = flatMat("#10131a");

    this._build();
    if (outline) addOutline(this.group, { thickness: 0.06 });
  }

  // ------------------------------------------------------------------
  _build() {
    const body = (this.body = new THREE.Group());
    this.group.add(body);

    // ---------- legs ----------
    const hips = (this.hips = new THREE.Group());
    hips.position.y = 0.95;
    body.add(hips);

    this.pelvis = box(0.27, 0.15, 0.17, this.darkLeatherMat);
    this.pelvis.position.y = -0.02;
    hips.add(this.pelvis);

    const belt = box(0.3, 0.05, 0.2, this.leatherMat);
    belt.position.y = 0.05;
    hips.add(belt);
    const buckle = box(0.06, 0.04, 0.02, this.accentGlowMat);
    buckle.position.set(0.05, 0.05, 0.105);
    buckle.userData.noOutline = true;
    hips.add(buckle);

    this.legs = [];
    for (const side of [-1, 1]) {
      const leg = new THREE.Group();
      leg.position.set(side * 0.09, 0, 0);
      hips.add(leg);

      const thigh = capsule(0.067, 0.27, this.darkLeatherMat);
      thigh.position.y = -0.21;
      leg.add(thigh);

      const knee = new THREE.Group();
      knee.position.y = -0.45;
      leg.add(knee);

      const shin = capsule(0.055, 0.26, this.darkLeatherMat);
      shin.position.y = -0.2;
      knee.add(shin);

      const boot = box(0.1, 0.08, 0.17, this.leatherMat);
      boot.position.set(0, -0.45, 0.03);
      knee.add(boot);

      leg.userData = { knee, thigh, shin };
      this.legs.push(leg);
    }

    // ---------- torso ----------
    const spine = (this.spine = new THREE.Group());
    spine.position.y = 1.0;
    body.add(spine);

    this.torso = capsule(0.16, 0.3, this.skinMat);
    this.torso.position.y = 0.26;
    spine.add(this.torso);

    // jerkin: leather chest layer + cross strap + asymmetric pauldron
    const jerkin = capsule(0.165, 0.18, this.leatherMat);
    jerkin.position.y = 0.18;
    spine.add(jerkin);
    this.jerkin = jerkin;

    const strap = box(0.07, 0.5, 0.02, this.darkLeatherMat);
    strap.position.set(0.02, 0.28, 0.155);
    strap.rotation.z = 0.62;
    spine.add(strap);
    this.strap = strap;

    const pauldron = new THREE.Group();
    pauldron.position.set(0.225, 0.5, 0);
    const plateA = box(0.15, 0.05, 0.17, this.metalMat);
    const plateB = box(0.12, 0.05, 0.14, this.metalMat);
    plateB.position.y = 0.05;
    const stud = box(0.04, 0.025, 0.04, this.accentGlowMat);
    stud.position.y = 0.085;
    stud.userData.noOutline = true;
    pauldron.add(plateA, plateB, stud);
    pauldron.rotation.z = -0.12;
    spine.add(pauldron);

    // ---------- arms ----------
    this.arms = [];
    for (const side of [-1, 1]) {
      const arm = new THREE.Group();
      arm.position.set(side * 0.222, 0.45, 0);
      spine.add(arm);

      const upper = capsule(0.054, 0.2, this.skinMat);
      upper.position.y = -0.14;
      arm.add(upper);

      const elbow = new THREE.Group();
      elbow.position.y = -0.3;
      arm.add(elbow);

      const fore = capsule(0.047, 0.18, this.skinMat);
      fore.position.y = -0.12;
      elbow.add(fore);

      const hand = new THREE.Mesh(new THREE.SphereGeometry(0.052, 8, 7), this.skinMat);
      hand.position.y = -0.26;
      elbow.add(hand);

      arm.userData = { elbow, upper, fore, hand, side };
      this.arms.push(arm);
    }

    // prosthetic aether forearm (left arm, shown at high Arcane Modification)
    const leftElbow = this.arms[0].userData.elbow;
    const pros = (this.prosthetic = new THREE.Group());
    const proseg = box(0.075, 0.2, 0.075, this.metalMat);
    proseg.position.y = -0.12;
    const seam1 = box(0.012, 0.18, 0.078, this.veinMat);
    seam1.position.set(0.034, -0.12, 0);
    seam1.userData.noOutline = true;
    const fist = box(0.085, 0.07, 0.08, this.metalMat);
    fist.position.y = -0.26;
    const knuckle = box(0.087, 0.018, 0.082, this.veinMat);
    knuckle.position.y = -0.235;
    knuckle.userData.noOutline = true;
    pros.add(proseg, seam1, fist, knuckle);
    pros.visible = false;
    leftElbow.add(pros);

    // ---------- head ----------
    const neck = capsule(0.05, 0.07, this.skinMat);
    neck.position.y = 0.58;
    spine.add(neck);

    const head = (this.head = new THREE.Group());
    head.position.y = 0.7;
    spine.add(head);

    this.skull = new THREE.Mesh(new THREE.SphereGeometry(0.15, 24, 18), this.headMat);
    this.skull.scale.y = 1.07;
    this.skull.rotation.y = -Math.PI / 2; // puts the atlas face strip (u≈0.5) at +z
    head.add(this.skull);

    this.jaw = box(0.165, 0.075, 0.13, this.headMat);
    this.jaw.position.set(0, -0.105, 0.062);
    head.add(this.jaw);

    this.cheeks = [];
    for (const side of [-1, 1]) {
      const cheek = new THREE.Mesh(new THREE.SphereGeometry(0.036, 8, 7), this.headMat);
      cheek.position.set(side * 0.088, -0.018, 0.108);
      head.add(cheek);
      this.cheeks.push(cheek);
    }

    this.eyes = [];
    this.brows = [];
    for (const side of [-1, 1]) {
      const eye = new THREE.Group();
      eye.position.set(side * 0.058, 0.018, 0.136);

      const white = new THREE.Mesh(new THREE.SphereGeometry(0.034, 10, 8), this.eyeWhiteMat);
      white.scale.z = 0.55;
      white.userData.noOutline = true;
      const iris = new THREE.Mesh(new THREE.CircleGeometry(0.0185, 12), this.irisMat);
      iris.position.z = 0.0195;
      iris.userData.noOutline = true;
      const pupil = new THREE.Mesh(new THREE.CircleGeometry(0.009, 10), this.pupilMat);
      pupil.position.z = 0.0205;
      pupil.userData.noOutline = true;
      const glint = new THREE.Mesh(new THREE.CircleGeometry(0.0045, 8), this.eyeWhiteMat);
      glint.position.set(0.006, 0.007, 0.021);
      glint.userData.noOutline = true;
      eye.add(white, iris, pupil, glint);
      eye.userData.side = side;
      head.add(eye);
      this.eyes.push(eye);

      const brow = box(0.055, 0.012, 0.012, this.pupilMat);
      brow.position.set(side * 0.058, 0.07, 0.146);
      brow.userData.noOutline = true;
      head.add(brow);
      this.brows.push(brow);
    }

    // technomagic goggles (visible at mid Arcane Modification)
    const goggles = (this.goggles = new THREE.Group());
    const band = box(0.31, 0.03, 0.03, this.darkLeatherMat);
    band.position.set(0, 0.095, 0.0);
    const lensL = new THREE.Mesh(new THREE.CylinderGeometry(0.035, 0.035, 0.03, 12), this.metalMat);
    lensL.rotation.x = Math.PI / 2;
    lensL.position.set(-0.055, 0.095, 0.125);
    const lensGlowL = new THREE.Mesh(new THREE.CircleGeometry(0.026, 12), this.accentGlowMat);
    lensGlowL.position.set(-0.055, 0.095, 0.142);
    lensGlowL.userData.noOutline = true;
    const lensR = lensL.clone();
    lensR.position.x = 0.055;
    const lensGlowR = lensGlowL.clone();
    lensGlowR.position.x = 0.055;
    goggles.add(band, lensL, lensR, lensGlowL, lensGlowR);
    goggles.visible = false;
    head.add(goggles);

    // hair / beard slots
    this.hairSlot = new THREE.Group();
    this.beardSlot = new THREE.Group();
    head.add(this.hairSlot, this.beardSlot);

    // origin features slot (ears / tail)
    this.featureSlot = new THREE.Group();
    head.add(this.featureSlot);
    this.tailSlot = new THREE.Group();
    hips.add(this.tailSlot);

    // glowing mana veins (Arcane Modification)
    this.veins = [];
    const veinDefs = [
      [this.arms[1], 0.045, -0.1, 0.02, 0.012, 0.16],   // right upper arm
      [this.arms[1].userData.elbow, 0.04, -0.1, 0.015, 0.01, 0.13],
      [this.spine, 0.1, 0.32, 0.145, 0.014, 0.2],       // chest line
      [this.spine, -0.06, 0.5, 0.12, 0.01, 0.09],       // neck side
      [this.legs[0].userData.knee, -0.04, -0.16, 0.045, 0.01, 0.14],
    ];
    for (const [parent, x, y, z, w, h] of veinDefs) {
      const vein = box(w, h, w, this.veinMat);
      vein.position.set(x, y, z);
      vein.rotation.z = 0.18;
      vein.userData.noOutline = true;
      vein.visible = false;
      parent.add(vein);
      this.veins.push(vein);
    }
  }

  // ------------------------------------------------------------------
  // Live phenotype application — called on every slider tick.
  applyPhenotype(p, origin) {
    // ---- body & tech ----
    const w = p.weight ?? 0.5;
    const limb = lerp(0.82, 1.42, w);
    this.torso.scale.set(lerp(0.84, 1.34, w), 1, lerp(0.86, 1.26, w));
    this.jerkin.scale.set(lerp(0.86, 1.36, w), 1, lerp(0.88, 1.28, w));
    this.pelvis.scale.set(lerp(0.88, 1.25, w), 1, 1);
    for (const arm of this.arms) {
      arm.userData.upper.scale.set(limb, 1, limb);
      arm.userData.fore.scale.set(limb, 1, limb);
    }
    for (const leg of this.legs) {
      leg.userData.thigh.scale.set(limb, 1, limb);
      leg.userData.shin.scale.set(limb, 1, limb);
    }

    const range = origin?.heightRange ?? [0.94, 1.1];
    this.group.scale.setScalar(lerp(range[0], range[1], p.height ?? 0.5));

    const mod = p.arcaneMod ?? 0;
    for (const vein of this.veins) vein.visible = mod > 0.06;
    this.veinMat.color.copy(this.accent).multiplyScalar(0.35 + mod * 1.8);
    this.goggles.visible = mod > 0.38;
    const prostheticOn = mod > 0.68;
    this.prosthetic.visible = prostheticOn;
    this.arms[0].userData.fore.visible = !prostheticOn;
    this.arms[0].userData.hand.visible = !prostheticOn;

    // ---- face structure ----
    this.jaw.scale.set(lerp(0.72, 1.28, p.jaw ?? 0.5), lerp(0.85, 1.18, p.jaw ?? 0.5), lerp(0.8, 1.22, p.jaw ?? 0.5));
    for (const cheek of this.cheeks) {
      cheek.position.y = lerp(-0.045, 0.012, p.cheek ?? 0.5);
      cheek.scale.setScalar(lerp(0.75, 1.3, p.cheek ?? 0.5));
    }
    this.eyes.forEach((eye, i) => {
      const side = eye.userData.side;
      eye.rotation.z = side * lerp(-0.32, 0.26, p.eyeTilt ?? 0.5);
      eye.scale.y = lerp(0.5, 1.3, p.eyeShape ?? 0.5);
      this.brows[i].rotation.z = side * lerp(-0.4, 0.18, p.eyeTilt ?? 0.5);
    });

    // ---- colors ----
    const skinHex = SKIN_TONES[p.skinTone ?? 1] ?? SKIN_TONES[1];
    const hairHex = HAIR_COLORS[p.hairColor ?? 0] ?? HAIR_COLORS[0];
    const paintHex = PAINT_COLORS[p.paintColor ?? 0] ?? PAINT_COLORS[0];
    this.skinMat.color.set(skinHex);
    this.hairMat.color.set(hairHex);

    const texKey = `${skinHex}|${p.warpaint ?? 0}|${paintHex}`;
    if (texKey !== this._headTexKey) {
      this._headTexKey = texKey;
      const old = this.headMat.map;
      this.headMat.map = buildHeadTexture({ skinHex, warpaintIndex: p.warpaint ?? 0, paintHex });
      this.headMat.needsUpdate = true;
      old?.dispose();
    }

    // ---- hair & beard swaps ----
    const hairKey = `${p.hair ?? 0}`;
    if (hairKey !== this._hairKey) {
      this._hairKey = hairKey;
      this.hairSlot.clear();
      const built = HAIR_BUILDERS[p.hair ?? 0]?.(this.hairMat);
      if (built) {
        addOutline(built, { thickness: 0.07 });
        this.hairSlot.add(built);
      }
    }
    const beardKey = `${p.beard ?? 0}`;
    if (beardKey !== this._beardKey) {
      this._beardKey = beardKey;
      this.beardSlot.clear();
      const built = BEARD_BUILDERS[p.beard ?? 0]?.(this.hairMat);
      if (built) {
        addOutline(built, { thickness: 0.07 });
        this.beardSlot.add(built);
      }
    }

    // ---- origin features (ears, tail, accent) ----
    if (origin && origin.id !== this._originId) {
      this._originId = origin.id;
      this.accent.set(origin.theme.accent);
      this.irisMat.color.set(origin.theme.accent);
      this.accentGlowMat.color.set(origin.theme.accent).multiplyScalar(1.2);
      this._buildOriginFeatures(origin);
    }
  }

  _buildOriginFeatures(origin) {
    this.featureSlot.clear();
    this.tailSlot.clear();

    if (origin.id === "aetherborn") {
      // long pointed elven ears
      for (const side of [-1, 1]) {
        const ear = new THREE.Mesh(new THREE.ConeGeometry(0.026, 0.14, 6), this.skinMat);
        ear.position.set(side * 0.155, 0.02, -0.01);
        ear.rotation.z = side * -1.95;
        ear.rotation.x = -0.25;
        this.featureSlot.add(ear);
      }
    } else if (origin.id === "miststalker") {
      // beastfolk ears + tail
      for (const side of [-1, 1]) {
        const ear = new THREE.Mesh(new THREE.ConeGeometry(0.045, 0.11, 5), this.hairMat);
        ear.position.set(side * 0.082, 0.15, -0.02);
        ear.rotation.z = side * -0.35;
        this.featureSlot.add(ear);
      }
      const tail = new THREE.Group();
      let r = 0.035;
      for (let i = 0; i < 6; i++) {
        const seg = new THREE.Mesh(new THREE.SphereGeometry(r, 8, 7), this.hairMat);
        seg.position.set(0, -0.05 - i * 0.012, -0.12 - i * 0.07);
        tail.add(seg);
        r *= 0.92;
      }
      this.tailSlot.add(tail);
    } else {
      // ironblooded: compact ears
      for (const side of [-1, 1]) {
        const ear = new THREE.Mesh(new THREE.SphereGeometry(0.032, 8, 7), this.skinMat);
        ear.position.set(side * 0.148, 0.0, 0.0);
        this.featureSlot.add(ear);
      }
    }
    addOutline(this.featureSlot, { thickness: 0.07 });
    addOutline(this.tailSlot, { thickness: 0.07 });
  }

  // ------------------------------------------------------------------
  setMotion({ speed = 0, crouch = false } = {}) {
    this.motion.speed = speed;
    this.motion.crouch = crouch;
  }

  playAttack(style = "melee") {
    this.attackStyle = style;
    this.attackTimer = 0.38;
  }

  update(dt) {
    this.t += dt;
    const { speed, crouch } = this.motion;

    // locomotion swing
    if (speed > 0.02) this.phase += dt * (6.5 + 7.5 * speed);
    const amp = Math.min(speed, 1) * 0.62;
    const swing = Math.sin(this.phase) * amp;
    this.legs[0].rotation.x = swing;
    this.legs[1].rotation.x = -swing;
    this.legs[0].userData.knee.rotation.x = Math.max(0, -Math.sin(this.phase)) * amp * 1.1;
    this.legs[1].userData.knee.rotation.x = Math.max(0, Math.sin(this.phase)) * amp * 1.1;

    const armSwing = swing * 0.75;
    if (this.attackTimer <= 0) {
      this.arms[0].rotation.x = -armSwing;
      this.arms[1].rotation.x = armSwing;
      this.arms[0].rotation.z = 0.1;
      this.arms[1].rotation.z = -0.1;
      this.arms[0].userData.elbow.rotation.x = -0.25 - Math.max(0, armSwing) * 0.6;
      this.arms[1].userData.elbow.rotation.x = -0.25 - Math.max(0, -armSwing) * 0.6;
    }

    // attack envelope: wind-up then snap
    if (this.attackTimer > 0) {
      this.attackTimer -= dt;
      const k = 1 - Math.max(this.attackTimer, 0) / 0.38; // 0→1
      const snap = k < 0.35 ? -1.0 - k * 2.2 : lerp(-1.8, 0.4, (k - 0.35) / 0.65);
      if (this.attackStyle === "bolt") {
        this.arms[0].rotation.x = snap * 0.8;
        this.arms[1].rotation.x = snap;
        this.arms[1].userData.elbow.rotation.x = -0.1;
      } else {
        this.arms[1].rotation.x = snap;
        this.arms[1].rotation.z = -0.35;
        this.arms[1].userData.elbow.rotation.x = -0.15;
      }
    }

    // crouch / breathe
    const crouchY = crouch ? -0.17 : 0;
    this.body.position.y += (crouchY - this.body.position.y) * Math.min(1, dt * 10);
    const lean = crouch ? 0.24 : 0;
    this.spine.rotation.x += (lean - this.spine.rotation.x) * Math.min(1, dt * 10);
    this.torso.scale.y = 1 + Math.sin(this.t * 2.1) * 0.012;

    // beast tail sway
    if (this.tailSlot.children.length) {
      this.tailSlot.rotation.y = Math.sin(this.t * 1.7) * 0.25 + swing * 0.3;
    }
  }
}
