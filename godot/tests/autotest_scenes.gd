## autotest_scenes.gd — scripted scene render test.
## Run via: godot --path godot -- --autotest=res://tests/autotest_scenes.gd
## Renders: wilds_overview, wilds_core_a, wilds_core_b, wilds_ruins_0/1/2,
##          office_aetherborn/ironblooded/miststalker, city_exit.
## Writes test_out/scenes_results.json with terrain_samples, ruins_zones, cases, wilds_fps.
extends Node

var _results: Array = []
var _cam: Camera3D = null
var _current_scene: Node = null
var _wilds_fps: float = 0.0

func _ready() -> void:
	_run_tests.call_deferred()

func _run_tests() -> void:
	# Free the main scene placeholder
	if get_tree().current_scene != null:
		get_tree().current_scene.queue_free()
	await get_tree().process_frame

	# Add persistent camera to root
	_cam = Camera3D.new()
	_cam.name = "AutotestCam"
	get_tree().root.add_child(_cam)

	# ---- TheWilds cases ----
	await _run_wilds_cases()

	# ---- RecruitmentOffice cases ----
	for origin_id in ["aetherborn", "ironblooded", "miststalker"]:
		await _run_office_case(origin_id)

	# ---- CityExit case ----
	await _run_city_exit_case()

	# ---- Collect terrain samples and ruins_zones for JSON ----
	var terrain_samples = []
	for coords in [[0.0, 88.0], [8.0, -42.0], [-46.0, 18.0], [30.0, 30.0], [-60.0, -60.0]]:
		terrain_samples.append({
			"x": coords[0],
			"z": coords[1],
			"h": TheWilds.terrain_height(coords[0], coords[1]),
		})

	# Build a temporary wilds instance just to read ruins_zones
	var wilds_tmp = TheWilds.new({})
	get_tree().root.add_child(wilds_tmp)
	await get_tree().process_frame
	var rz_export = []
	for rz in wilds_tmp.ruins_zones:
		rz_export.append({
			"center_x": rz["center"].x,
			"center_y": rz["center"].y,
			"center_z": rz["center"].z,
			"radius": rz["radius"],
		})
	wilds_tmp.queue_free()

	# Write final JSON
	Debug.write_json("res://test_out/scenes_results.json", {
		"terrain_samples": terrain_samples,
		"ruins_zones": rz_export,
		"cases": _results,
		"wilds_fps": _wilds_fps,
	})
	print("[autotest_scenes] all done, quitting")
	get_tree().quit(0)

# ================================================================
func _run_wilds_cases() -> void:
	var origin = OriginsData.get_origin("aetherborn")
	var wilds = TheWilds.new(origin)
	get_tree().root.add_child(wilds)
	# Wait for _ready to fully run
	await get_tree().process_frame
	await get_tree().process_frame

	# ---- FPS probe: let TheWilds (heaviest scene) run ~3 real seconds, sample FPS ----
	# Poll real time using Time.get_ticks_msec() to avoid frame-counting instability.
	var fps_start_ms = Time.get_ticks_msec()
	var fps_samples: Array = []
	_place_cam(Vector3(10.0, 45.0, 75.0), Vector3(8.0, 0.0, -10.0))
	while Time.get_ticks_msec() - fps_start_ms < 3000:
		await get_tree().process_frame
		fps_samples.append(Performance.get_monitor(Performance.TIME_FPS))
	# Average the last half of samples (ignore warm-up frames)
	var sample_count = fps_samples.size()
	var half_start = sample_count / 2
	var fps_sum = 0.0
	var fps_n = 0
	for si in range(half_start, sample_count):
		fps_sum += fps_samples[si]
		fps_n += 1
	_wilds_fps = fps_sum / float(max(fps_n, 1))
	print("[autotest_scenes] wilds_fps = ", _wilds_fps)
	if _wilds_fps < 60.0:
		push_warning("[autotest_scenes] FPS below target: " + str(_wilds_fps) + " < 60")

	# ---- wilds_overview: high 3/4 view from spawn toward core A ----
	# Spawn is at (0,~0.4,88); core A at (8,~0,-42). View from above-spawn southward.
	_place_cam(Vector3(10.0, 45.0, 75.0), Vector3(8.0, 0.0, -10.0))
	await _await_and_shot("wilds_overview")

	# ---- wilds_core_a: near core A (8, h, -42) ----
	var ca_h = TheWilds.terrain_height(8.0, -42.0)
	_place_cam(Vector3(8.0 + 14.0, ca_h + 8.0, -42.0 + 12.0), Vector3(8.0, ca_h + 1.0, -42.0))
	await _await_and_shot("wilds_core_a")

	# ---- wilds_core_b: near core B (-46, h, 18) ----
	var cb_h = TheWilds.terrain_height(-46.0, 18.0)
	_place_cam(Vector3(-46.0 + 12.0, cb_h + 8.0, 18.0 + 10.0), Vector3(-46.0, cb_h + 1.0, 18.0))
	await _await_and_shot("wilds_core_b")

	# ---- wilds_ruins_0/1/2: each ruins zone, close enough to see detail ----
	# Zone 0: (40, h, 40)
	var rz0_h = TheWilds.terrain_height(40.0, 40.0)
	_place_cam(Vector3(40.0 + 8.0, rz0_h + 5.0, 40.0 + 8.0), Vector3(40.0, rz0_h + 0.5, 40.0))
	await _await_and_shot("wilds_ruins_0")

	# Zone 1: (-55, h, -35)
	var rz1_h = TheWilds.terrain_height(-55.0, -35.0)
	_place_cam(Vector3(-55.0 + 8.0, rz1_h + 5.0, -35.0 + 8.0), Vector3(-55.0, rz1_h + 0.5, -35.0))
	await _await_and_shot("wilds_ruins_1")

	# Zone 2: (25, h, -75)
	var rz2_h = TheWilds.terrain_height(25.0, -75.0)
	_place_cam(Vector3(25.0 + 8.0, rz2_h + 5.0, -75.0 + 8.0), Vector3(25.0, rz2_h + 0.5, -75.0))
	await _await_and_shot("wilds_ruins_2")

	_free_current(wilds)

# ================================================================
func _run_office_case(origin_id: String) -> void:
	var origin = OriginsData.get_origin(origin_id)
	var office = RecruitmentOffice.new(origin)
	get_tree().root.add_child(office)
	await get_tree().process_frame
	await get_tree().process_frame

	# Camera from player spawn looking toward desk/recruiter
	# Spawn is (-1.2, 0, 2.6), desk at z=-1.6, recruiter at z=-2.75
	_place_cam(Vector3(-1.2, 1.6, 3.2), Vector3(0.0, 1.2, -1.9))
	await _await_and_shot("office_" + origin_id)

	_free_current(office)

# ================================================================
func _run_city_exit_case() -> void:
	var origin = OriginsData.get_origin("aetherborn")
	var exit_scene = CityExit.new(origin)
	get_tree().root.add_child(exit_scene)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	# Looking down corridor toward the portcullis from player spawn (z≈0)
	_place_cam(Vector3(0.0, 3.5, 6.0), Vector3(0.0, 2.0, -48.0))
	await _await_and_shot("city_exit")

	_free_current(exit_scene)

# ================================================================
func _place_cam(pos: Vector3, target: Vector3) -> void:
	_cam.position = pos
	_cam.look_at_from_position(pos, target, Vector3.UP)

func _await_and_shot(case_name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var out_path = "res://test_out/scene_" + case_name + ".png"
	await Debug.screenshot(out_path)
	_results.append({"case": case_name, "screenshot": out_path, "ok": true})
	print("[autotest_scenes] shot: ", case_name)

func _free_current(node: Node) -> void:
	node.queue_free()
	await get_tree().process_frame
