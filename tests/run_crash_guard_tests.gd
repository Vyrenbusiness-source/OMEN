extends SceneTree

## Headless-Tests fuer den Absturzschutz (scripts/system/crash_guard.gd):
## Wachmarke, Stufenlogik, Neustart-Startzeile, Bericht, Cache-Leeren, Texte.
## Schreibt nur in einen Temp-Ordner, nie nach user://.

const G := preload("res://scripts/system/crash_guard.gd")
var _failed := 0


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		_failed += 1


func _touch(path: String, text: String = "x") -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _initialize() -> void:
	var dir := OS.get_temp_dir().path_join("omen_crash_guard_test_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(dir)
	_marker(dir)
	_stages()
	_restart()
	_report(dir)
	_caches(dir)
	_misc()
	_texts()
	G._remove_tree(dir)
	print("=== Crash-Guard-Tests: %s ===" % ("OK" if _failed == 0 else "%d FEHLER" % _failed))
	quit(1 if _failed > 0 else 0)


func _marker(dir: String) -> void:
	var st := dir.path_join("run_state.cfg")
	_check(not G.evaluate_start(G.read_state(st)), "ohne Wachmarke: kein Absturz")
	var run := {"started": true, "clean": false, "phase": G.PHASE_GAME, "world": "storm",
		"stage": 1, "clean_runs": 2, "gpu": "AMD Radeon RX 9070", "notice": true, "report": ""}
	_check(G.write_state(st, run), "Wachmarke geschrieben")
	var back := G.read_state(st)
	_check(G.evaluate_start(back), "laufend, nicht sauber: Absturz erkannt")
	_check(str(back.get("phase")) == G.PHASE_GAME and str(back.get("world")) == "storm", "Phase und Welt gelesen")
	_check(int(back.get("stage")) == 1 and int(back.get("clean_runs")) == 2, "Stufe und Zaehler gelesen")
	var cfg := ConfigFile.new()
	cfg.load(st)
	_check(cfg.has_section_key("heal", "stage") and cfg.has_section_key("run", "phase"), "Abschnitte [run]/[heal]")
	run["clean"] = true
	G.write_state(st, run)
	_check(not G.evaluate_start(G.read_state(st)), "sauberes Ende: kein Absturz")
	_check(not G.evaluate_start({"started": true}), "fehlendes clean gilt als sauber (alte Datei)")


func _stages() -> void:
	# Absturz in Start/Laden/Spiel: eine Stufe hoch, Zaehler 0.
	_check(G.next_stage(0, 0, true, G.PHASE_START) == [1, 0], "Absturz Start: 0 -> 1")
	_check(G.next_stage(1, 2, true, G.PHASE_LOAD) == [2, 0], "Absturz Laden: 1 -> 2, Zaehler 0")
	_check(G.next_stage(2, 0, true, G.PHASE_GAME) == [3, 0], "Absturz Spiel: 2 -> 3")
	_check(G.next_stage(3, 0, true, G.PHASE_GAME) == [3, 0], "Stufe 3 ist das Maximum")
	# Absturz in Menue/Browser: keine neue Stufe, Serie bricht ab.
	_check(G.next_stage(1, 2, true, G.PHASE_MENU) == [1, 0], "Absturz Menue: Stufe bleibt, Zaehler 0")
	_check(G.next_stage(0, 0, true, G.PHASE_BROWSER) == [0, 0], "Absturz Browser: Stufe 0 bleibt")
	# Saubere Laeufe: nach 3 eine Stufe zurueck.
	_check(G.next_stage(2, 0, false, "") == [2, 1], "sauber 1")
	_check(G.next_stage(2, 1, false, "") == [2, 2], "sauber 2")
	_check(G.next_stage(2, 2, false, "") == [1, 0], "sauber 3: 2 -> 1")
	_check(G.next_stage(1, 2, false, "") == [0, 0], "sauber 3: 1 -> 0")
	_check(G.next_stage(0, 0, false, "") == [0, 0], "Stufe 0 zaehlt nicht hoch")
	# Kompletter Ablauf 0 -> 3 -> zurueck auf 0 (9 saubere Laeufe).
	var s := [0, 0]
	for p in [G.PHASE_LOAD, G.PHASE_GAME, G.PHASE_START]:
		s = G.next_stage(s[0], s[1], true, p)
	_check(s[0] == 3, "drei Abstuerze: Stufe 3")
	for i in 9:
		s = G.next_stage(s[0], s[1], false, "")
	_check(s == [0, 0], "neun saubere Laeufe: zurueck auf 0")
	# Neustart-Lauf (Vulkan -> D3D12) zaehlt nicht.
	_check(G.next_stage(3, 1, false, G.PHASE_START, false) == [3, 1], "D3D12-Neustart zaehlt nicht")
	_check(G.next_stage(9, 0, false, "") == [3, 1], "kaputte Stufe wird geklemmt")
	# Was die Stufen bewirken.
	_check(G.texture_limit(0) == 0 and G.texture_limit(1) == 0, "Stufe 0/1: keine Texturgrenze")
	_check(G.texture_limit(2) == 4096 and G.texture_limit(3) == 4096, "ab Stufe 2: Texturen max. 4096")
	_check(G.stage_key(0) == "Normal" and G.stage_key(7) == G.STAGE_KEYS[3], "Stufentexte")


func _restart() -> void:
	var none := PackedStringArray()
	_check(G.restart_args(2, "vulkan", "Windows", none, none).is_empty(), "Stufe 2: kein Neustart")
	_check(G.restart_args(3, "d3d12", "Windows", none, none).is_empty(), "schon D3D12: kein Neustart")
	_check(G.restart_args(3, "opengl3", "Windows", none, none).is_empty(), "OpenGL (GpuGuard): kein Neustart")
	_check(G.restart_args(3, "vulkan", "Linux", none, none).is_empty(), "nicht Windows: kein Neustart")
	var a := G.restart_args(3, "vulkan", "Windows", PackedStringArray(["--fullscreen"]), none)
	_check(a == PackedStringArray(["--fullscreen", "--rendering-driver", "d3d12"]), "Stufe 3 Vulkan: Neustart mit --rendering-driver d3d12")
	var b := G.restart_args(3, "Vulkan", "Windows", PackedStringArray(["--", "--x"]), PackedStringArray(["--x"]))
	_check(b == PackedStringArray(["--rendering-driver", "d3d12", "--", "--x"]), "Nutzer-Argumente bleiben hinter --")
	_check(G.restart_args(3, "vulkan", "Windows", PackedStringArray(["--rendering-driver", "d3d12"]), none).is_empty(),
		"D3D12 fiel auf Vulkan zurueck: keine Neustart-Schleife")


func _report(dir: String) -> void:
	var logs := dir.path_join("logs")
	_check(G.read_last_log(logs) == "", "ohne Log-Ordner: leer")
	_touch(logs.path_join("godot.log"), "aktueller Lauf")
	_check(G.read_last_log(logs).contains("aktueller Lauf"), "nur godot.log: wird genommen")
	_touch(logs.path_join("godot2026-11-27T10.00.00.log"), "ERROR: vkQueueSubmit failed VK_ERROR_DEVICE_LOST")
	var lg := G.read_last_log(logs)
	_check(lg.contains("DEVICE_LOST") and not lg.contains("aktueller Lauf"), "rotiertes Log des vorigen Laufs gewinnt")
	var big := "A".repeat(500) + "ENDE"
	_touch(logs.path_join("godot2026-11-27T11.00.00.log"), big)
	var tail := G.read_last_log(logs, 100)
	_check(tail.ends_with("ENDE") and tail.length() < 200, "nur das Ende grosser Logs")

	var prev := {"phase": G.PHASE_LOAD, "world": "monolith", "version": "1.43.1", "renderer": "forward_plus",
		"driver": "vulkan", "gpu": "AMD Radeon RX 9070", "gpu_vendor": "AMD", "gpu_driver": "AMD 32.0.21",
		"cpu": "AMD Ryzen 7 7800X3D", "stage": 1, "vram_mb": 2100, "started_at": "2026-11-27 10:00:00"}
	var txt := G.build_report(prev, "LOGZEILE")
	for want in ["OMEN", "Laden", "monolith", "1.43.1", "vulkan", "RX 9070", "AMD 32.0.21", "7800X3D", "2100 MB", "LOGZEILE"]:
		_check(txt.contains(want), "Bericht enthaelt " + want)
	_check(G.build_report({}, "").contains("kein Log"), "Bericht ohne Daten bricht nicht")
	_check(G.report_name(0) == "1970-01-01_00-00-00.txt", "Berichtsname nach Datum")
	var crash := dir.path_join("crash")
	var p := G.write_report(crash, prev, "L", 86400.0)
	_check(p.ends_with("1970-01-02_00-00-00.txt") and FileAccess.file_exists(p), "Bericht geschrieben")
	_check(FileAccess.get_file_as_string(p).contains("monolith"), "Berichtinhalt auf Platte")
	for i in 4:
		G.write_report(crash, prev, "L", 86400.0 * (i + 2))
	G.prune_reports(crash, 3)
	_check(DirAccess.get_files_at(crash).size() == 3, "alte Berichte aufgeraeumt (max 3)")
	_check(G.latest_report(crash).ends_with("1970-01-06_00-00-00.txt"), "neuester Bericht gefunden")
	_check(G.latest_report(dir.path_join("nix")) == "", "kein Ordner: kein Bericht")


func _caches(dir: String) -> void:
	var u := dir.path_join("user")
	_touch(u.path_join("shader_cache/SceneForwardClusteredShaderRD/abc/0.cache"))
	_touch(u.path_join("shader_cache/CanvasShaderRD/x.cache"))
	_touch(u.path_join("vulkan/pipelines.amd_radeon_rx_9070.cache"))
	_touch(u.path_join("d3d12/pipelines.amd_radeon_rx_9070.cache"))
	_touch(u.path_join("vulkan/keep.txt"))
	_touch(u.path_join("settings.cfg"))
	var n := G.clear_render_caches(u)
	_check(n == 4, "4 Cache-Dateien geloescht (%d)" % n)
	_check(not DirAccess.dir_exists_absolute(u.path_join("shader_cache")), "shader_cache weg")
	_check(not FileAccess.file_exists(u.path_join("vulkan/pipelines.amd_radeon_rx_9070.cache")), "Vulkan-Pipeline-Cache weg")
	_check(FileAccess.file_exists(u.path_join("vulkan/keep.txt")) and FileAccess.file_exists(u.path_join("settings.cfg")),
		"fremde Dateien bleiben")
	_check(G.clear_render_caches(u) == 0, "zweites Leeren ist harmlos")


func _misc() -> void:
	_check(G.phase_for_scene("res://scenes/main_menu.tscn") == G.PHASE_MENU, "Szene Menue")
	_check(G.phase_for_scene("res://scenes/song_select.tscn") == G.PHASE_BROWSER, "Szene Browser")
	_check(G.phase_for_scene("res://scenes/mania_3d.tscn") == G.PHASE_GAME, "Szene Spiel (Mania)")
	_check(G.phase_for_scene("res://scenes/trace.tscn") == G.PHASE_GAME, "Szene Spiel (Trace)")
	_check(G.phase_for_scene("") == "", "unbekannte Szene: Phase bleibt")
	for p in [G.PHASE_START, G.PHASE_LOAD, G.PHASE_GAME]:
		_check(G.HEAL_PHASES.has(p), "heilt nach Absturz in " + p)
	_check(G.is_test_run(PackedStringArray(["--shot-menu"])) and G.is_test_run(PackedStringArray(["--autoplay"])),
		"Test-Laeufe ohne Wachmarke")
	_check(not G.is_test_run(PackedStringArray(["--fullscreen"])), "normaler Start mit Wachmarke")
	var img := Image.create(8192, 4096, false, Image.FORMAT_RGBA8)
	G.limit_image(img, 4096)
	_check(img.get_width() == 4096 and img.get_height() == 2048, "8192x4096 -> 4096x2048")
	var small := Image.create(1024, 512, false, Image.FORMAT_RGBA8)
	_check(G.limit_image(small, 4096).get_width() == 1024, "kleine Bilder bleiben")
	_check(G.limit_image(img, 0).get_width() == 4096, "ohne Grenze unveraendert")


func _texts() -> void:
	var csv := FileAccess.get_file_as_string("res://translations/crash.csv")
	var keys := {}
	var f := FileAccess.open("res://translations/crash.csv", FileAccess.READ)
	var head := f.get_csv_line()
	_check(head == PackedStringArray(["keys", "de", "en"]), "crash.csv: keys,de,en")
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() >= 3 and row[0] != "":
			keys[row[0]] = row
			_check(row[2] != "" and row[1] != "", "en+de fuer: " + row[0])
	f.close()
	_check(csv != "", "crash.csv vorhanden")
	for k in G.STAGE_KEYS:
		_check(keys.has(k), "Stufentext uebersetzt: " + k)
	var src := FileAccess.get_file_as_string("res://scripts/ui/crash_notice.gd")
	var re := RegEx.create_from_string("tr\\(\"([^\"]+)\"\\)")
	var n := 0
	for m in re.search_all(src):
		n += 1
		_check(keys.has(m.get_string(1)), "Hinweistext uebersetzt: " + m.get_string(1))
	_check(n >= 6, "Hinweis nutzt tr() (%d Texte)" % n)
