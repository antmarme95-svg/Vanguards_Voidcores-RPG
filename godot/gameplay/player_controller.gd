# player_controller.gd — Third-person player controller.
# Port of src/gameplay/PlayerController.js — all constants preserved exactly.
#
# Y-AXIS PARITY NOTE: This controller drives Y analytically from scene.get_height()
# (same approach as the JS). CharacterBody3D / move_and_slide() is NOT used for
# terrain following — that would add physics overhead and change the feel. The
# capsule CollisionShape3D is kept for future physics layers (push-back vs. walls
# already handled by clamp_position per-scene). This matches the JS exactly and
# is the documented deviation.
#
# PRD-003: locomotion is now delegated to LocomotionStateMachine (LSM).
# The WALK/SPRINT/CROUCH consts are kept as FALLBACK values only; Config drives
# the actual values at runtime.
class_name PlayerController extends CharacterBody3D

const _LSM = preload("res://gameplay/locomotion_state_machine.gd")

# ---- movement constants (JS exactly) — FALLBACK only, Config drives runtime ----
const WALK    := 3.3
const SPRINT  := 6.6
const CROUCH  := 1.9
const GRAVITY := 24.0
const JUMP_V  := 8.4

# ---- camera constants ----
const CAM_DIST_DEFAULT  := 4.4
const CAM_DIST_MIN      := 2.4
const CAM_DIST_MAX      := 8.0
const CAM_PITCH_MIN     := -0.25
const CAM_PITCH_MAX     :=  1.25
const CAM_SHOULDER      :=  0.8    # right-shoulder offset in world units

# ---- deps (set via setup()) ----
var stats: Stats       = null
var passives: Passives = null
var save: SaveState    = null
var rig: CharacterRig  = null

# ---- scene ref ----
var scene: Node3D = null   # any scene that has get_height / clamp_position / etc.
var enemies: Array = []
var interactables: Array = []   # scene.interactables alias
var triggers: Array = []        # scene.triggers alias

# ---- camera node ----
var cam: Camera3D = null
var _spring: SpringArm3D = null   # optional — we use manual orbit math like JS

# ---- player state (mirrors JS) ----
var cam_yaw: float   = PI
var cam_pitch: float = 0.32
var cam_dist: float  = CAM_DIST_DEFAULT
var facing: float    = PI
var vel_y: float     = 0.0
var grounded: bool   = true
var crouching: bool  = false
var sprinting: bool  = false
var move_speed_norm: float = 0.0
var attack_cooldown: float = 0.0
var projectiles: Array     = []

# ---- PRD-003: locomotion state (exposed for HUD/rig) ----
var loco_state: String = "IDLE"

# ---- PRD-003: slide direction tracking ----
var _slide_dir: Vector3       = Vector3.ZERO
var _slide_entry_dir: Vector3 = Vector3.ZERO
var _was_sliding: bool        = false   # edge-detect slide end (auto-stand from crouch toggle)

# ---- Sprint L2: leap (slide→jump) state ----
var _air_vel: Vector3  = Vector3.ZERO   # horizontal velocity carried from leap launch
var _leaping: bool     = false          # true while airborne from a slide→jump leap
var _cam_thump: float  = 0.0           # camera thump timer for landing feel (seconds)

# ---- PRD-003: cam_yaw last-frame tracker (for cam_yaw_changed) ----
var _last_cam_yaw: float = PI

var _enabled: bool = false

# ---- mouse sensitivity ----
var sens_x: float = 1.0
var sens_y: float = 1.0

# ---- input state ----
var _keys_down: Dictionary = {}   # keyed by event physical_keycode
var _mouse_captured: bool  = false

# ---- locomotion state machine ----
var _lsm: RefCounted = null   # LocomotionStateMachine instance

# ---- FOV baseline (used for lerp target before LSM is ready) ----
var _fov_target: float = 50.0

# ---- ADS (aim-down-sights) state ----
var _ads_held: bool        = false
# ---- Sprint L3: attack interrupt pulse ----
var _attack_pulse: float   = 0.0
var _cam_dist_eff: float   = CAM_DIST_DEFAULT
var _shoulder_eff: float   = CAM_SHOULDER
var _ads_fov: float        = 36.0
var _ads_cam_dist: float   = 2.9
var _ads_shoulder: float   = 0.55
var _ads_sens_mult: float  = 0.6

# ----------------------------------------------------------------
func _ready() -> void:
	# Capsule collider — matches rig size (height ~1.8, radius 0.32)
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.16   # inner height (total = 1.8)
	col.shape  = cap
	col.position.y = 0.9
	add_child(col)

	# Create and configure LSM.
	# Config may not be available in headless unit-test context, so guard it.
	_lsm = _LSM.new()
	_lsm_configure()

func _lsm_configure() -> void:
	if _lsm == null:
		return
	# Config is an autoload Node — access via the scene tree if available.
	# Falls back to built-in LSM defaults if Config is not yet ready (headless tests).
	var loco: Dictionary = {}
	var cmult: Dictionary = {}
	var cfg_node = _get_config_node()
	if cfg_node != null:
		loco  = cfg_node.locomotion()
		# Determine origin_id and class_id from save
		var origin_id: String = save.origin_id if save != null else ""
		var class_id: String  = save.class_id  if save != null else ""
		cmult = cfg_node.class_mult(
			origin_id if origin_id != "" else "aetherborn",
			class_id  if class_id  != "" else "warrior"
		)
	_lsm.configure(loco, cmult)
	# Prime fov_target from fovBase (fallback 50.0 if not yet loaded)
	if loco.has("fovBase"):
		_fov_target = float(loco["fovBase"])
	else:
		_fov_target = 50.0
	# Prime ADS tunables from loco config (fall back to built-in constants)
	if loco.has("adsFov"):       _ads_fov        = float(loco["adsFov"])
	if loco.has("adsCamDist"):   _ads_cam_dist   = float(loco["adsCamDist"])
	if loco.has("adsShoulder"):  _ads_shoulder   = float(loco["adsShoulder"])
	if loco.has("adsSensMult"):  _ads_sens_mult  = float(loco["adsSensMult"])

func _get_config_node() -> Node:
	# In-game: Config is an autoload — use get_node on the root tree.
	# In headless unit tests this node won't exist; return null gracefully.
	if get_tree() == null:
		return null
	var root = get_tree().root
	if root == null:
		return null
	return root.get_node_or_null("/root/Config")

func setup(p_rig: CharacterRig, p_stats: Stats, p_passives: Passives, p_save: SaveState, p_cam: Camera3D) -> void:
	rig      = p_rig
	stats    = p_stats
	passives = p_passives
	save     = p_save
	cam      = p_cam
	# Re-configure LSM now that save is set (class_id is now known).
	_lsm_configure()

var enabled: bool:
	get: return _enabled
	set(v):
		_enabled = v
		if not v:
			_set_ads(false)
			if _mouse_captured:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
				_mouse_captured = false

func recapture_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_mouse_captured = true

func is_sneaking() -> bool:
	return crouching

# ---- set_scene — called each time a new scene activates ----
func set_scene(new_scene: Node3D) -> void:
	# Remove rig from previous scene
	if rig.get_parent() != null:
		rig.get_parent().remove_child(rig)
	# Clear projectiles
	for p in projectiles:
		if is_instance_valid(p["node"]) and p["node"].get_parent() != null:
			p["node"].get_parent().remove_child(p["node"])
	projectiles.clear()
	enemies.clear()

	scene = new_scene
	new_scene.add_child(rig)

	var spawn: Dictionary = new_scene.player_spawn
	var sp: Vector3 = spawn.get("position", Vector3.ZERO)
	position = sp
	vel_y    = 0.0
	facing   = spawn.get("yaw", PI)
	cam_yaw  = facing + PI
	_last_cam_yaw = cam_yaw
	cam_pitch = 0.3
	rig.global_position = sp
	rig.rotation.y      = facing

	# Wire alias arrays
	interactables = new_scene.interactables if new_scene.get("interactables") != null else []
	triggers      = new_scene.triggers      if new_scene.get("triggers")      != null else []

	# Re-configure LSM with class (scene change may coincide with class selection)
	_lsm_configure()

	_sync_camera(1.0)

# ----------------------------------------------------------------
# Input handling — _unhandled_input for keyboard/mouse (no action map needed)
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if not _mouse_captured:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
				_mouse_captured = true
			elif _enabled:
				try_attack()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and _enabled and _mouse_captured:
			_set_ads(mb.pressed)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and _enabled:
			cam_dist = clampf(cam_dist + 0.0035 * 40.0, CAM_DIST_MIN, CAM_DIST_MAX)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and _enabled:
			cam_dist = clampf(cam_dist - 0.0035 * 40.0, CAM_DIST_MIN, CAM_DIST_MAX)

	elif event is InputEventMouseMotion and _mouse_captured and _enabled:
		var mm := event as InputEventMouseMotion
		var s: float = _ads_sens_mult if _ads_held else 1.0
		cam_yaw   -= mm.relative.x * 0.0052 * sens_x * s
		cam_pitch  = clampf(cam_pitch + mm.relative.y * 0.0045 * sens_y * s, CAM_PITCH_MIN, CAM_PITCH_MAX)

	elif event is InputEventKey:
		var ke := event as InputEventKey
		var kc: int = ke.physical_keycode
		if ke.pressed and not ke.echo:
			_keys_down[kc] = true
			if not _enabled:
				return
			if kc == KEY_C:
				crouching = not crouching
				_crouch_just_pressed_this_frame = true   # slide-intent edge — fires on every C press (toggle-direction agnostic)
			elif kc == KEY_N:
				passives.toggle_night_vision()
			elif kc == KEY_F:
				try_attack()
			elif kc == KEY_M:
				EventBus.emit_event("minimap:toggled", {})
			elif kc == KEY_ESCAPE:
				EventBus.emit_event("player:pause_toggled", {})
		elif not ke.pressed:
			_keys_down.erase(kc)

func _has_key(kc: int) -> bool:
	return _keys_down.get(kc, false)

func _set_ads(on: bool) -> void:
	if _ads_held == on:
		return
	_ads_held = on
	EventBus.emit_event("player:ads_changed", {"active": on})

# ----------------------------------------------------------------
# try_attack — JS PlayerController.tryAttack()
func try_attack() -> void:
	if not _enabled or attack_cooldown > 0.0:
		return
	if save == null:
		return
	var cls: Dictionary = save.get_char_class()
	var combat: Dictionary = cls.get("combat", {})
	if combat.is_empty():
		return

	var style: String = combat.get("style", "melee")
	if style == "bolt":
		if not stats.spend_magicka(float(combat.get("magickaCost", 14))):
			return
		attack_cooldown = float(combat.get("cooldown", 0.55)) * passives.cast_cooldown_mult()
		_attack_pulse = 0.12   # Sprint L3: briefly interrupt sprint/slide
		rig.play_attack("bolt")
		_spawn_projectile(combat, Color("#7adfff"), 0.13, false)
	elif style == "arrow":
		if not stats.spend_stamina(float(combat.get("staminaCost", 8))):
			return
		attack_cooldown = float(combat.get("cooldown", 0.45))
		_attack_pulse = 0.12   # Sprint L3: briefly interrupt sprint/slide
		rig.play_attack("melee")
		_spawn_projectile(combat, Color("#d8e8c8"), 0.05, true)
	else:  # melee
		if not stats.spend_stamina(float(combat.get("staminaCost", 12))):
			return
		attack_cooldown = float(combat.get("cooldown", 0.65)) * passives.attack_cooldown_mult()
		_attack_pulse = 0.12   # Sprint L3: briefly interrupt sprint/slide
		rig.play_attack("melee")
		_melee_hit(combat)

func _attack_damage(combat: Dictionary) -> float:
	var key_skill: String = combat.get("keySkill", "")
	return float(combat.get("damage", 10)) * stats.skill_bonus(key_skill) * stats.damage_mult

func _melee_hit(combat: Dictionary) -> void:
	var fwd := Vector3(sin(facing), 0.0, cos(facing))
	var arc_deg: float = float(combat.get("arcDeg", 110))
	var cos_arc: float = cos(arc_deg * PI / 360.0)
	var range_m: float = float(combat.get("range", 2.6))
	for enemy in enemies:
		if enemy.dead:
			continue
		var to: Vector3 = (enemy.position - position)
		to.y = 0.0
		var d: float = to.length()
		if d > range_m:
			continue
		to = to.normalized()
		if to.dot(fwd) < cos_arc and d > 0.7:
			continue
		enemy.hit(_attack_damage(combat), self)

func _spawn_projectile(combat: Dictionary, color: Color, size: float, is_arrow: bool) -> void:
	var fwd := Vector3(
		-sin(cam_yaw),
		-sin(cam_pitch) * 0.35,
		-cos(cam_yaw)
	).normalized()
	facing = atan2(fwd.x, fwd.z)

	# ---- Duelist (thief) origin-specific VFX branch ----
	# Only applies when class is thief (arrow style). Non-thief paths are unaffected.
	if is_arrow and save != null and save.class_id == "thief":
		_spawn_duelist_projectile(combat, fwd)
		return

	var mi := MeshInstance3D.new()
	if is_arrow:
		var cm := CylinderMesh.new()
		cm.top_radius    = 0.018
		cm.bottom_radius = 0.018
		cm.height        = 0.55
		mi.mesh = cm
		mi.quaternion = Quaternion(Vector3.UP, fwd)
	else:
		var sm := SphereMesh.new()
		sm.radius = size
		sm.height = size * 2.0
		mi.mesh = sm
	mi.material_override = ToonMaterials.glow_mat(color, 1.3)
	mi.position = position + Vector3(0.0, 1.35, 0.0) + fwd * 0.6
	scene.add_child(mi)

	projectiles.append({
		"node":        mi,
		"vel":         fwd * float(combat.get("projectileSpeed", 26)),
		"life":        2.4,
		"damage":      _attack_damage(combat),
		"combat":      combat,
		"sneak_shot":  crouching,
	})

# ----------------------------------------------------------------
# _spawn_duelist_projectile — Duelist (thief) origin-specific attack VFX.
# Called only when save.class_id == "thief". Branches on save.origin_id.
# Three cells (PRD-001 §6):
#   aetherborn  → Spell-Blade:    aetherial dagger mesh + teal GPUParticles3D trail
#   ironblooded → Scrap-Slinger:  muzzle flash + fast tracer + impact spark flag
#   miststalker → Shadow-Stalker: dark projectile + blink afterimage flash on player
# ----------------------------------------------------------------
func _spawn_duelist_projectile(combat: Dictionary, fwd: Vector3) -> void:
	var origin: String = save.origin_id if save != null else ""
	var spawn_pos: Vector3 = position + Vector3(0.0, 1.35, 0.0) + fwd * 0.6
	var speed: float = float(combat.get("projectileSpeed", 26))
	var dmg: float   = _attack_damage(combat)

	match origin:
		"aetherborn":
			# ---- Spell-Blade: aetherial dagger + teal trail ----
			# Dagger: elongated box mesh oriented along travel direction
			var mi := MeshInstance3D.new()
			var bm  := BoxMesh.new()
			bm.size = Vector3(0.04, 0.04, 0.52)   # thin elongated blade shape
			mi.mesh = bm
			# Align box z-axis → forward direction
			mi.quaternion = Quaternion(Vector3(0.0, 0.0, 1.0), fwd)
			mi.material_override = ToonMaterials.glow_mat(Color("#00e8d8"), 2.2)  # bright teal
			mi.position = spawn_pos
			scene.add_child(mi)

			# Teal GPUParticles3D trail parented to the projectile node
			var trail := GPUParticles3D.new()
			trail.emitting      = true
			trail.amount        = 12
			trail.lifetime      = 0.22
			trail.explosiveness = 0.0
			trail.randomness    = 0.15
			trail.one_shot      = false
			trail.local_coords  = false
			# ProcessMaterial for trail
			var pm := ParticleProcessMaterial.new()
			pm.direction          = Vector3(0.0, 0.0, 0.0)
			pm.spread             = 14.0
			pm.initial_velocity_min = 0.4
			pm.initial_velocity_max = 0.9
			pm.gravity            = Vector3(0.0, -0.5, 0.0)
			pm.scale_min          = 0.06
			pm.scale_max          = 0.12
			pm.color              = Color(0.0, 0.91, 0.85, 0.85)
			# Fade out over lifetime
			var grad := Gradient.new()
			grad.set_color(0, Color(0.0, 0.91, 0.85, 0.85))
			grad.set_color(1, Color(0.0, 0.5, 0.5, 0.0))
			var gtex := GradientTexture1D.new()
			gtex.gradient = grad
			pm.color_ramp = gtex
			trail.process_material = pm
			# Draw: small sphere particle
			var sm := SphereMesh.new()
			sm.radius = 0.045
			sm.height = 0.09
			var tm_mat := ToonMaterials.glow_mat(Color("#00e8d8"), 1.6)
			tm_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			sm.surface_set_material(0, tm_mat)
			trail.draw_pass_1 = sm
			mi.add_child(trail)

			projectiles.append({
				"node":       mi,
				"vel":        fwd * speed,
				"life":       2.4,
				"damage":     dmg,
				"combat":     combat,
				"sneak_shot": crouching,
				"vfx_tag":    "spellblade",
			})

		"ironblooded":
			# ---- Scrap-Slinger: muzzle flash + fast tracer + impact spark flag ----
			# (A) Muzzle flash: short-lived bright orange emissive sphere at hand/muzzle
			var flash := MeshInstance3D.new()
			var fsm   := SphereMesh.new()
			fsm.radius = 0.18
			fsm.height = 0.36
			flash.mesh = fsm
			flash.material_override = ToonMaterials.glow_mat(Color("#ff8c00"), 3.5)
			flash.position = position + Vector3(0.0, 1.3, 0.0) + fwd * 0.55
			scene.add_child(flash)
			# Auto-free the muzzle flash after ~0.06s via a one-shot timer node
			var flash_timer := Timer.new()
			flash_timer.wait_time  = 0.06
			flash_timer.one_shot   = true
			flash_timer.autostart  = true
			flash.add_child(flash_timer)
			flash_timer.timeout.connect(func() -> void:
				if is_instance_valid(flash) and flash.get_parent() != null:
					flash.get_parent().remove_child(flash)
					flash.queue_free()
			)

			# (B) Tracer: thin fast cylinder
			var mi := MeshInstance3D.new()
			var cm  := CylinderMesh.new()
			cm.top_radius    = 0.008
			cm.bottom_radius = 0.008
			cm.height        = 0.80        # longer/thinner than default arrow
			mi.mesh = cm
			mi.quaternion = Quaternion(Vector3.UP, fwd)
			mi.material_override = ToonMaterials.glow_mat(Color("#ffcc44"), 3.0)  # bright orange-yellow
			mi.position = spawn_pos
			scene.add_child(mi)

			projectiles.append({
				"node":        mi,
				"vel":         fwd * speed * 1.45,   # faster than default
				"life":        2.4,
				"damage":      dmg,
				"combat":      combat,
				"sneak_shot":  crouching,
				"vfx_tag":     "scrapslinger",  # signals impact spark in _update_projectiles
			})

		"miststalker":
			# ---- Shadow-Stalker: dark projectile + player blink afterimage flash ----
			# (A) Dark shadow projectile
			var mi := MeshInstance3D.new()
			var cm  := CylinderMesh.new()
			cm.top_radius    = 0.016
			cm.bottom_radius = 0.016
			cm.height        = 0.48
			mi.mesh = cm
			mi.quaternion = Quaternion(Vector3.UP, fwd)
			# Very dark purple/black with slight glow — reads as "shadow" against any bg
			mi.material_override = ToonMaterials.glow_mat(Color("#220033"), 1.0)
			mi.position = spawn_pos
			scene.add_child(mi)

			# (B) Blink afterimage flash ON THE PLAYER: a subtle low-alpha flicker —
			#     hugs the body silhouette (radius 0.22), alpha ~0.22, gone in ~0.08s
			#     so it reads as a quick step flicker rather than a big purple pill.
			var blink := MeshInstance3D.new()
			var bsm   := CapsuleMesh.new()
			bsm.radius = 0.22   # was 0.34 — tighter body hug
			bsm.height = 1.60   # was 1.82 — slightly shorter
			blink.mesh = bsm
			var blink_mat := ToonMaterials.glow_mat(Color("#6600aa"), 0.8)
			blink_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			blink_mat.albedo_color = Color(0.4, 0.0, 0.67, 0.22)   # was 0.72 alpha
			blink.material_override = blink_mat
			blink.position = position + Vector3(0.0, 0.80, 0.0)
			scene.add_child(blink)
			# Short timer — gone in 0.08s (was 0.12s) for a fast flicker feel
			var blink_timer := Timer.new()
			blink_timer.wait_time = 0.08
			blink_timer.one_shot  = true
			blink_timer.autostart = true
			blink.add_child(blink_timer)
			blink_timer.timeout.connect(func() -> void:
				if is_instance_valid(blink) and blink.get_parent() != null:
					blink.get_parent().remove_child(blink)
					blink.queue_free()
			)

			projectiles.append({
				"node":       mi,
				"vel":        fwd * speed,
				"life":       2.4,
				"damage":     dmg,
				"combat":     combat,
				"sneak_shot": crouching,
				"vfx_tag":    "shadowstalker",
			})

		_:
			# Unknown origin — fall back to default arrow visual (no VFX branch)
			var mi := MeshInstance3D.new()
			var cm  := CylinderMesh.new()
			cm.top_radius    = 0.018
			cm.bottom_radius = 0.018
			cm.height        = 0.55
			mi.mesh = cm
			mi.quaternion = Quaternion(Vector3.UP, fwd)
			mi.material_override = ToonMaterials.glow_mat(Color("#d8e8c8"), 1.3)
			mi.position = spawn_pos
			scene.add_child(mi)
			projectiles.append({
				"node":       mi,
				"vel":        fwd * speed,
				"life":       2.4,
				"damage":     dmg,
				"combat":     combat,
				"sneak_shot": crouching,
			})

func _update_projectiles(dt: float) -> void:
	for i in range(projectiles.size() - 1, -1, -1):
		var p: Dictionary = projectiles[i]
		p["life"] -= dt
		var node: MeshInstance3D = p["node"]
		node.position += p["vel"] * dt
		var kill: bool = p["life"] <= 0.0
		if not kill and scene.has_method("get_height"):
			var gh: float = scene.get_height(node.position.x, node.position.z)
			if node.position.y < gh:
				kill = true
		if not kill:
			for enemy in enemies:
				if enemy.dead:
					continue
				var dxz: float = Vector2(enemy.position.x - node.position.x, enemy.position.z - node.position.z).length()
				var dy: float  = abs(enemy.position.y + 0.55 - node.position.y)
				if dxz < 0.95 and dy < 1.5:
					var dmg: float = p["damage"]
					if p["sneak_shot"] and not enemy.aggro:
						var sneak_mult: float = float(p["combat"].get("sneakMultiplier", 1.0))
						dmg *= sneak_mult
						EventBus.emit_event("quest:toast", {"text": "Sneak strike!"})
					enemy.hit(dmg, self)
					kill = true
					break
		if kill:
			# Scrap-Slinger: spawn impact spark at hit/death position
			if p.get("vfx_tag", "") == "scrapslinger" and is_instance_valid(node):
				_spawn_impact_spark(node.position)
			if is_instance_valid(node) and node.get_parent() != null:
				node.get_parent().remove_child(node)
			projectiles.remove_at(i)

# _spawn_impact_spark — Scrap-Slinger hit impact: bright burst GPUParticles3D
# one-shot at impact position; auto-frees after emission completes (~0.3s).
func _spawn_impact_spark(hit_pos: Vector3) -> void:
	if scene == null:
		return
	var sparks := GPUParticles3D.new()
	sparks.emitting      = true
	sparks.amount        = 14
	sparks.lifetime      = 0.28
	sparks.explosiveness = 0.92    # burst-like
	sparks.randomness    = 0.5
	sparks.one_shot      = true
	sparks.local_coords  = false
	sparks.position      = hit_pos
	var pm := ParticleProcessMaterial.new()
	pm.direction             = Vector3(0.0, 1.0, 0.0)
	pm.spread                = 85.0
	pm.initial_velocity_min  = 2.2
	pm.initial_velocity_max  = 5.5
	pm.gravity               = Vector3(0.0, -9.8, 0.0)
	pm.scale_min             = 0.05
	pm.scale_max             = 0.13
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.65, 0.1, 1.0))   # bright orange
	grad.set_color(1, Color(1.0, 0.3, 0.0, 0.0))    # fade to transparent red
	var gtex := GradientTexture1D.new()
	gtex.gradient = grad
	pm.color_ramp = gtex
	sparks.process_material = pm
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.10
	var smat := ToonMaterials.glow_mat(Color("#ff8c00"), 2.5)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.surface_set_material(0, smat)
	sparks.draw_pass_1 = sm
	scene.add_child(sparks)
	# Auto-free after one-shot emission completes (lifetime + small buffer)
	var t := Timer.new()
	t.wait_time = 0.55
	t.one_shot  = true
	t.autostart = true
	sparks.add_child(t)
	t.timeout.connect(func() -> void:
		if is_instance_valid(sparks) and sparks.get_parent() != null:
			sparks.get_parent().remove_child(sparks)
			sparks.queue_free()
	)

# ----------------------------------------------------------------
# nearest_interactable — planar distance (JS PlayerController.nearestInteractable)
func nearest_interactable() -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = INF
	for it in interactables:
		if not it.get("enabled", false):
			continue
		var it_pos: Vector3 = it.get("position", Vector3.ZERO)
		var r: float        = it.get("radius", 1.0)
		var d: float = Vector2(it_pos.x - position.x, it_pos.z - position.z).length() - r
		if d < 0.0 and d < best_d:
			best_d = d
			best   = it
	return best

# check_triggers — JS PlayerController.checkTriggers
func check_triggers() -> Dictionary:
	for tr in triggers:
		if tr.get("fired", true):
			continue
		var tr_pos: Vector3 = tr.get("position", Vector3.ZERO)
		var r: float        = tr.get("radius", 1.0)
		if position.distance_to(tr_pos) < r:
			tr["fired"] = true
			return tr
	return {}

# ----------------------------------------------------------------
# update — called from GameDirector._gameplay_update(dt)
func update(dt: float) -> void:
	if scene == null:
		return
	attack_cooldown = maxf(0.0, attack_cooldown - dt)
	_attack_pulse   = maxf(0.0, _attack_pulse - dt)   # Sprint L3: decay attack interrupt pulse

	# ---- planar input ----
	var ix: float = 0.0
	var iz: float = 0.0
	if _enabled:
		if _has_key(KEY_W) or _has_key(KEY_UP):    iz -= 1.0
		if _has_key(KEY_S) or _has_key(KEY_DOWN):   iz += 1.0
		if _has_key(KEY_A) or _has_key(KEY_LEFT):   ix -= 1.0
		if _has_key(KEY_D) or _has_key(KEY_RIGHT):  ix += 1.0
	var moving: bool = ix != 0.0 or iz != 0.0
	var want_sprint: bool = _has_key(KEY_SHIFT)

	# ---- stamina drain for sprint ----
	# NOTE: sprint intent (Shift) must win even while the crouch toggle is on, otherwise
	# a crouched player can never sprint → never slide. The FSM gives SPRINT priority over
	# crouch when stamina_ok, so we must grant stamina here regardless of `crouching`.
	var stamina_ok_for_sprint: bool = false
	if moving and want_sprint and grounded:
		stamina_ok_for_sprint = stats.drain_stamina(8.0, dt)   # ~15s sprint on a 120 pool

	# ---- detect edge inputs ----
	var crouch_just_pressed: bool = false
	# C key is toggled in _unhandled_input; detect the frame crouching just flipped on
	# We track this via a shadow bool that resets each frame.
	crouch_just_pressed = _crouch_just_pressed_this_frame
	_crouch_just_pressed_this_frame = false

	var cam_yaw_changed: bool = (cam_yaw != _last_cam_yaw)
	_last_cam_yaw = cam_yaw

	# ---- grass speed modifier ----
	var in_grass: bool = false
	if scene.has_method("is_in_grass"):
		in_grass = scene.is_in_grass(position)
	var grass_mult: float = passives.grass_speed_mult(in_grass)

	# ---- jump edge detect: consume SPACE once per press ----
	var jump_pressed: bool = false
	if _enabled and grounded and _has_key(KEY_SPACE) and stats.spend_stamina(4.0):
		jump_pressed = true
		_keys_down.erase(KEY_SPACE)

	# ---- Sprint L3: interrupt flags ----
	var forward_held: bool = _has_key(KEY_W) or _has_key(KEY_UP)

	# ---- build LSM input ----
	var lsm_inp: Dictionary = {
		"moving":               moving,
		"ix":                   ix,
		"iz":                   iz,
		"want_sprint":          want_sprint,
		"crouch":               crouching,
		"grounded":             grounded,
		"vel_y":                vel_y,
		"horiz_speed":          _horiz_speed,
		"jump_pressed":         jump_pressed,
		"stamina_ok_for_sprint": stamina_ok_for_sprint,
		"crouch_just_pressed":  crouch_just_pressed,
		"cam_yaw_changed":      cam_yaw_changed,
		"position_y":           position.y,
		"attacking":            _attack_pulse > 0.0,
		"ads_held":             _ads_held,
		"forward_held":         forward_held,
	}

	var lsm_out: Dictionary = _lsm.tick(lsm_inp, dt)
	loco_state = lsm_out["state"]
	var planar_speed: float  = lsm_out["planar_speed"]
	var air_control:  float  = lsm_out["air_control"]
	var sliding:      bool   = lsm_out["sliding"]
	var slide_speed:  float  = lsm_out["slide_speed"]
	var lock_horiz:   bool   = lsm_out["lock_horizontal"]
	_fov_target               = lsm_out["fov_target"]
	if _ads_held: _fov_target = _ads_fov
	var jump_vel:     float  = lsm_out["jump_velocity"]
	var launch_speed: float  = lsm_out.get("launch_speed", 0.0)

	# Sprint L2: detect leap launch (slide→jump) — carry horizontal momentum as air velocity.
	if launch_speed > 0.0:
		# _slide_dir holds the slide direction at the time of jump (cleared a few lines below).
		# Use the current slide dir if set; fall back to facing direction.
		var leap_dir: Vector3 = _slide_dir if _slide_dir.length_squared() > 0.001 else Vector3(sin(facing), 0.0, cos(facing))
		_air_vel = leap_dir * launch_speed
		_leaping = true

	# Update sprinting flag (for rig/passives)
	sprinting = (loco_state == "SPRINT")

	# Apply grass multiplier to planar speed
	planar_speed *= grass_mult

	# ---- aetherborn overclock ----
	passives.set_overclock(_enabled and _has_key(KEY_Q), dt)

	# ---- horizontal movement ----
	if not lock_horiz:
		if sliding:
			# Slide: maintain locked direction, steer within cap for Light subclasses.
			var max_deg: float = _lsm.get_slide_steer_max_deg()
			if max_deg > 0.001 and (ix != 0.0 or iz != 0.0):
				# Compute desired world direction from input (same formula as normal movement).
				var len: float = sqrt(ix * ix + iz * iz)
				var nix: float = ix / len
				var niz: float = iz / len
				var sin_y: float = sin(cam_yaw)
				var cos_y: float = cos(cam_yaw)
				var wx: float = niz * sin_y + nix * cos_y
				var wz: float = niz * cos_y - nix * sin_y
				var desired: Vector3 = Vector3(wx, 0.0, wz).normalized()
				# Work in angles (atan2(x,z) matches Vector3(sin(a),0,cos(a)) convention).
				var max_rad: float = deg_to_rad(max_deg)
				var entry_a: float = atan2(_slide_entry_dir.x, _slide_entry_dir.z)
				var cur_a:   float = atan2(_slide_dir.x, _slide_dir.z)
				var des_a:   float = atan2(desired.x, desired.z)
				# Clamp desired to within ±max_rad of entry angle.
				var off: float = wrapf(des_a - entry_a, -PI, PI)
				off = clampf(off, -max_rad, max_rad)
				var target_a: float = entry_a + off
				# Smooth rotate cur_a toward target_a at 120°/s.
				var step: float = deg_to_rad(120.0) * dt
				var da: float = wrapf(target_a - cur_a, -PI, PI)
				cur_a += clampf(da, -step, step)
				_slide_dir = Vector3(sin(cur_a), 0.0, cos(cur_a))
				# Rig turns into the slide direction.
				facing = cur_a
			position.x += _slide_dir.x * slide_speed * dt
			position.z += _slide_dir.z * slide_speed * dt
		elif _leaping and not grounded:
			# Sprint L2: leap air-movement — integrate carried horizontal velocity,
			# with input-steered blending scaled by the profile's air control.
			if ix != 0.0 or iz != 0.0:
				var len: float = sqrt(ix * ix + iz * iz)
				var nix: float = ix / len
				var niz: float = iz / len
				var sin_y: float = sin(cam_yaw)
				var cos_y: float = cos(cam_yaw)
				var wx: float = niz * sin_y + nix * cos_y
				var wz: float = niz * cos_y - nix * sin_y
				var desired: Vector3 = Vector3(wx, 0.0, wz).normalized()
				# Blend _air_vel toward desired direction at a rate scaled by air_control.
				# Light (0.75) → responsive sweep; Heavy (0.20) → mostly committed vault.
				var blend: float = clampf(air_control * dt * 3.0, 0.0, 1.0)
				_air_vel = _air_vel.lerp(desired * _air_vel.length(), blend)
			# Turn facing into air velocity direction.
			if _air_vel.length_squared() > 0.001:
				facing = atan2(_air_vel.x, _air_vel.z)
			position.x += _air_vel.x * dt
			position.z += _air_vel.z * dt
		elif moving and planar_speed > 0.0 and not _leaping:
			var len: float = sqrt(ix * ix + iz * iz)
			ix /= len
			iz /= len
			var sin_y: float = sin(cam_yaw)
			var cos_y: float = cos(cam_yaw)
			# Camera-relative (matches JS)
			var wx: float = iz * sin_y + ix * cos_y
			var wz: float = iz * cos_y - ix * sin_y
			# Air-momentum damp: a normal (non-leap) jump shouldn't broad-jump across the
			# map. Full speed on the ground; reduced horizontal carry while airborne.
			# The deliberate slide→leap (handled above via _air_vel) keeps its full reach.
			var air_damp: float = 1.0 if grounded else 0.55
			position.x += wx * planar_speed * air_control * air_damp * dt
			position.z += wz * planar_speed * air_control * air_damp * dt
			var target_facing: float = atan2(wx, wz)
			var d: float = target_facing - facing
			while d > PI:  d -= PI * 2.0
			while d < -PI: d += PI * 2.0
			facing += d * minf(1.0, dt * 14.0)

	# Update horizontal speed tracker for next LSM tick's horiz_speed
	_horiz_speed = Vector2(
		(position.x - _prev_position.x) / dt if dt > 0.0 else 0.0,
		(position.z - _prev_position.z) / dt if dt > 0.0 else 0.0
	).length()
	_prev_position = position

	# ---- move_speed_norm for rig (normalize by SPRINT fallback) ----
	move_speed_norm = (planar_speed / SPRINT) if (moving or sliding) else 0.0

	# ---- vertical (jump + gravity, analytic terrain Y) ----
	var ground_y: float = 0.0
	if scene.has_method("get_height"):
		ground_y = scene.get_height(position.x, position.z)

	if jump_vel > 0.0:
		vel_y    = jump_vel
		grounded = false
	vel_y     -= GRAVITY * dt
	position.y += vel_y * dt
	if position.y <= ground_y:
		position.y = ground_y
		vel_y      = 0.0
		var was_airborne: bool = not grounded
		grounded   = true

		# Sprint L2: leap landing resolution.
		if _leaping and was_airborne:
			# ---- Vanguard-only landing impact (warrior archetype) ----
			if save != null and save.class_id == "warrior":
				const LEAP_IMPACT_DMG: float = 18.0
				for enemy in enemies:
					if enemy.dead:
						continue
					var dxz: float = Vector2(enemy.position.x - position.x, enemy.position.z - position.z).length()
					if dxz <= 2.5:
						enemy.hit(LEAP_IMPACT_DMG, self)
			# ---- Camera thump feel (all archetypes) ----
			var mass_scale: float = 1.0
			if _lsm != null:
				# _mass_mult is an internal LSM field; approximate from air_control: heavier = lower ac.
				# Use a simple constant thump — mass scaling derived from air_control (inverted: heavy=low ac).
				mass_scale = clampf(1.0 + (0.5 - air_control) * 0.6, 0.7, 1.4)
			_cam_thump = 0.18 * mass_scale
			# Clear leap state.
			_air_vel = Vector3.ZERO
			_leaping = false

	# Capture slide direction on slide entry (only when we first start sliding).
	# Also record entry direction for steer-cap reference; reset both on exit.
	if sliding and _slide_dir == Vector3.ZERO:
		_slide_dir       = Vector3(sin(facing), 0.0, cos(facing))
		_slide_entry_dir = _slide_dir
	elif not sliding:
		if _was_sliding:
			# Slide just ended — auto-stand so the crouch toggle never leaves the player
			# stuck in a crouch pose while sprinting. (Normal crouch-walk is unaffected:
			# it never enters SLIDE, so _was_sliding stays false.)
			crouching = false
		_slide_dir       = Vector3.ZERO
		_slide_entry_dir = Vector3.ZERO
	_was_sliding = sliding

	# ---- bounds ----
	if scene.has_method("clamp_position"):
		position = scene.clamp_position(position)

	# ---- rig + camera ----
	rig.global_position = position
	rig.rotation.y      = facing
	rig.set_motion(move_speed_norm, crouching, sliding)
	# rig._process is called automatically by Godot each frame

	_update_projectiles(dt)
	stats.update(dt)
	# Sprint L2: decrement camera thump timer each frame.
	if _cam_thump > 0.0:
		_cam_thump = maxf(0.0, _cam_thump - dt)
	_sync_camera(minf(1.0, dt * 7.0))

	# ---- FOV kick (lerp toward target) ----
	if cam != null:
		cam.fov = lerp(cam.fov, _fov_target, minf(1.0, dt * 8.0))

# ---- Helpers for horizontal-speed tracking (PRD-003) ----
var _horiz_speed: float   = 0.0
var _prev_position: Vector3 = Vector3.ZERO

# ---- crouch-just-pressed edge detector ----
# Set to true in _unhandled_input when C is pressed; cleared each update tick.
var _crouch_just_pressed_this_frame: bool = false

# ---- sync_camera (JS PlayerController.syncCamera) ----
func _sync_camera(blend: float) -> void:
	if cam == null:
		return
	# Smoothly lerp effective camera distance and shoulder offset toward ADS or normal targets.
	var dist_goal: float     = _ads_cam_dist if _ads_held else cam_dist
	var shoulder_goal: float = _ads_shoulder if _ads_held else CAM_SHOULDER
	_cam_dist_eff = lerp(_cam_dist_eff, dist_goal, blend)
	_shoulder_eff = lerp(_shoulder_eff, shoulder_goal, blend)
	var head_y: float = 1.5 * rig.scale.y
	# Sprint L2: camera thump — transient downward dip on leap landing (subtle, self-canceling).
	var thump_offset: float = 0.0
	if _cam_thump > 0.0:
		# Sine curve over timer: peaks at t=thump_max/2, returns to 0 at t=0.
		# We advance the timer in the update loop; here we compute the current dip from remaining time.
		# Use a simple ramp-down: full dip at start, zero at end. Max dip ~0.12 m.
		thump_offset = -0.12 * (_cam_thump / 0.18)
	var target := position + Vector3(0.0, head_y + thump_offset, 0.0)
	var cp: float = cos(cam_pitch)
	var sp: float = sin(cam_pitch)
	# Camera-right vector perpendicular to yaw (horizontal plane).
	# Camera sits over the character's RIGHT shoulder; both the camera position
	# AND the look target shift by `shoulder`, so the view truly pans sideways and
	# the character ends up framed slightly left (centered crosshair = clear sight).
	var right := Vector3(cos(cam_yaw), 0.0, -sin(cam_yaw))
	var shoulder := right * _shoulder_eff
	var desired := Vector3(
		target.x + sin(cam_yaw) * cp * _cam_dist_eff,
		target.y + sp * _cam_dist_eff,
		target.z + cos(cam_yaw) * cp * _cam_dist_eff
	) + shoulder
	# Camera-terrain collision: march from the player toward the orbit point and
	# pull the camera in to just before the first terrain hit, so the lens never
	# enters a hill. A camera inside terrain back-face-culls the slope, making the
	# hill look "see-through" (trees behind it become visible).
	if scene != null and scene.has_method("get_height"):
		var steps := 16
		var safe_t := 1.0
		for i in range(1, steps + 1):
			var t: float = float(i) / float(steps)
			var p := target.lerp(desired, t)
			if p.y < scene.get_height(p.x, p.z) + 0.6:
				safe_t = float(i - 1) / float(steps)
				break
		desired = target.lerp(desired, safe_t)
	# Clamp inline — scene.clamp_camera passes Vector3 by value so it can't modify desired
	if scene != null and scene.has_method("get_bounds"):
		var bounds: Dictionary = scene.get_bounds()
		desired.x = clamp(desired.x, bounds.get("x_min", -999.0), bounds.get("x_max", 999.0))
		desired.z = clamp(desired.z, bounds.get("z_min", -999.0), bounds.get("z_max", 999.0))
		desired.y = clamp(desired.y, bounds.get("y_min", 0.35),   bounds.get("y_max", 999.0))
	cam.position = cam.position.lerp(desired, blend)
	# Hard floor after the blend so a fast tween never dips the lens into the ground.
	if scene != null and scene.has_method("get_height"):
		var floor_y: float = scene.get_height(cam.position.x, cam.position.z) + 0.4
		if cam.position.y < floor_y:
			cam.position.y = floor_y
	cam.look_at(target + shoulder)
