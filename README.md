# Backrooms: Signal Lost

First-person backrooms horror in **Godot 4.6**. Three floors, one way down.
Recover a reference tape, break the feedback loop, send the reply, leave
through the white door. Something in the corridors is learning you.

## The game

- **Level 0 · The Lobby** — yellow offices, west cubicles, service tunnels,
  server farm, dark pocket, break room. Station 01 + lore scraps. East stairs down.
- **Level 1 · Concrete Halls** — bare concrete maze on a hall grid. Station 02 north.
- **Level 2 · Pipe Dreams** — cold machine maze under pipe-run backbones.
  Station 03 north, white-door exit east. Locked until 03 is done.
- **193×193 handmade-feel maze per level** (~579 m per side). Same landmarks,
  separated by dense level-specific filler: partition drift + baffles (L0),
  hall grid + pillar breaks (L1), pipe backbones + hatches (L2).
- Survival meters (water/food/stamina), flash pulse, 3 glowsticks, field journal,
  crouch-to-hide stealth, and a stalker entity that hunts by sound and sight.
- **2-player co-op** over LAN (host/join from the menu), shared objectives.

## Play (macOS)

Double-click `PLAY-BACKROOMS.command` — it installs the app to Desktop and launches it.
If the normal app hangs on launch, use `PLAY-BACKROOMS-SAFE.command` (OpenGL renderer).

Or run from source with Godot 4.6:

```sh
godot --path backrooms
```

Seeded runs: enter a seed on the menu (default 1234) — same seed, same maze.

## Preview without playing

Open `build/review/index.html` in a browser: full maps of all 3 levels with a
zone/marker legend, 14 in-game screenshots, maze vistas, controls, zone guide.
`build/screenshots.zip` is the same page packed up.

## Controls

| Key | Action |
|-----|--------|
| W A S D / arrows | Move (mouse looks) |
| Shift | Sprint — fast but loud |
| Ctrl / C | Crouch (toggle) — quiet |
| F | Flash pulse (see in the dark) |
| E | Use: grab, read, station, exit |
| Q | Eat bread |
| R | Supply pack |
| G | Drop glowstick (3 per run) |
| J | Field journal |
| V | Camera: 1st / 3rd / front |
| Esc / P | Pause |

## Dev

```sh
# full regression (16 suites, must stay green)
HOME=/tmp/brhome python3 backrooms/tools/regression.py

# co-op smoke test (host + client, seed 424242)
HOME=/tmp/brhome MP_TEST_TIMEOUT=150 zsh backrooms/tools/mp_test.sh 424242

# recapture review screenshots (needs a display, NOT --headless)
HOME=/tmp/brhome godot --path backrooms --script res://tools/render_review.gd

# rebuild the macOS app zip
HOME=/tmp/brhome godot --headless --path backrooms --export-release "macOS"
```

Layout: `backrooms/` = Godot project (scripts, scenes, tools/tests),
`build/` = review site + screenshots + exported zips.
