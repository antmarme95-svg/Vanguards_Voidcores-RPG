// Cel-shading material factory. One shared stepped gradient map drives every
// MeshToonMaterial so the whole world lights with the same banding.
// Godot port note: this whole module becomes a single toon .gdshader.

import * as THREE from "three";
import { TOON_RAMP_STEPS } from "../data/palette.js";

let _gradientMap = null;

export function getGradientMap() {
  if (_gradientMap) return _gradientMap;
  const steps = TOON_RAMP_STEPS;
  const data = new Uint8Array(steps.length * 4);
  steps.forEach((s, i) => {
    const v = Math.round(s * 255);
    data.set([v, v, v, 255], i * 4);
  });
  _gradientMap = new THREE.DataTexture(data, steps.length, 1, THREE.RGBAFormat);
  _gradientMap.minFilter = THREE.NearestFilter;
  _gradientMap.magFilter = THREE.NearestFilter;
  _gradientMap.generateMipmaps = false;
  _gradientMap.needsUpdate = true;
  return _gradientMap;
}

export function toonMat(color, opts = {}) {
  return new THREE.MeshToonMaterial({
    color,
    gradientMap: getGradientMap(),
    ...opts,
  });
}

// Unlit "glow" — reads as emissive neon without a bloom pass.
export function glowMat(color, intensity = 1) {
  const c = new THREE.Color(color).multiplyScalar(intensity);
  return new THREE.MeshBasicMaterial({ color: c, toneMapped: false });
}

// Flat unlit color (skyboxes, backdrops, decal planes).
export function flatMat(color, opts = {}) {
  return new THREE.MeshBasicMaterial({ color, ...opts });
}

// Injects a cheap wind sway into any material's vertex stage (instanced grass).
// Sway strength comes from the green channel of vertex color (tips sway, roots don't).
export function addWindSway(material, { amplitude = 0.18, speed = 2.2 } = {}) {
  material.userData.windUniforms = { uTime: { value: 0 } };
  material.onBeforeCompile = (shader) => {
    shader.uniforms.uTime = material.userData.windUniforms.uTime;
    shader.vertexShader = shader.vertexShader
      .replace(
        "#include <common>",
        `#include <common>\nuniform float uTime;`
      )
      .replace(
        "#include <begin_vertex>",
        `#include <begin_vertex>
        {
          #ifdef USE_INSTANCING
            vec4 wpos = instanceMatrix * vec4(transformed, 1.0);
          #else
            vec4 wpos = vec4(transformed, 1.0);
          #endif
          float sway = sin(uTime * ${speed.toFixed(2)} + wpos.x * 0.8 + wpos.z * 0.6);
          float tip = clamp(transformed.y, 0.0, 1.5);
          transformed.x += sway * ${amplitude.toFixed(3)} * tip;
        }`
      );
  };
  return material;
}

export function tickWind(materials, t) {
  for (const m of materials) {
    if (m.userData.windUniforms) m.userData.windUniforms.uTime.value = t;
  }
}
