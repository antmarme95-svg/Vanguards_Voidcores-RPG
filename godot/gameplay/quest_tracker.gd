# quest_tracker.gd — Quest model + three-path macro-freedom branch.
# Direct port of src/gameplay/QuestTracker.js — objective text verbatim.
class_name QuestTracker extends RefCounted

var save: SaveState    = null
var quest: Dictionary  = {}

func _init(p_save: SaveState) -> void:
	save = p_save

func _emit() -> void:
	EventBus.emit_event("quest:update", {"tracker": self})

# ---- activate (JS QuestTracker.activate) ----
func activate(origin: Dictionary) -> void:
	var city_name: String = origin.get("city", {}).get("name", "the city")
	quest = {
		"id": "purge001",
		"title": "PURGE ORDER 001",
		"pathLabel": "Under contract — " + city_name,
		"objectives": [
			{"id": "reach",  "text": "Investigate the crimson resonance",   "done": false, "visible": true},
			{"id": "purge",  "text": "Put down the maddened beasts",         "count": 0, "total": 3, "done": false, "visible": false},
			{"id": "shatter","text": "Shatter the Core of the Dead God",     "done": false, "visible": false},
		],
	}
	EventBus.emit_event("quest:toast", {"text": "Purge Order 001 — received"})
	_emit()

func _obj(id: String) -> Dictionary:
	for o in quest.get("objectives", []):
		if o.get("id", "") == id:
			return o
	return {}

# ---- reach_core_site (JS QuestTracker.reachCoreSite) ----
func reach_core_site() -> void:
	var o: Dictionary = _obj("reach")
	if o.is_empty() or o.get("done", true):
		return
	o["done"] = true
	var purge: Dictionary = _obj("purge")
	if not purge.is_empty():
		purge["visible"] = true
	EventBus.emit_event("quest:toast", {"text": "Core resonance located"})
	_emit()

# ---- enemy_down (JS QuestTracker.enemyDown) ----
func enemy_down() -> void:
	var o: Dictionary = _obj("purge")
	if o.is_empty() or o.get("done", true):
		return
	o["count"] = mini(int(o.get("total", 3)), int(o.get("count", 0)) + 1)
	save.kills += 1
	if o["count"] >= o.get("total", 3):
		o["done"] = true
		var shatter: Dictionary = _obj("shatter")
		if not shatter.is_empty():
			shatter["visible"] = true
		EventBus.emit_event("quest:toast", {"text": "The maddened are silent"})
	_emit()

# ---- core_destroyed (JS QuestTracker.coreDestroyed) ----
func core_destroyed() -> void:
	var o: Dictionary = _obj("shatter")
	if o.is_empty() or o.get("done", true):
		return
	o["done"] = true
	save.cores_purged += 1
	_emit()

# ---- begin_second_purge (JS QuestTracker.beginSecondPurge) ----
func begin_second_purge(origin: Dictionary) -> void:
	if quest.get("id", "") != "campaign":
		return
	quest["objectives"] = [
		{"id": "reach",  "text": "A second resonance bleeds in the west",  "done": false, "visible": true},
		{"id": "purge",  "text": "Put down the maddened guardians",          "count": 0, "total": 3, "done": false, "visible": false},
		{"id": "shatter","text": "Shatter the second Core",                  "done": false, "visible": false},
	]
	EventBus.emit_event("quest:toast", {"text": "Amendment 001-B — a second Core detected"})
	_emit()

# ---- path_options (JS QuestTracker.pathOptions) ----
func path_options(origin: Dictionary) -> Array:
	var city_name: String = origin.get("city", {}).get("name", "the city")
	var rival: String     = origin.get("rival", "the rivals")
	var accent: String    = origin.get("theme", {}).get("accent", "#46e6ff")
	return [
		{
			"id": "kingdom",
			"letter": "PATH A — THE LOYAL BLADE",
			"name": "Serve " + city_name,
			"color": accent,
			"desc": "Fulfill the contract as written. Purge the Cores for the crown, bank the bounty, keep your name clean. The pay is steady. The leash is short.",
		},
		{
			"id": "betrayal",
			"letter": "PATH B — THE DOUBLE CONTRACT",
			"name": "Court " + rival,
			"color": "#ffc94d",
			"desc": rival + " pays triple for Core locations — and even more for your silence. Nobody needs to know. Yet.",
		},
		{
			"id": "rogue",
			"letter": "PATH C — THE UNBOUND",
			"name": "Answer to no crown",
			"color": "#ff4d5e",
			"desc": "Tear up the fine print. The Cores answer to whoever holds them — why not you? Every kingdom on the continent will come for your head. Let them queue.",
		},
	]

# ---- choose_path (JS QuestTracker.choosePath) — campaign titles verbatim ----
func choose_path(path_id: String, origin: Dictionary) -> void:
	save.chosen_path = path_id
	save.persist()
	var city_name: String = origin.get("city", {}).get("name", "the city")
	var rival: String     = origin.get("rival", "the rivals")

	var titles: Dictionary = {
		"kingdom": {
			"title": "THE LOYAL BLADE",
			"path":  "Sworn — for now — to " + city_name,
			"obj":   "Purge the frontier Cores in the Crown's name",
		},
		"betrayal": {
			"title": "THE DOUBLE CONTRACT",
			"path":  "Quietly treating with " + rival,
			"obj":   "Map the Cores… and leak the map",
		},
		"rogue": {
			"title": "THE UNBOUND",
			"path":  "Independent mercenary entity",
			"obj":   "Claim the Cores for no crown but your own",
		},
	}
	var t: Dictionary = titles.get(path_id, titles["kingdom"])
	quest = {
		"id": "campaign",
		"title": t["title"],
		"pathLabel": t["path"],
		"objectives": [
			{"id": "next", "text": t["obj"], "done": false, "visible": true},
			{"id": "roam", "text": "Vertical slice complete — roam The Wilds", "done": false, "visible": true},
		],
	}
	EventBus.emit_event("path:chosen", {"path": path_id})
	_emit()
