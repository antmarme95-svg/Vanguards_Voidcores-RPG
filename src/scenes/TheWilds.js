// The Wilds — the untamed frontier. Rolling toon terrain, swaying grass,
// and a red Core of the Dead Gods bleeding madness into the local wildlife.

import * as THREE from "three";
import { toonMat, glowMat, flatMat, addWindSway, tickWind } from "../rendering/ToonMaterials.js";
import { skyDome, particles, tree, rock } from "./props.js";

const SIZE = 220;
const CORE_POS = { x: 8, z: -42 };
const SPAWN = { x: 0, z: 88 };

// deterministic placement
function mulberry32(seed) {
  return function () {
    seed |= 0; seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const smooth = (t) => t * t * (3 - 2 * t);

function rawHeight(x, z) {
  return (
    2.4 * Math.sin(x * 0.042 + 0.7) * Math.cos(z * 0.036) +
    1.2 * Math.sin(x * 0.09 + 2.1) * Math.sin(z * 0.075 + 1.2) +
    0.45 * Math.sin(x * 0.21) * Math.cos(z * 0.19 + 0.5)
  );
}

function flatten(h, x, z, cx, cz, r, hc) {
  const d = Math.hypot(x - cx, z - cz);
  if (d >= r) return h;
  return THREE.MathUtils.lerp(hc, h, smooth(d / r));
}

export function terrainHeight(x, z) {
  let h = rawHeight(x, z);
  h = flatten(h, x, z, SPAWN.x, SPAWN.z, 16, 0.4);
  h = flatten(h, x, z, CORE_POS.x, CORE_POS.z, 20, 0.7);
  return h;
}

const GRASS_PATCHES = [
  { x: 0, z: 64, r: 13 },
  { x: -15, z: 36, r: 15 },
  { x: 12, z: 12, r: 16 },
  { x: -8, z: -14, r: 14 },
  { x: 24, z: -32, r: 12 },
  { x: -18, z: -50, r: 13 },
];

export class TheWilds {
  constructor(origin) {
    this.origin = origin;
    const scene = (this.scene = new THREE.Scene());
    scene.fog = new THREE.Fog(0xbfe3d4, 60, 230);
    scene.add(skyDome("#3f9fe8", "#bfe3d4"));

    this.t = 0;
    this.coreAlive = true;
    this.coreDying = false;
    this.windMats = [];

    this._buildTerrain();
    this._buildGrass();
    this._buildFlora();
    this._buildCoreSite();
    this._buildSkyDressing();

    scene.add(new THREE.HemisphereLight(0xbfe8ff, 0x4a7a3f, 0.95));
    const sun = new THREE.DirectionalLight(0xfff2d8, 2.1);
    sun.position.set(-40, 70, 30);
    scene.add(sun);

    // ---- gameplay metadata ----
    const sy = terrainHeight(SPAWN.x, SPAWN.z);
    this.playerSpawn = { position: new THREE.Vector3(SPAWN.x, sy, SPAWN.z), yaw: Math.PI };
    this.corePosition = new THREE.Vector3(CORE_POS.x, terrainHeight(CORE_POS.x, CORE_POS.z), CORE_POS.z);
    this.enemySpawns = [
      new THREE.Vector3(2, 0, -32),
      new THREE.Vector3(18, 0, -38),
      new THREE.Vector3(8, 0, -52),
    ].map((v) => { v.y = terrainHeight(v.x, v.z); return v; });

    this.triggers = [
      { id: "coreSight", position: this.corePosition.clone(), radius: 42, fired: false },
      { id: "encounterStart", position: this.corePosition.clone(), radius: 26, fired: false },
    ];
    this.interactables = [
      {
        id: "core",
        label: "Shatter the Core",
        position: this.corePosition.clone().add(new THREE.Vector3(0, 1, 0)),
        radius: 3.2,
        enabled: false,
      },
    ];
  }

  // ------------------------------------------------------------------
  _buildTerrain() {
    const seg = 110;
    const geo = new THREE.PlaneGeometry(SIZE, SIZE, seg, seg);
    geo.rotateX(-Math.PI / 2);
    const pos = geo.attributes.position;
    const colors = [];
    const cGrass = new THREE.Color("#56b04a");
    const cLush = new THREE.Color("#3f9e4f");
    const cDry = new THREE.Color("#8fae4e");
    const cScorch = new THREE.Color("#4a3434");
    const c = new THREE.Color();
    for (let i = 0; i < pos.count; i++) {
      const x = pos.getX(i), z = pos.getZ(i);
      const h = terrainHeight(x, z);
      pos.setY(i, h);
      const n = (Math.sin(x * 0.5) * Math.cos(z * 0.45) + 1) / 2;
      c.copy(cLush).lerp(n > 0.6 ? cDry : cGrass, Math.abs(n - 0.5) * 1.6);
      // corruption stain around the core
      const dCore = Math.hypot(x - CORE_POS.x, z - CORE_POS.z);
      if (dCore < 13) c.lerp(cScorch, 1 - smooth(dCore / 13));
      colors.push(c.r, c.g, c.b);
    }
    geo.setAttribute("color", new THREE.Float32BufferAttribute(colors, 3));
    geo.computeVertexNormals();
    const mat = toonMat(0xffffff, { vertexColors: true });
    this.terrain = new THREE.Mesh(geo, mat);
    this.scene.add(this.terrain);
  }

  _buildGrass() {
    const rand = mulberry32(1337);
    const blade = new THREE.PlaneGeometry(0.1, 0.62, 1, 2);
    blade.translate(0, 0.31, 0);
    const mat = toonMat("#4fae47", { side: THREE.DoubleSide });
    addWindSway(mat, { amplitude: 0.16, speed: 2.4 });
    this.windMats.push(mat);

    const COUNT = 2400;
    const grass = new THREE.InstancedMesh(blade, mat, COUNT);
    grass.userData.noOutline = true;
    const dummy = new THREE.Object3D();
    const col = new THREE.Color();
    const greens = ["#4fae47", "#63c24f", "#3f9e4f", "#7fc46a"];
    let i = 0;
    while (i < COUNT) {
      const patch = GRASS_PATCHES[Math.floor(rand() * GRASS_PATCHES.length)];
      const a = rand() * Math.PI * 2;
      const d = Math.sqrt(rand()) * patch.r;
      const x = patch.x + Math.cos(a) * d;
      const z = patch.z + Math.sin(a) * d;
      dummy.position.set(x, terrainHeight(x, z), z);
      dummy.rotation.y = rand() * Math.PI;
      const s = 0.75 + rand() * 0.7;
      dummy.scale.set(s, s, s);
      dummy.updateMatrix();
      grass.setMatrixAt(i, dummy.matrix);
      grass.setColorAt(i, col.set(greens[Math.floor(rand() * greens.length)]));
      i++;
    }
    grass.instanceMatrix.needsUpdate = true;
    if (grass.instanceColor) grass.instanceColor.needsUpdate = true;
    this.scene.add(grass);
  }

  _buildFlora() {
    const rand = mulberry32(777);
    this.obstacles = []; // {x, z, r} cylinders for collision
    for (let i = 0; i < 38; i++) {
      const a = rand() * Math.PI * 2;
      const d = 24 + rand() * 78;
      const x = Math.cos(a) * d;
      const z = Math.sin(a) * d * 0.95 + 10;
      // keep the spawn→core route readable
      if (Math.hypot(x - CORE_POS.x, z - CORE_POS.z) < 16) continue;
      if (Math.abs(x) < 7 && z > -30 && z < 95) continue;
      const s = 0.8 + rand() * 0.9;
      const t = tree(s);
      t.position.set(x, terrainHeight(x, z) - 0.1, z);
      this.scene.add(t);
      this.obstacles.push({ x, z, r: 0.45 * s });
    }
    for (let i = 0; i < 22; i++) {
      const a = rand() * Math.PI * 2;
      const d = 14 + rand() * 88;
      const x = Math.cos(a) * d;
      const z = Math.sin(a) * d;
      const s = 0.7 + rand() * 1.8;
      const r = rock(s);
      r.position.set(x, terrainHeight(x, z) + 0.1, z);
      this.scene.add(r);
      if (s > 1.2) this.obstacles.push({ x, z, r: 0.5 * s });
    }
  }

  _buildCoreSite() {
    const { x, z } = CORE_POS;
    const y = terrainHeight(x, z);
    const g = (this.coreGroup = new THREE.Group());
    g.position.set(x, y, z);

    this.coreMat = glowMat("#ff2336", 1.0);
    this.crystals = [];
    const defs = [
      [0, 0, 0, 1.9, 0, 0],
      [1.4, -0.6, 0.2, 1.2, 0.5, 0.3],
      [-1.2, 0.8, 0.1, 1.35, -0.45, -0.2],
      [0.6, 1.3, 0.15, 0.95, 0.3, -0.5],
      [-0.7, -1.2, 0.1, 1.1, -0.25, 0.45],
    ];
    for (const [cx, cz, , s, rx, rz] of defs) {
      const cr = new THREE.Mesh(new THREE.OctahedronGeometry(0.7), this.coreMat);
      cr.scale.set(s * 0.55, s * 1.9, s * 0.55);
      cr.position.set(cx, s * 1.1, cz);
      cr.rotation.set(rx, 0, rz);
      cr.userData.noOutline = true;
      g.add(cr);
      this.crystals.push(cr);
    }
    // shard ring
    const shardMat = glowMat("#a8141f", 0.9);
    for (let i = 0; i < 9; i++) {
      const a = (i / 9) * Math.PI * 2;
      const sh = new THREE.Mesh(new THREE.OctahedronGeometry(0.16), shardMat);
      sh.scale.y = 2.2;
      sh.position.set(Math.cos(a) * 3.6, 0.3, Math.sin(a) * 3.6);
      sh.rotation.z = Math.cos(a) * 0.5;
      sh.userData.noOutline = true;
      g.add(sh);
      this.crystals.push(sh);
    }

    this.coreLight = new THREE.PointLight(0xff2336, 90, 45);
    this.coreLight.position.y = 2.5;
    g.add(this.coreLight);

    this.corruptionMotes = particles(90, 0xff3344, 22, 0.09, 7);
    g.add(this.corruptionMotes);

    this.scene.add(g);
  }

  _buildSkyDressing() {
    this.clouds = new THREE.Group();
    const rand = mulberry32(42);
    const cloudMat = flatMat("#ffffff", { fog: false, transparent: true, opacity: 0.92 });
    for (let i = 0; i < 9; i++) {
      const cl = new THREE.Group();
      for (let b = 0; b < 3; b++) {
        const blob = new THREE.Mesh(new THREE.SphereGeometry(5 + rand() * 7, 10, 8), cloudMat);
        blob.scale.y = 0.32;
        blob.position.set(b * 7 - 7 + rand() * 4, rand() * 2, rand() * 5);
        blob.userData.noOutline = true;
        cl.add(blob);
      }
      cl.position.set(-160 + rand() * 320, 55 + rand() * 28, -160 + rand() * 320);
      cl.userData.speed = 0.5 + rand() * 0.7;
      this.clouds.add(cl);
    }
    this.scene.add(this.clouds);
    this.scene.add(particles(120, 0x9fe8ff, 160, 0.1, 24));
  }

  // ------------------------------------------------------------------
  getHeight(x, z) {
    return terrainHeight(x, z);
  }

  clampPosition(pos) {
    const r = Math.hypot(pos.x, pos.z);
    const MAX = 102;
    if (r > MAX) {
      pos.x *= MAX / r;
      pos.z *= MAX / r;
    }
    // tree/boulder push-out
    for (const o of this.obstacles) {
      const dx = pos.x - o.x, dz = pos.z - o.z;
      const d = Math.hypot(dx, dz);
      const minD = o.r + 0.34;
      if (d < minD && d > 0.0001) {
        pos.x = o.x + (dx / d) * minD;
        pos.z = o.z + (dz / d) * minD;
      }
    }
  }

  isInGrass(pos) {
    for (const p of GRASS_PATCHES) {
      if (Math.hypot(pos.x - p.x, pos.z - p.z) < p.r) return true;
    }
    return false;
  }

  setCoreInteractable(on) {
    const core = this.interactables.find((i) => i.id === "core");
    if (core) core.enabled = on && this.coreAlive;
  }

  destroyCore() {
    this.coreDying = true;
    this.setCoreInteractable(false);
  }

  update(dt) {
    this.t += dt;
    tickWind(this.windMats, this.t);

    for (const cl of this.clouds.children) {
      cl.position.x += dt * cl.userData.speed;
      if (cl.position.x > 180) cl.position.x = -180;
    }

    if (this.coreAlive) {
      const pulse = 0.8 + Math.sin(this.t * 3.2) * 0.25 + Math.sin(this.t * 7.7) * 0.08;
      this.coreMat.color.set("#ff2336").multiplyScalar(pulse);
      this.coreLight.intensity = 70 + pulse * 30;
      this.coreGroup.rotation.y += dt * 0.05;
      this.corruptionMotes.rotation.y -= dt * 0.1;

      if (this.coreDying) {
        let gone = true;
        for (const cr of this.crystals) {
          cr.scale.multiplyScalar(Math.max(0, 1 - dt * 2.2));
          if (cr.scale.y > 0.04) gone = false;
        }
        this.coreLight.intensity *= Math.max(0, 1 - dt * 2);
        this.corruptionMotes.material.opacity *= Math.max(0, 1 - dt * 2);
        if (gone) {
          this.coreAlive = false;
          this.coreGroup.visible = false;
          this.coreLight.intensity = 0;
        }
      }
    }
  }
}
