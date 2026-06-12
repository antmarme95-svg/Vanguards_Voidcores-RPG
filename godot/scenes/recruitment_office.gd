## recruitment_office.gd — The Recruitment Office. Port of RecruitmentOffice.js.
## One interior kit, three kingdom themes via origin.theme.propSet.
class_name RecruitmentOffice extends Node3D

const W = 12.0
const D = 10.0
const H = 4.6

# NPC presets (port of JS NPC_PRESETS)
const NPC_PRESETS = {
	"aetherborn": {
		"weight": 0.22, "height": 0.85, "arcaneMod": 0.55,
		"jaw": 0.35, "cheek": 0.75, "eyeTilt": 0.7, "eyeShape": 0.85,
		"hair": 2, "beard": 0, "hairColor": 1, "skinTone": 6,
		"warpaint": 2, "paintColor": 0,
	},
	"ironblooded": {
		"weight": 0.95, "height": 0.7, "arcaneMod": 0.25,
		"jaw": 0.9, "cheek": 0.4, "eyeTilt": 0.3, "eyeShape": 0.4,
		"hair": 1, "beard": 2, "hairColor": 2, "skinTone": 5,
		"warpaint": 5, "paintColor": 2,
	},
	"miststalker": {
		"weight": 0.35, "height": 0.6, "arcaneMod": 0.12,
		"jaw": 0.45, "cheek": 0.85, "eyeTilt": 0.9, "eyeShape": 0.7,
		"hair": 9, "beard": 0, "hairColor": 0, "skinTone": 7,
		"warpaint": 3, "paintColor": 4,
	},
}

# Gameplay data
var player_spawn: Dictionary = {}
var interactables: Array = []
var _doors_node: Node3D = null
var _doors_open: bool = false
var _desk_aabb: Dictionary = {}

# Origin dict
var _origin: Dictionary = {}

# Animation state
var _t: float = 0.0
var _spinners: Array = []
var _bobbers: Array = []
var _flicker_lights: Array = []
var _recruiter: CharacterRig = null

func _init(origin: Dictionary) -> void:
	_origin = origin

func _ready() -> void:
	var theme: Dictionary = _origin.get("theme", {})

	_build_environment(theme)
	_build_shell(theme)
	_build_doors(theme)
	_build_desk()
	_build_recruiter(theme)
	_build_fixtures(theme)
	_dress_theme(theme)
	_build_lights(theme)
	_setup_metadata(theme)

func _build_environment(theme: Dictionary) -> void:
	var we = WorldEnvironment.new()
	var env = Environment.new()
	var fog_col = Color(theme.get("fog", "#9fd0e8"))
	env.background_mode = Environment.BG_COLOR
	env.background_color = fog_col
	env.fog_enabled = true
	env.fog_light_color = fog_col
	env.fog_density = 0.02  # was 0.08 — much less interior fog so walls don't wash white
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(theme.get("ambient", "#bfe8ff"))
	env.ambient_light_energy = 0.10  # was 0.18 — reduce so floor doesn't wash white
	# ---- Glow/Bloom — enabled for the forge theme (molten channel is dramatic),
	# disabled for skyland/docks where large floating emissives create room-flooding bleed.
	var prop_set_for_glow: String = theme.get("propSet", "skyland")
	if prop_set_for_glow == "forge":
		env.glow_enabled = true
		env.glow_normalized = false
		env.glow_intensity = 0.18
		env.glow_bloom = 0.12
		env.glow_hdr_threshold = 1.5
		env.glow_hdr_luminance_cap = 3.0
		env.glow_hdr_scale = 2.0
		env.glow_strength = 0.8
		env.set_glow_level(0, 0.7)
		env.set_glow_level(1, 0.4)
		env.set_glow_level(2, 0.0)
		env.set_glow_level(3, 0.0)
		env.set_glow_level(4, 0.0)
		env.set_glow_level(5, 0.0)
		env.set_glow_level(6, 0.0)
	else:
		env.glow_enabled = false  # skyland/docks: floating emissives are too large — no bloom
	we.environment = env
	add_child(we)

func _build_shell(theme: Dictionary) -> void:
	var shell = Props.room({
		"w": W, "h": H, "d": D,
		"floor": Color(theme.get("floor", "#cfd8e6")),
		"wall": Color(theme.get("wall", "#8fa6c4")),
		"trim": Color(theme.get("trim", "#e8eef8")),
	})
	add_child(shell)

func _build_doors(theme: Dictionary) -> void:
	_doors_node = Props.sliding_doors(
		Color(theme.get("trim", "#e8eef8")),
		Color(theme.get("pipeGlow", "#46e6ff"))
	)
	_doors_node.position = Vector3(0.0, 0.0, D * 0.5)
	add_child(_doors_node)

	# Vestibule glow beyond doors
	var beyond_mat = ToonMaterials.glow_mat(Color(theme.get("sky", "#7fd4ff")), 0.8)
	var beyond = MeshInstance3D.new()
	var pm = PlaneMesh.new()
	pm.size = Vector2(4.0, 3.4)
	beyond.mesh = pm
	beyond.material_override = beyond_mat
	beyond.position = Vector3(0.0, 1.6, D * 0.5 + 3.2)
	beyond.rotation.y = PI
	beyond.rotation.x = PI * 0.5
	add_child(beyond)

func _build_desk() -> void:
	var desk = Node3D.new()
	var top_mat = ToonMaterials.toon_mat(Color("#4a3a2a"))
	var leg_mat = ToonMaterials.toon_mat(Color("#3a2d20"))

	var top = _box_mi(Vector3(2.3, 0.09, 0.95), top_mat)
	top.position.y = 0.8
	desk.add_child(top)

	for leg_pos in [Vector3(-1.05, 0.4, -0.38), Vector3(1.05, 0.4, -0.38),
					Vector3(-1.05, 0.4, 0.38),  Vector3(1.05, 0.4, 0.38)]:
		var leg = _box_mi(Vector3(0.09, 0.8, 0.09), leg_mat)
		leg.position = leg_pos
		desk.add_child(leg)

	var parchment_mat = StandardMaterial3D.new()
	parchment_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	parchment_mat.albedo_color = Color("#e8d5a8")
	var parchment = MeshInstance3D.new()
	var pm = PlaneMesh.new()
	pm.size = Vector2(0.34, 0.46)
	parchment.mesh = pm
	parchment.material_override = parchment_mat
	parchment.rotation.y = 0.2
	parchment.position = Vector3(0.2, 0.852, 0.1)
	desk.add_child(parchment)

	var inkwell = MeshInstance3D.new()
	var imesh = CylinderMesh.new()
	imesh.top_radius = 0.045
	imesh.bottom_radius = 0.055
	imesh.height = 0.09
	inkwell.mesh = imesh
	inkwell.material_override = ToonMaterials.toon_mat(Color("#1c2030"))
	inkwell.position = Vector3(-0.45, 0.89, 0.05)
	desk.add_child(inkwell)

	desk.position = Vector3(0.0, 0.0, -1.6)
	add_child(desk)

	_desk_aabb = {"min_x": -1.35, "max_x": 1.35, "min_z": -2.25, "max_z": -0.95}

func _build_recruiter(theme: Dictionary) -> void:
	var origin_id: String = _origin.get("id", "aetherborn")
	var preset = NPC_PRESETS.get(origin_id, NPC_PRESETS["aetherborn"])

	_recruiter = CharacterRig.new()
	add_child(_recruiter)
	_recruiter.position = Vector3(0.0, 0.0, -2.75)
	_recruiter.rotation.y = 0.0
	_recruiter.apply_phenotype(preset, _origin)

func _build_fixtures(theme: Dictionary) -> void:
	var pipe_glow = Color(theme.get("pipeGlow", "#46e6ff"))
	var accent = Color(theme.get("accent", "#46e6ff"))

	# Banners
	for bx in [-2.2, 2.2]:
		var b = Props.banner(theme)
		b.position = Vector3(bx, 2.9, -D * 0.5 + 0.2)
		add_child(b)

	# Aether pipes
	var pipe1 = Props.aether_pipe([
		Vector3(-W * 0.5 + 0.3, 3.9, -D * 0.5 + 0.3),
		Vector3(0.0, 4.1, -D * 0.5 + 0.3),
		Vector3(W * 0.5 - 0.3, 3.9, -D * 0.5 + 0.3),
	], pipe_glow)
	add_child(pipe1)

	var pipe2 = Props.aether_pipe([
		Vector3(W * 0.5 - 0.3, 0.4, -2.0),
		Vector3(W * 0.5 - 0.3, 2.2, 0.0),
		Vector3(W * 0.5 - 0.3, 3.8, 2.5),
	], pipe_glow)
	add_child(pipe2)

	# Crystal lamps
	for lamp_pos in [Vector3(-W * 0.5 + 0.8, 0.0, D * 0.5 - 1.2),
					 Vector3(W * 0.5 - 0.8, 0.0, D * 0.5 - 1.2)]:
		var lamp = Props.crystal_lamp(pipe_glow)
		lamp.position = lamp_pos
		add_child(lamp)

func _build_lights(theme: Dictionary) -> void:
	var pipe_glow = Color(theme.get("pipeGlow", "#46e6ff"))
	var ambient_col = Color(theme.get("ambient", "#bfe8ff"))
	var prop_set: String = theme.get("propSet", "skyland")

	# Key directional — from upper-front, modest to avoid washing out pale floors
	var key = DirectionalLight3D.new()
	key.light_color = Color("#ffffff")
	key.light_energy = 0.38
	key.rotation_degrees = Vector3(-50.0, 25.0, 0.0)
	add_child(key)

	# Bounce fill — tinted by ambient to warm/tint the scene
	var fill = DirectionalLight3D.new()
	fill.light_color = ambient_col
	fill.light_energy = 0.18
	fill.rotation_degrees = Vector3(30.0, -160.0, 0.0)
	fill.shadow_enabled = false
	add_child(fill)

	# Accent omni lights from pipe-glow colour
	var glow_a = OmniLight3D.new()
	glow_a.light_color = pipe_glow
	glow_a.light_energy = 2.0
	glow_a.omni_range = 7.0
	glow_a.position = Vector3(-3.5, 3.2, 1.5)
	add_child(glow_a)

	var glow_b = OmniLight3D.new()
	glow_b.light_color = pipe_glow
	glow_b.light_energy = 1.6
	glow_b.omni_range = 7.0
	glow_b.position = Vector3(3.5, 3.2, -2.0)
	add_child(glow_b)

	if prop_set == "forge":
		_flicker_lights = [glow_a, glow_b]

func _dress_theme(theme: Dictionary) -> void:
	var prop_set: String = theme.get("propSet", "skyland")
	var pipe_glow = Color(theme.get("pipeGlow", "#46e6ff"))
	var accent = Color(theme.get("accent", "#46e6ff"))
	var sky_col = Color(theme.get("sky", "#7fd4ff"))

	if prop_set == "skyland":
		# Floating crystals (deterministic positions)
		var positions = [
			Vector3(-4.5, 2.2, -4.0), Vector3(-2.0, 3.2, -2.5), Vector3(1.5, 2.8, -3.5),
			Vector3(3.0, 3.5, -1.0),  Vector3(-3.5, 3.0, 1.0),  Vector3(2.0, 2.5, 2.0),
		]
		var bob_seeds = [0.0, 1.1, 2.2, 3.3, 4.4, 5.5]
		for i in range(positions.size()):
			var c = Props.floating_crystal(pipe_glow, 0.1 + float(i) * 0.02)
			c.position = positions[i]
			c.set_meta("bob_seed", bob_seeds[i])
			_bobbers.append(c)
			add_child(c)

		# Book stacks
		for bdef in [[-4.6, -3.2, 0.4], [-4.2, -3.8, -0.2], [4.5, -2.5, 0.8]]:
			var books = Props.book_stack()
			books.position = Vector3(bdef[0], 0.0, bdef[1])
			books.rotation.y = bdef[2]
			add_child(books)

		# Sky window (glowing plane)
		var win_mat = ToonMaterials.glow_mat(sky_col, 1.0)
		var win = MeshInstance3D.new()
		var pm = PlaneMesh.new()
		pm.size = Vector2(2.4, 3.0)
		win.mesh = pm
		win.material_override = win_mat
		win.position = Vector3(-W * 0.5 + 0.15, 2.2, -1.0)
		win.rotation.y = PI * 0.5
		win.rotation.x = PI * 0.5
		add_child(win)

	elif prop_set == "forge":
		# Gears
		var gear1 = Props.spin_gear(0.9, Color("#5a4a3a"))
		gear1.position = Vector3(W * 0.5 - 0.45, 2.6, 1.5)
		gear1.rotation.y = PI * 0.5
		_spinners.append(gear1)
		add_child(gear1)

		var gear2 = Props.spin_gear(0.5, Color("#4a3c30"))
		gear2.position = Vector3(W * 0.5 - 0.4, 1.2, 3.2)
		gear2.rotation.y = PI * 0.5
		gear2.set_meta("spin", -0.7)
		_spinners.append(gear2)
		add_child(gear2)

		# Molten channel
		var channel_mat = ToonMaterials.glow_mat(Color("#ff5a1f"), 1.1)
		var channel = _box_mi(Vector3(0.8, 0.06, D - 1.0), channel_mat)
		channel.position = Vector3(-W * 0.5 + 0.7, 0.04, 0.0)
		add_child(channel)

		# Anvil
		var base = _box_mi(Vector3(0.5, 0.45, 0.4), ToonMaterials.toon_mat(Color("#3a3f4a")))
		base.position = Vector3(-3.6, 0.22, 1.8)
		add_child(base)
		var horn = _box_mi(Vector3(0.85, 0.18, 0.3), ToonMaterials.toon_mat(Color("#4a505c")))
		horn.position = Vector3(-3.6, 0.54, 1.8)
		add_child(horn)

	else:  # docks
		# Rib arcs
		for rz in [-2.5, 0.5, 3.5]:
			var rib = Props.rib_arc(4.4, Color("#cfc8b8"))
			rib.position = Vector3(0.0, 0.1, rz)
			rib.scale.y = 1.15
			add_child(rib)

		# Crate stacks
		var crates1 = Props.crate_stack(accent)
		crates1.position = Vector3(-4.2, 0.0, 2.6)
		add_child(crates1)

		var crates2 = Props.crate_stack(accent)
		crates2.position = Vector3(4.3, 0.0, -3.4)
		crates2.rotation.y = 1.2
		add_child(crates2)

func _setup_metadata(theme: Dictionary) -> void:
	player_spawn = {
		"position": Vector3(-1.2, 0.0, 2.6),
		"yaw": PI,
	}
	var origin_id: String = _origin.get("id", "")
	var recruiter_dict: Dictionary = _origin.get("recruiter", {})
	var recruiter_name: String = recruiter_dict.get("name", "Recruiter")
	interactables = [
		{
			"id": "recruiter",
			"label": "Talk to " + recruiter_name,
			"position": Vector3(0.0, 1.0, -1.9),
			"radius": 2.0,
			"enabled": true,
		},
		{
			"id": "exitDoors",
			"label": "Step into the Wilds",
			"position": Vector3(0.0, 1.0, D * 0.5),
			"radius": 1.6,
			"enabled": false,
		},
	]

# ================================================================
# Public API
# ================================================================
func set_doors_open(open: bool) -> void:
	_doors_open = open
	for it in interactables:
		if it["id"] == "exitDoors":
			it["enabled"] = open

func get_height(_x: float = 0.0, _z: float = 0.0) -> float:
	return 0.0

func clamp_camera(pos: Vector3) -> void:
	pos.x = clamp(pos.x, -W * 0.5 + 0.35, W * 0.5 - 0.35)
	pos.z = clamp(pos.z, -D * 0.5 + 0.35, D * 0.5 - 0.35)
	pos.y = clamp(pos.y, 0.35, H - 0.35)

func clamp_position(pos: Vector3, radius: float = 0.35) -> void:
	var in_doorway = abs(pos.x) < 1.0 and _doors_open
	pos.x = clamp(pos.x, -W * 0.5 + 0.5, W * 0.5 - 0.5)
	var max_z = D * 0.5 + 1.0 if in_doorway else D * 0.5 - 0.5
	pos.z = clamp(pos.z, -D * 0.5 + 0.5, max_z)
	# Desk block
	var a = _desk_aabb
	if pos.x > a["min_x"] - radius and pos.x < a["max_x"] + radius and \
	   pos.z > a["min_z"] - radius and pos.z < a["max_z"] + radius:
		var dx_min = abs(pos.x - (a["min_x"] - radius))
		var dx_max = abs(a["max_x"] + radius - pos.x)
		var dz_min = abs(pos.z - (a["min_z"] - radius))
		var dz_max = abs(a["max_z"] + radius - pos.z)
		var m = min(min(dx_min, dx_max), min(dz_min, dz_max))
		if m == dx_min:
			pos.x = a["min_x"] - radius
		elif m == dx_max:
			pos.x = a["max_x"] + radius
		elif m == dz_min:
			pos.z = a["min_z"] - radius
		else:
			pos.z = a["max_z"] + radius

func is_in_grass(_pos: Vector3 = Vector3.ZERO) -> bool:
	return false

func _process(delta: float) -> void:
	_t += delta

	# Doors animate
	if _doors_node != null:
		Props.tick_doors(_doors_node, delta, _doors_open)

	# Recruiter idle animation
	if _recruiter != null:
		pass  # CharacterRig has its own _process

	# Gear spin
	for s in _spinners:
		var sp: float = s.get_meta("spin") if s.has_meta("spin") else 0.4
		s.rotation.z += delta * sp

	# Crystal bob
	for b in _bobbers:
		var bs: float = b.get_meta("bob_seed") if b.has_meta("bob_seed") else 0.0
		b.position.y += sin(_t * 1.3 + bs) * 0.002
		b.rotation.y += delta * 0.6

	# Flicker lights
	for l in _flicker_lights:
		var ol = l as OmniLight3D
		ol.light_energy = 2.0 + sin(_t * 11.0 + ol.position.x) * 0.4

# ================================================================
static func _box_mi(sz: Vector3, mat: Material) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = sz
	mi.mesh = mesh
	mi.material_override = mat
	return mi
