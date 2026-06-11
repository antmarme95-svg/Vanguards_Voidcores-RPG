// Recruiter dialogue trees + Conqueror's Contract text, per origin.
// Node shape: { speaker, text, choices: [{label, next}] } or { speaker, text, next }
// Special node actions: "openContract" (show the parchment), "end" (close dialogue, open doors).

export function buildRecruiterDialogue(origin, playerName) {
  const r = origin.recruiter.name;
  const city = origin.city.name;
  const rival = origin.rival;

  const flavor = {
    aetherborn: {
      greet: `Ah! A pulse, ambulatory, and only mildly singed — you must be ${playerName}. Welcome to the Office of Profitable Curiosity. Sit. Don't touch the orb. The last applicant touched the orb and now he is the orb.`,
      contract: `The Conqueror's Contract, standard charter, eleven pages, four of which are legally load-bearing. ${city} claims survey rights over the frontier below us. You go down there, you plant our sigil on anything interesting, and you do not die in a way that embarrasses the Academy.`,
      outside: `The Wilds. Gorgeous. Lethal. The old gods died out there and left their Cores rotting in the ground — red crystal, screaming with residual divinity. Everything that grazes near one goes feral. We want them purged, catalogued, and ideally invoiced.`,
      pay: `Pay! Yes. Salvage rights, hazard stipend, and a posthumous citation if it comes to that. The Iron Tribunal of the Craters pays their mercs more, allegedly, but their healthcare plan is 'walk it off into the lava.'`,
      signed: `Splendid penmanship. Barely any blood. The deployment doors are open — the descent platform will drop you at the frontier gate. Do try to come back with all your original limbs. Or better ones.`,
    },
    ironblooded: {
      greet: `${playerName}! Good. You're upright and you didn't salute the coat rack like the last one. I'm ${r}. This is Conscription and Quenching. We forge soldiers here. Sometimes literally — don't lean on the red anvil.`,
      contract: `Conqueror's Contract. One page. We respect your time. The Craters claim the frontier ridge and every vein of aether under it. You march out, you break what's hostile, you stamp our seal on what's left. Clean work.`,
      outside: `Dead gods, kid. Their Cores stick out of the ground like shrapnel from a war the world lost. Red glow, bad hum. Beasts that breathe near one go mad — all teeth, no fear. The Tribunal wants every Core on our border shattered before some sky-academic 'studies' it onto our doorstep.`,
      pay: `Pay's in iron-script, spendable anywhere with a forge. Bonus per Core purged. The Archlectors of Zephyr-Academica will try to buy you out at double — that's because their mercs keep falling off the city. Their words: 'gravity-related attrition.'`,
      signed: `Ink's dry, soldier. The gate's open and the frontier's downhill — everything is downhill from here, it's a volcano. Hit hard, come home, first round's on the Division.`,
    },
    miststalker: {
      greet: `Mm. ${playerName}. You walk loud for someone with your résumé — we'll fix that. I'm Quill. This is the Acquisitions Desk. The parenthetical is load-bearing: don't ask. Tea? It's only slightly stolen.`,
      contract: `The Conqueror's Contract — the Docks' polite name for 'finders keepers, at scale.' The syndicate claims salvage over the fogline frontier. You slip out there, mark territory, pocket what shines, and the ribcage we all live in stays fed.`,
      outside: `Out past the fog the dead gods left their hearts in the dirt. Cores — red, loud, wrong. Animals that den near one come back rabid and glowing at the seams. Bad for trade routes. Worse for the animals. We're sentimental about exactly one of those things.`,
      pay: `Cut of salvage, no questions on provenance, and the Docks forget three crimes of your choosing. The Gilded Concord of Free Captains will wave fatter purses at you — Concord coin is real, but so are Concord exit interviews. Conducted off a pier.`,
      signed: `There it is. Signed, sealed, deniable. Door's open, frontier's through the fog — follow the green lamps, ignore anything that follows you. Bring me something shiny, ${playerName}.`,
    },
  }[origin.id];

  return {
    start: "greet",
    nodes: {
      greet: {
        speaker: r,
        text: flavor.greet,
        next: "hub",
      },
      hub: {
        speaker: r,
        text: `So. Questions, or ink? The frontier isn't getting any tamer while you stand there.`,
        choices: [
          { label: "What exactly am I signing?", next: "loreContract" },
          { label: "What's waiting outside the walls?", next: "loreOutside" },
          { label: "Let's talk pay.", next: "lorePay" },
          { label: "Give me the pen.", next: "openContract" },
        ],
      },
      loreContract: { speaker: r, text: flavor.contract, next: "hub" },
      loreOutside: { speaker: r, text: flavor.outside, next: "hub" },
      lorePay: { speaker: r, text: flavor.pay, next: "hub" },
      openContract: { speaker: r, text: `Smart. Read fast, sign faster.`, action: "openContract" },
      signed: { speaker: r, text: flavor.signed, action: "end" },
    },
  };
}

export function getContractClauses(origin, playerName) {
  const city = origin.city.name;
  return [
    {
      h: "ARTICLE I — THE PARTIES",
      body: `This Conqueror's Contract binds the free mercenary <b>${playerName}</b> (hereafter "the Asset") to the sovereign power of <b>${city}</b> (hereafter "the Crown-Equivalent"), in pursuit of the pacification, survey, and profitable exploitation of the untamed continent (hereafter "The Wilds").`,
    },
    {
      h: "ARTICLE II — THE WORK",
      body: `The Asset shall venture beyond the secure border, locate crystalline remnants designated <b>Cores of the Dead Gods</b>, and render each site inert by purge, shatter, or sanctioned harvest. Creatures maddened by Core resonance are considered <b>pre-approved for violence</b>.`,
    },
    {
      h: "ARTICLE III — COMPENSATION",
      body: `Salvage rights, hazard stipend, and per-Core bounty as scheduled. The Crown-Equivalent is not liable for curses, possession, prophetic dreams, or limbs replaced by superior arcano-mechanical alternatives.`,
    },
    {
      h: "ARTICLE IV — LOYALTY (ASPIRATIONAL)",
      body: `The Asset shall not treat with rival powers, including but not limited to <b>${origin.rival}</b>. The Crown-Equivalent acknowledges this clause is historically the least respected article in mercenary law and has priced your betrayal in accordingly.`,
    },
    {
      h: "ARTICLE V — TERMINATION",
      body: `This contract ends upon: completion of conquest, death of the Asset (verified twice), or the Asset going rogue — at which point the Asset becomes a line item in a different, angrier document.`,
    },
  ];
}
