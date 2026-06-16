## autotest_atmos.gd — Sprint 4 Gate: atmosphere verification render.
## Run via: godot --path godot -- --autotest=res://tests/autotest_atmos.gd
##
## Shots:
##   atmos_core_eyelevel.png — 1.7 m eye-height, 14 m from Core A looking at core.
##                             Verifies local red fog reads at eye level + core stays
##                             sharp/vivid red (PRD-002 §3 color language).
##   atmos_vista.png         — Low 3 m camera looking across the Wilds toward horizon.
##                             Verifies atmospheric perspective, islands veiled by fog,
##                             "feels massive" (PRD-002 §8).
##
## FPS measurement: samples ~3 s of real time at each camera position (eye-level and
## vista) using the same approach as autotest_scenes.gd — polls every process frame,
## averages the second half of samples to skip warm-up frames.
##
## Writes: test_out/atmos_results.json
extends Node

var _cam: Camera3D = null

func _ready() -> void:
	_run_tests.call_deferred()

func _run_tests() -> void:
	# Free main scene placeholder
	if get_tree().current_scene != null:
		get_tree().current_scene.queue_free()
	await get_tree().process_frame

	# Persistent camera
	_cam = Camera3D.new()
	_cam.name = "AtmosCam"
	# Give the camera a practical FOV that matches a player POV
	_cam.fov = 70.0
	get_tree().root.add_child(_cam)

	# Instantiate TheWilds — uses aetherborn origin for determinism
	var origin = OriginsData.get_origin("aetherborn")
	var wilds = TheWilds.new(origin)
	get_tree().root.add_child(wilds)

	# Wait for _ready to fully run
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	# ----------------------------------------------------------------
	# SHOT 1 — PLAYER-EYE-LEVEL NEAR CORE A
	# Core A is at world (8, ~0.7, -42).
	# Camera placed 14 m north of core at eye height (terrain_h + 1.7 m).
	# Looking directly at the core crystal cluster (~1.5 m above terrain).
	# PURPOSE: verify local red fog haze reads at eye level;
	#          core stays sharp + vivid red (danger by color, not blurred/grey).
	# ----------------------------------------------------------------
	var ca_h: float = TheWilds.terrain_height(8.0, -42.0)   # ~0.7
	var cam_pos_1 = Vector3(8.0, ca_h + 1.7, -42.0 + 14.0)  # 14 m north, 1.7 m high
	var look_at_1 = Vector3(8.0, ca_h + 1.5, -42.0)         # core crystal height
	_place_cam(cam_pos_1, look_at_1)

	# ---- FPS probe 1: eye-level near Core A (~3 real seconds) ----
	var fps_eyelevel: float = await _sample_fps("eyelevel")
	print("[autotest_atmos] eye-level fps = ", fps_eyelevel)
	if fps_eyelevel < 60.0:
		push_warning("[autotest_atmos] eye-level FPS below target: %f < 60" % fps_eyelevel)

	await _await_and_shot("atmos_core_eyelevel")

	# ----------------------------------------------------------------
	# SHOT 2 — WIDE ATMOSPHERIC VISTA
	# Camera at low angle (3 m height) near spawn, looking south toward core A
	# and horizon.  Floating islands appear in mid-distance at 135-185 m.
	# Camera slightly elevated at (−10, 3.0, 50) looking toward (0, 5, −60).
	# This framing shows: near crisp terrain → mid-range haze → distant islands
	# veiled by volumetric fog → sky dome. PURPOSE: "feels massive" (PRD-002 §8).
	# ----------------------------------------------------------------
	var cam_pos_2 = Vector3(-10.0, 3.0, 50.0)
	var look_at_2 = Vector3(0.0, 5.0, -60.0)
	_place_cam(cam_pos_2, look_at_2)

	# ---- FPS probe 2: wide vista (~3 real seconds) ----
	var fps_vista: float = await _sample_fps("vista")
	print("[autotest_atmos] vista fps = ", fps_vista)
	if fps_vista < 60.0:
		push_warning("[autotest_atmos] vista FPS below target: %f < 60" % fps_vista)

	await _await_and_shot("atmos_vista")

	# Write results JSON
	Debug.write_json("res://test_out/atmos_results.json", {
		"shots": [
			{
				"name": "atmos_core_eyelevel",
				"path": "res://test_out/atmos_core_eyelevel.png",
				"cam_pos": {"x": cam_pos_1.x, "y": cam_pos_1.y, "z": cam_pos_1.z},
				"look_at": {"x": look_at_1.x,  "y": look_at_1.y,  "z": look_at_1.z},
				"fps": fps_eyelevel,
				"ok": true,
			},
			{
				"name": "atmos_vista",
				"path": "res://test_out/atmos_vista.png",
				"cam_pos": {"x": cam_pos_2.x, "y": cam_pos_2.y, "z": cam_pos_2.z},
				"look_at": {"x": look_at_2.x,  "y": look_at_2.y,  "z": look_at_2.z},
				"fps": fps_vista,
				"ok": true,
			},
		],
		"core_a_terrain_h": ca_h,
		"fps_eyelevel": fps_eyelevel,
		"fps_vista": fps_vista,
	})

	wilds.queue_free()
	await get_tree().process_frame

	print("[autotest_atmos] all done, quitting")
	get_tree().quit(0)

# ================================================================
func _place_cam(pos: Vector3, target: Vector3) -> void:
	_cam.position = pos
	_cam.look_at_from_position(pos, target, Vector3.UP)

func _await_and_shot(case_name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var out_path = "res://test_out/" + case_name + ".png"
	await Debug.screenshot(out_path)
	print("[autotest_atmos] shot: ", case_name)

# ---- FPS sampler: polls ~3 real seconds, returns avg of second half (skip warm-up) ----
func _sample_fps(label: String) -> float:
	var fps_start_ms: int = Time.get_ticks_msec()
	var fps_samples: Array = []
	while Time.get_ticks_msec() - fps_start_ms < 3000:
		await get_tree().process_frame
		fps_samples.append(Performance.get_monitor(Performance.TIME_FPS))
	var sample_count: int = fps_samples.size()
	var half_start: int = sample_count / 2
	var fps_sum: float = 0.0
	var fps_n: int = 0
	for si in range(half_start, sample_count):
		fps_sum += fps_samples[si]
		fps_n += 1
	var avg: float = fps_sum / float(max(fps_n, 1))
	print("[autotest_atmos] fps_sample[", label, "] samples=", sample_count, " avg=", avg)
	return avg
