// Shared procedural prop kit — every scene assembles from these builders.

import * as THREE from "three";
import { toonMat, glowMat, flatMat } from "../rendering/ToonMaterials.js";
import { addOutline } from "../rendering/OutlinePass.js";

export function room({ w = 12, h = 4.6, d = 10, floor, wall, trim }) {
  const g = new THREE.Group();
  const floorMesh = new THREE.Mesh(new THREE.BoxGeometry(w, 0.2, d), toonMat(floor));
  floorMesh.position.y = -0.1;
  g.add(floorMesh);

  const wallMat = toonMat(wall);
  const mk = (bw, bd, x, z) => {
    const m = new THREE.Mesh(new THREE.BoxGeometry(bw, h, bd), wallMat);
    m.position.set(x, h / 2, z);
    g.add(m);
    return m;
  };
  mk(w, 0.25, 0, -d / 2);            // back
  mk(0.25, d, -w / 2, 0);            // left
  mk(0.25, d, w / 2, 0);             // right
  // front wall with a 2.4-wide door gap in the middle
  mk(w / 2 - 1.2, 0.25, -(w / 4 + 0.6), d / 2);
  mk(w / 2 - 1.2, 0.25, w / 4 + 0.6, d / 2);
  const lintel = new THREE.Mesh(new THREE.BoxGeometry(2.4, h - 2.7, 0.25), wallMat);
  lintel.position.set(0, 2.7 + (h - 2.7) / 2, d / 2);
  g.add(lintel);

  const ceil = new THREE.Mesh(new THREE.BoxGeometry(w, 0.2, d), toonMat(trim));
  ceil.position.y = h + 0.1;
  g.add(ceil);
  return g;
}

export function slidingDoors(color, glowColor) {
  const g = new THREE.Group();
  const mat = toonMat(color);
  for (const side of [-1, 1]) {
    const panel = new THREE.Mesh(new THREE.BoxGeometry(1.2, 2.7, 0.12), mat);
    panel.position.set(side * 0.6, 1.35, 0);
    const seam = new THREE.Mesh(new THREE.BoxGeometry(0.05, 2.5, 0.13), glowMat(glowColor, 0.9));
    seam.position.set(side * 0.06, 1.35, 0.0);
    seam.userData.noOutline = true;
    panel.add(seam);
    seam.position.x = -side * 0.55;
    g.add(panel);
    panel.userData.side = side;
  }
  g.userData.open = 0; // 0 closed → 1 open
  g.userData.tick = (dt, opening) => {
    const u = g.userData;
    u.open = THREE.MathUtils.clamp(u.open + (opening ? dt : -dt) * 0.9, 0, 1);
    for (const panel of g.children) {
      panel.position.x = panel.userData.side * (0.6 + u.open * 1.15);
    }
  };
  addOutline(g, { thickness: 0.04 });
  return g;
}

export function aetherPipe(points, glowColor, radius = 0.06) {
  const curve = new THREE.CatmullRomCurve3(points.map((p) => new THREE.Vector3(...p)));
  const tube = new THREE.Mesh(new THREE.TubeGeometry(curve, 32, radius, 7), glowMat(glowColor, 0.85));
  tube.userData.noOutline = true;
  const shellMat = toonMat("#2b3038");
  const joints = new THREE.Group();
  for (const p of points) {
    const j = new THREE.Mesh(new THREE.CylinderGeometry(radius * 1.9, radius * 1.9, 0.12, 8), shellMat);
    j.position.set(...p);
    joints.add(j);
  }
  const g = new THREE.Group();
  g.add(tube, joints);
  return g;
}

export function crystalLamp(color, height = 2.1) {
  const g = new THREE.Group();
  const post = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.07, height, 7), toonMat("#3a3f4a"));
  post.position.y = height / 2;
  const crystal = new THREE.Mesh(new THREE.OctahedronGeometry(0.16), glowMat(color, 1.1));
  crystal.position.y = height + 0.18;
  crystal.userData.noOutline = true;
  const cage = new THREE.Mesh(new THREE.TorusGeometry(0.2, 0.018, 6, 10), toonMat("#3a3f4a"));
  cage.position.y = height + 0.18;
  cage.rotation.x = Math.PI / 2;
  g.add(post, crystal, cage);
  g.userData.crystal = crystal;
  return g;
}

const SIGIL_DRAW = {
  skyland: (g, c) => { // floating eye-spire
    g.beginPath(); g.moveTo(64, 22); g.lineTo(96, 95); g.lineTo(32, 95); g.closePath(); g.stroke();
    g.beginPath(); g.arc(64, 70, 14, 0, Math.PI * 2); g.stroke();
  },
  forge: (g) => { // hammer over gear
    g.beginPath(); g.arc(64, 70, 26, 0, Math.PI * 2); g.stroke();
    g.fillRect(56, 20, 16, 56);
    g.fillRect(40, 20, 48, 14);
  },
  docks: (g) => { // fang and hook
    g.beginPath(); g.moveTo(45, 25); g.quadraticCurveTo(70, 60, 50, 100); g.stroke();
    g.beginPath(); g.moveTo(80, 25); g.quadraticCurveTo(60, 60, 84, 100); g.stroke();
  },
};

export function banner(theme) {
  const canvas = document.createElement("canvas");
  canvas.width = 128; canvas.height = 192;
  const g = canvas.getContext("2d");
  g.fillStyle = "#181c24";
  g.fillRect(0, 0, 128, 192);
  g.strokeStyle = theme.accent;
  g.fillStyle = theme.accent;
  g.lineWidth = 7;
  g.lineCap = "round";
  g.save();
  g.translate(0, 28);
  (SIGIL_DRAW[theme.propSet] ?? SIGIL_DRAW.skyland)(g);
  g.restore();
  g.strokeStyle = theme.accent;
  g.lineWidth = 4;
  g.strokeRect(8, 8, 112, 176);

  const tex = new THREE.CanvasTexture(canvas);
  tex.colorSpace = THREE.SRGBColorSpace;
  const mesh = new THREE.Mesh(new THREE.PlaneGeometry(0.85, 1.3), flatMat("#ffffff", { map: tex }));
  mesh.userData.noOutline = true;
  const rod = new THREE.Mesh(new THREE.CylinderGeometry(0.025, 0.025, 1.0, 6), toonMat("#3a3f4a"));
  rod.rotation.z = Math.PI / 2;
  rod.position.y = 0.7;
  const grp = new THREE.Group();
  grp.add(mesh, rod);
  return grp;
}

export function spinGear(radius, color) {
  const g = new THREE.Group();
  const mat = toonMat(color);
  const ring = new THREE.Mesh(new THREE.TorusGeometry(radius, radius * 0.18, 8, 18), mat);
  g.add(ring);
  for (let i = 0; i < 8; i++) {
    const a = (i / 8) * Math.PI * 2;
    const tooth = new THREE.Mesh(new THREE.BoxGeometry(radius * 0.22, radius * 0.3, radius * 0.18), mat);
    tooth.position.set(Math.cos(a) * radius * 1.18, Math.sin(a) * radius * 1.18, 0);
    tooth.rotation.z = a;
    g.add(tooth);
    const spoke = new THREE.Mesh(new THREE.BoxGeometry(radius * 0.08, radius * 1.9, radius * 0.08), mat);
    if (i < 3) {
      spoke.rotation.z = a;
      g.add(spoke);
    }
  }
  g.userData.spin = 0.4;
  return g;
}

export function floatingCrystal(color, size = 0.22) {
  const c = new THREE.Mesh(new THREE.OctahedronGeometry(size), glowMat(color, 1.0));
  c.userData.noOutline = true;
  c.userData.bobSeed = Math.random() * Math.PI * 2;
  return c;
}

export function crateStack(accent) {
  const g = new THREE.Group();
  const mat = toonMat("#6e5a40");
  const mk = (s, x, y, z, ry) => {
    const m = new THREE.Mesh(new THREE.BoxGeometry(s, s, s), mat);
    m.position.set(x, y + s / 2, z);
    m.rotation.y = ry;
    g.add(m);
  };
  mk(0.62, 0, 0, 0, 0.1);
  mk(0.62, 0.7, 0, 0.1, -0.2);
  mk(0.5, 0.3, 0.62, 0.05, 0.35);
  const rope = new THREE.Mesh(new THREE.TorusGeometry(0.3, 0.06, 6, 12), toonMat("#8a7a55"));
  rope.rotation.x = Math.PI / 2;
  rope.position.set(-0.7, 0.07, 0.4);
  g.add(rope);
  return g;
}

export function bookStack() {
  const g = new THREE.Group();
  const colors = ["#7a3b3b", "#3b5a7a", "#4a6e3b", "#6e5a8a"];
  let y = 0;
  for (let i = 0; i < 4; i++) {
    const h = 0.05 + Math.random() * 0.03;
    const b = new THREE.Mesh(new THREE.BoxGeometry(0.3 - i * 0.03, h, 0.22), toonMat(colors[i % colors.length]));
    b.position.set((Math.random() - 0.5) * 0.05, y + h / 2, 0);
    b.rotation.y = (Math.random() - 0.5) * 0.5;
    g.add(b);
    y += h;
  }
  return g;
}

export function ribArc(radius, color) {
  const rib = new THREE.Mesh(
    new THREE.TorusGeometry(radius, radius * 0.07, 7, 22, Math.PI),
    toonMat(color)
  );
  return rib;
}

export function tree(scale = 1) {
  const g = new THREE.Group();
  const trunk = new THREE.Mesh(new THREE.CylinderGeometry(0.18 * scale, 0.28 * scale, 2.4 * scale, 7), toonMat("#5a4030"));
  trunk.position.y = 1.2 * scale;
  g.add(trunk);
  const greens = ["#3f9e4f", "#2e8a4a", "#55b04e"];
  for (let i = 0; i < 3; i++) {
    const blob = new THREE.Mesh(
      new THREE.IcosahedronGeometry((1.0 - i * 0.22) * scale, 0),
      toonMat(greens[i % 3])
    );
    blob.position.set((Math.random() - 0.5) * 0.5 * scale, (2.4 + i * 0.75) * scale, (Math.random() - 0.5) * 0.5 * scale);
    blob.rotation.set(Math.random(), Math.random(), Math.random());
    g.add(blob);
  }
  addOutline(g, { thickness: 0.045 });
  return g;
}

export function rock(scale = 1) {
  const m = new THREE.Mesh(new THREE.IcosahedronGeometry(0.5 * scale, 0), toonMat("#8d9499"));
  m.scale.set(1, 0.7 + Math.random() * 0.4, 1);
  m.rotation.set(Math.random(), Math.random(), Math.random());
  addOutline(m, { thickness: 0.045 });
  return m;
}

export function skyDome(topColor, horizonColor, radius = 400) {
  const geo = new THREE.SphereGeometry(radius, 24, 16);
  const top = new THREE.Color(topColor);
  const hor = new THREE.Color(horizonColor);
  const colors = [];
  const pos = geo.attributes.position;
  const c = new THREE.Color();
  for (let i = 0; i < pos.count; i++) {
    const t = THREE.MathUtils.clamp(pos.getY(i) / radius, 0, 1);
    c.copy(hor).lerp(top, Math.pow(t, 0.65));
    colors.push(c.r, c.g, c.b);
  }
  geo.setAttribute("color", new THREE.Float32BufferAttribute(colors, 3));
  const mat = new THREE.MeshBasicMaterial({ vertexColors: true, side: THREE.BackSide, fog: false, toneMapped: false });
  return new THREE.Mesh(geo, mat);
}

export function particles(count, color, spread, size = 0.05, ySpread = null) {
  const positions = new Float32Array(count * 3);
  for (let i = 0; i < count; i++) {
    positions[i * 3] = (Math.random() - 0.5) * spread;
    positions[i * 3 + 1] = Math.random() * (ySpread ?? spread * 0.5);
    positions[i * 3 + 2] = (Math.random() - 0.5) * spread;
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute("position", new THREE.BufferAttribute(positions, 3));
  const mat = new THREE.PointsMaterial({ color, size, transparent: true, opacity: 0.8, toneMapped: false });
  const pts = new THREE.Points(geo, mat);
  pts.userData.noOutline = true;
  return pts;
}
