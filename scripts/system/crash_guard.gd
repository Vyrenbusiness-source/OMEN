extends Node

## Autoload "CrashGuard": Lauf-Wachmarke, Absturzbericht, Stufen-Selbstheilung.
##
## Wachmarke (user://run_state.cfg): jeder echte Spiellauf traegt beim Start
## started=true/clean=false ein, dazu Phase (Start/Menue/Browser/Laden/Spiel),
## Welt, Renderer, GPU, Treiber und Spielversion. Ein sauberes Ende (Fenster zu,
## get_tree().quit(), Updater-Neustart) setzt clean=true. Findet der naechste
## Start clean=false, endete der letzte Lauf hart: dann
##   - Absturzbericht nach user://crash/<datum>.txt (letzter Zustand + Ende des
##     Godot-Logs aus user://logs),
##   - Hinweis fuers Hauptmenue (scripts/ui/crash_notice.gd),
##   - bei Absturz in Start/Laden/Spiel eine Heilstufe hoeher:
##       1 = Shader-/Pipeline-Cache geleert
##       2 = + einfache Welt (Galaxie) und Texturgrenze 4096
##       3 = + Renderer D3D12 statt Vulkan (Neustart mit --rendering-driver d3d12)
##   - nach 3 sauberen Laeufen in Folge eine Stufe zurueck.
## Die Stufe steht in den Einstellungen und ist dort zuruecksetzbar
## (stage_label(), reset_stage()).
##
## Alle Entscheidungen sind statische Funktionen mit Pfad-Parametern
## (headless testbar: tests/run_crash_guard_tests.gd). Im Editor, headless und
## in Test-/Screenshot-Laeufen schreibt das Autoload keine Wachmarke.

const STATE_PATH := "user://run_state.cfg"
const CRASH_DIR := "user://crash"
const LOG_DIR := "user://logs"
const SHADER_CACHE_DIR := "user://shader_cache"
## Pipeline-Caches von RenderingDevice: user://<api>/pipelines.<geraet>.cache
const PIPELINE_DIRS: Array[String] = ["vulkan", "d3d12", "metal"]

const PHASE_START := "start"
const PHASE_MENU := "menu"
const PHASE_BROWSER := "browser"
const PHASE_LOAD := "load"
const PHASE_GAME := "game"
## Abstuerze in diesen Phasen sind grafik-/ladeverdaechtig: Stufe hoch.
const HEAL_PHASES: Array[String] = [PHASE_START, PHASE_LOAD, PHASE_GAME]

const STAGE_NONE := 0
const STAGE_CACHE := 1
const STAGE_SIMPLE := 2
const STAGE_D3D12 := 3
const STAGE_MAX := 3
## So viele saubere Laeufe in Folge, dann eine Stufe zurueck.
const CLEAN_RUNS_TO_STEP_DOWN := 3
## Texturgrenze ab Stufe 2 (Kantenlaenge in Pixeln).
const SAFE_TEXTURE_SIZE := 4096
## Laden -> Spiel nach so vielen gezeichneten Frames im neuen Spielszene.
const LOAD_FRAMES := 90
## Hoechstens so viel vom alten Log in den Bericht (Bytes vom Ende).
const LOG_TAIL_BYTES := 48000
## Hoechstens so viele Berichte behalten (aelteste fliegen raus).
const MAX_REPORTS := 20

## Szenen -> Phase (Dateiname ohne Pfad). Alles andere: Phase bleibt.
const SCENE_PHASES := {
	"main_menu.tscn": PHASE_MENU,
	"song_select.tscn": PHASE_BROWSER,
	"mp_lobby.tscn": PHASE_MENU,
	"campaign.tscn": PHASE_MENU,
	"mania_3d.tscn": PHASE_GAME,
	"gameplay_3d.tscn": PHASE_GAME,
	"trace.tscn": PHASE_GAME,
	"trace_tutorial.tscn": PHASE_GAME,
	"tutorial.tscn": PHASE_GAME,
}

signal stage_changed
signal report_ready(path: String)

## Aktuelle Heilstufe (0..3), gilt fuer diesen Lauf.
var stage: int = STAGE_NONE
## Saubere Laeufe in Folge seit dem letzten Absturz / der letzten Stufenaenderung.
var clean_runs: int = 0
## Dieser Lauf startete nach einem harten Ende.
var started_after_crash: bool = false
## Pfad des Berichts dieses Starts ("" = keiner).
var report_path: String = ""
## Hinweis im Menue steht noch aus.
var notice_pending: bool = false
## Aktuelle Phase und Welt dieses Laufs.
var phase: String = PHASE_START
var world: String = ""

var _active := false
var _restarting := false
var _load_frames_left := -1
var _info := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not should_guard():
		set_process(false)
		return
	_active = true
	set_process(false)
	var prev := read_state(STATE_PATH)
	var crashed := evaluate_start(prev)
	var prev_stage := int(prev.get("stage", 0))
	var prev_clean := int(prev.get("clean_runs", 0))
	var res := next_stage(prev_stage, prev_clean, crashed, str(prev.get("phase", "")), bool(prev.get("counts", true)))
	stage = res[0]
	clean_runs = res[1]
	notice_pending = bool(prev.get("notice", false))
	if crashed:
		started_after_crash = true
		notice_pending = true
		var local_unix := Time.get_unix_time_from_system() + int(Time.get_time_zone_from_system().get("bias", 0)) * 60
		report_path = write_report(CRASH_DIR, prev, read_last_log(LOG_DIR), local_unix)
		prune_reports(CRASH_DIR, MAX_REPORTS)
		if HEAL_PHASES.has(str(prev.get("phase", ""))):
			clear_render_caches("user://")
	elif prev.has("report") and notice_pending:
		report_path = str(prev.get("report", ""))
	_info = collect_info()
	_save(false)
	var args := restart_args(stage, str(_info.get("driver", "")), OS.get_name(),
		OS.get_cmdline_args(), OS.get_cmdline_user_args())
	if not args.is_empty():
		# Stufe 3: dieser Vulkan-Lauf endet sofort und startet mit D3D12 neu.
		# Zaehlt weder als sauberer Lauf noch als Absturz.
		_restarting = true
		_save(true, false)
		OS.set_restart_on_exit(true, args)
		get_tree().quit.call_deferred()
		return
	get_tree().root.child_entered_tree.connect(_on_root_child)
	if report_path != "":
		report_ready.emit.call_deferred(report_path)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_mark_clean()


func _exit_tree() -> void:
	_mark_clean()


func _process(_delta: float) -> void:
	if _load_frames_left < 0:
		return
	_load_frames_left -= 1
	if _load_frames_left <= 0:
		_load_frames_left = -1
		set_process(false)
		set_phase(PHASE_GAME)


## Wachmarke nur im echten Spielbetrieb: nicht im Editor, nicht headless, nicht
## in Test-/Screenshot-Laeufen (die enden per Timeout = kein Absturz).
func should_guard() -> bool:
	if OS.has_feature("editor") or DisplayServer.get_name() == "headless":
		return false
	return not is_test_run(OS.get_cmdline_args() + OS.get_cmdline_user_args())


static func is_test_run(args: PackedStringArray) -> bool:
	for a in args:
		if a.begins_with("--shot") or a == "--autoplay" or a == "--write-movie" \
				or a == "--clip" or a == "--perf" or a.begins_with("--sim"):
			return true
	return false


# ------------------------------------------------------------------ oeffentlich

## Phase setzen (Spielszenen koennen das selbst tun, sonst erkennt das Autoload
## sie am Szenenwechsel). world: Weltname, "" = unveraendert.
func set_phase(p: String, w: String = "") -> void:
	if w != "":
		world = w
	if p == phase and w == "":
		return
	phase = p
	if p != PHASE_LOAD:
		_load_frames_left = -1
	if _active:
		# VRAM je Phase: zeigt im Bericht, ob der Speicher vor dem Absturz voll lief.
		_info["vram_mb"] = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576)
		_save(false)


## Ab Stufe 2: Welt nur einfach (Galaxie, keine 8192er-Ebenen).
func simple_world() -> bool:
	return stage >= STAGE_SIMPLE


## Texturgrenze in Pixeln (0 = keine Grenze).
func max_texture_size() -> int:
	return texture_limit(stage)


## Kurzer Text fuer die Einstellungen (ueber tr()).
func stage_label() -> String:
	return tr(stage_key(stage))


## Einstellungen: Stufe auf 0, Hinweis weg. Wirkt ab dem naechsten Start.
func reset_stage() -> void:
	if stage == STAGE_NONE and clean_runs == 0:
		return
	stage = STAGE_NONE
	clean_runs = 0
	notice_pending = false
	if _active:
		_save(false)
	stage_changed.emit()


## Hinweis genau einmal abholen (Hauptmenue). Liefert den Berichtspfad oder "".
func take_notice() -> String:
	if not notice_pending:
		return ""
	notice_pending = false
	if _active:
		_save(false)
	return report_path


## Bild fuer Stufe 2 kleiner rechnen (Hauptthread). Liefert dasselbe Bild,
## wenn keine Grenze gilt oder es schon passt.
func fit_image(img: Image) -> Image:
	return limit_image(img, max_texture_size())


# ------------------------------------------------------------- reine Logik

## Lief der vorige Start als echter Lauf und endete nicht sauber?
static func evaluate_start(prev: Dictionary) -> bool:
	return bool(prev.get("started", false)) and not bool(prev.get("clean", true))


## Neue [stufe, saubere_laeufe] aus dem Ende des vorigen Laufs.
## counts=false: voriger Lauf war nur der Neustart auf D3D12 (zaehlt nicht).
static func next_stage(prev_stage: int, prev_clean: int, crashed: bool, crash_phase: String, counts: bool = true) -> Array:
	var s := clampi(prev_stage, STAGE_NONE, STAGE_MAX)
	if crashed:
		if HEAL_PHASES.has(crash_phase):
			return [mini(s + 1, STAGE_MAX), 0]
		return [s, 0]
	if not counts:
		return [s, prev_clean]
	var c := prev_clean + 1
	if s > STAGE_NONE and c >= CLEAN_RUNS_TO_STEP_DOWN:
		return [s - 1, 0]
	return [s, c if s > STAGE_NONE else 0]


static func texture_limit(s: int) -> int:
	return SAFE_TEXTURE_SIZE if s >= STAGE_SIMPLE else 0


## Uebersetzungsschluessel (deutscher Text, translations/crash.csv).
const STAGE_KEYS: Array[String] = [
	"Normal",
	"Stufe 1: Shader-Cache geleert",
	"Stufe 2: einfache Welt, Texturen max. 4096",
	"Stufe 3: Renderer D3D12",
]


static func stage_key(s: int) -> String:
	return STAGE_KEYS[clampi(s, STAGE_NONE, STAGE_MAX)]


## Startzeile fuer den Neustart mit D3D12, leer = kein Neustart noetig.
static func restart_args(s: int, driver: String, os_name: String,
		args: PackedStringArray, user_args: PackedStringArray) -> PackedStringArray:
	if s < STAGE_D3D12 or os_name != "Windows" or driver.to_lower() != "vulkan":
		return PackedStringArray()
	# Schon einmal mit Treiberwahl gestartet (z. B. d3d12 scheiterte beim Start
	# und Godot fiel auf Vulkan zurueck): keine Schleife.
	if args.has("--rendering-driver"):
		return PackedStringArray()
	var out := PackedStringArray()
	for a in args:
		if a == "--":
			break
		out.append(a)
	out.append("--rendering-driver")
	out.append("d3d12")
	if not user_args.is_empty():
		out.append("--")
		out.append_array(user_args)
	return out


static func phase_for_scene(scene_path: String) -> String:
	return str(SCENE_PHASES.get(scene_path.get_file(), ""))


static func phase_label(p: String) -> String:
	match p:
		PHASE_START: return "Start"
		PHASE_MENU: return "Menue"
		PHASE_BROWSER: return "Browser"
		PHASE_LOAD: return "Laden"
		PHASE_GAME: return "Spiel"
	return p if p != "" else "?"


## Bild auf hoechstens max_size Kantenlaenge (Seitenverhaeltnis bleibt).
static func limit_image(img: Image, max_size: int) -> Image:
	if img == null or max_size <= 0:
		return img
	var w := img.get_width()
	var h := img.get_height()
	if w <= max_size and h <= max_size:
		return img
	if img.is_compressed() and img.decompress() != OK:
		return img
	var k := float(max_size) / float(maxi(w, h))
	var had_mips := img.has_mipmaps()
	img.resize(maxi(int(w * k), 1), maxi(int(h * k), 1), Image.INTERPOLATE_LANCZOS)
	if had_mips:
		img.generate_mipmaps()
	return img


# -------------------------------------------------------------- Zustand

static func read_state(path: String) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return {}
	var out := {}
	for sec in cfg.get_sections():
		for k in cfg.get_section_keys(sec):
			out[k] = cfg.get_value(sec, k)
	return out


static func write_state(path: String, d: Dictionary) -> bool:
	var cfg := ConfigFile.new()
	for k in d:
		var sec := "heal" if k in ["stage", "clean_runs", "notice", "report"] else "run"
		cfg.set_value(sec, k, d[k])
	return cfg.save(path) == OK


func _save(clean: bool, counts: bool = true) -> void:
	var d := _info.duplicate()
	d["started"] = true
	d["clean"] = clean
	d["counts"] = counts
	d["phase"] = phase
	d["world"] = world
	d["stage"] = stage
	d["clean_runs"] = clean_runs
	d["notice"] = notice_pending
	d["report"] = report_path
	write_state(STATE_PATH, d)


func _mark_clean() -> void:
	if not _active:
		return
	_active = false
	_save(true, not _restarting)


func _on_root_child(n: Node) -> void:
	var p := phase_for_scene(n.scene_file_path)
	if p == "":
		return
	if p == PHASE_GAME:
		# Spielszene baut sich gerade auf (Welt, Texturen, Shader): erst "Laden".
		set_phase(PHASE_LOAD)
		_load_frames_left = LOAD_FRAMES
		set_process(true)
	else:
		world = ""
		set_phase(p)


## Renderer, GPU, Treiber, Version, Startzeile dieses Laufs.
func collect_info() -> Dictionary:
	var drv := OS.get_video_adapter_driver_info()
	return {
		"started_at": Time.get_datetime_string_from_system(false, true),
		"version": game_version(),
		"os": "%s %s" % [OS.get_name(), OS.get_version()],
		"renderer": RenderingServer.get_current_rendering_method(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"gpu_vendor": RenderingServer.get_video_adapter_vendor(),
		"gpu_api": RenderingServer.get_video_adapter_api_version(),
		"gpu_driver": " ".join(drv) if drv.size() > 0 else "",
		"cpu": OS.get_processor_name(),
		"vram_mb": 0,
		"file_log": bool(ProjectSettings.get_setting("debug/file_logging/enable_file_logging.pc", true)),
		"args": " ".join(OS.get_cmdline_args()),
	}


static func game_version() -> String:
	var s := load("res://scripts/net/updater.gd") as GDScript
	if s != null:
		var v = s.get_script_constant_map().get("CURRENT_VERSION")
		if v != null:
			return str(v)
	return str(ProjectSettings.get_setting("application/config/version", "?"))


# -------------------------------------------------------------- Bericht

static func report_name(unix: float) -> String:
	var d := Time.get_datetime_dict_from_unix_time(int(unix))
	return "%04d-%02d-%02d_%02d-%02d-%02d.txt" % [d.year, d.month, d.day, d.hour, d.minute, d.second]


## Text des Absturzberichts aus dem Zustand des abgestuerzten Laufs.
static func build_report(prev: Dictionary, log_text: String) -> String:
	var lines := PackedStringArray()
	lines.append("OMEN Absturzbericht / crash report")
	lines.append("====================================")
	lines.append("Letzte Phase / last phase: %s" % phase_label(str(prev.get("phase", ""))))
	var w := str(prev.get("world", ""))
	lines.append("Welt / world: %s" % (w if w != "" else "-"))
	lines.append("Lauf gestartet / run started: %s" % str(prev.get("started_at", "?")))
	lines.append("Spielversion / version: %s" % str(prev.get("version", "?")))
	lines.append("Renderer: %s / %s" % [str(prev.get("renderer", "?")), str(prev.get("driver", "?"))])
	lines.append("GPU: %s (%s), API %s" % [str(prev.get("gpu", "?")), str(prev.get("gpu_vendor", "?")), str(prev.get("gpu_api", "?"))])
	lines.append("GPU-Treiber / driver: %s" % str(prev.get("gpu_driver", "?")))
	lines.append("CPU: %s" % str(prev.get("cpu", "?")))
	lines.append("OS: %s" % str(prev.get("os", "?")))
	lines.append("VRAM belegt / used (letzte Phase): %d MB" % int(prev.get("vram_mb", 0)))
	lines.append("Datei-Log / file logging: %s" % ("an" if bool(prev.get("file_log", true)) else "AUS"))
	lines.append("Heilstufe / safe stage: %d" % int(prev.get("stage", 0)))
	lines.append("Startzeile / args: %s" % str(prev.get("args", "")))
	lines.append("")
	lines.append("--- Godot-Log (Ende) ---")
	lines.append(log_text if log_text != "" else "(kein Log gefunden / no log found)")
	return "\n".join(lines) + "\n"


## Bericht schreiben, liefert den Pfad ("" bei Fehler).
static func write_report(dir: String, prev: Dictionary, log_text: String, unix: float) -> String:
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(report_name(unix))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(build_report(prev, log_text))
	f.close()
	return path


## Juengstes rotiertes Log des vorigen Laufs (Godot benennt godot.log beim
## Start in godot<zeit>.log um; godot.log ist schon der aktuelle Lauf).
## Ohne rotiertes Log: godot.log selbst (Logging-Rotation aus).
static func read_last_log(dir: String, tail_bytes: int = LOG_TAIL_BYTES) -> String:
	var d := DirAccess.open(dir)
	if d == null:
		return ""
	var best := ""
	var best_t := -1
	for fn in d.get_files():
		if not fn.ends_with(".log") or fn == "godot.log":
			continue
		var t := FileAccess.get_modified_time(dir.path_join(fn))
		# Gleiche Sekunde: Name entscheidet (Godot haengt die Startzeit an).
		if t > best_t or (t == best_t and fn > best):
			best_t = t
			best = fn
	if best == "":
		if not FileAccess.file_exists(dir.path_join("godot.log")):
			return ""
		best = "godot.log"
	var f := FileAccess.open(dir.path_join(best), FileAccess.READ)
	if f == null:
		return ""
	var n := f.get_length()
	if n > tail_bytes:
		f.seek(n - tail_bytes)
	var txt := f.get_buffer(mini(n, tail_bytes)).get_string_from_utf8()
	f.close()
	return "[%s]\n%s" % [best, txt]


## Aelteste Berichte loeschen, bis hoechstens keep uebrig sind.
static func prune_reports(dir: String, keep: int) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	var files: Array = []
	for fn in d.get_files():
		if fn.ends_with(".txt"):
			files.append(fn)
	files.sort()
	while files.size() > keep:
		DirAccess.remove_absolute(dir.path_join(files.pop_front()))


## Neuester Bericht ("" = keiner).
static func latest_report(dir: String) -> String:
	var d := DirAccess.open(dir)
	if d == null:
		return ""
	var files: Array = []
	for fn in d.get_files():
		if fn.ends_with(".txt"):
			files.append(fn)
	if files.is_empty():
		return ""
	files.sort()
	return dir.path_join(files.back())


# -------------------------------------------------------------- Caches

## Stufe 1: Godots Shader-Cache (user://shader_cache) und die Pipeline-Caches
## (user://vulkan|d3d12/pipelines.*.cache) loeschen. Liefert die Zahl der
## geloeschten Dateien. Godot prueft den Pipeline-Cache beim Laden selbst
## (Kopf + Hash); ein Lauf, der neue Pipelines baut, schreibt ihn beim Beenden
## neu - darum zusaetzlich im Bericht: AMD-Treiber-Shadercache leeren lassen.
static func clear_render_caches(user_root: String) -> int:
	var n := _remove_tree(user_root.path_join(SHADER_CACHE_DIR.trim_prefix("user://")))
	for api in PIPELINE_DIRS:
		var dir := user_root.path_join(api)
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for fn in d.get_files():
			if fn.begins_with("pipelines") and fn.ends_with(".cache"):
				if DirAccess.remove_absolute(dir.path_join(fn)) == OK:
					n += 1
	return n


static func _remove_tree(dir: String) -> int:
	var d := DirAccess.open(dir)
	if d == null:
		return 0
	var n := 0
	for sub in d.get_directories():
		n += _remove_tree(dir.path_join(sub))
	for fn in d.get_files():
		if DirAccess.remove_absolute(dir.path_join(fn)) == OK:
			n += 1
	DirAccess.remove_absolute(dir)
	return n
