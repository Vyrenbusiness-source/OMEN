extends SceneTree

## Intro-Skip mit der Leertaste, auch wenn sie Spalte ist (7K-Mitte, wie osu!).
## Im Intro: Skip statt Anschlag (kein Lane-Event, kein key_down), danach normale Spalte.
## Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_skip_key_tests.gd

var _passed := 0
var _failed := 0
var _started := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _ok(cond: bool, label: String) -> bool:
	if cond:
		_passed += 1
		print("  [PASS] " + label)
	else:
		_failed += 1
		print("  [FAIL] " + label)
	return cond


func _key(code: int, down: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = down
	return e


func _game(first_ms: float) -> Node3D:
	var g: Node3D = load("res://scripts/gameplay3d/mania_3d.gd").new()
	var core: ManiaCore = g.get("core")
	core.columns = 7
	var bm := Beatmap.new()
	var n := ManiaNote.new()
	n.time = first_ms
	n.column = 3
	bm.hit_objects.append(n)
	g.set("_beatmap", bm)
	g.set("_use_audio", true)
	g.set("_lane_held", [false, false, false, false, false, false, false])
	return g


func _run() -> void:
	print("=== OMEN Skip-Taste ===")
	var st: Node = root.get_node_or_null("Settings")
	if not _ok(st != null, "Settings-Autoload"):
		quit(1)
		return
	var old_k: Dictionary = (st.get("key_lanes_k") as Dictionary).duplicate(true)
	var kk: Dictionary = st.get("key_lanes_k")
	kk[7] = ManiaKeys.default_keys(7)
	var lane := int(st.call("mania_lane_for_key", KEY_SPACE, 7))
	_ok(lane >= 0, "7K: Leertaste ist Spalte (%d)" % lane)

	var g := _game(30000.0)
	_ok(bool(g.call("_can_skip_intro")), "langes Intro ist uebersprungbar")
	g._input(_key(KEY_SPACE, true))
	_ok(int(g.get("skips_done")) == 1, "Druck im Intro: Skip")
	_ok((g.get("_recorded") as Array).is_empty(), "kein Lane-Event aufgezeichnet")
	_ok(not bool((g.get("_lane_held") as Array)[lane]), "Spalte nicht gehalten")
	g._input(_key(KEY_SPACE, false))
	_ok((g.get("_recorded") as Array).is_empty(), "Loslassen wird mitgeschluckt")
	g.free()

	g = _game(1000.0)
	_ok(not bool(g.call("_can_skip_intro")), "kurzes Intro: nichts zu ueberspringen")
	g._input(_key(KEY_SPACE, true))
	_ok(int(g.get("skips_done")) == 0, "danach kein Skip")
	var rec: Array = g.get("_recorded")
	_ok(rec.size() == 1 and int(rec[0].lane) == lane and bool(rec[0].down), "Leertaste ist wieder Spalte")
	g.free()

	st.set("key_lanes_k", old_k)

	var pf := ManiaSkin.load_skin("builtin:Pfeile")
	_ok(pf != null and pf.snap_auto, "Pfeile-Skin: snap_auto")
	var bal := ManiaSkin.load_skin("builtin:Balken")
	_ok(bal != null and not bal.snap_auto, "Balken-Skin: kein snap_auto")
	_ok(ManiaSkin.auto_snap_color(1).r > 0.9 and ManiaSkin.auto_snap_color(1).g < 0.4, "1/4 rot")
	_ok(ManiaSkin.auto_snap_color(2).b > 0.9, "1/8 blau")
	_ok(ManiaSkin.auto_snap_color(3).b > 0.9 and ManiaSkin.auto_snap_color(3).r > 0.6, "1/12 violett")
	_ok(ManiaSkin.auto_snap_color(4).r > 0.9 and ManiaSkin.auto_snap_color(4).g > 0.7, "1/16 gelb")
	_ok(ManiaSkin.auto_snap_color(8).is_equal_approx(ManiaSkin.auto_snap_color(16)), "sonst grau")
	print("=== Ergebnis: %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
