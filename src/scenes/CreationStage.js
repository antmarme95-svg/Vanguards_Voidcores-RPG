// The character-creation viewport stage: dark studio, hero platform,
// 3-point dynamic lighting that retints with the selected origin.

import * as THREE from "three";
import { toonMat, glowMat } from "../rendering/ToonMaterials.js";
import { skyDome, particles, floatingCrystal } from "./props.js";

export class CreationStage {
  constructor() {
    const scene = (this.scene = new THREE.Scene());
    scene.fog = new THREE.Fog(0x0a0f16, 8, 26);

    this.dome = skyDome("#10151f", "#1c2a3a", 60);
    scene.add(this.dome);

    const floor = new THREE.Mesh(new THREE.CircleGeometry(20, 40), toonMat("#10161f"));
    floor.rotation.x = -Math.PI / 2;
    scene.add(floor);

    this.platform = new THREE.Mesh(new THREE.CylinderGeometry(1.5, 1.7, 0.18, 28), toonMat("#222b38"));
    this.platform.position.y = 0.09;
    scene.add(this.platform);

    this.ringMat = glowMat("#46e6ff", 0.9);
    const ring = new THREE.Mesh(new THREE.TorusGeometry(1.62, 0.035, 8, 48), this.ringMat);
    ring.rotation.x = Math.PI / 2;
    ring.position.y = 0.2;
    scene.add(ring);

    // 3-point lighting
    this.key = new THREE.DirectionalLight(0xffffff, 2.4);
    this.key.position.set(2.5, 4, 3.5);
    this.fill = new THREE.DirectionalLight(0x8899bb, 0.9);
    this.fill.position.set(-3, 2, 2);
    this.rim = new THREE.PointLight(0x46e6ff, 14, 12);
    this.rim.position.set(0, 2.6, -2.6);
    this.ambient = new THREE.AmbientLight(0x404a5a, 1.4);
    scene.add(this.key, this.fill, this.rim, this.ambient);

    this.dust = particles(110, 0x46e6ff, 14, 0.035, 5);
    scene.add(this.dust);

    this.crystals = new THREE.Group();
    for (let i = 0; i < 5; i++) {
      const c = floatingCrystal("#46e6ff", 0.1 + Math.random() * 0.08);
      const a = (i / 5) * Math.PI * 2 + 0.5;
      // keep the ring wide and behind the stage so none drift into the lens
      c.position.set(Math.cos(a) * 5.4, 1.4 + Math.random() * 1.8, Math.sin(a) * 5.4 - 3.2);
      this.crystals.add(c);
    }
    scene.add(this.crystals);

    // camera anchor for the right-hand viewport composition
    this.cameraPos = new THREE.Vector3(0.85, 1.45, 3.3);
    this.cameraTarget = new THREE.Vector3(0.25, 1.0, 0);
    this.t = 0;
  }

  setTheme(origin) {
    if (!origin) return;
    const accent = new THREE.Color(origin.theme.accent);
    this.rim.color.copy(accent);
    this.ringMat.color.copy(accent).multiplyScalar(0.9);
    this.dust.material.color.copy(accent);
    for (const c of this.crystals.children) c.material.color.copy(accent);
    this.scene.fog.color.set("#0a0f16").lerp(accent, 0.08);
  }

  update(dt) {
    this.t += dt;
    for (const c of this.crystals.children) {
      c.position.y += Math.sin(this.t * 1.4 + c.userData.bobSeed) * 0.0018;
      c.rotation.y += dt * 0.5;
    }
    this.dust.rotation.y += dt * 0.02;
  }
}
