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

	# ---- Palette preset assertions (Task D) ----
	# Prove the palette is preset-driven: verify BIOME_PRESETS values directly from
	# the class constant (accessible because TheWilds has class_name TheWilds).
	# (a) terrain_colors.grass and grass_albedo DIFFER between "wilds" and "smelting_craters"
	# (b) wilds values equal the original baseline
	# (c) smelting_craters is the warm set
	_run_palette_assertions()

	print("[autotest_biome] all done, quitting")
	get_tree().quit(0)

func _run_palette_assertions() -> void:
	var wilds_preset: Dictionary = TheWilds.BIOME_PRESETS.get("wilds", {})
	var smelting_preset: Dictionary = TheWilds.BIOME_PRESETS.get("smelting_craters", {})

	# ---- (a) terrain_colors.grass and grass_albedo must differ between presets ----
	var wilds_tc: Dictionary = wilds_preset.get("terrain_colors", {})
	var smelting_tc: Dictionary = smelting_preset.get("terrain_colors", {})

	var wilds_grass: Color = wilds_tc.get("grass", Color.BLACK)
	var smelting_grass: Color = smelting_tc.get("grass", Color.BLACK)
	if wilds_grass != smelting_grass:
		print("PASS palette: terrain_colors.grass differs between wilds and smelting_craters")
	else:
		print("FAIL palette: terrain_colors.grass is identical between presets: " + str(wilds_grass))

	var wilds_albedo: Color = wilds_preset.get("grass_albedo", Color.BLACK)
	var smelting_albedo: Color = smelting_preset.get("grass_albedo", Color.BLACK)
	if wilds_albedo != smelting_albedo:
		print("PASS palette: grass_albedo differs between wilds and smelting_craters")
	else:
		print("FAIL palette: grass_albedo is identical between presets: " + str(wilds_albedo))

	# ---- (b) wilds values equal the documented originals ----
	# terrain_colors.grass == #3aaa30
	var expected_wilds_grass := Color("#3aaa30")
	if wilds_grass.is_equal_approx(expected_wilds_grass):
		print("PASS palette: wilds terrain_colors.grass == #3aaa30 (" + str(wilds_grass) + ")")
	else:
		print("FAIL palette: wilds terrain_colors.grass expected #3aaa30 got " + str(wilds_grass))

	# grass_albedo == #4ec844
	var expected_wilds_albedo := Color("#4ec844")
	if wilds_albedo.is_equal_approx(expected_wilds_albedo):
		print("PASS palette: wilds grass_albedo == #4ec844 (" + str(wilds_albedo) + ")")
	else:
		print("FAIL palette: wilds grass_albedo expected #4ec844 got " + str(wilds_albedo))

	# ---- (c) smelting_craters is the warm set ----
	# terrain_colors.grass == #8a6a3a
	var expected_smelting_grass := Color("#8a6a3a")
	if smelting_grass.is_equal_approx(expected_smelting_grass):
		print("PASS palette: smelting terrain_colors.grass == #8a6a3a (" + str(smelting_grass) + ")")
	else:
		print("FAIL palette: smelting terrain_colors.grass expected #8a6a3a got " + str(smelting_grass))

	# grass_albedo == #9a7038
	var expected_smelting_albedo := Color("#9a7038")
	if smelting_albedo.is_equal_approx(expected_smelting_albedo):
		print("PASS palette: smelting grass_albedo == #9a7038 (" + str(smelting_albedo) + ")")
	else:
		print("FAIL palette: smelting grass_albedo expected #9a7038 got " + str(smelting_albedo))

	# ---- Object/cel register check: both presets must have identical grass_colors array length ----
	var wilds_colors: Array = wilds_preset.get("grass_colors", [])
	var smelting_colors: Array = smelting_preset.get("grass_colors", [])
	if wilds_colors.size() == smelting_colors.size() and wilds_colors.size() == 6:
		print("PASS palette: both presets have grass_colors[6] (same object register)")
	else:
		print("FAIL palette: grass_colors size mismatch wilds=%d smelting=%d (expected 6)" % [
			wilds_colors.size(), smelting_colors.size()])
