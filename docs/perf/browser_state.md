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

## Handoff 2 (Commits 84a0cd1 und folgende)

Fertig und per Screenshot 1080p/1440p geprueft (Liste, Filter offen, For you, Mods offen, Trace, Map mit Scores):
- Liste: erste/letzte Karte duerfen bis in die Mitte (`_center_pad`, `_clamp_scroll` kappt nicht ohne Hoehe), Auswahl steht mittig. Filter-Feld offen: Liste rutscht darunter (`_update_list_top`), For you: Liste unsichtbar (`_apply_recs_visibility`).
- Linkes Panel volle Hoehe, Breite `_info_w()` (30 %, 500-720): Titel 30, Diff-Name + Sterne in Sternfarbe, Kennzahlen-Paare (`_stat_pair`: Laenge, BPM, Noten, Tasten/CS, OD, HP), Max-pp, Modus, Spielen, EINE Mods-Zeile (`_mods_btn`, Kuerzel via `mods_code_list`/`mods_codes`, Klick/Esc = `_set_mods_open`), "Mehr" (MenuButton: + Sammlung, An Freund, Marathon; alte Knoepfe unsichtbar in `act_holder`). Bestenliste im ScrollContainer, Zeilen 52 px, Rang 34 px, eigener erster Lauf mit Bernstein-Kante (`_score_row`, `_two_lines`, `score_date_text`).
- Hintergrund: `_bg_job` (Worker) dekodiert das Map-Bild, `blur_image` (640 -> 80 -> bilinear 640), `image_luminance`, `_on_bg_ready` blendet 0,35 s ueber (`_bg_next`), Helligkeit `_bg_dim` = 0,20 / Luminanz (helle Cover glaenzen nicht). Nutzer-Entscheidung: scharfe Kachel bleibt in der Mitte (`_layout_stage`, Seitenverhaeltnis `_stage_aspect` aus dem scharfen Bild, max 620x460), scharfes Bild <= 1280 px aus demselben Job. Noch NICHT per Screenshot geprueft (Shot f_list lief, nicht angesehen).
- Tempo: `_osu_info_job` (Timing-Points + HP im Worker, `_on_osu_info`), `_start_detail_jobs` nach DETAIL_DELAY_MS 140, PREPARE_DELAY_MS 350, Bestenliste + Max-pp ueber `_start_board_job`/`_board_job`/`_on_board_data` (Worker). `_bt()` misst Abschnitte im Bench. Bench `--bench-browser` hat jetzt BENCH_RAPID (40 Wechsel alle 33 ms + 1,5 s Nachlauf).
  Messung 1080p, 74 Sets: vorher Wechsel 19-25 ms pro Auswahl (maxpp 10 ms = stars.cfg laden, board 8 ms = scores laden); nachher BENCH_RAPID max 18,5 ms, 1 von 5092 Frames > 8 ms (einmal highlight=13,4), p99 2,07 ms; switch_median 2,9 ms (vorher 21,1).

OFFEN (naechster Agent, in dieser Reihenfolge):
1. BUG: `_board_job` ruft `ScoreStore.top_scores_all` im Worker; das ruft `_self_name()` -> get_node_or_null im Thread -> ERROR "caller thread can't call get_node_or_null". Fix: statische `board_scores(osz, ver, n, mode)` in song_select.gd (wie top_scores_all ohne Namen: ScoreStore._load, top_scores(.., HISTORY_CAP, mode), others aus cfg `_sec("others", mode)` / `map_id(osz, ver, cfg)`, sort `ranks_higher`, slice) und in `_on_board_data` `d["player"] = ScoreStore._self_name()` fuer is_self setzen. Danach pruefen, dass top_scores selbst keinen Szenenbaum liest.
2. Screenshot 1080p (`--map=magnum`) ansehen: scharfe Kachel mittig + weicher Hintergrund, nichts abgeschnitten; dazu eine Map mit weissem Cover.
3. Bench nochmal laufen lassen, Zahlen oben in docs/perf/browser.md eintragen.
4. Tests in tests/run_browser_filter_tests.gd: `mods_code_list` (Reihenfolge, keine Dubletten), `score_date_text` (de/en/ungueltig), `decode_image` leer -> null. Danach `warmd check` im Hintergrund, `warmd finish`.
5. `RuleModsHarness` (scripts/gameplay/mods/rule_mods_harness.gd, fremde Datei) liest `_lb_box`: Bestenliste kommt jetzt erst nach 140 ms + Worker; Harness ggf. warten lassen (nur Shot-Werkzeug).
- Screenshot-Hilfe: `--shot --shot-wait=2.5 --shot-view=list|filter|foryou|mods --shot-out=<png> [--map=<text>] [--mode=trace]`, override.cfg aus tools/test_override.cfg (danach loeschen).

Offen (alter Plan, Stand Handoff 1; Punkte 1-4 oben erledigt):
1. Screenshot 1920x1080 und 2560x1440: Liste fuellt die rechte Seite, Auswahl mittig, Filter-Feld, For-you-Tab. `warmd shot res://scenes/song_select.tscn` lieferte ein schwarzes Bild (godot.path fehlt, Brake gemeldet); direkt mit override.cfg aus tools/test_override.cfg und `--shot --shot-out=<png> --position -1920,0 --audio-driver Dummy --resolution WxH`, timeout 150.
2. Linkes Panel (Nutzer-Entscheidung): geschlossen nur Map-Info, Spielen, EINE Mods-Zeile ("Mods: NF SD" bzw. "Mods: keine"), Bestenliste. Klick auf Mods (oder Escape zum Schliessen) klappt die Mod-Gruppe mit vollen Namen auf (No Fail, SV Normal/Stark, SD, PF, Mines, Turbo, Keep pitch, Ueben; Trace: MR/HD/SS). Aktionen (+ Sammlung, An Freund schicken, Marathon) hinter "Mehr" oder als eine ruhige Textzeile. Modus-Umschalter Mania/Trace + Tutorial bleiben.
   - Mod-Knoepfe sind CheckButtons; `_apply_mod_visibility`/`_sync_rule_mod_buttons` casten `as CheckButton` -> beim Umbau auf Button mitziehen. TempoBrowserRow (fremde Datei) in einen versteckten Halter bauen, eigene Knoepfe setzen `TempoBrowserRow.turbo_on`, `TempoPrefs.set_keep_pitch`, Ueben = `TempoBrowserRow._start_practice(self)`.
   - Diff-Pfeile + `_diff_bar` weg (Liste zeigt die Diffs); `_rebuild_diff_bar` -> nur `_refresh_star_label` (auch in `_mode_stars_arrived`).
   - Info: Titel gross, Interpret, Diff-Name klar + "Map von", Kennzahlen-Zeile (Sterne in Sternfarbe, Laenge, BPM, Noten, Tasten, OD, HP, Max-pp) als Paare Beschriftung/Wert. HP fehlt in den Metadaten: im Worker aus der .osu ([Difficulty] HPDrainRate) zusammen mit den Timing-Points lesen.
   - Bestenliste: Zeilen ~52 px, Platz, Rang-Buchstabe 34 px (GRADE_COLOR), Name (`ScoreStore._self_name()`), darunter Mods + Datum; rechts Score, darunter Acc + Kombo; pp. Erster eigener Lauf hervorgehoben (Bernstein-Kante). Leer: ein Satz. Bis 8 Zeilen im ScrollContainer, Panel volle Hoehe, Breite clamp(34 % Fensterbreite, 520, 760).
3. Mitte: `_cover`-Kachel weg. Map-Bild als Vollbild-Hintergrund: Worker liest das Bild (`OszImporter.read_file_bytes` + decode wie `cover_build`), verkleinert auf 320 px, zieht weich auf 960 px hoch, Helligkeit nach Luminanz (wie `cover_dim`, Ziel ~0,2), Hauptthread nur Upload + 0,35 s Ueberblendung zweier TextureRects. Spektrum + Vorschau-Linie unten in der Mitte lassen.
4. Tempo (Ursachen gefunden): pro Auswahl im Hauptthread `UiTheme.blurred_texture(quick, 8)` (Textur-Readback von der GPU + Resizes), `_timing_points` (Zip lesen + parsen fuer BPM), `_load_fullres_bg` (Vollbild-Textur mit Mipmaps hochladen), Bestenliste neu bauen. Plan: Texte sofort, Rest entprellt (~140 ms, `_detail_due` in `_prepare_step`), Timing-Points/HP und Hintergrund im WorkerThreadPool (statische Jobs mit instance_id wie `_maxpp_job`, in `_exit_tree` abwarten), PREPARE_DELAY_MS 100 -> 350. Bench um schnelles Durchwechseln (alle 33 ms, 40 Wechsel, 1,5 s Nachlauf, max Frame / Frames > 8 ms) erweitern, Zahlen in browser.md.
5. Texte ueber tr() in translations/browser.csv (en+de), .translation neu importieren. Tests: statische Helfer (osu-Kopf-Parser, BPM-Bereich, Datum) in tests/run_browser_filter_tests.gd.

## Abschluss (Handoff 3)

Erledigt: Punkt 1 (`board_scores` in song_select.gd, Profilname aus dem Hauptthread als
Parameter von `_board_job`, kein Thread-ERROR mehr, eigener Name sichtbar), Punkt 2
(1080p: scharfe Kachel mittig zwischen Panel und Liste, weicher Hintergrund; For-you-Tab
blendet Sortier-Reihe und Filter-Feld aus, sie schienen durch), Punkt 3 (Zahlen in
docs/perf/browser.md), Punkt 4 (Tests `_test_panel_helpers`, `_test_board_scores`;
tests/mv_tempo_play.gd klappt die Mods-Gruppe vor der Sichtbarkeitspruefung auf).
Offen: Punkt 5 (`RuleModsHarness` wartet nicht auf die entprellte Bestenliste, fremde Datei).

## Songauswahl "Plakat statt Formular" (Aufgabe select-look)

Erledigt: linke Spalte ohne Kasten (Titel 48 px, Luft vor "Max pp" und vor Play),
Text-Reiter mit Bernstein-Unterstrich, Play 200x52, Liste buendig rechts mit
`curve_indent` (44 px * d^2, Test in tests/run_browser_filter_tests.gd).
Set-Karten: nicht gewaehlt nach eigener Cover-Helligkeit abgedunkelt
(`COVER_LUM` 0,18, Faktor 0,16..0,85), gewaehlt volles Cover, Titel weiss 24 px.
Gewaehlte Diff: gleiche Schrift fett (FontVariation), gleiche Hoehe und Grundlinie.
Mitte: Ecken 4 px, Schatten 12 px Alpha 0,25, Vorschau-Linie 2 px, Spektrum Alpha 0,35.
For you: kein Kasten, Zeilen mit Linie unten, gewaehlt Bernstein 16 % + 2 px Strich.
Filter-Chips mit Bernstein-Text, 16 px Abstand; Collections-Aktionen als Textknoepfe.
Offen: Filter-Feld hat noch eine dunkle Flaeche (Overlay ueber der Liste, sonst
unlesbar); neue CSV-Schluessel (`Type to search`, `SV-Stufe`) erscheinen erst nach
einem Import (Editor/`--import`) uebersetzt.
