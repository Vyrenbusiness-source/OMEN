extends RefCounted

## Bot-Eingabeplan fuer Live-QA/Tempo-Treiber (Mania/Trace-Spuren): je Note ein
## Druck und ein Loslassen, optional mit Streuung und jeder n-ten Note ausgelassen.
## Aufruf: preload("res://tests/bot_plan.gd").plan(beatmap, seed, jitter_ms, skip_every)
static func plan(bm: Beatmap, seed: int = 1, jitter_ms: float = 0.0, skip_every: int = 0) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var objs := bm.hit_objects
	var next_in_col := {}
	var next_t: Array = []
	next_t.resize(objs.size())
	for i in range(objs.size() - 1, -1, -1):
		var n := objs[i] as ManiaNote
		next_t[i] = float(next_in_col.get(n.column, 1e12))
		next_in_col[n.column] = n.time
	var out: Array = []
	for i in objs.size():
		if skip_every > 0 and (i + 1) % skip_every == 0:
			continue
		var n := objs[i] as ManiaNote
		var dt := rng.randf_range(-jitter_ms, jitter_ms) if jitter_ms > 0.0 else 0.0
		var du := rng.randf_range(-jitter_ms, jitter_ms) if jitter_ms > 0.0 else 0.0
		var t := int(round(n.time + dt))
		var up := int(round(n.end_time() + du)) if n.is_hold else t + 40
		up = maxi(up, t + 8)
		up = mini(up, int(next_t[i]) - 3) if next_t[i] < 1e11 else up
		up = maxi(up, t + 1)
		out.append({"t": t, "lane": n.column, "down": true, "o": 1})
		out.append({"t": up, "lane": n.column, "down": false, "o": 0})
	out.sort_custom(func(a, b):
		if a.t != b.t:
			return a.t < b.t
		return a.o < b.o)
	for e in out:
		e.erase("o")
	return out
