class_name BrowserSort
extends RefCounted

## Reine Sortier- und Gruppierlogik fuer den Song-Browser (Vorbild osu! Song
## Select). Nur statische Funktionen, keine Nodes.
##
## Eingabe: Array von Set-Dictionaries. Gelesene Felder (alle optional):
##   Set:  title, artist, mapper (oder creator), osz_path, date_added,
##         last_played, diffs: Array
##   Diff: version (oder name), stars, notes (oder max_combo), mode (3 = Mania),
##         keys (sonst cs bei Mania), bpm, duration_ms (oder length_ms),
##         date_added, last_played, rank ("SS","S","A","B","C","D";
##         Aliase X/SSH -> SS, SH -> S; leer = ungespielt)
##   Zeiten: Unix-Sekunden (Zahl) oder "YYYY-MM-DDTHH:MM:SS"-String.
## Set-Werte, die fehlen, werden aus den Diffs abgeleitet (bpm/length/date:
## Maximum, rank: bester). Fehlende Werte sortieren immer ans Ende, auch bei
## descending.
##
## API:
##   sort_diffs(diffs) -> Array              neue Liste, stabil: Mania nach
##                                           Tastenzahl, dann Sterne, Noten, Name
##   sort_sets(sets, key, descending=false)  -> Array[{set, diff_index}]
##       key: title|artist|mapper|bpm|length|difficulty|date_added|last_played|rank
##       Stabil. difficulty: je Diff ein Eintrag (diff_index = Index in
##       set.diffs); sonst ein Eintrag je Set mit diff_index = -1.
##   group(entries, mode, collections={})    -> Array[{title, entries}]
##       mode: none|artist|difficulty|keys|rank|collections
##       collections: { Name: [osz_path, ...] }
##   star_bucket(stars) -> int (0..10, -1 = unbekannt)
##   star_bucket_title(bucket) -> String ("0-1" ... "10+")
##   rank_order(rank) -> int (SS 0 .. D 5, ungespielt 6)
##   natural_key(text) -> String (klein, ohne Akzente, Zahlen aufgefuellt)

const RANK_NAMES := ["SS", "S", "A", "B", "C", "D"]
const UNPLAYED := 6
const _PAD := 12
const _IDX_SHIFT := 16777216.0  # 2^24: Platz fuer den Index im Sortierwert

static var _fold: Dictionary = {}


static func _build_fold() -> void:
	var pairs := {
		"a": "àáâãäåāăą", "c": "çćĉċč", "d": "ďđ", "e": "èéêëēĕėęě",
		"g": "ĝğġģ", "h": "ĥħ", "i": "ìíîïĩīĭįı", "l": "ĺļľŀł",
		"n": "ñńņň", "o": "òóôõöøōŏő", "r": "ŕŗř", "s": "śŝşš",
		"t": "ţťŧ", "u": "ùúûüũūŭůűų", "w": "ŵ", "y": "ýÿŷ", "z": "źżž",
		"ss": "ß", "ae": "æ", "oe": "œ",
	}
	for k in pairs:
		for ch in str(pairs[k]):
			_fold[ch.unicode_at(0)] = k


static func natural_key(text: String) -> String:
	if _fold.is_empty():
		_build_fold()
	var s := text.to_lower()
	var out := PackedStringArray()
	var run := ""
	for i in s.length():
		var c := s.unicode_at(i)
		if c >= 48 and c <= 57:
			run += char(c)
			continue
		if run != "":
			out.append(run.lpad(_PAD, "0"))
			run = ""
		if c < 128:
			out.append(char(c))
		elif _fold.has(c):
			out.append(_fold[c])
		else:
			out.append(char(c))
	if run != "":
		out.append(run.lpad(_PAD, "0"))
	return "".join(out)


static func star_bucket(stars: float) -> int:
	if stars < 0.0:
		return -1
	return clampi(int(floor(stars)), 0, 10)


static func star_bucket_title(bucket: int) -> String:
	if bucket < 0:
		return "?"
	if bucket >= 10:
		return "10+"
	return "%d-%d" % [bucket, bucket + 1]


static func rank_order(rank: String) -> int:
	match rank.strip_edges().to_upper():
		"SS", "X", "SSH", "XH":
			return 0
		"S", "SH":
			return 1
		"A":
			return 2
		"B":
			return 3
		"C":
			return 4
		"D":
			return 5
	return UNPLAYED


# ---------------------------------------------------------------- Felder

static func _num(d: Dictionary, names: Array, default: float = -1.0) -> float:
	for n in names:
		if d.has(n):
			var v = d[n]
			if v is float or v is int:
				return float(v)
			if v is String and v.is_valid_float():
				return v.to_float()
	return default


static func _time(d: Dictionary, name: String) -> float:
	var v = d.get(name, null)
	if v is float or v is int:
		return float(v)
	if v is String and v != "":
		if v.is_valid_float():
			return v.to_float()
		var t := Time.get_unix_time_from_datetime_string(v)
		if t > 0:
			return float(t)
	return -1.0


static func _str(d: Dictionary, names: Array) -> String:
	for n in names:
		var v = d.get(n, null)
		if v != null and str(v) != "":
			return str(v)
	return ""


static func _keys_of(d: Dictionary) -> int:
	if int(d.get("mode", 0)) != 3:
		return 0
	return maxi(int(_num(d, ["keys", "cs"], 0.0)), 0)


static func _diffs_of(set: Dictionary) -> Array:
	var v = set.get("diffs", null)
	return v if v is Array else []


static func _diff_rank(d: Dictionary) -> int:
	return rank_order(str(d.get("rank", "")))


const _RANK_FAST := {"SS": 0, "S": 1, "A": 2, "B": 3, "C": 4, "D": 5}
const _FIELDS := {
	"difficulty": ["stars"], "bpm": ["bpm"],
	"length": ["duration_ms", "length_ms", "length"],
	"date_added": ["date_added"], "last_played": ["last_played"],
}


## Zahlenwert eines Diffs fuer key; negativ = fehlt.
static func _diff_value(d: Dictionary, key: String) -> float:
	if key == "rank":
		var rv = d.get("rank", null)
		if rv is String and _RANK_FAST.has(rv):
			return float(_RANK_FAST[rv])
		var r := rank_order(str(rv if rv != null else ""))
		return -1.0 if r >= UNPLAYED else float(r)
	var names: Array = _FIELDS.get(key, [])
	for n in names:
		var v = d.get(n, null)
		if v is float or v is int:
			return float(v)
		if v != null:
			if key == "date_added" or key == "last_played":
				return _time(d, n)
			return _num(d, [n])
	return -1.0


## Zahlenwert eines Sets fuer numerische Keys; negativ = fehlt.
static func _set_value(set: Dictionary, key: String) -> float:
	var best := _diff_value(set, key)  # Set-eigener Wert (gleiche Feldnamen)
	var ds = set.get("diffs", null)
	if not (ds is Array):
		return best
	var is_rank := key == "rank"
	for d in ds:
		var v := _diff_value(d, key)
		if v < 0.0:
			continue
		if is_rank:
			best = v if best < 0.0 else minf(best, v)
		elif v > best:
			best = v
	return best


static func _set_text(set: Dictionary, key: String) -> String:
	var names: Array = ["mapper", "creator"] if key == "mapper" else [key]
	var s := _str(set, names)
	if s == "":
		for d in _diffs_of(set):
			s = _str(d, names)
			if s != "":
				break
	return s


# ---------------------------------------------------------------- Diffs

## Neue Liste: Mania nach Tastenzahl gruppiert (Nicht-Mania zuerst), dann
## Sterne, Notenzahl, Name. Stabil (Einfuegesortierung auf vorberechneten Werten).
static func sort_diffs(diffs: Array) -> Array:
	var n := diffs.size()
	var rows: Array = []
	rows.resize(n)
	for i in n:
		var d: Dictionary = diffs[i] if diffs[i] is Dictionary else {}
		var stars := _num(d, ["stars"])
		# Fehlende Sterne ans Ende der Gruppe.
		rows[i] = [_keys_of(d), stars if stars >= 0.0 else 1e18,
			_num(d, ["notes", "max_combo"], 0.0),
			natural_key(_str(d, ["version", "name"])), diffs[i]]
	for i in range(1, n):
		var cur: Array = rows[i]
		var j := i - 1
		while j >= 0 and _row_less(cur, rows[j]):
			rows[j + 1] = rows[j]
			j -= 1
		rows[j + 1] = cur
	var out: Array = []
	out.resize(n)
	for i in n:
		out[i] = rows[i][4]
	return out


static func _row_less(a: Array, b: Array) -> bool:
	for c in 4:
		if a[c] != b[c]:
			return a[c] < b[c]
	return false


# ---------------------------------------------------------------- Sets

## Werte -> dichte Raenge 0..u-1 ueber native Sortierung; fehlende = -1.
static func _rank_numbers(vals: PackedFloat64Array, missing: PackedByteArray) -> PackedInt64Array:
	var n := vals.size()
	var uniq := PackedFloat64Array()
	for i in n:
		if missing[i] == 0:
			uniq.append(vals[i])
	uniq.sort()
	var map := {}
	var u := 0
	for i in uniq.size():
		if i == 0 or uniq[i] != uniq[i - 1]:
			map[uniq[i]] = u
			u += 1
	var ranks := PackedInt64Array()
	ranks.resize(n)
	for i in n:
		ranks[i] = -1 if missing[i] != 0 else int(map[vals[i]])
	return ranks


## Texte -> dichte Raenge; leerer Text = fehlt = -1.
static func _rank_strings(vals: PackedStringArray) -> PackedInt64Array:
	var n := vals.size()
	var uniq := PackedStringArray()
	for i in n:
		if vals[i] != "":
			uniq.append(vals[i])
	uniq.sort()
	var map := {}
	var u := 0
	for i in uniq.size():
		if i == 0 or uniq[i] != uniq[i - 1]:
			map[uniq[i]] = u
			u += 1
	var ranks := PackedInt64Array()
	ranks.resize(n)
	for i in n:
		ranks[i] = -1 if vals[i] == "" else int(map[vals[i]])
	return ranks


## Stabile Reihenfolge ueber Raenge: Sortierwert = rang * 2^24 + index, nativ
## als Float64 sortiert (exakt bis 2^53). Fehlende (-1) liegen hinten und
## behalten bei descending ihre Eingabereihenfolge.
static func _order(ranks: PackedInt64Array, descending: bool) -> PackedInt64Array:
	var n := ranks.size()
	var maxr := 0
	for r in ranks:
		if r > maxr:
			maxr = r
	var comp := PackedFloat64Array()
	comp.resize(n)
	for i in n:
		var r: int = ranks[i]
		if r < 0:
			r = maxr + 1
		elif descending:
			r = maxr - r
		comp[i] = float(r) * _IDX_SHIFT + float(i)
	comp.sort()
	var out := PackedInt64Array()
	out.resize(n)
	var mask := int(_IDX_SHIFT)
	for i in n:
		out[i] = int(comp[i]) % mask
	return out


static func sort_sets(sets: Array, key: String, descending: bool = false) -> Array:
	var entries: Array = []
	var vals_n := PackedFloat64Array()
	var vals_s := PackedStringArray()
	var missing := PackedByteArray()
	var text := key == "title" or key == "artist" or key == "mapper"
	for set in sets:
		if not (set is Dictionary):
			continue
		if key == "difficulty":
			var ds := _diffs_of(set)
			if ds.is_empty():
				entries.append({"set": set, "diff_index": -1})
				vals_n.append(-1.0)
				missing.append(1)
			for i in ds.size():
				var v := _diff_value(ds[i], "difficulty")
				entries.append({"set": set, "diff_index": i})
				vals_n.append(v)
				missing.append(1 if v < 0.0 else 0)
		else:
			entries.append({"set": set, "diff_index": -1})
			if text:
				vals_s.append(natural_key(_set_text(set, key)))
			else:
				var v := _set_value(set, key)
				vals_n.append(v)
				missing.append(1 if v < 0.0 else 0)
	var ranks: PackedInt64Array
	if text:
		ranks = _rank_strings(vals_s)
	else:
		ranks = _rank_numbers(vals_n, missing)
	var order := _order(ranks, descending)
	var out: Array = []
	out.resize(order.size())
	for i in order.size():
		out[i] = entries[order[i]]
	return out


# ---------------------------------------------------------------- Gruppen

static func _entry_diff(e: Dictionary) -> Dictionary:
	var ds := _diffs_of(e["set"])
	var di := int(e.get("diff_index", -1))
	if di >= 0 and di < ds.size() and ds[di] is Dictionary:
		return ds[di]
	return {}


static func _entry_stars(e: Dictionary) -> float:
	var d := _entry_diff(e)
	if not d.is_empty():
		return _num(d, ["stars"])
	return _set_value(e["set"], "difficulty")


static func _entry_rank(e: Dictionary) -> int:
	var d := _entry_diff(e)
	if not d.is_empty():
		return _diff_rank(d)
	var v := _set_value(e["set"], "rank")
	return UNPLAYED if v < 0.0 else int(v)


static func _entry_keys(e: Dictionary) -> Array:
	var d := _entry_diff(e)
	if not d.is_empty():
		return [_keys_of(d)]
	var out: Array = []
	for x in _diffs_of(e["set"]):
		var k := _keys_of(x)
		if not out.has(k):
			out.append(k)
	if out.is_empty():
		out.append(0)
	return out


static func _letter(s: String) -> String:
	var k := natural_key(s)
	for i in k.length():
		var c := k.unicode_at(i)
		if c >= 97 and c <= 122:
			return char(c).to_upper()
		if c >= 48 and c <= 57:
			return "0-9"
	return "#"


## entries: Ausgabe von sort_sets (Reihenfolge bleibt in jeder Gruppe erhalten).
## Gruppen: artist 0-9, A-Z, #; difficulty aufsteigend; keys 4K..7K, dann
## "Andere"; rank SS..D, "Ungespielt"; collections nach Name, "Keine Sammlung"
## zuletzt. Ein Set kann in mehreren Gruppen stehen (keys, collections).
static func group(entries: Array, mode: String, collections: Dictionary = {}) -> Array:
	if mode == "none" or mode == "":
		return [{"title": "", "entries": entries.duplicate()}]
	var buckets := {}  # Sortierschluessel -> {title, entries}
	for e in entries:
		var set: Dictionary = e["set"]
		var tags: Array = []  # Paare [sortkey, title]
		match mode:
			"artist":
				var l := _letter(_set_text(set, "artist"))
				var sk := "0" if l == "0-9" else ("2" if l == "#" else "1" + l)
				tags.append([sk, l])
			"difficulty":
				var b := star_bucket(_entry_stars(e))
				tags.append(["%02d" % (b if b >= 0 else 99), star_bucket_title(b)])
			"keys":
				for k in _entry_keys(e):
					tags.append([("%02d" % k) if k > 0 else "99", ("%dK" % k) if k > 0 else "Andere"])
			"rank":
				var r := _entry_rank(e)
				tags.append([str(r), RANK_NAMES[r] if r < UNPLAYED else "Ungespielt"])
			"collections":
				var path := str(set.get("osz_path", ""))
				for cname in collections:
					if path != "" and (collections[cname] as Array).has(path):
						tags.append(["0" + natural_key(str(cname)), str(cname)])
				if tags.is_empty():
					tags.append(["1", "Keine Sammlung"])
			_:
				tags.append(["", ""])
		for t in tags:
			if not buckets.has(t[0]):
				buckets[t[0]] = {"title": t[1], "entries": []}
			buckets[t[0]]["entries"].append(e)
	var keys := PackedStringArray(buckets.keys())
	keys.sort()
	var out: Array = []
	for k in keys:
		out.append(buckets[k])
	return out
