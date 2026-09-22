# Acceptance — integrated 3D upgrade

## Graphics preset correction

A new test reproduced four failures: selecting Low changed environment effects but left the active viewport scale at 1.0, both immediately and the following frame. `apply_graphics_preset` now sets the active viewport directly: Low uses 0.67 with FSR2 when Forward+ effects are supported and bilinear otherwise; High restores 1.0/bilinear. The registered focused test passed headless and on real Metal/Forward+ with completed-frame readback; restart and volume suites also passed (`/var/folders/hl/b96jj8gs3hb9rcqtq5bmk4l80000gn/T/backrooms-regression-3k43ksmz/summary.json`). A stationary full-scene capture pair additionally rendered successfully in both presets; High reported scale 1.0/mode 0 and Low 0.67/mode 2 (`/var/folders/hl/b96jj8gs3hb9rcqtq5bmk4l80000gn/T/backrooms-preset-comparison-nv6uz76s/`). Those images differ, but the difference includes glow/SDFGI/volumetric changes and does not isolate scaling or certify visual quality.

The fresh-context audit found no correctness defect in this change and identified three coverage gaps: the headless runner cannot exercise FSR2 or image readback, High's environment restoration is unasserted, and pixel comparisons do not isolate scaling's independent contribution. Performance (frame-time) benefit remains unmeasured. Survival completion, visual/listening/performance acceptance and an updated export remain open.

## Third-person interaction correction

A focused test reproduced four nearby-target prompt/use failures in chase/front views. Player now shares `interaction_hit()` with campaign and pickup/door prompts: camera ray length includes its offset from the player, excludes the player collider, enforces 3.2m head-to-hit reach and rejects obstructions along the actor-to-target segment. All three views pass nearby, range and wall tests. Fresh audit prompted additional discriminating camera-visible/out-of-actor-range and actor-only-obstruction fixtures; these pass after isolating test cameras from spring-arm repositioning. The registered test was subsequently expanded with a second production player retaining attached, active spring arms and real `cycle_view()` transitions. Nearby prompts/use and wall rejection pass in all three live-boom modes (24 total assertions including fixed-camera cases): `/var/folders/hl/b96jj8gs3hb9rcqtq5bmk4l80000gn/T/backrooms-regression-s43ajpzj/summary.json`. This remains headless behavioral coverage, not real pickup UI or visual acceptance.

Full regression passed 14/14 before the extra test fixtures: `/var/folders/hl/b96jj8gs3hb9rcqtq5bmk4l80000gn/T/backrooms-regression-0q11dy95/summary.json`. The strengthened view test subsequently passed directly with 15 assertions. The required unchanged survival run still ended DEAD at 105.1667s, stage 3, no exit entries: `/var/folders/hl/b96jj8gs3hb9rcqtq5bmk4l80000gn/T/backrooms-interaction-survival-1os9o__s/report.json`. No survival completion or release acceptance is claimed. No updated export yet.

## Latest navigation and independent audit cycle

Campaign route hints now use pillar-aware occupancy. At blocked or out-of-map player cells the HUD explicitly reports route unavailable rather than falsely reporting arrival. The new registered `route_hint` test checks five seeds, pillar exclusion, distance agreement with A-star, descending clear steps, actual HUD text at four offsets around each pillar, out-of-map fallback and recovery in a clear corridor. These are scripted position checks, not a physical sweep or a guarantee of every prop approach. Route, campaign and interaction integration suites passed (3/3): `/var/folders/hl/b96jj8gs3hb9rcqtq5bmk4l80000gn/T/backrooms-regression-iro4bi5b/summary.json`.

The unchanged production-threat seed-1234 controller still died at 105.1667s after three stations, with no exit entries, no successful hiding, and a visible target 1.197m from the entity. Exit code 1; no timeout or script errors. Shutdown resource warnings remain. Evidence: `/var/folders/hl/b96jj8gs3hb9rcqtq5bmk4l80000gn/T/backrooms-survival-terminal-5ktqt94v/report.json`. The crouch fix corrected foot height but did not solve survival. The exit diversion is controller code, not campaign route-hint code.

Fresh-context reviewers identified remaining priorities: reproduce third-person interaction range/self-collision issues; verify live graphics-preset viewport scaling; cover all campaign stages in HUD tests; achieve a full natural threat-enabled escape; and export current validated source rather than distribute stale RC1. Visual, listening and performance acceptance remain open. No new release was exported this cycle.

Objective: finish the game with substantially improved 3D, animation, generation, graphics, sound, layout and lore. Implementation has advanced across all requested pillars; exceptional visual/listening quality is not certified.

| Requirement | Implemented and verified evidence | Remaining acceptance gap |
|---|---|---|
| Models | Detailed multipart furniture, doors, racks, keyboard and vent batches; preserved collider contracts; prop test passes | Visual inspection/performance review |
| Creature animation | Profiled anatomical meshes, articulated ribs/fingers/jaw, world-space foot planting, two-bone IK, breathing and anticipatory head motion; 18 assertions pass | Motion review in natural pursuit |
| Generation | 135 tested seeds produce 135 unique connected grids; pillar-aware A* routes and safe objective-clear enemy spawns verified; five physical full-campaign traversals pass (0, 42, 999, 1234, 424242), approximately 325m each without teleports | Threat-enabled survival balance and additional seeds |
| Graphics/textures | Seven original 1024px albedo/normal/roughness sets (21 maps), eight material slots verified loading them, anisotropic mipmapped filtering; renderer-aware effects | Five fresh engine views successfully rendered with completion marker; visual inspection remains unavailable to this model |
| Sound | 13 original WAVs plus five smoothly blended regional reverb/low-pass profiles; deterministic footstep/door variation; persisted volume API; routing/mute/cleanup tests pass | Listening and in-game mix assessment |
| Lore/gameplay | Ordered three-station campaign, journal, gated escape; campaign/interaction/restart/lifecycle tests pass | Natural complete playthrough |
| Co-op | Both real two-peer runs passed with seeds 1234 and 424242 after model/PBR/acoustic integration | WAN and human co-op playthrough |
| Packaging | build/backrooms-playable-3d.zip ZIP integrity passes; actual exported executable --verify-entity runs all 18 checks and exits 0; explicit startup dispatch fixes exported verification | Interactive packaged review/signing distribution not verified |

## Crouch collision correction — 2026-09-17

A production-player physics test reproduced a 0.325m downward shift of the player origin while crouching, and showed that two instantiated players shared the mutable capsule resource. Before correction, 13 assertions failed across three crouch/stand cycles. Player now duplicates its collision shape on initialization and keeps the capsule center at half its blended height, anchoring its bottom at the foot origin. The same test passes after correction, including floor contact, intended crouched eye height and independent second-player geometry. This does not cover standing beneath low ceilings or establish survival balance.

The registered crouch test and full regression pass **12/12 suites**, with zero script/assertion errors. Evidence: `/var/folders/hl/b96jj8gs3hb9rcqtq5bmk4l80000gn/T/backrooms-regression-v_beytkd/summary.json`; failing baseline: `/var/folders/hl/b96jj8gs3hb9rcqtq5bmk4l80000gn/T/backrooms-crouch-before-lq7hl5e5/test.log`. Shutdown warnings remain in some suites. These changes have not been exported.

## Player volume controls — 2026-09-17

Menu and pause now expose synchronized Master volume sliders with percentage/mute readouts, backed by the existing persisted AudioManager setting. `tools/volume_ui_test.gd` passed 129 assertions covering the production controls, keyboard Home/End input while paused, Master bus dB/linear gain and mute, configuration persistence across scene recreation, silent counterpart synchronization, and restoration of original configuration bytes and bus state. This is functional coverage, not a visual layout or listening review.

After registering the volume test, the full regression runner passed **11/11 suites**, with zero script/assertion errors. Evidence: `/var/folders/hl/b96jj8gs3hb9rcqtq5bmk4l80000gn/T/backrooms-regression-2mje3yuk/summary.json`. The volume suite emitted no engine warnings; previously noted shutdown warnings persist in several other suites. These UI changes are source-only; no new distribution has been exported.

## Exit diagnosis — 2026-09-17

The interrupted agent left a completed diagnostic trial and report in `backrooms/build/exit-diagnostic-20260917-200327/report.json`; these were recovered and inspected rather than repeating the live trial. It ended DEAD at 105.183s after three real station interactions. At hunt onset the player was 6.142m from the door root with 98.57% stamina. Closest approach was 6.005m; there were zero ticks within 2m of the door and no trigger overlap. The controller diverted because its interception estimate rejected exit commitment, not because its waypoint stopped outside the trigger.

Door root, maze exit position and route goal agree at (39,0,0). The trigger box is centered at (39,1.2,0), size (2.6,2.6,2.6). The ajar door is visual geometry, not a solid collider. No exit-geometry correction is supported by these measurements.

An independent current-source seed-1234 traversal with threats frozen physically walked 324.99m, activated all three stations and reached WON through the real exit at (37.4264,0.000839,0.000031), after 6100 physics ticks. No player teleport or stamina override was added. Log: `/var/folders/hl/b96jj8gs3hb9rcqtq5bmk4l80000gn/T/backrooms-exit-reachability-_c7hjjog/traversal.log`. The run had no script errors but reported ObjectDB leakage and three resources still in use at shutdown. This verifies reachability, not threat-enabled survival.

Corrections to prior commentary: attempt 2 did not start hunting with exhausted stamina (it had 98.6%); attempt 3 broke sight nine times but never lost the hunt. Neither early-aggression imbalance nor a blocked exit has been established. No complete threat-enabled WON run has been verified.

## Pursuit integration — 2026-09-17

Current-source regression: **10/10 suites passed**, zero script/assertion errors, including the newly registered pursuit suite. Its nine assertions cover line-of-sight acquisition, remembered destinations, audible updates, search timeout and reacquisition. These assertions are not a physical evasive playthrough or exhaustive close-range catch coverage. Lifecycle, entity animation, interaction and campaign regression suites also pass. Some shutdowns report ObjectDB/resource warnings; these remain unresolved.

Both real two-process co-op checks passed again on seeds 1234 and 424242 after the pursuit change. Those scripted co-op checks freeze threats and therefore verify networking/campaign contracts rather than natural pursuit balance.

Live-threat direct-walking trials failed to complete on all five seeds (0, 42, 999, 1234, 424242). Seeds 999 and 1234 reached station zero before dying during the next leg; the other three died on the first leg. The bot generates walking noise but does not sprint, crouch, hide or evade. This is neither survival acceptance nor proof that the game is unwinnable. No speed tuning was made to force this proxy to pass.

Latest regression evidence: `/var/folders/hl/b96jj8gs3hb9rcqtq5bmk4l80000gn/T/backrooms-regression-ftlwk_iq/summary.json`.
Latest co-op logs: `/var/folders/hl/b96jj8gs3hb9rcqtq5bmk4l80000gn/T/backrooms-pursuit-mp-sr41moqr/`.
Live-threat output: `/Users/anon5376/.zcode/cli/exec/sess_cc55f96d-ce09-4a63-9254-7be6770fd63b/cc84d44c-e3cc-4e2b-813b-025e6ea2e5a7-stdout.log`.

Frozen distribution remains `build/SignalLost-0.9.0-rc1-macos.zip`. The new pursuit behavior is source-only RC2 development; no RC2 archive has been exported. Visual, listening, performance and natural-play acceptance remain open.

Evidence: `/var/folders/hl/b96jj8gs3hb9rcqtq5bmk4l80000gn/T/backrooms-regression-f58u16z2/summary.json`, `/tmp/backrooms-upgrade-mp.log`, `/tmp/backrooms-upgrade-mp2.log`, `/tmp/backrooms-3d-export.log`, `/tmp/backrooms-packaged-boot.log`.

```sh
python3 backrooms/tools/regression.py
zsh backrooms/tools/mp_test.sh 1234
zsh backrooms/tools/mp_test.sh 424242
python3 backrooms/tools/bake_materials.py
python3 backrooms/tools/bake_audio.py
```

This report distinguishes implementation/test evidence from visual, listening and natural-play acceptance. Do not interpret green tests as proof that the entire quality goal is complete.

## Survival controller rework and RC2 export — 2026-09-17

The seed-1234 threat-enabled campaign gate now produces a complete verified WON. The oracle controller in `tools/survival_campaign_test.gd` was reworked on the controller side only — the enemy, player speeds, noise radii, stamina and all gameplay balance are untouched (runtime asserts confirm no actor writes; native threat teleports retained and reported separately). Controller changes:

- Concealment requires the hunter to hold no line of sight (in-place cover gate also checks occlusion from the hunter's remembered destination); crouch-walking to a side branch is aborted the moment sight or sprint-reach proximity returns.
- An established hide aborts only if actually spotted (visible or within 2m), holds crouched while the exit arbitration margin is negative, and stands up into the exit run only when the swept-capsule arbitration commits.
- At the exit stage, evasion candidates that shorten the hunter's BFS route to the exit are rejected; the lure drags the hunt memory away from the door before re-committing.

Result: three deterministic WON runs (attempts 1–3), 99.32s each, three real station interaction rays, production exit `body_entered`, minimum threat separation 6.09m, zero catch contacts, exit arbitration margin +4.65s at commit. Isolated `survival-` HOMEs were used for every run; production saves untouched. Evidence: `/var/folders/hl/b96jj8gs3hb9rcqtq5bmk4l80000gn/T/backrooms-survival-hideguard-3tg8jfni/`, `backrooms-survival-confirm2-h4vrpc8_`, `backrooms-survival-confirm3-fe0n8gsr` in the same tmp root.

Full regression after the rework: **15/15 suites passed**, zero script/assertion errors (`/var/folders/hl/b96jj8gs3hb9rcqtq5bmk4l80000gn/T/backrooms-regression-5opbw5g2`).

RC2 exported: `build/SignalLost-0.9.0-rc2-macos.zip` (sha256 `b47c2844…88d1ff2`, manifest `SignalLost-0.9.0-rc2-manifest.json` with 286 source-file hashes). The exported app boots headless with exit 0 and no renderer or script errors (`build/rc2-boot.log`); its pck hash differs from RC1's, confirming new content. RC1 remains byte-identical to its frozen manifest (sha256 re-verified). Caveats: scripts-in-pck are compiled, so text markers cannot be grepped from the archive; the boot check verifies the binary loads and runs, not visual quality. Shutdown ObjectDB/resource warnings reproduce in the exported binary as in RC1 and remain unresolved.

Still open: visual/listening/natural-play acceptance, frame-time measurement, shutdown resource warnings.
