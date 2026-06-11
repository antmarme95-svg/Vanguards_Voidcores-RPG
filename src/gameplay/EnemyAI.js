// Maddened Gloomfangs — frontier beasts driven feral by Core resonance.
// FSM: roam → chase → windup → lunge → recover, with stealth-aware detection.

import * as THREE from "three";
import { bus } from "../core/EventBus.js";
import { Sfx } from "../core/Sfx.js";
import { toonMat, glowMat } from "../rendering/ToonMaterials.js";
import { addOutline } from "../rendering/OutlinePass.js";

const BASE_DETECT = 11;

export class MaddenedBeast {
  constructor(spawnPos, scene) {
    this.scene = scene;
    this.home = spawnPos.clone();
    this.position = spawnPos.clone();

    this.health = 52;
    this.maxHealth = 52;
    this.dead = false;
    this.aggro = false;
    this.state = "roam";
    this.stateT = 0;
    this.wanderTarget = spawnPos.clone();
    this.wanderTimer = 0;
    this.facing = Math.random() * Math.PI * 2;
    this.lungeDir = new THREE.Vector3();
    this.lungeHitDone = false;
    this.flashT = 0;
    this.t = Math.random() * 10;

    this._build();
    this.group.position.copy(this.position);
    scene.scene.add(this.group);
  }

  _build() {
    const g = (this.group = new THREE.Group());
    this.furMat = toonMat("#564a6b");
    this.darkMat = toonMat("#3c3450");
    const crystalMat = (this.crystalMat = glowMat("#ff2336", 1.1));
    const eyeMat = (this.eyeMat = glowMat("#ff4444", 1.4));

    const body = new THREE.Mesh(new THREE.CapsuleGeometry(0.3, 0.65, 4, 10), this.furMat);
    body.rotation.x = Math.PI / 2;
    body.position.y = 0.52;
    g.add(body);
    this.body = body;

    const head = new THREE.Group();
    head.position.set(0, 0.66, 0.62);
    const skull = new THREE.Mesh(new THREE.SphereGeometry(0.23, 12, 10), this.furMat);
    const snout = new THREE.Mesh(new THREE.BoxGeometry(0.2, 0.14, 0.26), this.darkMat);
    snout.position.set(0, -0.06, 0.2);
    head.add(skull, snout);
    for (const side of [-1, 1]) {
      const ear = new THREE.Mesh(new THREE.ConeGeometry(0.07, 0.2, 5), this.darkMat);
      ear.position.set(side * 0.13, 0.2, -0.05);
      ear.rotation.z = side * -0.4;
      head.add(ear);
      const eye = new THREE.Mesh(new THREE.SphereGeometry(0.045, 8, 6), eyeMat);
      eye.position.set(side * 0.11, 0.04, 0.18);
      eye.userData.noOutline = true;
      head.add(eye);
    }
    // crystal corruption on the brow
    const browShard = new THREE.Mesh(new THREE.OctahedronGeometry(0.07), crystalMat);
    browShard.position.set(0, 0.16, 0.12);
    browShard.scale.y = 1.8;
    browShard.userData.noOutline = true;
    head.add(browShard);
    g.add(head);
    this.head = head;

    this.legs = [];
    for (const [x, z] of [[-0.2, 0.32], [0.2, 0.32], [-0.2, -0.32], [0.2, -0.32]]) {
      const leg = new THREE.Mesh(new THREE.CylinderGeometry(0.07, 0.05, 0.42, 6), this.darkMat);
      leg.position.set(x, 0.21, z);
      g.add(leg);
      this.legs.push(leg);
    }

    // corruption shards along the spine
    for (let i = 0; i < 3; i++) {
      const shard = new THREE.Mesh(new THREE.OctahedronGeometry(0.11 - i * 0.02), crystalMat);
      shard.position.set(0, 0.85 - i * 0.04, 0.18 - i * 0.3);
      shard.scale.y = 2.0;
      shard.rotation.z = (i - 1) * 0.25;
      shard.userData.noOutline = true;
      g.add(shard);
    }

    const tail = new THREE.Mesh(new THREE.ConeGeometry(0.07, 0.4, 5), this.darkMat);
    tail.position.set(0, 0.6, -0.62);
    tail.rotation.x = -1.1;
    g.add(tail);

    addOutline(g, { thickness: 0.05 });
  }

  // ------------------------------------------------------------------
  hit(dmg, controller) {
    if (this.dead) return;
    this.health -= dmg;
    this.flashT = 0.12;
    Sfx.hitEnemy();
    this.aggro = true;
    if (this.health <= 0) {
      this.state = "dying";
      this.stateT = 0;
      Sfx.enemyDie();
    } else if (this.state !== "lunge") {
      // flinch knockback away from the attacker
      const away = this.position.clone().sub(controller.position).setY(0).normalize();
      this.position.addScaledVector(away, 0.35);
    }
  }

  _detectionRadius(controller, passives) {
    let r = BASE_DETECT * passives.detectionMult();
    if (controller.isSneaking()) {
      r *= 0.5;
      r *= 2 - controller.stats.skillBonus("Sneak", 0.025); // Sneak skill shrinks it further
    }
    return Math.max(2.5, r);
  }

  update(dt, { controller, passives }) {
    if (this.dead) return;
    this.t += dt;
    this.stateT += dt;
    this.flashT = Math.max(0, this.flashT - dt);

    // hit flash
    const flash = this.flashT > 0;
    this.furMat.color.set(flash ? "#ffffff" : "#564a6b");
    this.darkMat.color.set(flash ? "#ffffff" : "#3c3450");

    const playerPos = controller.position;
    const toPlayer = playerPos.clone().sub(this.position).setY(0);
    const dist = toPlayer.length();

    switch (this.state) {
      case "roam": {
        this.wanderTimer -= dt;
        if (this.wanderTimer <= 0) {
          this.wanderTimer = 2.5 + Math.random() * 3;
          const a = Math.random() * Math.PI * 2;
          this.wanderTarget.set(
            this.home.x + Math.cos(a) * 6,
            0,
            this.home.z + Math.sin(a) * 6
          );
        }
        const toT = this.wanderTarget.clone().sub(this.position).setY(0);
        if (toT.length() > 0.5) {
          toT.normalize();
          this.position.addScaledVector(toT, 1.25 * dt);
          this._face(toT, dt, 4);
        }
        if (this.aggro || dist < this._detectionRadius(controller, passives)) {
          this.aggro = true;
          this.state = "chase";
          this.stateT = 0;
        }
        break;
      }
      case "chase": {
        if (dist > 1.95) {
          toPlayer.normalize();
          this.position.addScaledVector(toPlayer, 4.9 * dt);
          this._face(toPlayer, dt, 8);
        } else {
          this.state = "windup";
          this.stateT = 0;
        }
        break;
      }
      case "windup": {
        this._face(toPlayer.normalize(), dt, 10);
        this.group.scale.y = 1 - Math.min(0.25, this.stateT * 0.7); // crouch coil
        if (this.stateT > 0.42) {
          this.state = "lunge";
          this.stateT = 0;
          this.group.scale.y = 1;
          this.lungeDir.copy(toPlayer).normalize();
          this.lungeHitDone = false;
        }
        break;
      }
      case "lunge": {
        this.position.addScaledVector(this.lungeDir, 9.5 * dt);
        if (!this.lungeHitDone && dist < 1.25) {
          this.lungeHitDone = true;
          controller.stats.takeDamage(13);
          Sfx.hurt();
        }
        if (this.stateT > 0.34) {
          this.state = "recover";
          this.stateT = 0;
        }
        break;
      }
      case "recover": {
        if (this.stateT > 0.75) {
          this.state = "chase";
          this.stateT = 0;
        }
        break;
      }
      case "dying": {
        this.group.scale.multiplyScalar(Math.max(0.001, 1 - dt * 2.4));
        this.group.rotation.z += dt * 3;
        if (this.stateT > 0.9) {
          this.dead = true;
          this.group.visible = false;
          bus.emit("combat:enemyDown", {});
        }
        return;
      }
    }

    // stick to terrain + run bob
    const ground = this.scene.getHeight(this.position.x, this.position.z);
    const moving = this.state === "chase" || this.state === "lunge" || this.state === "roam";
    this.position.y = ground;
    this.group.position.copy(this.position);
    this.group.position.y += moving ? Math.abs(Math.sin(this.t * 9)) * 0.08 : 0;
    this.group.rotation.y = this.facing;

    // leg scuttle
    for (let i = 0; i < this.legs.length; i++) {
      this.legs[i].rotation.x = moving ? Math.sin(this.t * 11 + i * 1.7) * 0.5 : 0;
    }
    // crystal pulse — angrier when aggro
    const pulse = this.aggro ? 1.2 + Math.sin(this.t * 9) * 0.45 : 0.85 + Math.sin(this.t * 3) * 0.15;
    this.crystalMat.color.set("#ff2336").multiplyScalar(pulse);
  }

  _face(dir, dt, rate) {
    const target = Math.atan2(dir.x, dir.z);
    let d = target - this.facing;
    while (d > Math.PI) d -= Math.PI * 2;
    while (d < -Math.PI) d += Math.PI * 2;
    this.facing += d * Math.min(1, dt * rate);
  }
}
