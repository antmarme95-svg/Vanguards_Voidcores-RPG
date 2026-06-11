# Headless smoke test: godot --headless --path godot --script res://tests/test_hello.gd
extends SceneTree

func _init() -> void:
	print("BORISAWA_GODOT_OK ", Engine.get_version_info()["string"])
	quit(0)
