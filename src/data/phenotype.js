// Phenotype slider/pick definitions. The UI is generated from this table and
// CharacterRig.applyPhenotype consumes the same ids — single source of truth.

export const HAIR_STYLES = [
  "Wyld Mane", "Norse Braids", "Elven Topknot", "Pompadour Undercut", "Ash Spikes",
  "Curtain Long", "War Mohawk", "Twin Tails", "Shorn Scout", "Drake Dreads",
];

export const BEARD_STYLES = ["Clean", "Stubble", "Braided Jarl", "Goatee"];

export const WARPAINTS = ["None", "Slash Crimson", "Hexbrand", "Tribal Tide", "Eye of Ash", "Jagged Crown"];

// kind: "float" → slider 0..1   |   "pick" → button grid index   |   "color" → swatch index
export const PHENOTYPE_FIELDS = [
  // --- BODY & TECH ---
  { id: "weight", label: "Weight / Muscle", kind: "float", tab: "body", section: "Frame", default: 0.5,
    hint: "lean & wiry ↔ bulky & heavy" },
  { id: "height", label: "Height", kind: "float", tab: "body", section: "Frame", default: 0.5,
    hint: "scaled within your origin's range" },
  { id: "arcaneMod", label: "Arcane Modification", kind: "float", tab: "body", section: "Technomancy", default: 0.25,
    hint: "glowing mana veins → prosthetic aether limb" },
  { id: "skinTone", label: "Skin Tone", kind: "color", tab: "body", section: "Skin", default: 1, paletteKey: "skin" },

  // --- HEAD & FACE ---
  { id: "jaw", label: "Jaw Definition", kind: "float", tab: "face", section: "Structure", default: 0.5 },
  { id: "cheek", label: "Cheekbone Height", kind: "float", tab: "face", section: "Structure", default: 0.5 },
  { id: "eyeTilt", label: "Eye Tilt", kind: "float", tab: "face", section: "Structure", default: 0.5 },
  { id: "eyeShape", label: "Eye Shape", kind: "float", tab: "face", section: "Structure", default: 0.5,
    hint: "narrow glare ↔ wide anime" },

  // --- STYLIZED AESTHETICS ---
  { id: "hair", label: "Hair", kind: "pick", tab: "face", section: "Hair & Beard", default: 0, options: HAIR_STYLES },
  { id: "beard", label: "Beard", kind: "pick", tab: "face", section: "Hair & Beard", default: 0, options: BEARD_STYLES },
  { id: "hairColor", label: "Hair Color", kind: "color", tab: "face", section: "Hair & Beard", default: 2, paletteKey: "hair" },
  { id: "warpaint", label: "Warpaint", kind: "pick", tab: "face", section: "Warpaint & Ink", default: 0, options: WARPAINTS },
  { id: "paintColor", label: "Paint Color", kind: "color", tab: "face", section: "Warpaint & Ink", default: 0, paletteKey: "paint" },
];

export function defaultPhenotype() {
  const p = {};
  for (const f of PHENOTYPE_FIELDS) p[f.id] = f.default;
  return p;
}
