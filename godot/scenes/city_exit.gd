## city_exit.gd — The deployment corridor. Direct port of CityExit.js.
## Corridor walls, glowing window slits, rib arches, lamps, banners,
## frontier gate with rising portcullis, two guards, and a toWilds trigger.
class_name CityExit extends Node3D

const HALF_W = 4.0
const GATE_Z = -48.0
const END_Z  = -58.0

# Gameplay data
var player_spawn: Dictionary = {}
var interactables: Array = []
var triggers: Array = []

# Runtime
var _t: float = 0.0
var _gate_open: float = 0.0      # 0 = closed, 1 = fully raised
var _gate_node: Node3D = null
var _guards: Array = []
var _origin: Dictionary = {}

func _init(origin: Dictionary) -> void:
	_origin = origin

func _ready() -> void:
	var theme: Dictionary = _origin.get("theme", {})
	_build_environment(theme)
	_build_street(theme)
	_build_walls(theme)
	_build_arches(theme)
	_build_lamps_banners(theme)
	_build_gate(theme)
	_build_guards(theme)
	_build_lights(theme)
	_setup_metadata()

# ================================================================
func _build_environment(theme: Dictionary) -> void:
	var we = WorldEnvironment.new()
	var env = Environment.new()
	var fog_col = Color(theme.get("fog", "#9fd0e8"))
	env.background_mode = Environment.BG_COLOR
	env.background_color = fog_col
	# Fog — JS: Fog(theme.fog, 18, 85)
	env.fog_enabled = true
	env.fog_light_color = fog_col
	env.fog_density = 0.003
	env.fog_aerial_perspective = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(theme.get("ambient", "#9fb8d8"))
	env.ambient_light_energy = 0.20
	# ---- Glow/Bloom — halos on aether pipes, window slits, gate glow ----
	env.glow_enabled = true
	env.glow_normalized = false
	env.glow_intensity = 0.20
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 1.1
	env.glow_hdr_luminance_cap = 2.5
	env.glow_hdr_scale = 2.0
	env.glow_strength = 1.0
	env.set_glow_level(0, 0.6)
	env.set_glow_level(1, 0.5)
	env.set_glow_level(2, 0.3)
	env.set_glow_level(3, 0.0)
	env.set_glow_level(4, 0.0)
	env.set_glow_level(5, 0.0)
	env.set_glow_level(6, 0.0)
	we.environment = env
	add_child(we)

	# Sky dome
	var sky_col = Color(theme.get("sky", "#7fd4ff"))
	add_child(Props.sky_dome(sky_col, fog_col))

# ================================================================
func _build_street(theme: Dictionary) -> void:
	# Street: slate-dark floor (#8a96a8 family) so lamps read as bright accents
	# Override theme floor to be darker regardless of origin theme
	var floor_col = Color("#8a96a8")
	var street = _box_mi(
		Vector3(HALF_W * 2.0 + 1.0, 0.2, 70.0),
		ToonMaterials.toon_mat(floor_col)
	)
	street.position = Vector3(0.0, -0.1, -26.0)
	add_child(street)

	# Green frontier haze beyond the gate
	var wilds_mat = ToonMaterials.glow_mat(Color("#7fc46a"), 0.5)
	var wilds_mi = _box_mi(Vector3(40.0, 0.2, 14.0), wilds_mat)
	wilds_mi.position = Vector3(0.0, 5.0, END_Z - 16.0)
	add_child(wilds_mi)

	# Ambient pipe-glow motes
	var pipe_glow = Color(theme.get("pipeGlow", "#46e6ff"))
	add_child(Props.motes(60, pipe_glow, 30.0, 0.06, 8.0))

# ================================================================
func _build_walls(theme: Dictionary) -> void:
	var wall_mat = ToonMaterials.toon_mat(Color(theme.get("wall", "#8fa6c4")))
	var trim_mat = ToonMaterials.toon_mat(Color(theme.get("trim", "#e8eef8")))
	var pipe_glow = Color(theme.get("pipeGlow", "#46e6ff"))

	for side in [-1, 1]:
		for i in range(6):
			var z = 2.0 - float(i) * 9.5
			# Height varies to create a varied skyline
			var h = 4.5 + float((i * 7 + (3 if side > 0 else 0)) % 4) * 1.4
			var block = _box_mi(Vector3(3.0, h, 8.5), wall_mat)
			block.position = Vector3(float(side) * (HALF_W + 1.6), h * 0.5, z)
			add_child(block)

			var roof = _box_mi(Vector3(3.3, 0.35, 8.8), trim_mat)
			roof.position = Vector3(float(side) * (HALF_W + 1.6), h + 0.18, z)
			add_child(roof)

			# Glowing window slits
			var win_mat = ToonMaterials.glow_mat(pipe_glow, 0.85)
			var wy = 1.6
			while wy < h - 0.8:
				var win = _box_mi(Vector3(0.3, 0.55, 0.05), win_mat)
				var wz_offset = z - 2.5 + fmod(wy * 13.0, 5.0)
				win.position = Vector3(float(side) * (HALF_W + 0.08), wy, wz_offset)
				if side > 0:
					win.rotation.y = -PI * 0.5
				else:
					win.rotation.y = PI * 0.5
				add_child(win)
				wy += 1.7

		# Pipe run down the whole street (aether_pipe approximated with cylinders)
		var side_f = float(side)
		var pipe = Props.aether_pipe([
			Vector3(side_f * (HALF_W - 0.1), 3.4, 2.0),
			Vector3(side_f * (HALF_W - 0.3), 3.9, -22.0),
			Vector3(side_f * (HALF_W - 0.1), 3.4, -46.0),
		], pipe_glow, 0.08)
		add_child(pipe)

# ================================================================
func _build_arches(theme: Dictionary) -> void:
	var trim_col = Color(theme.get("trim", "#e8eef8"))
	# rib_arc spans left(-r,0) → apex(0,r) → right(+r,0) in XY plane.
	# Feet are at y=0 by construction; position at street level directly.
	var z = -6.0
	while z > GATE_Z + 4.0:
		var arch = Props.rib_arc(HALF_W + 0.6, trim_col)
		arch.position = Vector3(0.0, 0.0, z)
		add_child(arch)
		z -= 12.0

# ================================================================
func _build_lamps_banners(theme: Dictionary) -> void:
	var pipe_glow = Color(theme.get("pipeGlow", "#46e6ff"))

	# Crystal lamps on both sides at intervals
	var lz = -2.0
	while lz > GATE_Z:
		for side in [-1, 1]:
			var lamp = Props.crystal_lamp(pipe_glow, 2.4)
			lamp.position = Vector3(float(side) * (HALF_W - 0.5), 0.0, lz - 3.0)
			add_child(lamp)
		lz -= 11.0

	# Large banner over the gate
	var b = Props.banner(_origin.get("theme", {}))
	b.position = Vector3(0.0, 3.6, GATE_Z + 0.6)
	b.scale = Vector3(1.6, 1.6, 1.6)
	add_child(b)

# ================================================================
func _build_gate(theme: Dictionary) -> void:
	var trim_mat = ToonMaterials.toon_mat(Color(theme.get("trim", "#e8eef8")))
	var bar_mat  = ToonMaterials.toon_mat(Color("#2e3440"))
	var pipe_glow = Color(theme.get("pipeGlow", "#46e6ff"))

	# Gate frame — two posts + lintel
	var frame = Node3D.new()
	for side in [-1, 1]:
		var post = _box_mi(Vector3(0.8, 5.4, 0.8), trim_mat)
		post.position = Vector3(float(side) * (HALF_W - 0.2), 2.7, GATE_Z)
		frame.add_child(post)
	var lintel = _box_mi(Vector3(HALF_W * 2.0 + 1.0, 0.9, 0.9), trim_mat)
	lintel.position = Vector3(0.0, 5.2, GATE_Z)
	frame.add_child(lintel)
	add_child(frame)

	# Portcullis (bars + glow bottom)
	_gate_node = Node3D.new()
	var bar_height = 4.6
	var x = -HALF_W + 0.8
	while x <= HALF_W - 0.8:
		var bar = MeshInstance3D.new()
		var bmesh = CylinderMesh.new()
		bmesh.top_radius = 0.06
		bmesh.bottom_radius = 0.06
		bmesh.height = bar_height
		bar.mesh = bmesh
		bar.material_override = bar_mat
		bar.position = Vector3(x, bar_height * 0.5, 0.0)
		_gate_node.add_child(bar)
		x += 0.55

	var gate_glow_mat = ToonMaterials.glow_mat(pipe_glow, 1.0)
	var gate_glow = _box_mi(Vector3(HALF_W * 2.0 - 1.4, 0.08, 0.08), gate_glow_mat)
	gate_glow.position = Vector3(0.0, 0.35, 0.0)
	_gate_node.add_child(gate_glow)

	_gate_node.position = Vector3(0.0, 0.0, GATE_Z)
	add_child(_gate_node)

# ================================================================
func _build_guards(theme: Dictionary) -> void:
	var accent = Color(theme.get("accent", "#46e6ff"))
	for side in [-1, 1]:
		var guard = CharacterRig.new()
		add_child(guard)
		guard.position = Vector3(float(side) * (HALF_W - 1.1), 0.0, GATE_Z + 2.2)
		guard.rotation.y = PI  # face incoming player
		guard.apply_phenotype(
			{
				"weight": 0.8, "height": 0.6, "arcaneMod": 0.3,
				"jaw": 0.8, "cheek": 0.4, "eyeTilt": 0.4, "eyeShape": 0.35,
				"hair": 6, "beard": (3 if side > 0 else 0),
				"hairColor": 9, "skinTone": (2 if side > 0 else 5),
				"warpaint": 0, "paintColor": 0,
			},
			_origin
		)
		_guards.append(guard)

# ================================================================
func _build_lights(theme: Dictionary) -> void:
	# Key directional — low dusk angle so the floor stays in mid-ramp, not full-bright
	var sun = DirectionalLight3D.new()
	sun.light_color = Color("#ffe8c0")
	sun.light_energy = 0.65
	sun.rotation_degrees = Vector3(-28.0, -20.0, 0.0)  # grazing angle = floor in shadow band
	sun.shadow_enabled = true
	# PCF soft shadows — guards and gate cast grounding shadows
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 80.0
	sun.shadow_bias = 0.05
	sun.shadow_normal_bias = 1.2
	add_child(sun)

	# Side fill — slate-blue from the side keeps walls dark, doesn't flood floor
	var fill = DirectionalLight3D.new()
	fill.light_color = Color("#8ea8c8")
	fill.light_energy = 0.20
	fill.rotation_degrees = Vector3(-30.0, 90.0, 0.0)  # from the side
	fill.shadow_enabled = false
	add_child(fill)

# ================================================================
func _setup_metadata() -> void:
	player_spawn = {
		"position": Vector3(0.0, 0.0, 0.0),
		"yaw": PI,
	}
	interactables = []
	triggers = [
		{
			"id": "toWilds",
			"position": Vector3(0.0, 0.0, END_Z + 2.0),
			"radius": 3.5,
			"fired": false,
		},
	]

# ================================================================
# Public API
# ================================================================
func get_height(_x: float = 0.0, _z: float = 0.0) -> float:
	return 0.0

func clamp_camera(pos: Vector3) -> void:
	pos.x = clamp(pos.x, -HALF_W + 0.3, HALF_W - 0.3)
	pos.z = clamp(pos.z, END_Z, 4.2)
	if pos.y < 0.35:
		pos.y = 0.35

func clamp_position(pos: Vector3) -> void:
	pos.x = clamp(pos.x, -HALF_W + 0.4, HALF_W - 0.4)
	var gate_blocked = _gate_open < 0.85
	var min_z = GATE_Z + 1.0 if gate_blocked else END_Z - 1.0
	pos.z = clamp(pos.z, min_z, 2.5)

func is_in_grass(_pos: Vector3 = Vector3.ZERO) -> bool:
	return false

# ================================================================
# update — call from parent per frame (mirroring JS update(dt, playerPos))
func update(delta: float, player_pos: Vector3) -> void:
	_t += delta
	var near = player_pos.z < GATE_Z + 14.0
	_gate_open = clamp(_gate_open + (0.45 * delta if near else -0.3 * delta), 0.0, 1.0)
	if _gate_node != null:
		_gate_node.position.y = _gate_open * 4.4

func _process(delta: float) -> void:
	_t += delta
	# In autotest mode there is no player; advance gate slightly so it renders open
	_gate_open = clamp(_gate_open + delta * 0.45, 0.0, 1.0)
	if _gate_node != null:
		_gate_node.position.y = _gate_open * 4.4

# ================================================================
static func _box_mi(sz: Vector3, mat: Material) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = sz
	mi.mesh = mesh
	mi.material_override = mat
	return mi
