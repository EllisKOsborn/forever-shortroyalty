# In-game test checklist

Short on purpose: only what still needs checking in the game. Send the
`/sr debug` text (Settings → Advanced → Debug report) whenever something
looks wrong. The full checklist used from v0.1 to v0.6.0 (196 items) is in
git history (`git show v0.6.0:TESTING.md`).

## Already confirmed in game

- **Loading and sync** (5–10 Nov): interface 16001, the addon loads, player
  IDs stay the same between logins, guildmates' data arrives (numbered
  pieces, v0.3.3), no false send errors (v0.4.2).
- **Professions** (6–12 Nov): unlearned recipes are listed, reagents are
  read, gathering professions' recipes, skill-up colours (245 match, 0
  differ), TSM prices.
- **Owner, 11 Nov:** "All works fine" on v0.4.5 (the menu hover bug was
  fixed in v0.4.6).
- **Owner, 13 Nov:** the v0.6.0 redesign "looks fine"; the character model
  "looks fine"; alts "look fine" (they link themselves). The guild is
  **Alliance only**, so the Horde Onyxia chain doesn't matter.

## Still worth a look

1. [ ] **Onyxia's Lair:** a character with the attunement quest done shows
   *done*; take the Drakefire Amulet out of your bags and the Roster's
   Onyxia view shows the orange **!**.
2. [ ] **Cooldowns** (Professions → Cooldowns): only real cooldowns
   (Mooncloth, transmutes…), even right after crafting something.
3. [ ] **Where to learn:** open a profession trainer, then hold Shift over a
   recipe you don't know: it names the trainer's skill and cost.
4. [ ] **Who wears it:** point at an item a guildmate wears: "Guild: worn by
   …". `/sr who` then Shift-click an item lists who wears it.
5. [ ] **Reminder bar Open button:** with a profession window never opened,
   the orange bar's **Open** button opens it (not in combat).

## v0.7.0 Short Words

6. [ ] The sidebar has **Games → Short Words**. Its icon shows (not a
   green square).
7. [ ] **Daily:** click the board, type a word, press Enter. Tiles turn
   green (right letter, right place), yellow (in the word, wrong place) or
   red (not in the word). A made-up word says "Not in the word list" and doesn't use a turn.
   The on-screen keys work too, and Esc stops typing so you can move again.
8. [ ] After the daily word, the board stays solved for the rest of the day,
   also on your alts ("Played on …"), and the next word comes at midnight
   UTC (midnight in the UK in winter, 1 am in central Europe).
9. [ ] **Share** types "Short Words #… 4/6" into guild chat; you press Enter.
10. [ ] **Free for all:** solve or fail, then **Next word**; it keeps going.
    The word is never today's daily word.
11. [ ] **Leaderboards:** Today and All time for each mode. A guildmate who
    played shows up within a minute or two (daily) or a few minutes (free
    for all). Point at a name in Daily → Today to see their colours, never
    their letters.
12. [ ] Settings → Sharing → *Share my Short Words results* off: you
    disappear from guildmates' leaderboards after their next update.
13. [ ] **Guild streak** (v0.7.1, top right of Daily): says "N of 3 played
    today" until three of you have played, then the streak goes up by one.
    Share in guild chat adds "· guild streak N".
14. [ ] **Colour-blind colours** (v0.7.1, under the keyboard): click it and
    the board, keys and leaderboard colours turn orange / blue / grey;
    click again for green / yellow / red. It's still on after a `/reload`.

## v0.7.2 Short Words on flights

15. [ ] Take a **flight path**: within a second a small box appears near the
    top of the screen, "Flying? Play Short Words". It says *Today's word is
    waiting* if you haven't played today, otherwise *Play free for all
    until you land*.
16. [ ] **Play** opens Short Words. When you land, the box is gone and the
    window closes (only if the box opened it). **✕** or Esc hides the box.
17. [ ] Getting stunned or feared (not on a flight) never shows the box,
    and Settings → Display → *Short Words on flights* off stops it.
