## the_wilds.gd — The Wilds scene. Direct port of TheWilds.js.
## Deterministic PRNG, terrain math, core sites, grass MultiMesh, flora, sky dressing.
class_name TheWilds extends Node3D

# ---- constants (must match JS exactly) ----
const SIZE = 220.0
const CORE_POS = Vector2(8.0, -42.0)    # x, z
const CORE_POS_B = Vector2(-46.0, 18.0) # x, z
const SPAWN = Vector2(0.0, 88.0)        # x, z

const GRASS_PATCHES = [
	{"x": 0.0,   "z": 64.0,  "r": 22.0},
	{"x": -15.0, "z": 36.0,  "r": 24.0},
	{"x": 12.0,  "z": 12.0,  "r": 26.0},
	{"x": -8.0,  "z": -14.0, "r": 22.0},
	{"x": 24.0,  "z": -32.0, "r": 20.0},
	{"x": -18.0, "z": -50.0, "r": 21.0},
	{"x": 30.0,  "z": 55.0,  "r": 18.0},
	{"x": -35.0, "z": 25.0,  "r": 19.0},
	{"x": 5.0,   "z": -55.0, "r": 17.0},
	{"x": 45.0,  "z": -10.0, "r": 16.0},
	{"x": -20.0, "z": 70.0,  "r": 18.0},
	{"x": 20.0,  "z": 80.0,  "r": 15.0},
]

# ---- gameplay data ----
var player_spawn: Dictionary = {}    # {position: Vector3, yaw: float}
var core_positions: Array = []       # Array[Vector3]
var core_position: Vector3 = Vector3.ZERO
var enemy_spawns: Array = []         # Array[Vector3]
var enemy_spawns_b: Array = []       # Array[Vector3]
var triggers: Array = []             # Array[Dictionary]
var interactables: Array = []        # Array[Dictionary]
var sites: Array = []                # Array[Dictionary] per site
var obstacles: Array = []            # Array[Dictionary] {x,z,r}
var ruins_zones: Array = []          # Array[Dictionary] {center: Vector3, radius: float}

# ---- runtime ----
var _t: float = 0.0
var _wind_time_param: StringName = &"wind_time"
var _wind_mat: ShaderMaterial = null
var _clouds: Node3D = null

# ---- origin passed into _init ----
var _origin: Dictionary = {}

# ================================================================
func _init(origin: Dictionary) -> void:
	_origin = origin

func _ready() -> void:
	_build_environment()
	_build_terrain()
	_build_grass()
	_build_flora()
	sites = [
		_build_core_site(CORE_POS.x, CORE_POS.y, "core"),
		_build_core_site(CORE_POS_B.x, CORE_POS_B.y, "core2"),
	]
	_build_sky_dressing()
	_build_ruins_zones()
	_build_lights()
	_setup_metadata()

# ================================================================
# PRNG — mulberry32 port, returns a callable incrementing a ref-counted state.
# We use a simple Array[int] as a mutable holder.
# ================================================================
static func _mulberry32_next(state: Array) -> float:
	var s: int = state[0]
	s = (s + 0x6d2b79f5) & 0xFFFFFFFF
	state[0] = s
	var t: int = (s ^ (s >> 15)) & 0xFFFFFFFF
	t = (t * (1 | s)) & 0xFFFFFFFF
	t = (t + ((t ^ (t >> 7)) * (61 | t))) & 0xFFFFFFFF
	t = (t ^ (t >> 14)) & 0xFFFFFFFF
	return float(t) / 4294967296.0

# ================================================================
# Terrain math — static so autotest can call directly
# ================================================================
static func _smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)

static func raw_height(x: float, z: float) -> float:
	return (
		2.4 * sin(x * 0.042 + 0.7) * cos(z * 0.036) +
		1.2 * sin(x * 0.09 + 2.1) * sin(z * 0.075 + 1.2) +
		0.45 * sin(x * 0.21) * cos(z * 0.19 + 0.5)
	)

static func _flatten(h: float, x: float, z: float, cx: float, cz: float, r: float, hc: float) -> float:
	var d = sqrt((x - cx) * (x - cx) + (z - cz) * (z - cz))
	if d >= r:
		return h
	var t = _smooth(d / r)
	return lerp(hc, h, t)

static func terrain_height(x: float, z: float) -> float:
	var h = raw_height(x, z)
	h = _flatten(h, x, z, SPAWN.x, SPAWN.y, 16.0, 0.4)
	h = _flatten(h, x, z, CORE_POS.x, CORE_POS.y, 20.0, 0.7)
	h = _flatten(h, x, z, CORE_POS_B.x, CORE_POS_B.y, 18.0, 0.6)
	return h

# ================================================================
func _build_environment() -> void:
	var we = WorldEnvironment.new()
	var env = Environment.new()
	# Sky background color matching fog
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#bfe3d4")
	# Depth fog — begins at 55m, blue-green horizon tint for aerial perspective
	env.fog_enabled = true
	env.fog_light_color = Color("#bfe3d4")
	env.fog_density = 0.0015  # tuned so full at ~230
	env.fog_aerial_perspective = 0.45
	env.fog_sky_affect = 0.4
	# Tonemap — exposure 1.0 avoids ACES boost blowing out pastels
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	# Ambient — warm sky blue, moderate energy (drives ambient_lift in shader)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#a8d8c0")
	env.ambient_light_energy = 0.30
	# ---- Glow/Bloom — halos only on emissive aether tech, not white walls ----
	env.glow_enabled = true
	env.glow_normalized = false
	env.glow_intensity = 0.22
	env.glow_bloom = 0.18
	env.glow_hdr_threshold = 1.1   # only emissives (>1.0 effective) trigger bloom
	env.glow_hdr_luminance_cap = 2.5
	env.glow_hdr_scale = 2.0
	env.glow_strength = 1.0
	# Enable levels 1-3 (tight halo), disable 4-7 (wide bleed)
	env.set_glow_level(0, 0.6)
	env.set_glow_level(1, 0.5)
	env.set_glow_level(2, 0.3)
	env.set_glow_level(3, 0.0)
	env.set_glow_level(4, 0.0)
	env.set_glow_level(5, 0.0)
	env.set_glow_level(6, 0.0)
	we.environment = env
	add_child(we)

func _build_lights() -> void:
	# Sky fill — subtle cool blue from above (replaces hemisphere sky channel)
	var hemi_fill = DirectionalLight3D.new()
	hemi_fill.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	hemi_fill.light_color = Color("#bfe8ff")
	hemi_fill.light_energy = 0.18
	hemi_fill.shadow_enabled = false
	add_child(hemi_fill)

	# Sun — warm, PCF soft shadows to ground characters and trees
	var sun = DirectionalLight3D.new()
	sun.light_color = Color("#fff2d8")
	sun.light_energy = 1.1
	sun.rotation_degrees = Vector3(-66.0, -53.0, 0.0)
	sun.shadow_enabled = true
	# PCF soft shadows
	sun.shadow_blur = 1.8
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 120.0
	sun.directional_shadow_split_1 = 0.25
	# Tune bias to avoid acne and peter-panning
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 1.5
	add_child(sun)

# ================================================================
func _build_terrain() -> void:
	var seg = 110
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Richer, more saturated greens — deeper BotW meadow palette
	var c_grass = Color("#3aaa30")
	var c_lush = Color("#267a38")
	var c_dry = Color("#7aa83a")
	var c_scorch = Color("#4a3434")

	# Build vertex grid (SIZE x SIZE, seg x seg segments)
	# Vertices: (seg+1) x (seg+1)
	var verts = PackedVector3Array()
	var colors = PackedColorArray()
	var uvs = PackedVector2Array()

	var half = SIZE * 0.5
	var step = SIZE / float(seg)

	for iz in range(seg + 1):
		for ix in range(seg + 1):
			var x = -half + float(ix) * step
			var z_val = -half + float(iz) * step
			var h = terrain_height(x, z_val)
			verts.append(Vector3(x, h, z_val))
			uvs.append(Vector2(float(ix) / float(seg), float(iz) / float(seg)))

			# Vertex color
			var n = (sin(x * 0.5) * cos(z_val * 0.45) + 1.0) * 0.5
			var col: Color
			if n > 0.6:
				col = c_lush.lerp(c_dry, abs(n - 0.5) * 1.6)
			else:
				col = c_lush.lerp(c_grass, abs(n - 0.5) * 1.6)
			# Corruption stains around both cores
			for cp_x in [CORE_POS.x, CORE_POS_B.x]:
				var cp_z: float
				if cp_x == CORE_POS.x:
					cp_z = CORE_POS.y
				else:
					cp_z = CORE_POS_B.y
				var d_core = sqrt((x - cp_x) * (x - cp_x) + (z_val - cp_z) * (z_val - cp_z))
				if d_core < 13.0:
					col = col.lerp(c_scorch, 1.0 - _smooth(d_core / 13.0))
			colors.append(col)

	# Build indices
	for iz in range(seg):
		for ix in range(seg):
			var i00 = iz * (seg + 1) + ix
			var i10 = i00 + 1
			var i01 = i00 + (seg + 1)
			var i11 = i01 + 1
			st.set_color(colors[i00])
			st.set_uv(uvs[i00])
			st.set_normal(Vector3.UP)
			st.add_vertex(verts[i00])

			st.set_color(colors[i10])
			st.set_uv(uvs[i10])
			st.set_normal(Vector3.UP)
			st.add_vertex(verts[i10])

			st.set_color(colors[i11])
			st.set_uv(uvs[i11])
			st.set_normal(Vector3.UP)
			st.add_vertex(verts[i11])

			st.set_color(colors[i00])
			st.set_uv(uvs[i00])
			st.set_normal(Vector3.UP)
			st.add_vertex(verts[i00])

			st.set_color(colors[i11])
			st.set_uv(uvs[i11])
			st.set_normal(Vector3.UP)
			st.add_vertex(verts[i11])

			st.set_color(colors[i01])
			st.set_uv(uvs[i01])
			st.set_normal(Vector3.UP)
			st.add_vertex(verts[i01])

	st.generate_normals()
	var mesh = st.commit()

	# Toon material with vertex-color support enabled.
	# albedo_color WHITE so vertex colors show through unchanged;
	# use_vertex_color tells the shader to multiply by COLOR attribute.
	var mat = ToonMaterials.toon_mat(Color(1.0, 1.0, 1.0, 1.0))
	mat.set_shader_parameter("use_vertex_color", true)
	mat.set_shader_parameter("ambient_lift", 0.06)  # reduced so saturated greens read through

	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)

# ================================================================
func _build_grass() -> void:
	var state = [1337]  # seed 1337 — mulberry32 determinism preserved
	# ~20000 blades: 14000 in dense patches + 6000 background scatter
	var COUNT = 20000

	# Build a simple quad blade mesh (double-sided)
	# Short wide blades = soft carpet from above, less spiky at eye level
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw = 0.07
	var h = 0.28
	# Front face
	st.set_uv(Vector2(0, 1)); st.set_normal(Vector3.BACK); st.add_vertex(Vector3(-hw, 0, 0))
	st.set_uv(Vector2(1, 1)); st.set_normal(Vector3.BACK); st.add_vertex(Vector3( hw, 0, 0))
	st.set_uv(Vector2(1, 0)); st.set_normal(Vector3.BACK); st.add_vertex(Vector3( hw, h, 0))
	st.set_uv(Vector2(0, 1)); st.set_normal(Vector3.BACK); st.add_vertex(Vector3(-hw, 0, 0))
	st.set_uv(Vector2(1, 0)); st.set_normal(Vector3.BACK); st.add_vertex(Vector3( hw, h, 0))
	st.set_uv(Vector2(0, 0)); st.set_normal(Vector3.BACK); st.add_vertex(Vector3(-hw, h, 0))
	# Back face
	st.set_uv(Vector2(0, 1)); st.set_normal(Vector3.FORWARD); st.add_vertex(Vector3( hw, 0, 0))
	st.set_uv(Vector2(1, 1)); st.set_normal(Vector3.FORWARD); st.add_vertex(Vector3(-hw, 0, 0))
	st.set_uv(Vector2(1, 0)); st.set_normal(Vector3.FORWARD); st.add_vertex(Vector3(-hw, h, 0))
	st.set_uv(Vector2(0, 1)); st.set_normal(Vector3.FORWARD); st.add_vertex(Vector3( hw, 0, 0))
	st.set_uv(Vector2(1, 0)); st.set_normal(Vector3.FORWARD); st.add_vertex(Vector3(-hw, h, 0))
	st.set_uv(Vector2(0, 0)); st.set_normal(Vector3.FORWARD); st.add_vertex(Vector3( hw, h, 0))
	var blade_mesh = st.commit()

	# Wind-sway shader — COLOR.rgb = per-instance base tint (terrain-matched)
	# High ambient_lift so blades read bright green even in shadow ramp=0 band.
	# tip_brighten warms the blade tips (BotW style lighter/yellower tips).
	# unshaded_floor keeps minimum brightness so blades never go black.
	var grass_shader_code = """
shader_type spatial;
render_mode cull_disabled, ambient_light_disabled;

uniform vec4 albedo_color : source_color = vec4(0.33, 0.78, 0.26, 1.0);
uniform float wind_time : hint_range(0.0, 1000.0) = 0.0;
uniform float ambient_lift : hint_range(0.0, 1.0) = 0.55;
uniform float tip_brighten : hint_range(0.0, 1.0) = 0.28;

void vertex() {
	float wave = sin(wind_time * 2.4 + VERTEX.x * 0.7 + VERTEX.z * 0.5) * 0.12 * VERTEX.y;
	VERTEX.x += wave;
}

void fragment() {
	// UV.y = 1 at base, 0 at tip (standard Godot quad UVs)
	float tip_t = 1.0 - UV.y;
	vec3 base_tint = albedo_color.rgb * COLOR.rgb;
	// Tip: slightly brighter + warmer (adds yellow-green)
	vec3 tip_color = base_tint * (1.0 + tip_brighten) + vec3(tip_brighten * 0.08, tip_brighten * 0.04, -tip_brighten * 0.02);
	vec3 tinted = mix(base_tint, tip_color, tip_t * tip_t);
	ALBEDO = tinted;
	// High emission floor = blades never go fully dark regardless of shadow ramp
	EMISSION = tinted * ambient_lift;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}

void light() {
	float NdotL = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	float ramp;
	if (NdotL < 0.20) { ramp = 0.0; }
	else if (NdotL < 0.50) { ramp = 0.25; }
	else if (NdotL < 0.78) { ramp = 0.50; }
	else { ramp = 0.75; }
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ramp;
}
"""
	var grass_shader = Shader.new()
	grass_shader.code = grass_shader_code
	_wind_mat = ShaderMaterial.new()
	_wind_mat.shader = grass_shader
	_wind_mat.set_shader_parameter("albedo_color", Color("#4ec844"))
	_wind_mat.set_shader_parameter("wind_time", 0.0)
	_wind_mat.set_shader_parameter("tip_brighten", 0.28)

	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	# use_colors MUST be set before instance_count (Godot requirement)
	mm.use_colors = true
	mm.instance_count = COUNT
	mm.mesh = blade_mesh

	# Bright meadow greens — need to be light enough that base_tint*COLOR stays visible
	# (the shader multiplies albedo_color * COLOR; both must be bright enough)
	var greens = [
		Color("#5ec84e"),  # bright grass
		Color("#42b048"),  # mid lush
		Color("#6cd458"),  # lighter meadow
		Color("#4ac050"),  # balanced lush
		Color("#72de60"),  # very bright tip match
		Color("#38a040"),  # deeper lush
	]
	var patches_count = GRASS_PATCHES.size()
	# Split: first 14000 blades go in dense patches; last 6000 scatter across the roam ring
	var PATCH_COUNT = 14000
	var SCATTER_COUNT = COUNT - PATCH_COUNT
	var ROAM_R = 95.0  # slightly inside the 102m hard boundary

	for i in range(COUNT):
		var gx: float
		var gz: float
		var s: float
		var ry: float
		var col_idx: int

		if i < PATCH_COUNT:
			# Dense patch placement
			var patch_idx = int(_mulberry32_next(state) * float(patches_count)) % patches_count
			var patch: Dictionary = GRASS_PATCHES[patch_idx]
			var a = _mulberry32_next(state) * TAU
			# sqrt gives uniform-disk distribution; density falls off with distance from center
			var d = sqrt(_mulberry32_next(state)) * patch["r"]
			gx = patch["x"] + cos(a) * d
			gz = patch["z"] + sin(a) * d
			s = 0.75 + _mulberry32_next(state) * 0.6
			ry = _mulberry32_next(state) * TAU
			col_idx = int(_mulberry32_next(state) * float(greens.size())) % greens.size()
		else:
			# Background scatter — uniform across the full roam ring
			# Reject-sample: only keep if outside scorch rings (cores clear)
			var a = _mulberry32_next(state) * TAU
			var d = _mulberry32_next(state) * ROAM_R
			gx = cos(a) * d
			gz = sin(a) * d
			# Skip near core sites (scorch radius ~13m)
			var dc_a = sqrt((gx - CORE_POS.x) * (gx - CORE_POS.x) + (gz - CORE_POS.y) * (gz - CORE_POS.y))
			var dc_b = sqrt((gx - CORE_POS_B.x) * (gx - CORE_POS_B.x) + (gz - CORE_POS_B.y) * (gz - CORE_POS_B.y))
			if dc_a < 14.0 or dc_b < 14.0:
				# Advance state but skip (place blade at a safe fallback position)
				gx = _mulberry32_next(state) * 6.0
				gz = _mulberry32_next(state) * 6.0 + 80.0
			else:
				_mulberry32_next(state)  # consume the same number of state steps
				_mulberry32_next(state)
			s = 0.55 + _mulberry32_next(state) * 0.5  # slightly smaller for background
			ry = _mulberry32_next(state) * TAU
			col_idx = int(_mulberry32_next(state) * float(greens.size())) % greens.size()

		var gy = terrain_height(gx, gz)
		var xf = Transform3D()
		xf = xf.scaled(Vector3(s, s, s))
		xf = xf.rotated(Vector3.UP, ry)
		xf.origin = Vector3(gx, gy, gz)
		mm.set_instance_transform(i, xf)

		# Terrain-tinted color: sample the same noise used for vertex colors
		var n_sample = (sin(gx * 0.5) * cos(gz * 0.45) + 1.0) * 0.5
		var terrain_col: Color
		if n_sample > 0.6:
			terrain_col = greens[1].lerp(greens[2], abs(n_sample - 0.5) * 1.6)
		else:
			terrain_col = greens[1].lerp(greens[0], abs(n_sample - 0.5) * 1.6)
		var base_green: Color = greens[col_idx]
		var final_col = base_green.lerp(terrain_col, 0.40)
		# Background scatter blades are slightly lighter to avoid dark blotches at low density
		if i >= PATCH_COUNT:
			final_col = final_col.lightened(0.12)
		mm.set_instance_color(i, final_col)

	var mmi = MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _wind_mat
	add_child(mmi)

# ================================================================
func _build_flora() -> void:
	var state = [777]  # seed 777
	obstacles = []

	for i in range(38):
		var a = _mulberry32_next(state) * TAU
		var d = 24.0 + _mulberry32_next(state) * 78.0
		var x = cos(a) * d
		var z = sin(a) * d * 0.95 + 10.0
		# Keep core route clear
		if sqrt((x - CORE_POS.x) * (x - CORE_POS.x) + (z - CORE_POS.y) * (z - CORE_POS.y)) < 16.0:
			continue
		if sqrt((x - CORE_POS_B.x) * (x - CORE_POS_B.x) + (z - CORE_POS_B.y) * (z - CORE_POS_B.y)) < 16.0:
			continue
		if abs(x) < 7.0 and z > -30.0 and z < 95.0:
			continue
		var s = 0.8 + _mulberry32_next(state) * 0.9
		var t = Props.tree(s)
		t.position = Vector3(x, terrain_height(x, z) - 0.1, z)
		add_child(t)
		obstacles.append({"x": x, "z": z, "r": 0.45 * s})

	for i in range(22):
		var a = _mulberry32_next(state) * TAU
		var d = 14.0 + _mulberry32_next(state) * 88.0
		var x = cos(a) * d
		var z = sin(a) * d
		var s = 0.7 + _mulberry32_next(state) * 1.8
		var r = Props.rock(s)
		r.position = Vector3(x, terrain_height(x, z) + 0.1, z)
		add_child(r)
		if s > 1.2:
			obstacles.append({"x": x, "z": z, "r": 0.5 * s})

# ================================================================
func _build_core_site(cx: float, cz: float, interactable_id: String) -> Dictionary:
	var cy = terrain_height(cx, cz)
	var group = Node3D.new()
	group.position = Vector3(cx, cy, cz)

	var glow_col = Color("#ff2336")
	var glow_mat = ToonMaterials.glow_mat(glow_col, 1.0)
	var shard_mat = ToonMaterials.glow_mat(Color("#a8141f"), 0.9)

	var crystals: Array = []
	# [cx, cz, _, s, rx, rz]
	var defs = [
		[0.0, 0.0, 0.0, 1.9, 0.0, 0.0],
		[1.4, 0.2, 0.0, 1.2, 0.5, 0.3],
		[-1.2, 0.1, 0.0, 1.35, -0.45, -0.2],
		[0.6, 0.15, 0.0, 0.95, 0.3, -0.5],
		[-0.7, 0.1, 0.0, 1.1, -0.25, 0.45],
	]
	# Note: JS defs are [cx, cz, _, s, rx, rz] where index 0=cx,1=cz,2=unused,3=s,4=rx,5=rz
	# Actually from JS: const defs = [ [0,0,0,1.9,0,0], [1.4,-0.6,0.2,1.2,0.5,0.3], ... ]
	# Index: 0=local_x, 1=local_z, 2=unused_float, 3=scale, 4=rx, 5=rz
	var defs_correct = [
		[0.0,  0.0,  0.0, 1.9,  0.0,   0.0],
		[1.4, -0.6,  0.2, 1.2,  0.5,   0.3],
		[-1.2, 0.8,  0.1, 1.35, -0.45, -0.2],
		[0.6,  1.3,  0.15, 0.95, 0.3,  -0.5],
		[-0.7, -1.2, 0.1, 1.1,  -0.25,  0.45],
	]
	for def in defs_correct:
		var mi = MeshInstance3D.new()
		var mesh = BoxMesh.new()
		mesh.size = Vector3(0.7, 0.7, 0.7)
		mi.mesh = mesh
		mi.material_override = glow_mat
		var s = def[3]
		mi.scale = Vector3(s * 0.55, s * 1.9, s * 0.55)
		# def[0]=local_x in JS (XZ plane), def[1]=local_z in JS
		mi.position = Vector3(def[0], s * 1.1, def[1])
		mi.rotation = Vector3(def[4], 0.0, def[5])
		group.add_child(mi)
		crystals.append(mi)

	# Shard ring (9 shards)
	for i in range(9):
		var ang = float(i) / 9.0 * TAU
		var sh = MeshInstance3D.new()
		var smesh = BoxMesh.new()
		smesh.size = Vector3(0.16, 0.16, 0.16)
		sh.mesh = smesh
		sh.material_override = shard_mat
		sh.scale.y = 2.2
		sh.position = Vector3(cos(ang) * 3.6, 0.3, sin(ang) * 3.6)
		sh.rotation.z = cos(ang) * 0.5
		group.add_child(sh)
		crystals.append(sh)

	# Point light
	var light = OmniLight3D.new()
	light.light_color = Color("#ff2336")
	light.light_energy = 4.0
	light.omni_range = 18.0
	light.position.y = 2.5
	group.add_child(light)

	# Motes
	var motes_node = Props.motes(90, Color("#ff3344"), 22.0, 0.09, 7.0)
	group.add_child(motes_node)

	add_child(group)

	return {
		"group": group,
		"glow_mat": glow_mat,
		"crystals": crystals,
		"light": light,
		"motes": motes_node,
		"alive": true,
		"dying": false,
		"interactable_id": interactable_id,
	}

# ================================================================
# NEW: Reclaimed ruins zones — 3 clusters of aetherpunk ruins overgrown by nature.
# Zones: approx (40,40), (-55,-35), (25,-75).
# Each: 2-3 broken aether_pipe segments tilted/half-buried, a collapsed rib_arc,
# a spin_gear lying flat + crate debris, extra grass, 1-2 trees.
# All pieces ≥18 m from both cores and spawn corridor.
# Exposes ruins_zones Array[Dictionary] for future puzzle placement.
# ================================================================
func _build_ruins_zones() -> void:
	ruins_zones = []

	# Zone definitions: [cx, cz, radius, seed_offset]
	# Verified distances: zone0(40,40) vs CoreA(8,-42)=82m, CoreB(-46,18)=88m  OK
	# zone1(-55,-35) vs CoreA=59m, CoreB=54m  OK
	# zone2(25,-75) vs CoreA=34m, CoreB=96m  OK (CoreA clear >18)
	var zone_defs = [
		[40.0,  40.0,  12.0],
		[-55.0, -35.0, 11.0],
		[25.0,  -75.0, 10.0],
	]

	# Rusted metal material (desaturated, aged)
	var rust_mat = ToonMaterials.toon_mat(Color("#6b5040"))
	var old_metal_mat = ToonMaterials.toon_mat(Color("#4a4a4a"))
	var moss_mat = ToonMaterials.toon_mat(Color("#3d6b3a"))

	for zi in range(zone_defs.size()):
		var zd = zone_defs[zi]
		var cx: float = zd[0]
		var cz: float = zd[1]
		var zr: float = zd[2]
		var cy = terrain_height(cx, cz)

		var zone_root = Node3D.new()
		zone_root.position = Vector3(cx, cy, cz)
		zone_root.name = "ruins_zone_" + str(zi)

		# ---- 2-3 broken aether_pipe segments, tilted/half-buried ----
		# Use short 2-point pipe segments in rusted glow colour
		var rusted_glow = Color("#7a3a1a")
		# Segment 1 — tilted 40°, half-buried
		var pipe1 = Props.aether_pipe([
			Vector3(-3.0, -0.3, 1.0),
			Vector3(-1.0, 0.8, -0.5),
		], rusted_glow, 0.07)
		pipe1.rotation.z = 0.7
		zone_root.add_child(pipe1)

		# Segment 2 — lying near-flat
		var pipe2 = Props.aether_pipe([
			Vector3(1.5, 0.05, -2.0),
			Vector3(3.5, 0.15, -0.5),
		], rusted_glow, 0.07)
		pipe2.rotation.x = 0.15
		zone_root.add_child(pipe2)

		# Third pipe for zones 0 and 2 (more debris variety)
		if zi != 1:
			var pipe3 = Props.aether_pipe([
				Vector3(0.5, -0.2, 2.5),
				Vector3(-1.5, 0.4, 1.0),
			], rusted_glow, 0.06)
			pipe3.rotation.z = -0.5
			zone_root.add_child(pipe3)

		# ---- Collapsed rib_arc / broken arch ----
		# A rib_arc tilted on its side, partially buried
		var rib = Props.rib_arc(2.8, Color("#8a7a60"))
		rib.rotation.z = 1.1   # tilted ~60° from vertical = collapsed
		rib.rotation.y = float(zi) * 0.8
		rib.position = Vector3(0.5, 0.2, 0.0)
		zone_root.add_child(rib)

		# ---- Spin gear lying flat (on X axis = horizontal) ----
		var gear = Props.spin_gear(0.75, Color("#5a4a3a"))
		gear.position = Vector3(-1.5, 0.05, -1.0)
		gear.rotation.x = PI * 0.5   # flat on ground
		gear.rotation.y = float(zi) * 1.2
		zone_root.add_child(gear)

		# ---- Crate debris ----
		var crates = Props.crate_stack(Color("#6b5040"))
		crates.position = Vector3(2.0, 0.0, 1.5)
		crates.rotation.y = float(zi) * 0.9 + 0.3
		zone_root.add_child(crates)

		# Second crate, knocked over
		var crate2_mi = MeshInstance3D.new()
		var cmesh = BoxMesh.new()
		cmesh.size = Vector3(0.62, 0.62, 0.62)
		crate2_mi.mesh = cmesh
		crate2_mi.material_override = ToonMaterials.toon_mat(Color("#6e5a40"))
		crate2_mi.position = Vector3(2.8, 0.0, -0.8)
		crate2_mi.rotation = Vector3(0.4, 0.9, 0.3)
		zone_root.add_child(crate2_mi)

		# ---- 1-2 trees threaded through ruins ----
		var tree1 = Props.tree(0.85)
		tree1.position = Vector3(-2.5, terrain_height(cx - 2.5, cz + 1.5) - cy, 1.5)
		zone_root.add_child(tree1)
		obstacles.append({"x": cx - 2.5, "z": cz + 1.5, "r": 0.38})

		if zi % 2 == 0:
			var tree2 = Props.tree(0.7)
			tree2.position = Vector3(3.0, terrain_height(cx + 3.0, cz - 2.0) - cy, -2.0)
			zone_root.add_child(tree2)
			obstacles.append({"x": cx + 3.0, "z": cz - 2.0, "r": 0.32})

		# ---- Extra grass tufts (a few motes of green near ground) ----
		var grass_motes = Props.motes(12, Color("#4fae47"), zr * 0.6, 0.04, 0.3)
		zone_root.add_child(grass_motes)

		# Big piece obstacles (pipe cluster + gear)
		obstacles.append({"x": cx - 2.0, "z": cz + 0.5, "r": 1.2})
		obstacles.append({"x": cx + 0.5, "z": cz - 1.0, "r": 0.9})

		add_child(zone_root)

		ruins_zones.append({
			"center": Vector3(cx, cy, cz),
			"radius": zr,
		})


# ================================================================
# ================================================================
# Distant silhouette ridge ring — big low-poly hill mesh, flat-shaded.
# Spawns as a ring of triangular hill shapes at the given distance.
# No outlines; color = desaturated blue-green per layer.
# ================================================================
func _build_ridge_ring(dist: float, hill_h: float, segments: int, col: Color) -> Node3D:
	var g = Node3D.new()
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	# fog_enabled not available on StandardMaterial3D in Godot 4 — ridges affected by fog naturally

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Each segment is a triangle: two base points on the ring + apex above
	var seg_angle = TAU / float(segments)
	var seed_r = [42]  # deterministic height variation

	for i in range(segments):
		var a0 = float(i) * seg_angle
		var a1 = float(i + 1) * seg_angle
		var mid_a = (a0 + a1) * 0.5

		# Vary hill height slightly per segment (mulberry32)
		var h_var = 0.7 + _mulberry32_next(seed_r) * 0.65
		var local_h = hill_h * h_var

		# Width variation: slightly overlap segments for no gaps
		var w_inner = dist * 0.95
		var w_outer = dist * 1.18

		var p0 = Vector3(cos(a0) * w_inner, 0.0, sin(a0) * w_inner)
		var p1 = Vector3(cos(a1) * w_inner, 0.0, sin(a1) * w_inner)
		var apex = Vector3(cos(mid_a) * w_outer, local_h, sin(mid_a) * w_outer)
		# Also base corners slightly out for a wider hill base
		var pb0 = Vector3(cos(a0) * dist, 0.0, sin(a0) * dist)
		var pb1 = Vector3(cos(a1) * dist, 0.0, sin(a1) * dist)

		# Front-face normal (flat-shaded appearance — no st.generate_normals needed)
		var n = (p1 - p0).cross(apex - p0).normalized()
		st.set_normal(n); st.set_uv(Vector2(0, 1)); st.add_vertex(p0)
		st.set_normal(n); st.set_uv(Vector2(1, 1)); st.add_vertex(p1)
		st.set_normal(n); st.set_uv(Vector2(0.5, 0)); st.add_vertex(apex)
		# Base quad (ground-level fill so no gaps at bottom)
		var n2 = Vector3.UP
		st.set_normal(n2); st.set_uv(Vector2(0, 0)); st.add_vertex(p0)
		st.set_normal(n2); st.set_uv(Vector2(1, 0)); st.add_vertex(pb0)
		st.set_normal(n2); st.set_uv(Vector2(1, 1)); st.add_vertex(pb1)
		st.set_normal(n2); st.set_uv(Vector2(0, 0)); st.add_vertex(p0)
		st.set_normal(n2); st.set_uv(Vector2(1, 1)); st.add_vertex(pb1)
		st.set_normal(n2); st.set_uv(Vector2(0, 1)); st.add_vertex(p1)

	var mesh = st.commit()
	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	g.add_child(mi)
	return g

# ================================================================
func _build_sky_dressing() -> void:
	# Sky dome
	var dome = Props.sky_dome(Color("#3f9fe8"), Color("#bfe3d4"))
	add_child(dome)

	# ---- Distant silhouette ridges — layered aerial perspective (BotW horizon) ----
	# 3 rings of low-poly hills beyond the 102m roam boundary.
	# Flat-shaded, progressively lighter/more desaturated blue-greens. No outlines.
	# Ridge colors from near to far: rich blue-green → muted haze
	var ridge_layers = [
		{"dist": 140.0, "h": 22.0, "segments": 14, "col": Color("#5a9e7a")},  # near ridge: rich
		{"dist": 180.0, "h": 30.0, "segments": 12, "col": Color("#7ab8a8")},  # mid ridge
		{"dist": 230.0, "h": 38.0, "segments": 10, "col": Color("#a8cec2")},  # far haze ridge
	]
	for layer in ridge_layers:
		var ridge_node = _build_ridge_ring(
			float(layer["dist"]), float(layer["h"]),
			int(layer["segments"]), Color(layer["col"])
		)
		add_child(ridge_node)

	# Cloud clusters (9 clusters, seed 42)
	_clouds = Node3D.new()
	var state = [42]
	var cloud_mat = StandardMaterial3D.new()
	cloud_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cloud_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.92)
	cloud_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cloud_mat.fog_enabled = false

	for i in range(9):
		var cl = Node3D.new()
		for b in range(3):
			var blob = MeshInstance3D.new()
			var bmesh = SphereMesh.new()
			var br = 5.0 + _mulberry32_next(state) * 7.0
			bmesh.radius = br
			bmesh.height = br * 2.0
			blob.mesh = bmesh
			blob.material_override = cloud_mat
			blob.scale.y = 0.32
			blob.position = Vector3(
				float(b) * 7.0 - 7.0 + _mulberry32_next(state) * 4.0,
				_mulberry32_next(state) * 2.0,
				_mulberry32_next(state) * 5.0
			)
			cl.add_child(blob)
		cl.position = Vector3(
			-160.0 + _mulberry32_next(state) * 320.0,
			55.0 + _mulberry32_next(state) * 28.0,
			-160.0 + _mulberry32_next(state) * 320.0
		)
		cl.set_meta("cloud_speed", 0.5 + _mulberry32_next(state) * 0.7)
		_clouds.add_child(cl)
	add_child(_clouds)

	# Ambient motes
	var amb_motes = Props.motes(120, Color("#9fe8ff"), 160.0, 0.1, 24.0)
	add_child(amb_motes)

# ================================================================
func _setup_metadata() -> void:
	var sy = terrain_height(SPAWN.x, SPAWN.y)
	player_spawn = {
		"position": Vector3(SPAWN.x, sy, SPAWN.y),
		"yaw": PI,
	}

	core_positions = [
		Vector3(CORE_POS.x, terrain_height(CORE_POS.x, CORE_POS.y), CORE_POS.y),
		Vector3(CORE_POS_B.x, terrain_height(CORE_POS_B.x, CORE_POS_B.y), CORE_POS_B.y),
	]
	core_position = core_positions[0]

	var e_raw = [
		Vector3(2.0, 0.0, -32.0),
		Vector3(18.0, 0.0, -38.0),
		Vector3(8.0, 0.0, -52.0),
	]
	enemy_spawns = []
	for v in e_raw:
		enemy_spawns.append(Vector3(v.x, terrain_height(v.x, v.z), v.z))

	var eb_raw = [
		Vector3(-40.0, 0.0, 14.0),
		Vector3(-52.0, 0.0, 12.0),
		Vector3(-46.0, 0.0, 28.0),
	]
	enemy_spawns_b = []
	for v in eb_raw:
		enemy_spawns_b.append(Vector3(v.x, terrain_height(v.x, v.z), v.z))

	triggers = [
		{"id": "coreSight",      "position": core_position,        "radius": 42.0, "fired": false},
		{"id": "encounterStart", "position": core_position,        "radius": 26.0, "fired": false},
	]
	interactables = [
		{
			"id": "core",
			"label": "Shatter the Core",
			"position": core_positions[0] + Vector3(0.0, 1.0, 0.0),
			"radius": 3.2,
			"enabled": false,
		},
		{
			"id": "core2",
			"label": "Shatter the Core",
			"position": core_positions[1] + Vector3(0.0, 1.0, 0.0),
			"radius": 3.2,
			"enabled": false,
		},
	]

# ================================================================
# Public API
# ================================================================
func get_height(x: float, z: float) -> float:
	return terrain_height(x, z)

func clamp_position(pos: Vector3) -> void:
	var r = sqrt(pos.x * pos.x + pos.z * pos.z)
	var MAX_R = 102.0
	if r > MAX_R:
		pos.x *= MAX_R / r
		pos.z *= MAX_R / r
	for o in obstacles:
		var dx = pos.x - o["x"]
		var dz = pos.z - o["z"]
		var d = sqrt(dx * dx + dz * dz)
		var min_d = o["r"] + 0.34
		if d < min_d and d > 0.0001:
			pos.x = o["x"] + (dx / d) * min_d
			pos.z = o["z"] + (dz / d) * min_d

func is_in_grass(pos: Vector3) -> bool:
	for p in GRASS_PATCHES:
		if sqrt((pos.x - p["x"]) * (pos.x - p["x"]) + (pos.z - p["z"]) * (pos.z - p["z"])) < p["r"]:
			return true
	return false

func set_core_interactable(on: bool) -> void:
	for site in sites:
		if site["alive"] and not site["dying"]:
			var sid: String = site["interactable_id"]
			for it in interactables:
				if it["id"] == sid:
					it["enabled"] = on
			break

func destroy_core() -> void:
	for site in sites:
		if site["alive"] and not site["dying"]:
			site["dying"] = true
			var sid: String = site["interactable_id"]
			for it in interactables:
				if it["id"] == sid:
					it["enabled"] = false
			break

# ================================================================
func _process(delta: float) -> void:
	_t += delta

	# Wind uniform
	if _wind_mat != null:
		_wind_mat.set_shader_parameter(_wind_time_param, _t)

	# Clouds drift
	if _clouds != null:
		for cl in _clouds.get_children():
			cl.position.x += delta * float(cl.get_meta("cloud_speed"))
			if cl.position.x > 180.0:
				cl.position.x = -180.0

	# Core site pulse / dying
	for site in sites:
		if not site["alive"]:
			continue
		var pulse = 0.8 + sin(_t * 3.2) * 0.25 + sin(_t * 7.7) * 0.08
		var gm: StandardMaterial3D = site["glow_mat"]
		var base_col = Color("#ff2336")
		gm.emission = base_col * pulse
		gm.albedo_color = base_col * pulse

		var light: OmniLight3D = site["light"]
		light.light_energy = 3.0 + pulse * 2.0

		var group: Node3D = site["group"]
		group.rotation.y += delta * 0.05

		var motes_node: Node3D = site["motes"]
		motes_node.rotation.y -= delta * 0.1

		if site["dying"]:
			var gone = true
			var crystals: Array = site["crystals"]
			for cr in crystals:
				var cr_mi = cr as Node3D
				var shrink = max(0.0, 1.0 - delta * 2.2)
				cr_mi.scale *= shrink
				if cr_mi.scale.y > 0.04:
					gone = false
			light.light_energy *= max(0.0, 1.0 - delta * 2.0)
			if gone:
				site["alive"] = false
				group.visible = false
				light.light_energy = 0.0
