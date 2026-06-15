# player_controller.gd — Third-person player controller.
# Port of src/gameplay/PlayerController.js — all constants preserved exactly.
#
# Y-AXIS PARITY NOTE: This controller drives Y analytically from scene.get_height()
# (same approach as the JS). CharacterBody3D / move_and_slide() is NOT used for
# terrain following — that would add physics overhead and change the feel. The
# capsule CollisionShape3D is kept for future physics layers (push-back vs. walls
# already handled by clamp_position per-scene). This matches the JS exactly and
# is the documented deviation.
class_name PlayerController extends CharacterBody3D

# ---- movement constants (JS exactly) ----
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

var _enabled: bool = false

# ---- mouse sensitivity ----
var sens_x: float = 1.0
var sens_y: float = 1.0

# ---- input state ----
var _keys_down: Dictionary = {}   # keyed by event physical_keycode
var _mouse_captured: bool  = false

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

func setup(p_rig: CharacterRig, p_stats: Stats, p_passives: Passives, p_save: SaveState, p_cam: Camera3D) -> void:
	rig      = p_rig
	stats    = p_stats
	passives = p_passives
	save     = p_save
	cam      = p_cam

var enabled: bool:
	get: return _enabled
	set(v):
		_enabled = v
		if not v and _mouse_captured:
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
	cam_pitch = 0.3
	rig.global_position = sp
	rig.rotation.y      = facing

	# Wire alias arrays
	interactables = new_scene.interactables if new_scene.get("interactables") != null else []
	triggers      = new_scene.triggers      if new_scene.get("triggers")      != null else []

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
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and _enabled:
			cam_dist = clampf(cam_dist + 0.0035 * 40.0, CAM_DIST_MIN, CAM_DIST_MAX)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and _enabled:
			cam_dist = clampf(cam_dist - 0.0035 * 40.0, CAM_DIST_MIN, CAM_DIST_MAX)

	elif event is InputEventMouseMotion and _mouse_captured and _enabled:
		var mm := event as InputEventMouseMotion
		cam_yaw   -= mm.relative.x * 0.0052 * sens_x
		cam_pitch  = clampf(cam_pitch + mm.relative.y * 0.0045 * sens_y, CAM_PITCH_MIN, CAM_PITCH_MAX)

	elif event is InputEventKey:
		var ke := event as InputEventKey
		var kc: int = ke.physical_keycode
		if ke.pressed and not ke.echo:
			_keys_down[kc] = true
			if not _enabled:
				return
			if kc == KEY_C:
				crouching = not crouching
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
		rig.play_attack("bolt")
		_spawn_projectile(combat, Color("#7adfff"), 0.13, false)
	elif style == "arrow":
		if not stats.spend_stamina(float(combat.get("staminaCost", 8))):
			return
		attack_cooldown = float(combat.get("cooldown", 0.45))
		rig.play_attack("melee")
		_spawn_projectile(combat, Color("#d8e8c8"), 0.05, true)
	else:  # melee
		if not stats.spend_stamina(float(combat.get("staminaCost", 12))):
			return
		attack_cooldown = float(combat.get("cooldown", 0.65)) * passives.attack_cooldown_mult()
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
			if is_instance_valid(node) and node.get_parent() != null:
				node.get_parent().remove_child(node)
			projectiles.remove_at(i)

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

	sprinting = false
	var speed: float = CROUCH if crouching else WALK
	if moving and want_sprint and not crouching and stats.drain_stamina(15.0, dt):
		speed    = SPRINT
		sprinting = true

	var in_grass: bool = false
	if scene.has_method("is_in_grass"):
		in_grass = scene.is_in_grass(position)
	speed *= passives.grass_speed_mult(in_grass)

	if moving:
		var len: float = sqrt(ix * ix + iz * iz)
		ix /= len
		iz /= len
		var sin_y: float = sin(cam_yaw)
		var cos_y: float = cos(cam_yaw)
		# Camera-relative (matches JS)
		var wx: float = iz * sin_y + ix * cos_y
		var wz: float = iz * cos_y - ix * sin_y
		position.x += wx * speed * dt
		position.z += wz * speed * dt
		var target_facing: float = atan2(wx, wz)
		var d: float = target_facing - facing
		while d > PI:  d -= PI * 2.0
		while d < -PI: d += PI * 2.0
		facing += d * minf(1.0, dt * 14.0)

	move_speed_norm = (speed / SPRINT) if moving else 0.0

	# ---- aetherborn overclock ----
	passives.set_overclock(_enabled and _has_key(KEY_Q), dt)

	# ---- vertical (jump + gravity, analytic terrain Y) ----
	var ground_y: float = 0.0
	if scene.has_method("get_height"):
		ground_y = scene.get_height(position.x, position.z)
	if _enabled and grounded and _has_key(KEY_SPACE) and stats.spend_stamina(7.0):
		vel_y    = JUMP_V
		grounded = false
		_keys_down.erase(KEY_SPACE)
	vel_y     -= GRAVITY * dt
	position.y += vel_y * dt
	if position.y <= ground_y:
		position.y = ground_y
		vel_y      = 0.0
		grounded   = true

	# ---- bounds ----
	if scene.has_method("clamp_position"):
		position = scene.clamp_position(position)

	# ---- rig + camera ----
	rig.global_position = position
	rig.rotation.y      = facing
	rig.set_motion(move_speed_norm, crouching)
	# rig._process is called automatically by Godot each frame

	_update_projectiles(dt)
	stats.update(dt)
	_sync_camera(minf(1.0, dt * 7.0))

# ---- sync_camera (JS PlayerController.syncCamera) ----
func _sync_camera(blend: float) -> void:
	if cam == null:
		return
	var head_y: float = 1.5 * rig.scale.y
	var target := position + Vector3(0.0, head_y, 0.0)
	var cp: float = cos(cam_pitch)
	var sp: float = sin(cam_pitch)
	# Camera-right vector perpendicular to yaw (horizontal plane).
	# Camera sits over the character's RIGHT shoulder; both the camera position
	# AND the look target shift by `shoulder`, so the view truly pans sideways and
	# the character ends up framed slightly left (centered crosshair = clear sight).
	var right := Vector3(cos(cam_yaw), 0.0, -sin(cam_yaw))
	var shoulder := right * CAM_SHOULDER
	var desired := Vector3(
		target.x + sin(cam_yaw) * cp * cam_dist,
		target.y + sp * cam_dist,
		target.z + cos(cam_yaw) * cp * cam_dist
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
