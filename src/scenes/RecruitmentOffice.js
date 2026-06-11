// The Recruitment Office — one interior kit, three kingdom themes.
// The slice opens here: no prison carriage, just paperwork with attitude.

import * as THREE from "three";
import { toonMat, glowMat, flatMat } from "../rendering/ToonMaterials.js";
import { addOutline } from "../rendering/OutlinePass.js";
import {
  room, slidingDoors, aetherPipe, crystalLamp, banner,
  spinGear, floatingCrystal, crateStack, bookStack, ribArc,
} from "./props.js";
import { CharacterRig } from "../character/CharacterRig.js";

const NPC_PRESETS = {
  aetherborn: {
    weight: 0.22, height: 0.85, arcaneMod: 0.55, jaw: 0.35, cheek: 0.75, eyeTilt: 0.7, eyeShape: 0.85,
    hair: 2, beard: 0, hairColor: 1, skinTone: 6, warpaint: 2, paintColor: 0,
  },
  ironblooded: {
    weight: 0.95, height: 0.7, arcaneMod: 0.25, jaw: 0.9, cheek: 0.4, eyeTilt: 0.3, eyeShape: 0.4,
    hair: 1, beard: 2, hairColor: 2, skinTone: 5, warpaint: 5, paintColor: 2,
  },
  miststalker: {
    weight: 0.35, height: 0.6, arcaneMod: 0.12, jaw: 0.45, cheek: 0.85, eyeTilt: 0.9, eyeShape: 0.7,
    hair: 9, beard: 0, hairColor: 0, skinTone: 7, warpaint: 3, paintColor: 4,
  },
};

const W = 12, D = 10, H = 4.6;

export class RecruitmentOffice {
  constructor(origin) {
    this.origin = origin;
    const theme = origin.theme;
    const scene = (this.scene = new THREE.Scene());
    scene.fog = new THREE.Fog(theme.fog, 6, 30);
    scene.background = new THREE.Color(theme.fog);

    this.t = 0;
    this.doorsOpen = false;
    this.spinners = [];
    this.bobbers = [];
    this.flickerLights = [];

    // ---- shell ----
    const shell = room({ w: W, h: H, d: D, floor: theme.floor, wall: theme.wall, trim: theme.trim });
    addOutline(shell, { thickness: 0.012 });
    scene.add(shell);

    // ---- doors (front, +z) ----
    this.doors = slidingDoors(theme.trim, theme.pipeGlow);
    this.doors.position.set(0, 0, D / 2);
    scene.add(this.doors);

    // vestibule glow beyond the doors (the "outside" teaser)
    const beyond = new THREE.Mesh(new THREE.PlaneGeometry(4, 3.4), glowMat(theme.sky, 0.8));
    beyond.position.set(0, 1.6, D / 2 + 3.2);
    beyond.rotation.y = Math.PI;
    beyond.userData.noOutline = true;
    scene.add(beyond);

    // ---- desk + paperwork ----
    const desk = new THREE.Group();
    const top = new THREE.Mesh(new THREE.BoxGeometry(2.3, 0.09, 0.95), toonMat("#4a3a2a"));
    top.position.y = 0.8;
    desk.add(top);
    for (const [x, z] of [[-1.05, -0.38], [1.05, -0.38], [-1.05, 0.38], [1.05, 0.38]]) {
      const leg = new THREE.Mesh(new THREE.BoxGeometry(0.09, 0.8, 0.09), toonMat("#3a2d20"));
      leg.position.set(x, 0.4, z);
      desk.add(leg);
    }
    const parchment = new THREE.Mesh(new THREE.PlaneGeometry(0.34, 0.46), flatMat("#e8d5a8"));
    parchment.rotation.x = -Math.PI / 2;
    parchment.rotation.z = 0.2;
    parchment.position.set(0.2, 0.852, 0.1);
    parchment.userData.noOutline = true;
    desk.add(parchment);
    const inkwell = new THREE.Mesh(new THREE.CylinderGeometry(0.045, 0.055, 0.09, 8), toonMat("#1c2030"));
    inkwell.position.set(-0.45, 0.89, 0.05);
    desk.add(inkwell);
    addOutline(desk, { thickness: 0.03 });
    desk.position.set(0, 0, -1.6);
    scene.add(desk);
    this.deskAABB = { minX: -1.35, maxX: 1.35, minZ: -2.25, maxZ: -0.95 };

    // ---- recruiter NPC ----
    this.recruiter = new CharacterRig({ accent: theme.accent });
    this.recruiter.applyPhenotype(NPC_PRESETS[origin.id], origin);
    this.recruiter.group.position.set(0, 0, -2.75);
    this.recruiter.group.rotation.y = 0; // rig faces +z → toward the door
    scene.add(this.recruiter.group);

    // ---- banners + pipes + lamps ----
    for (const x of [-2.2, 2.2]) {
      const b = banner(theme);
      b.position.set(x, 2.9, -D / 2 + 0.2);
      scene.add(b);
    }
    scene.add(aetherPipe(
      [[-W / 2 + 0.3, 3.9, -D / 2 + 0.3], [0, 4.1, -D / 2 + 0.3], [W / 2 - 0.3, 3.9, -D / 2 + 0.3]],
      theme.pipeGlow
    ));
    scene.add(aetherPipe(
      [[W / 2 - 0.3, 0.4, -2], [W / 2 - 0.3, 2.2, 0], [W / 2 - 0.3, 3.8, 2.5]],
      theme.pipeGlow
    ));
    for (const [x, z] of [[-W / 2 + 0.8, D / 2 - 1.2], [W / 2 - 0.8, D / 2 - 1.2]]) {
      const lamp = crystalLamp(theme.pipeGlow);
      lamp.position.set(x, 0, z);
      scene.add(lamp);
    }

    // ---- theme set dressing ----
    this._dressTheme(theme);

    // ---- lights ----
    scene.add(new THREE.AmbientLight(theme.ambient, 0.55));
    const keyLight = new THREE.DirectionalLight(0xffffff, 1.25);
    keyLight.position.set(3, 6, 4);
    scene.add(keyLight);
    const glowA = new THREE.PointLight(theme.pipeGlow, 12, 12);
    glowA.position.set(-3.5, 3.2, 1.5);
    const glowB = new THREE.PointLight(theme.pipeGlow, 10, 12);
    glowB.position.set(3.5, 3.2, -2);
    scene.add(glowA, glowB);
    if (theme.propSet === "forge") this.flickerLights.push(glowA, glowB);

    // ---- gameplay metadata ----
    this.playerSpawn = { position: new THREE.Vector3(-1.2, 0, 2.6), yaw: Math.PI };
    this.interactables = [
      {
        id: "recruiter",
        label: `Talk to ${origin.recruiter.name}`,
        position: new THREE.Vector3(0, 1, -1.9),
        radius: 2.0,
        enabled: true,
      },
      {
        id: "exitDoors",
        label: "Step into the Wilds",
        position: new THREE.Vector3(0, 1, D / 2),
        radius: 1.6,
        enabled: false,
      },
    ];
  }

  _dressTheme(theme) {
    const scene = this.scene;
    if (theme.propSet === "skyland") {
      for (let i = 0; i < 6; i++) {
        const c = floatingCrystal(theme.pipeGlow, 0.1 + Math.random() * 0.12);
        c.position.set(-4.5 + Math.random() * 9, 2.2 + Math.random() * 1.8, -4 + Math.random() * 6);
        this.bobbers.push(c);
        scene.add(c);
      }
      for (const [x, z, ry] of [[-4.6, -3.2, 0.4], [-4.2, -3.8, -0.2], [4.5, -2.5, 0.8]]) {
        const books = bookStack();
        books.position.set(x, 0, z);
        books.rotation.y = ry;
        scene.add(books);
      }
      // tall arched window of open sky
      const win = new THREE.Mesh(new THREE.PlaneGeometry(2.4, 3), glowMat(theme.sky, 1.0));
      win.position.set(-W / 2 + 0.15, 2.2, -1);
      win.rotation.y = Math.PI / 2;
      win.userData.noOutline = true;
      scene.add(win);
    } else if (theme.propSet === "forge") {
      const gear = spinGear(0.9, "#5a4a3a");
      gear.position.set(W / 2 - 0.45, 2.6, 1.5);
      gear.rotation.y = Math.PI / 2;
      this.spinners.push(gear);
      scene.add(gear);
      const gear2 = spinGear(0.5, "#4a3c30");
      gear2.position.set(W / 2 - 0.4, 1.2, 3.2);
      gear2.rotation.y = Math.PI / 2;
      gear2.userData.spin = -0.7;
      this.spinners.push(gear2);
      scene.add(gear2);
      // molten channel along the left wall
      const channel = new THREE.Mesh(new THREE.BoxGeometry(0.8, 0.06, D - 1), glowMat("#ff5a1f", 1.1));
      channel.position.set(-W / 2 + 0.7, 0.04, 0);
      channel.userData.noOutline = true;
      scene.add(channel);
      const anvil = new THREE.Group();
      const base = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.45, 0.4), toonMat("#3a3f4a"));
      base.position.y = 0.22;
      const horn = new THREE.Mesh(new THREE.BoxGeometry(0.85, 0.18, 0.3), toonMat("#4a505c"));
      horn.position.y = 0.54;
      anvil.add(base, horn);
      addOutline(anvil, { thickness: 0.04 });
      anvil.position.set(-3.6, 0, 1.8);
      scene.add(anvil);
    } else {
      // docks: colossal rib arches + smuggler crates + low fog feel
      for (const z of [-2.5, 0.5, 3.5]) {
        const rib = ribArc(4.4, "#cfc8b8");
        rib.position.set(0, 0.1, z);
        rib.scale.y = 1.15;
        addOutline(rib, { thickness: 0.02 });
        this.scene.add(rib);
      }
      const crates = crateStack(theme.accent);
      crates.position.set(-4.2, 0, 2.6);
      scene.add(crates);
      const crates2 = crateStack(theme.accent);
      crates2.position.set(4.3, 0, -3.4);
      crates2.rotation.y = 1.2;
      scene.add(crates2);
      this.scene.fog = new THREE.Fog(this.origin.theme.fog, 3, 18);
    }
  }

  setDoorsOpen(open) {
    this.doorsOpen = open;
    const exit = this.interactables.find((i) => i.id === "exitDoors");
    if (exit) exit.enabled = open;
  }

  getHeight() {
    return 0;
  }

  clampCamera(pos) {
    pos.x = THREE.MathUtils.clamp(pos.x, -W / 2 + 0.35, W / 2 - 0.35);
    pos.z = THREE.MathUtils.clamp(pos.z, -D / 2 + 0.35, D / 2 - 0.35);
    pos.y = THREE.MathUtils.clamp(pos.y, 0.35, H - 0.35);
  }

  clampPosition(pos, radius = 0.35) {
    const inDoorway = Math.abs(pos.x) < 1.0 && this.doorsOpen;
    pos.x = THREE.MathUtils.clamp(pos.x, -W / 2 + 0.5, W / 2 - 0.5);
    const maxZ = inDoorway ? D / 2 + 1.0 : D / 2 - 0.5;
    pos.z = THREE.MathUtils.clamp(pos.z, -D / 2 + 0.5, maxZ);
    // desk block
    const a = this.deskAABB;
    if (pos.x > a.minX - radius && pos.x < a.maxX + radius && pos.z > a.minZ - radius && pos.z < a.maxZ + radius) {
      const dxMin = Math.abs(pos.x - (a.minX - radius));
      const dxMax = Math.abs(a.maxX + radius - pos.x);
      const dzMin = Math.abs(pos.z - (a.minZ - radius));
      const dzMax = Math.abs(a.maxZ + radius - pos.z);
      const m = Math.min(dxMin, dxMax, dzMin, dzMax);
      if (m === dxMin) pos.x = a.minX - radius;
      else if (m === dxMax) pos.x = a.maxX + radius;
      else if (m === dzMin) pos.z = a.minZ - radius;
      else pos.z = a.maxZ + radius;
    }
  }

  isInGrass() {
    return false;
  }

  update(dt) {
    this.t += dt;
    this.doors.userData.tick(dt, this.doorsOpen);
    this.recruiter.update(dt);
    for (const s of this.spinners) s.rotation.z += dt * s.userData.spin;
    for (const b of this.bobbers) {
      b.position.y += Math.sin(this.t * 1.3 + b.userData.bobSeed) * 0.002;
      b.rotation.y += dt * 0.6;
    }
    for (const l of this.flickerLights) {
      l.intensity = 22 + Math.sin(this.t * 11 + l.position.x) * 4 + Math.random() * 2;
    }
  }
}
