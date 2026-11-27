class_name CrashNotice
extends PanelContainer

## Kleiner Hinweis im Hauptmenue nach einem harten Ende (CrashGuard).
## Unten links, kein Modal: Spielen geht sofort weiter. Knoepfe:
## "Bericht kopieren" (Zwischenablage), "Ordner öffnen" (user://crash), "Schließen".
##
## Einbau im Hauptmenue (eine Zeile in _ready):
##   CrashNotice.show_if_pending(self)

const TR_CSV := "res://translations/crash.%s.translation"
const GUARD_NODE := "CrashGuard"

var report_path := ""
var stage := 0
var _copy_btn: Button


## Hinweis anhaengen, falls CrashGuard einen aussteht. Liefert ihn oder null.
static func show_if_pending(parent: Control) -> CrashNotice:
	# Autoload-Name als Wert: CrashGuard ist erst nach dem Einbau in project.godot da.
	var g := parent.get_tree().root.get_node_or_null(NodePath(GUARD_NODE))
	if g == null:
		return null
	var path: String = g.take_notice()
	if path == "":
		return null
	var n := CrashNotice.new()
	n.report_path = path
	n.stage = int(g.stage)
	parent.add_child(n)
	return n


## crash.csv-Uebersetzungen nachladen, falls project.godot sie (noch) nicht
## listet. Ohne sie zeigt tr() den deutschen Schluessel (Fallback de).
static var _tr_added := false


static func ensure_translations() -> void:
	if _tr_added:
		return
	_tr_added = true
	var listed: PackedStringArray = ProjectSettings.get_setting("internationalization/locale/translations", PackedStringArray())
	for loc in ["de", "en"]:
		var p := TR_CSV % loc
		if listed.has(p) or not ResourceLoader.exists(p):
			continue
		var t := load(p) as Translation
		if t != null:
			TranslationServer.add_translation(t)


func _ready() -> void:
	ensure_translations()
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_left = 24
	offset_bottom = -24
	custom_minimum_size = Vector2(420, 0)
	var sb := UiTheme.glass_box(10, 0.92, 0.2)
	sb.border_width_left = 3
	sb.border_color = UiTheme.BAD
	sb.content_margin_left = 18
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	add_theme_stylebox_override("panel", sb)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)

	var head := Label.new()
	head.text = tr("Das Spiel wurde beim letzten Mal nicht sauber beendet.")
	head.add_theme_font_override("font", UiTheme.heading_font(0))
	head.add_theme_color_override("font_color", UiTheme.TEXT)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(head)

	var body := Label.new()
	body.text = tr("Ein Bericht liegt im Absturz-Ordner. Schick ihn uns, wenn es wieder passiert.")
	body.add_theme_color_override("font_color", UiTheme.DIM)
	body.add_theme_font_size_override("font_size", 14)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(body)

	if stage > 0:
		var st := Label.new()
		var keys: Array = load("res://scripts/system/crash_guard.gd").STAGE_KEYS
		st.text = "%s %s" % [tr("OMEN startet vorsichtiger:"), tr(keys[clampi(stage, 0, keys.size() - 1)])]
		st.add_theme_color_override("font_color", UiTheme.ACCENT)
		st.add_theme_font_size_override("font_size", 14)
		st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(st)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	_copy_btn = Button.new()
	_copy_btn.text = tr("Bericht kopieren")
	UiTheme.style_button(_copy_btn, true, 8)
	_copy_btn.pressed.connect(_copy)
	row.add_child(_copy_btn)
	var open := Button.new()
	open.text = tr("Ordner öffnen")
	UiTheme.style_ghost_button(open, 8)
	open.pressed.connect(_open_folder)
	row.add_child(open)
	var close := Button.new()
	close.text = tr("Schließen")
	UiTheme.style_ghost_button(close, 8)
	close.pressed.connect(queue_free)
	row.add_child(close)


func _copy() -> void:
	DisplayServer.clipboard_set(report_text(report_path))
	_copy_btn.text = tr("Kopiert")


func _open_folder() -> void:
	OS.shell_open(ProjectSettings.globalize_path(report_path.get_base_dir() if report_path != "" else "user://crash"))


static func report_text(path: String) -> String:
	if path == "" or not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)
