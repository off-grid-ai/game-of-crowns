---
name: goc-ux
description: The Game of Crowns product and look bar. Load before designing, building or reviewing any screen, panel, scene, camera, crowd or animation.
---

# Product bar

0. **Never lose functionality.** A change keeps everything the game already does, settings included. If something would be lost, say so to Mac first, with the option that keeps it.
1. **No shoddy work.** Build what a polished strategy game ships: every control, state and next step. A half-built feature is a regression.
2. **Finesse is the whole experience.** Type, spacing, labels, motion and feel get the same care as systems. Nothing clipped, overlapping, flush to an edge or unreadable.
3. **The look:** Manor Lords-rich, warm and painterly, never toy-like. Low oblique camera, never top-down. People animated with Mixamo moves that fit the place (farm work in fields, haggling in the market, prayer at the sept).
4. **The interface:** approved layout (UI.md): four quiet corners, Geist and Geist Mono, warm smoked glass (not black), one gold accent, red only for loss. Map names flat on screen, decluttered. Minimap and camera pad together bottom-right.
5. **Loops.** After any result or failure, the next action is right there; a blocked state says why in one line and what to do. Every panel and page is a place: Back (Esc) returns exactly where you were.
6. **Smart defaults.** Decide from what the realm knows; ask once, where the choice arises, with a recommendation.
7. **The world never stops on its own.** No screen freezes; things build in before your eyes. It pauses only for a decision that matters (a promise coming due, an act ending), and only until the King decides. A chronicle starts when it's ready, not on a timer.
8. **The realm's voice.** Medieval, plain, specific copy: "Outlaws come for you", not "Enemy spawned". People speak to their station.
9. **Variety and reaction, never repetition.** Use every move we have: no one clip on repeat, no man doing the same thing twice running, no crowd moving as one. Every action gets a fitting reaction (a cut is parried, dodged or taken; a hit reels by where it lands; a fall goes the way the blow drives), so the world answers what happens in it. Before shipping any scene, list the moves the asset library holds for it and use them.
10. **Show problems on the shot, not in words.** When you find what's wrong with a screen or scene, mark it on the review page (`screen-review` section 6: a numbered box per problem, at most five), send the marked-up image, then ask the one question.
11. **Every platform.** The Mac comes first; when a change can't work on Windows or Linux (Godot exports all three), name what it misses.
