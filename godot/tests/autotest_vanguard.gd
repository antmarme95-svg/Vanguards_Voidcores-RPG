## autotest_vanguard.gd — visual acceptance test for Vanguard (warrior) per-Origin presence VFX.
## Run via: godot --path godot -- --autotest=res://tests/autotest_vanguard.gd
## Builds the rig THREE times (warrior × aetherborn / ironblooded / miststalker),
## advances frames so particles warm up, screenshots each to test_out/:
##   vanguard_aegis.png        (aetherborn warrior  — Arcane Aegis shield)
##   vanguard_juggernaut.png   (ironblooded warrior  — steam thruster jets)
##   vanguard_packleader.png   (miststalker warrior  — wisp orb + stealth ring)
extends Node

var CASES: Array = [
	{
		"name":      "vanguard_aegis",
		"origin_id": "aetherborn",
	},
	{
		"name":      "vanguard_juggernaut",
		"origin_id": "ironblooded",
	},
	{
		"name":      "vanguard_packleader",
		"origin_id": "miststalker",
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

		# Fresh rig per case
		if _rig != null:
			_rig.queue_free()
			await get_tree().process_frame
		_rig = CharacterRig.new()
		get_tree().root.add_child(_rig)
		_rig.position = Vector3(0.0, 0.0, 0.0)

		var origin:    Dictionary = OriginsData.get_origin(origin_id)
		var phenotype: Dictionary = PhenotypeData.default_phenotype()

		# Apply phenotype then warrior archetype
		_rig.apply_phenotype(phenotype, origin)
		_rig.apply_archetype("warrior")

		# Advance several frames: particles need a few ticks to emit
		for _i in range(8):
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
			"class_id":   "warrior",
			"screenshot": out_path,
			"bytes":      file_bytes,
			"ok":         ok,
		})
		print("[autotest_vanguard] %s → %d bytes, ok=%s" % [case_name, file_bytes, str(ok)])

	# (d) Write results JSON and quit
	Debug.write_json("res://test_out/vanguard_results.json", {"cases": _results, "done": true})
	print("[autotest_vanguard] all cases complete, quitting")
	get_tree().quit(0)

func _build_stage() -> void:
	var we  := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode  = Environment.BG_COLOR
	env.background_color = Color("#0c1622")
	env.tonemap_mode     = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.15
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color  = Color("#bfe8ff")
	env.ambient_light_energy = 0.35
	we.environment = env
	get_tree().root.add_child(we)

	# Key light: front-slightly-left so the shield reads clearly
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, 20.0, 0.0)
	sun.light_energy     = 1.2
	sun.light_color      = Color("#fff4e0")
	sun.shadow_enabled   = true
	get_tree().root.add_child(sun)

	# Soft fill from opposite side
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, -150.0, 0.0)
	fill.light_energy     = 0.3
	fill.light_color      = Color("#bfe8ff")
	fill.shadow_enabled   = false
	get_tree().root.add_child(fill)

	# Camera: full-body framing, slightly left of centre to catch left-arm shield
	_cam = Camera3D.new()
	_cam.position = Vector3(-0.15, 1.20, 2.8)
	_cam.look_at_from_position(_cam.position, Vector3(0.0, 0.90, 0.0), Vector3.UP)
	get_tree().root.add_child(_cam)
