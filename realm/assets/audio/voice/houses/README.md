# The houses' words

Each great house's words (and the Crown's), spoken when the King opens one of its towns, in the voice of whoever
rules the house now (`realm/data/sounds.json` `house_words`; the voice is chosen by `sound_v2.gd` `voice_profile`
from the lord's age and sex, the King's at Kingsmere). Every house is recorded in every profile, so a new lord
needs no new recording: `<house>/<profile>.ogg`.

Made with Off Grid AI Desktop (OGAD): its local Kokoro text-to-speech (`/v1/audio/speech`), then pitch, pace and
a hall echo by ffmpeg, encoded with oggenc. Remake them with `zsh realm/tools/record_house_words.sh` (OGAD running).

Licence: our own art, made for Game of Crowns; Kokoro's voices are Apache-2.0.

| Profile | Kokoro voice | Shaping |
|---|---|---|
| old_man | bm_daniel | lowest, slowest |
| man | am_adam | low |
| young_man | am_michael | as spoken |
| old_woman | bf_emma | low, slow |
| woman | af_sarah | a little low |
| young_woman | af_heart | a little high |
