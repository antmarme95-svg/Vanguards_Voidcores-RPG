# Config — autoload singleton (Node).
# Loads locomotion.json and class_multipliers.json at startup.
# Safe fallback: if a file is missing or fails to parse, push_warning and
# use built-in defaults so the game never crashes.
#
# Usage (once registered as autoload "Config"):
#   Config.locomotion()                          -> Dictionary  (all locomotion keys)
#   Config.class_mult(origin_id, class_id)       -> Dictionary  (9-field physiometry profile)

extends Node

# ── built-in defaults ──────────────────────────────────────────────────────────
const _LOCO_DEFAULTS := {
	"baseSpeed":        3.3,
	"sprintMultiplier": 2.0,
	"crouchSpeed":      1.9,
	"gravity":          24.0,
	"jumpForce":        8.4,
	"staminaDrainRate": 15.0,
	"jumpStaminaCost":  7.0,
	"facingBlend":      14.0,
	"airControl":       0.2,
	"slideVelocity":    9.0,
	"slideDecay":       8.0,
	"slideThreshold":   5.0,
	"fovBase":          50.0,
	"fovKickDeg":       8.0,
	"landingStutterPerMeter": 0.03,
	"landingStutterMax":      0.35,
}

const _CLASS_MULT_DEFAULT := {
	"speedMult":         1.0,
	"sprintSpeedMult":   1.0,
	"jumpMult":          1.0,
	"massMult":          1.0,
	"slideFriction":     0.92,
	"airControlPct":     0.50,
	"crouchStealthMult": 0.50,
	"slideSteerMaxDeg":  22,
	"staminaMult":       1.0,
}

# ── internal state ─────────────────────────────────────────────────────────────
var _loco:       Dictionary = {}
var _class_mult: Dictionary = {}
var _substyles:  Dictionary = {}

# ── lifecycle ──────────────────────────────────────────────────────────────────
func _ready() -> void:
	_loco       = _load_locomotion()
	_class_mult = _load_class_mult()
	_substyles  = _load_substyles()


# ── public API ─────────────────────────────────────────────────────────────────

## Returns the full locomotion dictionary.
## All keys from _LOCO_DEFAULTS are guaranteed to be present.
func locomotion() -> Dictionary:
	return _loco


## Returns per-subclass physiometry profile for (origin_id, class_id).
## 3-level fallback: built-in defaults → archetype_defaults[class_id] → origin[class_id].
## Always returns a dict containing all 9 fields. Never crashes on unknown keys.
func class_mult(origin_id: String, class_id: String) -> Dictionary:
	var result: Dictionary = _CLASS_MULT_DEFAULT.duplicate(true)

	# Level 1: merge archetype_defaults[class_id] over built-in defaults
	if _class_mult.has("archetype_defaults"):
		var arch_defaults: Variant = _class_mult["archetype_defaults"]
		if arch_defaults is Dictionary and arch_defaults.has(class_id):
			var arch_cell: Variant = arch_defaults[class_id]
			if arch_cell is Dictionary:
				for k in arch_cell:
					result[k] = arch_cell[k]

	# Level 2: merge origin-specific subclass cell over the above
	if _class_mult.has(origin_id):
		var origin_dict: Variant = _class_mult[origin_id]
		if origin_dict is Dictionary and origin_dict.has(class_id):
			var sub_cell: Variant = origin_dict[class_id]
			if sub_cell is Dictionary:
				for k in sub_cell:
					result[k] = sub_cell[k]
		else:
			push_warning("Config.class_mult: no cell for origin='%s' class='%s', using archetype defaults" % [origin_id, class_id])
	else:
		push_warning("Config.class_mult: unknown origin_id='%s', using archetype/built-in defaults" % origin_id)

	return result


## Returns the substyle dictionary for (origin_id, class_id), or {} if not found.
func substyle(origin_id: String, class_id: String) -> Dictionary:
	if not _substyles.has("substyles"):
		return {}
	var substyles_dict: Variant = _substyles["substyles"]
	if not substyles_dict is Dictionary:
		return {}
	if not substyles_dict.has(origin_id):
		return {}
	var origin_dict: Variant = substyles_dict[origin_id]
	if not origin_dict is Dictionary:
		return {}
	if not origin_dict.has(class_id):
		return {}
	var result: Variant = origin_dict[class_id]
	if result is Dictionary:
		return result
	return {}


## Returns the archetype dictionary for class_id, or {} if not found.
func archetype(class_id: String) -> Dictionary:
	if not _substyles.has("archetypes"):
		return {}
	var archetypes_dict: Variant = _substyles["archetypes"]
	if not archetypes_dict is Dictionary:
		return {}
	if not archetypes_dict.has(class_id):
		return {}
	var result: Variant = archetypes_dict[class_id]
	if result is Dictionary:
		return result
	return {}


# ── internal loaders ───────────────────────────────────────────────────────────

func _load_locomotion() -> Dictionary:
	var result: Dictionary = _LOCO_DEFAULTS.duplicate(true)
	const PATH := "res://data/locomotion.json"
	var parsed: Variant = _parse_json_file(PATH)
	if parsed != null and parsed is Dictionary:
		# Merge loaded values over defaults so missing keys fall back.
		for k in parsed:
			result[k] = parsed[k]
	return result


func _load_class_mult() -> Dictionary:
	var result: Dictionary = {}
	const PATH := "res://data/class_multipliers.json"
	var parsed: Variant = _parse_json_file(PATH)
	if parsed == null or not parsed is Dictionary:
		# Parse failed — leave result empty; class_mult() falls back to built-in defaults.
		return result
	for top_key in parsed:
		# Skip metadata keys (beginning with "_")
		if (top_key as String).begins_with("_"):
			continue
		var entry: Variant = parsed[top_key]
		if entry is Dictionary:
			result[top_key] = entry
	return result


func _load_substyles() -> Dictionary:
	var result: Dictionary = {}
	const PATH := "res://data/substyles.json"
	var parsed: Variant = _parse_json_file(PATH)
	if parsed != null and parsed is Dictionary:
		result = parsed
	return result


func _parse_json_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_warning("Config: file not found — %s — using built-in defaults" % path)
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("Config: could not open '%s' (error %d) — using built-in defaults" % [path, FileAccess.get_open_error()])
		return null
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		push_warning("Config: JSON parse error in '%s' — using built-in defaults" % path)
		return null
	return parsed
