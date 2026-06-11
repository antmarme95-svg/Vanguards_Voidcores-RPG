// Inverted-hull outlines: every outlined mesh gets a slightly inflated
// back-face shell as a child, so it inherits all transforms (including the
// live phenotype scaling). Cheap, stylized, ports to a Godot shader pass.

import * as THREE from "three";

const outlineMaterialCache = new Map();

function getOutlineMaterial(color) {
  const key = String(color);
  if (!outlineMaterialCache.has(key)) {
    outlineMaterialCache.set(
      key,
      new THREE.MeshBasicMaterial({ color, side: THREE.BackSide, toneMapped: false })
    );
  }
  return outlineMaterialCache.get(key);
}

export function addOutline(target, { thickness = 0.035, color = 0x07090c } = {}) {
  const targets = [];
  target.traverse((obj) => {
    if (obj.isMesh && !obj.userData.isOutline && !obj.userData.noOutline) targets.push(obj);
  });
  for (const mesh of targets) {
    const shell = new THREE.Mesh(mesh.geometry, getOutlineMaterial(color));
    shell.userData.isOutline = true;
    shell.raycast = () => {};
    shell.scale.setScalar(1 + thickness);
    mesh.add(shell);
  }
  return target;
}

export function removeOutlines(target) {
  const trash = [];
  target.traverse((obj) => {
    if (obj.userData.isOutline) trash.push(obj);
  });
  for (const shell of trash) shell.parent?.remove(shell);
}
