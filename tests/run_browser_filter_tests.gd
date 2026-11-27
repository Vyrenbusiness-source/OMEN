extends SceneTree

## Headless-Tests fuer die Song-Browser-Filter (Task browser-filters): Score-Index
## je Modus aus einer Fake-scores.cfg in user://test_tmp, Bestwert-/Noten-Filter,
## Sortierungen (zuletzt gespielt, heruntergeladen, meistgespielt) und das
## Speichern/Pruefen des Modus-Filters.
## Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_browser_filter_tests.gd

## Zur Laufzeit geladen: song_select.gd braucht Autoloads (GameSession), die
## beim Parsen eines --script noch fehlen.
var SS: GDScript
const TMP := "user://test_tmp/browser_filter_scores.cfg"

var _passed := 0
var _failed := 0
var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_run()
	return true


func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: ", label)


func _run() -> void:
	print("=== OMEN Browser-Filter-Tests ===")
	SS = load("res://scripts/song_select.gd")
	if SS == null or not SS.can_instantiate():
		print("  FAIL: song_select.gd laedt nicht")
		quit(1)
		return
	_test_index()
	_test_best_filter()
	_test_sort()
	_test_mode_filter()
	_test_modes()
	_test_mtime()
	_test_recs()
	_test_menu_stack()
	_test_mode_stars()
	_test_panel_helpers()
	_test_board_scores()
	_test_curve_indent()
	print("=== %d ok, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


## Kartenkurve der Liste: x-Einzug = 44 px * d^2, d gekappt auf 0..1, symmetrisch.
func _test_curve_indent() -> void:
	_ok(is_equal_approx(SS.curve_indent(0.0), 0.0), "curve_indent: Mitte ohne Einzug")
	_ok(is_equal_approx(SS.curve_indent(1.0), 44.0), "curve_indent: Rand 44 px")
	_ok(is_equal_approx(SS.curve_indent(-0.5), 11.0), "curve_indent: -0.5 -> 11 px (symmetrisch)")
	_ok(is_equal_approx(SS.curve_indent(2.0), 44.0), "curve_indent: ausserhalb gekappt auf 44 px")


## Fake-Scores: Mania und Trace in getrennten Sektionen (ScoreStore._sec).
func _fake_cfg() -> ConfigFile:
	DirAccess.make_dir_recursive_absolute("user://test_tmp")
	var cfg := ConfigFile.new()
	cfg.set_value("scores", "1 A.osz|Easy", {"grade": "A", "date": "2026-11-01T10:00:00"})
	cfg.set_value("scores", "1 A.osz|Hard", {"grade": "SS", "date": "2026-11-02T10:00:00"})
	cfg.set_value("scores", "2 B.osz|Normal", {"grade": "F", "date": "2026-10-01T10:00:00"})
	cfg.set_value("plays", "1 A.osz|Easy", 3)
	cfg.set_value("plays", "1 A.osz|Hard", 1)
	cfg.set_value("plays", "2 B.osz|Normal", 7)
	cfg.set_value("plays", "3 C.osz|X", 2)
	cfg.set_value("history", "3 C.osz|X", [
		{"date": "2026-11-05T09:00:00", "failed": true},
		{"date": "2026-11-06T09:00:00", "failed": true}])
	cfg.set_value("recent", "plays", [
		{"osz_file": "2 B.osz", "version": "Normal", "date": "2026-11-07T12:00:00"}])
	cfg.set_value("trace_scores", "2 B.osz|Normal", {"grade": "S", "date": "2026-09-01T10:00:00"})
	cfg.set_value("trace_plays", "2 B.osz|Normal", 1)
	cfg.save(TMP)
	var back := ConfigFile.new()
	back.load(TMP)
	return back


func _test_index() -> void:
	var cfg := _fake_cfg()
	var mania: Dictionary = SS.build_score_index(cfg, "")
	var trace: Dictionary = SS.build_score_index(cfg, "trace")
	_ok(mania.size() == 3, "Mania-Index hat 3 Sets (%d)" % mania.size())
	_ok(SS.set_best_grade(mania["1 A.osz"], ["Easy", "Hard"]) == "SS", "beste Note ueber Diffs = SS")
	_ok(SS.set_best_grade(mania["1 A.osz"], ["Easy"]) == "A", "nur sichtbare Diffs zaehlen")
	_ok(SS.set_best_grade(mania["2 B.osz"], ["Normal"]) == "D", "F zaehlt als D")
	_ok(SS.set_best_grade(mania["3 C.osz"], ["X"]) == "", "nur Fails: kein Bestwert")
	_ok(SS.set_plays(mania["1 A.osz"], ["Easy", "Hard"]) == 4, "Plays summiert")
	_ok(SS.set_last_played(mania["3 C.osz"], ["X"]) == "2026-11-06T09:00:00", "letzter Play aus History")
	_ok(SS.set_last_played(mania["2 B.osz"], ["Normal"]) == "2026-11-07T12:00:00", "letzter Play aus Recent")
	_ok(trace.size() == 1 and trace.has("2 B.osz"), "Trace-Index getrennt von Mania")
	_ok(SS.set_best_grade(trace["2 B.osz"], ["Normal"]) == "S", "Trace-Note aus trace_scores")
	_ok(SS.set_plays(trace["2 B.osz"], ["Normal"]) == 1, "Trace-Plays getrennt")
	_ok(SS.build_score_index(ConfigFile.new(), "").is_empty(), "leere cfg -> leerer Index")


func _test_best_filter() -> void:
	_ok(SS.grade_bucket("SSH") == "SS" and SS.grade_bucket("SH") == "S", "Hidden-Noten gebuendelt")
	_ok(SS.grade_bucket("X") == "SS" and SS.grade_bucket("") == "", "X = SS, leer bleibt leer")
	_ok(SS.passes_best_filter("", SS.BEST_ALL, []), "Alle: ohne Bestwert sichtbar")
	_ok(SS.passes_best_filter("B", SS.BEST_ALL, []), "Alle: mit Bestwert sichtbar")
	_ok(SS.passes_best_filter("A", SS.BEST_WITH, []), "Mit Bestwert")
	_ok(not SS.passes_best_filter("", SS.BEST_WITH, []), "Mit Bestwert schliesst leere aus")
	_ok(SS.passes_best_filter("", SS.BEST_WITHOUT, []), "Ohne Bestwert")
	_ok(not SS.passes_best_filter("S", SS.BEST_WITHOUT, []), "Ohne Bestwert schliesst Noten aus")
	_ok(SS.passes_best_filter("S", SS.BEST_WITH, ["S", "A"]), "Note S in S/A")
	_ok(not SS.passes_best_filter("B", SS.BEST_WITH, ["S", "A"]), "Note B nicht in S/A")
	_ok(not SS.passes_best_filter("", SS.BEST_ALL, ["S"]), "Note gewaehlt: ohne Bestwert weg")


## Drei Sets wie _sort_set() sie fuer BrowserSort baut.
func _sets() -> Array:
	return [
		{"title": "B", "artist": "Zed", "mapper": "m", "osz_path": "b.osz", "date_added": 300, "diffs": [
			{"version": "Hard", "stars": 4.0, "mode": 3, "keys": 7, "rank": "A", "_i": 0},
			{"version": "Easy", "stars": 1.5, "mode": 3, "keys": 4, "_i": 1}]},
		{"title": "a", "artist": "Alpha", "mapper": "m", "osz_path": "a.osz", "date_added": 100, "diffs": [
			{"version": "X", "stars": 3.0, "mode": 3, "keys": 4, "rank": "SS",
				"last_played": "2026-11-07T12:00:00", "_i": 0}]},
		{"title": "C", "artist": "1nd", "mapper": "m", "osz_path": "c.osz", "date_added": 200, "diffs": [
			{"version": "N", "stars": 2.0, "mode": 3, "keys": 4, "_i": 0}]},
	]


func _titles(groups: Array, gi: int = 0) -> Array:
	return (groups[gi]["entries"] as Array).map(func(e): return str(e["set"]["title"]))


func _test_sort() -> void:
	_ok(SS.SORT_KEYS.size() == 9 and SS.SORT_NAMES.size() == 9, "9 Sortierungen wie osu!")
	_ok(SS.GROUP_KEYS == ["none", "artist", "difficulty", "keys", "rank", "collections"], "6 Gruppierungen")
	_ok(SS.GROUP_NAMES.size() == SS.GROUP_KEYS.size(), "Gruppen-Namen vollstaendig")
	_ok(SS.sort_from_v1(0) == SS.SORT_TITLE and SS.sort_from_v1(1) == SS.SORT_DIFFICULTY
		and SS.sort_from_v1(3) == SS.SORT_RECENT and SS.sort_from_v1(4) == SS.SORT_ADDED
		and SS.sort_from_v1(99) == SS.SORT_RECENT, "alte Sortier-Nummern umgestellt")
	var g: Array = SS.browser_entries(_sets(), SS.SORT_TITLE, 0)
	_ok(g.size() == 1 and _titles(g) == ["a", "B", "C"], "Titel, ohne Gross/Klein (%s)" % str(_titles(g)))
	_ok((g[0]["entries"] as Array).all(func(e): return int(e["diff_index"]) == -1), "ein Eintrag je Set")
	g = SS.browser_entries(_sets(), SS.SORT_DIFFICULTY, 0)
	var stars: Array = (g[0]["entries"] as Array).map(func(e): return float(e["set"]["diffs"][e["diff_index"]]["stars"]))
	_ok(stars == [1.5, 2.0, 3.0, 4.0], "Schwierigkeit: jede Diff einzeln, aufsteigend (%s)" % str(stars))
	g = SS.browser_entries(_sets(), SS.SORT_RANK, 0)
	_ok(_titles(g) == ["a", "B", "C"], "Rang: SS vor A vor ungespielt (%s)" % str(_titles(g)))
	g = SS.browser_entries(_sets(), SS.SORT_RECENT, 0)
	_ok(_titles(g)[0] == "a", "Zuletzt gespielt zuerst")
	g = SS.browser_entries(_sets(), SS.SORT_ADDED, 0)
	_ok(_titles(g) == ["B", "C", "a"], "Hinzugefuegt: neueste zuerst (%s)" % str(_titles(g)))
	g = SS.browser_entries(_sets(), SS.SORT_TITLE, SS.GROUP_KEYS.find("keys"))
	_ok(g.size() == 2 and g[0]["title"] == "4K" and g[1]["title"] == "7K" and _titles(g, 1) == ["B"],
		"Gruppe Tasten: 4K, 7K")
	g = SS.browser_entries(_sets(), SS.SORT_TITLE, SS.GROUP_KEYS.find("artist"))
	_ok(g[0]["title"] == "0-9" and g[1]["title"] == "A", "Gruppe Interpret: 0-9 vor A")
	g = SS.browser_entries(_sets(), SS.SORT_TITLE, SS.GROUP_KEYS.find("collections"), {"Fav": ["c.osz"]})
	_ok(g.size() == 2 and g[0]["title"] == "Fav" and _titles(g, 0) == ["C"] and g[1]["title"] == "Keine Sammlung",
		"Gruppe Sammlungen")
	g = SS.browser_entries(_sets(), SS.SORT_TITLE, SS.GROUP_KEYS.find("rank"))
	_ok(g[0]["title"] == "SS" and g[-1]["title"] == "Ungespielt", "Gruppe Rang: SS zuerst, ungespielt zuletzt")


func _test_mode_filter() -> void:
	var d: Dictionary = SS.default_mode_filter()
	_ok(d["sort"] == SS.SORT_TITLE and d["best"] == SS.BEST_ALL and (d["grades"] as Array).is_empty(), "Standard")
	var s: Dictionary = SS.sanitize_mode_filter({"sort": 99, "best": -3, "grades": ["S", "Q", "S", "A"]})
	_ok(s["sort"] == SS.SORT_NAMES.size() - 1, "Sortierung begrenzt")
	_ok(s["grades"] == ["S", "A"], "unbekannte/doppelte Noten weg (%s)" % str(s["grades"]))
	_ok(s["best"] == SS.BEST_WITH, "Noten erzwingen Mit Bestwert")
	_ok(SS.sanitize_mode_filter({"grades": "S"})["grades"] == [], "kaputte Noten-Liste ignoriert")
	# Je Modus getrennt ueber ConfigFile gespeichert und wieder gelesen.
	var cfg := ConfigFile.new()
	cfg.set_value("browser", "mode_filters", {
		"mania": {"sort": SS.SORT_RECENT, "best": SS.BEST_WITHOUT, "grades": []},
		"trace": {"sort": SS.SORT_RANK, "best": SS.BEST_WITH, "grades": ["SS"]}})
	var path := "user://test_tmp/browser_filter_state.cfg"
	cfg.save(path)
	var back := ConfigFile.new()
	back.load(path)
	var mfs: Dictionary = back.get_value("browser", "mode_filters", {})
	var m: Dictionary = SS.sanitize_mode_filter(mfs.get("mania", {}))
	var o: Dictionary = SS.sanitize_mode_filter(mfs.get("trace", {}))
	_ok(m["sort"] == SS.SORT_RECENT and m["best"] == SS.BEST_WITHOUT, "Mania-Filter nach Neustart")
	_ok(o["sort"] == SS.SORT_RANK and o["grades"] == ["SS"], "Trace-Filter nach Neustart")
	DirAccess.remove_absolute(path)


## Mania + Trace: Index und Filter je Modus getrennt.
func _test_modes() -> void:
	var cfg := _fake_cfg()
	_ok(SS.build_score_index(cfg, "trace").size() == 1 and SS.build_score_index(cfg, "").size() == 3, "Trace/Mania-Index getrennt")
	_ok(SS.PLAY_MODES == ["mania", "trace"], "Browser kennt Mania und Trace")
	_ok(SS.PLAY_MODES == Array(ScoreStore.MODES), "Browser-Modi = ScoreStore.MODES")
	var mf := {}
	for m in SS.PLAY_MODES:
		mf[m] = SS.sanitize_mode_filter({"sort": SS.SORT_RECENT if m == "trace" else SS.SORT_RANK, "grades": ["S"] if m == "trace" else []})
	_ok(mf["trace"]["sort"] == SS.SORT_RECENT and mf["trace"]["grades"] == ["S"] and mf["mania"]["grades"] == []
		and mf["mania"]["sort"] == SS.SORT_RANK, "Modus-Filter getrennt")


## "Zuletzt heruntergeladen" nutzt die Aenderungszeit der Datei.
func _test_mtime() -> void:
	var p := "user://test_tmp/browser_filter_map.osz"
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string("x")
	f.close()
	var t := FileAccess.get_modified_time(p)
	_ok(absi(t - int(Time.get_unix_time_from_system())) < 120, "mtime der neuen Datei ist jetzt")
	DirAccess.remove_absolute(p)
	DirAccess.remove_absolute(TMP)


## "For you": Zustand, Stufe, Anzahl, Start-Vorschlaege, Rechnung, Laeufe, Grund, Stil.
func _test_recs() -> void:
	var st: Dictionary = SS.rec_sanitize({"levels": {"mania": "push", "trace": "quatsch"}, "hidden": 1})
	_ok(st.levels.mania == "push" and st.levels.trace == "challenge",
		"rec_sanitize: bekannte Stufe bleibt, sonst Challenge")
	_ok(st.hidden == true and st.collapsed == false, "rec_sanitize: Schalter als bool")
	_ok(SS.rec_sanitize(null).levels.size() == SS.PLAY_MODES.size(), "rec_sanitize(null): alle Modi")
	_ok(SS.rec_level(st, "mania") == "push" and SS.rec_level({}, "trace") == "challenge", "rec_level")
	_ok(SS.rec_count(720.0) == 3 and SS.rec_count(1080.0) == 5, "rec_count: 3 bei 720, 5 bei 1080")
	var cands: Array = []
	for i in 12:
		cands.append({"set": "s%d" % (i / 2), "diff": "d%d" % i, "stars": 0.6 + 0.4 * i, "osu_mode": 3})
	cands.append({"set": "ss", "diff": "d", "stars": 1.2, "osu_mode": 3, "best_grade": "SS"})
	cands.append({"set": "std", "diff": "d", "stars": 1.1, "osu_mode": 0})
	var sp: Array = SS.rec_starters("mania", cands, 3)
	_ok(sp.size() == 3 and float(sp[0].stars) >= 1.0 and sp[0].set != "ss" and sp[0].set != "std",
		"rec_starters: leichteste ab 1 Stern, ohne SS/unspielbar")
	var sets := {}
	for x in sp:
		sets[x.set] = true
	_ok(sets.size() == 3, "rec_starters: eine Map je Set")
	var few: Dictionary = SS.rec_compute("mania", "challenge", cands, [], 3)
	_ok(few.starter == true and few.items.size() == 3, "rec_compute: unter 5 Laeufen Start-Vorschlaege")
	var runs: Array = []
	for i in 8:
		runs.append({"set": "r%d" % i, "diff": "d", "stars": 2.6, "accuracy": 0.9, "pp": 20.0,
			"grade": "A", "date": "2026-01-0%dT10:00:00" % (i + 1)})
	var full: Dictionary = SS.rec_compute("mania", "challenge", cands, runs, 3, 1800000000)
	_ok(full.starter == false and absf(float(full.comfort) - 2.6) < 0.3 and not full.items.is_empty(),
		"rec_compute: Vorschlaege mit Level um 2,6 (%.2f)" % float(full.comfort))
	var rr: Array = SS.rec_runs([{"set": "a.osz", "diff": "Hard ", "stars": -1.0},
		{"set": "a.osz", "diff": "Hard | x", "stars": -1.0}, {"set": "b.osz", "diff": "X", "stars": -1.0}],
		{"a.osz|Hard": 3.2})
	_ok(rr.size() == 2 and float(rr[0].stars) == 3.2 and rr[1].diff == "Hard", "rec_runs: Sterne + Version gebunden")
	_ok(SS.rec_join_reason("expected 90 %", "") == "expected 90 %", "Grund ohne Stil")
	_ok(SS.rec_join_reason("expected 90 %", "Jacks, like your favourites").contains("Jacks"), "Grund mit Stil")
	var osu := "[General]\nMode: 3\n[Difficulty]\nCircleSize:4\n[HitObjects]\n"
	for i in 40:
		osu += "64,192,%d,1,0,0:0:0:0:\n" % (i * 120)
	var sty: Dictionary = SS.rec_style_of_text(osu)
	_ok(float(sty.get("jack", 0.0)) > 0.9, "rec_style_of_text: Jacks erkannt")


## Hauptmenue: Block vertikal mittig, genug Rand unten, Logo bei 720 kleiner.
func _test_menu_stack() -> void:
	var MM: GDScript = load("res://scripts/ui/main_menu.gd")
	for h in [720.0, 1080.0]:
		var r: Dictionary = MM.menu_stack(h, 300.0)
		_ok(absf(float(r.top) - float(r.bottom)) <= 1.0, "menu_stack %d: oben == unten" % h)
		_ok(float(r.bottom) >= 60.0, "menu_stack %d: unten >= 60 (%.0f)" % [h, float(r.bottom)])
	_ok(float(MM.menu_stack(720.0, 300.0).logo_scale) < 1.0, "menu_stack 720: Logo kleiner")


## Set mit vier Mania-Diffs und einer osu!standard-Diff (nie sichtbar). In Trace
## ist "HD" die schwerste Diff (10,65). Diffs liegen nach Mania-Sternen in der Bibliothek.
func _star_set(osz: String) -> MapSet:
	var ms := MapSet.new()
	ms.osz_path = osz
	for d in [["Easy", 1.5, 3], ["HD", 2.5, 3], ["Hard", 3.5, 3], ["Insane", 4.5, 3], ["Std", 2.0, 0]]:
		ms.diffs.append({"version": d[0], "stars": d[1], "mode": d[2], "cs": 4.0,
			"osu_filename": "%s.osu" % d[0]})
	return ms


## Browser nutzt die Sterne des aktiven Modus (Diff-Leiste, Pfeile, Auswahl,
## Liste, Filter, Sortierung); fehlende zaehlen vorlaeufig als Mania-Sterne.
func _test_mode_stars() -> void:
	_ok(SS.star_src("mania") == "mania" and SS.star_src("trace") == "trace" and SS.star_src("") == "mania",
		"Sternquelle je Modus")
	var b: Control = SS.new()
	var osz := "user://test_tmp/mode_stars_none.osz"
	var ms := _star_set(osz)
	var ms2 := MapSet.new()
	ms2.osz_path = "user://test_tmp/mode_stars_two.osz"
	ms2.diffs.append({"version": "X", "stars": 6.0, "mode": 3, "cs": 4.0, "osu_filename": "X.osu"})
	var tc := {}
	for v in [["Easy", 2.0], ["HD", 10.65], ["Hard", 5.0], ["Insane", 6.0]]:
		tc[StarService._trace_key("mode_stars_none.osz|1", "%s.osu" % v[0])] = v[1]
	tc[StarService._trace_key("mode_stars_two.osz|1", "X.osu")] = 3.0
	b.set("_tbase", {osz: "mode_stars_none.osz|1", ms2.osz_path: "mode_stars_two.osz|1"})
	b.set("_trace_cache", tc)
	b.set("_trace_cache_loaded", true)
	b.set("_play_mode", "mania")
	_ok(b.call("_mode_order", ms) == [0, 1, 2, 3], "Mania: Diffs nach Mania-Sternen, osu!standard unsichtbar")
	_ok(b.call("_hardest", ms) == 3, "Mania: Standard = Insane")
	b.set("_selected_set", ms)
	b.set("_selected_diff", 1)  # HD
	b.set("_play_mode", "trace")
	b.set("_selected_diff", maxi(ms.nearest_visible(int(b.get("_selected_diff")), b.call("_vm")), 0))
	var order: Array = b.call("_mode_order", ms)
	_ok(order == [0, 2, 3, 1], "Trace: Diffs nach Trace-Sternen, HD zuletzt (%s)" % str(order))
	_ok(int(b.get("_selected_diff")) == 1, "Wechsel Mania->Trace: Auswahl bleibt HD")
	_ok(b.call("_hardest", ms) == 1 and b.call("_easiest", ms) == 0, "Trace: Standard = HD, leichteste = Easy")
	_ok(MapSet.cycle_in(order, 3, 1) == 1 and MapSet.cycle_in(order, 1, 1) == 0
		and MapSet.cycle_in(order, 0, -1) == 1 and MapSet.cycle_in(order, 99, 1) == 0, "Pfeile folgen der Trace-Reihenfolge")
	_ok(is_equal_approx(float(b.call("_mode_max", ms)), 10.65), "Trace: Karten-Sterne = 10,65")
	_ok(is_equal_approx(float(b.call("_mode_stars", ms, 1)), 10.65), "Trace: Segment-Sterne der HD")
	# Sterne-Filter 6+: Trace-Set passt, Mania nicht.
	var smap: Dictionary = b.call("_mode_star_map", ms)
	_ok(ms.star_or_base(1, smap) >= 6.0 and ms.star_or_base(1, {}) < 6.0, "Sternfilter mit Modus-Sternen")
	# Fehlende Modus-Sterne: vorlaeufig Mania-Sterne.
	tc.erase(StarService._trace_key("mode_stars_none.osz|1", "Insane.osu"))
	_ok(b.call("_mode_order", ms) == [0, 3, 2, 1], "Trace: fehlende Insane vorlaeufig 4,5 (Mania)")
	_ok(float(b.call("_mode_stars_known", ms, 3)) < 0.0, "Trace: Insane noch unbekannt")
	# Liste: Sortierung "Sterne" nach Modus-Maximum.
	for mode in ["mania", "trace"]:
		b.set("_play_mode", mode)
		var rows := []
		for m in [ms, ms2]:
			rows.append({"ms": m, "i": rows.size(), "stars": m.max_visible_stars(b.call("_vm"), b.call("_mode_star_map", m))})
		_ok(rows.size() == 2, "Sterne-Maximum je Set (%s)" % mode)
	# Liste: Sortierung "Schwierigkeit" nach Modus-Sternen, schwerste Diff zuletzt.
	tc[StarService._trace_key("mode_stars_none.osz|1", "Insane.osu")] = 6.0
	b.set("_score_index", {"mania": {}, "trace": {}})
	for mode in ["mania", "trace"]:
		b.set("_play_mode", mode)
		b.set("_sort_cache", {})
		var g: Array = SS.browser_entries([b.call("_sort_set", ms), b.call("_sort_set", ms2)], SS.SORT_DIFFICULTY, 0)
		var last: Dictionary = (g[0]["entries"] as Array)[-1]
		_ok(last["set"]["_ms"] == (ms2 if mode == "mania" else ms), "Sortierung Schwierigkeit (%s)" % mode)
	_test_rows(b, ms, ms2)
	b.free()


## Virtuelle Liste: Zeilen aus Eintraegen, aufgeklapptes Set, Gruppenkoepfe, Auswahl.
func _test_rows(b: Control, ms: MapSet, ms2: MapSet) -> void:
	b.set("_play_mode", "mania")
	b.set("_sort_cache", {})
	b.set("_e_ms", [ms, ms2])
	b.set("_e_di", PackedInt32Array([-1, -1]))
	b.set("_e_g", PackedInt32Array([0, 1]))
	b.set("_selected_set", ms)
	b.set("_selected_diff", 2)
	b.set("_group_mode", 0)
	b.call("_rebuild_rows")
	var kinds: PackedInt32Array = b.get("_r_kind")
	_ok(Array(kinds) == [SS.ROW_SET, SS.ROW_DIFF, SS.ROW_DIFF, SS.ROW_DIFF, SS.ROW_DIFF, SS.ROW_SET],
		"gewaehltes Set klappt auf: 4 Diff-Zeilen (%s)" % str(kinds))
	_ok(Array(b.get("_r_di")).slice(1, 5) == [0, 1, 2, 3], "Diffs aufsteigend nach Sternen")
	_ok(int(b.call("_sel_row")) == 3, "Auswahl = Diff-Zeile der gewaehlten Diff")
	var ys: PackedFloat32Array = b.get("_r_y")
	_ok(is_equal_approx(ys[1] - ys[0], SS.SET_H + SS.ROW_GAP) and is_equal_approx(ys[2] - ys[1], SS.DIFF_H + SS.ROW_GAP),
		"feste Zeilenhoehen")
	_ok(is_equal_approx(float(b.get("_content_h")), ys[5] + SS.SET_H + SS.ROW_GAP + SS.LIST_TOP_PAD), "Gesamthoehe")
	b.set("_group_mode", SS.GROUP_KEYS.find("keys"))
	b.set("_selected_set", ms2)
	b.set("_selected_diff", 0)
	b.call("_rebuild_rows")
	kinds = b.get("_r_kind")
	_ok(Array(kinds) == [SS.ROW_GROUP, SS.ROW_SET, SS.ROW_GROUP, SS.ROW_SET, SS.ROW_DIFF],
		"Gruppenkoepfe, nur das gewaehlte Set offen (%s)" % str(kinds))
	_ok(int(b.call("_set_row_of", ms2)) == 3 and int(b.call("_set_row_of", ms)) == 1, "Set-Zeile finden")
	_ok(int(b.call("_row_state", 4)) == 2 and int(b.call("_row_state", 3)) == 1 and int(b.call("_row_state", 1)) == 0,
		"Zustand: Diff gewaehlt, Set offen, normal")


## Linkes Panel (Stufe 2a): Mod-Kuerzel, Datum der Bestenliste, Bild-Helfer.
func _test_panel_helpers() -> void:
	var codes: Array = SS.mods_code_list({"SV": true, "NF": true, "TB": true})
	_ok(codes == ["NF", "SV", "TB"], "Mod-Kuerzel in fester Reihenfolge (%s)" % str(codes))
	_ok(SS.mods_code_list({}).is_empty(), "keine Mods -> leere Liste")
	_ok(SS.mods_code_list({"NF": false}).is_empty(), "abgeschaltete Mod zaehlt nicht")
	var uniq := {}
	for k in codes:
		uniq[k] = true
	_ok(uniq.size() == codes.size(), "keine doppelten Kuerzel")
	_ok(SS.score_date_text("2026-11-27T10:00:00", true) == "27.11.26", "Datum de")
	_ok(SS.score_date_text("2026-11-27T10:00:00", false) == "11/27/26", "Datum en")
	_ok(SS.score_date_text("kaputt", true) == "", "unlesbares Datum -> leer")
	_ok(SS.score_date_text("", false) == "", "leeres Datum -> leer")
	_ok(SS.decode_image(PackedByteArray(), "png") == null, "leere Bytes -> kein Bild")
	var img := Image.create(320, 180, false, Image.FORMAT_RGB8)
	img.fill(Color(1, 1, 1))
	_ok(absf(SS.image_luminance(img) - 1.0) < 0.01, "weisses Bild: Luminanz 1")
	var blurred: Image = SS.blur_image(img)
	_ok(blurred != null and blurred.get_width() == 640, "Weichzeichner liefert 640 px Breite")


## Bestenliste im Worker: ohne Szenenbaum, eigener Name kommt als Parameter.
func _test_board_scores() -> void:
	const BTMP := "user://test_tmp/browser_board_scores.cfg"
	DirAccess.make_dir_recursive_absolute("user://test_tmp")
	var old_path: String = ScoreStore.PATH
	var old_mig: String = ScoreStore._migrated_path
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "schema", ScoreStore.SCHEMA)
	cfg.set_value("history", ScoreStore._key("9 Z.osz", "Hard"), [
		{"accuracy": 0.95, "score": 800000, "date": "2026-11-01T10:00:00"},
		{"accuracy": 0.99, "score": 900000, "date": "2026-11-02T10:00:00", "failed": true},
		{"accuracy": 0.90, "score": 700000, "date": "2026-11-03T10:00:00"}])
	cfg.set_value("others", ScoreStore.map_id("9 Z.osz", "Hard", cfg), [
		{"player": "Rival", "accuracy": 0.97, "score": 850000}])
	cfg.save(BTMP)
	ScoreStore.PATH = BTMP
	var rows: Array = SS.board_scores("9 Z.osz", "Hard", 5, "", "Tester")
	var one: Array = SS.board_scores("9 Z.osz", "Hard", 1, "", "T")
	ScoreStore.PATH = old_path
	ScoreStore._migrated_path = old_mig
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BTMP))
	_ok(rows.size() == 3, "Bestenliste: 2 eigene ohne Fail + 1 fremder (%d)" % rows.size())
	if rows.size() == 3:
		_ok(str(rows[0].get("player")) == "Rival" and not bool(rows[0].get("is_self")), "Fremder mit 97 % zuerst")
		_ok(str(rows[1].get("player")) == "Tester" and bool(rows[1].get("is_self")), "eigener Name aus Parameter")
		_ok(str(rows[2].get("mode")) == "mania", "Modus-Feld gesetzt")
	_ok(one.size() == 1, "n begrenzt die Zeilen")
