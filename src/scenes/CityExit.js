// The deployment corridor: the last secure street of the kingdom, ending at
// the frontier gate. Walk the length, the portcullis rises, The Wilds begin.

import * as THREE from "three";
import { toonMat, glowMat } from "../rendering/ToonMaterials.js";
import { addOutline } from "../rendering/OutlinePass.js";
import { aetherPipe, crystalLamp, banner, skyDome, ribArc, particles } from "./props.js";
import { CharacterRig } from "../character/CharacterRig.js";

const HALF_W = 4;
const GATE_Z = -48;
const END_Z = -58;

export class CityExit {
  constructor(origin) {
    this.origin = origin;
    const theme = origin.theme;
    const scene = (this.scene = new THREE.Scene());
    scene.fog = new THREE.Fog(theme.fog, 18, 85);
    scene.add(skyDome(theme.sky, theme.fog));

    this.t = 0;
    this.gateOpen = 0;

    // ---- street ----
    const street = new THREE.Mesh(new THREE.BoxGeometry(HALF_W * 2 + 1, 0.2, 70), toonMat(theme.floor));
    street.position.set(0, -0.1, -26);
    scene.add(street);

    // ---- flanking wall blocks + skyline ----
    const wallMat = toonMat(theme.wall);
    const trimMat = toonMat(theme.trim);
    for (const side of [-1, 1]) {
      for (let i = 0; i < 6; i++) {
        const z = 2 - i * 9.5;
        const h = 4.5 + ((i * 7 + (side > 0 ? 3 : 0)) % 4) * 1.4;
        const block = new THREE.Mesh(new THREE.BoxGeometry(3, h, 8.5), wallMat);
        block.position.set(side * (HALF_W + 1.6), h / 2, z);
        scene.add(block);
        const roof = new THREE.Mesh(new THREE.BoxGeometry(3.3, 0.35, 8.8), trimMat);
        roof.position.set(side * (HALF_W + 1.6), h + 0.18, z);
        scene.add(roof);
        // glowing window slits
        for (let wY = 1.6; wY < h - 0.8; wY += 1.7) {
          const win = new THREE.Mesh(new THREE.PlaneGeometry(0.3, 0.55), glowMat(theme.pipeGlow, 0.85));
          win.position.set(side * (HALF_W + 0.08), wY, z - 2.5 + ((wY * 13) % 5));
          win.rotation.y = side > 0 ? -Math.PI / 2 : Math.PI / 2;
          win.userData.noOutline = true;
          scene.add(win);
        }
      }
      // pipe run down the whole street
      scene.add(aetherPipe(
        [[side * (HALF_W - 0.1), 3.4, 2], [side * (HALF_W - 0.3), 3.9, -22], [side * (HALF_W - 0.1), 3.4, -46]],
        theme.pipeGlow, 0.08
      ));
    }

    // arches over the street
    for (let z = -6; z > GATE_Z + 4; z -= 12) {
      const arch = ribArc(HALF_W + 0.6, theme.trim);
      arch.position.set(0, 0.4, z);
      scene.add(arch);
    }

    // lamps + banners
    for (let z = -2; z > GATE_Z; z -= 11) {
      for (const side of [-1, 1]) {
        const lamp = crystalLamp(theme.pipeGlow, 2.4);
        lamp.position.set(side * (HALF_W - 0.5), 0, z - 3);
        scene.add(lamp);
      }
    }
    const b = banner(this.origin.theme);
    b.position.set(0, 3.6, GATE_Z + 0.6);
    b.scale.setScalar(1.6);
    scene.add(b);

    // ---- frontier gate ----
    const frame = new THREE.Group();
    const post = new THREE.BoxGeometry(0.8, 5.4, 0.8);
    for (const side of [-1, 1]) {
      const p = new THREE.Mesh(post, trimMat);
      p.position.set(side * (HALF_W - 0.2), 2.7, GATE_Z);
      frame.add(p);
    }
    const lintel = new THREE.Mesh(new THREE.BoxGeometry(HALF_W * 2 + 1, 0.9, 0.9), trimMat);
    lintel.position.set(0, 5.2, GATE_Z);
    frame.add(lintel);
    addOutline(frame, { thickness: 0.02 });
    scene.add(frame);

    this.gate = new THREE.Group();
    const barGeo = new THREE.CylinderGeometry(0.06, 0.06, 4.6, 6);
    const barMat = toonMat("#2e3440");
    for (let x = -HALF_W + 0.8; x <= HALF_W - 0.8; x += 0.55) {
      const bar = new THREE.Mesh(barGeo, barMat);
      bar.position.set(x, 2.3, 0);
      this.gate.add(bar);
    }
    const gateGlow = new THREE.Mesh(new THREE.BoxGeometry(HALF_W * 2 - 1.4, 0.08, 0.08), glowMat(theme.pipeGlow, 1));
    gateGlow.position.set(0, 0.35, 0);
    gateGlow.userData.noOutline = true;
    this.gate.add(gateGlow);
    this.gate.position.set(0, 0, GATE_Z);
    scene.add(this.gate);

    // beyond the gate: green haze of the frontier
    const wilds = new THREE.Mesh(new THREE.PlaneGeometry(40, 14), glowMat("#7fc46a", 0.5));
    wilds.position.set(0, 5, END_Z - 16);
    wilds.userData.noOutline = true;
    scene.add(wilds);
    scene.add(particles(60, theme.pipeGlow, 30, 0.06, 8));

    // ---- guards ----
    this.guards = [];
    for (const side of [-1, 1]) {
      const guard = new CharacterRig({ accent: theme.accent });
      guard.applyPhenotype(
        { weight: 0.8, height: 0.6, arcaneMod: 0.3, jaw: 0.8, cheek: 0.4, eyeTilt: 0.4, eyeShape: 0.35,
          hair: 6, beard: side > 0 ? 3 : 0, hairColor: 9, skinTone: side > 0 ? 2 : 5, warpaint: 0, paintColor: 0 },
        origin
      );
      guard.group.position.set(side * (HALF_W - 1.1), 0, GATE_Z + 2.2);
      guard.group.rotation.y = Math.PI; // face incoming player
      scene.add(guard.group);
      this.guards.push(guard);
    }

    // ---- lights ----
    scene.add(new THREE.AmbientLight(theme.ambient, 0.75));
    const sun = new THREE.DirectionalLight(0xfff2dd, 1.9);
    sun.position.set(-20, 30, -10);
    scene.add(sun);

    // ---- gameplay metadata ----
    this.playerSpawn = { position: new THREE.Vector3(0, 0, 0), yaw: Math.PI };
    this.interactables = [];
    this.triggers = [{ id: "toWilds", position: new THREE.Vector3(0, 0, END_Z + 2), radius: 3.5, fired: false }];
  }

  getHeight() {
    return 0;
  }

  clampCamera(pos) {
    pos.x = THREE.MathUtils.clamp(pos.x, -HALF_W + 0.3, HALF_W - 0.3);
    pos.z = THREE.MathUtils.clamp(pos.z, END_Z, 4.2);
    if (pos.y < 0.35) pos.y = 0.35;
  }

  clampPosition(pos) {
    pos.x = THREE.MathUtils.clamp(pos.x, -HALF_W + 0.4, HALF_W - 0.4);
    const gateBlocked = this.gateOpen < 0.85;
    const minZ = gateBlocked ? GATE_Z + 1.0 : END_Z - 1;
    pos.z = THREE.MathUtils.clamp(pos.z, minZ, 2.5);
  }

  isInGrass() {
    return false;
  }

  update(dt, playerPos) {
    this.t += dt;
    // portcullis rises as the player approaches
    const near = playerPos && playerPos.z < GATE_Z + 14;
    this.gateOpen = THREE.MathUtils.clamp(this.gateOpen + (near ? dt * 0.45 : -dt * 0.3), 0, 1);
    this.gate.position.y = this.gateOpen * 4.4;
    for (const guard of this.guards) guard.update(dt);
  }
}
