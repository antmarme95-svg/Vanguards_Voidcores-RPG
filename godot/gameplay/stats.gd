# stats.gd — Runtime vitals: health / magicka / stamina.
# Direct port of src/gameplay/Stats.js — all numbers identical.
class_name Stats extends RefCounted

# ---- pools (set from save.compute_attributes()) ----
var max_health: float
var max_magicka: float
var max_stamina: float
var health: float
var magicka: float
var stamina: float

# ---- skill map ----
var skills: Dictionary = {}

# ---- regen rates (JS constants) ----
var stamina_regen: float = 26.0
var magicka_regen: float = 9.0
var health_regen: float  = 1.5

# ---- exhaustion (BotW-style) ----
var exhausted: bool = false
var _regen_hold: float = 0.0

# ---- passives / buffs ----
var physical_resist: float = 0.0   # set by Passives (ironblooded = 0.25)
var damage_mult: float     = 1.0   # multiplied by apply_path_buff

func _init(save: SaveState) -> void:
	var attrs: Dictionary = save.compute_attributes()
	max_health  = float(attrs.get("health",  100))
	max_magicka = float(attrs.get("magicka", 100))
	max_stamina = float(attrs.get("stamina", 100))
	health  = max_health
	magicka = max_magicka
	stamina = max_stamina
	skills  = save.compute_skills()

# ---- path buffs (JS Stats.applyPathBuff) ----
func apply_path_buff(mods: Dictionary) -> void:
	if mods.has("maxHealth"):
		max_health += float(mods["maxHealth"])
		health     += float(mods["maxHealth"])
	if mods.has("maxMagicka"):
		max_magicka += float(mods["maxMagicka"])
		magicka     += float(mods["maxMagicka"])
	if mods.has("maxStamina"):
		max_stamina += float(mods["maxStamina"])
		stamina     += float(mods["maxStamina"])
	if mods.has("physicalResist"):
		physical_resist += float(mods["physicalResist"])
	if mods.has("damageMult"):
		damage_mult *= float(mods["damageMult"])

# ---- skill bonus (JS Stats.skillBonus) ----
func skill_bonus(skill_name: String, per_point: float = 0.02) -> float:
	var v: int = skills.get(skill_name, 15)
	return 1.0 + float(v - 15) * per_point

# ---- stamina (JS Stats.spendStamina / drainStamina) ----
func spend_stamina(amount: float) -> bool:
	if exhausted:
		return false
	stamina -= amount
	_regen_hold = 0.6
	if stamina <= 0.0:
		stamina = 0.0
		exhausted = true
	return true

func drain_stamina(per_second: float, dt: float) -> bool:
	if exhausted:
		return false
	stamina -= per_second * dt
	_regen_hold = 0.4
	if stamina <= 0.0:
		stamina = 0.0
		exhausted = true
		return false
	return true

# ---- magicka (JS Stats.spendMagicka) ----
func spend_magicka(amount: float) -> bool:
	if magicka < amount:
		return false
	magicka -= amount
	return true

# ---- damage / heal (JS Stats.takeDamage / heal) ----
func take_damage(amount: float, physical: bool = true) -> float:
	var final_dmg: float = amount * (1.0 - physical_resist) if physical else amount
	health = maxf(0.0, health - final_dmg)
	EventBus.emit_event("combat:playerHit", {"amount": final_dmg})
	if health <= 0.0:
		EventBus.emit_event("player:died", {})
	return final_dmg

func heal(amount: float) -> void:
	health = minf(max_health, health + amount)

# ---- regen update (JS Stats.update) ----
func update(dt: float) -> void:
	_regen_hold = maxf(0.0, _regen_hold - dt)
	if _regen_hold <= 0.0:
		stamina = minf(max_stamina, stamina + stamina_regen * dt)
		if exhausted and stamina >= max_stamina * 0.35:
			exhausted = false
	magicka = minf(max_magicka, magicka + magicka_regen * dt)
	health  = minf(max_health,  health  + health_regen  * dt)
