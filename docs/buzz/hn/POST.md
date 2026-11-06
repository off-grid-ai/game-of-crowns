# Show HN: Game of Crowns (draft, not posted)

Built from the study of 79 Show HN game launches (launches.md, records_F*.md). Each choice
below names the evidence it rests on.

## Title

Show HN: I built a kingdom sim where the lords think for themselves, on your Mac

- The player's experience plus a human hook ("I built"), no stack, no "AI-powered":
  "Interview AI suspects with your voice" 215 vs "An AI-powered political simulation game" 2.
- "on your Mac" answers the top AI objection (cloud, cost) in the title itself.

## First comment (Mac posts it the moment the link goes up)

Hi HN, I'm [your name]. I make Off Grid AI, an app that runs AI models on your own phone or Mac, with no cloud and no account. I kept wondering what a strategy game would feel like if the people in it could actually think, without anyone paying per turn or sending your game to a server. So I built one.

You're the king of a medieval realm, and seven great houses want your throne. Freeciv runs the world underneath: harvests, armies, sieges, the economy. On top of that, every lord, heir and bannerman has a mind: memories, moods, wants and grudges. The on-device model gives them their reasons and their words. You hold the crown with grain, gold, marriages and your rulings at court. A lord whose enemy you sided with in a war ten years ago will stand up in front of the whole court and remind you of the season and the year, and a house you've let go cold will refuse your order to make peace. When your reign ends, history names you for how you ruled: the Golden, the Bloody, the Deposed.

The model never decides what's true in the realm. Freeciv and the game's rules hold the state, and the lords can only act through the same levers you have, so they can scheme and refuse but they can't rewrite the world. With Off Grid AI off, the game still plays fully on its rules; the lords just speak in set lines.

I built it with Claude writing most of the code while I made the calls on design and checked every build, and the whole history is in the repo. It's free, open source (MIT, Freeciv is GPL and credited), Apple Silicon only for now because the model runs on the device. Windows is next. No sign-in, nothing locked.

It's rough in places and I'll be here all day fixing what you find. I'd love to know what history ends up calling you.

## Links in the post
- URL field: the GitHub repo (download at the top, trailer one click away).
- A 45 to 60 second gameplay video in the first comment.

## Before posting (from the study)
- A sign-in, paywall or autoplaying music anywhere sinks the thread. None today; keep it so.
- Credit Freeciv and show the licence (done in the README).
- Post when Mac can stay 8+ hours: reply in his own words, fix live, post a short changelog comment. Never argue.
- Timing showed no signal; Tuesday to Thursday, 12:00 to 20:00 UTC is where both hits and flops cluster.

## The five questions to have answers ready for
1. Cloud, cost, my data: runs on your Mac, no account, no key, costs nobody anything per turn, plays on rules with the model off.
2. Is it a game or a chat toy: the reign loop (grain, gold, marriages, rulings, seven houses, the name history gives you); Freeciv holds the state.
3. Slop, NPCs that just obey: they act from their own memories and wants and refuse cold orders; they can't change the realm's state. Show one real court exchange.
4. Vibecoded jank: disclosed up front; what Mac decided himself; known bugs owned and fixed in the thread.
5. Apple Silicon only, an Off Grid ad: why (on-device model), Windows next, and the Off Grid disclosure is in the first line.
