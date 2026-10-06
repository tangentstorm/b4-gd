# mineswpr logic in b4 (arcade #45 Phase 2)

`carts/mineswpr-logic.b4` ports the game words of `mineswpr.org`
(Retro Forth 11, 2013) to b4, matching arcade's
`games/mineswpr/direct/mineswpr_logic.gd`. Logic only: no draw, no `mswp'`
shell yet (Phase 3).

## Run the proof

```bash
# once per fresh checkout (builds the class_name cache in .godot/)
godot --headless --path . --import

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

## Next (Phase 3)

- Port the `draw`, `show`, and `(x,y)` words to `tm`: the striped brackets,
  `|m` for the active cell, and the GAME OVER title.
- Port the `mswp'` shell: the line reader on `tm` `k`/`r`, hex numbers, a
  persistent stack, `+ - ?`, `a`-`f`, `r`, `q`, and `if-cell-ok` setting `K`.
- Add a playable scene that hosts the cart (TermGrid + `tm` + `rn`), plus a
  screen golden vs Direct `mineswpr_screen.gd`.
- Consider making `B4Asm` fail (not just warn) on unknown tokens: an undefined
  label silently assembles to nothing (the proof still catches it at runtime).
