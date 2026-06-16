## autotest_strategist.gd — visual acceptance test for Strategist (mage) per-Origin presence VFX.
## Run via: godot --path godot -- --autotest=res://tests/autotest_strategist.gd
## Builds the rig THREE times (mage × aetherborn / ironblooded / miststalker),
## advances frames so particles warm up, screenshots each to test_out/:
##   strategist_chrono.png   (aetherborn mage  — Chrono-Weaver dome + teal ring)
##   strategist_thermite.png (ironblooded mage  — Thermite-Sage embers + orange ring)
##   strategist_shaman.png   (miststalker mage  — Blood-Shaman siphon ring + heal aura)
##
## NOTE: the focus orb (task 3.1) is also visible in all three shots since it is
## always present for mage — the strategist VFX layers ON TOP of it.
##
## NOTE: The Chrono dome is a screen-space refraction shader. It needs SOME background
## content to visually refract. The stage has a coloured WorldEnvironment + a lit
## floor mesh, so the dome refraction is subtly visible; on a plain solid-colour
## empty background it would read mainly as the teal tint + alpha blend.
extends Node

var CASES: Array = [
	{
		"name":      "strategist_chrono",
		"origin_id": "aetherborn",
		"label":     "Chrono-Weaver",
	},
	{
		"name":      "strategist_thermite",
		"origin_id": "ironblooded",
		"label":     "Thermite-Sage",
	},
	{
		"name":      "strategist_shaman",
		"origin_id": "miststalker",
		"label":     "Blood-Shaman",
	},
]

var _rig: CharacterRig = null
var _results: Array    = []
var _cam: Camera3D     = null

func _ready() -> void:
	_run_tests.call_deferred()

func _run_tests() -> void:
	# (a) Remove placeholder main scene
	if get_tree().current_scene != null:
		get_tree().current_scene.queue_free()
	await get_tree().process_frame

	# (b) Build stage lighting + camera
	_build_stage()

	# (c) Run each case
	for case_def in CASES:
		var origin_id: String = case_def["origin_id"]
		var case_name: String = case_def["name"]
		var label: String     = case_def["label"]
		print("[autotest_strategist] starting case: ", case_name, " (", label, ")")

		# Fresh rig per case
		if _rig != null:
			_rig.queue_free()
			await get_tree().process_frame
		_rig = CharacterRig.new()
		get_tree().root.add_child(_rig)
		_rig.position = Vector3(0.0, 0.0, 0.0)

		var origin:    Dictionary = OriginsData.get_origin(origin_id)
		var phenotype: Dictionary = PhenotypeData.default_phenotype()

		# Apply phenotype then mage archetype
		_rig.apply_phenotype(phenotype, origin)
		_rig.apply_archetype("mage")

		# Advance several frames: particles need a few ticks to emit, shader needs a frame to compile
		for _i in range(10):
			await get_tree().process_frame

		var out_path: String = "res://test_out/" + case_name + ".png"
		await Debug.screenshot(out_path)

		# Basic size check via FileAccess
		var fa := FileAccess.open(out_path, FileAccess.READ)
		var file_bytes: int = 0
		if fa != null:
			file_bytes = fa.get_length()
			fa.close()

		var ok: bool = file_bytes > 4096  # >4 KB means non-blank rendered image
		_results.append({
			"case":       case_name,
			"origin":     origin_id,
			"label":      label,
			"class_id":   "mage",
			"screenshot": out_path,
			"bytes":      file_bytes,
			"ok":         ok,
		})
		print("[autotest_strategist] %s → %d bytes, ok=%s" % [case_name, file_bytes, str(ok)])

	# (d) Write results JSON and quit
	Debug.write_json("res://test_out/strategist_results.json", {"cases": _results, "done": true})
	print("[autotest_strategist] all cases complete, quitting")
	get_tree().quit(0)

func _build_stage() -> void:
	# WorldEnvironment: dark-teal night sky with atmospheric ambient
	var we  := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode      = Environment.BG_COLOR
	env.background_color     = Color("#0c1622")   # dark navy — gives the refraction dome
	                                               # some background content to distort
	env.tonemap_mode         = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure     = 1.15
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color  = Color("#bfe8ff")
	env.ambient_light_energy = 0.35
	we.environment = env
	get_tree().root.add_child(we)

	# Key light: front-slightly-left
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, 20.0, 0.0)
	sun.light_energy     = 1.2
	sun.light_color      = Color("#fff4e0")
	sun.shadow_enabled   = true
	get_tree().root.add_child(sun)

	# Soft fill
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, -150.0, 0.0)
	fill.light_energy     = 0.3
	fill.light_color      = Color("#bfe8ff")
	fill.shadow_enabled   = false
	get_tree().root.add_child(fill)

	# Ground plane — gives the Chrono dome something to refract
	var ground := MeshInstance3D.new()
	var gm     := PlaneMesh.new()
	gm.size    = Vector2(12.0, 12.0)
	ground.mesh = gm
	ground.material_override = ToonMaterials.toon_mat(Color("#1a2030"))
	get_tree().root.add_child(ground)

	# Camera: full-body framing, slightly low-angle so ground ring + dome are both visible
	_cam = Camera3D.new()
	_cam.position = Vector3(0.0, 1.30, 3.0)
	_cam.look_at_from_position(_cam.position, Vector3(0.0, 0.95, 0.0), Vector3.UP)
	get_tree().root.add_child(_cam)
