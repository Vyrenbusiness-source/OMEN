extends SceneTree

## Headless-Tests fuer BrowserSort.
## Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_browser_sort_tests.gd

var _failed := 0


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		_failed += 1


func _mk(title: String, artist: String, mapper: String, diffs: Array, extra: Dictionary = {}) -> Dictionary:
	var s := {"title": title, "artist": artist, "mapper": mapper, "diffs": diffs,
		"osz_path": "user://" + title + ".osz"}
	s.merge(extra, true)
	return s


func _d(version: String, stars: float, notes: int = 100, extra: Dictionary = {}) -> Dictionary:
	var d := {"version": version, "stars": stars, "notes": notes, "mode": 3, "keys": 4}
	d.merge(extra, true)
	return d


func _titles(entries: Array) -> Array:
	var out: Array = []
	for e in entries:
		out.append(e["set"]["title"])
	return out


func _initialize() -> void:
	print("=== BrowserSort-Tests ===")
	_test_helpers()
	_test_sort_diffs()
	_test_sort_sets_text()
	_test_sort_sets_numeric()
	_test_missing_and_stability()
	_test_difficulty_split()
	_test_groups()
	_test_speed()
	print("=== ", "OK" if _failed == 0 else "%d FEHLER" % _failed, " ===")
	quit(1 if _failed > 0 else 0)


func _test_helpers() -> void:
	print("-- Hilfen")
	_check(BrowserSort.natural_key("Song 2") < BrowserSort.natural_key("Song 10"), "natural: 2 vor 10")
	_check(BrowserSort.natural_key("ÄPFEL") == BrowserSort.natural_key("apfel") or
		BrowserSort.natural_key("Äpfel") == "apfel", "natural: Umlaut/Gross egal")
	_check(BrowserSort.natural_key("Café") == BrowserSort.natural_key("cafe"), "natural: Akzent egal")
	_check(BrowserSort.natural_key("Straße") == "strasse", "natural: ß")
	_check(BrowserSort.star_bucket(0.0) == 0 and BrowserSort.star_bucket(0.99) == 0, "bucket 0-1")
	_check(BrowserSort.star_bucket(1.0) == 1 and BrowserSort.star_bucket(9.5) == 9, "bucket 1, 9")
	_check(BrowserSort.star_bucket(10.0) == 10 and BrowserSort.star_bucket(14.0) == 10, "bucket 10+")
	_check(BrowserSort.star_bucket(-1.0) == -1, "bucket unbekannt")
	_check(BrowserSort.star_bucket_title(3) == "3-4" and BrowserSort.star_bucket_title(10) == "10+", "bucket-Titel")
	_check(BrowserSort.rank_order("SS") < BrowserSort.rank_order("S") and
		BrowserSort.rank_order("S") < BrowserSort.rank_order("A") and
		BrowserSort.rank_order("A") < BrowserSort.rank_order("B") and
		BrowserSort.rank_order("B") < BrowserSort.rank_order("C") and
		BrowserSort.rank_order("C") < BrowserSort.rank_order("D") and
		BrowserSort.rank_order("D") < BrowserSort.rank_order(""), "rank_order SS..D, ungespielt")
	_check(BrowserSort.rank_order("sh") == 1 and BrowserSort.rank_order("X") == 0, "rank Aliase")


func _test_sort_diffs() -> void:
	print("-- sort_diffs")
	var diffs := [_d("Hard", 3.0, 300), _d("Easy", 1.0, 100), _d("Alt", 3.0, 200),
		_d("Zed", 3.0, 200), _d("Seven", 0.5, 50, {"keys": 7}), _d("Five", 4.5, 10, {"keys": 5}),
		_d("Four", 6.0, 10)]
	var s := BrowserSort.sort_diffs(diffs)
	var names: Array = []
	for d in s:
		names.append(d["version"])
	_check(names == ["Easy", "Alt", "Zed", "Hard", "Four", "Five", "Seven"],
		"4K vor 5K vor 7K; je Gruppe Sterne, Noten, Name: " + str(names))
	_check(diffs[0]["version"] == "Hard", "Eingabe unveraendert")
	# Gleichstand komplett: stabil
	var tie := [_d("Same", 2.0, 10), _d("same", 2.0, 10)]
	var t := BrowserSort.sort_diffs(tie)
	_check(t[0]["version"] == "Same" and t[1]["version"] == "same", "Gleichstand stabil")
	# fehlende Felder
	var miss := BrowserSort.sort_diffs([{"version": "x"}, {"version": "a", "stars": 2.0}, {}])
	_check(miss.size() == 3 and miss[0]["version"] == "a", "fehlende Felder: Sterne zuerst")
	_check(BrowserSort.sort_diffs([]).is_empty(), "leer")
	# Nicht-Mania vor Mania
	var mix := BrowserSort.sort_diffs([_d("M", 1.0), {"version": "Std", "stars": 5.0, "mode": 0}])
	_check(mix[0]["version"] == "Std", "Nicht-Mania zuerst")


func _sample() -> Array:
	return [
		_mk("Zebra 10", "Beta", "mapC", [_d("a", 2.0, 10, {"bpm": 120, "duration_ms": 90000, "date_added": 300, "last_played": 50, "rank": "A"})]),
		_mk("apfel", "Äther", "Mapa", [_d("a", 5.0, 10, {"bpm": 200, "duration_ms": 60000, "date_added": 100, "last_played": 500, "rank": "S"})]),
		_mk("Zebra 2", "alpha", "mapB", [_d("a", 3.0, 10, {"bpm": 90, "duration_ms": 120000, "date_added": 200, "last_played": 100, "rank": "B"})]),
		_mk("Ärger", "Cee", "mapd", [_d("a", 1.0, 10, {"bpm": 150, "duration_ms": 30000, "date_added": 400, "rank": "SS"}),
			_d("b", 6.0, 10, {"bpm": 160, "duration_ms": 31000})]),
	]


func _test_sort_sets_text() -> void:
	print("-- sort_sets Text")
	var sets := _sample()
	var t := _titles(BrowserSort.sort_sets(sets, "title"))
	_check(t == ["apfel", "Ärger", "Zebra 2", "Zebra 10"], "title natuerlich+Umlaut: " + str(t))
	t = _titles(BrowserSort.sort_sets(sets, "title", true))
	_check(t == ["Zebra 10", "Zebra 2", "Ärger", "apfel"], "title absteigend: " + str(t))
	t = _titles(BrowserSort.sort_sets(sets, "artist"))
	_check(t == ["Zebra 2", "apfel", "Zebra 10", "Ärger"], "artist: " + str(t))
	t = _titles(BrowserSort.sort_sets(sets, "mapper"))
	_check(t == ["apfel", "Zebra 2", "Zebra 10", "Ärger"], "mapper (Gross/Klein egal): " + str(t))
	var e: Array = BrowserSort.sort_sets(sets, "title")
	_check(e[0].has("set") and int(e[0]["diff_index"]) == -1 and e.size() == 4, "ein Eintrag je Set")


func _test_sort_sets_numeric() -> void:
	print("-- sort_sets numerisch")
	var sets := _sample()
	_check(_titles(BrowserSort.sort_sets(sets, "bpm")) == ["Zebra 2", "Zebra 10", "Ärger", "apfel"], "bpm aufsteigend (Max der Diffs)")
	_check(_titles(BrowserSort.sort_sets(sets, "bpm", true)) == ["apfel", "Ärger", "Zebra 10", "Zebra 2"], "bpm absteigend")
	_check(_titles(BrowserSort.sort_sets(sets, "length")) == ["Ärger", "apfel", "Zebra 10", "Zebra 2"], "length")
	_check(_titles(BrowserSort.sort_sets(sets, "date_added")) == ["apfel", "Zebra 2", "Zebra 10", "Ärger"], "date_added")
	_check(_titles(BrowserSort.sort_sets(sets, "date_added", true)) == ["Ärger", "Zebra 10", "Zebra 2", "apfel"], "date_added absteigend")
	# last_played: Ärger fehlt -> immer hinten
	_check(_titles(BrowserSort.sort_sets(sets, "last_played")) == ["Zebra 10", "Zebra 2", "apfel", "Ärger"], "last_played, fehlend hinten")
	_check(_titles(BrowserSort.sort_sets(sets, "last_played", true)) == ["apfel", "Zebra 2", "Zebra 10", "Ärger"], "last_played absteigend, fehlend hinten")
	# rank: bester Rang je Set (Ärger = SS)
	_check(_titles(BrowserSort.sort_sets(sets, "rank")) == ["Ärger", "apfel", "Zebra 10", "Zebra 2"] or
		_titles(BrowserSort.sort_sets(sets, "rank")) == ["Ärger", "apfel", "Zebra 2", "Zebra 10"], "rank")
	_check(_titles(BrowserSort.sort_sets(sets, "rank")) == ["Ärger", "apfel", "Zebra 10", "Zebra 2"], "rank SS,S,A,B")
	# Datum als String
	var ds := [_mk("late", "x", "m", [{"date_added": "2024-05-02T10:00:00"}]),
		_mk("early", "x", "m", [{"date_added": "2023-01-01T00:00:00"}])]
	_check(_titles(BrowserSort.sort_sets(ds, "date_added")) == ["early", "late"], "Datum als String")


func _test_missing_and_stability() -> void:
	print("-- fehlende Felder, Stabilitaet")
	var sets := [_mk("b", "", "", []), _mk("a", "", "", [{}]), {"title": "c"}, {}]
	for key in ["title", "artist", "mapper", "bpm", "length", "difficulty", "date_added", "last_played", "rank"]:
		for desc in [false, true]:
			var r := BrowserSort.sort_sets(sets, key, desc)
			_check(r.size() >= 4, "%s desc=%s: kein Absturz, %d Eintraege" % [key, desc, r.size()])
	# Gleichstand: Eingabereihenfolge, auch absteigend
	var tie: Array = []
	for i in 6:
		tie.append(_mk("T%d" % i, "same", "same", [_d("a", 2.0, 10, {"bpm": 100})]))
	for key in ["artist", "mapper", "bpm", "difficulty"]:
		for desc in [false, true]:
			var names := _titles(BrowserSort.sort_sets(tie, key, desc))
			_check(names == ["T0", "T1", "T2", "T3", "T4", "T5"], "stabil %s desc=%s" % [key, desc])
	# Titel mit Gleichstand + Gross/Klein
	var cs := [_mk("Abc", "x", "m", []), _mk("abc", "x", "m", []), _mk("ABC", "x", "m", [])]
	_check(_titles(BrowserSort.sort_sets(cs, "title")) == ["Abc", "abc", "ABC"], "Gross/Klein gleich -> stabil")
	# Fehlendes Feld steht hinten (auch absteigend), Reihenfolge unter Fehlenden stabil
	var mixed := [_mk("m1", "", "", []), _mk("has2", "B", "", []), _mk("m2", "", "", []), _mk("has1", "A", "", [])]
	_check(_titles(BrowserSort.sort_sets(mixed, "artist")) == ["has1", "has2", "m1", "m2"], "fehlend hinten aufsteigend")
	_check(_titles(BrowserSort.sort_sets(mixed, "artist", true)) == ["has2", "has1", "m1", "m2"], "fehlend hinten absteigend")
	_check(BrowserSort.sort_sets([], "title").is_empty(), "leere Eingabe")


func _test_difficulty_split() -> void:
	print("-- difficulty: jede Diff einzeln")
	var sets := _sample()
	var r := BrowserSort.sort_sets(sets, "difficulty")
	_check(r.size() == 5, "5 Eintraege (4 Sets, 5 Diffs): %d" % r.size())
	var stars: Array = []
	for e in r:
		stars.append(e["set"]["diffs"][e["diff_index"]]["stars"])
	_check(stars == [1.0, 2.0, 3.0, 5.0, 6.0], "nach Sternen: " + str(stars))
	_check(r[0]["set"]["title"] == "Ärger" and r[0]["diff_index"] == 0 and
		r[4]["set"]["title"] == "Ärger" and r[4]["diff_index"] == 1, "Set kommt zweimal vor, richtiger diff_index")
	var d := BrowserSort.sort_sets(sets, "difficulty", true)
	_check(d[0]["diff_index"] == 1 and d[0]["set"]["title"] == "Ärger", "absteigend")


func _test_groups() -> void:
	print("-- group")
	var sets := _sample()
	var by_title := BrowserSort.sort_sets(sets, "title")
	var g := BrowserSort.group(by_title, "none")
	_check(g.size() == 1 and g[0]["entries"].size() == 4, "none: eine Gruppe")
	# artist: Äther->A, alpha->A, Beta->B, Cee->C
	g = BrowserSort.group(BrowserSort.sort_sets(sets, "artist"), "artist")
	var titles: Array = []
	for x in g:
		titles.append(x["title"])
	_check(titles == ["A", "B", "C"], "artist Buchstaben: " + str(titles))
	_check(g[0]["entries"].size() == 2 and _titles(g[0]["entries"]) == ["Zebra 2", "apfel"], "artist A behaelt Sortierung")
	var odd := [_mk("1", "7 Seconds", "", []), _mk("2", "(Hidden)", "", []), _mk("3", "!!!", "", []), _mk("4", "Zed", "", [])]
	g = BrowserSort.group(BrowserSort.sort_sets(odd, "title"), "artist")
	titles = []
	for x in g:
		titles.append(x["title"])
	_check(titles == ["0-9", "H", "Z", "#"], "artist: Ziffern vor Buchstaben, # zuletzt: " + str(titles))
	# difficulty (je Diff)
	g = BrowserSort.group(BrowserSort.sort_sets(sets, "difficulty"), "difficulty")
	titles = []
	for x in g:
		titles.append(x["title"])
	_check(titles == ["1-2", "2-3", "3-4", "5-6", "6-7"], "Stern-Stufen: " + str(titles))
	# difficulty je Set (diff_index -1 -> max Sterne), 10+
	var hi := [_mk("hi", "a", "m", [_d("x", 11.2)]), _mk("lo", "a", "m", [_d("x", 0.4)]), _mk("none", "a", "m", [{}])]
	g = BrowserSort.group(BrowserSort.sort_sets(hi, "title"), "difficulty")
	titles = []
	for x in g:
		titles.append(x["title"])
	_check(titles == ["0-1", "10+", "?"], "0-1, 10+, unbekannt zuletzt: " + str(titles))
	# keys
	var ks := [_mk("k7", "a", "m", [_d("x", 1.0, 1, {"keys": 7})]),
		_mk("k4", "a", "m", [_d("x", 1.0)]),
		_mk("k47", "a", "m", [_d("x", 1.0), _d("y", 2.0, 1, {"keys": 7})]),
		_mk("std", "a", "m", [{"version": "s", "stars": 2.0, "mode": 0}])]
	g = BrowserSort.group(BrowserSort.sort_sets(ks, "title"), "keys")
	titles = []
	for x in g:
		titles.append(x["title"])
	_check(titles == ["4K", "7K", "Andere"], "keys: " + str(titles))
	_check(_titles(g[0]["entries"]) == ["k4", "k47"] and _titles(g[1]["entries"]) == ["k47", "k7"] or
		_titles(g[1]["entries"]) == ["k7", "k47"], "k47 in 4K und 7K")
	# rank (je Diff)
	var rs := [_mk("r1", "a", "m", [_d("x", 1.0, 1, {"rank": "B"})]), _mk("r2", "a", "m", [_d("x", 1.0, 1, {"rank": "SS"})]),
		_mk("r3", "a", "m", [_d("x", 1.0)]), _mk("r4", "a", "m", [_d("x", 1.0, 1, {"rank": "D"})])]
	g = BrowserSort.group(BrowserSort.sort_sets(rs, "title"), "rank")
	titles = []
	for x in g:
		titles.append(x["title"])
	_check(titles == ["SS", "B", "D", "Ungespielt"], "rank-Gruppen: " + str(titles))
	# collections
	var cols := {"Zeta": ["user://Zebra 2.osz", "user://apfel.osz"], "alpha": ["user://apfel.osz"]}
	g = BrowserSort.group(BrowserSort.sort_sets(sets, "title"), "collections", cols)
	titles = []
	for x in g:
		titles.append(x["title"])
	_check(titles == ["alpha", "Zeta", "Keine Sammlung"], "collections: " + str(titles))
	_check(_titles(g[1]["entries"]) == ["apfel", "Zebra 2"] and _titles(g[2]["entries"]) == ["Ärger", "Zebra 10"], "collections Inhalt")
	g = BrowserSort.group(BrowserSort.sort_sets(sets, "title"), "collections")
	_check(g.size() == 1 and g[0]["title"] == "Keine Sammlung", "collections ohne Parameter")
	_check(BrowserSort.group([], "artist").is_empty(), "leere Eingabe")


func _test_speed() -> void:
	print("-- Tempo")
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var sets: Array = []
	var ranks := ["", "", "D", "C", "B", "A", "S", "SS"]
	for i in 5000:
		var diffs: Array = []
		for j in 5:
			diffs.append({"version": "d%d" % j, "stars": rng.randf_range(0.5, 9.0), "notes": rng.randi_range(50, 2000),
				"mode": 3, "keys": 4 + rng.randi() % 4, "bpm": rng.randi_range(80, 240),
				"duration_ms": rng.randi_range(30000, 300000), "date_added": rng.randi_range(1, 2000000000),
				"last_played": rng.randi_range(0, 2000000000), "rank": ranks[rng.randi() % ranks.size()]})
		sets.append({"title": "Song %d Ärger %d" % [rng.randi() % 3000, i], "artist": "Artist %d" % (rng.randi() % 800),
			"mapper": "Mapper %d" % (rng.randi() % 300), "osz_path": "x%d" % i, "diffs": diffs})
	var worst := 0.0
	for key in ["title", "artist", "mapper", "bpm", "length", "difficulty", "date_added", "last_played", "rank"]:
		var t0 := Time.get_ticks_usec()
		var r := BrowserSort.sort_sets(sets, key, true)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		print("  sort_sets %-11s 5000x5: %7.2f ms (%d Eintraege)" % [key, ms, r.size()])
		if key != "difficulty":
			worst = maxf(worst, ms)
	var t1 := Time.get_ticks_usec()
	var sorted_diffs := 0
	for s in sets:
		sorted_diffs += BrowserSort.sort_diffs(s["diffs"]).size()
	var dms := (Time.get_ticks_usec() - t1) / 1000.0
	print("  sort_diffs alle 5000 Sets: %7.2f ms (%d Diffs)" % [dms, sorted_diffs])
	var t2 := Time.get_ticks_usec()
	var gr := BrowserSort.group(BrowserSort.sort_sets(sets, "difficulty"), "difficulty")
	print("  difficulty + group:        %7.2f ms (%d Gruppen)" % [(Time.get_ticks_usec() - t2) / 1000.0, gr.size()])
	_check(worst < 30.0, "5000 Sets x 5 Diffs je Key < 30 ms (schlechtester: %.2f ms)" % worst)
