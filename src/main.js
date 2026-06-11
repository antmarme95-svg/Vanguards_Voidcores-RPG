// BORISAWA — boot, render loop, and debug fast-forward hooks.

import * as THREE from "three";
import { GameDirector } from "./core/GameDirector.js";
import { bus } from "./core/EventBus.js";
import { getOrigin } from "./data/origins.js";

// ---- renderer ----
const renderer = new THREE.WebGLRenderer({ antialias: true });
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.outputColorSpace = THREE.SRGBColorSpace;
document.getElementById("app").appendChild(renderer.domElement);

const camera = new THREE.PerspectiveCamera(50, window.innerWidth / window.innerHeight, 0.1, 700);

window.addEventListener("resize", () => {
  camera.aspect = window.innerWidth / window.innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(window.innerWidth, window.innerHeight);
});

// ---- game ----
const director = new GameDirector({
  renderer,
  camera,
  uiRoot: document.getElementById("ui-root"),
});

director.start();

// ---- debug / test fast-forward: ?origin=aetherborn&cls=mage&name=Test&skip=office|exit|wilds ----
const params = new URLSearchParams(location.search);
if (params.has("origin")) {
  const origin = getOrigin(params.get("origin"));
  if (origin) {
    const save = director.save;
    save.originId = origin.id;
    save.classId = params.get("cls") ?? "warrior";
    save.name = params.get("name") ?? origin.defaultName;
    director.rig.applyPhenotype(save.phenotype, origin);
    director.stage?.setTheme(origin);
    director.creationUI?.setAccent(origin.theme.accent);

    const skip = params.get("skip");
    if (skip === "office") {
      director.fsm.go("OFFICE");
    } else if (skip === "exit") {
      director.fsm.go("OFFICE");
      director.fsm.go("CITY_EXIT");
    } else if (skip === "wilds") {
      director.fsm.go("OFFICE");
      director.fsm.go("WILDS");
    }
  }
}

window.__BORISAWA = { director, bus, THREE };

// ---- loop ----
// rAF when visible; setTimeout fallback keeps the sim alive in hidden tabs
// (headless previews, background testing).
const clock = new THREE.Clock();
let booted = false;

function render() {
  const scene = director.activeThreeScene();
  if (scene) {
    renderer.render(scene, camera);
    if (!booted) {
      booted = true;
      document.getElementById("boot-screen").classList.add("hidden");
    }
  }
}

function frame() {
  if (document.hidden) {
    // background timers are throttled to ~1Hz — sub-step so sim time keeps
    // tracking real time (matters for automated testing, costs nothing live)
    setTimeout(frame, 33);
    const elapsed = clock.getDelta();
    const steps = Math.min(40, Math.max(1, Math.round(elapsed / 0.033)));
    for (let i = 0; i < steps; i++) director.update(0.033);
    render();
  } else {
    requestAnimationFrame(frame);
    director.update(Math.min(clock.getDelta(), 0.05));
    render();
  }
}
frame();
