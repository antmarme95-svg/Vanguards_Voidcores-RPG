# Headless parity test suite.
# Run with: godot --headless --path godot --script res://tests/test_core.gd
extends SceneTree

var _pass_count := 0
var _fail_count := 0

func _pass(test_name: String) -> void:
	print("PASS " + test_name)
	_pass_count += 1

func _fail(test_name: String, detail: String) -> void:
	print("FAIL " + test_name + ": " + detail)
	_fail_count += 1

func _init() -> void:
	# Autoloads are NOT instanced in --script mode; instantiate manually.
	var _event_bus = load("res://autoload/event_bus.gd").new()

	_test_event_bus()
	_test_state_machine()
	_test_attributes()
	_test_skills()
	_test_phenotype()
	_test_paths()
	_test_dialogue()
	_test_save_state()
	_test_config()

	print("")
	if _fail_count == 0:
		print("ALL_PASS")
		quit(0)
	else:
		print("FAILURES: %d" % _fail_count)
		quit(1)

# ------------------------------------------------------------------ 1. EventBus
func _test_event_bus() -> void:
	var eb = load("res://autoload/event_bus.gd").new()
	var state := {"count": 0, "payload": {}}

	var cb := func(p: Dictionary) -> void:
		state["payload"] = p
		state["count"] += 1

	eb.on("test:event", cb)
	eb.emit_event("test:event", {"value": 42})

	if state["count"] == 1 and state["payload"].get("value") == 42:
		_pass("EventBus: on/emit delivers payload")
	else:
		_fail("EventBus: on/emit delivers payload",
			"call_count=%d payload=%s" % [state["count"], str(state["payload"])])

	eb.off("test:event", cb)
	eb.emit_event("test:event", {"value": 99})

	if state["count"] == 1:
		_pass("EventBus: off stops delivery")
	else:
		_fail("EventBus: off stops delivery", "call_count=%d after off" % state["count"])

# ------------------------------------------------------------------ 2. StateMachine
func _test_state_machine() -> void:
	var sm := StateMachine.new("test", {})
	var log_enter: Array = []
	var log_exit: Array = []
	var log_update: Array = []

	sm.add("A", {
		"enter": func(ctx: Dictionary, from: String, payload: Dictionary) -> void:
			log_enter.append({"state": "A", "payload": payload}),
		"exit": func(ctx: Dictionary, to: String) -> void:
			log_exit.append("A"),
		"update": func(ctx: Dictionary, dt: float) -> void:
			log_update.append(dt),
	})
	sm.add("B", {
		"enter": func(ctx: Dictionary, from: String, payload: Dictionary) -> void:
			log_enter.append({"state": "B", "payload": payload}),
		"exit": func(ctx: Dictionary, to: String) -> void:
			log_exit.append("B"),
	})

	sm.go("A", {"hello": "world"})

	if log_enter.size() == 1 and log_enter[0]["state"] == "A" and log_enter[0]["payload"].get("hello") == "world":
		_pass("StateMachine: go calls enter with payload")
	else:
		_fail("StateMachine: go calls enter with payload", str(log_enter))

	sm.go("B", {})

	if log_exit.size() == 1 and log_exit[0] == "A":
		_pass("StateMachine: go calls exit of previous")
	else:
		_fail("StateMachine: go calls exit of previous", str(log_exit))

	# B has no "update" key — update should be a no-op
	sm.update(0.016)

	if log_update.is_empty():
		_pass("StateMachine: update is no-op for state without update key")
	else:
		_fail("StateMachine: update is no-op for state without update key",
			"got calls: %s" % str(log_update))

	# Switch to A which has "update"
	sm.go("A", {})
	sm.update(0.033)

	if log_update.size() == 1 and abs(log_update[0] - 0.033) < 0.0001:
		_pass("StateMachine: update forwards delta")
	else:
		_fail("StateMachine: update forwards delta", str(log_update))

	if sm.is_state("A"):
		_pass("StateMachine: is_state works")
	else:
		_fail("StateMachine: is_state works", "current_id=%s" % sm.current_id)

# ------------------------------------------------------------------ 3. Attribute parity
func _test_attributes() -> void:
	var ss := SaveState.new()

	# ironblooded + warrior → health == 130 (ironblooded has no attributeMods)
	ss.origin_id = "ironblooded"
	ss.class_id  = "warrior"
	var attrs_iw := ss.compute_attributes()
	if attrs_iw.get("health") == 130:
		_pass("Attributes: ironblooded+warrior health==130")
	else:
		_fail("Attributes: ironblooded+warrior health==130",
			"health=%d" % attrs_iw.get("health", -1))

	# aetherborn + mage → health 90, magicka 190 (140+50), stamina 90
	ss.origin_id = "aetherborn"
	ss.class_id  = "mage"
	var attrs_am := ss.compute_attributes()
	if attrs_am.get("health") == 90 and attrs_am.get("magicka") == 190 and attrs_am.get("stamina") == 90:
		_pass("Attributes: aetherborn+mage health/magicka/stamina")
	else:
		_fail("Attributes: aetherborn+mage health/magicka/stamina",
			"health=%d magicka=%d stamina=%d" % [
				attrs_am.get("health", -1), attrs_am.get("magicka", -1), attrs_am.get("stamina", -1)])

	# miststalker + thief → stamina 120 (miststalker has no attributeMods)
	ss.origin_id = "miststalker"
	ss.class_id  = "thief"
	var attrs_mt := ss.compute_attributes()
	if attrs_mt.get("stamina") == 120:
		_pass("Attributes: miststalker+thief stamina==120")
	else:
		_fail("Attributes: miststalker+thief stamina==120",
			"stamina=%d" % attrs_mt.get("stamina", -1))

# ------------------------------------------------------------------ 4. Skill parity
func _test_skills() -> void:
	var ss := SaveState.new()

	ss.origin_id = "aetherborn"
	ss.class_id  = "mage"
	var skills_mage := ss.compute_skills()
	if skills_mage.get("Destruction") == 25:
		_pass("Skills: mage Destruction==25")
	else:
		_fail("Skills: mage Destruction==25",
			"Destruction=%d" % skills_mage.get("Destruction", -1))

	ss.class_id = "warrior"
	var skills_war := ss.compute_skills()
	if skills_war.get("Two-Handed") == 25:
		_pass("Skills: warrior Two-Handed==25")
	else:
		_fail("Skills: warrior Two-Handed==25",
			"Two-Handed=%d" % skills_war.get("Two-Handed", -1))

	ss.class_id = "thief"
	var skills_thief := ss.compute_skills()
	if skills_thief.get("Sneak") == 25 and skills_thief.get("Archery") == 20:
		_pass("Skills: thief Sneak==25 Archery==20")
	else:
		_fail("Skills: thief Sneak==25 Archery==20",
			"Sneak=%d Archery=%d" % [skills_thief.get("Sneak", -1), skills_thief.get("Archery", -1)])

	if skills_thief.get("Destruction") == 15:
		_pass("Skills: unlisted skill==15 (thief/Destruction)")
	else:
		_fail("Skills: unlisted skill==15 (thief/Destruction)",
			"Destruction=%d" % skills_thief.get("Destruction", -1))

# ------------------------------------------------------------------ 5. Phenotype defaults
func _test_phenotype() -> void:
	var defaults := PhenotypeData.default_phenotype()
	var all_ok := true
	var missing := ""
	for f in PhenotypeData.PHENOTYPE_FIELDS:
		if not defaults.has(f["id"]):
			all_ok = false
			missing = "missing key: %s" % f["id"]
			break
		if defaults[f["id"]] != f["default"]:
			all_ok = false
			missing = "%s: got %s expected %s" % [f["id"], str(defaults[f["id"]]), str(f["default"])]
			break
	if all_ok:
		_pass("Phenotype: default_phenotype has all fields with correct defaults")
	else:
		_fail("Phenotype: default_phenotype has all fields with correct defaults", missing)

# ------------------------------------------------------------------ 6. Paths data
func _test_paths() -> void:
	var kingdom: Dictionary = PathsData.PATH_BUFFS.get("kingdom", {})
	var rogue: Dictionary   = PathsData.PATH_BUFFS.get("rogue", {})
	var k_mods: Dictionary  = kingdom.get("mods", {})
	var r_mods: Dictionary  = rogue.get("mods", {})

	if k_mods.get("maxHealth") == 25 and abs(float(k_mods.get("physicalResist", 0.0)) - 0.10) < 0.0001:
		_pass("Paths: kingdom mods maxHealth==25 physicalResist==0.10")
	else:
		_fail("Paths: kingdom mods maxHealth==25 physicalResist==0.10", str(k_mods))

	if abs(float(r_mods.get("damageMult", 0.0)) - 1.15) < 0.0001:
		_pass("Paths: rogue damageMult==1.15")
	else:
		_fail("Paths: rogue damageMult==1.15", str(r_mods))

# ------------------------------------------------------------------ 7. Dialogue
func _test_dialogue() -> void:
	var aetherborn_origin := OriginsData.get_origin("aetherborn")
	var tree := ContractData.build_recruiter_dialogue(aetherborn_origin, "Boris")

	if tree.has("start"):
		_pass("Dialogue: tree has 'start' entry")
	else:
		_fail("Dialogue: tree has 'start' entry", str(tree.keys()))

	var nodes: Dictionary = tree.get("nodes", {})
	var hub: Dictionary   = nodes.get("hub", {})
	var choices: Array    = hub.get("choices", [])
	if choices.size() == 4:
		_pass("Dialogue: hub has 4 choices")
	else:
		_fail("Dialogue: hub has 4 choices", "choices=%d" % choices.size())

	var found_open_contract := false
	var found_end := false
	for node_key in nodes:
		var node: Dictionary = nodes[node_key]
		if node.get("action") == "openContract":
			found_open_contract = true
		if node.get("action") == "end":
			found_end = true

	if found_open_contract:
		_pass("Dialogue: node with action 'openContract' exists")
	else:
		_fail("Dialogue: node with action 'openContract' exists", "not found in nodes")

	if found_end:
		_pass("Dialogue: node with action 'end' exists")
	else:
		_fail("Dialogue: node with action 'end' exists", "not found in nodes")

	var clauses := ContractData.get_contract_clauses(aetherborn_origin, "Boris")
	if clauses.size() == 5:
		_pass("Dialogue: get_contract_clauses returns 5 clauses")
	else:
		_fail("Dialogue: get_contract_clauses returns 5 clauses", "count=%d" % clauses.size())

	# Clause index 0 = ARTICLE I, which embeds playerName.
	var clause0_body: String = clauses[0].get("body", "")
	if "Boris" in clause0_body:
		_pass("Dialogue: clause 1 (ARTICLE I) body contains player name 'Boris'")
	else:
		_fail("Dialogue: clause 1 (ARTICLE I) body contains player name 'Boris'",
			clause0_body.left(80))

# ------------------------------------------------------------------ 8. SaveState round-trip
func _test_save_state() -> void:
	var sv := SaveState.new()
	sv.player_name  = "TestHero"
	sv.origin_id    = "ironblooded"
	sv.class_id     = "warrior"
	sv.chosen_path  = "kingdom"
	sv.kills        = 7
	sv.cores_purged = 2
	sv.persist()

	var loaded := SaveState.load_saved()
	if (loaded.get("name") == "TestHero"
		and loaded.get("originId") == "ironblooded"
		and loaded.get("classId") == "warrior"
		and loaded.get("chosenPath") == "kingdom"
		and loaded.get("kills") == 7):
		_pass("SaveState: persist/load round-trip (name/origin/class/path/kills)")
	else:
		_fail("SaveState: persist/load round-trip (name/origin/class/path/kills)",
			str(loaded))


# ------------------------------------------------------------------ 9. Config
func _test_config() -> void:
	var cfg: Node = load("res://core/config.gd").new()
	cfg.call("_ready")

	# Test substyle accessor
	var ss_aether_mage: Dictionary = cfg.call("substyle", "aetherborn", "mage")
	if ss_aether_mage.get("name") == "Chrono-Weaver":
		_pass("Config: substyle(aetherborn, mage) name==Chrono-Weaver")
	else:
		_fail("Config: substyle(aetherborn, mage) name==Chrono-Weaver",
			"name=%s" % ss_aether_mage.get("name", "NOT_FOUND"))

	var ss_iron_thief: Dictionary = cfg.call("substyle", "ironblooded", "thief")
	if ss_iron_thief.get("name") == "Scrap-Slinger":
		_pass("Config: substyle(ironblooded, thief) name==Scrap-Slinger")
	else:
		_fail("Config: substyle(ironblooded, thief) name==Scrap-Slinger",
			"name=%s" % ss_iron_thief.get("name", "NOT_FOUND"))

	# Test archetype accessor
	var arch_warrior: Dictionary = cfg.call("archetype", "warrior")
	if arch_warrior.get("name") == "Vanguard":
		_pass("Config: archetype(warrior) name==Vanguard")
	else:
		_fail("Config: archetype(warrior) name==Vanguard",
			"name=%s" % arch_warrior.get("name", "NOT_FOUND"))

	# Test missing keys return empty dict
	var missing: Dictionary = cfg.call("substyle", "unknown", "unknown")
	if missing.is_empty():
		_pass("Config: substyle(unknown, unknown) returns empty dict")
	else:
		_fail("Config: substyle(unknown, unknown) returns empty dict",
			"returned %s" % str(missing))

	# ── class_mult nested accessor (Sprint L0) ─────────────────────────────────
	# ironblooded+warrior → HEAVY tier: massMult==1.5, sprintSpeedMult==0.85
	var cm_iw: Dictionary = cfg.call("class_mult", "ironblooded", "warrior")
	if absf(float(cm_iw.get("massMult", 0.0)) - 1.5) < 0.001:
		_pass("Config: class_mult(ironblooded, warrior) massMult==1.5")
	else:
		_fail("Config: class_mult(ironblooded, warrior) massMult==1.5",
			"massMult=%s" % str(cm_iw.get("massMult", "NOT_FOUND")))
	if absf(float(cm_iw.get("sprintSpeedMult", 0.0)) - 0.85) < 0.001:
		_pass("Config: class_mult(ironblooded, warrior) sprintSpeedMult==0.85")
	else:
		_fail("Config: class_mult(ironblooded, warrior) sprintSpeedMult==0.85",
			"sprintSpeedMult=%s" % str(cm_iw.get("sprintSpeedMult", "NOT_FOUND")))

	# miststalker+thief → LIGHT tier: airControlPct==0.75, slideSteerMaxDeg==45
	var cm_mt: Dictionary = cfg.call("class_mult", "miststalker", "thief")
	if absf(float(cm_mt.get("airControlPct", 0.0)) - 0.75) < 0.001:
		_pass("Config: class_mult(miststalker, thief) airControlPct==0.75")
	else:
		_fail("Config: class_mult(miststalker, thief) airControlPct==0.75",
			"airControlPct=%s" % str(cm_mt.get("airControlPct", "NOT_FOUND")))
	if absf(float(cm_mt.get("slideSteerMaxDeg", 0.0)) - 45.0) < 0.001:
		_pass("Config: class_mult(miststalker, thief) slideSteerMaxDeg==45")
	else:
		_fail("Config: class_mult(miststalker, thief) slideSteerMaxDeg==45",
			"slideSteerMaxDeg=%s" % str(cm_mt.get("slideSteerMaxDeg", "NOT_FOUND")))

	# aetherborn+mage → BALANCED tier: slideFriction==0.95 (softened for longer slides)
	var cm_am: Dictionary = cfg.call("class_mult", "aetherborn", "mage")
	if absf(float(cm_am.get("slideFriction", 0.0)) - 0.95) < 0.001:
		_pass("Config: class_mult(aetherborn, mage) slideFriction==0.95")
	else:
		_fail("Config: class_mult(aetherborn, mage) slideFriction==0.95",
			"slideFriction=%s" % str(cm_am.get("slideFriction", "NOT_FOUND")))

	# unknown+unknown → graceful fallback: dict contains all 9 fields
	var cm_unk: Dictionary = cfg.call("class_mult", "unknown", "unknown")
	if cm_unk.has("massMult") and cm_unk.has("airControlPct"):
		_pass("Config: class_mult(unknown, unknown) fallback has massMult and airControlPct")
	else:
		_fail("Config: class_mult(unknown, unknown) fallback has massMult and airControlPct",
			"keys=%s" % str(cm_unk.keys()))
