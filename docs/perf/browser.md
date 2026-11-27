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

AFTER_TABLE
