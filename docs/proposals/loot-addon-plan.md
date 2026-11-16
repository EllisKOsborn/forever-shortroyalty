# Loot addon plan: soft reserves with bonus points

Draft, 16 Nov 2026. Moves to the new addon's own repo once it exists.
Nothing is built yet.

## What it does

The guild's TBC system: soft reserve (SR), then main spec (MS), then
off spec (OS). Every time you reserve an item and **don't get it** (you
lose the roll, or it doesn't drop), that item gets **bonus points** that
are added to your roll the next time.

Decided by the owner (16 Nov):

| Rule | Decision |
|---|---|
| Separate addon | Yes, its own addon, repo, release and CurseForge page, so Short Royalty doesn't get cluttered. |
| Look | Same family as Short Royalty v0.6.0 (the Polestar/FojjiCore-inspired sidebar look). |
| Bonus amount | Editable in the addon (officers). |
| Bonus cap | Editable in the addon (officers), e.g. +10 per raid up to +50. |
| Points belong to | The **item**. Reserving a different item starts that one at 0; the old item keeps its points. |
| When you win | That item's points reset to 0. |
| Missed raid / item not reserved that week | Points stay, but don't grow. |
| Alts | Don't share points. Every character has its own. |
| Who can change points | Raid leader and officers. |

Still open: see "Questions" at the end.

## How a raid night works

1. **Before the raid** (in town): an officer opens a raid night and picks
   the raid. Members pick their reserve in the addon (as with v0.8.0
   sign-ups, people without the addon need to install it). The officer
   locks reserves.
2. **Boss dies, loot shows:** the loot officer clicks the item. The addon
   shows who reserved it and their bonus, and posts the item to raid chat
   when the officer presses the button (the game only lets addons post to
   chat on a button press).
3. **Players `/roll`.** The officer's addon reads the rolls and shows
   *roll + bonus = total*, reservers first, then MS, then OS. Ties re-roll.
4. **Officer awards** (master loot or trade). The winner's points for that
   item go to 0.
5. **End of night:** every reserver who was there and didn't win their item
   gets +bonus on it (up to the cap). The officer sees the list and
   confirms. Everything goes into the history.

During the raid only the **officer's** addon has to work. Everyone else's
addon catches up after the raid.

## Trust: why only officers can change points

Short Royalty treats everything another player sends as untrusted, and
anyone could send fake data. That's fine for gear and recipes, but not for
loot points. So:

- The points are a **history of changes** (who, when, what), not just
  numbers. Points are added up from the history, so every number can be
  explained and a mistake can be undone.
- A change is accepted only if its author has an **officer or raid leader
  rank**, checked against **our own** guild roster, never the message. This
  uses the same rank rule as Short Royalty's raids (guild master, or a rank
  named "Officer" / "Raid Leader").
- Members' addons only **read**. Every member keeps a full copy, so the
  points survive if an officer quits.
- Settings changes (bonus, cap) are history entries too, and apply from
  then on, not backwards.

## Working with Short Royalty

The two addons stay separate (each works alone), with different saved
data and message prefixes. If both are installed, the loot addon *can*
read Short Royalty's raid list (v0.8.0), so an officer picks tonight's raid
instead of typing it, and its attendance to decide who "was there". That's
a later step. Version 1 records who was in the raid group at each boss
kill by itself.

## Loot lists

Forever's game data has **no boss loot tables** (checked 16 Nov: wago.tools
has no journal tables for the Forever build). softres.it shows no sign of
Forever support either. So the item list comes from:

- officers adding items (shift-click an item link, or paste item IDs);
- the addon **learning** every item that drops in a raid (the loot window
  and loot messages), per raid;
- for the first raids, an officer fills in the list once from Wowhead's
  Forever pages by hand. We link to Wowhead but don't copy from it
  automatically, because its terms forbid scraping.

Only three raids open on 9 Dec (Barrow Deeps, Hyjal Summit, Onyxia), so
this is a small job.

## Checks needed in game before we rely on it

From Blizzard's Forever code (16 Nov): the client still has the **master
looter** loot method and window (`Enum.LootMethod.Masterlooter`,
`GiveMasterLoot`, `MasterLooterFrame`), but the code can't say whether
Forever's servers allow it in raids. Forever also has the newer chat
restrictions inside instances. Before the first real use, an officer in a
group inside an instance (a dungeon is enough) runs the addon's debug
report and checks:

1. Which loot methods the leader can pick (master loot? group loot?).
2. That `/roll` results can be read by the addon inside an instance, out
   of combat.
3. That addon messages arrive inside an instance, out of combat. Short
   Royalty pauses there on purpose. The loot addon only needs them between
   pulls, and could wait until the raid ends.
4. That an addon can post to raid chat from a button press.

If master loot isn't allowed, the officer hands items over by trade, and
the addon only records the winner.

## Look

The same family as Short Royalty v0.6.0 (`DESIGN.md`): the 960 × 600
window, sidebar with the crest and sections, page header with one
sentence, page tabs with an accent underline, one accent colour, Inter,
true black. Reusing our own Theme and widgets is faster and makes the two
addons feel like a pair. It needs its own crest or icon (ideas welcome) and
probably its own default accent so you can tell them apart. Polestar and
FojjiCore stay **inspiration only**: no code or art copied (GPL / All
Rights Reserved).

## Screens

| Sidebar | Who | What |
|---|---|---|
| **Reserves** | everyone | Tonight's raid, its items, my reserve and its bonus, who reserved what. |
| **Loot** | loot officer, in raid | Current item, reservers with bonus, live roll table (roll + bonus = total, SR/MS/OS), Award button, raid-chat button. |
| **Points** | everyone | Every character's points per item; search; "my points". |
| **History** | everyone | Every change: who, when, why. Officers can undo an entry. |
| **Settings** | officers edit, others read | Bonus per raid, cap, reserves per player, scale, minimap. |

## Build order

0. **Owner:** create the empty GitHub repo, pick the name, add the repo to
   this Claude session. The name sets the folder, saved data and message
   prefix, which **can't change after rollout**.
1. **Skeleton:** TOC, CI, tests, release workflow, and the theme, widgets and
   sending code taken from Short Royalty (our own code). Mock-ups first so
   you can approve the screens.
2. **Points history and rules** (pure Lua, many tests): bonus, cap, reset
   on win, undo, settings changes.
3. **Sharing the history** between guild members (officer-only changes).
4. **Reserves and Points screens.**
5. **Loot screen** (rolls, award, end of night).
6. **Debug report** with the in-game checks above.

Rough size: about as big as Short Royalty's v0.8.0 raids update. Steps 1–5
take about a week of sessions. Then it needs a **test run** (a dungeon
group works) before 9 Dec. If it isn't tested by then, run the first raids
by hand and switch over after.

## Questions

1. **Name.** Ideas: *Royal Reserve*, *Crown Roll*, *Reserve+*. Slash
   command to match (e.g. `/rr`).
2. **Reserves per player per raid:** 1 or 2? (A setting, default 1?)
3. **Item didn't drop because the boss wasn't killed** (wipe, raid ended
   early): bonus or not? Suggestion: bonus only when the boss was killed.
4. **Non-reservers:** can someone roll MS on an item someone else reserved?
   (Usually not: reservers only; MS/OS only if nobody reserved it.)
5. **Hide other people's reserves until the lock?** Some guilds do, so
   people can't reserve tactically.
6. Ask the guildmate for the **name of the TBC addon** they used, so we
   can read its feature list (not its code).
