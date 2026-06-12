# game_director.gd — Top-level game FSM and scene orchestrator.
# Port of src/core/GameDirector.js.
# FSM: CREATION → OFFICE → CITY_EXIT → WILDS → CHOICE → FREE_ROAM
# CREATION is a minimal stub (reads Debug args, goes to OFFICE — full UI is P5).
class_name GameDirector extends Node3D

# ---- child nodes ----
var _cam: Camera3D
var _fade_layer: ColorRect     = null
var _fade_canvas: CanvasLayer  = null

# ---- game state ----
var save: SaveState            = null
var fsm: StateMachine          = null
var _timers: Array             = []

# ---- scene wrappers ----
var scene: Node3D              = null
var enemies: Array             = []

# ---- gameplay systems ----
var stats: Stats               = null
var passives: Passives         = null
var controller: PlayerController = null
var rig: CharacterRig          = null
var quest_tracker: QuestTracker = null

# ---- visited states (for autotest reporting) ----
var fsm_states_visited: Array  = []

# ================================================================
func _ready() -> void:
	# Camera
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.near = 0.1
	_cam.far  = 700.0
	add_child(_cam)

	# Fade layer (CanvasLayer so it renders on top)
	_fade_canvas = CanvasLayer.new()
	_fade_canvas.layer = 10
	add_child(_fade_canvas)
	_fade_layer = ColorRect.new()
	_fade_layer.color           = Color(0.0, 0.0, 0.0, 0.0)
	_fade_layer.anchor_right    = 1.0
	_fade_layer.anchor_bottom   = 1.0
	_fade_layer.mouse_filter    = Control.MOUSE_FILTER_IGNORE
	_fade_canvas.add_child(_fade_layer)

	# Shared rig (created once, moved between scenes)
	rig = CharacterRig.new()
	add_child(rig)

	# Save + quest tracker
	save          = SaveState.new()
	quest_tracker = QuestTracker.new(save)

	# FSM
	fsm = StateMachine.new("game", {})
	fsm.add("CREATION",   _state_creation())
	fsm.add("OFFICE",     _state_office())
	fsm.add("CITY_EXIT",  _state_city_exit())
	fsm.add("WILDS",      _state_wilds())
	fsm.add("CHOICE",     _state_choice())
	fsm.add("FREE_ROAM",  _state_free_roam())

	# Wire global events
	EventBus.on("combat:enemyDown", _on_enemy_down)
	EventBus.on("player:died",      _on_player_died)

	# Apply Debug args (--origin / --cls / --name / --skip)
	_apply_debug_args()

# ---- public start (called by autotest after wiring args) ----
func start() -> void:
	if fsm.current_id == "":
		fsm.go("CREATION")

func _process(dt: float) -> void:
	# dt-scheduler
	if _timers.size() > 0:
		var due: Array = []
		for timer in _timers:
			timer["t"] -= dt
			if timer["t"] <= 0.0:
				due.append(timer)
		for timer in due:
			_timers.erase(timer)
			timer["fn"].call()
	fsm.update(dt)

# ================================================================
# CREATION — reads Debug args, boots to OFFICE (creation UI is P5)
# ================================================================
func _state_creation() -> Dictionary:
	return {
		"enter": func(_ctx: Dictionary, _from: String, _payload: Dictionary) -> void:
			_record_state("CREATION")
			# If Debug already set origin (via --skip), just go straight to OFFICE
			if save.origin_id != "" and save.class_id != "":
				fsm.go("OFFICE")
			else:
				# No args — set sensible defaults and go to OFFICE
				if save.origin_id == "":
					save.origin_id = "aetherborn"
				if save.class_id == "":
					save.class_id = "warrior"
				if save.player_name == "":
					var origin: Dictionary = save.get_origin()
					save.player_name = origin.get("defaultName", "Borisawa")
				fsm.go("OFFICE"),
	}

# ================================================================
# OFFICE
# ================================================================
func _state_office() -> Dictionary:
	return {
		"enter": func(_ctx: Dictionary, _from: String, _payload: Dictionary) -> void:
			_record_state("OFFICE")
			var origin: Dictionary = save.get_origin()

			# Build player systems
			stats      = Stats.new(save)
			passives   = Passives.new(save, stats)
			controller = PlayerController.new()
			add_child(controller)
			controller.setup(rig, stats, passives, save, _cam)

			# Build scene
			var office := RecruitmentOffice.new(origin)
			_set_scene(office)
			controller.enabled = true

			EventBus.emit_event("quest:toast", {"text": "Speak with the recruiter"}),

		"update": func(_ctx: Dictionary, dt: float) -> void:
			_gameplay_update(dt)
			var it: Dictionary = controller.nearest_interactable()
			if Input.is_action_just_pressed("ui_accept") or _check_key_e():
				if not it.is_empty():
					var it_id: String = it.get("id", "")
					if it_id == "recruiter":
						EventBus.emit_event("ui:dialogueRequested", {"interactable": it, "origin": save.get_origin()})
					elif it_id == "exitDoors":
						transition(func() -> void: fsm.go("CITY_EXIT")),
	}

var _e_was_pressed: bool = false
func _check_key_e() -> bool:
	var pressed: bool = Input.is_key_pressed(KEY_E)
	var just: bool    = pressed and not _e_was_pressed
	_e_was_pressed    = pressed
	return just

## sign_contract — autotest direct path (bypasses dialogue UI).
## Mirrors the JS onSigned callback.
func sign_contract() -> void:
	save.persist()
	EventBus.emit_event("contract:signed", {"origin": save.get_origin()})
	# Open doors
	if scene != null and scene.has_method("set_doors_open"):
		scene.set_doors_open(true)
	# Disable recruiter interactable
	if scene != null and scene.get("interactables") != null:
		for it in scene.interactables:
			if it.get("id", "") == "recruiter":
				it["enabled"] = false
	EventBus.emit_event("quest:toast", {"text": "The doors are open — deploy to The Wilds"})

# ================================================================
# CITY_EXIT
# ================================================================
func _state_city_exit() -> Dictionary:
	return {
		"enter": func(_ctx: Dictionary, _from: String, _payload: Dictionary) -> void:
			_record_state("CITY_EXIT")
			var origin: Dictionary = save.get_origin()
			var exit := CityExit.new(origin)
			_set_scene(exit)
			controller.enabled = true,

		"update": func(_ctx: Dictionary, dt: float) -> void:
			_gameplay_update(dt)
			var trigger: Dictionary = controller.check_triggers()
			if trigger.get("id", "") == "toWilds":
				transition(func() -> void: fsm.go("WILDS")),
	}

# ================================================================
# WILDS
# ================================================================
func _state_wilds() -> Dictionary:
	return {
		"enter": func(_ctx: Dictionary, _from: String, _payload: Dictionary) -> void:
			_record_state("WILDS")
			var origin: Dictionary = save.get_origin()
			var wilds := TheWilds.new(origin)
			_set_scene(wilds)
			controller.enabled = true

			# Spawn beasts
			enemies = []
			for sp in wilds.enemy_spawns:
				var beast := MaddenedBeast.new(sp, wilds)
				wilds.add_child(beast)
				enemies.append(beast)
			controller.enemies = enemies

			# Quest
			quest_tracker.activate(origin),

		"update": func(_ctx: Dictionary, dt: float) -> void:
			_gameplay_update(dt)
			var trigger: Dictionary = controller.check_triggers()
			if trigger.get("id", "") == "coreSight":
				quest_tracker.reach_core_site()
			elif trigger.get("id", "") == "encounterStart":
				for e in enemies:
					e.aggro = true
				EventBus.emit_event("quest:toast", {"text": "The maddened have your scent"})

			# E to interact
			if _check_key_e():
				var it: Dictionary = controller.nearest_interactable()
				if not it.is_empty():
					var it_id: String = it.get("id", "")
					if it_id == "core" or it_id == "core2":
						_on_core_shattered(),
	}

func _on_core_shattered() -> void:
	if scene != null and scene.has_method("destroy_core"):
		scene.destroy_core()
	quest_tracker.core_destroyed()
	if save.chosen_path == "":
		schedule(1.7, func() -> void: fsm.go("CHOICE"))
	else:
		save.persist()
		EventBus.emit_event("quest:toast", {"text": "The frontier is quiet — for now"})

# ================================================================
# CHOICE
# ================================================================
func _state_choice() -> Dictionary:
	return {
		"enter": func(_ctx: Dictionary, _from: String, _payload: Dictionary) -> void:
			_record_state("CHOICE")
			if controller != null:
				controller.enabled = false
			EventBus.emit_event("ui:choiceRequested", {
				"options": quest_tracker.path_options(save.get_origin()),
			}),

		"update": func(_ctx: Dictionary, dt: float) -> void:
			_gameplay_update(dt),
	}

## pick_path — autotest direct path (UI calls this via signal, or autotest directly)
func pick_path(path_id: String) -> void:
	var origin: Dictionary = save.get_origin()
	quest_tracker.choose_path(path_id, origin)
	var buff: Dictionary = PathsData.PATH_BUFFS.get(path_id, {})
	var mods: Dictionary = buff.get("mods", {})
	if stats != null:
		stats.apply_path_buff(mods)
	EventBus.emit_event("quest:toast", {"text": buff.get("toast", "Path chosen")})
	fsm.go("FREE_ROAM")

# ================================================================
# FREE_ROAM
# ================================================================
func _state_free_roam() -> Dictionary:
	return {
		"enter": func(_ctx: Dictionary, _from: String, _payload: Dictionary) -> void:
			_record_state("FREE_ROAM")
			EventBus.emit_event("ui:endCardRequested", {
				"save": save,
				"chosen_path": save.chosen_path,
			}),

		"update": func(_ctx: Dictionary, dt: float) -> void:
			_gameplay_update(dt)
			var trigger: Dictionary = controller.check_triggers()
			if trigger.get("id", "") == "coreSightB":
				quest_tracker.reach_core_site()
			elif trigger.get("id", "") == "encounterStartB":
				for e in enemies:
					e.aggro = true
				EventBus.emit_event("quest:toast", {"text": "The guardians wake"})
			# E to interact core2
			if _check_key_e():
				var it: Dictionary = controller.nearest_interactable()
				if it.get("id", "") == "core2":
					_on_core_shattered()
					EventBus.emit_event("quest:toast", {"text": "The quiet frontier holds — for now"})
					save.persist(),
	}

## continue_free_roam — autotest direct path (called after pick_path resolves end card)
func continue_free_roam() -> void:
	if controller != null:
		controller.enabled = true
	var origin: Dictionary = save.get_origin()
	quest_tracker.begin_second_purge(origin)
	# Spawn B-wave beasts
	if scene != null and scene.get("enemy_spawns_b") != null:
		for sp in scene.enemy_spawns_b:
			var beast := MaddenedBeast.new(sp, scene)
			scene.add_child(beast)
			enemies.append(beast)
		controller.enemies = enemies
	# Push B triggers
	if scene != null and scene.get("triggers") != null:
		if scene.get("core_positions") != null and scene.core_positions.size() > 1:
			var cp2: Vector3 = scene.core_positions[1]
			scene.triggers.append({"id": "coreSightB",      "position": cp2, "radius": 42.0, "fired": false})
			scene.triggers.append({"id": "encounterStartB", "position": cp2, "radius": 26.0, "fired": false})
		# Refresh controller trigger alias
		controller.triggers = scene.triggers
	# Expose core2 interactable (it starts disabled, gets enabled after all beasts die)

# ================================================================
# Shared gameplay update
# ================================================================
func _gameplay_update(dt: float) -> void:
	if scene != null and scene.has_method("update"):
		var ctrl_pos: Vector3 = controller.position if controller != null else Vector3.ZERO
		scene.update(dt, ctrl_pos)
	if controller != null:
		controller.update(dt)
	for enemy in enemies:
		if not enemy.dead:
			enemy.update_ai(dt, controller, passives)

# ================================================================
# Global event handlers
# ================================================================
func _on_enemy_down(_payload: Dictionary) -> void:
	quest_tracker.enemy_down()
	var alive: int = 0
	for e in enemies:
		if not e.dead and e.state != "dying":
			alive += 1
	if alive == 0 and scene != null and scene.has_method("set_core_interactable"):
		scene.set_core_interactable(true)
		# Also enable core2 interactable if it exists and is still alive
		EventBus.emit_event("quest:toast", {"text": "The Core is exposed — shatter it"})

func _on_player_died(_payload: Dictionary) -> void:
	transition(func() -> void:
		if stats != null:
			stats.health  = stats.max_health
			stats.stamina = stats.max_stamina
		if controller != null and scene != null:
			var sp: Dictionary = scene.player_spawn
			controller.position = sp.get("position", Vector3.ZERO)
		EventBus.emit_event("quest:toast", {"text": "Clause V: death verified once. Resurrection invoiced."})
	)

# ================================================================
# Helpers
# ================================================================
func schedule(delay: float, fn: Callable) -> void:
	_timers.append({"t": delay, "fn": fn})

func transition(midpoint: Callable) -> void:
	# Fade out
	_set_fade(1.0)
	schedule(0.75, func() -> void:
		midpoint.call()
		_set_fade(0.0)
	)

func _set_fade(alpha: float) -> void:
	if _fade_layer != null:
		_fade_layer.color = Color(0.0, 0.0, 0.0, alpha)

# ---- _set_scene: instantiate scene, put it in the tree, wire controller ----
func _set_scene(new_scene: Node3D) -> void:
	if scene != null:
		remove_child(scene)
		scene.queue_free()
	scene = new_scene
	add_child(scene)
	if controller != null:
		controller.set_scene(scene)

# ---- apply_debug_args: wire --origin/--cls/--name/--skip ----
func _apply_debug_args() -> void:
	var args: Dictionary = Debug.args
	if args.has("origin"):
		var origin: Dictionary = OriginsData.get_origin(String(args["origin"]))
		if not origin.is_empty():
			save.origin_id = origin.get("id", "")
	if args.has("cls"):
		save.class_id = String(args["cls"])
	if args.has("name"):
		save.player_name = String(args["name"])
	# --skip handled after start() is called (see start())

func _apply_skip_arg() -> void:
	var args: Dictionary = Debug.args
	if args.has("skip"):
		var skip: String = String(args["skip"])
		if skip == "office":
			fsm.go("OFFICE")
		elif skip == "exit":
			fsm.go("OFFICE")
			fsm.go("CITY_EXIT")
		elif skip == "wilds":
			fsm.go("OFFICE")
			fsm.go("WILDS")

func _record_state(id: String) -> void:
	if not fsm_states_visited.has(id):
		fsm_states_visited.append(id)
