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
