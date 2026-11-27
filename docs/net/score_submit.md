# Score-Versand: Fehlersuche

Client: `scripts/net/online_api.gd`. Vertrag mit dem Server: `docs/server/SERVER.md` (unveraendert).

## Ablauf

- Jeder gewertete Lauf kommt in die Warteschlange `user://online_queue.json` (hoechstens 200 Eintraege) und wird per `POST /score` gesendet. Auch ohne Anmeldung: der Eintrag gehoert dem zuletzt angemeldeten Profilnamen und geht nach dem naechsten Login raus. Nur der passende Profilname sendet ihn.
- Pro Durchlauf wird jeder Eintrag hoechstens einmal versucht. Schlaegt einer fehl (Netz 5xx), wandert er ans Ende, der naechste kommt dran (keine Kopf-Blockade). Nach 8 Fehlversuchen mit 5xx wird er verworfen. Kein Server erreichbar (Code 0) zaehlt nicht als Versuch und stoppt den Durchlauf. 429 stoppt den Durchlauf bis zum naechsten Takt (120 s).
- 4xx (ausser 401/426/429): der Server lehnt den Score ab, er wird verworfen und protokolliert. 401: Abmeldung, Warteschlange bleibt. 426: Client zu alt, Update noetig.
- Nachtrag: nach Login, beim Spielstart (mit gueltiger Anmeldung) und wenn die Warteschlange leer wurde, sucht der Client lokale Bestwerte ohne `online_id` und sendet sie leise im Takt von 1 s (429: 10 s Pause). Abgelehnte Scores stehen in `user://online.cfg`, Abschnitt `[backfill]`, Listen `rejected` (+ `rejected_reason`) und werden nie wieder gesendet. Antwort `duplicate: true` zaehlt als gesendet. Derzeit nur Mania 4K.

## Protokoll

`user://online_log.txt` (Windows: `%APPDATA%\Godot\app_userdata\<Projekt>\online_log.txt`), hoechstens 200 Zeilen, die aeltesten fallen weg. Im Profil: Knopf "Protokoll oeffnen". Kein Token, kein Passwort, kein Replay-Inhalt.

Zeile, durch Tab getrennt: `Zeit  Aktion  HTTP  Servertext  Modus  Titel [Diff]  Client-Version`

| Aktion | Bedeutung |
|---|---|
| queued | Lauf eingereiht |
| sent | Server hat angenommen |
| retry | Netz/5xx/429, wird spaeter erneut versucht |
| dropped | Server lehnt ab (4xx) oder 8 Fehlversuche, Score weg |
| auth | 401, abgemeldet, Queue bleibt |
| update | 426, Client zu alt |
| catchup | Lauf des automatischen Nachtrags (Start/Ende) |

HTTP 0 = kein Server erreichbar. Servertext = Fehlercode des Servers, z. B. `counts_mismatch`.

## Sichtbar

- Ergebnisbild: Zeile "Online: gesendet / wartet (Grund) / nicht gesendet: Grund / nicht angemeldet".
- Profil, Konto-Zeile: wartende Scores, "Alle Scores sind online", letzter Fehler mit Zeit, "Jetzt senden", "Protokoll oeffnen".

## Befund Circleguard (2026-11-28)

`GET /panel-api/tethra/player/Circleguard`: 76 Scores, alle vom 2026-11-08 13:47-13:53 (Backfill alter Bestwerte plus ein Lauf), danach keiner; `lastSeenSource` "web". Der Client sendete seit dem 08.11. nichts mehr oder alles wurde abgelehnt, ohne Meldung. Moegliche Ursachen im alten Client: 401 meldete still ab und `submit()` warf danach jeden Lauf weg; ein Eintrag mit dauerndem 5xx blockierte die Queue; 4xx verwarf ohne Spur; NaN im Body. Alles behoben und protokolliert. Der Rechner des Spielers war nicht einsehbar: bitte `online_log.txt` anfordern.
