extends SceneTree

## Tests fuer ScoreStore: Mods im Bestwert, alte Eintraege ohne Mods,
## Modus-Trennung (Mania/Trace), SV-Stufe, Migration alter Dateien,
## Daten entfernter Modi (v1.44.0) werden uebersprungen.
## Laeuft immer auf einer Test-Datei (ScoreStore.PATH unter --script).

var _failed := 0


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		_failed += 1


func _init() -> void:
	var backup := ""
	if FileAccess.file_exists(ScoreStore.PATH):
		backup = FileAccess.get_file_as_string(ScoreStore.PATH)
		DirAccess.remove_absolute(ScoreStore.PATH)

	# Roundtrip mit Mods
	ScoreStore.submit("t1.osz", "Hard", { "score": 1000, "grade": "S", "mods": ["SV", "NF"], "mod_mult": 1.05 })
	var b := ScoreStore.best("t1.osz", "Hard")
	_check(b.get("mods", []) == ["SV", "NF"], "mods roundtrip")
	_check(is_equal_approx(float(b.get("mod_mult", 0)), 1.05), "mod_mult roundtrip")
	_check(ScoreStore.best_mods("t1.osz", "Hard") == ["SV", "NF"], "best_mods")
	_check(MapPicker.mods_badge(b) == "SV NF", "badge zeigt Mods")

	# Ohne Mods
	ScoreStore.submit("t2.osz", "Easy", { "score": 500, "grade": "A" })
	var c := ScoreStore.best("t2.osz", "Easy")
	_check(c.get("mods", ["x"]) == [], "ohne Mods leer")
	_check(MapPicker.mods_badge(c) == "", "kein Badge ohne Mods")

	# Alte Datei ohne mods-Feld
	var cfg := ConfigFile.new()
	cfg.load(ScoreStore.PATH)
	cfg.set_value("scores", ScoreStore._key("old.osz", "Old"), { "score": 700, "grade": "B", "accuracy": 0.9 })
	cfg.save(ScoreStore.PATH)
	var o := ScoreStore.best("old.osz", "Old")
	_check(int(o.get("score", 0)) == 700, "alter Eintrag lesbar")
	_check(ScoreStore.best_mods("old.osz", "Old") == [], "alter Eintrag: keine Mods")
	var r := ScoreStore.submit("old.osz", "Old", { "score": 900, "accuracy": 0.95, "mods": ["NF"] })
	_check(bool(r.is_new_best), "alter Eintrag ueberbietbar")
	_check(ScoreStore.best_mods("old.osz", "Old") == ["NF"], "neue Mods ersetzen alte")

	# Fremde Scores
	ScoreStore.submit("77 Song.osz", "Hard", { "score": 1000, "grade": "A", "pp": 50.0, "accuracy": 0.9 })
	ScoreStore.log_play("77 Song.osz", "Hard", "x", { "score": 1000, "grade": "A" })
	var pp_before := ScoreStore.profile_pp()
	var bp_before := ScoreStore.best_plays(10).size()
	var tp_before := ScoreStore.total_plays()
	var mk := ScoreStore.map_id_for_set(77, "Hard")
	var fe := { "score": 2000, "accuracy": 0.95, "grade": "S", "max_combo": 10, "pp": 99.0, "mods": [], "date": "d1" }
	_check(ScoreStore.submit_others(mk, "Bob", [fe]) == 1, "fremder Score gespeichert")
	_check(ScoreStore.submit_others(mk, "Bob", [fe]) == 0, "Duplikat nicht doppelt")
	_check(ScoreStore.submit_others(mk, "Cy", [fe]) == 1, "gleicher Score anderer Spieler ok")
	var many: Array = []
	for i in 15:
		many.append(fe.merged({ "score": 3000 + i, "date": "m%d" % i }, true))
	ScoreStore.submit_others(mk, "Bob", many)
	var bob := 0
	var top_bob := 0
	for e in ScoreStore.top_scores_all("mirror_77.osz", "Hard", 100):
		if e.player == "Bob":
			bob += 1
			top_bob = maxi(top_bob, int(e.score))
	_check(bob == 10 and top_bob == 3014, "max. 10 pro Spieler, beste bleiben")
	var all := ScoreStore.top_scores_all("77 Song.osz", "Hard", 100)
	var sorted_ok := true
	for i in range(1, all.size()):
		if int(all[i - 1].score) < int(all[i].score):
			sorted_ok = false
	_check(sorted_ok and int(all[0].score) == 3014, "top_scores_all sortiert")
	_check(all.any(func(e): return e.is_self and e.player == ScoreStore._self_name()), "eigener Eintrag is_self")
	_check(ScoreStore.top_scores_all("77 Song.osz", "Hard", 3).size() == 3, "n begrenzt")
	_check(ScoreStore.top_scores_all("mirror_77.osz", "Hard", 100).size() == all.size() - 1, "anderer Dateiname: fremde zugeordnet")
	ScoreStore.register_set_id("Artist - Weird Name.osz", 77)
	_check(ScoreStore.top_scores_all("Artist - Weird Name.osz", "Hard", 100).size() == all.size() - 1, "Registry ordnet zu")
	_check(ScoreStore.top_scores("77 Song.osz", "Hard").size() == 1, "top_scores nur eigene")
	_check(is_equal_approx(ScoreStore.profile_pp(), pp_before) and ScoreStore.best_plays(10).size() == bp_before \
			and ScoreStore.total_plays() == tp_before and int(ScoreStore.best("77 Song.osz", "Hard").score) == 1000, "Profil/pp/Bestwert unveraendert")
	_check(ScoreStore.submit_others(mk, "Dee", [fe.merged({ "score": -1 }, true)]) == 0, "ungueltig abgewiesen")
	# pp vom Server nachtragen: Live-Endergebnis kam ohne pp (-1).
	var mk2 := ScoreStore.map_id_for_set(78, "Hard")
	ScoreStore.submit_others(mk2, "Eve", [fe.merged({ "score": 4000, "pp": -1.0 }, true), fe.merged({ "score": 3500, "pp": -1.0 }, true)])
	var online := [{ "player": "Eve", "score": 4000, "pp": 123.4 }, { "player": "Bob", "score": 4000, "pp": 77.0 }, { "player": "Eve", "score": 3500, "pp": 0.0 }]
	_check(ScoreStore.fill_others_pp(mk2, online) == 1, "pp nur bei gleichem Spieler + Score nachgetragen")
	var eve := ScoreStore.top_scores_all("78 Song.osz", "Hard", 10)
	_check(eve.size() == 2 and is_equal_approx(float(eve[0].pp), 123.4) and float(eve[1].pp) < 0.0, "nachgetragene pp gespeichert, Rest bleibt offen")
	_check(ScoreStore.fill_others_pp(mk2, online) == 0, "zweiter Abgleich aendert nichts")

	_test_modes()
	_test_mode_list()
	_test_removed_modes()
	_test_sv_level()
	_test_migration()
	_test_run_fields()
	_test_legacy_rescore()
	_test_playtime()

	# aufraeumen
	DirAccess.remove_absolute(ScoreStore.PATH)
	if backup != "":
		var f := FileAccess.open(ScoreStore.PATH, FileAccess.WRITE)
		f.store_string(backup)
		f.close()
	print("FAILED: %d" % _failed if _failed > 0 else "ALL OK")
	quit(1 if _failed > 0 else 0)


## Modus-Liste: nur Mania und Trace, unbekannte Modi -> Mania bzw. unbekannt.
func _test_mode_list() -> void:
	_check(ScoreStore.MODES == ["mania", "trace"], "2 Modi in Reihenfolge")
	_check(ScoreStore.mode_label("trace") == "Trace" and ScoreStore.mode_label("") == "Mania 4K", "mode_label je Modus")
	_check(ScoreStore.uses_points("trace") and not ScoreStore.uses_points("quatsch")
		and not ScoreStore.uses_points("") and not ScoreStore.uses_points("mania"), "uses_points")
	_check(ScoreStore.is_mania_like("") and ScoreStore.is_mania_like("trace") and not ScoreStore.is_mania_like("quatsch"), "is_mania_like")
	_check(ScoreStore.mode_scene("trace") == "res://scenes/trace.tscn" and ScoreStore.mode_scene("") == "res://scenes/mania_3d.tscn"
		and ScoreStore.mode_scene("quatsch") == "res://scenes/mania_3d.tscn", "mode_scene")
	_check(ScoreStore.mode_tutorial("quatsch") == "" and (ScoreStore.mode_tutorial("trace") == ""
		or ResourceLoader.exists(ScoreStore.mode_tutorial("trace"))), "mode_tutorial nur mit Szene")
	_check(ScoreStore.normalize_mode("quatsch") == "mania" and ScoreStore.normalize_mode("trace") == "trace", "normalize_mode")
	_check(ScoreStore.known_mode("") and ScoreStore.known_mode("mania") and ScoreStore.known_mode("trace")
		and not ScoreStore.known_mode("quatsch"), "known_mode")
	_check(is_equal_approx(ScoreStore.rating_of([100.0, 50.0]), 100.0 + 50.0 * 0.95), "Gewichtung 0,95^Platz")
	var pp0 := ScoreStore.profile_pp()
	ScoreStore.submit("78 Six.osz", "Hard", { "score": 900000, "grade": "S", "accuracy": 0.97, "stars": 5.0, "mode": "trace" }, ScoreStore.MODE_TRACE)
	_check(int(ScoreStore.best("78 Six.osz", "Hard", ScoreStore.MODE_TRACE).score) == 900000
		and ScoreStore.best("78 Six.osz", "Hard").is_empty(), "Trace-Bestwert getrennt von Mania")
	_check(is_equal_approx(ScoreStore.profile_pp(), pp0), "Mania-pp nie durch Trace veraendert")


## Alte Nutzerdaten entfernter Modi (Orbit, Rally, Dirigent, Rebound, bis v1.43):
## Sektionen und Eintraege mit mode=orbit bleiben in der Datei liegen, werden nie
## als Mania/Trace gezaehlt, nichts stuerzt ab, nichts wird geloescht.
func _test_removed_modes() -> void:
	var real := ScoreStore.PATH
	var path := real.get_base_dir().path_join("removed_%d.cfg" % OS.get_process_id())
	ScoreStore.PATH = path
	var old := ConfigFile.new()
	var k := ScoreStore._key("20 Gone.osz", "Hard")
	old.set_value("meta", "schema", ScoreStore.SCHEMA)
	old.set_value("scores", k, { "score": 500, "grade": "B", "accuracy": 0.9, "pp": 12.0, "mode": "mania" })
	old.set_value("plays", k, 1)
	old.set_value("orbit_scores", k, { "score": 990000, "grade": "SS", "accuracy": 1.0, "stars": 9.0, "mode": "orbit" })
	old.set_value("orbit_plays", k, 7)
	old.set_value("orbit_history", k, [{ "score": 990000, "grade": "SS", "accuracy": 1.0, "mode": "orbit" }])
	old.set_value("orbit_recent", "plays", [{ "score": 990000, "map": "Gone", "mode": "orbit" }])
	old.set_value("rebound_scores", k, { "score": 880000, "grade": "S", "accuracy": 0.97, "mode": "rebound" })
	old.set_value("history", k, [{ "score": 500, "grade": "B", "accuracy": 0.9, "mode": "mania" }])
	old.set_value("recent", "plays", [{ "score": 500, "map": "Gone", "mode": "mania" }])
	old.save(path)
	ScoreStore._migrated_path = ""
	_check(int(ScoreStore.best("20 Gone.osz", "Hard").score) == 500, "Alt-Modi: Mania-Bestwert unveraendert")
	_check(ScoreStore.best("20 Gone.osz", "Hard", ScoreStore.MODE_TRACE).is_empty(), "Alt-Modi: nichts landet in Trace")
	_check(is_equal_approx(ScoreStore.profile_pp(), 12.0), "Alt-Modi: pp nur aus Mania")
	_check(ScoreStore.total_plays() == 1 and ScoreStore.total_plays(ScoreStore.MODE_TRACE) == 0, "Alt-Modi: Plays nicht mitgezaehlt")
	_check(ScoreStore.recent_plays(9).size() == 1 and ScoreStore.best_plays(9).size() == 1, "Alt-Modi: Verlauf/Bestwerte nur Mania")
	_check(int(ScoreStore.mode_stats().maps) == 1 and int(ScoreStore.mode_stats(ScoreStore.MODE_TRACE).maps) == 0, "Alt-Modi: Profil-Kennzahlen")
	var tops := ScoreStore.top_scores_all("20 Gone.osz", "Hard", 9)
	_check(tops.size() == 1 and int(tops[0].score) == 500, "Alt-Modi: Rangliste nur Mania")
	_check(not ScoreStore.known_mode("orbit") and not ScoreStore.known_mode("rally")
		and not ScoreStore.known_mode("dirigent") and not ScoreStore.known_mode("rebound"), "Alt-Modi: unbekannte Modi")
	# Neuer Lauf schreibt die Datei: alte Sektionen bleiben unangetastet liegen.
	ScoreStore.submit("20 Gone.osz", "Hard", { "score": 600, "grade": "A", "accuracy": 0.92 })
	var after := ConfigFile.new()
	after.load(path)
	_check(int((after.get_value("orbit_scores", k, {}) as Dictionary).get("score", 0)) == 990000
		and int(after.get_value("orbit_plays", k, 0)) == 7 and after.has_section("rebound_scores"), "Alt-Modi: Daten bleiben liegen")
	DirAccess.remove_absolute(path)
	ScoreStore.PATH = real
	ScoreStore._migrated_path = ""


## Mania und Trace getrennt: Bestwerte, Plays, Verlauf, Profil, Rangliste.
func _test_modes() -> void:
	_check(ScoreStore.PATH != "user://scores.cfg", "Test nutzt nie die echte scores.cfg")
	var O := ScoreStore.MODE_TRACE
	ScoreStore.submit("88 Mix.osz", "Hard", { "score": 5000, "grade": "A", "accuracy": 0.91, "pp": 40.0 })
	ScoreStore.log_play("88 Mix.osz", "Hard", "A - Mix", { "score": 5000, "grade": "A", "accuracy": 0.91, "pp": 40.0 })
	var pp0 := ScoreStore.profile_pp()
	var plays0 := ScoreStore.total_plays()
	var best0 := ScoreStore.best_plays(99).size()
	var recent0 := ScoreStore.recent_plays(99).size()
	# Trace-Score (mit pp-Wert, darf trotzdem nie in Mania-pp fliessen)
	var r := ScoreStore.submit("88 Mix.osz", "Hard", { "score": 9000, "grade": "S", "accuracy": 0.97, "pp": 500.0, "mode": "trace" }, O)
	ScoreStore.log_play("88 Mix.osz", "Hard", "A - Mix", { "score": 9000, "grade": "S", "accuracy": 0.97, "pp": 500.0 }, O)
	ScoreStore.log_play("88 Mix.osz", "Hard", "A - Mix", { "score": 100, "grade": "F", "accuracy": 0.2, "failed": true }, O)
	_check(bool(r.is_new_best), "erster Trace-Score ist Bestwert (Mania-Bestwert egal)")
	_check(int(ScoreStore.best("88 Mix.osz", "Hard").score) == 5000, "Mania-Bestwert unveraendert")
	_check(int(ScoreStore.best("88 Mix.osz", "Hard", O).score) == 9000, "Trace-Bestwert eigen")
	_check(str(ScoreStore.best("88 Mix.osz", "Hard", O).get("mode", "")) == "trace", "Trace-Eintrag traegt mode")
	_check(str(ScoreStore.best("88 Mix.osz", "Hard").get("mode", "")) == "mania", "Mania-Eintrag traegt mode")
	_check(is_equal_approx(ScoreStore.profile_pp(), pp0), "Mania-pp nie durch Trace veraendert")
	_check(ScoreStore.total_plays() == plays0 and ScoreStore.total_plays(O) == 1, "Plays je Modus")
	_check(ScoreStore.best_plays(99).size() == best0 and ScoreStore.best_plays(99, O).size() == 1, "Bestwerte je Modus")
	_check(ScoreStore.recent_plays(99).size() == recent0 and ScoreStore.recent_plays(99, O).size() == 2, "Verlauf je Modus")
	_check(ScoreStore.most_played(9, O).size() == 1 and int(ScoreStore.most_played(9, O)[0].count) == 1, "Meistgespielt je Modus")
	# Rangliste: Mania-Fremdscores nie in Trace, Trace-Fremdscores nie in Mania
	var fe := { "score": 7000, "accuracy": 0.9, "grade": "A", "max_combo": 5, "pp": 10.0, "mods": [], "date": "d" }
	ScoreStore.submit_others(ScoreStore.map_id_for_set(88, "Hard"), "Mia", [fe])
	ScoreStore.submit_others(ScoreStore.map_id_for_set(88, "Hard"), "Oli", [fe.merged({ "score": 7100 }, true)], O)
	var tm := ScoreStore.top_scores_all("88 Mix.osz", "Hard", 10)
	var to := ScoreStore.top_scores_all("88 Mix.osz", "Hard", 10, O)
	_check(tm.size() == 2 and tm.any(func(e): return e.player == "Mia") and not tm.any(func(e): return e.player == "Oli"), "Mania-Rangliste ohne Trace")
	_check(to.size() == 2 and to.any(func(e): return e.player == "Oli") and not to.any(func(e): return e.player == "Mia"), "Trace-Rangliste ohne Mania")
	_check(to.all(func(e): return e.mode == "trace") and tm.all(func(e): return e.mode == "mania"), "Rangliste traegt Modus")
	_check(int(to[0].score) == 9000, "Trace-Rangliste: eigener Trace-Score zuerst")
	# Profil-Kennzahlen je Modus
	var so := ScoreStore.mode_stats(O)
	_check(int(so.plays) == 1 and int(so.maps) == 1 and int(so.best_score) == 9000, "Trace-Kennzahlen")
	_check(is_equal_approx(float(so.avg_acc), 0.97), "Trace-Acc ohne Fails")
	_check(is_equal_approx(float(so.rating), 100.0 * pow(0.97, 4.0)), "Trace-Wertung 4 x Sterne^2 x Acc^4 (Standard 5 Sterne)")
	_check(is_equal_approx(float(ScoreStore.mode_stats().rating), ScoreStore.profile_pp()), "Mania-Wertung = pp")
	# Vergleich im Results-Screen: nur derselbe Modus
	ScoreStore.submit("88 Mix.osz", "Hard", { "score": 9500, "grade": "S", "accuracy": 0.98 }, O)
	var prev = ScoreStore.previous_best_for("88 Mix.osz", "Hard", O, 9500)
	_check(prev is Dictionary and int(prev.score) == 9000, "Bestleistung: vorheriger Trace-Score")
	_check(ScoreStore.previous_best_for("88 Mix.osz", "Hard", "", 9500) == null, "Bestleistung: nie anderer Modus")
	_check(ScoreStore.previous_best_for("88 Mix.osz", "Hard", O, 1) == null, "Bestleistung: nur gespeichertes Ergebnis")


## SV-Stufe im Score: gespeichert, angezeigt, alte Eintraege ohne Stufe.
func _test_sv_level() -> void:
	var keep := SvMod.strength
	SvMod.strength = SvMod.STRENGTH_NORMAL
	ScoreStore.submit("sv.osz", "N", { "score": 10, "mods": ["SV"] })
	ScoreStore.log_play("sv.osz", "N", "x", { "score": 10, "mods": ["SV"] })
	SvMod.strength = SvMod.STRENGTH_STRONG
	ScoreStore.submit("sv.osz", "S", { "score": 10, "mods": ["SV", "NF"] })
	ScoreStore.submit("sv.osz", "X", { "score": 10, "mods": ["SV"], "sv_level": "normal" })
	ScoreStore.submit("sv.osz", "P", { "score": 10, "mods": ["NF"] })
	var n := ScoreStore.best("sv.osz", "N")
	var st := ScoreStore.best("sv.osz", "S")
	_check(str(n.get("sv_level", "")) == "normal", "SV Normal gespeichert")
	_check(str(ScoreStore.top_scores("sv.osz", "N")[0].get("sv_level", "")) == "normal", "SV-Stufe im Verlauf")
	_check(str(st.get("sv_level", "")) == "strong", "SV Stark gespeichert (Standard)")
	_check(ScoreStore.sv_level(ScoreStore.best("sv.osz", "X")) == "normal", "SV-Stufe aus dem Ergebnis")
	_check(not ScoreStore.best("sv.osz", "P").has("sv_level"), "ohne SV keine Stufe")
	_check(ScoreStore.mods_label(n) == "SV " + TranslationServer.translate("Normal"), "Anzeige SV Normal")
	_check(ScoreStore.mods_label(st) == "SV " + TranslationServer.translate("Stark") + " NF", "Anzeige SV Stark NF")
	_check(ScoreStore.mods_label({ "mods": ["SV"] }) == "SV", "alter SV-Score ohne Stufe")
	_check(ScoreStore.mods_label({}) == "", "ohne Mods leer")
	var f := ScoreStore.sanitize_foreign({ "score": 1, "accuracy": 0.5, "grade": "D", "max_combo": 1, "pp": -1.0,
		"mods": ["SV"], "sv_level": "strong" }, "Zed")
	_check(str(f.get("sv_level", "")) == "strong", "Fremd-Score behaelt SV-Stufe")
	var bad := ScoreStore.sanitize_foreign({ "score": 1, "accuracy": 0.5, "grade": "D", "max_combo": 1, "pp": -1.0,
		"mods": [], "sv_level": 5 }, "Zed")
	_check(not bad.is_empty() and not bad.has("sv_level"), "Fremd-Score: ungueltige Stufe verworfen")
	SvMod.strength = keep


## Alte Datei (Schema 1): alles bleibt Mania, nichts geht verloren; nur
## Verlaufs-Eintraege mit anderem mode (hier Trace) wandern in dessen Sektion.
func _test_migration() -> void:
	var real := ScoreStore.PATH
	var path := real.get_base_dir().path_join("migrate_%d.cfg" % OS.get_process_id())
	ScoreStore.PATH = path
	var old := ConfigFile.new()
	var k := ScoreStore._key("10 Old.osz", "Hard")
	old.set_value("scores", k, { "score": 800, "grade": "A", "accuracy": 0.93, "pp": 77.0 })
	old.set_value("plays", k, 3)
	old.set_value("history", k, [{ "score": 800, "grade": "A" }, { "score": 600, "grade": "B", "mode": "trace" }])
	old.set_value("recent", "plays", [{ "score": 800, "map": "x" }, { "score": 600, "map": "x", "mode": "trace" }])
	old.set_value("others", "10|Hard", [{ "player": "Bob", "score": 1 }])
	old.save(path)
	ScoreStore._migrated_path = ""
	_check(int(ScoreStore.best("10 Old.osz", "Hard").score) == 800, "Migration: Bestwert bleibt Mania")
	_check(ScoreStore.best("10 Old.osz", "Hard", "trace").is_empty(), "Migration: kein Bestwert anderer Modi erfunden")
	_check(is_equal_approx(ScoreStore.profile_pp(), 77.0), "Migration: pp unveraendert")
	_check(ScoreStore.play_count("10 Old.osz", "Hard") == 3, "Migration: Plays bleiben")
	_check(ScoreStore.top_scores("10 Old.osz", "Hard", 9).size() == 1, "Migration: Mania-Verlauf ohne andere Modi")
	_check(ScoreStore.top_scores("10 Old.osz", "Hard", 9, "trace").size() == 1, "Migration: Verlauf anderer Modi verschoben, nicht geloescht")
	_check(ScoreStore.recent_plays(9).size() == 1 and ScoreStore.recent_plays(9, "trace").size() == 1, "Migration: Recent getrennt")
	var after := ConfigFile.new()
	after.load(path)
	_check(int(after.get_value("meta", "schema", 0)) == ScoreStore.SCHEMA, "Migration: Schema gesetzt")
	_check((after.get_value("others", "10|Hard", []) as Array).size() == 1, "Migration: Fremd-Scores bleiben")
	_check(not ScoreStore.migrate(after), "Migration nur einmal")
	DirAccess.remove_absolute(path)
	ScoreStore.PATH = real


## Alte Arcade-Scores (vor v1.1.5): einmalig auf ScoreV1, Bestwert neu bestimmt.
func _test_legacy_rescore() -> void:
	var real := ScoreStore.PATH
	var path := real.get_base_dir().path_join("legacy_%d.cfg" % OS.get_process_id())
	ScoreStore.PATH = path
	var k := ScoreStore._key("5 Song.osz", "Hard")
	var old_best := { "score": 1497224, "accuracy": 0.9163, "grade": "A", "pp": 23.0,
		"n_max": 600, "n300": 300, "n200": 40, "n100": 60, "n50": 10, "n_miss": 20,
		"date": "2026-07-18T20:00:00" }
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "schema", 2)
	cfg.set_value("scores", k, old_best)
	cfg.set_value("history", k, [
		{ "score": 1497224, "accuracy": 0.9163, "grade": "A", "pp": 23.0, "date": "2026-07-18T20:00:00" },
		{ "score": 956161, "accuracy": 0.9812, "grade": "S", "pp": 45.0, "date": "2026-11-08T12:00:00" },
		{ "score": 504624, "accuracy": 0.8599, "grade": "B", "pp": 13.0, "date": "2026-11-07T12:00:00" }])
	cfg.set_value("others", "5|Hard", [{ "player": "Alt", "score": 1800000, "accuracy": 0.97,
		"grade": "S", "max_combo": 1, "pp": 1.0, "mods": [], "date": "2026-07-17T10:00:00" }])
	cfg.save(path)
	ScoreStore._migrated_path = ""
	var tops := ScoreStore.top_scores("5 Song.osz", "Hard", 9)
	_check(tops.size() == 3 and is_equal_approx(float(tops[0].pp), 45.0), "Alt-Score: 98-%-Lauf jetzt vorn")
	var maxed := true
	for e in tops:
		maxed = maxed and int(e.score) <= 1000000
	_check(maxed, "Alt-Score: alle <= 1.000.000")
	var leg: Dictionary = tops[1] if int(tops[1].get("legacy_score", 0)) == 1497224 else tops[2]
	_check(int(leg.get("legacy_score", 0)) == 1497224, "Alt-Score: alter Wert in legacy_score")
	var b := ScoreStore.best("5 Song.osz", "Hard")
	_check(int(b.score) == 956161 and is_equal_approx(ScoreStore.profile_pp(), 45.0), "Alt-Score: Bestwert + pp = neuer Lauf")
	var after := ConfigFile.new()
	after.load(path)
	var others: Array = after.get_value("others", "5|Hard", [])
	_check(others.size() == 1 and int(others[0].score) <= 1000000, "Alt-Score: Fremd-Score umgerechnet")
	_check(not ScoreStore.migrate(after), "Alt-Score: nur einmal")
	# Perfekter Lauf ergibt exakt das Maximum.
	_check(ScoreStore.rescore_v1({ "n_max": 500 }) == 1000000, "rescore_v1: SS = 1.000.000")
	# Fremd-Score ueber Maximum wird beim Empfang umgerechnet.
	var fe := ScoreStore.sanitize_foreign({ "score": 1500000, "accuracy": 0.95, "grade": "S",
		"max_combo": 5, "pp": 2.0, "mods": [], "date": "2026-07-18T10:00:00" }, "Alt")
	_check(int(fe.score) <= 1000000, "Fremd-Score beim Empfang umgerechnet")
	DirAccess.remove_absolute(path)
	ScoreStore.PATH = real


## Spielzeit: Startwert nur einmal, danach addieren, Modi getrennt.
func _test_playtime() -> void:
	_check(ScoreStore.playtime_ms() == -1, "Spielzeit: ungemessen = -1")
	# Rangfolge: Genauigkeit vor Score (SV/MAX blaehen den Score auf).
	_check(ScoreStore.ranks_higher({"accuracy": 0.9525, "score": 794661}, {"accuracy": 0.9498, "score": 806603}),
		"Rangfolge: 95,25 % vor 94,98 % trotz kleinerem Score")
	_check(ScoreStore.ranks_higher({"accuracy": 0.95, "score": 2}, {"accuracy": 0.95, "score": 1}), "Rangfolge: gleiche Acc -> Score")
	ScoreStore.seed_playtime(60000)
	ScoreStore.seed_playtime(999999)
	_check(ScoreStore.playtime_ms() == 60000, "Spielzeit: Startwert nur einmal")
	ScoreStore.add_playtime(15000)
	_check(ScoreStore.playtime_ms() == 75000, "Spielzeit: addiert")
	ScoreStore.add_playtime(5000, ScoreStore.MODE_TRACE)
	_check(ScoreStore.playtime_ms(ScoreStore.MODE_TRACE) == 5000 and ScoreStore.playtime_ms() == 75000, "Spielzeit: Modi getrennt")
	var GS = load("res://scripts/game_session.gd")
	_check(GS.playtime_mode_of("res://scenes/trace.tscn") == "trace" 			and GS.playtime_mode_of("res://scenes/mania_3d.tscn") == "" 			and GS.playtime_mode_of("res://scenes/song_select.tscn") == null, "Spielzeit: Szenen-Modus")


## Schema 4: neue Laeufe tragen alle Felder des Online-Submits; alte Eintraege
## bleiben unveraendert, vor dem ersten neuen Schreiben liegt eine .bak.
func _test_run_fields() -> void:
	var real := ScoreStore.PATH
	var path := real.get_base_dir().path_join("runfields_%d.cfg" % OS.get_process_id())
	ScoreStore.PATH = path
	DirAccess.remove_absolute(path + ".bak")
	var old := ConfigFile.new()
	var ok := ScoreStore._key("old3.osz", "Hard")
	old.set_value("meta", "schema", 3)
	old.set_value("scores", ok, { "score": 800, "grade": "A", "accuracy": 0.9, "mods": ["HD"] })
	old.save(path)
	var old_text := FileAccess.get_file_as_string(path)
	ScoreStore._migrated_path = ""
	# Laden migriert: .bak = alte Datei, alter Eintrag ohne erfundene Felder.
	var o := ScoreStore.best("old3.osz", "Hard")
	_check(int(o.score) == 800 and not o.has("mod_mult") and not o.has("mines") and not o.has("stars"),
			"Schema 4: alter Eintrag unveraendert, Felder fehlen weiter")
	_check(FileAccess.file_exists(path + ".bak") and FileAccess.get_file_as_string(path + ".bak") == old_text,
			"Schema 4: .bak der alten Datei")
	# Mit Minen und Mods
	var mine := { "score": 5000, "accuracy": 0.98, "grade": "S", "mods": ["MN", "HD"], "mod_mult": 1.1,
		"mines": 40, "mine_hits": 3, "keys": 6 }
	ScoreStore.submit("new.osz", "Hard", mine, "mines")
	var e := ScoreStore.best("new.osz", "Hard", "mines")
	_check(int(e.get("mines", -1)) == 40 and int(e.get("mine_hits", -1)) == 3, "Minen-Zaehler gespeichert")
	_check(is_equal_approx(float(e.get("mod_mult", 0)), 1.1) and int(e.get("keys", 0)) == 6, "mod_mult + keys gespeichert")
	_check(str(e.get("client_version", "")) == OnlineApi.client_version() and str(e.get("date", "")).length() >= 19,
			"client_version + Datum mit Sekunden")
	# Trace mit Sternen
	ScoreStore.submit("tr.osz", "Hard", { "score": 900, "accuracy": 0.9, "grade": "A", "mods": ["NF"],
		"mod_mult": 0.5, "stars": 3.25 }, "trace")
	var t := ScoreStore.best("tr.osz", "Hard", "trace")
	_check(is_equal_approx(float(t.get("stars", -1)), 3.25) and is_equal_approx(float(t.get("mod_mult", 0)), 0.5),
			"Trace: stars + mod_mult gespeichert")
	# Verlauf traegt dieselben Felder
	ScoreStore.log_play("new.osz", "Hard", "x", mine, "mines")
	var h := ScoreStore.top_scores("new.osz", "Hard", 3, "mines")
	var rp := ScoreStore.recent_plays(3, "mines")
	_check(rp.size() == 1 and int(rp[0].get("mines", -1)) == 40 and is_equal_approx(float(rp[0].get("mod_mult", 0)), 1.1),
			"Verlauf/Recent tragen Felder")
	# Roundtrip: Datei neu lesen, alter Eintrag weiter da
	ScoreStore._migrated_path = ""
	var again := ScoreStore.best("new.osz", "Hard", "mines")
	_check(int(again.get("mine_hits", -1)) == 3 and int(ScoreStore.best("old3.osz", "Hard").score) == 800,
			"Roundtrip: neu und alt lesbar")
	var cfg := ConfigFile.new()
	cfg.load(path)
	_check(int(cfg.get_value("meta", "schema", 0)) == 4, "Schema 4 gesetzt")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".bak")
	ScoreStore.PATH = real
