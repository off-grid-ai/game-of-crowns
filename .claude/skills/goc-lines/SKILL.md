---
name: goc-lines
description: How to write the short lines players remember in Game of Crowns (house words, battle cries, the realm's calls, a lord's motto, a chapter title). Use whenever Mac asks for words, a motto, a call, a cry or "something memorable", and before showing him any such line.
---

# Lines that stick

Mac's bar is the house words of A Song of Ice and Fire: "Ours Is the Fury", "Unbowed, Unbent, Unbroken",
"We Do Not Sow". Write like Martin, Tolkien and C. S. Lewis together: plain words, real weight, a threat or a
promise underneath. Never copy their lines or lean on their exact shapes; take the qualities, not the words.

## What makes a line great

1. **It comes from the house's story, not its virtues.** Know where the house came from and what it went through
   before writing. No story yet: ask Mac for one, or draft a short one first. (The Crown: came from nothing,
   worked, climbed, deposed the old king by grit and sheer will.)
2. **It is a claim about now, from strength.** What the house is, not where it was. No looking back at weakness.
3. **It has music.** Say it aloud. Heavy beats, often three; repetition or alliteration; the strongest word last.
   It must work shouted by a host before a charge.
4. **Concrete or elemental words.** Fury, fire, blood, winter, a roar. Not abstract virtues (patience, labour).
5. **It never explains itself.** The meaning lives underneath. If it needs a note, it has failed.
6. **It is a real, complete sentence or phrase in plain English.** No dangling verb, no inversion that sounds
   unfinished, no word a child or a scholar would stumble on.
7. **Clear on the first hearing.** Mysterious means something left unsaid, never a riddle. No dares or orders
   aimed at the listener that need decoding ("Bury Us Deeper", "You Will Tire First" read as weird).
8. **Simple words, grown-up weight.** Not cute ("We Work. We Wait. We Win." read as a two-year-old's), not a
   slogan, not a pun, not a maxim with a twist.

## Banned

Stock fantasy words: hammer, forge, anvil, stone, dawn, iron, steel, kneel, rise, endure, prevail, toil.
Past tense. Explanations. "My pick" with a paragraph. Lines that echo a famous one's exact shape.

## The process (it worked once; skipping it failed every time)

1. Hold every criterion Mac has given in this conversation at once. Never fix only his last note.
2. Write fifty candidates privately, in thinking. Range wide: claims, threats, promises, images.
3. Say each aloud in your head. Cut every line that fails any rule above, needs a note, uses a banned word,
   talks about the past, or is not a complete phrase.
4. Of the survivors, keep the three strongest and most different from each other.
5. Show Mac the three in bold, one per line, with no commentary. One short line before them at most.
6. When he reacts, add his note to the criteria and run the whole process again from step 1: never patch the
   last three.

## After he picks

Recording and wiring is the voice session's job (`realm/tools/record_house_words.sh`, `record_calls.sh`); the
words live in `bridge/narrator.js` and `realm/data/sounds.json`. Restart the bridge so the game says them.
