extends SceneTree
## Headless proof: the b4 mineswpr cart (carts/mineswpr-logic.b4 +
## carts/mineswpr-play.b4) on TermGrid vs full screens from arcade mineswpr
## Direct (tests/mineswpr_screen_golden.json).
##
## Each session boots the cart with the session's rn seed, replays the typed
## keys through tm k / tm r (the cart's keys word) or an exec line (the mouse
## path), and compares every cell of the 80x25 grid: char, fg and bg.
##
## Run: godot --headless --path . --script res://tools/test_mineswpr_screen.gd
## Prints ok:/FAIL: per screen, then "proof: PASS" or "proof: FAIL"; exit 0 on PASS.
## Options (after --): --dump  print every b4 screen as text.

const Cart := preload("res://game/MineswprCart.gd")
const TermGridScript := preload("res://game/TermGrid.gd")
const GOLDEN_PATH := "res://tests/mineswpr_screen_golden.json"
const MAX_DIFFS := 8

var _checks := 0
var _fail := 0
var dump := false


func _check(cond: bool, msg: String) -> bool:
	_checks += 1
	print(("ok: " if cond else "FAIL: ") + msg)
	if not cond:
		_fail += 1
	return cond


## "" when the grid matches the golden screen, else the first few cell diffs.
func diff_screen(grid: TermGrid, want: Dictionary) -> String:
	var bg := {}
	for e in want["bg"]:
		bg[Vector2i(int(e[0]), int(e[1]))] = int(e[2])
	var diffs := []
	var count := 0
	for y in grid.grid_wh.y:
		var row: String = want["text"][y]
		var fg: String = want["fg"][y]
		for x in grid.grid_wh.x:
			var c := grid.char_at(x, y)
			var f := grid.fg_at(x, y)
			var b := grid.bg_at(x, y)
			var wc := row[x]
			var wf := fg[x].hex_to_int()
			var wb: int = bg.get(Vector2i(x, y), 0)
			if c != wc or f != wf or b != wb:
				count += 1
				if diffs.size() < MAX_DIFFS:
					diffs.append("(%d,%d) b4 '%s' fg%d bg%d != Direct '%s' fg%d bg%d"
						% [x, y, c, f, b, wc, wf, wb])
	if count == 0:
		return ""
	return "%d cells differ: %s" % [count, "; ".join(diffs)]


func run_session(s: Dictionary) -> void:
	var grid: TermGrid = TermGridScript.new()
	var cart = Cart.new()
	var err: String = cart.boot(grid, int(s["seed"]))
	if not _check(err.is_empty(), "%s: cart boots with seed %d %s" % [s["name"], s["seed"], err]):
		grid.free()
		return
	var n := 0
	var t0 := Time.get_ticks_msec()
	for step in s["steps"]:
		var what := ""
		if step.has("exec"):
			what = "exec %s" % JSON.stringify(step["exec"])
			err = cart.exec_line(step["exec"])
		else:
			what = "keys %s" % JSON.stringify(step["keys"])
			err = cart.type_keys(step["keys"])
		if not err.is_empty() or cart.vm.ds.size() != 0:
			_check(false, "%s step %d %s: %s ds=%s" % [s["name"], n, what, err, cart.vm.ds])
			cart.vm.ds.clear()
		if step.has("quit") and cart.quit_requested() != bool(step["quit"]):
			_check(false, "%s step %d %s: quit flag %s != Direct %s"
				% [s["name"], n, what, cart.quit_requested(), step["quit"]])
		if step.has("text"):
			if dump:
				print("-- %s step %d %s" % [s["name"], n, what])
				for y in grid.grid_wh.y:
					print(grid.row_text(y))
			var d := diff_screen(grid, step)
			_check(d.is_empty(), "%s step %d %s: screen %s" % [s["name"], n, what,
				"== Direct (2000 cells: char, fg, bg)" if d.is_empty() else d])
		n += 1
	print("   %s: %d steps in %d ms" % [s["name"], n, Time.get_ticks_msec() - t0])
	cart.dispose()
	grid.free()


func _initialize() -> void:
	dump = "--dump" in OS.get_cmdline_user_args()
	var gold = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN_PATH))
	if gold == null:
		print("FAIL: cannot read ", GOLDEN_PATH)
		print("proof: FAIL")
		quit(1)
		return
	print("golden: arcade %s mineswpr Direct (screen + shell + logic)" % gold["source"]["commit"].left(7))
	for s in gold["sessions"]:
		run_session(s)
	var ok := _fail == 0
	print("proof: %s (%d checks, %d failed)" % ["PASS" if ok else "FAIL", _checks, _fail])
	quit(0 if ok else 1)
