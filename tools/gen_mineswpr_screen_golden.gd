extends SceneTree
## Generate tests/mineswpr_screen_golden.json: full 80x25 screens (chars, fg,
## bg) from arcade mineswpr Direct for scripted keystroke sessions.
## tools/test_mineswpr_screen.gd replays the same keys into the b4 cart.
##
## This drives Direct's own mineswpr_logic.gd, mswp_shell.gd and
## mineswpr_screen.gd, and mirrors the few lines of direct/game.gd that glue
## them (line editor, run(), draw_screen()). The term is b4-gd's TermGrid, which
## has the same put/puts/cscr API as Direct's term_grid.gd.
##
## Run:
##   mkdir -p /tmp/mswp && for f in mineswpr_logic mswp_shell mineswpr_screen; do
##     git -C /path/to/arcade show origin/main:games/mineswpr/direct/$f.gd > /tmp/mswp/$f.gd; done
##   godot --headless --path . --script res://tools/gen_mineswpr_screen_golden.gd -- \
##     --direct /tmp/mswp --commit "$(git -C /path/to/arcade rev-parse origin/main)"
##
## (One session types "+7"; Godot's hex_to_int logs an "Invalid hexadecimal
## notation character" error for it. That is expected: it is how Direct reads it.)

const TermGridScript := preload("res://game/TermGrid.gd")
const MAX_INPUT := 70 ## direct/game.gd

var Logic: GDScript
var ShellScript: GDScript
var Screen: GDScript

# -- direct/game.gd state --------------------------------------------------------
var term: TermGrid
var game
var shell
var input := ""
var last_cmd := ""
var _active := -1
var _error := ""
var quit_flag := false


func _on_quit() -> void:
	quit_flag = true


func new_game(seed_value: int) -> void:
	game = Logic.new(seed_value)
	shell = ShellScript.new(game)
	shell.quit_requested.connect(_on_quit)
	input = ""
	last_cmd = ""
	_error = ""
	quit_flag = false
	draw_screen()


func run(line: String) -> void:
	shell.eval_line(line)
	_error = shell.last_error
	if line.strip_edges() != "":
		last_cmd = line.strip_edges()
	draw_screen()


func draw_screen() -> void:
	_active = game.active_cell
	game.active_cell = -1
	_render()


## The cursor stays on: no time passes between keys here (direct/game.gd
## blinks it every 0.5 s).
func _render() -> void:
	Screen.render(term, game, shell, {
		"active": _active, "hover": -1, "input": input,
		"cursor": true, "last": last_cmd.left(11),
		"cleared": game.cleared(), "error": _error,
	})


## direct/game.gd _unhandled_key_input, by character.
func key(ch: String) -> void:
	if ch == "\n":
		var line := input
		input = ""
		run(line)
	elif ch == "\b":
		input = input.left(-1) if input != "" else ""
		_render()
	else:
		var u := ch.unicode_at(0)
		if u < 32 or u > 126:
			return
		if input.length() < MAX_INPUT:
			input += ch
		_render()


# -- snapshots --------------------------------------------------------------------
func snap(step: Dictionary) -> Dictionary:
	var text := []
	var fg := []
	var bg := []
	for y in term.grid_wh.y:
		text.append(term.row_text(y))
		var f := ""
		for x in term.grid_wh.x:
			f += "%X" % term.fg_at(x, y)
			if term.bg_at(x, y) != 0:
				bg.append([x, y, term.bg_at(x, y)])
		fg.append(f)
	var out := step.duplicate()
	out["quit"] = quit_flag
	out["text"] = text
	out["fg"] = fg
	out["bg"] = bg
	return out


func do_keys(s: String) -> Dictionary:
	for i in s.length():
		key(s[i])
	return snap({"keys": s})


func do_exec(line: String) -> Dictionary:
	run(line)
	return snap({"exec": line})


# -- picks from the Direct board ------------------------------------------------------
func find_cell(pred: Callable) -> Vector2i:
	for c in 256:
		if pred.call(c):
			return Vector2i(c % 16, c / 16)
	return Vector2i(-1, -1)


func is_zero(c: int) -> bool:
	return game.has(c, 1) and not game.has(c, 0) and game.armed_neighbor_count(c) == 0


func is_hint(c: int) -> bool:
	return game.has(c, 1) and not game.has(c, 0) and not game.has(c, 2) \
		and game.armed_neighbor_count(c) > 0


func is_mine(c: int) -> bool:
	return game.has(c, 0)


func is_safe_covered(c: int) -> bool:
	return game.has(c, 1) and not game.has(c, 0) and not game.has(c, 2)


static func cmd(p: Vector2i, op: String) -> String:
	return "%X %X %s\n" % [p.x, p.y, op]


func session_play() -> Dictionary:
	new_game(45)
	var snaps := [snap({"keys": ""})]
	snaps.append(do_keys("3 4"))                        # typing: prompt only
	snaps.append(do_keys("\b\b\b5 C +\n"))              # rubout, flag
	snaps.append(do_keys("a b +\n"))                    # a..f words
	snaps.append(do_keys("a b -\n"))                    # unflag
	snaps.append(do_keys(cmd(find_cell(is_zero), "?"))) # flood
	snaps.append(do_keys(cmd(find_cell(is_hint), "?"))) # one hint
	var f := find_cell(is_hint)
	snaps.append(do_keys(cmd(f, "+")))                  # flag a covered cell
	snaps.append(do_keys(cmd(f, "?")))                  # ? on a flag: flag- then prod
	snaps.append(do_keys("3\n"))                        # stack persists ...
	snaps.append(do_keys("4 ?\n"))                      # ... 3 4 ?
	snaps.append(do_keys("  hello 1 -2 zz 7  \n"))      # unknown words, last: strip + left 11
	snaps.append(do_keys("--5 +7 -+3 ff FFFF 7fffffff -80000000 12345678 123456789\n"))
	snaps.append(do_keys("reset\n"))
	snaps.append(do_keys("1 2 3 4 5 6 7 8 9 A B C D E F 10 11 12 13 14 15 16 17 18 19 1A\n"))
	snaps.append(do_keys("10 0 ? 0 10 + -1 3 ?\n"))     # out of range: dropped
	snaps.append(do_keys("reset 1 2"))                  # pending typed input ...
	snaps.append(do_exec("%X %X ?" % [find_cell(is_safe_covered).x, find_cell(is_safe_covered).y]))
	snaps.append(do_keys("\n"))                         # ... still there for Enter
	snaps.append(do_keys("r\n"))                        # game-new, same rng stream
	snaps.append(do_keys(cmd(find_cell(is_mine), "?"))) # GAME OVER
	snaps.append(do_keys("1 1 + 2 2 ?\n"))              # commands after GAME OVER
	var long := ""
	for i in 38:
		long += "e "
	snaps.append(do_keys(long))                         # 76 chars typed, 70 kept
	snaps.append(do_keys("\n"))
	snaps.append(do_keys("play\n"))                     # reset + game-new
	snaps.append(do_keys("q\n"))                        # mineswpr-exit-hook
	return {"name": "play", "seed": 45, "steps": snaps}


func session_clear() -> Dictionary:
	new_game(2013)
	var snaps := [snap({"keys": ""})]
	var flags := ""
	var n := 0
	for c in 256:
		if is_mine(c) and n < 3:
			flags += "%X %X + " % [c % 16, c / 16]
			n += 1
	snaps.append(do_keys(flags + "\n"))
	var lines := 0
	while not game.cleared():
		var line := ""
		for c in 256:
			# a prod may flood cells queued later on the line; prodding an
			# uncovered cell again is a no-op, as in Direct
			if is_safe_covered(c) and line.length() + 6 <= MAX_INPUT:
				line += "%X %X ? " % [c % 16, c / 16]
		lines += 1
		if lines == 2:
			snaps.append(do_keys(line + "\n"))
		else:
			for i in line.length():
				key(line[i])
			key("\n")
			snaps.append({"keys": line + "\n"}) # replayed, screen not stored
	snaps.append(snap({"keys": ""}))  # ALL CLEAR
	return {"name": "all-clear", "seed": 2013, "steps": snaps}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var dir := ""
	var commit := "unknown"
	var out_path := "res://tests/mineswpr_screen_golden.json"
	var i := 0
	while i < args.size():
		match args[i]:
			"--direct": dir = args[i + 1]; i += 1
			"--commit": commit = args[i + 1]; i += 1
			"--out": out_path = args[i + 1]; i += 1
		i += 1
	if dir.is_empty():
		printerr("usage: -- --direct <dir with mineswpr_logic.gd mswp_shell.gd mineswpr_screen.gd> [--commit sha]")
		quit(2)
		return
	Logic = _load(dir.path_join("mineswpr_logic.gd"))
	ShellScript = _load(dir.path_join("mswp_shell.gd"))
	Screen = _load(dir.path_join("mineswpr_screen.gd"))
	if Logic == null or ShellScript == null or Screen == null:
		quit(2)
		return
	term = TermGridScript.new()

	var doc := {
		"about": "Screen golden for carts/mineswpr-play.b4 (+ mineswpr-logic.b4), generated from arcade mineswpr Direct by tools/gen_mineswpr_screen_golden.gd. Each step is typed keys (\\n Enter, \\b Backspace) or an exec line (Direct run(), the mouse path), then the whole 80x25 screen: text rows, fg rows (one hex digit per cell), and [x, y, bg] for every cell whose bg is not 0. Cursor always on.",
		"source": {"repo": "tangentstorm/arcade", "commit": commit,
			"files": ["games/mineswpr/direct/mineswpr_logic.gd",
				"games/mineswpr/direct/mswp_shell.gd",
				"games/mineswpr/direct/mineswpr_screen.gd",
				"games/mineswpr/direct/game.gd (line editor, mirrored)"]},
		"sessions": [session_play()],
	}
	doc["sessions"].append(session_clear())

	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		printerr("cannot write ", out_path)
		quit(2)
		return
	f.store_string(_pretty(doc) + "\n")
	f.close()
	var n := 0
	for s in doc["sessions"]:
		for st in s["steps"]:
			n += 1 if st.has("text") else 0
	print("wrote ", out_path, ": ", doc["sessions"].size(), " sessions, ", n, " screens")
	term.free()
	quit(0)


func _load(path: String) -> GDScript:
	var src := FileAccess.get_file_as_string(path)
	if src.is_empty():
		printerr("cannot read ", path)
		return null
	var s := GDScript.new()
	s.source_code = src
	if s.reload() != OK:
		printerr("cannot compile ", path)
		return null
	return s


## One screen row per line keeps diffs readable.
static func _pretty(doc: Dictionary) -> String:
	var out := "{\n"
	out += '  "about": %s,\n' % JSON.stringify(doc["about"])
	out += '  "source": %s,\n' % JSON.stringify(doc["source"])
	out += '  "sessions": [\n'
	var ss := []
	for s in doc["sessions"]:
		var t := '    {"name": %s, "seed": %d,\n' % [JSON.stringify(s["name"]), s["seed"]]
		t += '     "steps": [\n'
		var st := []
		for step in s["steps"]:
			var head := {}
			for k in step:
				if k not in ["text", "fg", "bg"]:
					head[k] = step[k]
			if not step.has("text"):
				st.append("      " + JSON.stringify(head))
				continue
			var u := "      {" + JSON.stringify(head).trim_prefix("{").trim_suffix("}") + ",\n"
			u += '       "text": [\n' + _rows(step["text"]) + "\n       ],\n"
			u += '       "fg": [\n' + _rows(step["fg"]) + "\n       ],\n"
			u += '       "bg": ' + JSON.stringify(step["bg"]) + "}"
			st.append(u)
		t += ",\n".join(st) + "\n     ]}"
		ss.append(t)
	out += ",\n".join(ss) + "\n  ]\n}"
	return out


static func _rows(rows: Array) -> String:
	var r := []
	for row in rows:
		r.append("        " + JSON.stringify(row))
	return ",\n".join(r)
