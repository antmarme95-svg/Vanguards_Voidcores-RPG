// Canvas-generated head texture: flat cel skin base + sharp warpaint strokes.
// The head sphere's UV face region sits around u=0.5; patterns paint there.

import * as THREE from "three";

const W = 512;
const H = 256;

// Face strip in UV space (sphere: u wraps horizontally, v bottom→top).
const FACE = { x0: 0.34 * W, x1: 0.66 * W, yEye: 0.46 * H, yBrow: 0.38 * H, yChin: 0.72 * H };
const CX = 0.5 * W;

const PATTERNS = {
  0: () => {}, // None

  // Slash Crimson — three hard diagonal slashes across the right eye line
  1: (g) => {
    g.lineWidth = 9;
    for (let i = 0; i < 3; i++) {
      const x = CX + 14 + i * 22;
      g.beginPath();
      g.moveTo(x - 26, FACE.yBrow - 14);
      g.lineTo(x + 6, FACE.yChin - 18);
      g.stroke();
    }
  },

  // Hexbrand — arcane hexagon on the forehead with a drop line to the nose
  2: (g) => {
    const cy = FACE.yBrow - 16;
    const r = 17;
    g.lineWidth = 6;
    g.beginPath();
    for (let i = 0; i <= 6; i++) {
      const a = (i / 6) * Math.PI * 2 + Math.PI / 6;
      const px = CX + Math.cos(a) * r;
      const py = cy + Math.sin(a) * r * 0.9;
      i === 0 ? g.moveTo(px, py) : g.lineTo(px, py);
    }
    g.stroke();
    g.beginPath();
    g.moveTo(CX, cy + r);
    g.lineTo(CX, FACE.yEye + 24);
    g.stroke();
  },

  // Tribal Tide — stacked wave hooks on both cheeks
  3: (g) => {
    g.lineWidth = 7;
    for (const side of [-1, 1]) {
      for (let i = 0; i < 3; i++) {
        const bx = CX + side * (38 + i * 6);
        const by = FACE.yEye + 16 + i * 14;
        g.beginPath();
        g.moveTo(bx, by);
        g.quadraticCurveTo(bx + side * 22, by - 10, bx + side * 30, by + 8);
        g.stroke();
      }
    }
  },

  // Eye of Ash — one solid band across both eyes
  4: (g) => {
    g.fillRect(FACE.x0, FACE.yEye - 16, FACE.x1 - FACE.x0, 32);
  },

  // Jagged Crown — zigzag across the forehead
  5: (g) => {
    g.lineWidth = 8;
    g.beginPath();
    const y0 = FACE.yBrow - 8;
    let x = FACE.x0 + 8;
    g.moveTo(x, y0);
    let up = true;
    while (x < FACE.x1 - 8) {
      x += 16;
      g.lineTo(x, up ? y0 - 22 : y0);
      up = !up;
    }
    g.stroke();
  },
};

export function buildHeadTexture({ skinHex, warpaintIndex = 0, paintHex = "#46e6ff" }) {
  const canvas = document.createElement("canvas");
  canvas.width = W;
  canvas.height = H;
  const g = canvas.getContext("2d");

  g.fillStyle = skinHex;
  g.fillRect(0, 0, W, H);

  // faint cel cheek shading (hard-edged, no gradient — keeps the anime read)
  g.fillStyle = "rgba(0,0,0,0.07)";
  g.fillRect(0, 0.78 * H, W, 0.22 * H);

  const pattern = PATTERNS[warpaintIndex] ?? PATTERNS[0];
  g.strokeStyle = paintHex;
  g.fillStyle = paintHex;
  g.lineCap = "round";
  pattern(g);

  const tex = new THREE.CanvasTexture(canvas);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = 4;
  return tex;
}
