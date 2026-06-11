// 10 anime-stylized hairstyles + 4 beards, built from primitives around a
// skull of radius ~0.15 centered at the head group origin.

import * as THREE from "three";

const R = 0.15;

function mesh(geo, mat, x = 0, y = 0, z = 0, rx = 0, ry = 0, rz = 0, s = 1) {
  const m = new THREE.Mesh(geo, mat);
  m.position.set(x, y, z);
  m.rotation.set(rx, ry, rz);
  if (s !== 1) m.scale.setScalar(s);
  return m;
}

function cap(mat, scale = 1.06, yScale = 1.0) {
  // skull-hugging hair shell, open at the face
  // (sphere phi gap 0.38π..0.62π faces +z already — the face direction)
  const geo = new THREE.SphereGeometry(R * scale, 18, 14, Math.PI * 0.62, Math.PI * 1.76, 0, Math.PI * 0.62);
  const m = new THREE.Mesh(geo, mat);
  m.scale.y = yScale;
  return m;
}

function braid(mat, segments, x, y, z, dirX, dirY, dirZ, startR = 0.035) {
  const g = new THREE.Group();
  let px = x, py = y, pz = z, r = startR;
  for (let i = 0; i < segments; i++) {
    g.add(mesh(new THREE.SphereGeometry(r, 8, 7), mat, px, py, pz));
    px += dirX; py += dirY; pz += dirZ;
    r *= 0.88;
  }
  return g;
}

export const HAIR_BUILDERS = [
  // 0 — Wyld Mane: explosive spiky mass
  (mat) => {
    const g = new THREE.Group();
    g.add(cap(mat, 1.1));
    for (let i = 0; i < 10; i++) {
      const a = (i / 10) * Math.PI * 2;
      const tilt = 0.5 + (i % 3) * 0.35;
      const spike = mesh(
        new THREE.ConeGeometry(0.045, 0.16 + (i % 4) * 0.05, 6),
        mat,
        Math.cos(a) * R * 0.72,
        0.1 + (i % 2) * 0.05,
        Math.sin(a) * R * 0.72 - 0.03
      );
      spike.lookAt(Math.cos(a) * 2, 1.4 + tilt, Math.sin(a) * 2 - 0.06);
      spike.rotateX(Math.PI / 2);
      g.add(spike);
    }
    return g;
  },

  // 1 — Norse Braids: cap + twin side braids + back braid
  (mat) => {
    const g = new THREE.Group();
    g.add(cap(mat, 1.07));
    g.add(braid(mat, 5, R * 0.85, -0.02, 0.02, 0.004, -0.05, -0.004));
    g.add(braid(mat, 5, -R * 0.85, -0.02, 0.02, -0.004, -0.05, -0.004));
    g.add(braid(mat, 6, 0, 0.06, -R * 0.92, 0, -0.052, -0.012, 0.042));
    return g;
  },

  // 2 — Elven Topknot: sleek cap + high bun + thin tail
  (mat) => {
    const g = new THREE.Group();
    g.add(cap(mat, 1.045));
    g.add(mesh(new THREE.SphereGeometry(0.06, 10, 8), mat, 0, R * 1.12, -0.02));
    g.add(braid(mat, 5, 0, R * 1.05, -0.07, 0, -0.045, -0.028, 0.026));
    return g;
  },

  // 3 — Pompadour Undercut: shaved sides, big front swoosh
  (mat) => {
    const g = new THREE.Group();
    g.add(cap(mat, 1.02, 0.92));
    const swoosh = mesh(new THREE.SphereGeometry(0.095, 12, 10), mat, 0, R * 0.78, R * 0.5);
    swoosh.scale.set(1.15, 0.78, 1.25);
    g.add(swoosh);
    return g;
  },

  // 4 — Ash Spikes: short cap with upward shards
  (mat) => {
    const g = new THREE.Group();
    g.add(cap(mat, 1.05));
    for (let i = 0; i < 6; i++) {
      const a = (i / 6) * Math.PI * 2 + 0.3;
      g.add(
        mesh(new THREE.ConeGeometry(0.035, 0.13, 5), mat,
          Math.cos(a) * R * 0.5, R * 0.95, Math.sin(a) * R * 0.5 - 0.02,
          (Math.random() - 0.5) * 0.4, 0, (Math.random() - 0.5) * 0.4)
      );
    }
    return g;
  },

  // 5 — Curtain Long: cap + flat panels falling to the shoulders
  (mat) => {
    const g = new THREE.Group();
    g.add(cap(mat, 1.06));
    const panel = new THREE.BoxGeometry(0.07, 0.34, 0.045);
    g.add(mesh(panel, mat, R * 0.82, -0.13, 0.015, 0, 0, 0.08));
    g.add(mesh(panel, mat, -R * 0.82, -0.13, 0.015, 0, 0, -0.08));
    const back = mesh(new THREE.BoxGeometry(0.22, 0.36, 0.06), mat, 0, -0.1, -R * 0.85);
    g.add(back);
    return g;
  },

  // 6 — War Mohawk: shaved shell + center fin
  (mat) => {
    const g = new THREE.Group();
    g.add(cap(mat, 1.015, 0.9));
    for (let i = 0; i < 5; i++) {
      const z = R * 0.7 - i * 0.07;
      g.add(mesh(new THREE.ConeGeometry(0.032, 0.17 - i * 0.012, 4), mat, 0, R * 0.92 + 0.02, z));
    }
    return g;
  },

  // 7 — Twin Tails: cap + two long side tails
  (mat) => {
    const g = new THREE.Group();
    g.add(cap(mat, 1.05));
    g.add(braid(mat, 7, R * 0.95, 0.02, -0.03, 0.012, -0.055, -0.01, 0.04));
    g.add(braid(mat, 7, -R * 0.95, 0.02, -0.03, -0.012, -0.055, -0.01, 0.04));
    return g;
  },

  // 8 — Shorn Scout: tight buzz shell
  (mat) => {
    const g = new THREE.Group();
    g.add(cap(mat, 1.012, 0.96));
    return g;
  },

  // 9 — Drake Dreads: cap + heavy hanging ropes
  (mat) => {
    const g = new THREE.Group();
    g.add(cap(mat, 1.07));
    for (let i = 0; i < 7; i++) {
      const a = Math.PI * (0.6 + (i / 6) * 0.8); // back arc
      const x = Math.cos(a) * R * 0.85;
      const z = Math.sin(a) * -R * 0.85;
      g.add(mesh(new THREE.CylinderGeometry(0.022, 0.016, 0.3, 6), mat, x, -0.1, z, 0.12, 0, x * 0.6));
    }
    return g;
  },
];

export const BEARD_BUILDERS = [
  // 0 — Clean
  () => new THREE.Group(),

  // 1 — Stubble: dark thin jaw shell (phi centered on +z = the face)
  (mat) => {
    const g = new THREE.Group();
    const shell = mesh(
      new THREE.SphereGeometry(R * 0.92, 14, 10, Math.PI * 0.25, Math.PI * 0.5, Math.PI * 0.52, Math.PI * 0.34),
      mat, 0, -0.035, 0.012
    );
    shell.material = mat.clone();
    shell.material.transparent = true;
    shell.material.opacity = 0.45;
    g.add(shell);
    return g;
  },

  // 2 — Braided Jarl: full chin mass + hanging braid
  (mat) => {
    const g = new THREE.Group();
    const chin = mesh(new THREE.SphereGeometry(0.075, 10, 8), mat, 0, -R * 0.78, R * 0.5);
    chin.scale.set(1.25, 0.9, 0.9);
    g.add(chin);
    g.add(braid(mat, 4, 0, -R * 1.05, R * 0.55, 0, -0.045, -0.008, 0.034));
    return g;
  },

  // 3 — Goatee: sharp little cone
  (mat) => {
    const g = new THREE.Group();
    g.add(mesh(new THREE.ConeGeometry(0.04, 0.09, 6), mat, 0, -R * 0.95, R * 0.55, Math.PI, 0, 0));
    return g;
  },
];
