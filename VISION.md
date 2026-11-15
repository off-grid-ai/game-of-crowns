# Game of Crowns: vision

What is decided and what is in scope. New ideas are added here; they replace a decision only when we
say so. How it plays is [GAME_DESIGN.md](GAME_DESIGN.md).

## The game in one line
A war king's reign over a living medieval realm: command your army, hold seven great houses by sword or
by oath, and find out what kind of king you'd be.

## Decided
- **A war king from minute one (2026-11-15).** The King starts with a royal army at Kingsmere and
  commands it live: click to select, right-click to march, attack, besiege or relieve. One objective is
  always on screen, something to act on comes at least every 45 seconds, and every first choice is
  affordable. The court is a side layer that never stops time.
- **Win on play, not pixels.** One kind of game done really well. Graphics only need to be clear,
  consistent and readable from roof height up; the camera stops at roof height and faces are painted
  portraits on cards.
- **The player is the King,** not a god. No god powers or sandbox fate buttons.
- **The Crown has its own people.** The King and his household (commanders, champion, council) are
  people with stories, and the player can edit the King's story and theirs.
- **People are met in play, not in a menu (2026-11-15).** No Lore encyclopedia on the main menu. A
  person's card opens when you click them in the world: your army's commander, a lord bringing a demand,
  a rival marching on you (Total War's general, Warcraft III's hero portrait, Crusader Kings 3's sheet).
  The Crown's people are reached the same way, from your army and your court.
- **Setting:** around 900 AD, Game of Thrones in era and feel: great houses, castles, shields, mail, axes
  and bows, gritty war. Mythical touches (the dead beyond the wall, wildlings). No dragons. Not Westeros,
  no GoT names. One age: tech grows within it (wooden forts become stone castles), never past it.
- **A world that runs itself.** Houses farm, march, scheme and fight on their own; the King steers it.
- **Timed reigns only:** 15, 30 or 60 minutes; no endless mode. "Rule on" after the end grants 15 more.
- **System integrators.** Every layer comes from an existing project; our code is glue. Before building
  anything, ask who already built it.
- **Personal use only, so licences don't matter.** Pick on quality and fit.
- **No model in the app.** The game ships and downloads no model. Lords speak in their own words when
  Off Grid AI is running; Settings says so.
- **One player, from above.** Walking as a character is built and switched off; it may return with
  multiplayer.

## In the game
- The realm: towns, seasons, crops, coast and rivers; the houses on a map in their colours.
- The royal army and the houses' armies: marching, battles on open ground, sieges that breach walls.
- **The houses and their people:** lords, bannermen and heirs with names, wants and memory of what you
  did. You meet them in play, when they matter.
- **Royal goals:** a ladder of objectives, always one on screen, each with a reward you can see.
- **The Crown's own lands:** built from the town card, sited by the game, producing crowns, grain and men.
- **The King's levers:** alliances and oaths that bind a house to your wars, marching on a house,
  granting and stripping castles, hostages, spies, executing traitors, gifts of grain and crowns. Gifts
  lose force when repeated, rivals resent favourites, long wars cost the Crown.
- **Reign stories.** Each reign has a main threat told in acts; survive it and you win. Stories are data
  made of beats, chosen on the New Chronicle screen by tags (threat, feel, length, hardness), or written
  by the player beat by beat. Every story is checked before it begins.
- **Scenarios:** start a new realm any time (map, houses, wealth, temperaments, starting wars).
- **Release calls:** always day for now (nights later, with lit windows and torches); speech as captions,
  not voice; any scene that fails the final look check is cut, not patched.

## Later
- **Multiplayer:** friends share a realm, likely one King and friends as lords who scheme and march on
  the throne. Open: who hosts, and a Windows build.
- **Beyond:** more continents, your own maps and characters, deeper lore, hedge magic. No dragons.
