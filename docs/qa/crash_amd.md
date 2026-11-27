# Absturz auf Radeon RX 9070 + Ryzen 7 7800X3D

Nutzer-Meldung: OMEN stuerzt ab. Windows, aktueller AMD-Treiber. Es gibt kein Log
und keinen bekannten Zeitpunkt. Ohne Log laesst sich die Ursache nicht beweisen. Darum
macht dieser Stand zwei Dinge: Er grenzt die Ursachen im Code ein, und er macht den
naechsten Absturz diagnostizierbar und selbstheilend.

## Was neu ist

| Teil | Datei |
|---|---|
| Wachmarke, Bericht, Heilstufen (Autoload `CrashGuard`) | `scripts/system/crash_guard.gd` |
| Hinweis im Hauptmenue (Bericht kopieren, Ordner oeffnen) | `scripts/ui/crash_notice.gd` |
| Texte en+de | `translations/crash.csv` |
| Tests (headless, rund 100 Pruefungen) | `tests/run_crash_guard_tests.gd` |

### Wachmarke `user://run_state.cfg`
- `[run]`: `started`, `clean`, `phase` (start/menu/browser/load/game), `world`, `renderer`,
  `driver`, `gpu`, `gpu_vendor`, `gpu_api`, `gpu_driver` (Name + Version aus
  `OS.get_video_adapter_driver_info()`), `cpu`, `os`, `version`, `vram_mb` (VRAM beim
  letzten Phasenwechsel), `file_log`, `args`, `started_at`.
- `[heal]`: `stage`, `clean_runs`, `notice`, `report`.
- Die Phase kommt automatisch aus dem Szenenwechsel (`root.child_entered_tree`, also vor
  `_ready` der neuen Szene). Eine Spielszene ist zuerst "Laden" und nach 90 Frames "Spiel".
  Spielszenen koennen die Welt selbst melden: `CrashGuard.set_phase("game", welt)`.
- Im Editor, headless und bei `--shot*`, `--autoplay`, `--write-movie`, `--clip`, `--perf`,
  `--sim*` schreibt das Spiel keine Wachmarke.

### Absturzbericht
Der naechste Start nach einem unsauberen Ende schreibt `user://crash/JJJJ-MM-TT_hh-mm-ss.txt`
(Ortszeit, hoechstens 20 Berichte). Inhalt: letzte Phase, Welt, Version, Renderer/Treiber,
GPU, GPU-Treiber, CPU, OS, VRAM, Heilstufe, Startzeile. Dazu kommt das Ende (48 KB) des
Godot-Logs des abgestuerzten Laufs: das neueste rotierte `user://logs/godot<zeit>.log`.
Der Ordner liegt bei `%APPDATA%\Godot\app_userdata\TETHRA\crash` (custom_user_dir bleibt
TETHRA, damit alte Installationen nichts verlieren).

### Heilstufen
Ein Absturz in Phase **Start, Laden oder Spiel** hebt die Stufe um 1 (hoechstens 3).
Ein Absturz in Menue oder Browser aendert die Stufe nicht, bricht aber die Serie sauberer
Laeufe ab. Nach **3 sauberen Laeufen in Folge** geht es eine Stufe zurueck.

| Stufe | Wirkung |
|---|---|
| 1 | Shader-Cache `user://shader_cache` und die Pipeline-Caches `user://vulkan|d3d12/pipelines.*.cache` werden geloescht (bei jedem Absturz in Start/Laden/Spiel). |
| 2 | dazu `simple_world()` = true (Galaxie statt 8192er-Welt) und `max_texture_size()` = 4096 (`fit_image()`) |
| 3 | dazu Neustart mit `--rendering-driver d3d12`, wenn der Lauf auf Windows mit Vulkan startet |

Schutz gegen Schleifen: Der Vulkan-Lauf, der nur auf D3D12 neu startet, zaehlt weder als
sauberer Lauf noch als Absturz. Steht `--rendering-driver` schon in der Startzeile (D3D12
scheiterte und Godot fiel auf Vulkan zurueck), startet das Spiel nicht noch einmal neu.
Faellt GpuGuard auf OpenGL zurueck, startet es ebenfalls nicht neu.

## Befunde (Schritt 1)

### Renderer-Einstellungen (project.godot, nur gelesen)
- Forward+ (Vulkan auf Windows), `rendering_device/fallback_to_opengl3=true`.
- `msaa_2d=3` und `msaa_3d=3` (8x) sind Projekt-Standard. `Settings` setzt das zur Laufzeit
  nach `graphics_quality` (Standard 2 = 4x, siehe GPU-Guard-Tests). Kein Absturzgrund,
  aber teuer.
- Datei-Logging: `debug/file_logging/enable_file_logging.pc` ist nicht gesetzt. Der
  Godot-Standard ist an, also gibt es im Release `user://logs/godot.log` (rotiert). **Aber:**
  `application/run/flush_stdout_on_print` steht im Release auf false. Normale `print()`-Zeilen
  stehen beim harten Absturz dann oft nicht mehr in der Datei, Fehlerzeilen schon. Dafuer gibt
  es die Wachmarke. Vorschlag fuer project.godot siehe unten.
- `export_presets.cfg`: `application/export_d3d12=0`. Die D3D12-Laufzeit-DLLs (Agility SDK)
  werden also nicht mitgeliefert. Godots D3D12-Treiber laeuft dann mit der D3D12-Version des
  Systems. Auf Windows 10/11 mit RX 9070 reicht das. Scheitert es trotzdem, faellt Godot auf
  Vulkan zurueck (siehe Schleifenschutz).

### GPU-Schutz (Bestand)
`scripts/core/gpu_guard.gd` (Autoload GpuGuard) erkennt ein hartes Ende ueber
`user://gpu_running.marker` und schaltet **schon nach dem ersten Absturz** dauerhaft auf
OpenGL (override.cfg neben der exe). Phase, Bericht und Stufen gibt es dort nicht.
Zusammenspiel: Laufen beide, ist der Lauf nach dem ersten Absturz schon OpenGL, und
Stufe 3 (D3D12) greift nicht. Das ist gewollt, denn OpenGL ist die sicherste Stufe. Die
Empfehlung unten laesst GpuGuard erst nach Stufe 3 auf OpenGL gehen.

### Shader (`shaders/*.gdshader`, 5340 Zeilen)
- Alle Schleifen haben feste Grenzen (`WARP_TAPS` ist const 3/12/16, sonst 2 bis 6). Es gibt
  keine Schleife mit variabler Laenge und kein `while`.
- `dFdx`/`dFdy`/`fwidth`/`textureGrad` (`tx()`/`tg()` in den Welt-Shadern) stehen nur in
  Zweigen ueber Uniforms (`palette_mix`, `AT_CUBEMAP_PASS`). Das ist uniformer Kontrollfluss,
  die Ableitungen sind also definiert. Kein Fund.
- Keine Uniform-Arrays, kein `hint_depth_texture`.
- `hint_screen_texture` nutzen `black_hole` (spatial), `screen_fx` und `glass_panel` (canvas),
  `black_hole` und `screen_fx` mit `filter_linear_mipmap`. Dafuer baut Godot pro Frame eine
  Bildschirm-Mip-Kette. Das kostet Leistung, ist aber kein bekanntes Absturzmuster.
  Bleibt so.
- `textureSize(tex_a, 0)` (singularity, storm): Ohne gesetzte Textur liefert der Standard
  (`hint_default_black`) 4x4. Kein Absturz.
- **Ergebnis:** Kein Shader mit belegter AMD/Vulkan-Gefahr, also keine Shader-Aenderung.

### VRAM der Welten
Gemessen aus den Bildkoepfen in `assets_game/themes/*`. Rechnung: VRAM-komprimiert (BC7) =
1 Byte/Pixel, lossless (RGBA8) = 4 Byte/Pixel, Mipmaps x4/3.

| Welt | Ebenen | VRAM |
|---|---|---|
| monolith | 4x 8192x4096 (prisms lossless, ohne Mips) | ~256 MB |
| boss, nerve | 5x 8192x4096 | je ~213 MB |
| rift, singularity, storm | 4x 8192x4096 | je ~171 MB |
| aurora | 3x 8192x4096 + 8192x2048 | ~149 MB |
| obsidian, fractal | 3x 8192x4096 (+1024) | ~129 MB |
| eclipse | 2x 8192x4096 + 8192x2048 | ~107 MB |
| abyss | 2x 8192x4096 + 4096x2048 | ~96 MB |
| neon | 4096x2048 lossless | ~32 MB |
| **alle 12 zusammen** | | **~1.8 GB** |

`WorldTheme.prefetch()` laedt nur die Ebenen **einer** Welt, und das ueber
`ResourceLoader.load_threaded_request`, also Godots eigenen Lade-Thread (sicher). Selbst alle
Welten auf einmal braeuchten 1.8 GB von 16 GB. **VRAM ist kein Absturzgrund.**
Nebenbefund: `sky_monolith_prisms.webp` ist lossless und ohne Mips importiert (128 MB statt
43 MB). Ein Import als VRAM-komprimiert mit Mips spart 85 MB. Die Datei gehoert nicht zu
diesem Task.

### Threads (die echte Gefahr)
Auf Vulkan muss `vkQueueSubmit` extern synchronisiert sein. Ein GPU-Readback aus einem
Nebenthread erzwingt ein Submit + Stall, waehrend der Hauptthread rendert. Das ist das
Muster, das auf AMD-Treibern am ehesten haengt oder abstuerzt.

| Stelle | Was im Thread passiert | Einstufung |
|---|---|---|
| `scripts/ui/profile_panel.gd:892` `_thumb_worker` (Thread) | `ms.background_texture()` erzeugt eine ImageTexture, dann **`tex.get_image()` = GPU-Readback aus dem Thread** | **hoch** |
| `scripts/parser/osz_importer.gd:49` `_prepare_task` (WorkerThreadPool) -> `_load_image_uncached` :293 | `ImageTexture.create_from_image()` im Worker (Textur-Upload aus dem Thread) | mittel (Godot 4.4+ laedt ueber Transfer-Worker hoch und gilt als thread-sicher, ist aber der haeufigste Thread-Render-Aufruf im Spiel: jede Browser-Auswahl) |
| `scripts/ui/tournament_panel.gd:560` `_hires_job` (WorkerThreadPool) | `OszImporter.load_image_texture()` -> wie oben | mittel |
| `scripts/campaign/campaign_screen.gd:519`, `scripts/ui/map_picker.gd:1037`, `scripts/net/beatmap_mirror.gd:589` | Bild im Thread dekodieren, Textur im Hauptthread erzeugen | sicher (Vorbild) |
| `song_select.gd` `_bg_thread`/`_os_thread`/`_rec_thread`/`_maxpp_thread`, `map_library.gd` `_sv_thread`, `am_features.gd` | nur Rechnen, Ergebnis per `call_deferred` | sicher |

Behebung: Diese Dateien gehoeren nicht zu diesem Task. Die Einbau-Zeilen unten beschreiben
die Aenderung genau. Muster: Im Thread nur `Image` dekodieren und verkleinern
(`OszImporter.decode_image_bytes`), Textur und `get_image()` nur im Hauptthread.

### Godot 4.7 + RDNA4 / Adrenalin (nicht reproduziert, ohne Log nur Hypothesen)
- **Vulkan-Layer von Overlays** (Adrenalin-Overlay, OBS, Discord, Steam, RivaTuner/MSI
  Afterburner, Overwolf) laden sich in jeden Vulkan-Prozess. Sie sind ein haeufiger Grund fuer
  Abstuerze beim Start oder bei der Pipeline-Erstellung. Stufe 3 (D3D12) umgeht Vulkan-Layer.
- **Pipeline-/Shader-Cache:** Ein Absturz mitten im Schreiben kann Cache-Dateien
  beschaedigen. Godot prueft den Pipeline-Cache beim Laden (Kopf + Hash). Stufe 1 loescht
  Godots Caches. Der **treibereigene** Shader-Cache von AMD (Adrenalin > Grafik > Shader-Cache
  zuruecksetzen) liegt ausserhalb des Spiels. Den muss der Nutzer selbst leeren.
- Grenze von Stufe 1: Der Pipeline-Cache wird beim Start geladen, bevor ein Skript laeuft.
  Ein Lauf, der neue Pipelines baut, schreibt ihn beim Beenden aus dem Speicher neu. Das
  Loeschen wirkt also sicher fuer den Shader-Cache und nur bestmoeglich fuer den Pipeline-Cache.
- Ein **Absturz bei der Renderer-Initialisierung** (vor allen Autoloads) erreicht CrashGuard
  nie. Dagegen hilft nur die override.cfg von GpuGuard (wirkt vor dem Renderer-Start).
- Der 7800X3D ist hier unauffaellig. Ausnahme: EXPO/Curve-Optimizer-Uebertaktung. Instabile
  RAM-Profile zeigen sich in Spielen oft als "zufaellige" Abstuerze.

## Was behoben ist
- Diagnose fehlte: Jetzt gibt es Wachmarke + Bericht mit Phase, Welt, GPU, Treiber, VRAM und
  dem Log-Ende des abgestuerzten Laufs.
- Feste Reaktion (immer OpenGL): Jetzt gibt es Stufen mit Rueckweg nach 3 sauberen Laeufen.
  Die Stufe ist in den Einstellungen sichtbar und zuruecksetzbar.
- Thread-Gefahren und Shader: geprueft und oben belegt. Die Thread-Fixes liegen in fremden
  Dateien, die Zeilen dazu stehen unten.

## Eingebaut in v1.44.0
- `project.godot`: Autoload `CrashGuard` nach `GpuGuard`, `crash.*.translation`,
  `run/flush_stdout_on_print=true`, Datei-Log fuer Release (`[debug] file_logging`).
- Hauptmenue: `CrashNotice.show_if_pending(self)` mit "Ordner oeffnen" und "Bericht kopieren"
  (Graphit + Bernstein). Einstellungen: Zeile "Absturzschutz" mit Stufe und "Zuruecksetzen".
- Stufe 2 wirkt in `world_theme.gd` (`safe_simple()`: `resolve()` liefert Galaxie;
  `safe_image()`: Bilder hoechstens 4096) und `world_backdrop.gd` (`theme_sky_material()`
  gibt bei Stufe 2 keinen 8192er-Himmel). Die Welt meldet `WorldTheme` selbst an CrashGuard.
  Die Phasen kommen aus den Szenenwechseln im Autoload. `mania_3d.gd` und `song_select.gd`
  bleiben dafuer unveraendert.
- Thread-Fixes: `osz_importer.gd` (Worker cached nur `Image`, Textur im Hauptthread; Aufruf aus
  einem Nebenthread gibt eine leere `ImageTexture`, die der Hauptthread fuellt) und
  `profile_panel.gd` (`_thumb_worker` nutzt `OszImporter.load_thumb_image()`, kein `get_image()`).
- GpuGuard: `gpu_guard.gd` bleibt unveraendert. CrashGuard nimmt dessen OpenGL-Schalter zurueck
  (`undo_gpu_safe()`), bis Stufe 3 trotzdem abstuerzte. Den sicheren Modus des Nutzers laesst
  es stehen.
- Offen: `export_presets.cfg` bleibt auf `export_d3d12=0`. Stufe 3 nutzt das D3D12 des Systems.
  Scheitert das, faellt Godot auf Vulkan zurueck, und der Schleifenschutz greift.
- Screenshot-Lauf: `--shot-menu --shot-crash-notice` liest eine von Hand gesetzte Wachmarke
  und zeigt den Hinweis, schreibt aber keine Wachmarke.
- Rang-Buchstaben in den Score-Zeilen des Profils: 30 px statt 20 px.

## Einbau (fremde Dateien, je eine Zeile)
- `project.godot` [autoload], direkt nach `GpuGuard`:
  `CrashGuard="*res://scripts/system/crash_guard.gd"`
- `project.godot` `locale/translations`: `"res://translations/crash.en.translation", "res://translations/crash.de.translation"`
  (`CrashNotice` laedt die Texte auch ohne diesen Eintrag nach.)
- `project.godot` [application]: `run/flush_stdout_on_print=true`. Damit stehen die letzten
  print-Zeilen vor einem harten Absturz im Log. Wenig Kosten, da das Spiel kaum print() im
  Takt aufruft.
- `scripts/ui/main_menu.gd` `_ready()` nach `GpuGuard.take_notice()`: `CrashNotice.show_if_pending(self)`
- `scripts/ui/settings_panel.gd` Grafik-Abschnitt: Zeile "Absturzschutz" mit
  `CrashGuard.stage_label()` und Knopf "Zuruecksetzen" -> `CrashGuard.reset_stage()`
  (nur sichtbar bei `CrashGuard.stage > 0`).
- `scripts/gameplay3d/mania_3d.gd:5199` nach
  `WorldTheme.resolve(...)`: `if CrashGuard.simple_world(): t = WorldTheme.GALAXY` und danach
  `CrashGuard.set_phase("load", t)`.
- Welt-/Hintergrund-Bilder aus eigenen Dateien (z. B. `mania_3d.gd:652`/`:879`) vor
  `ImageTexture.create_from_image(img)`: `img = CrashGuard.fit_image(img)`.
- `scripts/ui/profile_panel.gd:904`: im Thread `OszImporter.decode_image_bytes(OszImporter.read_file_bytes(ms.osz_path, ms.background_file))`
  statt `ms.background_texture().get_image()`. Das ist der Readback-Fix.
- `scripts/parser/osz_importer.gd:293`: Der Worker legt nur das `Image` in den Cache, und
  `load_image_texture()` erzeugt die Textur im Hauptthread (Thread-Upload-Fix).
  `tournament_panel.gd:560` profitiert davon ohne eigene Aenderung.
- `scripts/core/gpu_guard.gd:35`: Den OpenGL-Modus erst setzen, wenn
  `CrashGuard.stage >= 3` war und der Lauf trotzdem abstuerzte (dann greifen die Stufen zuerst).
- `export_presets.cfg`: `application/export_d3d12=1`, damit Stufe 3 die Agility-SDK-DLLs
  mitbringt.

## Was der Betroffene sagen soll
1. **Wann** stuerzt es ab: beim Start, im Menue, im Song-Browser, beim Laden einer Map oder
   mitten im Spiel? Immer bei derselben Map oder Welt?
2. **Treiberversion** (Adrenalin > System > Software-Version) und Windows-Version.
3. **Wie** stuerzt es ab: Fenster weg ohne Meldung, Bild friert ein, schwarzer Bildschirm
   mit Treiber-Reset ("AMD Bug Report Tool" oeffnet sich), oder PC-Neustart?
4. Die **Datei aus `%APPDATA%\Godot\app_userdata\TETHRA\crash\`**. Ab dem naechsten Update
   oeffnet das Hauptmenue den Ordner mit einem Knopf, oder er kopiert den Bericht direkt.
   Dazu `...\TETHRA\logs\` als ZIP.
5. Laufen Overlays (Adrenalin-Overlay, Discord, OBS, Steam, MSI Afterburner/RivaTuner)?
   Hilft es, sie abzuschalten?
6. Hilft "Adrenalin > Grafik > Erweitert > Shader-Cache zuruecksetzen"?
7. Ist EXPO oder Curve Optimizer aktiv? Stuerzt es ohne sie auch ab?
