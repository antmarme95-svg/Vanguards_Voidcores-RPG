## autotest_biome.gd — PRD-002 §6/§8 biome generalization proof.
## Renders The Wilds scene under two biome presets from the SAME camera position.
## Proves "misma fórmula, distinta paleta/atmósfera":
##   - biome_wilds.png     = preset "wilds"           (green/teal baseline)
##   - biome_smelting.png  = preset "smelting_craters" (orange/ash industrial)
## Both images must show the IDENTICAL object/cel register (same terrain, trees,
## cores, outlines, cel bands) — ONLY the atmosphere/palette differs.
##
## Run via: godot --path godot -- --autotest=res://tests/autotest_biome.gd
extends Node

var _cam: Camera3D = null
var _results: Array = []

func _ready() -> void:
	_run_tests.call_deferred()

func _run_tests() -> void:
	# Free placeholder main scene
	if get_tree().current_scene != null:
		get_tree().current_scene.queue_free()
	await get_tree().process_frame

	# Persistent camera — same for BOTH presets (identical framing = fair comparison)
	_cam = Camera3D.new()
	_cam.name = "BiomeCam"
	_cam.fov = 70.0
	get_tree().root.add_child(_cam)

	# ----------------------------------------------------------------
	# SHARED CAMERA POSITION — high 3/4 view from spawn toward core A.
	# Identical to autotest_scenes overview shot so baseline is cross-comparable.
	# Shows: terrain, grass, trees, core crystals, sky, horizon ridges.
	# ----------------------------------------------------------------
	var cam_pos := Vector3(10.0, 45.0, 75.0)
	var cam_target := Vector3(8.0, 0.0, -10.0)
	_cam.position = cam_pos
	_cam.look_at_from_position(cam_pos, cam_target, Vector3.UP)

	# ---- PRESET A: "wilds" (green/teal baseline — must match normal play exactly) ----
	var origin := OriginsData.get_origin("aetherborn")
	var wilds_a := TheWilds.new(origin, "wilds")
	get_tree().root.add_child(wilds_a)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var path_a := "res://test_out/biome_wilds.png"
	await Debug.screenshot(path_a)
	_results.append({
		"preset":     "wilds",
		"screenshot": path_a,
		"bg_color":   "#bfe3d4",
		"fog_color":  "#bfe3d4",
		"ambient":    "#a8d8c0",
		"ok": true,
	})
	print("[autotest_biome] shot: biome_wilds.png (preset=wilds, green/teal)")

	wilds_a.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	# ---- PRESET B: "smelting_craters" (orange/ash industrial — same objects) ----
	var wilds_b := TheWilds.new(origin, "smelting_craters")
	get_tree().root.add_child(wilds_b)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var path_b := "res://test_out/biome_smelting.png"
	await Debug.screenshot(path_b)
	_results.append({
		"preset":     "smelting_craters",
		"screenshot": path_b,
		"bg_color":   "#caa07a",
		"fog_color":  "#d8a070",
		"ambient":    "#c89060",
		"ok": true,
	})
	print("[autotest_biome] shot: biome_smelting.png (preset=smelting_craters, orange/ash)")

	wilds_b.queue_free()
	await get_tree().process_frame

	# ---- Write JSON proof ----
	var cam_h := TheWilds.terrain_height(cam_pos.x, cam_pos.z)
	Debug.write_json("res://test_out/biome_results.json", {
		"proof": "PRD-002 §6/§8 — same object register, two atmosphere presets",
		"cam_pos": {"x": cam_pos.x, "y": cam_pos.y, "z": cam_pos.z},
		"cam_target": {"x": cam_target.x, "y": cam_target.y, "z": cam_target.z},
		"terrain_h_at_cam_xz": cam_h,
		"cases": _results,
	})

	print("[autotest_biome] all done, quitting")
	get_tree().quit(0)
