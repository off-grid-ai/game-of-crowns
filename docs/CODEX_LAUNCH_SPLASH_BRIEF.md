# Launch screens: two paintings for Codex

When Game of Crowns starts, two full-screen paintings play before the main menu, about 3 seconds each, with slow movement and fades. Any key skips them. The game sets its own words over each one, so the paintings carry **no text, letters, logos or watermarks**.

Deliver both as PNG, 3840×2160 (16:9), to:

- `realm/assets/intro/splash/splash_1.png`
- `realm/assets/intro/splash/splash_2.png`

House style for both: the warm, painterly realism of Manor Lords and classic oil painting, not cartoon or anime. A low, cinematic eye level, never top-down. Rich but restrained colour: deep shadow, warm candle and dawn light, one strong focal point. Leave the lower third darker and quieter: the game writes over it.

---

## 1. The war table (under "Off Grid AI presents")

```
A cinematic oil painting, 16:9, no text or letters anywhere. Night, inside a stone keep. A heavy oak war table fills the frame, seen low from its near edge. On it lies a hand-drawn parchment map of a long continent (snowy north, green heartland, red southern desert, a ring of mountains, islands to the west), weighted at the corners with daggers and a candlestick. Seven carved wooden house tokens stand on the map (a wolf, a lion, a rose, a stag, a sun, an eagle, a kraken), and in the centre a plain iron crown rests on its side. Candle flames are the only light: warm amber pools, long shadows, wax drips, smoke curling up. Far behind, out of focus, a tall arched window shows a cold blue night and falling snow. Shallow depth of field on the crown. Painterly brushwork, Manor Lords realism, muted earth tones with gold highlights. The bottom third falls into soft darkness.
```

## 2. The empty throne (under the Game of Crowns title)

```
A cinematic oil painting, 16:9, no text or letters anywhere. Dawn in a vast medieval great hall. An empty stone throne stands at the far end on three worn steps, a sword laid across its seat. Shafts of early sunlight fall through high narrow windows onto the throne, gold in the dusty air. Down both sides of the hall hang seven long house banners, each a different colour and beast (grey wolf, gold lion, green rose, red stag, orange sun, blue eagle, dark kraken), still in the windless air. The stone floor runs from the viewer toward the throne, low and centred, so the eye travels down the hall. Cold blue shadow in the corners, warm gold on the throne. Painterly brushwork, Manor Lords realism, grand and quiet, a sense that someone must take the seat. The bottom third falls into soft shadow.
```

---

Once both files are in place, tell the game session; `realm/tools/intro_art.sh` brings them into the game as ~1 MB JPGs. The screens are already wired to use them and skip themselves until they exist.
