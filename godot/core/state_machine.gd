# Generic finite state machine — direct port of src/core/StateMachine.js.
# States are Dictionaries with optional Callable values keyed "enter", "exit", "update".
class_name StateMachine extends RefCounted

var name: String
var ctx: Dictionary
var _states: Dictionary = {}
var current: Dictionary = {}
var current_id: String = ""
var history: Array = []

func _init(p_name: String, p_ctx: Dictionary = {}) -> void:
	name = p_name
	ctx = p_ctx

# Chainable add.
func add(id: String, state: Dictionary) -> StateMachine:
	_states[id] = state
	return self

func go(id: String, payload: Dictionary = {}) -> void:
	if id == current_id:
		return
	if not _states.has(id):
		push_error("[FSM:%s] unknown state \"%s\"" % [name, id])
		return
	var from_id: String = current_id
	# Call exit on current state if it has one.
	if current.has("exit") and current["exit"] is Callable:
		current["exit"].call(ctx, id)
	history.append(id)
	current_id = id
	current = _states[id]
	print("[FSM:%s] %s → %s" % [name, from_id if from_id != "" else "∅", id])
	# Call enter on next state if it has one.
	if current.has("enter") and current["enter"] is Callable:
		current["enter"].call(ctx, from_id, payload)

func update(delta: float) -> void:
	if current.has("update") and current["update"] is Callable:
		current["update"].call(ctx, delta)

# is() is reserved in GDScript — use is_state() instead.
func is_state(id: String) -> bool:
	return current_id == id
