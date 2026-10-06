# TermGrid / `tm` host (arcade #45 Phase 1)

Smallest shippable terminal spike for rewriting mineswpr in b4.

## What landed

| Piece | Role |
|-------|------|
| `game/TermGrid.gd` | 80×25 CHB/FGB/BGB cells, xterm-256, `put` / `puts` / `cscr` |
| `game/B4Term.gd` | Host device: b4 opcode **`tm` = 0xBE** (Pascal `uhw_vt` / b4f) |
| `carts/hello-term.b4` | Clears screen, prints colored "hello term" / "color ok" |
| `scenes/HelloTerm.tscn` | Runs the cart and shows the grid |

### `tm` commands (cmd char on stack)

| Cmd | Stack | Effect |
|-----|-------|--------|
| `s` | — | clear screen (`ts`) |
| `g` | x y | goto xy (`tg`) |
| `a` | n | attr: fg = n&0xF, bg = (n>>4)&0xF (`ta`) |
| `e` | c | emit char (`tw`) |
| `l` | — | clear to end of line |
| `c` | — x y | cursor position |
| `k` / `r` | key stubs | for typed `mswp'` later |

## Run hello-term

```bash
# GUI
/workspace/tools/godot4 --path /workspace/wt-b4-term

# Headless proof (prints row text + exits 0 if buffers match)
/workspace/tools/godot4 --path /workspace/wt-b4-term --headless -- --proof
```

CLI smoke (must stay green):

```bash
printf '%s\n' '%C' '1 2 ad' '?d' '%q' \
  | /workspace/tools/godot4 --path /workspace/wt-b4-term --headless --script res://cli.gd
```

## Next: mineswpr in b4

1. ~~Port grid / flood / flag / prod~~ -- done: see [MINESWPR.md](MINESWPR.md).
2. Draw with `tm` (or TermGrid `put`/`puts`) — `vt'` colors as ANSI 0–15.
3. Shell `mswp'` needs character input (`tm` `r`/`k` + typed line).
4. Optional arcade edition host; **keep** Direct + Enhanced GDScript.

Do **not** embed Retro/Ngaro. Do **not** replace arcade's shipping mineswpr.
