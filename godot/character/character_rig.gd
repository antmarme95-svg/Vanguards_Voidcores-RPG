## CharacterRig — parametric anime humanoid, direct port of CharacterRig.js.
## All JS numeric constants are preserved exactly (positions, scales, thresholds).
## Pivots: body > hips/spine > head > sub-meshes, arms, legs — same hierarchy.
class_name CharacterRig extends Node3D

# ---- lerp helper ----
static func _lerp(a: float, b: float, t: float) -> float:
	return a + (b - a) * t

# ---- capsule helper ----
static func _capsule_mesh(r: float, len: float, mat: Material) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var mesh = CapsuleMesh.new()
	mesh.radius = r
	mesh.height = len + r * 2.0
	mi.mesh = mesh
	mi.material_override = mat
	return mi

# ---- box helper ----
static func _box_mesh(w: float, h: float, d: float, mat: Material) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = Vector3(w, h, d)
	mi.mesh = mesh
	mi.material_override = mat
	return mi

# ---- sphere helper ----
static func _sphere_mesh(r: float, mat: Material) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var mesh = SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	mi.mesh = mesh
	mi.material_override = mat
	return mi

# ---- cylinder helper ----
static func _cylinder_mesh(top_r: float, bot_r: float, height: float, mat: Material) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var mesh = CylinderMesh.new()
	mesh.top_radius = top_r
	mesh.bottom_radius = bot_r
	mesh.height = height
	mi.mesh = mesh
	mi.material_override = mat
	return mi

# ---- disc (circle) helper (for iris/pupil — flat cylinder) ----
static func _disc_mesh(r: float, mat: Material) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var mesh = CylinderMesh.new()
	mesh.top_radius = r
	mesh.bottom_radius = r
	mesh.height = 0.002
	mi.mesh = mesh
	mi.material_override = mat
	return mi

# ----------------------------------------------------------------
# Scene nodes (mirrors JS property names where possible)
# ----------------------------------------------------------------
var body: Node3D
var hips: Node3D
var spine: Node3D
var head: Node3D
var hair_slot: Node3D
var beard_slot: Node3D
var feature_slot: Node3D
var tail_slot: Node3D

var pelvis: MeshInstance3D
var torso: MeshInstance3D
var jerkin: MeshInstance3D
var strap: MeshInstance3D
var goggles: Node3D
var skull: MeshInstance3D
var jaw_mesh: MeshInstance3D  # renamed from "jaw" to avoid shadowing Node3D.get_name
var cheeks: Array = []
var eyes: Array = []
var brows: Array = []
var legs: Array = []
var arms: Array = []
var prosthetic: Node3D
var veins: Array = []

# ---- materials (per-rig so colors are independent) ----
var skin_mat: ShaderMaterial
var head_mat: ShaderMaterial
var hair_mat: ShaderMaterial
var leather_mat: ShaderMaterial
var dark_leather_mat: ShaderMaterial
var metal_mat: ShaderMaterial
var accent_glow_mat: StandardMaterial3D
var vein_mat: StandardMaterial3D
var eye_white_mat: StandardMaterial3D
var iris_mat: StandardMaterial3D
var pupil_mat: StandardMaterial3D

var accent: Color = Color("#46e6ff")

# Per-origin visual state
var _spark_particles: GPUParticles3D = null   # ironblooded sparks node
var _fur_slot: Node3D = null                  # miststalker fake-fur node
var _iron_armor: Array = []                   # ironblooded armor pieces: [{node, base}]

# Motion / animation state
var _t: float = 0.0
var _phase: float = 0.0
var _motion_speed: float = 0.0
var _motion_crouch: bool = false
var _attack_timer: float = 0.0
var _attack_style: String = "melee"

# Cache keys to avoid redundant texture/hair rebuilds
var _head_tex_key: String = ""
var _hair_key: String = ""
var _beard_key: String = ""
var _origin_id: String = ""

# ---- archetype silhouette state ----
var _archetype_class: String = ""        # "warrior" / "mage" / "thief" / ""
var _last_p: Dictionary = {}             # last phenotype applied
var _last_origin: Dictionary = {}        # last origin applied
var _focus_orb: MeshInstance3D = null    # Strategist-only floating orb

# ---- Vanguard VFX nodes (warrior only, per-origin) ----
var _aegis_shield: MeshInstance3D = null    # aetherborn warrior: teal emissive shield
var _thruster_l: GPUParticles3D = null      # ironblooded warrior: left steam jet
var _thruster_r: GPUParticles3D = null      # ironblooded warrior: right steam jet
var _pack_wisp: MeshInstance3D = null       # miststalker warrior: spectral wisp orb
var _stealth_decal: MeshInstance3D = null   # miststalker warrior: stealth zone ring
var _wisp_angle: float = 0.0               # orbit angle for wisp

# ---- Strategist VFX nodes (mage only, per-origin) ----
const _CHRONO_SHADER = preload("res://rendering/chrono_field.gdshader")
var _chrono_field: MeshInstance3D = null    # aetherborn mage: temporal refraction dome
var _chrono_decal: MeshInstance3D = null    # aetherborn mage: teal ground AoE ring
var _thermite_embers: GPUParticles3D = null # ironblooded mage: orange ember particles
var _thermite_decal: MeshInstance3D = null  # ironblooded mage: orange ground ring decal
var _shaman_decal: MeshInstance3D = null    # miststalker mage: green-red siphon ring
var _shaman_aura: GPUParticles3D = null     # miststalker mage: green heal particles

# ----------------------------------------------------------------
func _ready() -> void:
	_init_materials()
	_build()
	# Apply default outline to body group (thickness 0.06, matches JS addOutline)
	_apply_outline_to_children(self, Color("#1c1d24"), 0.02)

func _init_materials() -> void:
	skin_mat = ToonMaterials.toon_mat(Color("#f2b186"))
	head_mat = ToonMaterials.toon_mat(Color("#ffffff"))
	hair_mat = ToonMaterials.toon_mat(Color("#b8451f"))
	leather_mat = ToonMaterials.toon_mat(Color("#5b4632"))
	dark_leather_mat = ToonMaterials.toon_mat(Color("#3a2d22"))
	metal_mat = ToonMaterials.toon_mat(Color("#6f7a88"))
	accent_glow_mat = ToonMaterials.glow_mat(accent, 1.2)
	vein_mat = ToonMaterials.glow_mat(accent, 0.8)

	eye_white_mat = StandardMaterial3D.new()
	eye_white_mat.albedo_color = Color("#f8f6f2")
	eye_white_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	iris_mat = StandardMaterial3D.new()
	iris_mat.albedo_color = accent
	iris_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	pupil_mat = StandardMaterial3D.new()
	pupil_mat.albedo_color = Color("#10131a")
	pupil_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

# ----------------------------------------------------------------
func _build() -> void:
	body = Node3D.new()
	body.name = "body"
	add_child(body)

	# ---------- legs ----------
	hips = Node3D.new()
	hips.name = "hips"
	hips.position.y = 0.95
	body.add_child(hips)

	pelvis = _box_mesh(0.27, 0.15, 0.17, dark_leather_mat)
	pelvis.name = "pelvis"
	pelvis.position.y = -0.02
	hips.add_child(pelvis)
	_add_outline_pass(pelvis, Color("#3a2d22"))

	var belt = _box_mesh(0.3, 0.05, 0.2, leather_mat)
	belt.position.y = 0.05
	hips.add_child(belt)
	_add_outline_pass(belt, Color("#5b4632"))

	var buckle = _box_mesh(0.06, 0.04, 0.02, accent_glow_mat)
	buckle.position = Vector3(0.05, 0.05, 0.105)
	buckle.name = "buckle_glow"
	hips.add_child(buckle)  # no outline on glow parts

	for side in [-1, 1]:
		var leg = Node3D.new()
		leg.name = "leg_" + ("l" if side == -1 else "r")
		leg.position = Vector3(side * 0.09, 0.0, 0.0)
		hips.add_child(leg)

		var thigh = _capsule_mesh(0.067, 0.27, dark_leather_mat)
		thigh.position.y = -0.21
		leg.add_child(thigh)
		_add_outline_pass(thigh, Color("#3a2d22"))

		var knee = Node3D.new()
		knee.name = "knee"
		knee.position.y = -0.45
		leg.add_child(knee)

		var shin = _capsule_mesh(0.055, 0.26, dark_leather_mat)
		shin.position.y = -0.2
		knee.add_child(shin)
		_add_outline_pass(shin, Color("#3a2d22"))

		var boot = _box_mesh(0.1, 0.08, 0.17, leather_mat)
		boot.position = Vector3(0.0, -0.45, 0.03)
		knee.add_child(boot)
		_add_outline_pass(boot, Color("#5b4632"))

		# Store sub-nodes in metadata (mirrors JS leg.userData)
		leg.set_meta("knee", knee)
		leg.set_meta("thigh", thigh)
		leg.set_meta("shin", shin)
		legs.append(leg)

	# ---------- torso ----------
	spine = Node3D.new()
	spine.name = "spine"
	spine.position.y = 1.0
	body.add_child(spine)

	torso = _capsule_mesh(0.16, 0.3, skin_mat)
	torso.position.y = 0.26
	spine.add_child(torso)
	_add_outline_pass(torso, Color("#f2b186"))

	jerkin = _capsule_mesh(0.165, 0.18, leather_mat)
	jerkin.position.y = 0.18
	spine.add_child(jerkin)
	_add_outline_pass(jerkin, Color("#5b4632"))

	strap = _box_mesh(0.07, 0.5, 0.02, dark_leather_mat)
	strap.position = Vector3(0.02, 0.28, 0.155)
	strap.rotation.z = 0.62
	spine.add_child(strap)
	_add_outline_pass(strap, Color("#3a2d22"))

	# Pauldron is built AFTER arms loop so arm_r (arms[1], side==1) exists.
	# It will be added to arm_r after that loop runs — placeholder here.

	# ---------- arms ----------
	for side in [-1, 1]:
		var arm = Node3D.new()
		arm.name = "arm_" + ("l" if side == -1 else "r")
		# JS: arm.position.set(side * 0.222, 0.45, 0)
		arm.position = Vector3(side * 0.222, 0.45, 0.0)
		spine.add_child(arm)

		var upper = _capsule_mesh(0.054, 0.2, skin_mat)
		upper.position.y = -0.14
		arm.add_child(upper)
		_add_outline_pass(upper, Color("#f2b186"))

		var elbow = Node3D.new()
		elbow.name = "elbow"
		elbow.position.y = -0.3
		arm.add_child(elbow)

		var fore = _capsule_mesh(0.047, 0.18, skin_mat)
		fore.position.y = -0.12
		elbow.add_child(fore)
		_add_outline_pass(fore, Color("#f2b186"))

		var hand = _sphere_mesh(0.052, skin_mat)
		hand.position.y = -0.26
		elbow.add_child(hand)
		_add_outline_pass(hand, Color("#f2b186"))

		arm.set_meta("elbow", elbow)
		arm.set_meta("upper", upper)
		arm.set_meta("fore", fore)
		arm.set_meta("hand", hand)
		arm.set_meta("side", side)
		arms.append(arm)

	# ---------- pauldron (right shoulder armor) ----------
	# Parent to arm_r (arms[1], side==1) so it sits on the shoulder joint and follows arm swing.
	# Local position (0, 0.03, 0) = just above the arm root = top of shoulder cap.
	var arm_r: Node3D = arms[1]
	var pauldron = Node3D.new()
	pauldron.position = Vector3(0.0, 0.03, 0.0)
	pauldron.rotation.z = -0.12
	var plate_a = _box_mesh(0.13, 0.035, 0.14, metal_mat)
	_add_outline_pass(plate_a, Color("#6f7a88"))
	var plate_b = _box_mesh(0.10, 0.03, 0.11, metal_mat)
	plate_b.position.y = 0.04
	_add_outline_pass(plate_b, Color("#6f7a88"))
	var stud = _box_mesh(0.035, 0.02, 0.035, accent_glow_mat)
	stud.position.y = 0.065
	pauldron.add_child(plate_a)
	pauldron.add_child(plate_b)
	pauldron.add_child(stud)  # stud = glow, no outline
	arm_r.add_child(pauldron)

	# Prosthetic aether forearm (left arm [0], shown at high arcaneMod)
	var left_elbow: Node3D = arms[0].get_meta("elbow")
	prosthetic = Node3D.new()
	prosthetic.name = "prosthetic"

	var proseg = _box_mesh(0.075, 0.2, 0.075, metal_mat)
	proseg.position.y = -0.12
	_add_outline_pass(proseg, Color("#6f7a88"))

	var seam1 = _box_mesh(0.012, 0.18, 0.078, vein_mat)
	seam1.position = Vector3(0.034, -0.12, 0.0)
	# seam1 = glow, no outline

	var fist = _box_mesh(0.085, 0.07, 0.08, metal_mat)
	fist.position.y = -0.26
	_add_outline_pass(fist, Color("#6f7a88"))

	var knuckle = _box_mesh(0.087, 0.018, 0.082, vein_mat)
	knuckle.position.y = -0.235
	# knuckle = glow, no outline

	prosthetic.add_child(proseg)
	prosthetic.add_child(seam1)
	prosthetic.add_child(fist)
	prosthetic.add_child(knuckle)
	prosthetic.visible = false
	left_elbow.add_child(prosthetic)

	# ---------- head ----------
	var neck = _capsule_mesh(0.05, 0.07, skin_mat)
	neck.position.y = 0.58
	spine.add_child(neck)
	_add_outline_pass(neck, Color("#f2b186"))

	head = Node3D.new()
	head.name = "head"
	head.position.y = 0.7
	spine.add_child(head)

	skull = _sphere_mesh(0.15, head_mat)
	skull.name = "skull"
	skull.scale.y = 1.07
	# Godot SphereMesh: seam at -Z, so u=0.5 (face strip) faces +Z by default.
	# No Y rotation needed — camera at +Z sees the face strip directly.
	skull.rotation.y = 0.0
	head.add_child(skull)
	_add_outline_pass(skull, Color("#f2b186"))

	jaw_mesh = _box_mesh(0.165, 0.075, 0.13, head_mat)
	jaw_mesh.name = "jaw"
	jaw_mesh.position = Vector3(0.0, -0.105, 0.062)
	head.add_child(jaw_mesh)
	_add_outline_pass(jaw_mesh, Color("#f2b186"))

	cheeks = []
	for side in [-1, 1]:
		var cheek = _sphere_mesh(0.036, head_mat)
		cheek.position = Vector3(side * 0.088, -0.018, 0.108)
		head.add_child(cheek)
		_add_outline_pass(cheek, Color("#f2b186"))
		cheeks.append(cheek)

	eyes = []
	brows = []
	for side in [-1, 1]:
		var eye_group = Node3D.new()
		eye_group.name = "eye_" + ("l" if side == -1 else "r")
		# JS: eye.position.set(side * 0.058, 0.018, 0.136)
		eye_group.position = Vector3(side * 0.058, 0.018, 0.136)

		var white = _sphere_mesh(0.034, eye_white_mat)
		white.scale.z = 0.55
		eye_group.add_child(white)

		var iris = _disc_mesh(0.0185, iris_mat)
		iris.rotation.x = PI / 2.0
		iris.position.z = 0.0195
		eye_group.add_child(iris)

		var pupil = _disc_mesh(0.009, pupil_mat)
		pupil.rotation.x = PI / 2.0
		pupil.position.z = 0.0205
		eye_group.add_child(pupil)

		var glint = _disc_mesh(0.0045, eye_white_mat)
		glint.rotation.x = PI / 2.0
		glint.position = Vector3(0.006, 0.007, 0.021)
		eye_group.add_child(glint)

		eye_group.set_meta("side", side)
		head.add_child(eye_group)
		eyes.append(eye_group)

		# JS: brow.position.set(side * 0.058, 0.07, 0.146)
		var brow = _box_mesh(0.055, 0.012, 0.012, pupil_mat)
		brow.position = Vector3(side * 0.058, 0.07, 0.146)
		head.add_child(brow)
		brows.append(brow)

	# Technomagic goggles (visible at mid arcaneMod > 0.38)
	goggles = Node3D.new()
	goggles.name = "goggles"
	var band = _box_mesh(0.31, 0.03, 0.03, dark_leather_mat)
	band.position = Vector3(0.0, 0.095, 0.0)
	_add_outline_pass(band, Color("#3a2d22"))
	goggles.add_child(band)

	var lens_l = _cylinder_mesh(0.035, 0.035, 0.03, metal_mat)
	lens_l.rotation.x = PI / 2.0
	lens_l.position = Vector3(-0.055, 0.095, 0.125)
	_add_outline_pass(lens_l, Color("#6f7a88"))
	goggles.add_child(lens_l)

	var lens_r = _cylinder_mesh(0.035, 0.035, 0.03, metal_mat)
	lens_r.rotation.x = PI / 2.0
	lens_r.position = Vector3(0.055, 0.095, 0.125)
	_add_outline_pass(lens_r, Color("#6f7a88"))
	goggles.add_child(lens_r)

	var lens_glow_l = _disc_mesh(0.026, accent_glow_mat)
	lens_glow_l.rotation.x = PI / 2.0
	lens_glow_l.position = Vector3(-0.055, 0.095, 0.142)
	goggles.add_child(lens_glow_l)

	var lens_glow_r = _disc_mesh(0.026, accent_glow_mat)
	lens_glow_r.rotation.x = PI / 2.0
	lens_glow_r.position = Vector3(0.055, 0.095, 0.142)
	goggles.add_child(lens_glow_r)

	goggles.visible = false
	head.add_child(goggles)

	# Hair / beard slots
	hair_slot = Node3D.new()
	hair_slot.name = "hair_slot"
	beard_slot = Node3D.new()
	beard_slot.name = "beard_slot"
	head.add_child(hair_slot)
	head.add_child(beard_slot)

	# Origin feature slot (ears, etc.) attached to head; tail to hips
	feature_slot = Node3D.new()
	feature_slot.name = "feature_slot"
	head.add_child(feature_slot)

	tail_slot = Node3D.new()
	tail_slot.name = "tail_slot"
	hips.add_child(tail_slot)

	# Glowing mana veins (visible when arcaneMod > 0.06)
	# JS veinDefs: [parent, x, y, z, w, h]
	var vein_defs: Array = [
		[arms[1],                                    0.045,  -0.1,   0.02,  0.012, 0.16],  # right upper arm
		[arms[1].get_meta("elbow"),                  0.04,   -0.1,   0.015, 0.01,  0.13],  # right forearm
		[spine,                                      0.1,     0.32,  0.145, 0.014, 0.2 ],  # chest line
		[spine,                                     -0.06,    0.5,   0.12,  0.01,  0.09],  # neck side
		[legs[0].get_meta("knee"),                  -0.04,  -0.16,   0.045, 0.01,  0.14],  # left shin
	]
	veins = []
	for def in vein_defs:
		var parent_node: Node3D = def[0]
		var vein = _box_mesh(def[4], def[5], def[4], vein_mat)
		vein.position = Vector3(def[1], def[2], def[3])
		vein.rotation.z = 0.18
		vein.visible = false
		parent_node.add_child(vein)
		veins.append(vein)

# ---- helper: attach outline next_pass to a MeshInstance3D ----
func _add_outline_pass(mi: MeshInstance3D, base_color: Color, thickness: float = 0.02) -> void:
	if mi.material_override != null:
		ToonMaterials.add_outline(mi.material_override, base_color, thickness)

# ---- helper: recurse node tree and add outlines ----
func _apply_outline_to_children(node: Node, base_color: Color, thickness: float) -> void:
	if node is MeshInstance3D:
		var mi = node as MeshInstance3D
		if mi.material_override != null and not (mi.material_override is StandardMaterial3D and (mi.material_override as StandardMaterial3D).emission_enabled):
			_add_outline_pass(mi, base_color, thickness)
	for child in node.get_children():
		_apply_outline_to_children(child, base_color, thickness)

# ================================================================
# _apply_build — internal helper that combines phenotype weight + archetype multiplier.
# Called by both apply_phenotype and apply_archetype so order never matters.
# Archetype multipliers are applied on top of the weight-based scale (X/Z only).
# ================================================================
func _apply_build() -> void:
	if _last_p.is_empty():
		return
	var w: float = _last_p.get("weight", 0.5)
	var limb: float = _lerp(0.82, 1.42, w)

	# Archetype multiplier for X/Z (breadth/depth); 1.0 = neutral
	var arch_xz: float = 1.0
	match _archetype_class:
		"warrior":
			arch_xz = 1.30  # Vanguard — clearly bulky tank
		"thief":
			arch_xz = 0.80  # Duelist — clearly lean/agile

	torso.scale  = Vector3(_lerp(0.84, 1.34, w) * arch_xz, 1.0, _lerp(0.86, 1.26, w) * arch_xz)
	jerkin.scale = Vector3(_lerp(0.86, 1.36, w) * arch_xz, 1.0, _lerp(0.88, 1.28, w) * arch_xz)
	pelvis.scale = Vector3(_lerp(0.88, 1.25, w) * arch_xz, 1.0, 1.0)

	var limb_xz: float = limb * arch_xz
	for arm in arms:
		var upper: MeshInstance3D = arm.get_meta("upper")
		var fore: MeshInstance3D = arm.get_meta("fore")
		upper.scale = Vector3(limb_xz, 1.0, limb_xz)
		fore.scale  = Vector3(limb_xz, 1.0, limb_xz)

	for leg in legs:
		var thigh: MeshInstance3D = leg.get_meta("thigh")
		var shin:  MeshInstance3D = leg.get_meta("shin")
		thigh.scale = Vector3(limb_xz, 1.0, limb_xz)
		shin.scale  = Vector3(limb_xz, 1.0, limb_xz)

	# Vanguard: larger pauldron to read as tank
	var pauldron: Node3D = arms[1].get_child(arms[1].get_child_count() - 1)
	if pauldron != null:
		if _archetype_class == "warrior":
			pauldron.scale = Vector3(1.3, 1.2, 1.3)
		else:
			pauldron.scale = Vector3.ONE

	# Ironblooded armor pieces: scale X/Z by arch_xz so armor is bulky on
	# Vanguard (1.30), lean on Duelist (0.80), neutral on Strategist (1.0).
	# Y is kept at base so piece height doesn't stretch with body width.
	# Safe no-op when _iron_armor is empty (non-ironblooded origins).
	for entry in _iron_armor:
		var n = entry.get("node")
		if is_instance_valid(n):
			var b: Vector3 = entry.get("base", Vector3.ONE)
			n.scale = Vector3(b.x * arch_xz, b.y, b.z * arch_xz)

	# Strategist: floating focus orb (only for mage; remove for all others)
	_update_focus_orb()
	# Vanguard: per-origin presence VFX (only for warrior; remove for all others)
	_update_vanguard_vfx()
	# Strategist: per-origin presence VFX (only for mage; remove for all others)
	_update_strategist_vfx()

# ================================================================
# _update_focus_orb — manages the Strategist emissive focus orb.
# Creates it if class is "mage" and not yet present; removes it otherwise.
# Parented above the right shoulder so it floats when the rig is viewed.
# ================================================================
func _update_focus_orb() -> void:
	if _archetype_class == "mage":
		if _focus_orb == null:
			# Build a small emissive sphere parented to the right arm root.
			# Material is set to accent color so each origin gets a distinctive orb
			# (teal for aetherborn, orange for ironblooded, green for miststalker).
			var orb_mat := StandardMaterial3D.new()
			# Use a moderate emission multiplier (1.0) so the accent hue stays readable
			# at camera distance rather than blooming to white. The albedo already
			# provides a bright saturated base; emission adds a glow ring.
			orb_mat.albedo_color               = accent
			orb_mat.emission_enabled           = true
			orb_mat.emission                   = accent
			orb_mat.emission_energy_multiplier = 1.0
			orb_mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
			_focus_orb = _sphere_mesh(0.055, orb_mat)
			_focus_orb.name = "focus_orb"
			# Position: float above right shoulder (arm_r local space)
			_focus_orb.position = Vector3(0.18, 0.25, 0.0)
			arms[1].add_child(_focus_orb)
		else:
			# Orb already exists — refresh its material to the current accent color
			# so origin switches (e.g. staying mage but changing origin) take effect.
			var orb_mat := _focus_orb.material_override as StandardMaterial3D
			if orb_mat != null:
				orb_mat.albedo_color               = accent
				orb_mat.emission                   = accent
	else:
		if _focus_orb != null:
			_focus_orb.queue_free()
			_focus_orb = null

# ================================================================
# _update_vanguard_vfx — manages Vanguard (warrior) per-Origin presence VFX.
# Creates the appropriate VFX only when _archetype_class == "warrior", branched
# by _origin_id, and frees all nodes otherwise or on origin switch.
# Mirrors the _update_focus_orb lifecycle exactly.
# ================================================================
func _update_vanguard_vfx() -> void:
	# Always free every cell's nodes first (clean state before branch)
	if _aegis_shield != null:
		_aegis_shield.queue_free()
		_aegis_shield = null
	if _thruster_l != null:
		_thruster_l.queue_free()
		_thruster_l = null
	if _thruster_r != null:
		_thruster_r.queue_free()
		_thruster_r = null
	if _pack_wisp != null:
		_pack_wisp.queue_free()
		_pack_wisp = null
	if _stealth_decal != null:
		_stealth_decal.queue_free()
		_stealth_decal = null

	if _archetype_class != "warrior":
		return

	match _origin_id:
		"aetherborn":
			# ---- Arcane Aegis: single translucent teal emissive shield surface ----
			# A rounded quad (BoxMesh, flat on Z) in front of the left arm — one modest
			# transparent surface (overdraw budget: 1 surface).
			var shield_mat := StandardMaterial3D.new()
			shield_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			shield_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			shield_mat.blend_mode   = BaseMaterial3D.BLEND_MODE_ADD
			shield_mat.cull_mode    = BaseMaterial3D.CULL_DISABLED
			shield_mat.albedo_color = Color(0.15, 0.85, 0.95, 0.38)
			shield_mat.emission_enabled = true
			shield_mat.emission         = Color(0.0, 0.65, 0.90) * 1.4
			shield_mat.emission_energy_multiplier = 1.6
			# Rim/fresnel-look: use grow+front-face trick (second mesh pass if desired later;
			# for now the additive blend already creates a limb-glow Fresnel read).

			var shield_mesh := BoxMesh.new()
			shield_mesh.size = Vector3(0.22, 0.30, 0.018)  # flat shield plate

			_aegis_shield = MeshInstance3D.new()
			_aegis_shield.name = "aegis_shield"
			_aegis_shield.mesh = shield_mesh
			_aegis_shield.material_override = shield_mat
			# Parent to left arm (arms[0]), positioned outward/forward at forearm level
			_aegis_shield.position = Vector3(-0.04, -0.28, 0.08)
			arms[0].add_child(_aegis_shield)

		"ironblooded":
			# ---- Juggernaut: steam-exhaust GPUParticles3D jets at both shoulders ----
			# Two jets (left + right), modest amount (~22 each) so total stays ~44.
			for side_idx in range(2):
				var side_sign: float = -1.0 if side_idx == 0 else 1.0
				var arm_node: Node3D = arms[side_idx]

				var jet := GPUParticles3D.new()
				jet.name = "steam_jet_" + ("l" if side_idx == 0 else "r")
				jet.amount = 22
				jet.lifetime = 0.90
				jet.explosiveness = 0.0   # continuous
				jet.fixed_fps = 0
				jet.visibility_aabb = AABB(Vector3(-0.5, -0.1, -0.5), Vector3(1.0, 1.2, 1.0))

				var proc := ParticleProcessMaterial.new()
				proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
				proc.emission_sphere_radius = 0.04
				proc.lifetime_randomness = 0.4
				# Exhaust vents upward and backward from shoulder
				proc.direction = Vector3(side_sign * 0.2, 1.0, -0.4)
				proc.spread = 40.0
				proc.gravity = Vector3(0.0, -1.0, 0.0)   # light — steam drifts
				proc.initial_velocity_min = 0.25
				proc.initial_velocity_max = 0.65
				proc.scale_min = 0.05
				proc.scale_max = 0.12

				# Steam colour: grey-white with a tiny orange-ember core
				var steam_grad := GradientTexture1D.new()
				var grad := Gradient.new()
				grad.colors = PackedColorArray([
					Color(1.0, 0.62, 0.28, 0.85),  # faint orange-hot at source
					Color(0.88, 0.88, 0.88, 0.60),  # light grey steam
					Color(0.75, 0.75, 0.75, 0.0),   # dissipate
				])
				grad.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
				steam_grad.gradient = grad
				proc.color_ramp = steam_grad

				jet.process_material = proc

				# Draw mesh: low-poly sphere (reads as steam puff)
				var puff_mesh := SphereMesh.new()
				puff_mesh.radius = 0.045
				puff_mesh.height = 0.09
				puff_mesh.radial_segments = 5
				puff_mesh.rings = 3
				var puff_mat := StandardMaterial3D.new()
				puff_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				puff_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				puff_mat.blend_mode   = BaseMaterial3D.BLEND_MODE_MIX
				puff_mat.albedo_color = Color(0.85, 0.85, 0.85, 0.55)
				puff_mesh.material = puff_mat
				jet.draw_pass_1 = puff_mesh

				# Position: at the shoulder top, slightly behind
				jet.position = Vector3(0.0, 0.1, -0.06)
				arm_node.add_child(jet)

				if side_idx == 0:
					_thruster_l = jet
				else:
					_thruster_r = jet

		"miststalker":
			# ---- Pack-Leader: spectral wisp orb + stealth-zone ground decal ----

			# 1) Spectral wisp: translucent green blob that orbits the head
			var wisp_mat := StandardMaterial3D.new()
			wisp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			wisp_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			wisp_mat.blend_mode   = BaseMaterial3D.BLEND_MODE_ADD
			wisp_mat.albedo_color = Color(0.18, 0.95, 0.35, 0.70)
			wisp_mat.emission_enabled = true
			wisp_mat.emission         = Color(0.10, 0.80, 0.25) * 1.8
			wisp_mat.emission_energy_multiplier = 1.8

			var wisp_mesh := SphereMesh.new()
			wisp_mesh.radius = 0.065
			wisp_mesh.height = 0.13
			wisp_mesh.radial_segments = 8
			wisp_mesh.rings = 5

			_pack_wisp = MeshInstance3D.new()
			_pack_wisp.name = "pack_wisp"
			_pack_wisp.mesh = wisp_mesh
			_pack_wisp.material_override = wisp_mat
			# Initial position: will be updated in _process orbit
			_pack_wisp.position = Vector3(0.22, 0.12, 0.0)
			# Parent to head so it orbits around the head pivot
			head.add_child(_pack_wisp)
			_wisp_angle = 0.0

			# 2) Stealth-zone ground decal: flat translucent green ring under feet
			# A flat torus-like ring = outer cylinder minus inner (use two concentric
			# flat cylinders in a Node3D; simpler: one thin CylinderMesh with inner_radius).
			# Godot CylinderMesh has no inner_radius, so use a flat TorusMesh.
			var ring_mat := StandardMaterial3D.new()
			ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			ring_mat.blend_mode   = BaseMaterial3D.BLEND_MODE_ADD
			ring_mat.cull_mode    = BaseMaterial3D.CULL_DISABLED
			ring_mat.albedo_color = Color(0.05, 0.70, 0.15, 0.22)
			ring_mat.emission_enabled = true
			ring_mat.emission         = Color(0.04, 0.55, 0.12) * 0.9
			ring_mat.emission_energy_multiplier = 0.9

			var ring_torus := TorusMesh.new()
			ring_torus.inner_radius = 0.35
			ring_torus.outer_radius = 0.50
			ring_torus.rings = 24
			ring_torus.ring_segments = 12

			_stealth_decal = MeshInstance3D.new()
			_stealth_decal.name = "stealth_ring"
			_stealth_decal.mesh = ring_torus
			_stealth_decal.material_override = ring_mat
			# Place at ground level; rig root is at origin, feet at ~y=-0.95 in world,
			# but in body-local space hips are at 0.95. Place ring at body.position_y = 0
			# so it's at character's feet in rig-local space (world y=0).
			_stealth_decal.position = Vector3(0.0, -0.98, 0.0)
			add_child(_stealth_decal)

# ================================================================
# _update_strategist_vfx — manages Strategist (mage) per-Origin presence VFX.
# Creates the appropriate VFX only when _archetype_class == "mage", branched
# by _origin_id, and frees all nodes otherwise or on origin switch.
# Mirrors the _update_vanguard_vfx lifecycle exactly.
# ================================================================
func _update_strategist_vfx() -> void:
	# Always free every cell's nodes first (clean state before branch)
	if _chrono_field != null:
		_chrono_field.queue_free()
		_chrono_field = null
	if _chrono_decal != null:
		_chrono_decal.queue_free()
		_chrono_decal = null
	if _thermite_embers != null:
		_thermite_embers.queue_free()
		_thermite_embers = null
	if _thermite_decal != null:
		_thermite_decal.queue_free()
		_thermite_decal = null
	if _shaman_decal != null:
		_shaman_decal.queue_free()
		_shaman_decal = null
	if _shaman_aura != null:
		_shaman_aura.queue_free()
		_shaman_aura = null

	if _archetype_class != "mage":
		return

	match _origin_id:
		"aetherborn":
			# ---- Chrono-Weaver: screen-space refraction dome + teal ground ring ----

			# 1) Translucent refraction dome around the character (SphereMesh + chrono shader)
			var dome_mat := ShaderMaterial.new()
			dome_mat.shader = _CHRONO_SHADER
			dome_mat.set_shader_parameter("tint_color",         Color(0.15, 0.85, 0.90, 1.0))
			dome_mat.set_shader_parameter("distortion_amount",  0.008)
			dome_mat.set_shader_parameter("dome_alpha",         0.30)
			dome_mat.set_shader_parameter("wobble_freq",        2.2)

			var dome_mesh := SphereMesh.new()
			dome_mesh.radius          = 0.88   # modest — keeps overdraw low
			dome_mesh.height          = 1.76
			dome_mesh.radial_segments = 16
			dome_mesh.rings           = 10

			_chrono_field = MeshInstance3D.new()
			_chrono_field.name              = "chrono_dome"
			_chrono_field.mesh              = dome_mesh
			_chrono_field.material_override = dome_mat
			# Centre at torso height (~1.05 above rig root = spine base 1.0 + a bit)
			_chrono_field.position = Vector3(0.0, 1.05, 0.0)
			add_child(_chrono_field)

			# 2) Faint teal ground AoE ring decal
			var ring_mat := StandardMaterial3D.new()
			ring_mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
			ring_mat.transparency    = BaseMaterial3D.TRANSPARENCY_ALPHA
			ring_mat.blend_mode      = BaseMaterial3D.BLEND_MODE_ADD
			ring_mat.cull_mode       = BaseMaterial3D.CULL_DISABLED
			ring_mat.albedo_color    = Color(0.10, 0.75, 0.85, 0.28)
			ring_mat.emission_enabled = true
			ring_mat.emission        = Color(0.04, 0.60, 0.80) * 0.8
			ring_mat.emission_energy_multiplier = 0.8

			var ring_torus := TorusMesh.new()
			ring_torus.inner_radius  = 0.65
			ring_torus.outer_radius  = 0.88
			ring_torus.rings         = 24
			ring_torus.ring_segments = 12

			_chrono_decal = MeshInstance3D.new()
			_chrono_decal.name              = "chrono_ring"
			_chrono_decal.mesh              = ring_torus
			_chrono_decal.material_override = ring_mat
			_chrono_decal.position          = Vector3(0.0, -0.98, 0.0)
			add_child(_chrono_decal)

		"ironblooded":
			# ---- Thermite-Sage: orange ember GPUParticles3D + orange ground ring ----

			# 1) Orange ember particles rising around the character
			_thermite_embers = GPUParticles3D.new()
			_thermite_embers.name           = "thermite_embers"
			_thermite_embers.amount         = 22
			_thermite_embers.lifetime       = 1.20
			_thermite_embers.explosiveness  = 0.0   # continuous
			_thermite_embers.fixed_fps      = 0
			_thermite_embers.visibility_aabb = AABB(Vector3(-0.6, -0.1, -0.6), Vector3(1.2, 2.0, 1.2))

			var ember_proc := ParticleProcessMaterial.new()
			ember_proc.emission_shape        = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			ember_proc.emission_sphere_radius = 0.35   # spawn in a ring around body
			ember_proc.lifetime_randomness   = 0.45
			ember_proc.direction             = Vector3(0.0, 1.0, 0.0)
			ember_proc.spread                = 50.0
			ember_proc.gravity               = Vector3(0.0, 0.5, 0.0)   # embers drift up
			ember_proc.initial_velocity_min  = 0.20
			ember_proc.initial_velocity_max  = 0.60
			ember_proc.scale_min             = 0.025
			ember_proc.scale_max             = 0.06

			# Orange-to-transparent ember colour ramp
			var ember_grad := GradientTexture1D.new()
			var eg := Gradient.new()
			eg.colors  = PackedColorArray([
				Color(1.00, 0.70, 0.10, 1.0),  # bright orange-yellow core
				Color(1.00, 0.40, 0.05, 0.80),  # deeper orange
				Color(0.80, 0.20, 0.02, 0.0),   # fade to transparent
			])
			eg.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
			ember_grad.gradient = eg
			ember_proc.color_ramp = ember_grad

			_thermite_embers.process_material = ember_proc

			# Tiny sphere draw pass — reads as glowing ember dot
			var ember_sphere := SphereMesh.new()
			ember_sphere.radius          = 0.018
			ember_sphere.height          = 0.036
			ember_sphere.radial_segments = 4
			ember_sphere.rings           = 2
			var ember_draw_mat := StandardMaterial3D.new()
			ember_draw_mat.shading_mode      = BaseMaterial3D.SHADING_MODE_UNSHADED
			ember_draw_mat.emission_enabled  = true
			ember_draw_mat.emission          = Color(1.0, 0.55, 0.08)
			ember_draw_mat.albedo_color      = Color(1.0, 0.55, 0.08)
			ember_draw_mat.transparency      = BaseMaterial3D.TRANSPARENCY_ALPHA
			ember_draw_mat.blend_mode        = BaseMaterial3D.BLEND_MODE_ADD
			ember_sphere.material            = ember_draw_mat
			_thermite_embers.draw_pass_1     = ember_sphere

			# Parented to rig root, centred — emitters spread outward via sphere emission
			_thermite_embers.position = Vector3(0.0, 1.0, 0.0)
			add_child(_thermite_embers)

			# 2) Orange napalm ground ring decal
			var therm_ring_mat := StandardMaterial3D.new()
			therm_ring_mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
			therm_ring_mat.transparency    = BaseMaterial3D.TRANSPARENCY_ALPHA
			therm_ring_mat.blend_mode      = BaseMaterial3D.BLEND_MODE_ADD
			therm_ring_mat.cull_mode       = BaseMaterial3D.CULL_DISABLED
			therm_ring_mat.albedo_color    = Color(0.90, 0.38, 0.05, 0.30)
			therm_ring_mat.emission_enabled = true
			therm_ring_mat.emission        = Color(0.80, 0.30, 0.02) * 1.2
			therm_ring_mat.emission_energy_multiplier = 1.2

			var therm_torus := TorusMesh.new()
			therm_torus.inner_radius  = 0.28
			therm_torus.outer_radius  = 0.50
			therm_torus.rings         = 24
			therm_torus.ring_segments = 12

			_thermite_decal = MeshInstance3D.new()
			_thermite_decal.name              = "thermite_ring"
			_thermite_decal.mesh              = therm_torus
			_thermite_decal.material_override = therm_ring_mat
			_thermite_decal.position          = Vector3(0.0, -0.98, 0.0)
			add_child(_thermite_decal)

		"miststalker":
			# ---- Blood-Shaman: green-red siphon ring + green heal-aura particles ----

			# 1) Green→red translucent siphon ground ring (brighter + larger for legibility)
			var siphon_mat := StandardMaterial3D.new()
			siphon_mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
			siphon_mat.transparency    = BaseMaterial3D.TRANSPARENCY_ALPHA
			siphon_mat.blend_mode      = BaseMaterial3D.BLEND_MODE_ADD
			siphon_mat.cull_mode       = BaseMaterial3D.CULL_DISABLED
			# Bumped alpha 0.26→0.42 and brighter emission for clear readability at distance
			siphon_mat.albedo_color    = Color(0.30, 0.70, 0.15, 0.42)
			siphon_mat.emission_enabled = true
			siphon_mat.emission        = Color(0.20, 0.65, 0.10) * 1.5
			siphon_mat.emission_energy_multiplier = 1.5

			# Slightly larger torus (inner 0.32→0.30, outer 0.55→0.62) for visibility
			var siphon_torus := TorusMesh.new()
			siphon_torus.inner_radius  = 0.30
			siphon_torus.outer_radius  = 0.62
			siphon_torus.rings         = 28
			siphon_torus.ring_segments = 14

			_shaman_decal = MeshInstance3D.new()
			_shaman_decal.name              = "siphon_ring"
			_shaman_decal.mesh              = siphon_torus
			_shaman_decal.material_override = siphon_mat
			_shaman_decal.position          = Vector3(0.0, -0.98, 0.0)
			add_child(_shaman_decal)

			# Outer red drain ring — brighter than before for the drain edge read
			var drain_mat := StandardMaterial3D.new()
			drain_mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
			drain_mat.transparency    = BaseMaterial3D.TRANSPARENCY_ALPHA
			drain_mat.blend_mode      = BaseMaterial3D.BLEND_MODE_ADD
			drain_mat.cull_mode       = BaseMaterial3D.CULL_DISABLED
			drain_mat.albedo_color    = Color(0.85, 0.12, 0.12, 0.32)
			drain_mat.emission_enabled = true
			drain_mat.emission        = Color(0.75, 0.08, 0.08) * 1.2
			drain_mat.emission_energy_multiplier = 1.2

			var drain_torus := TorusMesh.new()
			drain_torus.inner_radius  = 0.58
			drain_torus.outer_radius  = 0.72
			drain_torus.rings         = 24
			drain_torus.ring_segments = 10

			var drain_ring := MeshInstance3D.new()
			drain_ring.name              = "drain_ring"
			drain_ring.mesh              = drain_torus
			drain_ring.material_override = drain_mat
			drain_ring.position          = Vector3(0.0, -0.98, 0.0)
			add_child(drain_ring)

			# 1b) Green siphon wisps — 3 short vertical rising columns (one-surface each)
			# Very thin capsules rising from just above the ring, bright green additive.
			var wisp_mat := StandardMaterial3D.new()
			wisp_mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
			wisp_mat.transparency    = BaseMaterial3D.TRANSPARENCY_ALPHA
			wisp_mat.blend_mode      = BaseMaterial3D.BLEND_MODE_ADD
			wisp_mat.cull_mode       = BaseMaterial3D.CULL_DISABLED
			wisp_mat.albedo_color    = Color(0.15, 0.90, 0.25, 0.55)
			wisp_mat.emission_enabled = true
			wisp_mat.emission        = Color(0.10, 0.80, 0.20) * 1.6
			wisp_mat.emission_energy_multiplier = 1.6
			# 3 wisps at equal angles around the ring
			var wisp_angles: PackedFloat32Array = PackedFloat32Array([0.0, 2.094, 4.189])  # 0, 120, 240 deg
			for wa in wisp_angles:
				var wx: float = sin(wa) * 0.46
				var wz: float = cos(wa) * 0.46
				var wisp_cap := CapsuleMesh.new()
				wisp_cap.radius = 0.028
				wisp_cap.height = 0.22
				var wisp_mi := MeshInstance3D.new()
				wisp_mi.mesh = wisp_cap
				wisp_mi.material_override = wisp_mat
				wisp_mi.position = Vector3(wx, -0.78, wz)   # slightly above ground ring
				add_child(wisp_mi)

			# 2) Green heal-aura GPUParticles3D drifting upward (~18 particles)
			_shaman_aura = GPUParticles3D.new()
			_shaman_aura.name            = "shaman_aura"
			_shaman_aura.amount          = 18
			_shaman_aura.lifetime        = 1.60
			_shaman_aura.explosiveness   = 0.0
			_shaman_aura.fixed_fps       = 0
			_shaman_aura.visibility_aabb = AABB(Vector3(-0.6, 0.0, -0.6), Vector3(1.2, 2.2, 1.2))

			var aura_proc := ParticleProcessMaterial.new()
			aura_proc.emission_shape        = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			aura_proc.emission_sphere_radius = 0.30
			aura_proc.lifetime_randomness   = 0.40
			aura_proc.direction             = Vector3(0.0, 1.0, 0.0)
			aura_proc.spread                = 35.0
			aura_proc.gravity               = Vector3(0.0, 0.35, 0.0)   # gentle upward drift
			aura_proc.initial_velocity_min  = 0.15
			aura_proc.initial_velocity_max  = 0.45
			aura_proc.scale_min             = 0.022
			aura_proc.scale_max             = 0.052

			var aura_grad := GradientTexture1D.new()
			var ag := Gradient.new()
			ag.colors  = PackedColorArray([
				Color(0.35, 1.00, 0.35, 1.0),  # bright heal green
				Color(0.15, 0.85, 0.25, 0.60),  # mid green
				Color(0.05, 0.60, 0.15, 0.0),   # fade out
			])
			ag.offsets = PackedFloat32Array([0.0, 0.50, 1.0])
			aura_grad.gradient = ag
			aura_proc.color_ramp = aura_grad

			_shaman_aura.process_material = aura_proc

			var aura_sphere := SphereMesh.new()
			aura_sphere.radius          = 0.016
			aura_sphere.height          = 0.032
			aura_sphere.radial_segments = 4
			aura_sphere.rings           = 2
			var aura_draw_mat := StandardMaterial3D.new()
			aura_draw_mat.shading_mode      = BaseMaterial3D.SHADING_MODE_UNSHADED
			aura_draw_mat.emission_enabled  = true
			aura_draw_mat.emission          = Color(0.20, 1.00, 0.35)
			aura_draw_mat.albedo_color      = Color(0.20, 1.00, 0.35)
			aura_draw_mat.transparency      = BaseMaterial3D.TRANSPARENCY_ALPHA
			aura_draw_mat.blend_mode        = BaseMaterial3D.BLEND_MODE_ADD
			aura_sphere.material            = aura_draw_mat
			_shaman_aura.draw_pass_1        = aura_sphere

			_shaman_aura.position = Vector3(0.0, 0.05, 0.0)
			add_child(_shaman_aura)

# ================================================================
# apply_archetype — set the combat archetype and re-apply proportions.
# Call after apply_phenotype (or at any time; idempotent on repeated calls).
# class_id: "warrior" | "mage" | "thief"  (empty string = reset to neutral)
# ================================================================
func apply_archetype(class_id: String) -> void:
	_archetype_class = class_id
	_apply_build()

# ================================================================
# apply_phenotype — live-update all sliders. Mirrors JS applyPhenotype exactly.
# p: Dictionary with same keys as PhenotypeData.default_phenotype()
# origin: Dictionary from OriginsData.get_origin(id)
# ================================================================
func apply_phenotype(p: Dictionary, origin: Dictionary) -> void:
	# Cache for re-application by apply_archetype
	_last_p = p
	_last_origin = origin
	_apply_build()

	# Height: uniform root scale within origin heightRange
	var range_arr: Array = origin.get("heightRange", [0.94, 1.1])
	scale = Vector3.ONE * _lerp(float(range_arr[0]), float(range_arr[1]), p.get("height", 0.5))

	# Arcane modification thresholds (JS: >0.06, >0.38, >0.68)
	var mod: float = p.get("arcaneMod", 0.0)
	for vein in veins:
		vein.visible = mod > 0.06
	# Vein color: JS: veinMat.color.copy(accent).multiplyScalar(0.35 + mod * 1.8)
	var vein_brightness: float = 0.35 + mod * 1.8
	vein_mat.albedo_color = accent * vein_brightness
	vein_mat.emission = accent * vein_brightness

	goggles.visible = mod > 0.38

	var prosthetic_on: bool = mod > 0.68
	prosthetic.visible = prosthetic_on
	var left_fore: MeshInstance3D = arms[0].get_meta("fore")
	var left_hand: MeshInstance3D = arms[0].get_meta("hand")
	left_fore.visible = not prosthetic_on
	left_hand.visible = not prosthetic_on

	# ---- face structure ----
	# JS jaw.scale: lerp(0.72..1.28, 0.85..1.18, 0.8..1.22)
	var jaw_v: float = p.get("jaw", 0.5)
	jaw_mesh.scale = Vector3(
		_lerp(0.72, 1.28, jaw_v),
		_lerp(0.85, 1.18, jaw_v),
		_lerp(0.8, 1.22, jaw_v)
	)

	# JS cheek.position.y = lerp(-0.045, 0.012, cheek), scale lerp(0.75..1.3)
	var cheek_v: float = p.get("cheek", 0.5)
	for cheek in cheeks:
		cheek.position.y = _lerp(-0.045, 0.012, cheek_v)
		var cheek_s: float = _lerp(0.75, 1.3, cheek_v)
		cheek.scale = Vector3(cheek_s, cheek_s, cheek_s)

	# JS eyes: rotation.z = side * lerp(-0.32, 0.26, eyeTilt), scale.y = lerp(0.5, 1.3, eyeShape)
	# JS brows: rotation.z = side * lerp(-0.4, 0.18, eyeTilt)
	var eye_tilt: float = p.get("eyeTilt", 0.5)
	var eye_shape: float = p.get("eyeShape", 0.5)
	for i in range(eyes.size()):
		var eye = eyes[i]
		var side: int = eye.get_meta("side")
		eye.rotation.z = float(side) * _lerp(-0.32, 0.26, eye_tilt)
		eye.scale.y = _lerp(0.5, 1.3, eye_shape)
		brows[i].rotation.z = float(side) * _lerp(-0.4, 0.18, eye_tilt)

	# ---- colors ----
	var skin_tones: Array = PaletteData.SKIN_TONES
	var hair_colors: Array = PaletteData.HAIR_COLORS
	var paint_colors: Array = PaletteData.PAINT_COLORS

	var skin_idx: int = int(p.get("skinTone", 1))
	var hair_idx: int = int(p.get("hairColor", 0))
	var paint_idx: int = int(p.get("paintColor", 0))

	var skin_color: Color = skin_tones[clamp(skin_idx, 0, skin_tones.size() - 1)]
	var hair_color: Color = hair_colors[clamp(hair_idx, 0, hair_colors.size() - 1)]
	var paint_color: Color = paint_colors[clamp(paint_idx, 0, paint_colors.size() - 1)]

	skin_mat.set_shader_parameter("albedo_color", skin_color)
	hair_mat.set_shader_parameter("albedo_color", hair_color)

	# Head texture (warpaint atlas)
	var warpaint_idx: int = int(p.get("warpaint", 0))
	var tex_key = skin_color.to_html() + "|" + str(warpaint_idx) + "|" + paint_color.to_html()
	if tex_key != _head_tex_key:
		_head_tex_key = tex_key
		var new_tex = WarpaintAtlas.build_head_texture(skin_color, warpaint_idx, paint_color)
		head_mat = ToonMaterials.toon_mat_textured(new_tex)
		skull.material_override = head_mat
		jaw_mesh.material_override = head_mat
		for cheek in cheeks:
			cheek.material_override = head_mat

	# ---- hair swap ----
	var hair_style: int = int(p.get("hair", 0))
	var hair_k = str(hair_style)
	if hair_k != _hair_key:
		_hair_key = hair_k
		for child in hair_slot.get_children():
			hair_slot.remove_child(child)
			child.queue_free()
		var built = HairLibrary.build_hair(hair_style, hair_mat)
		if built != null:
			_apply_outline_to_children(built, hair_color, 0.025)
			hair_slot.add_child(built)

	# ---- beard swap ----
	var beard_style: int = int(p.get("beard", 0))
	var beard_k = str(beard_style)
	if beard_k != _beard_key:
		_beard_key = beard_k
		for child in beard_slot.get_children():
			beard_slot.remove_child(child)
			child.queue_free()
		var built_b = HairLibrary.build_beard(beard_style, hair_mat)
		if built_b != null and built_b.get_child_count() > 0:
			_apply_outline_to_children(built_b, hair_color, 0.025)
			beard_slot.add_child(built_b)

	# ---- origin features (ears, tail, accent) ----
	var origin_id: String = origin.get("id", "")
	if origin_id != _origin_id:
		_origin_id = origin_id
		var theme: Dictionary = origin.get("theme", {})
		var accent_hex: String = theme.get("accent", "#46e6ff")
		accent = Color(accent_hex)
		iris_mat.albedo_color = accent
		accent_glow_mat.albedo_color = accent * 1.2
		accent_glow_mat.emission = accent * 1.2
		_build_origin_features(origin)

	# ---- per-origin rim override (MUST be after warpaint rebuild so head_mat is current) ----
	_apply_origin_rim()

## Set rim_color = accent on every toon ShaderMaterial for per-origin identity.
## Also sets origin-specific rim_strength (aetherborn gets higher = glassy look).
## Ironblooded gets a bright hot-orange rim for a forge-fire silhouette glow.
func _apply_origin_rim() -> void:
	var rim_str: float
	var rim_col: Color

	if _origin_id == "aetherborn":
		rim_str = 0.28
		rim_col = accent
	elif _origin_id == "ironblooded":
		rim_str = 0.32
		rim_col = Color(1.0, 0.45, 0.12)  # bright hot forge orange
	else:
		rim_str = 0.18
		rim_col = accent

	var toon_mats: Array = [skin_mat, head_mat, leather_mat, dark_leather_mat, metal_mat, hair_mat]
	for mat in toon_mats:
		if mat is ShaderMaterial:
			mat.set_shader_parameter("rim_color", rim_col)
			mat.set_shader_parameter("rim_strength", rim_str)

# ================================================================
# _build_iron_armor — creates cel-shaded metal armor pieces for the ironblooded
# origin: left pauldron, chest plate, two greaves, two bracers.
# All pieces use metal_mat so they automatically inherit the dark-iron albedo +
# orange-emission + forge-rim applied in _build_origin_features/ironblooded.
# Each piece is recorded in _iron_armor for cleanup and archetype scaling.
# NEVER parents anything to arms[1] — the existing right-pauldron last-child
# lookup in _apply_build must stay untouched.
# ================================================================
func _build_iron_armor() -> void:
	# ---- LEFT PAULDRON — mirrored from the right pauldron on arms[1] ----
	# Parent to arms[0] (left arm root). arms[0] has no existing pauldron child,
	# so adding here does not affect the arms[1].get_child(count-1) lookup.
	var pauldron_l := Node3D.new()
	pauldron_l.name = "pauldron_l"
	pauldron_l.position = Vector3(0.0, 0.03, 0.0)
	pauldron_l.rotation.z = 0.12   # mirror of right shoulder's -0.12
	var pl_a := _box_mesh(0.13, 0.035, 0.14, metal_mat)
	_add_outline_pass(pl_a, Color("#6f7a88"))
	var pl_b := _box_mesh(0.10, 0.03, 0.11, metal_mat)
	pl_b.position.y = 0.04
	_add_outline_pass(pl_b, Color("#6f7a88"))
	var pl_stud := _box_mesh(0.035, 0.02, 0.035, accent_glow_mat)
	pl_stud.position.y = 0.065
	pauldron_l.add_child(pl_a)
	pauldron_l.add_child(pl_b)
	pauldron_l.add_child(pl_stud)
	arms[0].add_child(pauldron_l)
	_iron_armor.append({"node": pauldron_l, "base": Vector3.ONE})

	# ---- CHEST PLATE — parented to spine, covers the torso ----
	var chest := _box_mesh(0.30, 0.26, 0.16, metal_mat)
	chest.name = "chest_plate"
	chest.position = Vector3(0.0, 0.26, 0.04)
	_add_outline_pass(chest, Color("#6f7a88"))
	spine.add_child(chest)
	_iron_armor.append({"node": chest, "base": Vector3.ONE})

	# ---- GREAVES — one shin guard per leg, parented to each leg's knee pivot ----
	for leg in legs:
		var knee_node: Node3D = leg.get_meta("knee")
		var greave := _box_mesh(0.12, 0.22, 0.13, metal_mat)
		greave.name = "greave"
		greave.position = Vector3(0.0, -0.13, 0.02)
		_add_outline_pass(greave, Color("#6f7a88"))
		knee_node.add_child(greave)
		_iron_armor.append({"node": greave, "base": Vector3.ONE})

	# ---- BRACERS — one forearm cuff per arm, parented to each arm's elbow pivot ----
	for arm in arms:
		var elbow_node: Node3D = arm.get_meta("elbow")
		var bracer := _box_mesh(0.11, 0.14, 0.11, metal_mat)
		bracer.name = "bracer"
		bracer.position = Vector3(0.0, -0.12, 0.0)
		_add_outline_pass(bracer, Color("#6f7a88"))
		elbow_node.add_child(bracer)
		_iron_armor.append({"node": bracer, "base": Vector3.ONE})

func _build_origin_features(origin: Dictionary) -> void:
	# ---- clean up previous origin's exclusive nodes ----
	for child in feature_slot.get_children():
		feature_slot.remove_child(child)
		child.queue_free()
	for child in tail_slot.get_children():
		tail_slot.remove_child(child)
		child.queue_free()

	# Clean up ironblooded sparks (always; only re-created when ironblooded)
	if _spark_particles != null:
		_spark_particles.queue_free()
		_spark_particles = null

	# Clean up ironblooded armor pieces (always; only re-created when ironblooded)
	for entry in _iron_armor:
		var n = entry.get("node")
		if is_instance_valid(n):
			n.queue_free()
	_iron_armor.clear()

	# Clean up miststalker fur (always; only re-created when miststalker)
	if _fur_slot != null:
		_fur_slot.queue_free()
		_fur_slot = null

	# Reset metal heat glow (cleared for all non-ironblooded origins)
	metal_mat.set_shader_parameter("emission_color", Color(0.0, 0.0, 0.0, 1.0))
	metal_mat.set_shader_parameter("emission_strength", 0.0)
	metal_mat.set_shader_parameter("albedo_color", Color("#6f7a88"))

	# Reset leather to neutral originals (overwritten below for ironblooded warm tint)
	leather_mat.set_shader_parameter("albedo_color", Color("#5b4632"))
	dark_leather_mat.set_shader_parameter("albedo_color", Color("#3a2d22"))

	# Reset vein materials back to the shared instance (clears aetherborn per-vein duplicates)
	for vein in veins:
		vein.material_override = vein_mat

	var id: String = origin.get("id", "")

	if id == "aetherborn":
		# Long pointed elven ears (ConeGeometry(0.026, 0.14, 6))
		for side in [-1, 1]:
			var ear = MeshInstance3D.new()
			var mesh = CylinderMesh.new()
			mesh.top_radius = 0.001
			mesh.bottom_radius = 0.026
			mesh.height = 0.14
			ear.mesh = mesh
			ear.material_override = skin_mat
			ear.position = Vector3(side * 0.155, 0.02, 0.0)
			ear.rotation = Vector3(-0.25, 0.0, float(side) * -1.95)
			_add_outline_pass(ear, Color("#f2b186"), 0.02)
			feature_slot.add_child(ear)
		# (vein flow animation is handled in _process when _origin_id=="aetherborn")

	elif id == "miststalker":
		# Beastfolk ears (ConeGeometry(0.045, 0.11, 5)) using hair color
		for side in [-1, 1]:
			var ear = MeshInstance3D.new()
			var mesh = CylinderMesh.new()
			mesh.top_radius = 0.001
			mesh.bottom_radius = 0.045
			mesh.height = 0.11
			ear.mesh = mesh
			ear.material_override = hair_mat
			ear.position = Vector3(side * 0.082, 0.15, 0.0)
			ear.rotation.z = float(side) * -0.35
			_add_outline_pass(ear, Color("#b8451f"), 0.02)
			feature_slot.add_child(ear)

		# Tail: 6 sphere segments tapering from hips
		var tail = Node3D.new()
		var r: float = 0.035
		for i in range(6):
			var seg = MeshInstance3D.new()
			var smesh = SphereMesh.new()
			smesh.radius = r
			smesh.height = r * 2.0
			seg.mesh = smesh
			seg.material_override = hair_mat
			seg.position = Vector3(0.0, -0.05 - float(i) * 0.012, -0.12 - float(i) * 0.07)
			_add_outline_pass(seg, Color("#b8451f"), 0.02)
			tail.add_child(seg)
			r *= 0.92
		tail_slot.add_child(tail)

		# ---- Miststalker fake-fur tufts ----
		# A few flat alpha-card-like quads (thin boxes) on shoulders and torso to
		# read as a pelt silhouette. Green-tinted, slightly semi-transparent.
		# Parented to spine so they follow the torso.
		_fur_slot = Node3D.new()
		_fur_slot.name = "fur_slot"
		spine.add_child(_fur_slot)

		var fur_color: Color = Color(0.18, 0.38, 0.12, 0.72)  # mossy green, partly transparent
		var fur_mat := StandardMaterial3D.new()
		fur_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fur_mat.albedo_color = fur_color
		fur_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fur_mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # visible from both sides

		# Left shoulder tuft
		var tuft_l := _box_mesh(0.08, 0.14, 0.03, fur_mat)
		tuft_l.position = Vector3(-0.22, 0.44, 0.0)
		tuft_l.rotation.z = 0.3
		_fur_slot.add_child(tuft_l)

		# Right shoulder tuft (smaller — pauldron is on this side)
		var tuft_r := _box_mesh(0.06, 0.10, 0.03, fur_mat)
		tuft_r.position = Vector3(0.22, 0.44, 0.0)
		tuft_r.rotation.z = -0.3
		_fur_slot.add_child(tuft_r)

		# Chest center tuft
		var tuft_c := _box_mesh(0.07, 0.16, 0.03, fur_mat)
		tuft_c.position = Vector3(0.0, 0.30, 0.15)
		_fur_slot.add_child(tuft_c)

		# Forearm left tuft
		var tuft_fa := _box_mesh(0.06, 0.11, 0.025, fur_mat)
		tuft_fa.position = Vector3(-0.22, 0.18, 0.0)
		tuft_fa.rotation.z = 0.15
		_fur_slot.add_child(tuft_fa)

	else:
		# ---- Ironblooded: compact round ears + heat glow + sparks ----
		for side in [-1, 1]:
			var ear = MeshInstance3D.new()
			var smesh = SphereMesh.new()
			smesh.radius = 0.032
			smesh.height = 0.064
			ear.mesh = smesh
			ear.material_override = skin_mat
			ear.position = Vector3(side * 0.148, 0.0, 0.0)
			_add_outline_pass(ear, Color("#f2b186"), 0.02)
			feature_slot.add_child(ear)

		# Warm body tint: leather clothing reads rust/amber so the ironblooded silhouette
		# reads warm at distance (not just via the low-contrast rim).
		leather_mat.set_shader_parameter("albedo_color", Color("#6e3a1f"))
		dark_leather_mat.set_shader_parameter("albedo_color", Color("#3a1d10"))

		# Heat glow: metal parts (pauldron, prosthetic) read as heated forge-metal.
		# Dark iron albedo so the hot-orange emission pops against the dark base.
		metal_mat.set_shader_parameter("albedo_color", Color(0.22, 0.20, 0.20))
		metal_mat.set_shader_parameter("emission_color", Color(1.0, 0.42, 0.10, 1.0))
		metal_mat.set_shader_parameter("emission_strength", 1.8)

		# Cel-shaded armor pieces (left pauldron, chest plate, greaves, bracers).
		# Must be called AFTER metal_mat heat parameters are set so all pieces
		# inherit the forge look immediately on first build.
		_build_iron_armor()

		# Sparks: forge-style GPUParticles3D near right shoulder pauldron.
		# Amount ~30 gives continuous visible arcing without overdraw excess.
		_spark_particles = GPUParticles3D.new()
		_spark_particles.name = "iron_sparks"
		_spark_particles.amount = 30
		_spark_particles.lifetime = 0.70
		_spark_particles.explosiveness = 0.0          # continuous stream
		_spark_particles.fixed_fps = 0
		_spark_particles.visibility_aabb = AABB(Vector3(-0.4, -0.2, -0.4), Vector3(0.8, 1.0, 0.8))

		var spark_proc := ParticleProcessMaterial.new()
		spark_proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		spark_proc.emission_sphere_radius = 0.05
		spark_proc.lifetime_randomness = 0.35   # variance: not all sparks die at once
		# Biased upward/outward like forge sparks rising from hot metal
		spark_proc.direction = Vector3(0.2, 1.0, 0.0)
		spark_proc.spread = 65.0
		spark_proc.gravity = Vector3(0.0, -6.0, 0.0)   # pull sparks into arc
		spark_proc.initial_velocity_min = 0.45
		spark_proc.initial_velocity_max = 1.0
		# Slightly larger sparks so they read at a glance
		spark_proc.scale_min = 0.018
		spark_proc.scale_max = 0.038
		# Bright white-orange core → deep orange fade → transparent
		var spark_grad := GradientTexture1D.new()
		var grad := Gradient.new()
		grad.colors = PackedColorArray([
			Color(1.0, 0.90, 0.55, 1.0),   # white-hot core
			Color(1.0, 0.55, 0.12, 0.85),  # orange mid
			Color(1.0, 0.25, 0.03, 0.0)    # ember tail, transparent
		])
		grad.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
		spark_grad.gradient = grad
		spark_proc.color_ramp = spark_grad

		_spark_particles.process_material = spark_proc

		# Tiny sphere mesh for each spark — use PrimitiveMesh.material to avoid
		# lazy-surface-generation issues with surface_set_material.
		var spark_sphere := SphereMesh.new()
		spark_sphere.radius = 0.011
		spark_sphere.height = 0.022
		spark_sphere.radial_segments = 4
		spark_sphere.rings = 2
		var spark_draw_mat := StandardMaterial3D.new()
		spark_draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		spark_draw_mat.emission_enabled = true
		spark_draw_mat.emission = Color(1.0, 0.65, 0.15)
		spark_draw_mat.albedo_color = Color(1.0, 0.65, 0.15)
		spark_draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		spark_draw_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		spark_sphere.material = spark_draw_mat  # PrimitiveMesh.material: safe before surface gen
		_spark_particles.draw_pass_1 = spark_sphere

		# Place near the right shoulder (arm_r is arms[1])
		_spark_particles.position = Vector3(0.0, 0.06, 0.0)
		arms[1].add_child(_spark_particles)

# ================================================================
# Motion API — mirrors JS setMotion / playAttack / update
# ================================================================

## Set locomotion parameters (speed 0..1, crouch bool).
func set_motion(speed_norm: float, crouch: bool) -> void:
	_motion_speed = speed_norm
	_motion_crouch = crouch

## Trigger an attack animation. kind = "melee" or "bolt".
func play_attack(kind: String) -> void:
	_attack_style = kind
	_attack_timer = 0.38

func _process(delta: float) -> void:
	_t += delta
	var speed: float = _motion_speed
	var crouch: bool = _motion_crouch

	# Locomotion phase advance (JS: phase += dt * (6.5 + 7.5*speed))
	if speed > 0.02:
		_phase += delta * (6.5 + 7.5 * speed)

	var amp: float = min(speed, 1.0) * 0.62
	var swing: float = sin(_phase) * amp

	# Leg swing (JS direct port)
	if legs.size() >= 2:
		legs[0].rotation.x = swing
		legs[1].rotation.x = -swing
		var knee0: Node3D = legs[0].get_meta("knee")
		var knee1: Node3D = legs[1].get_meta("knee")
		knee0.rotation.x = max(0.0, -sin(_phase)) * amp * 1.1
		knee1.rotation.x = max(0.0, sin(_phase)) * amp * 1.1

	# Arm swing (JS: armSwing = swing * 0.75)
	var arm_swing: float = swing * 0.75
	if _attack_timer <= 0.0 and arms.size() >= 2:
		arms[0].rotation.x = -arm_swing
		arms[1].rotation.x = arm_swing
		arms[0].rotation.z = 0.1
		arms[1].rotation.z = -0.1
		var e0: Node3D = arms[0].get_meta("elbow")
		var e1: Node3D = arms[1].get_meta("elbow")
		e0.rotation.x = -0.25 - max(0.0, arm_swing) * 0.6
		e1.rotation.x = -0.25 - max(0.0, -arm_swing) * 0.6

	# Attack envelope (JS: wind-up then snap)
	if _attack_timer > 0.0:
		_attack_timer -= delta
		var k: float = 1.0 - max(_attack_timer, 0.0) / 0.38  # 0→1
		var snap: float
		if k < 0.35:
			snap = -1.0 - k * 2.2
		else:
			snap = _lerp(-1.8, 0.4, (k - 0.35) / 0.65)

		if arms.size() >= 2:
			if _attack_style == "bolt":
				arms[0].rotation.x = snap * 0.8
				arms[1].rotation.x = snap
				arms[1].get_meta("elbow").rotation.x = -0.1
			else:
				arms[1].rotation.x = snap
				arms[1].rotation.z = -0.35
				arms[1].get_meta("elbow").rotation.x = -0.15

	# Crouch / breathe (JS: body.position.y lerp toward crouchY, spine.rotation.x lerp)
	var crouch_y: float = -0.17 if crouch else 0.0
	body.position.y += (crouch_y - body.position.y) * min(1.0, delta * 10.0)
	var lean: float = 0.24 if crouch else 0.0
	spine.rotation.x += (lean - spine.rotation.x) * min(1.0, delta * 10.0)

	# Idle breathe (JS: torso.scale.y = 1 + sin(t*2.1)*0.012)
	torso.scale.y = 1.0 + sin(_t * 2.1) * 0.012

	# Beast tail sway (JS: tailSlot.rotation.y = sin(t*1.7)*0.25 + swing*0.3)
	if tail_slot.get_child_count() > 0:
		tail_slot.rotation.y = sin(_t * 1.7) * 0.25 + swing * 0.3

	# ---- Vanguard per-origin animations ----
	if _archetype_class == "warrior":
		# Arcane Aegis (aetherborn): slow shield rotation / bob
		if _origin_id == "aetherborn" and _aegis_shield != null:
			_aegis_shield.rotation.z = sin(_t * 0.8) * 0.08
			_aegis_shield.rotation.y = sin(_t * 0.5) * 0.05

		# Pack-Leader (miststalker): wisp orbits head
		if _origin_id == "miststalker" and _pack_wisp != null:
			_wisp_angle += delta * 1.4  # orbit speed rad/s
			var orbit_r: float = 0.22
			_pack_wisp.position = Vector3(
				cos(_wisp_angle) * orbit_r,
				0.12 + sin(_t * 2.2) * 0.04,   # gentle up-down float
				sin(_wisp_angle) * orbit_r
			)

	# ---- Strategist per-origin animations (mage only) ----
	if _archetype_class == "mage":
		# Chrono-Weaver (aetherborn): gentle dome rotation to reinforce the time-wobble feel
		if _origin_id == "aetherborn" and _chrono_field != null:
			_chrono_field.rotation.y = sin(_t * 0.35) * 0.06
			# Pulse the ring alpha via emission scale — subtle breathing effect
			if _chrono_decal != null:
				var ring_pulse: float = 0.8 + 0.2 * sin(_t * 2.0)
				(_chrono_decal.material_override as StandardMaterial3D).emission_energy_multiplier = ring_pulse * 0.8

		# Thermite-Sage (ironblooded): ring flickers — modulate emission to simulate heat shimmer
		if _origin_id == "ironblooded" and _thermite_decal != null:
			var flicker: float = 0.85 + 0.15 * sin(_t * 6.3 + 0.7)
			(_thermite_decal.material_override as StandardMaterial3D).emission_energy_multiplier = flicker * 1.2

		# Blood-Shaman (miststalker): siphon ring slow rotation
		if _origin_id == "miststalker" and _shaman_decal != null:
			_shaman_decal.rotation.y = _t * 0.6   # slow clockwise spin

	# ---- Aetherborn: traveling vein pulse (flowing aether visual) ----
	# Only animate when aetherborn and veins are visible (arcaneMod > 0.06).
	if _origin_id == "aetherborn" and veins.size() > 0 and veins[0].visible:
		# Ensure each vein has its own material instance for independent modulation.
		# We detect this by checking if the override is still the shared vein_mat.
		for i in range(veins.size()):
			if veins[i].material_override == vein_mat:
				veins[i].material_override = vein_mat.duplicate() as StandardMaterial3D

		var base_bright: float = vein_mat.albedo_color.v  # luminance from shared reference
		for i in range(veins.size()):
			var pulse: float = 0.6 + 0.4 * sin(_t * 3.0 + float(i) * 0.9)
			var pulsed: Color = accent * (base_bright * pulse)
			var m := veins[i].material_override as StandardMaterial3D
			m.albedo_color = pulsed
			m.emission = pulsed
