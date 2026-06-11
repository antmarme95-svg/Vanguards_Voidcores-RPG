// Tiny WebAudio synth — zero-asset sound effects with an aetherpunk timbre.

let ctx = null;

function ac() {
  if (!ctx) ctx = new (window.AudioContext || window.webkitAudioContext)();
  if (ctx.state === "suspended") ctx.resume();
  return ctx;
}

function tone({ freq = 440, end = null, dur = 0.12, type = "square", vol = 0.08, delay = 0 }) {
  try {
    const a = ac();
    const t0 = a.currentTime + delay;
    const osc = a.createOscillator();
    const gain = a.createGain();
    osc.type = type;
    osc.frequency.setValueAtTime(freq, t0);
    if (end) osc.frequency.exponentialRampToValueAtTime(end, t0 + dur);
    gain.gain.setValueAtTime(vol, t0);
    gain.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
    osc.connect(gain).connect(a.destination);
    osc.start(t0);
    osc.stop(t0 + dur + 0.02);
  } catch {
    /* audio blocked until user gesture — fine */
  }
}

function noise({ dur = 0.15, vol = 0.06, delay = 0, low = false }) {
  try {
    const a = ac();
    const t0 = a.currentTime + delay;
    const len = Math.floor(a.sampleRate * dur);
    const buf = a.createBuffer(1, len, a.sampleRate);
    const data = buf.getChannelData(0);
    for (let i = 0; i < len; i++) data[i] = (Math.random() * 2 - 1) * (1 - i / len);
    const src = a.createBufferSource();
    src.buffer = buf;
    const gain = a.createGain();
    gain.gain.setValueAtTime(vol, t0);
    gain.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
    let node = src;
    if (low) {
      const f = a.createBiquadFilter();
      f.type = "lowpass";
      f.frequency.value = 700;
      src.connect(f);
      node = f;
    }
    node.connect(gain).connect(a.destination);
    src.start(t0);
  } catch { /* ignore */ }
}

export const Sfx = {
  uiClick: () => tone({ freq: 720, end: 980, dur: 0.06, type: "triangle", vol: 0.05 }),
  uiTab: () => tone({ freq: 460, end: 620, dur: 0.07, type: "triangle", vol: 0.05 }),
  swing: () => noise({ dur: 0.12, vol: 0.07 }),
  cast: () => tone({ freq: 320, end: 1400, dur: 0.18, type: "sawtooth", vol: 0.05 }),
  arrow: () => { noise({ dur: 0.07, vol: 0.05 }); tone({ freq: 900, end: 1500, dur: 0.08, type: "sine", vol: 0.03 }); },
  hitEnemy: () => { tone({ freq: 220, end: 120, dur: 0.1, type: "square", vol: 0.07 }); noise({ dur: 0.08, vol: 0.05 }); },
  enemyDie: () => { tone({ freq: 280, end: 60, dur: 0.4, type: "sawtooth", vol: 0.07 }); noise({ dur: 0.3, vol: 0.06, low: true }); },
  hurt: () => tone({ freq: 160, end: 80, dur: 0.22, type: "square", vol: 0.09 }),
  jump: () => tone({ freq: 300, end: 520, dur: 0.1, type: "triangle", vol: 0.04 }),
  sign: () => { noise({ dur: 0.25, vol: 0.04 }); tone({ freq: 520, end: 780, dur: 0.3, type: "sine", vol: 0.05, delay: 0.22 }); },
  doors: () => { noise({ dur: 0.5, vol: 0.05, low: true }); tone({ freq: 140, end: 200, dur: 0.5, type: "sine", vol: 0.05 }); },
  quest: () => { tone({ freq: 660, dur: 0.1, type: "triangle", vol: 0.06 }); tone({ freq: 880, dur: 0.16, type: "triangle", vol: 0.06, delay: 0.1 }); },
  coreShatter: () => {
    noise({ dur: 0.6, vol: 0.1 });
    tone({ freq: 1200, end: 90, dur: 0.7, type: "sawtooth", vol: 0.08 });
    tone({ freq: 70, end: 40, dur: 0.9, type: "sine", vol: 0.1, delay: 0.1 });
  },
  choice: () => {
    tone({ freq: 440, dur: 0.14, type: "triangle", vol: 0.06 });
    tone({ freq: 554, dur: 0.14, type: "triangle", vol: 0.06, delay: 0.12 });
    tone({ freq: 660, dur: 0.26, type: "triangle", vol: 0.07, delay: 0.24 });
  },
};
