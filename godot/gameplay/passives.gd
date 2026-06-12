# passives.gd — Origin passive abilities.
# Direct port of src/gameplay/Passives.js — all numbers identical.
class_name Passives extends RefCounted

var origin_id: String = ""
var stats: Stats       = null

var overclock_active: bool = false   # aetherborn: held Q
var night_vision: bool     = false   # miststalker: toggled N

func _init(save: SaveState, p_stats: Stats) -> void:
	origin_id = save.origin_id
	stats      = p_stats

	# Colossus Stance (ironblooded) — set resist immediately on construction
	if origin_id == "ironblooded":
		stats.physical_resist = 0.25

# ---- Mana-Overload: hold Q → overclock casting, drains stamina 16/s ----
# held = true while Q is pressed
func set_overclock(held: bool, dt: float) -> void:
	if origin_id != "aetherborn":
		return
	var active: bool = false
	if held:
		active = stats.drain_stamina(16.0, dt)
	if active != overclock_active:
		overclock_active = active
		EventBus.emit_event("passive:toggled", {"active": active, "id": "manaOverload"})

func cast_cooldown_mult() -> float:
	return 0.45 if overclock_active else 1.0

# ---- Colossus Stance: faster heavy swings (resist handled in Stats) ----
func attack_cooldown_mult() -> float:
	return 0.8 if origin_id == "ironblooded" else 1.0

# ---- Feral Instinct ----
func grass_speed_mult(in_grass: bool) -> float:
	return 1.35 if (origin_id == "miststalker" and in_grass) else 1.0

func detection_mult() -> float:
	return 0.55 if origin_id == "miststalker" else 1.0

func toggle_night_vision() -> void:
	if origin_id != "miststalker":
		return
	night_vision = not night_vision
	EventBus.emit_event("passive:toggled", {"active": night_vision, "id": "feralInstinct"})
