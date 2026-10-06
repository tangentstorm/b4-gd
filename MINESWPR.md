# mineswpr in b4 (arcade #45 Phases 2 and 3)

`mineswpr.org` (Retro Forth 11, 2013) rewritten as a b4 program that plays on
the TermGrid / `tm` terminal:

- `carts/mineswpr-logic.b4` (Phase 2): the game words, matching arcade's
  `games/mineswpr/direct/mineswpr_logic.gd`.
- `carts/mineswpr-play.b4` (Phase 3): `draw` / `show` / `(x,y)`, the `mswp'`
  shell and its line editor, matching Direct's `mineswpr_screen.gd`,
  `mswp_shell.gd`, and the input part of `game.gd`.
- `scenes/Mineswpr.tscn`: the playable scene.

## Play (Phase 3)

```bash
# once per fresh checkout (builds the class_name cache in .godot/)
godot --headless --path . --import

# play: type at the ok prompt, e.g. `0 0 ?`, `5 c +`, `a b -`, `r`, `q`
godot --path . res://scenes/Mineswpr.tscn            # random board
godot --path . res://scenes/Mineswpr.tscn -- --seed 45

# scene smoke: sends InputEventKeys for a short game plus one right-click
# and a hover check ("hover proof: PASS"), prints the screen, "scene proof: PASS"
godot --headless --path . res://scenes/Mineswpr.tscn -- --seed 45

# screen proof vs arcade Direct: "proof: PASS (32 checks, 0 failed)"
godot --headless --path . --script res://tools/test_mineswpr_screen.gd
```

In the scene, keys go to the cart: printable characters edit the line, Enter
runs it, and Backspace deletes. Left click runs `x y ?`. Right click runs
`x y +`, or `x y -` on a flag. F2 boots a fresh cart, `q` halts the cart (the
original's exit hook), and Esc closes the window.

Hover: the scene inks the `[` and `]` of the board cell under the mouse Y
(11), like Direct's `|Y`. The host does this as an overlay, not the cart,
because a full redraw costs about 90 ms. The overlay saves the bracket colors,
is lifted before every cart call and put back after, so cart draws never wipe
it and never see it.

### Screen proof

`tools/test_mineswpr_screen.gd` boots the cart with a seed and replays typed
keys through `tm k` / `tm r` (the cart's `keys` word). It also replays one
`exec` line, which is the mouse path. After each step it compares all 2000
cells (char, fg, and bg) with `tests/mineswpr_screen_golden.json`.

That golden file comes from arcade Direct's own logic, shell, and screen
scripts, run by `tools/gen_mineswpr_screen_golden.gd` (the generator mirrors
the few lines of `game.gd` that glue them). It covers 30 screens in 2 sessions:

- **play** (seed 45): typing without Enter, Backspace, flag and unflag through
  `a`-`f`, a flood, a hint, `?` on a flag, the stack persisting across lines,
  and unknown words. It types the number edge cases `--5 +7 -+3 ff
  -80000000 123456789` as Godot reads them. It also covers a stack line
  clipped at column 80, out-of-range points, a mouse exec while a typed line is
  pending, `r`, GAME OVER with the mines shown, commands after GAME OVER, a
  76-character line (70 kept), `play`, `reset`, and `q` (the quit flag is
  checked too).
- **all-clear** (seed 2013): flags 3 mines, then prods every safe cell over
  typed lines until the side panel shows `ALL CLEAR`.

Mutants fail it. Swapping the stripe colors fails with 798 cells, turning off
the `+7` -> 0 rule fails with 35, a cursor with fg 0 fails with 1, and a typo
in a word name fails at assembly.

Regenerate (deterministic):

```bash
mkdir -p /tmp/mswp && for f in mineswpr_logic mswp_shell mineswpr_screen; do
  git -C /path/to/arcade show origin/main:games/mineswpr/direct/$f.gd > /tmp/mswp/$f.gd; done
godot --headless --path . --script res://tools/gen_mineswpr_screen_golden.gd -- \
  --direct /tmp/mswp --commit "$(git -C /path/to/arcade rev-parse origin/main)"
```

The current file comes from arcade `bc1b151`. One expected Godot error gets
logged when the generator runs, for `+7` (`hex_to_int`).

### How the play cart works

`game/MineswprCart.gd` builds one `B4VM` with `tm` (`B4Term` on the scene's
`TermGrid`) and `rn` (`B4Rand`). It assembles the `__code__` of both carts as
one program, logic first. The cart's immediate code turns autowrap off, runs
`game-new`, and draws. After that the host only calls these entry words:

| Word | Stack | Notes |
|---|---|---|
| `keys` | - | drains the `tm` key queue: 20-7E edit the line (max 70), 0D/0A run it, 08/7F delete |
| `exec` | a n - | runs the line at `a`, then draws (the original's `ok` was revectored to `draw`). Mouse clicks use it |
| `blink` | - | toggles the cursor and redraws the prompt row |
| `draw` | - | full redraw |

Typing redraws only the prompt row. Enter (`exec`) redraws everything, which
takes about 90 ms in the GDScript VM.

Shell (`mswp'`): tokens are runs of non-spaces. `+ - ?` go through `cell-ok?`
(if-cell-ok), which needs a depth of at least 2, pops y then x, drops points
that are off the board, and sets `K` (active-cell). The other words are
`a`-`f`, `r` (`game-new`), `q` (sets `Z`), and Direct's Retro extras `play` and
`reset`. Anything else is read as a hex number by `hex?`. That reading
reproduces Direct's `parse_hex` on Godot, quirks included: one leading `-`,
at most 8 chars after it, one more sign allowed, and a `+` sign giving 0.
Failing all of those gives `word ?` on the status line. The stack lives in RAM
at `$9200` and persists between lines.

Draw: the `tm` words `at ink emit`, plus `put"`, which prints the
zero-terminated string compiled after the call (`put" 'o'k' 00`; each empty
part between quotes is a space, and `'` itself is `lb 27 emit`). `(x,y)`
picks the glyph and ink (mine on GAME OVER, flag, cover, hint, zero), the
striped brackets `|c`/`|K`, `|k` to hide them, and `|m` for the active cell.
`A` holds the active cell shown by the last full draw.

Registers used by the play cart are `A B C D E H L M P R S T U V W Z`, all
listed at the top of the cart. Buffers are at `$9000`-`$97FF`.

### Phase 3 gaps

- **Hover** is done, host-side (see Play above), because a cart redraw is too
  slow for every mouse move.
- **Esc label:** the cart still draws Direct's `Esc menu` (arcade PauseOverlay).
  The standalone scene overwrites it to `Esc quit` after each cart call.
- **Cursor blink:** done. Key redraws keep the previous blink state; `keys`
  forces the cursor on afterward with no extra redraw (Direct's order). Goldens
  still see the cursor on (no blink between proof keys).
- **32-bit cells:** done. `B4VM.ds` is `Array[int]` (was `PackedInt32Array`,
  which wrapped `FFFFFFFF` to `-1`), and the shell stack is host-backed (`ss`)
  so cells stay full Godot ints like Direct. Cap remains 256 (Direct has none).
- `flood-cursor` (a debug display) is not ported. It is always -1 when Direct
  draws. Skipped (debug-only).
- `q` halts the cart in the standalone scene; arcade's mineswpr_b4 host returns
  to the gallery.
- Each full redraw costs about 25k VM steps, roughly 90 ms. That is fine for
  typed play, but too slow to redraw on every mouse move.

## Logic proof (Phase 2)

```bash
# golden-vector proof: prints ok:/FAIL: lines, then "proof: PASS", exit 0
godot --headless --path . --script res://tools/test_mineswpr_logic.gd
```

The proof assembles the cart on a fresh `B4VM` for each vector, runs the b4
words through `imrun`, and compares registers and grid RAM with
`tests/mineswpr_golden.json`. It checks:

- the point words `inbounds?`, `cell`, and `c>xy`, including edges and wrap
- `game-new` for 5 seeds: the same 24 mines and hints as Direct `Logic.new(seed)`
- 8 scripted scenarios: cardinal-only flood, a diagonal hint wall, a hint
  prod, the flag rules, `?` on a flag (`flag-` then prod), play after
  GAME OVER, and flood edges (no row wrap, flood keeps flags)
- 3 seeded play runs, 40 steps each, with a mid-run `game-new` that keeps
  drawing from the same rng

Options: `-- --cart <path>` checks another cart (mutation testing), and
`-- --max-steps <n>` sets the per-word step guard. The proof also passes with
the VM default of 100000.

## Regenerate the golden vectors (from arcade Direct)

```bash
git -C /path/to/arcade show origin/main:games/mineswpr/direct/mineswpr_logic.gd > /tmp/mineswpr_logic.gd
godot --headless --path . --script res://tools/gen_mineswpr_golden.gd -- \
  --logic /tmp/mineswpr_logic.gd --commit "$(git -C /path/to/arcade rev-parse origin/main)"
```

Output is deterministic. The current file comes from arcade `5e3962c`.

## Words

Cells are 32-bit words at `@G` (`$8000`). A cell `c` on the stack is an index
from 0 to `FF` (`y*10+x`, hex), the same as in Direct. The bit layout matches
the original: bit 0 = mine, bit 1 = cover, bit 2 = flag, and the armed-neighbor
count is stored as `$100` per neighbor.

| Word | Stack | Notes |
|---|---|---|
| `c>a` | c - a | ram address of cell |
| `cell` | x y - c | |
| `c>xy` | c - x y | |
| `inbounds?` | x y - f | -1 / 0 |
| `has?` | c e - f | 1 / 0, e = bit number |
| `incl` `excl` | c e - | set or clear bit e |
| `uncover` | c - | |
| `armed-neighbor-count` | c - n | |
| `armed-neighbor-add` | c - | |
| `randcell` | - c | `10 rn` for x, then for y (same order as Direct) |
| `needs-visit?` `keep-going?` | c - f | |
| `flood` | x y - | recursive and cardinal-only (n w e s). Ignores flags |
| `dead` | - | gameOver? on |
| `flaggable?` | c - f | covered and not flagged |
| `flag+` `flag-` | c - | updates flagCount |
| `prod` | c - | `flag-`, then `dead` or `flood` |
| `mine-set` | c - | |
| `nbr-add` `mine-hints` `hints-create` | | hint counts |
| `mine-add` | - | random empty cell (recursive retry, like the original) |
| `grid-fill` `game-reset` `game-new` | - | |
| `covered-count` | - n | extra (not in the original) |

Registers: `G` holds the grid, `N` mineCount (`18`), `F` flagCount, `O`
gameOver?, and `K` active-cell (-1, for Phase 3). `I J X Y` are scratch.

## Host and VM changes

- `game/B4Rand.gd`: `rn ( n - r )` uses opcode `$BD`, a free public byte next to
  `tm`. It is backed by `RandomNumberGenerator.randi_range(0, n-1)`, so a given
  seed produces the same mines as Direct.
- `B4VM._i8` fix: signed hop offsets now use two's complement, as JS b4 does.
  Before, every backward hop (`.o` loops, `nx`) went to the wrong place. The
  Phase 1 carts had no loops, so nothing caught it.
- `B4VM.max_steps` / `guard_hit` replace the hard-coded `imrun` guard of 100000
  (the default is unchanged), and `B4Asm.label(name)` gives a label's address.

## Host, VM and assembler changes in Phase 3

- `B4Term`: `tm k` / `tm r` now read the real key queue (`push_key`), which the
  scene fills from `_unhandled_key_input`. A new `tm w ( f - )` sets autowrap.
  With autowrap off, characters past column 79 are dropped, which matches
  Direct's `puts`.
- `B4Asm` now fails on an unknown token, an unknown macro, a macro outside a
  word, or a bad `$` literal. Before, a typo or a forward reference assembled
  to nothing and only printed a warning. All carts still assemble.
- `B4VM.step` caches opcode names. `dis()` scanned the opcode enum on every
  step, and a full redraw now takes about 90 ms instead of about 130 ms.
- `B4VM.ds` / `cs` are `Array[int]` (64-bit). `PackedInt32Array` made
  `FFFFFFFF` wrap to `-1` during `hex?`.
- Shell stack device `ss` (0xBC) on `MineswprCart`: full-int push/pop so
  stack cells match Direct after `upush` (RAM `wv`/`rv` are still 32-bit).
