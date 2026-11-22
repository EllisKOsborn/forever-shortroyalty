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

- [ ] (v0.8.2) **No "No player named … is currently playing"** in the
   chat any more when a guildmate logs off (it came from the addon). Whisper
   an offline name yourself: that message still shows. `/sr debug` line
   "Logged-off players: whispers skipped …, messages hidden …, chat filter:
   yes".
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
    top of the screen, "Flying? Play Short Words", *Today's word is
    waiting*, but only if you haven't played today's word (v0.8.0: after
    that, no box until the next day's word).
16. [ ] **Play** opens Short Words. When you land, the box is gone and the
    window closes (only if the box opened it). **✕** or Esc hides the box.
17. [ ] Getting stunned or feared (not on a flight) never shows the box,
    and Settings → Display → *Short Words on flights* off stops it.

## v0.8.0 Raids, sign-ups and attendance

Officers: first send the `/sr debug` **Raids** block. It shows your rank,
which ranks can make raids (they're matched by the words "Officer" and
"Raid Leader" in the rank name, plus the Guild Master), and what the game
says about your raid group.

18. [ ] The sidebar has **Guild → Raids** with a calendar icon. A member
    sees only the *Raids* tab; `/sr officer` prints the help for them.
19. [ ] An officer or raid leader types `/sr officer`: *New raid* and
    *Attendance* appear. Typing it again hides them.
20. [ ] **New raid:** make one for tonight. Within a minute a guildmate
    with v0.8.0 sees it under Raids and on their Overview, at the right
    time for them. Someone who logs in later gets it too (within about two
    minutes of logging in).
21. [ ] **Sign up / Tentative / Can't come** and the role menu: your answer
    shows for guildmates within a minute; the counts and line-up update.
22. [ ] Cancel the raid from its ··· menu: it disappears for everyone.
23. [ ] **Attendance** (a dungeon group converted to a raid group works for
    a first test): be in a raid group from 30 minutes before a raid's start.
    Chat says "Recording attendance for …", and *Attendance* shows checks
    going up every 2 minutes. `/sr debug` → *Raid group* shows members read,
    with GUID and matched to the guild.
24. [ ] After a boss or a fight, a check is taken once combat ends.
25. [ ] Someone who signed up and stays online outside the group gets the
    **Bench** tick after 30 minutes; clicking their row changes it.
26. [ ] Someone who joins late or leaves early shows **Late / part**;
    someone who signed up and never came shows **Didn't attend**.
27. [ ] Leave the group: the recording stops 15 minutes later (or press
    *End raid*) and chat says what was saved.
28. [ ] (v0.8.1) **Other officers see it:** after the recording ends and the
    recording officer is out of the instance, another officer or raid
    leader online sees the raid on their Attendance tab ("recorded by …")
    within a minute. One who was offline sees it about 2 minutes after
    logging in. A Bench change shows for the others too.
29. [ ] **Totals** with 30 / 60 / 90 days / All.

## v0.9.0 Reserve+ (released 16 Nov)

Try it in a dungeon group before the first raid (5 people are enough; an
officer with `/sr officer` on, and a raid made on the Raids page for
tonight). Send `/sr debug` afterwards: its "Reserve+" block says what the
addon read.

30. [ ] **Loot** is in the sidebar under Raids, with its dice icon. Members
    see Reserves, Points and History; officers also Loot night and Rules.
31. [ ] **Reserve:** pick tonight's raid, click an item, *Reserve this*.
    Within a minute guildmates see it under "Who reserved what".
32. [ ] **Rules:** set a raid to 2 reserves; members can then reserve two
    (the same item twice works). Change the bonus; the line at the top
    right follows.
33. [ ] **Lock reserves** (officer, in the group): the top line says how
    many on the bench are online and offline. Members can't change their
    reserves any more.
34. [ ] **Drops:** open a boss's loot window as the officer: rare and epic
    items appear on the left. `/sr debug` "Loot method:" says which loot
    method the group uses (**tell me whether master loot is offered in a
    raid**: it decides whether we can replace Gargul later).
35. [ ] **Post to raid chat** types the line into the chat box; press Enter.
    Players `/roll`: their rolls appear, ranked (reservers first, roll +
    points). `/sr debug` "rolls read" goes up.
36. [ ] **Award** records the win: the winner's points on that item go to 0
    (Points → Everyone, and the History).
37. [ ] **End of night:** the list shows who gets +10 and why (in the raid,
    bench online, bench offline, not there, won it). Click someone to leave
    them out, then *Save the bonus*. Points go up for everyone within a few
    minutes after leaving the instance.
38. [ ] **Change points by hand** (Points → Everyone, officer): a penalty
    (e.g. -30 with a reason) and a move to another character both show in
    the History; right-click a line there to undo it.
39. [ ] **Tooltips:** on a raid night, point at a reserved item (in AtlasLoot
    or your bags): "Reserve+: Reserved by …" with points.
40. [ ] A member who logs in later gets the points history and tonight's
    reserves within a few minutes (needs an officer online for the
    history).
41. [ ] `/sr debug` "Encounter Journal:" line: does the game turn the
    journal off, and which raids does it list? (If it lists Forever's raids,
    loot lists come from the game itself.)

## v0.9.1 (not released yet)

42. [ ] On your main (the addon creator), `/sr debug` says "can make raids:
    yes (addon creator)". Type `/sr officer`: Raids shows New raid and
    Attendance, Loot shows Loot night and Rules. You can then do items
    30–41 yourself (a raid made by you, reserves, lock, a dungeon group's
    loot window, rolls, award, end of night).
43. [ ] **Reminders:** sign up for a raid later this week without
    reserving, then log in: a calm (pink) box "Onyxia's Lair, Fri 20:00 ·
    Signed up, nothing reserved yet". On the raid's day (after midnight) an
    orange box "Raid today: …" at login, when you join the raid group, and
    every 30 minutes. **Reserve** opens the Loot page; once you've reserved,
    or an officer locks reserves, they stop. Not in combat, no sound.
44. [ ] **Remind in raid chat** (Loot night, raid check): types the names of
    raiders without a reserve into raid chat; you press Enter.
45. [ ] **Short Words after Alt-F4** (needs a guildmate with this version
    online): make 2 guesses on the daily word, quit with Alt-F4, log back
    in. The Daily page says "Checking today's guesses with the guild…" for
    a few seconds, then shows 2 coloured rows without letters and 4 tries
    left, and chat says "brought back 2 guesses". `/sr debug` "Short Words
    guesses kept by guildmates" line.

## v0.9.2

46. [ ] **Milestones** (Overview): no Grats button; times like "2h" and
    "13d" show in full, without "…".

## v0.9.3

47. [ ] Ask the guildmate who got the "Sending to guildmates is failing
    (GeneralError)" message to update and, after a while, send `/sr debug`
    again: the "Failed sends by kind" line and the lines under it say which
    messages fail and to whom.

## v0.9.4

48. [ ] **Professions → Cooldowns:** no cooldown shows more than a few days
    (transmutes are at most 2 days). Jheri's transmutes that showed "49d
    19h" now show a sensible time, even before Jheri updates.

## v0.10.0 In or Bench, Discord by copy and paste

49. [ ] **In or Bench** (officer with `/sr officer`): on a raid, click a
    name: *In*, again: *Bench*, again: nothing. Right-click opens their
    character. A guildmate on v0.10.0 sees the same *Raid* column within a
    minute, and their own "You're in" / "You're on the bench" on the Raids
    page and on the Overview.
50. [ ] **Copy for Discord**, paste into a Discord channel: the time shows
    in your own time zone, names are grouped by role.
51. [ ] **Import sign-ups from Discord**: copy a sign-up list from Discord
    (a bot's message or names typed by hand), paste it, press Import. The
    line under the box says how many were added; the names appear in the
    line-up. Tell me what it couldn't match (paste me the list).

## v0.10.1 Officers view on the Roster

52. [ ] With `/sr officer` on, Roster shows an **Officers** chip; a member
    doesn't see it. Click it: every member with Rank, Roles, Attend. and
    Note; alts under their main.
53. [ ] Click a name: tick Tank / Healer / DPS, pick *Alt of*, write a note
    and press **Save note**. Another officer on v0.10.1 sees the same
    within a minute (or about 2 minutes after logging in).
54. [ ] The *Attend.* column matches the Attendance tab's 30-day totals.

## v0.10.2 Raid calendar

55. [ ] **Raids → Calendar**: this month, weeks from Monday, today outlined,
    each raid on the right day at the right time for you. Click a raid: it
    opens on the Raids tab. **<** / **>** / **Today** work.
56. [ ] Officers: click an empty day in the next two weeks: New raid opens
    with that day picked.

## v0.11.0 Groups, Invite & arrange, away days, assignments

57. [ ] **Raids → Groups** (officer with `/sr officer`): drag a name from
    Available into a group, from a group onto the Bench, and back. Also
    click a name, then click a group. Dropping on a full group swaps the
    two. A guildmate on v0.11.0 sees the same groups within a minute and
    "You're in group N" on the Raids page.
58. [ ] Right-click a name in a group: late, then leaving early, then
    absent, then nothing. The mark shows for everyone.
59. [ ] **Auto-fill** on a raid with sign-ups: the line under the buttons
    says how many were placed and benched; each group has a healer; tanks
    fill the first groups; people already placed didn't move.
60. [ ] **Invite & arrange** while leading (not in a group yet): it invites
    4. Press again once one joined: it becomes a raid. Press again: the
    rest are invited and, as they join, moved into their groups ("Raid
    groups arranged." in chat). Tell me any red error text from the game.
61. [ ] **Away days**: Calendar → right-click a day: "away" shows on it. Tick
    **Away every** Tue: every Tuesday shows away. If you'd signed up for a
    raid that day, your answer becomes *Can't come*. An officer sees "N
    away" on that day and "away" next to your name in Groups.
62. [ ] **Assignments** (officer): type "Onyxia", Add boss; pick "Main tank"
    from *Add a job…*; click the job, then names on the right. A member sees
    the jobs and "Main tank on Onyxia" on their Raids page. **Copy last
    raid** on the next Onyxia brings them over.

## v0.12.0 Discord bot (after the setup in docs/DISCORD-BOT.md)

63. [ ] The **Discord bot** workflow run is green, and its last step printed
    an "Add the bot" link that worked.
64. [ ] In game (officer): raid ··· menu → **Post with the Discord bot** →
    copy all. In Discord: `/raid-post`, paste, Submit: the raid appears with
    the right time and names. Do it again: the same post updates.
65. [ ] A member presses **DPS** without linking: the bot asks them to
    `/link`. After `/link Their Name`, the button puts them on the post.
66. [ ] **Copy for the addon** → in game *Import sign-ups from Discord* →
    paste → Import: those players appear in the line-up.

## v0.13.0 Raid roster planner (officers, with /sr officer)

67. [ ] **Roster → Officers**: one row per player (no Alt-rank characters,
    alts shown as "+1"). The "All" line under the chips adds up (at 60,
    attuned, missing enchants, without the addon).
68. [ ] Click a **Tank / Healer / DPS** cell: a small menu, pick Main or
    Backup. Click **Status**: Raider or Backup. Another officer on v0.13.0
    sees the same within a minute.
69. [ ] **Tanks** chip: mains, then backups, then unsorted players with a
    tanking spec. Click someone's **Away** cell: a month calendar opens
    with raid days underlined. Click two days this week: they turn red, the
    cell says e.g. "9-10 Dec" (red if a raid is on one), and the Main header
    says "AWAY THIS WEEK: NAME". A player's own away days (Raids → Calendar)
    show outlined; hover a day for who set it.
70. [ ] Click a **note** cell: write a note, Save my note. Another officer
    adds theirs: both show, with names and how long ago. Remove mine works.
71. [ ] Click a **name**: their Character page has an **Officers** section
    (with Away days); **Alt of** links an alt (it disappears from the
    planner, "+1" on the main).
72. [ ] **Needs a look**, **Raider**, **Backup** filters; column titles sort;
    **Sign-ups** menu shows who signed up for a raid.
73. [ ] ··· → **Taller window**: the window grows; the list shows more rows.
74. [x] (Removed in v0.14.2: the "+N" level and item level gains.)

## v0.14.0 Raids from the calendar, attendance at the start time

75. [ ] Roster → Officers: a role menu says **Main / Off / No**; the Status
    menu has **Social**; the **Social** chip filters them.
76. [ ] Raids → **Calendar**, click a day (as a member): the day box has
    **I'm away this day**; the day then says "away" and officers see it.
77. [ ] As an officer: click a day **six weeks ahead**, pick 20:00 and
    **Hyjal + Onyxia**, Create raid. Everyone sees "Hyjal + Onyxia (40)".
78. [ ] Make a raid with **no instance**: it reads "Raid (to be decided)".
    On the Raids page, click the **Onyxia** chip by its title: it becomes
    Onyxia's Lair for everyone within a minute.
79. [ ] **Groups** on the Hyjal + Onyxia night: chips **Hyjal** / **Onyxia**
    show different groups (4 and 8). Bench takes someone out of both.
80. [ ] **Loot** on that night: the list has both raids' items.
81. [ ] Attendance: sign up three players; at the raid's start, have one
    online, one log in 5 minutes later, one stay offline. 15 minutes after
    the start (an officer online the whole time) Attendance shows **On time**,
    **Late**, **No-show**. Another officer sees the same.
82. [ ] A player signs up, then changes to Can't come: the raid's
    Attendance shows "Changed … before" (orange within a day), and Totals
    count it under **Changed** and **<24h**.
83. [ ] `/sr debug` "Attendance (v0.14.0, online at the start)" line: checking
    yes during the first 15 minutes of a raid.


## v0.14.1 Item names on the Loot page

84. [ ] Loot → Reserves on an Onyxia night: every item has a **name**, an
    **icon** and purple (epic) text, in A–Z order; no "item 16900" rows.
    Say whether the icons show (or are blank / a green square).
85. [ ] Hover an item the game doesn't know yet (e.g. Stormrage Cover): the
    tooltip says "Head, Leather" and "Not in the game's item data yet".
    Hover Onyxia Hide Backpack: the game's own item tooltip.