# Unified player record — direct port of src/core/SaveState.js.
# Pure data, no engine scene imports.
class_name SaveState extends RefCounted

const SAVE_PATH := "user://borisawa_save.json"

var player_name: String = ""
var origin_id: String = ""
var class_id: String = ""
var phenotype: Dictionary = {}
var chosen_path: String = ""   # "kingdom" | "betrayal" | "rogue" | ""
var kills: int = 0
var cores_purged: int = 0
var started_at: int = 0

func _init() -> void:
	phenotype = PhenotypeData.default_phenotype()
	started_at = int(Time.get_unix_time_from_system() * 1000)

func get_origin() -> Dictionary:
	for o in OriginsData.ORIGINS:
		if o["id"] == origin_id:
			return o
	return {}

func get_char_class() -> Dictionary:
	for c in ClassesData.CLASSES:
		if c["id"] == class_id:
			return c
	return {}

# Final attribute pools: class table + origin passive attribute modifiers.
func compute_attributes() -> Dictionary:
	var cls := get_char_class()
	var attrs: Dictionary
	if cls.is_empty():
		attrs = {
			"health": ClassesData.BASE_ATTRIBUTE,
			"magicka": ClassesData.BASE_ATTRIBUTE,
			"stamina": ClassesData.BASE_ATTRIBUTE,
		}
	else:
		attrs = cls["attributes"].duplicate()
	var origin := get_origin()
	if not origin.is_empty():
		var passive: Dictionary = origin.get("passive", {})
		var mods: Dictionary = passive.get("attributeMods", {})
		for k in mods:
			attrs[k] = attrs.get(k, ClassesData.BASE_ATTRIBUTE) + mods[k]
	return attrs

# Skills: every skill at BASE_SKILL, class bonuses applied on top.
func compute_skills() -> Dictionary:
	var skills: Dictionary = {}
	for s in ClassesData.SKILL_LIST:
		skills[s] = ClassesData.BASE_SKILL
	var cls := get_char_class()
	if not cls.is_empty():
		var bonuses: Dictionary = cls.get("skillBonuses", {})
		for skill in bonuses:
			skills[skill] = ClassesData.BASE_SKILL + bonuses[skill]
	return skills

func is_creation_complete() -> bool:
	return origin_id != "" and class_id != "" and player_name.strip_edges().length() > 0

func persist() -> void:
	var data := {
		"name": player_name,
		"originId": origin_id,
		"classId": class_id,
		"phenotype": phenotype,
		"chosenPath": chosen_path,
		"kills": kills,
		"coresPurged": cores_purged,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()

static func load_saved() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not f:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not parsed is Dictionary:
		return {}
	return parsed
