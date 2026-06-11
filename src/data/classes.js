// Class tables. Base attributes 100, base skills 15, Skyrim-style bonuses.

export const BASE_ATTRIBUTE = 100;
export const BASE_SKILL = 15;

export const SKILL_LIST = [
  "Two-Handed", "One-Handed", "Block", "Heavy Armor", "Smithing",
  "Destruction", "Restoration", "Illusion", "Conjuration", "Alchemy",
  "Sneak", "Lockpicking", "Light Armor", "Archery", "Pickpocket",
];

export const CLASSES = [
  {
    id: "warrior",
    name: "Warrior",
    tag: "Background: Pit-Forged Soldier",
    desc: "You hit things until the contract is fulfilled. The continent respects this approach more than it admits.",
    attributes: { health: 130, magicka: 90, stamina: 110 },
    skillBonuses: { "Two-Handed": 10, "One-Handed": 5, "Block": 5, "Heavy Armor": 5, "Smithing": 5 },
    combat: {
      style: "melee",
      weaponName: "Aether-Quenched Greatblade",
      damage: 34,
      range: 2.6,
      arcDeg: 110,
      cooldown: 0.65,
      staminaCost: 12,
      keySkill: "Two-Handed",
    },
  },
  {
    id: "mage",
    name: "Mage",
    tag: "Background: Unlicensed Evoker",
    desc: "Reality is a suggestion and you argue loudly. Fire support, self-mending, and occasional property damage.",
    attributes: { health: 90, magicka: 140, stamina: 90 },
    skillBonuses: { "Destruction": 10, "Restoration": 5, "Illusion": 5, "Conjuration": 5, "Alchemy": 5 },
    combat: {
      style: "bolt",
      weaponName: "Destruction Bolt",
      damage: 26,
      projectileSpeed: 26,
      cooldown: 0.55,
      magickaCost: 14,
      keySkill: "Destruction",
    },
  },
  {
    id: "thief",
    name: "Thief",
    tag: "Background: Contract Ghost",
    desc: "Doors are optional, witnesses are negotiable. Strikes from the tall grass and bills by the hour.",
    attributes: { health: 100, magicka: 100, stamina: 120 },
    skillBonuses: { "Sneak": 10, "Lockpicking": 5, "Light Armor": 5, "Archery": 5, "Pickpocket": 5 },
    combat: {
      style: "arrow",
      weaponName: "Whisperwind Shortbow",
      damage: 20,
      projectileSpeed: 38,
      cooldown: 0.45,
      staminaCost: 8,
      sneakMultiplier: 2.5,
      keySkill: "Archery",
    },
  },
];

export function getClass(id) {
  return CLASSES.find((c) => c.id === id) ?? null;
}
