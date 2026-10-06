extends Control
class_name TermGrid
## TermGrid — J-free character-cell terminal (CHB/FGB/BGB), after jprez JKVM
## and arcade mineswpr/direct/term_grid.gd. Host surface for b4 `tm` (Phase 1 of
## arcade #45). Mineswpr will draw the board via put/puts (or bios emit/tg/tw).

signal cell_clicked(col: int, row: int, button: int)
signal cell_hovered(col: int, row: int) ## (-1, -1) when the mouse leaves

const FONT := preload("res://assets/NotoSansMono-Regular.ttf")

@export var grid_wh := Vector2i(80, 25)
@export var cell_wh := Vector2(15, 26)
@export var font_size := 24

var CHB := PackedInt32Array() ## unicode code points
var FGB := PackedByteArray() ## palette index per cell
var BGB := PackedByteArray() ## palette index per cell
var pal: PackedColorArray = make_palette()

var _hover := Vector2i(-1, -1)
var _baseline := 0.0


func _init() -> void:
	cscr()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(grid_wh) * cell_wh
	var asc := FONT.get_ascent(font_size)
	var desc := FONT.get_descent(font_size)
	_baseline = round((cell_wh.y - (asc + desc)) / 2.0 + asc)
	mouse_exited.connect(func() -> void: _set_hover(Vector2i(-1, -1)))


## clear screen: spaces, gray on black.
func cscr(fg: int = 7, bg: int = 0) -> void:
	var n := grid_wh.x * grid_wh.y
	CHB.resize(n)
	CHB.fill(32)
	FGB.resize(n)
	FGB.fill(fg)
	BGB.resize(n)
	BGB.fill(bg)
	queue_redraw()


func put(x: int, y: int, ch: String, fg: int = 7, bg: int = 0) -> void:
	if x < 0 or y < 0 or x >= grid_wh.x or y >= grid_wh.y:
		return
	var p := y * grid_wh.x + x
	CHB[p] = ch.unicode_at(0) if ch != "" else 32
	FGB[p] = fg
	BGB[p] = bg
	queue_redraw()


## Write a string left to right; returns the column after the last char.
func puts(x: int, y: int, s: String, fg: int = 7, bg: int = 0) -> int:
	for i in s.length():
		put(x + i, y, s[i], fg, bg)
	return x + s.length()


func char_at(x: int, y: int) -> String:
	return String.chr(CHB[y * grid_wh.x + x])


func fg_at(x: int, y: int) -> int:
	return FGB[y * grid_wh.x + x]


func bg_at(x: int, y: int) -> int:
	return BGB[y * grid_wh.x + x]


## One row of text (for tests / debugging).
func row_text(y: int) -> String:
	var s := ""
	for x in grid_wh.x:
		s += char_at(x, y)
	return s


func cell_at(pos: Vector2) -> Vector2i:
	var c := Vector2i((pos / cell_wh).floor())
	if c.x < 0 or c.y < 0 or c.x >= grid_wh.x or c.y >= grid_wh.y:
		return Vector2i(-1, -1)
	return c


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		_set_hover(cell_at(e.position))
	elif e is InputEventMouseButton and e.pressed:
		var c := cell_at(e.position)
		if c.x >= 0 and e.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			cell_clicked.emit(c.x, c.y, e.button_index)
			accept_event()


func _set_hover(c: Vector2i) -> void:
	if c != _hover:
		_hover = c
		cell_hovered.emit(c.x, c.y)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(grid_wh) * cell_wh), pal[0])
	for y in grid_wh.y:
		for x in grid_wh.x:
			var p := y * grid_wh.x + x
			var xy := Vector2(x, y) * cell_wh
			if BGB[p] != 0:
				draw_rect(Rect2(xy, cell_wh), pal[BGB[p]])
			var c := CHB[p]
			if c != 32 and FGB[p] != BGB[p]:
				draw_char(FONT, xy + Vector2(0, _baseline), String.chr(c), font_size, pal[FGB[p]])


## xterm-256 palette, verbatim from JKVM._make_palette / arcade TermGrid.
static func make_palette() -> PackedColorArray:
	var res := PackedColorArray()
	var ansi := [
		0x000000, 0xaa0000, 0x00aa00, 0xaaaa00,
		0x0000aa, 0xaa00aa, 0x00aaaa, 0xaaaaaa,
		0x555555, 0xff5555, 0x55ff55, 0xffff55,
		0x5555ff, 0xff55ff, 0x55ffff, 0xffffff,
	]
	for a in ansi:
		res.append(Color.hex(a * 0x100 + 0xff))
	var ramp := [0x00, 0x5F, 0x87, 0xAF, 0xD7, 0xFF]
	for r in ramp:
		for g in ramp:
			for b in ramp:
				res.append(Color.hex(((r << 16) + (g << 8) + b) * 0x100 + 0xff))
	var grays := [
		0x00, 0x12, 0x1C, 0x26, 0x30, 0x3A, 0x44, 0x4E,
		0x58, 0x62, 0x6C, 0x76, 0x80, 0x8A, 0x94, 0x9E,
		0xA8, 0xB2, 0xBC, 0xC6, 0xD0, 0xDA, 0xE4, 0xEE,
	]
	for v in grays:
		res.append(Color.hex(((v << 16) + (v << 8) + v) * 0x100 + 0xff))
	return res
