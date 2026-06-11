# Debug / test harness autoload. Ports the web build's URL-param conventions:
#   godot --path godot -- --origin=aetherborn --cls=mage --name=X --skip=wilds
#   godot --path godot -- --screenshot-and-quit          (P0 smoke test)
#   godot --path godot -- --autotest=res://tests/foo.gd  (scripted run; writes
#                                                         JSON + PNGs to test_out/)
# F12 in any run saves a screenshot to test_out/.
extends Node

var args: Dictionary = {}

func _ready() -> void:
	for raw: String in OS.get_cmdline_user_args():
		var trimmed := raw.lstrip("-")
		var eq := trimmed.find("=")
		if eq == -1:
			args[trimmed] = true
		else:
			args[trimmed.substr(0, eq)] = trimmed.substr(eq + 1)

	if args.has("screenshot-and-quit"):
		_smoke_test()
	elif args.has("autotest"):
		_run_autotest(String(args["autotest"]))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F12:
		screenshot("res://test_out/manual_%d.png" % Time.get_ticks_msec())

func screenshot(res_path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var abs_path := ProjectSettings.globalize_path(res_path)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	img.save_png(abs_path)
	print("[Debug] screenshot -> ", abs_path)

func write_json(res_path: String, data: Dictionary) -> void:
	var abs_path := ProjectSettings.globalize_path(res_path)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	print("[Debug] json -> ", abs_path)

func _smoke_test() -> void:
	# Wait a few frames so the main scene has rendered something.
	for i in range(8):
		await get_tree().process_frame
	await screenshot("res://test_out/boot.png")
	get_tree().quit(0)

func _run_autotest(script_path: String) -> void:
	var script: GDScript = load(script_path)
	if script == null:
		push_error("[Debug] autotest script not found: " + script_path)
		get_tree().quit(1)
		return
	var node: Node = script.new()
	add_child(node)  # the test node drives the game and quits when done
