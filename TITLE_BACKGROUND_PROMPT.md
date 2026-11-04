# Title screen background: brief for Codex

Generate one image and save it as `realm/assets/ui/title-background.png` (PNG, 3840×2160, 16:9). No text, no logo, no watermark, no UI.

## Prompt

A cinematic, painterly-realistic vista of a medieval realm at golden hour, in the style of a prestige fantasy film's establishing shot (grounded like Game of Thrones or Kingdom Come: Deliverance, not cartoonish or high-fantasy). A walled royal city on a great river delta, Kingsmere, seen from a low hillside across the water: a stone castle with tall square towers and crimson banners on a rise above slate and thatch roofs, smoke from chimneys, boats on the river. Rolling green farmland and dark pine forest in the middle distance, snow-capped mountains far behind under a vast sky of warm amber and slate-blue cloud, low sun breaking through from the left with soft god-rays and atmospheric haze. A lone raven in flight near the upper right. Rich, natural colour: deep greens, warm stone, gold light, cool blue shadows. Highly detailed, sharp foreground (wet grass and rocks at the bottom edge), soft depth falloff toward the horizon.

## Composition (matters: the menu sits on top)

- The centre third of the frame must be calm and open (sky, river, distant land), with no busy detail, because the logo and menu sit there and will be darkened.
- The interest sits at the left and right thirds: the city and castle on the right, the forest and sun on the left.
- Horizon a little below the middle. Nothing important in the outer 5% (it may be cropped on other screen shapes).
- Lighter and warmer overall than a night scene: the game's direction is "not grim, not black".

## Avoid

People's faces close up, dragons, modern objects, text, signatures, frames or borders, oversaturated fantasy colours, plastic CG look, fisheye.

## Deliver

1. The PNG at `realm/assets/ui/title-background.png`.
2. A line in `realm/assets/ui/CREDITS.md` naming the tool and model used, and the date.
3. Also save a second variant with the city on the left (`title-background-alt.png`) so we can pick.
