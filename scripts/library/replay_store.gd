class_name ReplayStore
extends RefCounted

## Replays: pro Map+Difficulty wird der letzte Lauf gespeichert — als reine
## Input-Liste [{t, lane, down}] mit exakten Judgement-Zeitstempeln. Die
## Wiedergabe speist dieselben Events zeitgenau wieder in den ManiaCore ein.
##
## Modus: "mania" (Standard, user://replays/<md5>.json, Format unveraendert),
## "trace" (bester Trace-Lauf, user://replays/trace/<md5>.json) oder
## "trace_last" (letzter Trace-Lauf, user://replays/trace/last/<md5>.json).
## Trace-Events wie Mania [t, lane, down], meta.mode = "trace". Alles liegt
## getrennt: ein Trace-Lauf ueberschreibt nie das Mania-Replay derselben Diff.
## Ordner entfernter Modi (v1.44.0) bleiben liegen; unbekannte Replay-Modi
## laden nie (load_key liefert {}), damit sie nie als Mania abgespielt werden.

const DIR := "user://replays"
## Trace (Mania-4K-Wertung, Mania-Events [t, lane, down]) getrennt von Mania.
const MODE_TRACE_BEST := "trace"
const MODE_TRACE_LAST := "trace_last"
## Spielmodi mit eigener Ablage (bester + letzter Lauf); Mania bleibt im alten Ordner.
const OWN_DIR_MODES := ["trace"]


## Replay-Schluessel (= Dateiname ohne .json, auch fuer --clip <md5>).
static func key(osz_path: String, version: String) -> String:
	return ("%s|%s" % [osz_path.get_file(), version]).md5_text()


## Ordner je Modus (Mania bleibt im alten Ordner).
static func dir_for(mode: String = "mania") -> String:
	match mode:
		MODE_TRACE_BEST: return DIR + "/trace"
		MODE_TRACE_LAST: return DIR + "/trace/last"
	return DIR


## Spielmodus hinter einem Replay-Modus: "mania" oder "trace".
static func base_mode(mode: String) -> String:
	return mode.trim_suffix("_last") if mode != "mania" else "mania"


## true fuer "mania" und die Replay-Modi aus OWN_DIR_MODES (bester/letzter Lauf).
static func known_mode(mode: String) -> bool:
	return mode == "mania" or base_mode(mode) in OWN_DIR_MODES


## Replay-Modus fuer den besten bzw. letzten Lauf eines Spielmodus.
static func best_mode_of(game_mode: String) -> String:
	return game_mode if game_mode in OWN_DIR_MODES else "mania"


static func last_mode_of(game_mode: String) -> String:
	return game_mode + "_last" if game_mode in OWN_DIR_MODES else "mania"


static func path_for_key(md5: String, mode: String = "mania") -> String:
	return "%s/%s.json" % [dir_for(mode), md5]


static func _path(osz_path: String, version: String, mode: String = "mania") -> String:
	return path_for_key(key(osz_path, version), mode)


static func exists(osz_path: String, version: String, mode: String = "mania") -> bool:
	return FileAccess.file_exists(_path(osz_path, version, mode))


static func save(osz_path: String, version: String, events: Array, meta: Dictionary,
		mode: String = "mania") -> void:
	if events.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_for(mode)))
	var f := FileAccess.open(_path(osz_path, version, mode), FileAccess.WRITE)
	if f == null:
		return
	var m := meta
	if base_mode(mode) != "mania":
		m = meta.duplicate()
		m["mode"] = base_mode(mode)
	f.store_string(JSON.stringify({ "meta": m, "events": events }))
	f.close()


## Liefert { meta: Dictionary, events: Array } oder {}.
static func load_replay(osz_path: String, version: String, mode: String = "mania") -> Dictionary:
	return load_key(key(osz_path, version), mode)


## Wie load_replay, aber ueber den Schluessel (Clip-Prozess).
static func load_key(md5: String, mode: String = "mania") -> Dictionary:
	if not known_mode(mode):
		return {}
	var path := path_for_key(md5, mode)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary and parsed.has("events"):
		# Replay eines entfernten oder fremden Modus: still ueberspringen.
		var meta = parsed.get("meta", {})
		if meta is Dictionary and not ScoreStore.known_mode(str(meta.get("mode", ""))):
			return {}
		return parsed
	return {}
