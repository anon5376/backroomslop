# Next-cycle backlog (fresh-context audit, 2026-09-17, post-RC2)

Ranked by player impact. Source-only audit; rendered confirmation still required for visual items.

1. **Reading a transcript must not be a death sentence** (scripts/campaign.gd): auto-keep recovered transcripts, open reader only via J; add safe-reading design in solo, explicit warning in co-op. Verify: coached-free playthroughs on several seeds.
2. **Deliver the return-channel story through sound** (scripts/campaign_interactable.gd): six-second signal motif per station, recorder/transport/isolator audio, fluorescent→rain transition at release, captions, payoff line about Mara/Ivo's record. Verify: perceived three distinct changes; captions; co-op shared progress.
3. **Fix dressing placement before adding props** (scripts/maze_generator.gd): grime quads sit 0.03m inside the wall (lines ~919–924, `CELL/2.0 - proud`); all four dark-pocket chairs map to solid cells far from the dark region (lines ~866–870). Add overlap/approach assertions + rendered walkthrough check.
4. **Visual style & lighting transitions** (scripts/main.gd, scripts/light_manager.gd): fade reassigned light-pool members instead of popping; regional contrast/fog review; replace single-box scare silhouette; improve box-built explorer avatar. Verify: moving footage, all five regions, High+Low.
5. **Environmental audio mix** (scripts/audio_manager.gd): surface-specific footsteps, sparse regional emitters, fix unused hum voices stacking at one location (scripts/light_manager.gd ~145–154), separate ambience/SFX volumes, reduced-dynamic-range option, distinct consumption feedback.
6. **Accessibility before gameplay** (scripts/ui_manager.gd): reduced flashing affecting fixtures+scare events, headbob toggle, FOV, invert-Y, rebinding, UI scale; visual equivalents for critical sound cues.
7. **Menu/HUD/end-screen flow** (scripts/ui_manager.gd): separate Play/Settings/Co-op, quit action, settings persistence, HUD declutter, prompt placement, failed-consumption feedback.
8. **Packaged human-quality gate** (next RC): rendered playthrough + listening pass + frame-time percentiles on the exported build; profile startup texture work (scripts/texture_factory.gd); resolve shutdown ObjectDB/resource warnings.

Defects also noticed: third-person camera inconsistency in entity staring/scare placement (entity.gd ~252–313, scare_director.gd ~89–109); `_random_reachable_in_ring()` skips pillar/approach protections used at initial spawn (entity.gd); pickup audio differs solo vs network path (pickup.gd ~33–50, main.gd); stale README claims (seeds/layout, 24 vs 16 lights, Q-to-eat).
