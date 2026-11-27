# Song-Browser Stufe 1 (Liste): Stand

Fertig (scripts/song_select.gd):
- Virtuelles Karussell: `_build_list`, Abschnitt "Karussell". Daten `_e_*` (Eintraege aus BrowserSort), Zeilen `_r_*` (Gruppenkopf, Set-Karte, Diff-Zeile, unspielbar), feste Hoehen, Pool je Zeilenart, Bindung nur beim Sichtbarwerden (`_layout_list`, `_bind_row`).
- Gewaehltes Set klappt auf (`_rebuild_rows`), Diffs ueber `BrowserSort.sort_diffs` (`_diff_order`), Pfeile links/rechts folgen dieser Reihenfolge.
- Sortierung `SORT_KEYS` (9) und Gruppierung `GROUP_KEYS` (6) ueber `browser_entries` -> BrowserSort; Auswahlfelder in der Sortier-Reihe oben rechts; gespeichert in browser_state.cfg (`sort_ver` 2 rechnet alte Nummern um, `group_mode`).
- Cover im WorkerThreadPool (`_cover_task`), nur sichtbare Sets warten (`_cover_want`), LRU 160 (`_cover_put`).
- Weiches Mausrad-Scrollen (`_list_step`), Vorschau-Audio entprellt 200 ms (`_play_preview` -> `_play_preview_now`).
- Rang gross: Set-Karte 38 px, Diff-Zeile 28 px (Titel 20 bzw. 16 px).
- `--bench-browser [--bench-mult=N]`, Werte in docs/perf/browser.md.
- Tests: tests/run_browser_filter_tests.gd (Sortierung, Gruppen, Zeilen-Layout).

Naechste Schritte (Stufe 2): linke Seite (Info, Bestenliste), untere Leiste, Tastatur (hoch/runter durch Diff-Zeilen wie osu!), "For you"-Block nimmt der Liste viel Hoehe.

# Stufe 2a (Task browser-panel): Stand

Fertig (Commit "Liste volle Hoehe ..."), Lint gruen, noch NICHT per Screenshot geprueft:
- Liste rechts: nur noch die Sortier-Reihe (Anzahl, Sortieren, Gruppieren, Knopf "Filter") liegt ueber ihr; `_update_list_top` ergibt FILTER_Y + 32 px.
- Filter-Chips (Sterne, SV, Tasten, Bestwert, Rang) im Feld `_filter_pop` (auf Abruf ueber der Liste, nimmt keine Hoehe). Knopf zeigt Akzent + Zahl aktiver Filter (`_active_filter_count`, `_restyle_filter_btn`, aufgerufen in `_refresh_filter`).
- "For you" ist ein eigener Tab (`_tab_foryou`, `_set_foryou_mode`): Ansicht `_rec_view` (deckend, rechte Spalte, volle Hoehe, ScrollContainer) ueber der Liste; Kopf ohne Einklappen/Ausblenden; `_recs_refresh` rechnet nur bei offenem Tab; 6+ Vorschlaege untereinander. `_rec_chip` wird nicht mehr gebaut.
- "Importieren" sitzt jetzt links neben Profil/Zahnrad (Platz fuer den neuen Tab).

Offen (in dieser Reihenfolge):
1. Screenshot 1920x1080 und 2560x1440: Liste fuellt die rechte Seite, Auswahl mittig, Filter-Feld, For-you-Tab. `warmd shot res://scenes/song_select.tscn` lieferte ein schwarzes Bild (godot.path fehlt, Brake gemeldet); direkt mit override.cfg aus tools/test_override.cfg und `--shot --shot-out=<png> --position -1920,0 --audio-driver Dummy --resolution WxH`, timeout 150.
2. Linkes Panel (Nutzer-Entscheidung): geschlossen nur Map-Info, Spielen, EINE Mods-Zeile ("Mods: NF SD" bzw. "Mods: keine"), Bestenliste. Klick auf Mods (oder Escape zum Schliessen) klappt die Mod-Gruppe mit vollen Namen auf (No Fail, SV Normal/Stark, SD, PF, Mines, Turbo, Keep pitch, Ueben; Trace: MR/HD/SS). Aktionen (+ Sammlung, An Freund schicken, Marathon) hinter "Mehr" oder als eine ruhige Textzeile. Modus-Umschalter Mania/Trace + Tutorial bleiben.
   - Mod-Knoepfe sind CheckButtons; `_apply_mod_visibility`/`_sync_rule_mod_buttons` casten `as CheckButton` -> beim Umbau auf Button mitziehen. TempoBrowserRow (fremde Datei) in einen versteckten Halter bauen, eigene Knoepfe setzen `TempoBrowserRow.turbo_on`, `TempoPrefs.set_keep_pitch`, Ueben = `TempoBrowserRow._start_practice(self)`.
   - Diff-Pfeile + `_diff_bar` weg (Liste zeigt die Diffs); `_rebuild_diff_bar` -> nur `_refresh_star_label` (auch in `_mode_stars_arrived`).
   - Info: Titel gross, Interpret, Diff-Name klar + "Map von", Kennzahlen-Zeile (Sterne in Sternfarbe, Laenge, BPM, Noten, Tasten, OD, HP, Max-pp) als Paare Beschriftung/Wert. HP fehlt in den Metadaten: im Worker aus der .osu ([Difficulty] HPDrainRate) zusammen mit den Timing-Points lesen.
   - Bestenliste: Zeilen ~52 px, Platz, Rang-Buchstabe 34 px (GRADE_COLOR), Name (`ScoreStore._self_name()`), darunter Mods + Datum; rechts Score, darunter Acc + Kombo; pp. Erster eigener Lauf hervorgehoben (Bernstein-Kante). Leer: ein Satz. Bis 8 Zeilen im ScrollContainer, Panel volle Hoehe, Breite clamp(34 % Fensterbreite, 520, 760).
3. Mitte: `_cover`-Kachel weg. Map-Bild als Vollbild-Hintergrund: Worker liest das Bild (`OszImporter.read_file_bytes` + decode wie `cover_build`), verkleinert auf 320 px, zieht weich auf 960 px hoch, Helligkeit nach Luminanz (wie `cover_dim`, Ziel ~0,2), Hauptthread nur Upload + 0,35 s Ueberblendung zweier TextureRects. Spektrum + Vorschau-Linie unten in der Mitte lassen.
4. Tempo (Ursachen gefunden): pro Auswahl im Hauptthread `UiTheme.blurred_texture(quick, 8)` (Textur-Readback von der GPU + Resizes), `_timing_points` (Zip lesen + parsen fuer BPM), `_load_fullres_bg` (Vollbild-Textur mit Mipmaps hochladen), Bestenliste neu bauen. Plan: Texte sofort, Rest entprellt (~140 ms, `_detail_due` in `_prepare_step`), Timing-Points/HP und Hintergrund im WorkerThreadPool (statische Jobs mit instance_id wie `_maxpp_job`, in `_exit_tree` abwarten), PREPARE_DELAY_MS 100 -> 350. Bench um schnelles Durchwechseln (alle 33 ms, 40 Wechsel, 1,5 s Nachlauf, max Frame / Frames > 8 ms) erweitern, Zahlen in browser.md.
5. Texte ueber tr() in translations/browser.csv (en+de), .translation neu importieren. Tests: statische Helfer (osu-Kopf-Parser, BPM-Bereich, Datum) in tests/run_browser_filter_tests.gd.
