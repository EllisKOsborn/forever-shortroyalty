# Reserve+ plan: soft reserves with bonus points

Draft, 16 Nov 2026. Nothing is built yet.

## What it does

The guild's TBC system: soft reserve (SR). Every time you reserve an item
and **don't get it** (you lose the roll, or it doesn't drop), that item
gets **bonus points** that are added to your roll the next time you
reserve it.

## Owner's decisions (16 Nov)

| Rule | Decision |
|---|---|
| Where | **Inside Short Royalty** if it isn't a big build, else a separate addon called **ReservePlus**. Recommendation below: inside. |
| Reserves | **1** per character per raid night. |
| Points belong to | **One character + one item.** Alts don't share. |
| Switching items | Reserving a different item starts that item from 0. The old item **keeps** its points, and they count again the night you reserve it again. |
| Points only count on your reserve | If you have 100 on the mace but reserved the trinket tonight and the mace drops, the 100 don't count. |
| When you win | That item's points reset to 0. |
| Boss not killed | **No bonus** for items from that boss. |
| Missed raid | Points stay, but don't grow. |
| Bonus amount and cap | Editable in the addon by officers, e.g. +10 per night up to +50. |
| Who can change points | Officer and Raid Leader ranks (the same rule as v0.8.0 raids). |
| Non-reservers | May roll, but a reserver always beats them, so in practice they only win items nobody reserved. |

## Inside Short Royalty or separate?

**Recommendation: inside Short Royalty.** It's about the size of the v0.8.0
raids update, and most of what it needs is already there:

- **Raid nights** (v0.8.0): a reserve belongs to a raid the officers made.
  You reserve on the same screen where you sign up.
- **Who was there** (v0.8.0/v0.8.1 attendance) decides who gets the bonus.
- **Officer and Raid Leader ranks** are already checked.
- **Sharing** between guild members already works, and everyone already
  has the addon installed. A separate addon would mean a second download
  for 50 people, a new repo and a new CurseForge page.

To avoid clutter it gets **one sidebar line, "Loot"**, with page tabs
*Reserves*, *My points*, *History*, and for officers *Loot night*. People
who don't raid never need to open it.

If you'd still rather keep it separate, the same plan works as
**ReservePlus**. It's more work (it can't reuse the raid nights and
attendance) and it needs the empty repo.

## How a raid night works

1. **Before the raid:** the officer makes the raid night as now (Raids
   page). Each member picks **one** item from that raid's loot list when
   signing up. The list shows their saved points on every item, so they
   can go back to an item they've built points on. The officer locks
   reserves before the pull.
2. **Boss dies:** the officer's addon notes the kill (the game's "encounter
   ended" event). The loot officer clicks an item: the addon shows who
   reserved it with their bonus, and posts it to raid chat on a button
   press (the game allows addon chat only on a button press).
3. **Players `/roll`.** The officer's addon reads the rolls: reservers
   first, by *roll + bonus*; then everyone else. Ties re-roll.
4. **Award:** master loot or trade. The winner's points on that item go to 0.
5. **End of night:** every reserver who was there, whose item's boss was
   **killed**, and who didn't win it, gets +bonus (up to the cap). The
   officer checks the list and confirms. It's saved in the history.

## Trust: why only officers can change points

Anyone could send the addon fake data, so:

- Points are a **history of changes** (who, when, what). The numbers are
  added up from the history, so every number can be explained, and an
  officer can undo a mistake.
- A points change is accepted only from someone with an **officer or raid
  leader rank** in **our own** guild roster (never trust the message).
- A **reserve** is accepted only from the character's own player, like
  sign-ups now.
- Every member keeps the full history, so nothing is lost if an officer
  quits. Bonus and cap changes go into the history too and only count
  from then on.

## Loot lists (searched 16 Nov)

- **Onyxia's Lair:** in the game files now; one boss (encounter 1084). The
  loot list can be built now from public sources and checked against
  Forever's item data.
- **Barrow Deeps and Hyjal Summit:** brand-new raids. They are **not in the
  game files yet** (checked build 1.60.1.70938 on wago.tools: no map, no
  bosses), and **no loot list has been published**. Guides even disagree
  on the boss names. So nobody can know their loot before the patch that
  adds them.

How we fill the lists anyway:

1. When the patch lands, rerun a data script (like the recipe one) to get
   each raid's **bosses** from Forever's own data.
2. Once trustworthy lists appear (warcraft.wiki.gg, which allows reuse with
   credit; checked by hand against Wowhead's Forever pages, which we may
   link but not scrape; AtlasLoot Classic Forever and NeedRoll are
   building lists too), add them to the addon's data in an update.
3. **The addon learns as you raid:** items in the loot window after a boss
   kill are added to that boss's list and shared with everyone. Officers
   can also add an item to a boss by shift-clicking it.

Honest result: **on the first night of a new raid there may be no list to
reserve from**, unless a reliable list appears in time. From the second
week on, the learned list works.

## Checks needed in game

The Forever client still has the master-looter window
(`Enum.LootMethod.Masterlooter`, `GiveMasterLoot`), but only the game can
tell us if raids allow it. An officer in an instance group (a dungeon is
enough) runs `/sr debug` and we check:

1. Which loot methods the leader can pick.
2. That the addon can read `/roll` results inside an instance.
3. That the addon can post to raid chat from a button press.
4. That the "encounter ended" event arrives (it does in Classic).

Without master loot, items are traded and the addon only records the
winner.

## Build order (inside Short Royalty)

1. Points history and rules: pure Lua, many tests (bonus, cap, reset on
   win, per character + item, only your reserve counts, boss-killed rule,
   undo).
2. Loot lists: Onyxia now; the boss script ready for the patch; learning
   from drops.
3. Reserve on sign-up, and sharing (reserves from players, points from
   officers).
4. Loot page: Reserves, My points, History.
5. Officer's Loot night: kills, rolls, award, end of night.
6. `/sr debug` checks, README, TESTING, pictures.

Then a **test run** in a dungeon before 9 Dec. If it isn't tested by then,
run the first night by hand and switch over after.

## Still open

1. **Inside Short Royalty, or separate as ReservePlus?** (Recommendation:
   inside.)
2. **Show reserves to everyone before the lock, or hide them?** Default
   unless you say otherwise: shown, like softres.it.
3. Starting numbers: **+10 per night, cap +50**? (Officers can change them.)
4. Ask the guildmate for the **name of the TBC addon**, so we can read its
   feature list (not its code).
