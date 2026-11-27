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
	print("=== %d ok, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


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


func _rows() -> Array:
	return [
		{"i": 0, "stars": 3.0, "last": "", "plays": 0, "mtime": 100},
		{"i": 1, "stars": 5.0, "last": "2026-11-06T09:00:00", "plays": 2, "mtime": 300},
		{"i": 2, "stars": 1.0, "last": "2026-11-07T12:00:00", "plays": 7, "mtime": 200},
		{"i": 3, "stars": 3.0, "last": "", "plays": 2, "mtime": 300},
	]


func _order(rows: Array) -> Array:
	return rows.map(func(r): return int(r["i"]))


func _test_sort() -> void:
	var r := _rows()
	SS.sort_rows(r, SS.SORT_TITLE)
	_ok(_order(r) == [0, 1, 2, 3], "Titel: Bibliotheks-Reihenfolge")
	r = _rows()
	SS.sort_rows(r, SS.SORT_STARS_UP)
	_ok(_order(r) == [2, 0, 3, 1], "Sterne aufsteigend, Gleichstand stabil (%s)" % str(_order(r)))
	r = _rows()
	SS.sort_rows(r, SS.SORT_STARS_DOWN)
	_ok(_order(r) == [1, 0, 3, 2], "Sterne absteigend (%s)" % str(_order(r)))
	r = _rows()
	SS.sort_rows(r, SS.SORT_RECENT)
	_ok(_order(r) == [2, 1, 0, 3], "Zuletzt gespielt, ungespielte hinten (%s)" % str(_order(r)))
	r = _rows()
	SS.sort_rows(r, SS.SORT_DOWNLOADED)
	_ok(_order(r) == [1, 3, 2, 0], "Zuletzt heruntergeladen (%s)" % str(_order(r)))
	r = _rows()
	SS.sort_rows(r, SS.SORT_MOST_PLAYED)
	_ok(_order(r) == [2, 1, 3, 0], "Meistgespielt (%s)" % str(_order(r)))


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
		"trace": {"sort": SS.SORT_MOST_PLAYED, "best": SS.BEST_WITH, "grades": ["SS"]}})
	var path := "user://test_tmp/browser_filter_state.cfg"
	cfg.save(path)
	var back := ConfigFile.new()
	back.load(path)
	var mfs: Dictionary = back.get_value("browser", "mode_filters", {})
	var m: Dictionary = SS.sanitize_mode_filter(mfs.get("mania", {}))
	var o: Dictionary = SS.sanitize_mode_filter(mfs.get("trace", {}))
	_ok(m["sort"] == SS.SORT_RECENT and m["best"] == SS.BEST_WITHOUT, "Mania-Filter nach Neustart")
	_ok(o["sort"] == SS.SORT_MOST_PLAYED and o["grades"] == ["SS"], "Trace-Filter nach Neustart")
	DirAccess.remove_absolute(path)


## Mania + Trace: Index und Filter je Modus getrennt.
func _test_modes() -> void:
	var cfg := _fake_cfg()
	_ok(SS.build_score_index(cfg, "trace").size() == 1 and SS.build_score_index(cfg, "").size() == 3, "Trace/Mania-Index getrennt")
	_ok(SS.PLAY_MODES == ["mania", "trace"], "Browser kennt Mania und Trace")
	_ok(SS.PLAY_MODES == Array(ScoreStore.MODES), "Browser-Modi = ScoreStore.MODES")
	var mf := {}
	for m in SS.PLAY_MODES:
		mf[m] = SS.sanitize_mode_filter({"sort": SS.SORT_RECENT if m == "trace" else SS.SORT_MOST_PLAYED, "grades": ["S"] if m == "trace" else []})
	_ok(mf["trace"]["sort"] == SS.SORT_RECENT and mf["trace"]["grades"] == ["S"] and mf["mania"]["grades"] == []
		and mf["mania"]["sort"] == SS.SORT_MOST_PLAYED, "Modus-Filter getrennt")


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
		SS.sort_rows(rows, SS.SORT_STARS_DOWN)
		var first: MapSet = rows[0].ms
		_ok(first == (ms2 if mode == "mania" else ms), "Sortierung Sterne absteigend (%s)" % mode)
	b.free()
