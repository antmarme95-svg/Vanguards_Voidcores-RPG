# game_director.gd — Top-level game FSM and scene orchestrator.
# Port of src/core/GameDirector.js.
# FSM: CREATION → OFFICE → CITY_EXIT → WILDS → CHOICE → FREE_ROAM
# CREATION now has real UI (CreationUI) — Debug-arg fast path preserved for autotests.
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

# ---- UI layers (untyped to avoid cross-file class_name parse-order issues) ----
var creation_ui                = null  # CreationUI
var hud                        = null  # HUD
var dialogue_ui                = null  # DialogueUI
var quest_ui                   = null  # QuestUI
var pause_ui                   = null  # PauseUI
var minimap_ui                 = null  # MinimapUI

# ---- creation stage helpers ----
var _creation_env: WorldEnvironment = null
var _creation_lights: Array = []
var _creation_platform: Node3D = null
var _turntable_t: float = 0.0

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
	EventBus.on("ui:pathChosen",    _on_ui_path_chosen)
	EventBus.on("ui:continueRoam",  _on_ui_continue_roam)

	# Build persistent UI layers (always present in the tree)
	_build_ui_layers()

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
# CREATION — real UI state.
# Debug-args fast path: if --origin + --cls set, skip UI and go straight to OFFICE.
# ================================================================
func _state_creation() -> Dictionary:
	return {
		"enter": func(_ctx: Dictionary, _from: String, _payload: Dictionary) -> void:
			_record_state("CREATION")
			# Debug fast path (autotest_slice uses this)
			if save.origin_id != "" and save.class_id != "":
				fsm.go("OFFICE")
				return

			# Build creation stage: dark env + rim lights + ring platform
			_build_creation_stage()

			# Show creation UI
			creation_ui.show_panel()

			# Wire callbacks
			creation_ui.on_tab       = func(_tab_id: String) -> void: pass
			creation_ui.on_origin    = func(origin: Dictionary) -> void:
				# Apply rig phenotype + theme accent
				rig.apply_phenotype(save.phenotype, origin)
				var theme: Dictionary = origin.get("theme", {})
				var accent_hex: String = theme.get("accent", "#46e6ff")
				var ac := Color(accent_hex)
				creation_ui.set_accent(ac)
				quest_ui.set_accent_color(ac)
				hud.set_accent_color(ac)
			creation_ui.on_phenotype = func(field_id: String, value) -> void:
				var origin_dict: Dictionary = save.get_origin()
				if not origin_dict.is_empty():
					rig.apply_phenotype(save.phenotype, origin_dict)
			creation_ui.on_class_selected = func(_cls: Dictionary) -> void:
				if save.class_id != "":
					rig.apply_archetype(save.class_id)
			creation_ui.on_name      = func(_n: String) -> void: pass
			creation_ui.on_confirm   = func(_name_text: String) -> void:
				save.persist()
				EventBus.emit_event("creation:complete", {"save": save})
				creation_ui.hide_panel()
				_teardown_creation_stage()
				transition(func() -> void: fsm.go("OFFICE")),

		"update": func(_ctx: Dictionary, dt: float) -> void:
			# Turntable
			_turntable_t += dt
			if rig != null:
				rig.rotation.y = _turntable_t * 0.35,

		"exit": func(_ctx: Dictionary, _to: String) -> void:
			creation_ui.hide_panel()
			_teardown_creation_stage(),
	}

func _build_creation_stage() -> void:
	# Minimal creation stage: dark environment, rim lights, ring platform
	if _creation_env != null:
		return  # already built

	# Environment
	_creation_env = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.05, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.15, 0.22, 0.35)
	env.ambient_light_energy = 0.6
	_creation_env.environment = env
	add_child(_creation_env)

	# Rim lights
	var rim_front := OmniLight3D.new()
	rim_front.light_color = Color("#8af0ff")
	rim_front.light_energy = 1.4
	rim_front.omni_range   = 12.0
	rim_front.position     = Vector3(0, 2.8, -4)
	add_child(rim_front)
	_creation_lights.append(rim_front)

	var rim_back := OmniLight3D.new()
	rim_back.light_color  = Color("#ffa060")
	rim_back.light_energy = 0.9
	rim_back.omni_range   = 10.0
	rim_back.position     = Vector3(0, 1.5, 4)
	add_child(rim_back)
	_creation_lights.append(rim_back)

	# Ring platform
	_creation_platform = Node3D.new()
	var ring_mi := MeshInstance3D.new()
	var ring_mesh := CylinderMesh.new()
	ring_mesh.top_radius    = 1.6
	ring_mesh.bottom_radius = 1.6
	ring_mesh.height        = 0.06
	ring_mi.mesh = ring_mesh
	var ring_mat := ToonMaterials.toon_mat(Color(0.12, 0.18, 0.26))
	ring_mi.material_override = ring_mat
	_creation_platform.add_child(ring_mi)
	_creation_platform.position = Vector3(3.5, 0.0, -2.0)
	add_child(_creation_platform)

	# Position rig on platform
	rig.position = _creation_platform.position
	rig.rotation.y = 0.0
	_turntable_t = 0.0

	# Camera: look at rig from front-right
	_cam.position = _creation_platform.position + Vector3(0.0, 1.8, 4.5)
	_cam.look_at(_creation_platform.position + Vector3(0, 1.0, 0))

	# Apply default phenotype so rig shows skin tones instead of gray
	if save != null:
		var ph: Dictionary = save.phenotype
		if ph.is_empty():
			ph = PhenotypeData.default_phenotype()
		var origin: Dictionary = save.get_origin()
		# If no origin chosen yet, use a sensible neutral default (aetherborn has a light skin tone)
		if origin.is_empty():
			origin = OriginsData.get_origin("aetherborn")
		rig.apply_phenotype(ph, origin)

func _teardown_creation_stage() -> void:
	for light in _creation_lights:
		if is_instance_valid(light):
			remove_child(light)
			light.queue_free()
	_creation_lights.clear()
	if _creation_env != null:
		remove_child(_creation_env)
		_creation_env.queue_free()
		_creation_env = null
	if _creation_platform != null:
		remove_child(_creation_platform)
		_creation_platform.queue_free()
		_creation_platform = null

# ================================================================
# OFFICE
# ================================================================
func _state_office() -> Dictionary:
	return {
		"enter": func(_ctx: Dictionary, _from: String, _payload: Dictionary) -> void:
			_record_state("OFFICE")
			# Ensure creation panel is gone (belt-and-suspenders)
			if creation_ui != null:
				creation_ui.hide_panel()
			var origin: Dictionary = save.get_origin()

			# Build player systems (idempotent if already built)
			if stats == null:
				stats = Stats.new(save)
			if passives == null:
				passives = Passives.new(save, stats)
			if controller == null:
				controller = PlayerController.new()
				add_child(controller)
				controller.setup(rig, stats, passives, save, _cam)

			# Apply archetype silhouette now that class is confirmed
			if save.class_id != "":
				rig.apply_archetype(save.class_id)

			# Build scene
			var office := RecruitmentOffice.new(origin)
			_set_scene(office)
			controller.enabled = true

			# HUD
			hud.visible = true
			hud.show_crosshair()
			hud.set_passive(origin)
			var theme: Dictionary = origin.get("theme", {})
			var accent_hex: String = theme.get("accent", "#46e6ff")
			hud.set_accent_color(Color(accent_hex))
			quest_ui.set_accent_color(Color(accent_hex))

			# Wire dialogue
			EventBus.on("ui:dialogueRequested", _on_dialogue_requested)

			EventBus.emit_event("quest:toast", {"text": "Speak with the recruiter"}),

		"update": func(_ctx: Dictionary, dt: float) -> void:
			_gameplay_update(dt)
			var it: Dictionary = controller.nearest_interactable()
			if not it.is_empty():
				hud.show_prompt(it.get("label", it.get("id", "")))
			else:
				hud.hide_prompt()
			if Input.is_action_just_pressed("ui_accept") or _check_key_e():
				if not it.is_empty():
					var it_id: String = it.get("id", "")
					if it_id == "recruiter":
						if not dialogue_ui.is_open():
							EventBus.emit_event("ui:dialogueRequested", {"interactable": it, "origin": save.get_origin()})
					elif it_id == "exitDoors":
						transition(func() -> void: fsm.go("CITY_EXIT")),

		"exit": func(_ctx: Dictionary, _to: String) -> void:
			hud.hide_prompt()
			dialogue_ui.close_dialogue(),
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
			if creation_ui != null:
				creation_ui.hide_panel()
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
			if creation_ui != null:
				creation_ui.hide_panel()
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
			quest_tracker.activate(origin)

			# HUD markers — core positions as compass markers
			var markers: Array = []
			if wilds.get("core_positions") != null:
				for i in range(wilds.core_positions.size()):
					markers.append({"id": "core_%d" % i, "icon": "◆", "world_pos": wilds.core_positions[i]})
			hud.set_markers(markers),

		"update": func(_ctx: Dictionary, dt: float) -> void:
			_gameplay_update(dt)
			var trigger: Dictionary = controller.check_triggers()
			if trigger.get("id", "") == "coreSight":
				quest_tracker.reach_core_site()
			elif trigger.get("id", "") == "encounterStart":
				for e in enemies:
					e.aggro = true
				EventBus.emit_event("quest:toast", {"text": "The maddened have your scent"})

			# Interact prompt
			var it: Dictionary = controller.nearest_interactable()
			if not it.is_empty():
				hud.show_prompt(it.get("label", it.get("id", "")))
			else:
				hud.hide_prompt()

			# E to interact
			if _check_key_e():
				var it2: Dictionary = controller.nearest_interactable()
				if not it2.is_empty():
					var it_id: String = it2.get("id", "")
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
			if creation_ui != null:
				creation_ui.hide_panel()
			if controller != null:
				controller.enabled = false
			hud.hide_prompt()
			EventBus.emit_event("ui:choiceRequested", {
				"options": quest_tracker.path_options(save.get_origin()),
			}),

		"update": func(_ctx: Dictionary, dt: float) -> void:
			_gameplay_update(dt),
	}

## pick_path — autotest direct path (UI calls this via signal, or autotest directly)
func pick_path(path_id: String) -> void:
	# Dismiss choice overlay regardless of how pick_path is triggered
	if quest_ui != null and quest_ui._choice_overlay != null:
		quest_ui._choice_overlay.visible = false
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
			if creation_ui != null:
				creation_ui.hide_panel()
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
	# Set allegiance chip on HUD
	if save != null and save.chosen_path != "" and hud != null:
		var pb: Dictionary = PathsData.PATH_BUFFS.get(save.chosen_path, {})
		var label: String = pb.get("label", save.chosen_path)
		var origin: Dictionary = save.get_origin()
		var theme: Dictionary = origin.get("theme", {})
		var accent_hex: String = theme.get("accent", "#46e6ff")
		hud.set_allegiance(label, Color(accent_hex))
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
	# HUD per-frame update
	if hud != null and hud.visible and stats != null and controller != null:
		hud.update_hud(stats, controller.cam_yaw,
			controller.position if controller != null else Vector3.ZERO)

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
	if minimap_ui != null:
		minimap_ui.close()
		minimap_ui.bind(controller, scene)

# ================================================================
# UI layer construction (called once in _ready)
# ================================================================
func _build_ui_layers() -> void:
	var _CreationUI: GDScript = load("res://ui/creation_ui.gd")
	var _HUD: GDScript        = load("res://ui/hud.gd")
	var _DialogueUI: GDScript = load("res://ui/dialogue_ui.gd")
	var _QuestUI: GDScript    = load("res://ui/quest_ui.gd")
	var _PauseUI: GDScript    = load("res://ui/pause_ui.gd")
	var _MinimapUI: GDScript  = load("res://ui/minimap_ui.gd")

	if _CreationUI == null or _HUD == null or _DialogueUI == null or _QuestUI == null or _PauseUI == null or _MinimapUI == null:
		push_error("[GameDirector] Failed to load one or more UI scripts")
		return

	# CreationUI — set _save BEFORE add_child (add_child triggers _ready)
	creation_ui = _CreationUI.new()
	creation_ui._save = save
	add_child(creation_ui)
	creation_ui.hide_panel()

	# HUD
	hud = _HUD.new()
	add_child(hud)
	hud.visible = false

	# DialogueUI
	dialogue_ui = _DialogueUI.new()
	add_child(dialogue_ui)
	dialogue_ui.visible = false

	# QuestUI
	quest_ui = _QuestUI.new()
	add_child(quest_ui)

	# PauseUI
	pause_ui = _PauseUI.new()
	add_child(pause_ui)
	EventBus.on("player:pause_toggled", _on_pause_toggled)

	# MinimapUI
	minimap_ui = _MinimapUI.new()
	add_child(minimap_ui)
	minimap_ui.visible = false
	EventBus.on("minimap:toggled", _on_minimap_toggled)

# ================================================================
# Dialogue request handler
# ================================================================
func _on_dialogue_requested(payload: Dictionary) -> void:
	if dialogue_ui == null:
		return
	var origin: Dictionary = payload.get("origin", save.get_origin())
	var theme: Dictionary = origin.get("theme", {})
	var accent_hex: String = theme.get("accent", "#46e6ff")
	var tree: Dictionary = ContractData.build_recruiter_dialogue(origin, save.player_name)
	if tree.is_empty():
		return
	dialogue_ui.visible = true
	controller.enabled = false
	hud.hide_crosshair()
	dialogue_ui.start_tree(tree, func(action: String) -> void:
		if action == "openContract":
			dialogue_ui.visible = true
			dialogue_ui.open_contract(origin, save.player_name, func() -> void:
				sign_contract()
				dialogue_ui.visible = true
				dialogue_ui.jump_to("signed")
			)
		elif action == "end":
			dialogue_ui.visible = false
			dialogue_ui.close_dialogue()
			controller.enabled = true
			hud.show_crosshair()
			EventBus.emit_event("quest:toast", {"text": "The doors are open — deploy to The Wilds"})
	, Color(accent_hex))

# ================================================================
# Pause toggle handler
# ================================================================
func _on_minimap_toggled(_payload: Dictionary) -> void:
	if minimap_ui == null:
		return
	if dialogue_ui != null and dialogue_ui.is_open():
		return
	if pause_ui != null and pause_ui.is_open():
		return
	minimap_ui.toggle()

func _on_pause_toggled(_payload: Dictionary) -> void:
	if pause_ui == null or controller == null:
		return
	if dialogue_ui != null and dialogue_ui.is_open():
		return
	# ESC dismisses an open map before opening the pause menu
	if minimap_ui != null and minimap_ui.is_open():
		minimap_ui.close()
		return
	if pause_ui.is_open():
		pause_ui.close()
		hud.show_crosshair()
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		hud.hide_crosshair()
		pause_ui.open(controller)

# ================================================================
# ui:pathChosen / ui:continueRoam event handlers (from QuestUI)
# ================================================================
func _on_ui_path_chosen(payload: Dictionary) -> void:
	var path_id: String = payload.get("path_id", "")
	if path_id != "":
		pick_path(path_id)

func _on_ui_continue_roam(_payload: Dictionary) -> void:
	continue_free_roam()
	# Set allegiance chip
	if save.chosen_path != "":
		var pb: Dictionary = PathsData.PATH_BUFFS.get(save.chosen_path, {})
		var label: String = pb.get("label", save.chosen_path)
		var origin: Dictionary = save.get_origin()
		var theme: Dictionary = origin.get("theme", {})
		var accent_hex: String = theme.get("accent", "#46e6ff")
		hud.set_allegiance(label, Color(accent_hex))
		quest_ui.set_accent_color(Color(accent_hex))

func _apply_debug_args() -> void:
	var args: Dictionary = Debug.args
	if args.has("origin"):
		var origin: Dictionary = OriginsData.get_origin(str(args["origin"]))
		if not origin.is_empty():
			save.origin_id = origin.get("id", "")
	if args.has("cls"):
		save.class_id = str(args["cls"])
	if args.has("name"):
		save.player_name = str(args["name"])
	# --skip handled after start() is called (see start())

func _apply_skip_arg() -> void:
	var args: Dictionary = Debug.args
	if args.has("skip"):
		var skip: String = str(args["skip"])
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
