# Political influence on the map (one page, Builder 2, 2026-11-11)

**Mac:** political influence should read much better on the map, to CK3's political map-mode standard, in the Warcraft III look.

**References:**
- **CK3's political map mode:** a flat, crisp realm colour with thick borders between realms and thin ones within; occupied land striped in the occupier's colour.
- **Warcraft III:** bold team colours on banners, buildings and units, saturated and readable from the RTS camera.
- **Total War's campaign map:** a faction's border glow, and a region's colour bleeding to its new owner.

## What we have (land3d.gd `REALM_WASH`, terrain.gd `set_realm`)
- Each house's land is washed in its colour at the land's brightness, stronger in a band inside its border.
- A thin dark seam marks where two houses meet:
  - red at war;
  - dashed gold under a truce;
  - gold if the house is sworn to the crown;
  - silver dashes along an envoy's road.
- When land changes hands, the new colour floods out from the changed patch.
- Each town carries its house's banner on its keep.

## What changes
1. **Crisp borders in the house's colour (CK3, WC3).**
   - The seam becomes a two-tone line: the house's own saturated colour on its side, the neighbour's on theirs, with a thin dark core.
   - About 3 px wide from the town view, 5 px from the realm view; the shader already holds the width constant in pixels.
   - War, truce and the sworn mark stay as they are, on the core.
2. **The tint's strength shows the hold (new).**
   - Per house, a `hold` value from 0 to 1 sent in `/world`, from the bridge's favour bands. The bridge owns it; the view only draws it:
     - **Loyal:** 1, a strong, full colour, the heartland.
     - **Content:** 0.7.
     - **Cold:** 0.45, the colour fading toward the bare land.
     - **Angry, or an ultimatum sent:** 0.3, plus diagonal stripes in the colour of the house it leans to (its scheme partner, or else its strongest neighbour). That is CK3's occupation stripe, read here as "slipping".
   - The heartland stays strong near the seat and fades toward the edges by distance, so even a loyal house reads as a centre.
   - In the shader: `uniform float hold[64]`, indexed by the owner id already in `realm_tex.a`, plus `lean[64]` for the stripe colour. There's no new texture, and nothing repaints when a mood shifts; only two uniforms change.
3. **Banners in the holder's colours (WC3).**
   - The keep's banner is already there; it goes saturated, at the WC3 look's colour (no lerp to white).
   - Roadside posts: where a road crosses into a house's land, a post with a small flag in the holder's colour, placed once from the road network and the owner grid (data: one post per crossing, none within 3 tiles of a town). It changes colour when the land does.
   - The posts are a component from the asset catalogue (`realm/data/assets.json`), never a hard-coded model.
4. **A change of hands spreads.**
   - The flood already does this. It gets a visible front: a bright line in the new colour at the flood's edge, about a second, and a sound.
   - Then the posts on the changed land swap colour as the front passes.
5. **Readable at every zoom.**
   - **Town view:** border line plus posts; the wash stays faint over the streets (as today).
   - **Middle:** wash at its `hold` strength plus the lines.
   - **Realm view:** a flatter, map-like colour (CK3's paper map), lines thick, stripes wide.
   - The existing distance blend (`far_off`) carries it; its numbers go to `realm/data/look.json`.

## Order and owners
All mine (Builder 2: terrain, look, map). The bridge's `hold` and `lean` are a small addition to `/world` in `view.js`.
1. Borders and hold. The biggest read for the least work.
2. Banners and posts.
3. The flood's front.

**Done when:** three stills, at town, middle and realm zoom, judged beside CK3's political map and a WC3 base: who holds what, who is slipping, and where the borders run, all readable without a legend.
