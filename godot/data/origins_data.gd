# Origin factions — direct port of src/data/origins.js.
class_name OriginsData extends RefCounted

const ORIGINS: Array[Dictionary] = [
	{
		"id": "aetherborn",
		"name": "Aether-Born",
		"tag": "High-Tech Elven Mage Lineage",
		"lore": "Heirs of the sky-archives. Their blood runs hot with raw mana and unpaid library fines.",
		"defaultName": "Vessari",
		"passive": {
			"id": "manaOverload",
			"name": "Mana-Overload",
			"desc": "Hold Q to overclock casting speed at the cost of draining stamina. +50 permanent Magicka.",
			"attributeMods": {"magicka": 50},
			"hint": "Q — OVERCLOCK",
		},
		"city": {
			"name": "Zephyr-Academica",
			"desc": "A levitating skyland city held aloft by blue crystal pipelines, floating lecture halls, and sheer institutional stubbornness.",
		},
		"recruiter": {"name": "Provost Ilyra Venn", "title": "Office of Profitable Curiosity"},
		"rival": "The Iron Tribunal of the Craters",
		"heightRange": [0.97, 1.13],
		"theme": {
			"accent": "#46e6ff",
			"sky": "#7fd4ff",
			"ambient": "#bfe8ff",
			"fog": "#9fd0e8",
			"pipeGlow": "#46e6ff",
			"floor": "#cfd8e6",
			"wall": "#8fa6c4",
			"trim": "#e8eef8",
			"propSet": "skyland",
		},
	},
	{
		"id": "ironblooded",
		"name": "Iron-Blooded",
		"tag": "Steam & Arcane Forge Warriors",
		"lore": "Volcano-born smith-soldiers. They settle philosophical disputes with hammers, and most other disputes with bigger hammers.",
		"defaultName": "Brunhylde",
		"passive": {
			"id": "colossusStance",
			"name": "Colossus Stance",
			"desc": "Immune to stagger. Heavy swings land faster, and you shrug off 25% of all physical damage.",
			"attributeMods": {},
			"hint": "PASSIVE — ALWAYS FORGED ON",
		},
		"city": {
			"name": "The Smelting Craters",
			"desc": "An industrial fortress city bolted into a live volcano — iron gears the size of houses, rivers of molten aether, doors that mean it.",
		},
		"recruiter": {"name": "Forge-Sergeant Brakka Húldottir", "title": "Conscription & Quenching Division"},
		"rival": "The Archlectors of Zephyr-Academica",
		"heightRange": [0.92, 1.08],
		"theme": {
			"accent": "#ff9d4d",
			"sky": "#3a2420",
			"ambient": "#ffb37a",
			"fog": "#52281c",
			"pipeGlow": "#ff6a2b",
			"floor": "#4a3a32",
			"wall": "#5e4438",
			"trim": "#2e2018",
			"propSet": "forge",
		},
	},
	{
		"id": "miststalker",
		"name": "Mist-Stalkers",
		"tag": "Beast-Folk Outlaw Rogues",
		"lore": "Canal-running beastfolk of the fog. If you can see them, they are either being polite or you are already robbed.",
		"defaultName": "Ryx",
		"passive": {
			"id": "feralInstinct",
			"name": "Feral Instinct",
			"desc": "Move faster through high grass, toggle night-vision with N, and enemies notice you far later.",
			"attributeMods": {},
			"hint": "N — NIGHT-VISION",
		},
		"city": {
			"name": "The Titan's Docks",
			"desc": "A foggy multi-level canal sprawl built inside the ribcage of a fallen colossus. Run by smugglers, tolerated by gods.",
		},
		"recruiter": {"name": "Quillane “Quill” Marrow", "title": "Acquisitions (Don't Ask) Desk"},
		"rival": "The Gilded Concord of Free Captains",
		"heightRange": [0.9, 1.1],
		"theme": {
			"accent": "#4dff9d",
			"sky": "#2c4a44",
			"ambient": "#9fd8c5",
			"fog": "#56766e",
			"pipeGlow": "#4dff9d",
			"floor": "#3c4a44",
			"wall": "#51635c",
			"trim": "#27332e",
			"propSet": "docks",
		},
	},
]

static func get_origin(id: String) -> Dictionary:
	for o in ORIGINS:
		if o["id"] == id:
			return o
	return {}
