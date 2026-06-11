// Third-person player controller: BotW-flavored movement (sprint/stamina,
// jump, crouch-sneak), pointer-lock camera orbit, and class-flavored attacks.

import * as THREE from "three";
import { bus } from "../core/EventBus.js";
import { Sfx } from "../core/Sfx.js";
import { glowMat } from "../rendering/ToonMaterials.js";

const WALK = 3.3;
const SPRINT = 6.6;
const CROUCH = 1.9;
const GRAVITY = 24;
const JUMP_V = 8.4;

export class PlayerController {
  constructor({ rig, camera, stats, passives, save, dom }) {
    this.rig = rig;
    this.camera = camera;
    this.stats = stats;
    this.passives = passives;
    this.save = save;
    this.dom = dom;

    this._enabled = false;
    this.scene = null;
    this.enemies = [];

    this.position = new THREE.Vector3();
    this.velY = 0;
    this.grounded = true;
    this.crouching = false;
    this.sprinting = false;
    this.moveSpeedNorm = 0;
    this.camYaw = Math.PI;
    this.camPitch = 0.32;
    this.camDist = 4.4;
    this.facing = Math.PI;
    this.attackCooldown = 0;
    this.projectiles = [];

    this.keys = new Set();
    this._locked = false;
    this._bindInput();

    // Expose enabled as a setter so the hint can react when gameplay starts.
    Object.defineProperty(this, "enabled", {
      get: () => this._enabled,
      set: (v) => {
        this._enabled = v;
        this._updateHint();
      },
    });
  }

  _updateHint() {
    const hint = this.dom.parentElement?.querySelector(".pointer-hint");
    if (hint) hint.classList.toggle("visible", this._enabled && !this._locked);
  }

  _bindInput() {
    window.addEventListener("keydown", (e) => {
      if (e.repeat) return;
      this.keys.add(e.code);
      if (!this.enabled) return;
      if (e.code === "KeyC") this.crouching = !this.crouching;
      if (e.code === "KeyN") this.passives.toggleNightVision();
      if (e.code === "KeyF") this.tryAttack();
      if (e.code === "Space") e.preventDefault();
    });
    window.addEventListener("keyup", (e) => this.keys.delete(e.code));
    window.addEventListener("blur", () => this.keys.clear());

    // Click canvas to enter pointer lock; click while locked to attack.
    this.dom.addEventListener("mousedown", (e) => {
      if (!this.enabled) return;
      if (!this._locked) {
        this.dom.requestPointerLock();
      } else if (e.button === 0) {
        this.tryAttack();
      }
    });

    document.addEventListener("pointerlockchange", () => {
      this._locked = document.pointerLockElement === this.dom;
      this.dom.classList.toggle("locked", this._locked);
      this._updateHint();
    });

    window.addEventListener("mousemove", (e) => {
      if (!this._locked || !this.enabled) return;
      this.camYaw -= e.movementX * 0.0052;
      this.camPitch = THREE.MathUtils.clamp(this.camPitch + e.movementY * 0.0045, -0.25, 1.25);
    });

    this.dom.addEventListener("wheel", (e) => {
      if (!this.enabled) return;
      this.camDist = THREE.MathUtils.clamp(this.camDist + e.deltaY * 0.0035, 2.4, 8);
    }, { passive: true });
  }

  // ------------------------------------------------------------------
  setScene(scene, { keepEnemies = false } = {}) {
    if (this.scene && this.rig.group.parent) this.rig.group.parent.remove(this.rig.group);
    for (const p of this.projectiles) p.mesh.parent?.remove(p.mesh);
    this.projectiles = [];
    if (!keepEnemies) this.enemies = [];

    this.scene = scene;
    scene.scene.add(this.rig.group);
    const spawn = scene.playerSpawn;
    this.position.copy(spawn.position);
    this.velY = 0;
    this.facing = spawn.yaw;
    this.camYaw = spawn.yaw + Math.PI; // camera sits behind the player
    this.camPitch = 0.3;
    this.rig.group.position.copy(this.position);
    this.rig.group.rotation.y = this.facing;
    this.syncCamera(1);
  }

  isSneaking() {
    return this.crouching;
  }

  // ------------------------------------------------------------------
  tryAttack() {
    if (!this.enabled || this.attackCooldown > 0) return;
    const combat = this.save.charClass?.combat;
    if (!combat) return;

    if (combat.style === "bolt") {
      if (!this.stats.spendMagicka(combat.magickaCost)) return;
      this.attackCooldown = combat.cooldown * this.passives.castCooldownMult();
      this.rig.playAttack("bolt");
      Sfx.cast();
      this._spawnProjectile(combat, "#7adfff", 0.13);
    } else if (combat.style === "arrow") {
      if (!this.stats.spendStamina(combat.staminaCost)) return;
      this.attackCooldown = combat.cooldown;
      this.rig.playAttack("melee");
      Sfx.arrow();
      this._spawnProjectile(combat, "#d8e8c8", 0.05, true);
    } else {
      if (!this.stats.spendStamina(combat.staminaCost)) return;
      this.attackCooldown = combat.cooldown * this.passives.attackCooldownMult();
      this.rig.playAttack("melee");
      Sfx.swing();
      this._meleeHit(combat);
    }
  }

  _attackDamage(combat) {
    let dmg = combat.damage * this.stats.skillBonus(combat.keySkill);
    return dmg;
  }

  _meleeHit(combat) {
    const fwd = new THREE.Vector3(Math.sin(this.facing), 0, Math.cos(this.facing));
    const cosArc = Math.cos((combat.arcDeg * Math.PI) / 360);
    for (const enemy of this.enemies) {
      if (enemy.dead) continue;
      const to = enemy.position.clone().sub(this.position);
      to.y = 0;
      const d = to.length();
      if (d > combat.range) continue;
      to.normalize();
      if (to.dot(fwd) < cosArc && d > 0.7) continue;
      enemy.hit(this._attackDamage(combat), this);
    }
  }

  _spawnProjectile(combat, color, size, isArrow = false) {
    // fire along the camera look direction (slight pitch influence)
    const fwd = new THREE.Vector3(
      -Math.sin(this.camYaw),
      -Math.sin(this.camPitch) * 0.35,
      -Math.cos(this.camYaw)
    ).normalize();
    this.facing = Math.atan2(fwd.x, fwd.z);

    let mesh;
    if (isArrow) {
      mesh = new THREE.Mesh(new THREE.CylinderGeometry(0.018, 0.018, 0.55, 5), glowMat(color, 0.9));
      mesh.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), fwd);
    } else {
      mesh = new THREE.Mesh(new THREE.SphereGeometry(size, 8, 7), glowMat(color, 1.3));
    }
    mesh.userData.noOutline = true;
    mesh.position.copy(this.position).add(new THREE.Vector3(0, 1.35, 0)).addScaledVector(fwd, 0.6);
    this.scene.scene.add(mesh);
    this.projectiles.push({
      mesh,
      vel: fwd.multiplyScalar(combat.projectileSpeed),
      life: 2.4,
      damage: this._attackDamage(combat),
      combat,
      sneakShot: this.crouching,
    });
  }

  _updateProjectiles(dt) {
    for (let i = this.projectiles.length - 1; i >= 0; i--) {
      const p = this.projectiles[i];
      p.life -= dt;
      p.mesh.position.addScaledVector(p.vel, dt);
      let kill = p.life <= 0;
      if (!kill && this.scene.getHeight && p.mesh.position.y < this.scene.getHeight(p.mesh.position.x, p.mesh.position.z)) {
        kill = true;
      }
      if (!kill) {
        for (const enemy of this.enemies) {
          if (enemy.dead) continue;
          const dxz = Math.hypot(enemy.position.x - p.mesh.position.x, enemy.position.z - p.mesh.position.z);
          const dy = Math.abs(enemy.position.y + 0.55 - p.mesh.position.y);
          if (dxz < 0.95 && dy < 1.5) {
            let dmg = p.damage;
            if (p.sneakShot && !enemy.aggro && p.combat.sneakMultiplier) {
              dmg *= p.combat.sneakMultiplier;
              bus.emit("quest:toast", { text: "Sneak strike!" });
            }
            enemy.hit(dmg, this);
            kill = true;
            break;
          }
        }
      }
      if (kill) {
        this.scene.scene.remove(p.mesh);
        this.projectiles.splice(i, 1);
      }
    }
  }

  // ------------------------------------------------------------------
  nearestInteractable() {
    if (!this.scene?.interactables) return null;
    let best = null;
    let bestD = Infinity;
    for (const it of this.scene.interactables) {
      if (!it.enabled) continue;
      const d = Math.hypot(it.position.x - this.position.x, it.position.z - this.position.z) - it.radius;
      if (d < 0 && d < bestD) {
        bestD = d;
        best = it;
      }
    }
    return best;
  }

  checkTriggers() {
    if (!this.scene?.triggers) return null;
    for (const tr of this.scene.triggers) {
      if (tr.fired) continue;
      if (tr.position.distanceTo(this.position) < tr.radius) {
        tr.fired = true;
        return tr;
      }
    }
    return null;
  }

  // ------------------------------------------------------------------
  update(dt) {
    if (!this.scene) return;
    this.attackCooldown = Math.max(0, this.attackCooldown - dt);

    // ---- input → planar velocity ----
    let ix = 0, iz = 0;
    if (this.enabled) {
      if (this.keys.has("KeyW") || this.keys.has("ArrowUp")) iz -= 1;
      if (this.keys.has("KeyS") || this.keys.has("ArrowDown")) iz += 1;
      if (this.keys.has("KeyA") || this.keys.has("ArrowLeft")) ix -= 1;
      if (this.keys.has("KeyD") || this.keys.has("ArrowRight")) ix += 1;
    }
    const moving = ix !== 0 || iz !== 0;
    const wantSprint = this.keys.has("ShiftLeft") || this.keys.has("ShiftRight");

    this.sprinting = false;
    let speed = this.crouching ? CROUCH : WALK;
    if (moving && wantSprint && !this.crouching && this.stats.drainStamina(15, dt)) {
      speed = SPRINT;
      this.sprinting = true;
    }
    const inGrass = this.scene.isInGrass?.(this.position) ?? false;
    speed *= this.passives.grassSpeedMult(inGrass);

    if (moving) {
      const len = Math.hypot(ix, iz);
      ix /= len; iz /= len;
      const sin = Math.sin(this.camYaw), cos = Math.cos(this.camYaw);
      // camera-relative: camera forward = (-sin, -cos), camera right = (cos, -sin)
      const wx = iz * sin + ix * cos;
      const wz = iz * cos - ix * sin;
      this.position.x += wx * speed * dt;
      this.position.z += wz * speed * dt;
      const targetFacing = Math.atan2(wx, wz);
      let d = targetFacing - this.facing;
      while (d > Math.PI) d -= Math.PI * 2;
      while (d < -Math.PI) d += Math.PI * 2;
      this.facing += d * Math.min(1, dt * 14);
    }
    this.moveSpeedNorm = moving ? speed / SPRINT : 0;

    // ---- aetherborn overclock (held) ----
    this.passives.setOverclock(this.enabled && this.keys.has("KeyQ"), dt);

    // ---- vertical ----
    const ground = this.scene.getHeight(this.position.x, this.position.z);
    if (this.enabled && this.grounded && this.keys.has("Space") && this.stats.spendStamina(7)) {
      this.velY = JUMP_V;
      this.grounded = false;
      this.keys.delete("Space");
      Sfx.jump();
    }
    this.velY -= GRAVITY * dt;
    this.position.y += this.velY * dt;
    if (this.position.y <= ground) {
      this.position.y = ground;
      this.velY = 0;
      this.grounded = true;
    }

    this.scene.clampPosition?.(this.position);

    // ---- rig + camera ----
    this.rig.group.position.copy(this.position);
    this.rig.group.rotation.y = this.facing;
    this.rig.setMotion({ speed: this.moveSpeedNorm, crouch: this.crouching });
    this.rig.update(dt);

    this._updateProjectiles(dt);
    this.stats.update(dt);
    this.syncCamera(Math.min(1, dt * 7));
  }

  syncCamera(blend) {
    const headY = 1.5 * this.rig.group.scale.y;
    const target = this.position.clone().add(new THREE.Vector3(0, headY, 0));
    const cp = Math.cos(this.camPitch), sp = Math.sin(this.camPitch);
    const desired = new THREE.Vector3(
      target.x + Math.sin(this.camYaw) * cp * this.camDist,
      target.y + sp * this.camDist,
      target.z + Math.cos(this.camYaw) * cp * this.camDist
    );
    if (this.scene?.getHeight) {
      const minY = this.scene.getHeight(desired.x, desired.z) + 0.35;
      if (desired.y < minY) desired.y = minY;
    }
    this.scene?.clampCamera?.(desired);
    this.camera.position.lerp(desired, blend);
    this.camera.lookAt(target);
  }
}
