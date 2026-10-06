extends SceneTree
## Generate tests/mineswpr_golden.json from arcade's mineswpr Direct logic.
##
## The golden vectors are what arcade games/mineswpr/direct/mineswpr_logic.gd
## does; tools/test_mineswpr_logic.gd checks the b4 cart against them.
##
## Run (Direct logic file can live anywhere, e.g. extracted from arcade main):
##   git -C /path/to/arcade show origin/main:games/mineswpr/direct/mineswpr_logic.gd > /tmp/mineswpr_logic.gd
##   godot --headless --path . --script res://tools/gen_mineswpr_golden.gd -- \
##     --logic /tmp/mineswpr_logic.gd --commit <arcade sha> [--out tests/mineswpr_golden.json]

const SEEDS := [1, 7, 45, 1234, 2013]
const PLAY_SEEDS := [45, 1234, 2013]
const PLAY_STEPS := 40

var Logic: GDScript


static func xy(c: int) -> Array:
	return [c % 16, c / 16]


## One row string per board row: two digits per cell, "<count><bits>".
static func grid_rows(g) -> Array:
	var rows := []
	for y in 16:
		var s := ""
		for x in 16:
			var v: int = g.grid[y * 16 + x]
			s += "%d%d" % [v >> 8, v & 7]
		rows.append(s)
	return rows


## Cheap order-sensitive signature of the whole grid (31-bit).
static func grid_sig(g) -> int:
	var h := 0
	for i in 256:
		h = (h * 31 + int(g.grid[i]) + i) & 0x7FFFFFFF
	return h


static func covered(g) -> int:
	return g.covered_count()


func apply(g, step: Array) -> void:
	var op: String = step[0]
	match op:
		"prod": g.prod(Logic.cell(step[1], step[2]))
		"flag+": g.flag_add(Logic.cell(step[1], step[2]))
		"flag-": g.flag_remove(Logic.cell(step[1], step[2]))
		"flood": g.flood(step[1], step[2])
		"game-new": g.game_new()
		_: push_error("unknown op " + op)


func state(g, full: bool) -> Dictionary:
	var d := {"flags": g.flag_count, "over": g.game_over, "covered": covered(g), "sig": grid_sig(g)}
	if full:
		d["grid"] = grid_rows(g)
	return d


func scenario(name: String, note: String, mines: Array, steps: Array) -> Dictionary:
	var g = Logic.new(1)
	var cells := []
	for m in mines:
		cells.append(Logic.cell(m[0], m[1]))
	g.load_mines(cells)
	var out := {"name": name, "note": note, "mines": mines, "start": state(g, true), "steps": []}
	for s in steps:
		apply(g, s)
		var st := {"do": s}
		st.merge(state(g, true))
		out["steps"].append(st)
	return out


func play(seed_value: int) -> Dictionary:
	var g = Logic.new(seed_value)
	var pick := RandomNumberGenerator.new()
	pick.seed = seed_value + 1000
	var out := {"name": "play-%d" % seed_value, "seed": seed_value,
		"note": "Logic.new(seed) then scripted random ops; game-new mid-way keeps drawing from the same rng",
		"start": state(g, true), "steps": []}
	for i in PLAY_STEPS:
		var s: Array
		if i == PLAY_STEPS / 2:
			s = ["game-new"]
		else:
			var r := pick.randi_range(0, 9)
			var op := "prod" if r < 5 else ("flag+" if r < 8 else "flag-")
			s = [op, pick.randi_range(0, 15), pick.randi_range(0, 15)]
		apply(g, s)
		var st := {"do": s}
		st.merge(state(g, false))
		out["steps"].append(st)
	out["end"] = state(g, true)
	return out


## JSON with one level of structure per line: scalar arrays and small dicts of
## scalars stay inline, grid rows get one line each (diff-friendly, compact).
static func pretty(v, ind: String) -> String:
	var nxt := ind + "  "
	if v is Dictionary:
		var simple := true
		for k in v:
			if v[k] is Dictionary or (v[k] is Array and not _inline_array(v[k])):
				simple = false
		if simple:
			return JSON.stringify(v, "", false)
		var parts := []
		for k in v:
			parts.append(nxt + JSON.stringify(str(k)) + ": " + pretty(v[k], nxt))
		return "{\n" + ",\n".join(parts) + "\n" + ind + "}"
	if v is Array:
		if _inline_array(v):
			return JSON.stringify(v, "", false)
		var parts := []
		for e in v:
			parts.append(nxt + pretty(e, nxt))
		return "[\n" + ",\n".join(parts) + "\n" + ind + "]"
	return JSON.stringify(v, "", false)


## Arrays of numbers / short strings stay on one line; grid rows do not.
static func _inline_array(a: Array) -> bool:
	for e in a:
		if e is Array or e is Dictionary or (e is String and e.length() > 8):
			return false
	return true


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var logic_path := ""
	var commit := "unknown"
	var out_path := "res://tests/mineswpr_golden.json"
	var i := 0
	while i < args.size():
		match args[i]:
			"--logic": logic_path = args[i + 1]; i += 1
			"--commit": commit = args[i + 1]; i += 1
			"--out": out_path = args[i + 1]; i += 1
		i += 1
	if logic_path.is_empty():
		printerr("usage: -- --logic <mineswpr_logic.gd> [--commit sha] [--out path]")
		quit(2)
		return
	Logic = GDScript.new()
	Logic.source_code = FileAccess.get_file_as_string(logic_path)
	if Logic.reload() != OK:
		printerr("cannot compile ", logic_path)
		quit(2)
		return

	var doc := {
		"about": "Golden vectors for carts/mineswpr-logic.b4, generated from arcade mineswpr Direct by tools/gen_mineswpr_golden.gd. Grid rows: 16 strings of 16 cells, two digits per cell = armed-neighbor-count then bits (1=mine 2=cover 4=flag). sig = h=(h*31+cell+i)&0x7FFFFFFF over cells 0..255.",
		"source": {"repo": "tangentstorm/arcade", "commit": commit,
			"file": "games/mineswpr/direct/mineswpr_logic.gd"},
		"points": [], "c2xy": [], "seeds": [], "scenarios": [], "play": []}

	for y in [-1, 0, 7, 15, 16]:
		for x in [-1, 0, 9, 15, 16]:
			var p := {"x": x, "y": y, "inbounds": Logic.inbounds(x, y)}
			if p["inbounds"]:
				p["cell"] = Logic.cell(x, y)
			doc["points"].append(p)
	for c in [0, 1, 15, 16, 17, 128, 254, 255]:
		var v: Vector2i = Logic.c2xy(c)
		doc["c2xy"].append([c, v.x, v.y])

	for s in SEEDS:
		var g = Logic.new(s)
		var mines := []
		for c in 256:
			if g.has(c, Logic.MINE):
				mines.append(c)
		doc["seeds"].append({"seed": s, "mines": mines, "grid": grid_rows(g)})

	var sc: Array = doc["scenarios"]
	sc.append(scenario("flood-single-mine", "one mine: prod a zero cell uncovers everything else",
		[[2, 2]], [["prod", 0, 0]]))
	sc.append(scenario("flood-cardinal-only", "PORT.md: flood spreads n/w/e/s only; (1,1) is a diagonal hint of zero cell (2,2) and stays covered",
		[[1, 0], [0, 1], [5, 5]], [["prod", 10, 10]]))
	sc.append(scenario("diagonal-wall", "flood stops at a diagonal line of hints; second prod on the far side",
		[[3, 0], [2, 1], [1, 2], [0, 3]], [["prod", 0, 0], ["prod", 10, 10]]))
	sc.append(scenario("hint-prod", "prodding a hint cell uncovers only it",
		[[3, 3]], [["prod", 3, 4]]))
	sc.append(scenario("flags", "flag+ twice counts once; flood ignores flags (uncovers, keeps bit); cannot flag uncovered; flag-; prod on flagged mine = flag- then dead",
		[[8, 8]], [["flag+", 0, 5], ["flag+", 0, 5], ["prod", 0, 0], ["flag+", 0, 6],
			["flag-", 0, 5], ["flag+", 8, 8], ["prod", 8, 8]]))
	sc.append(scenario("prod-on-flag", "PORT.md: ? on a flag = flag- then prod (safe cell floods); flag- on an unflagged cell is a no-op",
		[[8, 8], [9, 8]], [["flag+", 3, 3], ["flag+", 12, 12], ["prod", 3, 3], ["flag-", 4, 4]]))
	sc.append(scenario("after-game-over", "PORT.md: commands still work after GAME OVER",
		[[0, 0], [15, 15]], [["prod", 0, 0], ["prod", 8, 8], ["flag+", 15, 15], ["prod", 15, 15]]))
	sc.append(scenario("flood-edges", "flood ( x y - ) drops out-of-range points (no row wrap); flood keeps flags and flagCount",
		[[4, 4]], [["flood", -1, 0], ["flood", 16, 3], ["flood", 3, -1], ["flood", 0, 16],
			["flag+", 15, 1], ["flood", 15, 0], ["flag-", 15, 1], ["flag+", 15, 2]]))

	for s in PLAY_SEEDS:
		doc["play"].append(play(s))

	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		printerr("cannot write ", out_path)
		quit(2)
		return
	f.store_string(pretty(doc, "") + "\n")
	f.close()
	print("wrote ", out_path, ": ", doc["seeds"].size(), " seeds, ", sc.size(), " scenarios, ",
		doc["play"].size(), " play runs")
	quit(0)
