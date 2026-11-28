class_name TownGen
extends RefCounted
## LOOK2: towns as places for the generated province (GenField). Each engine town gets a street grid turned to its own angle, a main street
## and a cross street, a square with a hall at the centre, terraces and shop blocks near the square, houses with gardens further out, and
## street lamps along every street. Every building carries an energy index (the engine's shed share darkens whole districts: the index runs
## round the town by angle, so a 21 % shed is a 21 % wedge of streets) and its distance from the centre (lights come on and go out in a
## wave outward from the substation). Presentation only.

## Returns {places: [[x, z, w, d, h, rot, town_id, idx, big, dn, front_turn]], streets: [[a: Vector2, b: Vector2, width, town]], lamps: [[Vector3, town_id, dn]],
## centres: [[Vector2, town_id, rot]]}.
## 1.18 (lead's art review: "a square grid with a pale halo"): streets grow the way a town grows. A main street follows the town's road and bends
## with it; side streets leave it at uneven gaps and angles and wander; some side streets carry a back lane; where the river passes, a street
## follows the bank. Houses line every street and keep clear of the others.
static func build(gf, model: Dictionary, quality: String, ground: Callable) -> Dictionary:   # gf: a GenField or an AreaTowns
	var places: Array = []; var streets: Array = []; var lamps: Array = []; var centres: Array = []
	var gap := 62.0 if quality == "high" else (78.0 if quality == "medium" else 100.0)
	var keep_k := 1.0 if quality == "high" else (0.8 if quality == "medium" else 0.5)
	for ti in model.towns.size():
		var tw: Dictionary = model.towns[ti]
		var c: Vector2 = gf.towns[ti].c; var r: float = gf.towns[ti].r * 1.45
		if r <= 0.0: centres.append([c, str(tw.id), 0.0]); continue   # a town with no tiles of its own (AreaTowns)
		var id := str(tw.id); var count := maxi(1, int(tw.count))
		var rot := TAU * WorldMath.hash2(ti, 7, 901)
		var ax := Vector2(cos(rot), sin(rot))
		centres.append([c, id, rot])
		var polys: Array = []   # [PackedVector2Array, width]
		# the main street: through the centre along the road, bending with it, running on a little past the edge
		var main := _wander(gf, ti, c, ax, r * 1.3, 1.25, 0.10, ti * 7 + 1)
		var back := _wander(gf, ti, c, -ax, r * 1.3, 1.25, 0.10, ti * 7 + 2)
		var mpoly := PackedVector2Array()
		for k in range(back.size() - 1, 0, -1): mpoly.append(back[k])
		mpoly.append_array(main)
		if mpoly.size() >= 2: polys.append([mpoly, 11.0])
		# side streets off the main street, both sides, at uneven gaps; a back lane on some of them
		var acc := 0.0; var q := 0
		for k in range(mpoly.size() - 1):
			var a: Vector2 = mpoly[k]; var b2: Vector2 = mpoly[k + 1]; var seg := a.distance_to(b2)
			var t := 0.0
			while t < seg:
				var step := gap * (0.75 + 0.6 * WorldMath.hash2(ti, q, 920))
				if acc + (seg - t) < step: acc += seg - t; break
				t += step - acc; acc = 0.0; q += 1
				var p := a.lerp(b2, t / seg); var d := (b2 - a).normalized()
				if p.distance_to(c) < 30.0: continue   # the square
				for sd2 in [-1.0, 1.0]:
					var side: float = sd2
					if WorldMath.hash2(ti * 13 + q, int(side) + 2, 921) > 0.86: continue
					var ang := (PI * 0.5 + (WorldMath.hash2(ti, q * 2 + int(side > 0), 922) - 0.5) * 0.7) * side
					var sp := _wander(gf, ti, p, d.rotated(ang), r * (0.55 + 0.5 * WorldMath.hash2(q, ti, 923)), 0.98, 0.22, ti * 101 + q * 3 + int(side > 0))
					if sp.size() < 3: continue
					polys.append([sp, 7.0])
					if sp.size() >= 5 and WorldMath.hash2(ti, q, 924 + int(side > 0)) > 0.45:   # a back lane, roughly along the main street
						var mid: Vector2 = sp[int(sp.size() * 0.6)]; var sd := (sp[int(sp.size() * 0.6)] - sp[int(sp.size() * 0.6) - 1]).normalized()
						var lane_dir := sd.rotated(-PI * 0.5 * side * (1.0 if WorldMath.hash2(q, ti, 925) > 0.5 else -1.0))
						var lp := _wander(gf, ti, mid, lane_dir, gap * (1.0 + WorldMath.hash2(ti, q, 926)), 0.95, 0.25, ti * 211 + q)
						if lp.size() >= 3: polys.append([lp, 6.0])
		# the river bank: where the river runs through or past the town, a street follows it
		var bank := PackedVector2Array()
		for k in gf.river.size() - 1:
			var a: Vector2 = gf.river[k]; var b2: Vector2 = gf.river[k + 1]
			var n := maxi(1, int(a.distance_to(b2) / 25.0))
			for s in n + 1:
				var p := a.lerp(b2, float(s) / float(n)); var dd := (b2 - a).normalized().orthogonal()
				var pb := p + dd * 95.0 * (1.0 if (c - p).dot(dd) > 0.0 else -1.0)   # the town's own bank, clear of the water
				if gf.town_dn(ti, pb) < 1.0: bank.append(pb)
				elif bank.size() >= 3: break
		if bank.size() >= 3: polys.append([bank, 8.0])
		# houses along every street, both sides, every 12-15 m, set back from the kerb; lamps every 34 m
		var segs: Array = []
		for pi in polys.size():
			var pts: PackedVector2Array = polys[pi][0]
			for k in pts.size() - 1: segs.append([pts[k], pts[k + 1], float(polys[pi][1]), pi])
		var buck := _bucket(segs)
		for si in segs.size():
			var a: Vector2 = segs[si][0]; var b2: Vector2 = segs[si][1]; var w0: float = segs[si][2]
			# 11-28 (lead's review of chapters 5-6): on engine maps (AreaTowns) no house may stand off the town's tiles, so a street that wandered
			# past them was a bare dark line across the fields (the towns read as spiders): only the segments inside the town are drawn
			if gf is AreaTowns and gf.town_dn(ti, (a + b2) * 0.5) > 1.0: continue
			streets.append([a, b2, w0, ti])
			var along := (b2 - a).normalized(); var across := along.orthogonal(); var L := a.distance_to(b2)
			var s := 4.0; var hq := 0
			while s < L - 4.0:
				var step := 12.0 + 3.5 * WorldMath.hash2(ti * 31 + si, hq, 903)
				var mid := s + step * 0.5; s += step; hq += 1
				for sd2 in [-1.0, 1.0]:
					var side: float = sd2
					var hh := WorldMath.hash2(ti * 131 + si * 7 + hq, int(side) + 3, 904)
					var p := a + along * mid + across * side * (w0 * 0.5 + 4.5 + 3.0 * hh)
					var dn: float = gf.town_dn(ti, p)
					if dn > 1.0 or p.distance_to(c) < 32.0: continue
					if _near_street(segs, buck, si, p, 8.5): continue   # corners stay open
					var in_yard := false
					for f in gf.flats: if (f.c as Vector2).distance_to(p) < float(f.r) * 0.5 + 18.0: in_yard = true
					if in_yard: continue
					if not is_nan(gf.river_surface(p.x, p.y)) or gf._river_dist(p.x, p.y) < 80.0: continue   # no house in the river
					var keep := lerpf(0.97, 0.3, pow(dn, 1.4)) * keep_k
					if WorldMath.hash2(ti * 17 + si, hq * 2 + int(side > 0), 905) > keep: continue
					var core := dn < 0.28
					var w := (8.0 + 5.0 * hh) if not core else (12.0 + 8.0 * hh)
					var dd := 7.0 + 3.0 * WorldMath.hash2(hq, si, 906)
					var h := (5.0 + 3.0 * WorldMath.hash2(si, hq, 907)) if not core else (8.5 + 6.0 * WorldMath.hash2(si, hq, 908))
					if count >= 26 and dn < 0.16 and hh > 0.55:   # the capital's skyline: a few office and flat towers round the square
						w = 16.0 + 8.0 * hh; dd = 14.0 + 6.0 * WorldMath.hash2(si, hq, 910); h = 20.0 + 26.0 * WorldMath.hash2(hq, si, 911)
					var ang := atan2(-along.y, along.x)
					var idx := int(fposmod(atan2((p - c).y, (p - c).x) - rot, TAU) / TAU * count) % count
					places.append([p.x, p.y, w, dd, h, ang + (WorldMath.hash2(hq, si, 909) - 0.5) * 0.06, id, idx, (core and hh > 0.4) or h > 19.0, dn, 0.0 if side > 0.0 else PI])   # [10]: the turn that puts a kit house's front (+Z) to the street
			var ls := 15.0; var lq := 0
			while ls < L - 10.0:
				var side2 := 1.0 if lq % 2 == 0 else -1.0
				var lp := a + along * ls + across * side2 * (w0 * 0.5 + 1.0)
				if gf.town_dn(ti, lp) < 1.05: lamps.append([Vector3(lp.x, ground.call(lp.x, lp.y) + 7.0, lp.y), id, gf.town_dn(ti, lp)])
				ls += 34.0; lq += 1
	return {"places": places, "streets": streets, "lamps": lamps, "centres": centres}

## A street that wanders: steps of 22 m from p0 along dir, turning a little each step (a smooth noise of the town and street seeds),
## until it leaves the town (town_dn > lim) or reaches max_len. Returns the polyline (at least p0).
static func _wander(gf, ti: int, p0: Vector2, dir: Vector2, max_len: float, lim: float, bend: float, seed: int) -> PackedVector2Array:
	var out := PackedVector2Array([p0]); var p := p0; var d := dir.normalized(); var run := 0.0; var k := 0
	var ph := WorldMath.hash2(seed, 3, 930) * TAU
	while run < max_len:
		d = d.rotated(sin(ph + float(k) * 0.7) * bend * 0.5 + (WorldMath.hash2(seed, k, 931) - 0.5) * bend * 0.4)
		p += d * 22.0; run += 22.0; k += 1
		if gf.town_dn(ti, p) > lim: break
		if not is_nan(gf.river_surface(p.x, p.y)): break   # streets stop at the water
		out.append(p)
	return out

const BUCKET_M := 40.0
## Street segments by 40 m cell (each segment in every cell its box, grown by 16 m, touches): the house test reads one cell.
static func _bucket(segs: Array) -> Dictionary:
	var out := {}
	for k in segs.size():
		var a: Vector2 = segs[k][0]; var b: Vector2 = segs[k][1]
		var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(16, 16); var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(16, 16)
		for j in range(int(floorf(lo.y / BUCKET_M)), int(floorf(hi.y / BUCKET_M)) + 1):
			for i in range(int(floorf(lo.x / BUCKET_M)), int(floorf(hi.x / BUCKET_M)) + 1):
				var key := Vector2i(i, j)
				if not out.has(key): out[key] = []
				out[key].append(k)
	return out

static func _near_street(segs: Array, buck: Dictionary, skip: int, p: Vector2, r: float) -> bool:
	for k in buck.get(Vector2i(int(floorf(p.x / BUCKET_M)), int(floorf(p.y / BUCKET_M))), []):
		if k == skip or segs[k][3] == segs[skip][3]: continue   # its own street (the next 22 m piece) does not count
		var a: Vector2 = segs[k][0]; var b: Vector2 = segs[k][1]
		var ab := b - a; var l2 := ab.length_squared()
		var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0) if l2 > 1e-6 else 0.0
		if p.distance_to(a + ab * t) < r + float(segs[k][2]) * 0.5: return true
	return false

## Road surfaces: a ribbon a little above the ground, sampled every 20 m so it follows the land.
## A warm disc per town (the lit core seen from far away): a fan, COLOR.a = town index, UV.x = 0 at the centre and 1 at the rim.
static func core_mesh(centres: Array, radii: Array, ground: Callable, gf: GenField = null) -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES); st.set_normal(Vector3.UP)
	for k in centres.size():
		var c: Vector2 = centres[k][0]; var r: float = radii[k] * 1.1; var ti: int = k
		var y: float = float(ground.call(c.x, c.y)) + 3.0
		for s in 48:
			var a0 := TAU * s / 48.0; var a1 := TAU * (s + 1) / 48.0
			var r0 := r; var r1 := r
			if gf != null: r0 = gf.town_edge(ti, a0) * 1.05; r1 = gf.town_edge(ti, a1) * 1.05   # the glow follows the town's own edge
			for pt: Array in [[c, 0.0], [c + Vector2(cos(a0), sin(a0)) * r0, 1.0], [c + Vector2(cos(a1), sin(a1)) * r1, 1.0]]:
				st.set_color(Color(0, 0, 0, float(ti) / 63.0)); st.set_uv(Vector2(pt[1], 0)); st.add_vertex(Vector3(pt[0].x, y, pt[0].y))
	return st.commit()

static func street_mesh(streets: Array, ground: Callable) -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for sd in streets:
		var a: Vector2 = sd[0]; var b: Vector2 = sd[1]; var w: float = sd[2]
		var d := (b - a).normalized(); var o := Vector2(-d.y, d.x) * w * 0.5
		var n := maxi(1, int(a.distance_to(b) / 20.0))
		for k in n:
			var p0 := a.lerp(b, float(k) / n); var p1 := a.lerp(b, float(k + 1) / n)
			var v := [Vector3(p0.x + o.x, 0, p0.y + o.y), Vector3(p1.x + o.x, 0, p1.y + o.y), Vector3(p1.x - o.x, 0, p1.y - o.y), Vector3(p0.x - o.x, 0, p0.y - o.y)]
			for vi in 4: v[vi].y = ground.call(v[vi].x, v[vi].z) + 0.18
			var lat := o.normalized(); var ti := int(sd[3]) if sd.size() > 3 else 0
			for idx in [0, 1, 2, 0, 2, 3]:   # COLOR: lateral direction (rg), side (b), town index (a): the street shader widens far streets and lights them by town
				st.set_color(Color(lat.x * 0.5 + 0.5, lat.y * 0.5 + 0.5, 1.0 if idx < 2 else 0.0, float(ti) / 63.0))
				st.set_uv(Vector2(0.0 if idx < 2 or idx == 3 else 1.0, 1.0 if w > 9.0 else 0.0)); st.add_vertex(v[idx])   # UV.y: a main street
	return st.commit()
