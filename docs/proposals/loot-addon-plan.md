# Reserve+ plan: soft reserves with bonus points

16 Nov 2026. **Built** inside Short Royalty as v0.9.0 (not released; untested in game).

## What it does

The guild's TBC system: soft reserve (SR). Every time you reserve an item
and **don't get it** (you lose the roll, or it doesn't drop), that item
gets **bonus points** that are added to your roll the next time you
reserve it.

## Owner's decisions (16 Nov)

| Rule | Decision |
|---|---|
| Where | **Inside Short Royalty** (owner: "Great", 16 Nov). |
| Reserves | **Set per raid by officers** (owner, 16 Nov: "we used 2 in Mount Hyjal in TBC but 4 in Black Temple; it depends on how many bosses and items a raid has"). Default 1. **Several reserves may go on the same item** for a double bonus, still one roll (owner, 16 Nov, as in Kerath Raidcheck). |
| Points belong to | **One character + one item.** Alts don't share. |
| Switching items | Reserving a different item starts that item from 0. The old item **keeps** its points, and they count again the night you reserve it again. |
| Points only count on your reserve | If you have 100 on the mace but reserved the trinket tonight and the mace drops, the 100 don't count. |
| When you win | That item's points reset to 0. |
| Boss not killed | **Bonus anyway** (owner changed this 16 Nov: with 10 bosses and only 8 killed, people reserving from bosses 9 and 10 mustn't fall behind). |
| Bench | **Benched players get the bonus too**, so rotating people doesn't make them fall behind. But only if they're **online when reserves are locked** (Nuhra, 16 Nov: standby should mean standby). At the lock, officers see which benched players are online and which aren't; offline ones get no bonus that night, and officers can add a penalty by hand. |
| Missed raid | Points stay, but don't grow. |
| Bonus amount | Editable in the addon by officers (default +10). |
| Cap | **None.** In TBC people reserved Dragonspine Trophy for three phases and built hundreds of points; that was intended. |
| Fixing points by hand | Officers and raid leaders can add or take points with a reason, e.g. a bonus given to someone who didn't show, or a **penalty** for leaving halfway. A penalty can take points below 0. Any change can be undone. |
| Moving points | When someone is asked to main an alt, officers can move points (all or some) to another character, and to a different item if the alt needs other loot. Or simply give the alt a bonus by hand. |
| Who can change points | Officer and Raid Leader ranks (the same rule as v0.8.0 raids). |
| Non-reservers | May roll, but a reserver always beats them, so in practice they only win items nobody reserved. |

## Why inside Short Royalty

The owner agreed on 16 Nov. It's about the size of the v0.8.0
raids update, and most of what it needs is already there:

- **Raid nights** (v0.8.0): a reserve belongs to a raid the officers made.
  You reserve on the same screen where you sign up.
- **Who was there** (v0.8.0/v0.8.1 attendance) decides who gets the bonus.
- **Officer and Raid Leader ranks** are already checked.
- **Sharing** between guild members already works, and everyone already
  has the addon installed. A separate addon would mean a second download
  for 50 people, a new repo and a new CurseForge page.

To avoid clutter it gets **one sidebar line, "Loot"**, with page tabs
*Reserves*, *Points*, *History*, and for officers *Loot night* and *Rules*
(reserves per player for each raid, bonus per night; owner, 16 Nov). People
who don't raid never need to open it.

## How a raid night works

1. **Before the raid:** the officer makes the raid night as now (Raids
   page). Each member picks their reserves (as many as that raid allows)
   from that raid's loot list when signing up. The list shows their saved points on every item, so they
   can go back to an item they've built points on. The officer locks
   reserves before the pull, and sees who on the bench is online.
2. **Boss dies:** the officer's addon notes the kill (the game's "encounter
   ended" event). The loot officer clicks an item: the addon shows who
   reserved it with their bonus, and posts it to raid chat on a button
   press (the game allows addon chat only on a button press).
3. **Players `/roll`.** The officer's addon reads the rolls: reservers
   first, by *roll + bonus*; then everyone else. Ties re-roll.
4. **Award:** master loot or trade. The winner's points on that item go to 0.
5. **End of night:** every reserve that wasn't won gets +bonus, for
   everyone who was in the raid or online on the bench at the lock
   (whether the boss died or not; no cap). The officer checks the list and
   confirms. It's saved in the history.

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

## Loot lists: filled in without typing (owner, 16 Nov)

Owner: "future proof this to look at some websites to see the loot that
drops from the raid rather than having to do anything manually". Addons
can't use the internet in game, so the websites are read outside the
game and the result ships with the addon. Three sources, merged:

1. **The game's Encounter Journal.** Forever's client has Blizzard's
   journal behind a game rule (`GameRulesUtil.EJIsDisabled`); its data had
   no journal tables on 16 Nov. If Forever turns it on for its raids, every
   player's addon reads the loot from it, no update needed. `/sr debug`
   says whether it's on and which raids it lists.
2. **warcraft.wiki.gg** (public API; content reusable with credit):
   `node tools/loot.js` finds each raid's loot page, takes its loot
   entries, looks up each item's ID and checks it against Forever's own
   item data (wago.tools). A weekly GitHub job (`.github/workflows/loot.yml`)
   reruns it and commits `Data/Loot.lua` when a list changed; the next
   release ships it. Wowhead is not read (its terms forbid scraping).
3. **Drops and officers:** the officer's addon adds every rare+ item it
   sees in a loot window (shared with everyone); officers can still add an
   item by hand.

On 16 Nov: Onyxia = the wiki's original-game list (20 items; 4 in
Forever's data, the rest probably held back until the raid opens);
Barrow Deeps and Hyjal Summit have no loot page yet.

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

1. **Done 16 Nov** (`Core/Reserves.lua`, `tests/v090_reserves_spec.lua`):
   points history and rules: bonus (no cap), reset on win, per character +
   item, only tonight's reserves count, reserves per raid, bench at the
   lock, changes by hand, penalties, moves, undo, ranking rolls (ties: more
   points, then re-roll), end-of-night bonus.
2. **Done 16 Nov:** loot lists (`Data/Loot.lua`: Onyxia's original loot;
   learning from drops and officers adding items, ledger kind `l`). Not
   done: a script for Barrow Deeps / Hyjal bosses (not in the game files
   yet; ENCOUNTER_END gives kills anyway, and the boss rule was dropped).
3. **Done 16 Nov:** reserving happens on the Loot page (not the Raids
   sign-up: simpler), sharing (`Sync/ReserveSync.lua`).
4. **Done 16 Nov:** Loot page: Reserves, Points, History.
5. **Done 16 Nov:** Loot night, Rules, "Reserved by" on item tooltips.
6. **Done 16 Nov:** `/sr debug` block, README, TESTING 30–40, pictures.

Then a **test run** in a dungeon before 9 Dec. If it isn't tested by then,
run the first night by hand and switch over after.

## Compared with Kerath Raidcheck (16 Nov)

The guild's TBC tool was **Kerath Raidcheck** (CurseForge, Classic Era only,
All Rights Reserved: features only, never code), used with **Gargul** and
softres.it. What it does and what we take:

| Kerath Raidcheck | Reserve+ |
|---|---|
| Points per character, tracked between raids | Same. |
| Highest points + roll wins among reservers | Same. |
| Equal totals: **more points wins**; equal points too: re-roll | **Adopted** (`Reserves.Rank`). |
| Items nobody reserved: normal rolls | Same (anyone can roll; reservers come first). |
| +10 per reserve, added when you reserve (also for that night) | Owner's rule instead: added after the night, if you were there (or online on the bench) and didn't win it. |
| 2 reserves a raid, both may go on one item (+20, one roll) | **Adopted**; reserves per raid set by officers. |
| Points live in a Google Sheet, pasted in each raid | In the addon, shared with everyone, history kept. |
| Raid check: reservers not in the raid, raiders without a reserve | **Adopted** on Loot night (mock-up). |
| Buff check | Later: see "Replacing Gargul". |

From Gargul (owner): item tooltips show who reserved the item. **Adopted**:
on a raid night, every item tooltip (bags, loot window, AtlasLoot, NeedRoll)
gets "Reserved by …" with points (mock-up `loot-tooltip.png`). Gargul (it
supports Forever since 3 Oct) stays in use for handing out loot **for now**;
the owner wants to replace it later: see the next section.

## Replacing Gargul (later, after Reserve+)

Owner, 16 Nov: "fine for now, but create a plan for us to come back to this
as we don't want to use Gargul". Gargul is used for the first raids; these
parts replace it one at a time, **each tested in a real raid before the
next**. Features only, written from scratch (never Gargul's code).

**Gate first (blocks parts 2–4):** an officer's `/sr debug` inside a raid
must show which loot methods Forever allows. The client still has master
loot (`Enum.LootMethod.Masterlooter`, `GiveMasterLoot`, `MasterLooterFrame`
in the forever UI source), but only the game can say if raids use it. If
it doesn't, parts 2 and 4 become "trade helpers" instead.

| Part | What | Needs | Size |
|---|---|---|---|
| 1. Buff check | Before the pull: who's missing required buffs or consumables, who has the "bonus" world buffs (as Kerath Raidcheck). Officers pick the list. | Reading raid members' buffs inside an instance (Forever's newer restrictions: check in game). Buff spell IDs from Forever's data, verified twice. | Small |
| 2. Hand out in one click | On Loot night, Award gives the item to the winner straight from the loot window (master loot), and records the win. Without master loot: a trade reminder and "trade this to X" when the winner opens a trade. | Master loot, or trade events. | Medium |
| 3. Disenchanter and auto-loot rules | Officers name a disenchanter (and a banker for materials); items nobody needs, and items matching rules (e.g. all greens, all Onyxia hide bags), go to them automatically. | Master loot. | Medium |
| 4. Loot council | For chosen items, officers vote in a small window: each candidate's reserve and points, item level of what they wear now (we already have their gear), attendance %, and past wins. The raid leader confirms. | Addon messages between officers inside the raid between pulls (check in game). | Large |
| 5. Loot history | Who got what, when, from which boss; search and filter. | Nothing new (the win entries already exist). | Small |

Gargul's other modes (GDKP gold auctions, TMB/DFT/PRIO3 lists) aren't
planned unless the guild asks.

## Answered 16 Nov

- Reserves are **visible to everyone** before the lock.
- Starting bonus **+10 per night** (officers can change it).
- The guild's TBC tool was **Kerath Raidcheck** with Gargul (see above).
- 16 Nov (owner, Nuhra): reserves per raid set by officers; bonus even if
  the boss isn't killed; benched players get it if online at the lock.
- Two reserves may go on the same item: double points, one roll (owner).
- Still to ask: "delete their points" for offline bench: no bonus that
  night (built), or also a penalty / wipe? Officers can do either by hand.

## Mock-ups (16 Nov)

`docs/images/loot*.png` (preview `screen=loot`, `lootView`, `lootMode`,
`officer=1`): Reserves, Points (mine / everyone + officer "Change points"),
History, Loot night, End of night, Rules (`loot-rules.png`), item tooltip.
Waiting for the owner's verdict.
