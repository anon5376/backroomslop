# Backrooms: Signal Lost

First-person Backrooms survival horror for **Godot 4.6**. Explore an authored
five-wing facility with seeded lighting and supplies. Recover a reference tape
in the west wing, isolate the service circuit, then transmit a release pulse
from the server hall to unlock the exit. Read the original recovered records
with **J**. The Stalker hears movement; sprint only when you must.

This is a gameplay candidate, not a visually/audio-certified final release.
See `ACCEPTANCE.md` for verified coverage and outstanding quality gates.

100% original work. Not affiliated with Kane Pixels / Kane Parsons, A24, or the
Backrooms Wiki. No assets, designs, audio, or story beats were taken from any
film — everything is procedural or CC0 (see Licenses).

## Run

1. Open Godot 4.x → Import → select `backrooms/project.godot` → Open.
2. Press **F5** (or ▶). Main scene is `scenes/main.tscn`.
3. Optional: `python3 tools/fetch_assets.py` first for nicer CC0 textures.
   The game runs fine without them — every texture and sound has a procedural
   fallback generated at startup.

Headless smoke test (no window):

```sh
godot --headless --path backrooms --quit-after 600 -- --autoplay --seed 1234
```

`--autoplay` skips the menu and drops you in with a fixed seed. If the command
exits 0 with no errors, generation + spawn + all managers work.

## Controls

| Input | Action |
|---|---|
| WASD / arrows | Move |
| Mouse | Look |
| Shift | Sprint (loud — it hears you) |
| Ctrl / C | Crouch (quiet) |
| F | Flashlight (toggle, ~8 min battery, recharges when off) |
| E | Interact (doors, almond water, bread) |
| V | Cycle view: 1st / chase / front |
| Esc / P | Pause |
| R | Supply pack (mid-run) / Restart (solo end screens) |
| Q | Eat bread |
| J | Open/close field journal |

## Regression checks

From the workspace root:

```sh
python3 backrooms/tools/regression.py
zsh backrooms/tools/mp_test.sh 1234
zsh backrooms/tools/mp_test.sh 424242
```

The Python runner rejects GDScript errors even if Godot exits zero. Tests cover
layout, lifecycle, scene reloads, actual E/J/pause input across two restarts,
and ordered campaign activation. Co-op tests use two real ENet peers and
complete the campaign through client requests before escaping. These tests
teleport actors and freeze enemy AI; they do not replace a natural playthrough,
rendered visual inspection, sound listening, or performance profiling.

Noise radii: sprint 18m, walk 7m, crouch 3m.

## Co-op (2 players, direct IP)

One player hosts, the other joins by address. Works on **LAN out of the box**;
online play goes through a free tunnel (below). From the menu:

1. **Host** — click `Host`. Your IP shows in the status line
   (port 7777). Pick a seed if you like, then press
   `ENTER THE BACKROOMS` once your partner connects. Hosting with nobody
   connected falls back to a plain solo run.
2. **Join** — type the host's IP, click `Join`, and wait. The host starts the
   run; both machines build the identical world from the host's seed.

Rules of the co-op run:

- The **entity runs on the host**; it hears **both** players' footsteps, and it
  chases whoever is nearest. Clients see a synced puppet with local
  animation/eyes/sounds.
- Pickups, exits and deaths are **host-validated**. Grabbing is host-approved
  (no double-grabs); the win fires when **every living player** has reached the
  exit. Downed players **spectate** while the run continues.
- Meters, stamina and inventory are per-player. Esc pauses only **you** — it
  never freezes the other player's world (you're standing still and vulnerable).
- Disconnects: if the host drops, the client returns to the menu; if the client
  drops, the host continues alone. No mid-run restart in co-op — quit to menu
  and re-host.

### Playing over the internet (no relay server)

The build has no matchmaking/relay; it does direct IP. For play across the
internet, tunnel UDP port 7777 with any of these free options:

- **Tailscale** (easiest): both players install Tailscale and log in. The
  joiner uses the host's Tailscale IP (`tailscale ip -4`, 100.x.y.z) as the
  "Partner IP".
- **ZeroTier**: create a free network, both join it, authorize both devices in
  the web console; use the host's ZeroTier managed IP.
- **playit.gg**: host runs the playit agent and maps a UDP tunnel to local port
  7777; the joiner uses the playit address it hands out.

Whichever you use, it must forward **UDP 7777** (ENet).

Headless co-op acceptance test (real two-process localhost session: seed sync,
both-way avatar sync, entity sync, host-validated grab, host-validated escape,
shared win, disconnect):

```sh
tools/mp_test.sh          # or: tools/mp_test.sh 424242
```

## Survival

FOOD and WATER bars drain over ~6 and ~4 minutes. Grab the bobbing
**almond water** bottles (thirst) and **dry bread** loaves (hunger) scattered
through the maze with E. Starving slows you and halves stamina regen; parched
doubles stamina drain and frays the camera. Both empty for a minute and you
collapse.

## How it works

- `scripts/maze_generator.gd` — authored connected facility on a 61×61 grid,
  3m cells, five distinct wings, seeded fixtures/supplies and BFS validation.
  Seeds do not change the floor plan.
- `scripts/campaign.gd` — ordered shared objectives, host-validated station
  activation, local field journal, route guidance and exit interlock.
- `scripts/campaign_interactable.gd` — diegetic tape, circuit and transmitter stations.
- `scripts/grid_astar.gd` — deterministic grid A* for the entity.
- `scripts/player.gd`, `scripts/entity.gd` — FPS controller, Stalker state
  machine (DORMANT → STALK → HUNT → KILL).
- `scripts/scare_director.gd` — timed row-by-row blackout scares.
- `scripts/light_manager.gd` — emissive panels everywhere, pooled real
  OmniLight3Ds in a window around the player (max 24), pooled positional hum.
- `scripts/audio_manager.gd` — CC0 file slots in `assets/` + synthesized WAV
  fallback (hum, steps, drone, screech).
- `scripts/texture_factory.gd` — procedural wallpaper/carpet/tile/grime.
- `scripts/prop_factory.gd` — primitive-built chairs, doors, signs, clutter.
- `scripts/ui_manager.gd` — menu, pause, HUD, win/death, VHS overlay.
- `shaders/` — VHS post-process, flickering light panels, entity static.

Saves (best time, last seed, settings) live in `user://backrooms.cfg`.

## Export

Install the Godot export templates matching your editor version, then
Project → Export → Windows / Linux. Output goes to `build/`.

## Licenses

- All code, shaders, scenes, and procedural assets in this repo: **CC0 1.0**
  (public domain). Do anything with them.
- Files downloaded by `tools/fetch_assets.py`: **CC0** per their sources
  (ambientCG, Poly Haven). No attribution required, but nice.
- Freesound.org sounds (optional, manual download — see the fetch script's
  search terms): check each sound's license (usually CC0 or CC-BY; if CC-BY,
  credit the author in your release).
- "Almond Water" concept inspired by the Backrooms Wiki
  (backrooms-wiki.wikidot.com, CC BY-SA 3.0). This game's bottle design and
  effect text are original; the name/idea credit goes to the wiki community.
