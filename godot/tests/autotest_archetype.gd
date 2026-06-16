## autotest_archetype.gd — visual acceptance test for per-class silhouette differentiation.
## Run via: godot --path godot -- --autotest=res://tests/autotest_archetype.gd
## Builds the rig THREE times (warrior/mage/thief) with the same origin + default phenotype,
## screenshots each, writes rig_arch_*.png to godot/test_out/ for side-by-side comparison.
extends Node

# Three archetypes, same origin + default phenotype — only archetype differs.
var CASES: Array = [
	{
		"name":     "vanguard",
		"class_id": "warrior",
		"origin_id": "aetherborn",
	},
	{
		"name":     "strategist",
		"class_id": "mage",
		"origin_id": "aetherborn",
	},
	{
		"name":     "duelist",
		"class_id": "thief",
		"origin_id": "aetherborn",
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

	# (b) Build stage
	_build_stage()

	# (c) Run each case
	for case_def in CASES:
		var class_id:  String = case_def["class_id"]
		var origin_id: String = case_def["origin_id"]
		var case_name: String = "rig_arch_" + case_def["name"]

		# Fresh rig per case so proportions are never blended across archetypes
		if _rig != null:
			_rig.queue_free()
			await get_tree().process_frame
		_rig = CharacterRig.new()
		get_tree().root.add_child(_rig)
		_rig.position = Vector3(0.0, 0.0, 0.0)

		var origin:    Dictionary = OriginsData.get_origin(origin_id)
		var phenotype: Dictionary = PhenotypeData.default_phenotype()

		# Apply phenotype first, then archetype (order-independence is tested by the helper)
		_rig.apply_phenotype(phenotype, origin)
		_rig.apply_archetype(class_id)

		# Wait for the scene tree to settle + 3 render frames
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame

		var out_path: String = "res://test_out/" + case_name + ".png"
		await Debug.screenshot(out_path)
		_results.append({
			"case":       case_name,
			"class_id":   class_id,
			"origin":     origin_id,
			"screenshot": out_path,
			"ok":         true,
		})
		print("[autotest_archetype] case done: ", case_name)

	# (d) Write results JSON and quit
	Debug.write_json("res://test_out/archetype_results.json", {"cases": _results, "done": true})
	print("[autotest_archetype] all cases complete, quitting")
	get_tree().quit(0)

func _build_stage() -> void:
	# WorldEnvironment: same settings as autotest_rig for consistency
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

	# Key light
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
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

	# Camera: slightly wider view to capture full body including orb
	_cam = Camera3D.new()
	_cam.position = Vector3(0.0, 1.25, 2.8)
	_cam.look_at_from_position(_cam.position, Vector3(0.0, 0.95, 0.0), Vector3.UP)
	get_tree().root.add_child(_cam)
