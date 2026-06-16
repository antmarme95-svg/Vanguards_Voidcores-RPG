# enemy_ai.gd — Maddened Gloomfang beast. Port of src/gameplay/EnemyAI.js.
# All JS FSM constants, health value, damage, and detection radius preserved exactly.
class_name MaddenedBeast extends Node3D

const BASE_DETECT := 11.0

# ---- stats ----
var health: float    = 52.0
var max_health: float = 52.0
var dead: bool       = false
var aggro: bool      = false

# ---- FSM ----
var state: String    = "roam"
var state_t: float   = 0.0
var _t: float        = 0.0

# ---- movement ----
var home: Vector3       = Vector3.ZERO
# "position" is a reserved Node3D property — we shadow it via the Node3D.position property
var wander_target: Vector3 = Vector3.ZERO
var wander_timer: float    = 0.0
var facing: float          = 0.0

# ---- lunge ----
var lunge_dir: Vector3    = Vector3.ZERO
var lunge_hit_done: bool  = false

# ---- hit flash ----
var flash_t: float = 0.0

# ---- scene ref (for get_height) ----
var _scene: Node3D = null

# ---- visual parts ----
var _body_mi: MeshInstance3D       = null
var _fur_mat: ShaderMaterial       = null
var _dark_mat: ShaderMaterial      = null
var _crystal_mat: StandardMaterial3D = null
var _legs: Array                   = []
var _group: Node3D                 = null   # root of visual, equals self

# ---- off-screen culling ----
# VisibleOnScreenNotifier3D tracks whether any part of this beast is in the camera frustum.
# When off-screen AND not in an active-combat state, we skip expensive per-frame
# cosmetic work (leg scuttle, crystal pulse, hit-flash colour updates).
# AI position/terrain-snap still runs every frame so beasts don't desync.
var _on_screen: bool               = true   # conservative default = always process
var _screen_notifier: VisibleOnScreenNotifier3D = null

# ================================================================
func _init(spawn_pos: Vector3, scene: Node3D) -> void:
	_scene        = scene
	home          = spawn_pos
	position      = spawn_pos
	wander_target = spawn_pos
	facing        = randf() * TAU
	_t            = randf() * 10.0

func _ready() -> void:
	_build()
	_setup_screen_notifier()

func _setup_screen_notifier() -> void:
	# AABB covers the beast body (roughly 0.6 wide × 1.0 tall × 0.6 deep, centred at 0.5 Y).
	# A slight margin ensures the notifier triggers slightly before the mesh becomes visible,
	# avoiding the 1-frame cosmetic pop when the beast enters the frustum.
	_screen_notifier = VisibleOnScreenNotifier3D.new()
	_screen_notifier.aabb = AABB(Vector3(-0.5, 0.0, -0.5), Vector3(1.0, 1.1, 1.0))
	add_child(_screen_notifier)
	_screen_notifier.screen_entered.connect(func() -> void: _on_screen = true)
	_screen_notifier.screen_exited.connect(func() -> void: _on_screen = false)

func _build() -> void:
	_group = self

	_fur_mat = ToonMaterials.toon_mat(Color("#564a6b"))
	_dark_mat = ToonMaterials.toon_mat(Color("#3c3450"))
	_crystal_mat = ToonMaterials.glow_mat(Color("#ff2336"), 1.1)
	var eye_mat: StandardMaterial3D = ToonMaterials.glow_mat(Color("#ff4444"), 1.4)

	# Body (horizontal capsule)
	var body_mi := MeshInstance3D.new()
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.3
	body_mesh.height = 0.65 + 0.3 * 2.0
	body_mi.mesh = body_mesh
	body_mi.material_override = _fur_mat
	body_mi.rotation.x = PI / 2.0
	body_mi.position.y = 0.52
	add_child(body_mi)
	_body_mi = body_mi

	# Head group
	var head_g := Node3D.new()
	head_g.position = Vector3(0.0, 0.66, 0.62)

	var skull_mi := MeshInstance3D.new()
	var skull_mesh := SphereMesh.new()
	skull_mesh.radius = 0.23
	skull_mesh.height = 0.46
	skull_mi.mesh = skull_mesh
	skull_mi.material_override = _fur_mat
	head_g.add_child(skull_mi)

	var snout_mi := MeshInstance3D.new()
	var snout_mesh := BoxMesh.new()
	snout_mesh.size = Vector3(0.2, 0.14, 0.26)
	snout_mi.mesh = snout_mesh
	snout_mi.material_override = _dark_mat
	snout_mi.position = Vector3(0.0, -0.06, 0.2)
	head_g.add_child(snout_mi)

	for side in [-1, 1]:
		var ear_mi := MeshInstance3D.new()
		var ear_mesh := CylinderMesh.new()
		ear_mesh.top_radius    = 0.001
		ear_mesh.bottom_radius = 0.07
		ear_mesh.height        = 0.2
		ear_mi.mesh = ear_mesh
		ear_mi.material_override = _dark_mat
		ear_mi.position = Vector3(float(side) * 0.13, 0.2, -0.05)
		ear_mi.rotation.z = float(side) * -0.4
		head_g.add_child(ear_mi)

		var eye_mi := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.045
		eye_mesh.height = 0.09
		eye_mi.mesh = eye_mesh
		eye_mi.material_override = eye_mat
		eye_mi.position = Vector3(float(side) * 0.11, 0.04, 0.18)
		head_g.add_child(eye_mi)

	# Brow shard
	var brow_mi := MeshInstance3D.new()
	var brow_mesh := BoxMesh.new()
	brow_mesh.size = Vector3(0.14, 0.14, 0.14)   # OctahedronGeometry(0.07) approx
	brow_mi.mesh = brow_mesh
	brow_mi.material_override = _crystal_mat
	brow_mi.position = Vector3(0.0, 0.16, 0.12)
	brow_mi.scale.y = 1.8
	head_g.add_child(brow_mi)

	add_child(head_g)

	# Legs (4)
	_legs = []
	var leg_defs := [
		Vector3(-0.2, 0.21, 0.32),
		Vector3( 0.2, 0.21, 0.32),
		Vector3(-0.2, 0.21, -0.32),
		Vector3( 0.2, 0.21, -0.32),
	]
	for lp in leg_defs:
		var leg_mi := MeshInstance3D.new()
		var leg_mesh := CylinderMesh.new()
		leg_mesh.top_radius    = 0.07
		leg_mesh.bottom_radius = 0.05
		leg_mesh.height        = 0.42
		leg_mi.mesh = leg_mesh
		leg_mi.material_override = _dark_mat
		leg_mi.position = lp
		add_child(leg_mi)
		_legs.append(leg_mi)

	# Spine shards (3)
	for i in range(3):
		var shard_mi := MeshInstance3D.new()
		var shard_mesh := BoxMesh.new()
		var sz: float = (0.11 - float(i) * 0.02) * 1.4
		shard_mesh.size = Vector3(sz, sz, sz)
		shard_mi.mesh = shard_mesh
		shard_mi.material_override = _crystal_mat
		shard_mi.position = Vector3(0.0, 0.85 - float(i) * 0.04, 0.18 - float(i) * 0.3)
		shard_mi.scale.y   = 2.0
		shard_mi.rotation.z = (float(i) - 1.0) * 0.25
		add_child(shard_mi)

	# Tail
	var tail_mi := MeshInstance3D.new()
	var tail_mesh := CylinderMesh.new()
	tail_mesh.top_radius    = 0.001
	tail_mesh.bottom_radius = 0.07
	tail_mesh.height        = 0.4
	tail_mi.mesh = tail_mesh
	tail_mi.material_override = _dark_mat
	tail_mi.position = Vector3(0.0, 0.6, -0.62)
	tail_mi.rotation.x = -1.1
	add_child(tail_mi)

# ================================================================
# Public API
# ================================================================

## hit — called by PlayerController on melee/projectile contact
func hit(dmg: float, controller: PlayerController) -> void:
	if dead:
		return
	health -= dmg
	flash_t = 0.12
	aggro   = true
	if health <= 0.0:
		state    = "dying"
		state_t  = 0.0
	elif state != "lunge":
		# Flinch knockback (JS: away from attacker)
		var away: Vector3 = (position - controller.position)
		away.y = 0.0
		if away.length() > 0.0001:
			position += away.normalized() * 0.35

## _detection_radius — JS MaddenedBeast._detectionRadius
func _detection_radius(controller: PlayerController, passives: Passives) -> float:
	var r: float = BASE_DETECT * passives.detection_mult()
	if controller.is_sneaking():
		r *= 0.5
		# Sneak skill shrinks it further (JS: r *= 2 - controller.stats.skillBonus("Sneak", 0.025))
		r *= 2.0 - controller.stats.skill_bonus("Sneak", 0.025)
	return maxf(2.5, r)

# ================================================================
# update — called from GameDirector._gameplay_update each frame
# ================================================================
func update_ai(dt: float, controller: PlayerController, passives: Passives) -> void:
	if dead:
		return
	_t      += dt
	state_t += dt
	flash_t  = maxf(0.0, flash_t - dt)

	# Hit flash — only push shader params when the flash state changes or is active.
	# Skip the set_shader_parameter overhead every frame for roaming off-screen beasts.
	var flash: bool = flash_t > 0.0
	if flash or _on_screen:
		var fur_col   := Color("#ffffff") if flash else Color("#564a6b")
		var dark_col  := Color("#ffffff") if flash else Color("#3c3450")
		_fur_mat.set_shader_parameter("albedo_color", fur_col)
		_dark_mat.set_shader_parameter("albedo_color", dark_col)

	var player_pos: Vector3 = controller.position
	var to_player: Vector3  = (player_pos - position)
	to_player.y = 0.0
	var dist: float = to_player.length()

	match state:
		"roam":
			wander_timer -= dt
			if wander_timer <= 0.0:
				wander_timer = 2.5 + randf() * 3.0
				var a: float = randf() * TAU
				wander_target = Vector3(
					home.x + cos(a) * 6.0,
					0.0,
					home.z + sin(a) * 6.0
				)
			var to_t: Vector3 = (wander_target - position)
			to_t.y = 0.0
			if to_t.length() > 0.5:
				to_t = to_t.normalized()
				position += to_t * 1.25 * dt
				_face_dir(to_t, dt, 4.0)
			if aggro or dist < _detection_radius(controller, passives):
				aggro   = true
				state   = "chase"
				state_t = 0.0

		"chase":
			if dist > 1.95:
				var tp: Vector3 = to_player.normalized()
				position += tp * 4.9 * dt
				_face_dir(tp, dt, 8.0)
			else:
				state   = "windup"
				state_t = 0.0

		"windup":
			_face_dir(to_player.normalized(), dt, 10.0)
			scale.y = 1.0 - minf(0.25, state_t * 0.7)
			if state_t > 0.42:
				state          = "lunge"
				state_t        = 0.0
				scale.y        = 1.0
				lunge_dir      = to_player.normalized()
				lunge_hit_done = false

		"lunge":
			position += lunge_dir * 9.5 * dt
			if not lunge_hit_done and dist < 1.25:
				lunge_hit_done = true
				controller.stats.take_damage(13.0)
			if state_t > 0.34:
				state   = "recover"
				state_t = 0.0

		"recover":
			if state_t > 0.75:
				state   = "chase"
				state_t = 0.0

		"dying":
			var shrink: float = maxf(0.001, 1.0 - dt * 2.4)
			scale *= shrink
			rotation.z += dt * 3.0
			if state_t > 0.9:
				dead     = true
				visible  = false
				EventBus.emit_event("combat:enemyDown", {})
			return

	# Terrain snap
	var ground_y: float = 0.0
	if _scene != null and _scene.has_method("get_height"):
		ground_y = _scene.get_height(position.x, position.z)
	var beast_moving: bool = state == "chase" or state == "lunge" or state == "roam"
	position.y = ground_y

	# Bob when moving
	global_position = position
	global_position.y += abs(sin(_t * 9.0)) * 0.08 if beast_moving else 0.0

	rotation.y = facing

	# ---- cosmetic-only updates: skip when off-screen and not in active combat ----
	# "active combat" = windup/lunge/recover or aggro+chase — beast is close enough
	# to the player that it's almost certainly on screen; safety net keeps visuals correct.
	var in_active_combat: bool = (state == "windup" or state == "lunge" or state == "recover"
		or (aggro and state == "chase"))
	var do_cosmetics: bool = _on_screen or in_active_combat

	if do_cosmetics:
		# Leg scuttle
		for i in range(_legs.size()):
			_legs[i].rotation.x = sin(_t * 11.0 + float(i) * 1.7) * 0.5 if beast_moving else 0.0

		# Crystal pulse
		var pulse: float
		if aggro:
			pulse = 1.2 + sin(_t * 9.0) * 0.45
		else:
			pulse = 0.85 + sin(_t * 3.0) * 0.15
		var cry_col := Color("#ff2336") * pulse
		_crystal_mat.albedo_color = cry_col
		_crystal_mat.emission     = cry_col

func _face_dir(dir: Vector3, dt: float, rate: float) -> void:
	var target_y: float = atan2(dir.x, dir.z)
	var d: float        = target_y - facing
	while d > PI:  d -= PI * 2.0
	while d < -PI: d += PI * 2.0
	facing += d * minf(1.0, dt * rate)
