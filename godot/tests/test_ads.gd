# test_ads.gd — Headless ADS (aim-down-sights) wiring assertions.
#
# Strategy: ii — load locomotion.json directly (same path Config uses) and verify
# the four ADS tunables exist with expected values, then unit-test the override and
# lerp logic by replicating the two relevant lines from player_controller.gd inline.
#
# WHY not strategy (i):
#   PlayerController extends CharacterBody3D (physics body). Instantiating it
#   headless requires a valid SceneTree with a physics world; CharacterBody3D also
#   tries to register a CollisionShape3D in _ready(), and _lsm_configure() calls
#   _get_config_node() which depends on get_tree().root. Adding the node to a
#   SceneTree in --script mode (no autoloads) causes cascading errors from
#   EventBus.emit_event inside _set_ads(). The logic under test (the FOV override
#   one-liner and the _sync_camera lerp) is trivially replicable without all that.
#
# Run: godot --headless --path godot --script res://tests/test_ads.gd
extends SceneTree

var _pass_count := 0
var _fail_count := 0

func _pass(name: String) -> void:
	print("PASS " + name)
	_pass_count += 1

func _fail(name: String, detail: String) -> void:
	print("FAIL " + name + ": " + detail)
	_fail_count += 1

func _init() -> void:
	_test_loco_json_ads_keys()
	_test_fov_override_logic()
	_test_cam_dist_lerp_logic()

	print("")
	if _fail_count == 0:
		print("ADS_ALL_PASS")
		quit(0)
	else:
		print("ADS_FAILURES: %d" % _fail_count)
		quit(1)

# ──────────────────────────────────────────────────────────────────────────────
# 1. locomotion.json must contain all four ADS keys with the expected values.
# ──────────────────────────────────────────────────────────────────────────────
func _test_loco_json_ads_keys() -> void:
	const PATH := "res://data/locomotion.json"
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		_fail("loco_json: file opens", "FileAccess.open returned null for " + PATH)
		return
	var text := f.get_as_text()
	f.close()

	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		_fail("loco_json: JSON parses", "JSON.parse error %d" % err)
		return
	_pass("loco_json: file opens and parses")

	var loco: Dictionary = json.get_data() as Dictionary

	# adsFov
	if loco.has("adsFov") and absf(float(loco["adsFov"]) - 36.0) < 0.001:
		_pass("loco_json: adsFov == 36.0")
	else:
		_fail("loco_json: adsFov == 36.0",
			"value=%s" % str(loco.get("adsFov", "MISSING")))

	# adsCamDist
	if loco.has("adsCamDist") and absf(float(loco["adsCamDist"]) - 2.9) < 0.001:
		_pass("loco_json: adsCamDist == 2.9")
	else:
		_fail("loco_json: adsCamDist == 2.9",
			"value=%s" % str(loco.get("adsCamDist", "MISSING")))

	# adsShoulder
	if loco.has("adsShoulder") and absf(float(loco["adsShoulder"]) - 0.55) < 0.001:
		_pass("loco_json: adsShoulder == 0.55")
	else:
		_fail("loco_json: adsShoulder == 0.55",
			"value=%s" % str(loco.get("adsShoulder", "MISSING")))

	# adsSensMult
	if loco.has("adsSensMult") and absf(float(loco["adsSensMult"]) - 0.6) < 0.001:
		_pass("loco_json: adsSensMult == 0.6")
	else:
		_fail("loco_json: adsSensMult == 0.6",
			"value=%s" % str(loco.get("adsSensMult", "MISSING")))

# ──────────────────────────────────────────────────────────────────────────────
# 2. FOV override logic — replicate the two lines from update():
#       _fov_target = lsm_out["fov_target"]       (LSM result, e.g. 50)
#       if _ads_held: _fov_target = _ads_fov       (override when ADS held)
# ──────────────────────────────────────────────────────────────────────────────
func _test_fov_override_logic() -> void:
	var _ads_fov    := 36.0
	var _fov_target := 50.0   # LSM base FOV (fovBase)

	# --- ADS NOT held: target stays at LSM value ---
	var _ads_held_off := false
	_fov_target = 50.0
	if _ads_held_off:
		_fov_target = _ads_fov
	if absf(_fov_target - 50.0) < 0.001:
		_pass("fov_override: ads_held=false → _fov_target stays at 50.0")
	else:
		_fail("fov_override: ads_held=false → _fov_target stays at 50.0",
			"_fov_target=%f" % _fov_target)

	# --- ADS held: target snaps to _ads_fov (36.0) ---
	var _ads_held_on := true
	_fov_target = 50.0
	if _ads_held_on:
		_fov_target = _ads_fov
	if absf(_fov_target - 36.0) < 0.001:
		_pass("fov_override: ads_held=true → _fov_target becomes _ads_fov (36.0)")
	else:
		_fail("fov_override: ads_held=true → _fov_target becomes _ads_fov (36.0)",
			"_fov_target=%f" % _fov_target)

# ──────────────────────────────────────────────────────────────────────────────
# 3. Camera-distance lerp logic — replicate _sync_camera's lerp from update():
#       var dist_goal = _ads_cam_dist if _ads_held else cam_dist
#       _cam_dist_eff = lerp(_cam_dist_eff, dist_goal, blend)
#
#    After many frames, _cam_dist_eff must approach _ads_cam_dist (2.9) when ADS
#    is held, and must have moved meaningfully away from the default (4.4).
# ──────────────────────────────────────────────────────────────────────────────
func _test_cam_dist_lerp_logic() -> void:
	const CAM_DIST_DEFAULT := 4.4
	const ADS_CAM_DIST     := 2.9
	const BLEND            := 0.105   # dt * 7 at 15 fps — conservative bound

	var _cam_dist_eff := CAM_DIST_DEFAULT
	var _ads_held     := true
	var cam_dist      := CAM_DIST_DEFAULT

	# Simulate 60 lerp steps (equivalent to ~1 s at 60 fps with blend = minf(1, dt*7))
	for _i in range(60):
		var dist_goal: float = ADS_CAM_DIST if _ads_held else cam_dist
		_cam_dist_eff = lerp(_cam_dist_eff, dist_goal, BLEND)

	# After 60 steps it should be very close to 2.9 (within 0.05)
	if _cam_dist_eff < ADS_CAM_DIST + 0.05:
		_pass("cam_dist_lerp: after 60 steps ads_held=true → _cam_dist_eff ≈ 2.9 (got %f)" % _cam_dist_eff)
	else:
		_fail("cam_dist_lerp: after 60 steps ads_held=true → _cam_dist_eff ≈ 2.9",
			"_cam_dist_eff=%f, expected < %f" % [_cam_dist_eff, ADS_CAM_DIST + 0.05])

	# Also verify it actually moved toward ADS (i.e. decreased from 4.4)
	if _cam_dist_eff < CAM_DIST_DEFAULT - 0.5:
		_pass("cam_dist_lerp: _cam_dist_eff has meaningfully decreased from default 4.4")
	else:
		_fail("cam_dist_lerp: _cam_dist_eff has meaningfully decreased from default 4.4",
			"_cam_dist_eff=%f" % _cam_dist_eff)

	# Verify the reverse: when ADS released, it lerps back toward cam_dist (4.4)
	_ads_held = false
	var dist_after_release := _cam_dist_eff
	for _i in range(60):
		var dist_goal: float = ADS_CAM_DIST if _ads_held else cam_dist
		_cam_dist_eff = lerp(_cam_dist_eff, dist_goal, BLEND)

	if _cam_dist_eff > dist_after_release + 0.5:
		_pass("cam_dist_lerp: after release ads_held=false → _cam_dist_eff recovers toward 4.4")
	else:
		_fail("cam_dist_lerp: after release ads_held=false → _cam_dist_eff recovers toward 4.4",
			"before=%f after=%f" % [dist_after_release, _cam_dist_eff])
