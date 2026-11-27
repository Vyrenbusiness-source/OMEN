# Song-Browser: Messung Liste (Stufe 1)

Messung mit dem Startflag `--bench-browser` (scripts/song_select.gd, `_bench_browser`):

```
Godot_v4.7-stable_win64_console.exe --path . --position -1920,0 --resolution 1920x1080 \
  --audio-driver Dummy res://scenes/song_select.tscn --bench-browser [--bench-mult=20]
```

- `first_list_ms`: von `_ready` bis zum ersten gezeichneten Frame mit Liste (warm = zweiter Lauf, Cover-Cache auf Disk).
- `max_frame_ms`, `p99_ms`, `avg_ms`, `frames_over_8ms`: ganze Bibliothek in 40-px-Schritten (ein Schritt je Frame) durchscrollen, VSync aus, echte Frame-Zeit.
- `switch_*`: 20 Set-Wechsel ueber `_select_set` + Scroll zur Auswahl bis zum gezeichneten Frame.
- `--bench-mult=20`: Bibliothek 20-fach (Kopien im Speicher), um eine grosse Bibliothek zu pruefen.

Rechner: Entwickler-PC (Windows 10, Bildschirm 2), Bibliothek 95 Sets.

## Vorher (Commit b08c0b7, alte Liste: eine Karte je Set als Node)

| Lauf | Sets | erste Liste | laengster Frame | p99 | Mittel | Frames > 8 ms | Set-Wechsel Median / max |
|---|---|---|---|---|---|---|---|
| 1x warm | 95 | 448 ms | 4,6 ms | 4,1 ms | 1,3 ms | 0 von 188 | 74 / 114 ms |
| 20x | 1900 | 4977 ms | 145,7 ms | 22,3 ms | 14,0 ms | 3968 von 3968 | 158 / 222 ms |

## Nachher (virtuelles Karussell)

Ab hier wartet der Bench nach der ersten Liste 1,5 s, bevor er scrollt (Startflag
`--bench-cold-scroll` laesst die Pause weg). Grund: ohne Pause fielen 4 Frames von
12 bis 41 ms in den Scroll-Wert, die nicht von der Liste kamen. Die Diagnose-Zeilen
`BENCH_SLOW` (Layout-Zeit, neue Nodes, Cover, Skript-Schritte je Frame) zeigten:
Liste 0,0 bis 1,6 ms, kein neuer Node, kein Skript-Schritt ueber 1,5 ms. Es ist die
Vorbereitung der Auswahl nach dem Start (Worker: Vollbild-Hintergrund, Vollparse,
Textur-Upload) und das Laden der Vorschau-Musik. Die Vorschau laedt jetzt im Worker
(`_play_preview_now` -> `_preview_loaded`); der Rest gehoert zur linken Seite (Stufe 2).

| Lauf | Sets | erste Liste | laengster Frame | p99 | Mittel | Frames > 8 ms | Set-Wechsel Median / max |
|---|---|---|---|---|---|---|---|
| 1x warm | 95 | 252 ms | 3,0 ms | 1,9 ms | 0,9 ms | 0 von 220 | 35 / 47 ms |
| 20x | 1900 | 641 ms | 2,5 ms | 1,6 ms | 0,8 ms | 0 von 4371 | 35 / 66 ms |
| 1x kalt gescrollt (ohne Pause) | 95 | 255 ms | 38,4 ms | 11,7 ms | 1,3 ms | 4 von 209 | 42 / 82 ms |
| 20x kalt gescrollt (ohne Pause) | 1900 | 761 ms | 116,7 ms | 2,0 ms | 0,8 ms | 4 von 4360 | 38 / 51 ms |

Ziele: kein Scroll-Frame ueber 8 ms (erfuellt, sobald der Start-Anlauf vorbei ist),
erste Liste unter 300 ms warm (erfuellt: 252 ms). Die alte Liste wurde ohne Pause
gemessen; ihr Scroll-Wert bei 1x (4,6 ms) enthaelt also denselben Anlauf.

Offen fuer Stufe 2: Hintergrund-Vorbereitung der Auswahl blockiert in den ersten
etwa 0,5 s nach dem Start einzelne Frames (bis 41 ms); bei 1900 Sets dauert die
erste Liste 641 ms (Sortieren und Gruppieren aller Sets im Hauptthread).

## Stufe 2a: Auswahlwechsel (linkes Panel, Hintergrund, Bestenliste)

Neu im Bench: `BENCH_RAPID` waehlt 40-mal im Abstand von 33 ms ein anderes Set
(schnelles Durchwechseln) und misst danach noch 1,5 s weiter (entprellte Jobs
laufen in dieser Zeit fertig). `_bt()` schreibt Abschnitte ueber 1 ms als
`BENCH_RAPID_SLOW`.

Vorher kostete jede Auswahl im Hauptthread 19-25 ms: Max-pp (stars.cfg laden,
10 ms), Bestenliste (scores laden, 8 ms), weicher Hintergrund (Textur-Readback),
Timing-Points (Zip lesen fuer BPM). Jetzt: Texte sofort, alles andere nach
140 ms (`DETAIL_DELAY_MS`) im WorkerThreadPool (`_osu_info_job`, `_bg_job`,
`_board_job`); der Hauptthread laedt nur Texturen hoch und baut die Zeilen.
Den Profilnamen liest `_start_board_job` im Hauptthread (kein Szenenzugriff im Worker).

1920x1080, 74 Sets, warm:

| Lauf | Set-Wechsel Median / max | Schnelles Durchwechseln: laengster Frame | p99 | Frames > 8 ms |
|---|---|---|---|---|
| vorher (Stufe 1) | 21,1 ms / 25 ms | – | – | – |
| nachher, Lauf 1 | 2,9 ms / – | 18,5 ms | 2,07 ms | 1 von 5092 |
| nachher, Lauf 2 (Board-Job ohne Szenenbaum) | 4,4 ms / 8,7 ms | 6,6 ms | 2,53 ms | 0 von 4080 |

Scrollen im selben Lauf 2: laengster Frame 5,1 ms, p99 4,0 ms, 0 von 158 Frames > 8 ms,
erste Liste 272 ms.
