# Raid roster planner (proposal, 21 Nov 2026)

From the officers' feedback (21 Nov): raids open on 9 Dec, the guild grew
fast, and the officers don't all know everyone. They want **one overview**
for building the raid roster: who can fill which role as a **main or a
backup**, how each player's **levelling, gear and attunement** are going,
**notes** shared between officers, and **gaps** to work on before release.
Today they'd use a spreadsheet and check everyone's armory by hand; the
addon already has the level, gear, enchants and attunement data.

Pictures (mock-ups, made-up names): `docs/images/roster-planner.png`,
`docs/images/roster-planner-edit.png`.

## What it is

The Roster page's **Officers** view becomes the **roster planner**
(officers and raid leaders with `/sr officer`; members never see it).

1. **Planning for** a raid and date (default: the next raid, or Onyxia on
   9 Dec until one is made). It sets the role targets and who's away.
2. **Coverage cards** for Tanks, Healers and DPS: mains available out of the
   target, plus backups, and a bar of who's **ready** (level 60 and attuned
   for that raid), **close** (55+), **levelling** or **away**. A one-line
   gap under each ("Brannoc away 9 Dec", "6 short of 10"). An **Everyone**
   card: how many are 60 (and how many reached it this week), 55–59,
   attuned, missing enchants.
3. **The list**, grouped by role (Tanks main, Tanks backup, Healers main…;
   a player shows in every group they fill). Columns: name, status, role
   badges (filled = main, outline = backup), level (with "+4" levels in the
   last 7 days), item level, attuned, missing enchants, attendance %, note.
   Chips: **By role**, **Everyone** (one row each, sortable), **Gaps** (only
   people with something to chase: not 60, not attuned, missing enchants,
   or old data). Right-click opens their Character page (gear, talents).
4. **Click a name** for the side panel: **Status** (Core, Backup raider,
   Trial, Not raiding), **Main / Backup / no** for Tank, Healer and DPS,
   **Can't make** (raid dates an officer marks for them, on top of the
   away days players set themselves), the officer **note**, and the last 7
   days' progress.

## Examples from the feedback

| Need | In the planner |
|---|---|
| Two main tanks, one misses the first reset | Both Tank: Main; tick "Wed 9 Dec" under Can't make for the absent one. The Tanks card shows 1 of 2 mains on 9 Dec and the backups' progress. |
| Backup tanks | Tank: Backup. They show under Tanks · Backup with level (+gain), item level, attunement. |
| DPS mains who can heal | DPS: Main, Healer: Backup. They count in both cards. |
| A great raider who can't commit | Status: Backup raider, all roles Backup, a note for the other officers. |

## How it's built (for the record)

- Extends the v0.10.1 officer roster (`Core/OfficerDir.lua`, shared only
  between officers by whisper, OR/OQ). New entry kinds: **role tiers**
  (Main/Backup per role; replaces the plain roles, which carry over as
  Main), **status**, **can't make** (dates). Officers on v0.12.0 ignore the
  new kinds safely; everyone needs the new version to see them.
- **Progress**: each officer's game remembers each member's level and item
  level once a day (kept 30 days, local), for the "+4 in 7 days" figures.
- Readiness uses the attunement check the Roster already has; gear = item
  level + missing enchants (the Character page has the rest).
- Role tiers also feed **Auto-fill** on the Groups page: mains first,
  backups when a role is short.

## Not in it

- Armory links: Forever's web armory pages aren't confirmed; the Character
  page shows the same gear from the game itself.
- Members setting their own tiers or status: officers only, as asked.

## Questions for the owner

1. **Targets per raid**: 40 = 4 tanks, 10 healers, 26 DPS; 20 = 2 / 5 / 13;
   10 = 2 / 3 / 5. Officers can change them. OK?
2. **Ready** = level 60 and attuned for that raid. Add an officer-set item
   level target too (shown as "below 58")? Default: yes, optional.
3. **Status** names: Core, Backup raider, Trial, Not raiding. OK?
