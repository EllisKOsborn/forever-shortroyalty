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

## What it is (version 2, after reviewing version 1 against the message)

The Roster page's **Officers** view becomes the **roster planner**
(officers and raid leaders with `/sr officer`; members never see it). It
works like the officers' spreadsheet, **one row per person**, but the
level, gear, attunement and spec fill themselves in from the addon.

1. **Planning for** a raid and **reset week** (default: Onyxia, week 1 =
   9 Dec). It sets the role targets and who's away that week.
2. **Four coverage tiles**: Tanks, Healers, DPS (mains available that week
   out of the target, a bar of ready / 55+ / levelling / away, one gap line)
   and **Not sorted** (people with no status or roles yet: "start here").
   Clicking a tile filters the list to that role: its mains, then its
   backups, then **unsorted people whose spec fits** (e.g. an unsorted Prot
   warrior shows under Tanks). Nobody appears twice.
3. **The list**: name (class colour, "+2" = alts), spec, status, **Tank /
   Healer / DPS cells** (Main filled, Backup outlined; **click a cell** to
   cycle none → Backup → Main, like typing in a spreadsheet), level with
   "+4" gained in 7 days, item level, attuned, missing enchants, **seen**
   (how old their data is; orange after a week), note (hover for all of it).
   Chips: All, **Needs a look** (not 60, not attuned, missing enchants or
   old data), Core, Backup, Trial. Right-click opens their Character page.
4. **Click a name** for the side panel: spec with talent points, level,
   item level, attunement, **alts**, **status** (Core, Backup raider,
   Trial, Not raiding), **away by reset week** (on top of the away days
   players set themselves), **notes with who wrote them and when** (several
   officers can add notes), and the last 7 days' progress.

### What changed from version 1 (and why)

- One row per person instead of a row per role (version 1 listed a player
  up to three times).
- Role cells you click in the list instead of tiny T/H/D badges.
- Added: a **Not sorted** pile (the officers don't know everyone yet),
  **spec**, **alts**, **seen** (is the progress real?), note authors,
  rank (in the panel), away by **reset week** ("misses the first reset").
- Smaller tiles, so the list gets more of the 600-pixel window.

## Examples from the feedback

| Need | In the planner |
|---|---|
| Two main tanks, one misses the first reset | Both Tank: Main; tick "Wk 1" under Away for the absent one. The Tanks tile shows the gap for week 1 and the backups' progress. |
| Backup tanks | Tank: Backup. They show under Tanks after the mains, with level (+gain), item level, attunement and how fresh the data is. |
| DPS mains who can heal | DPS: Main, Healer: Backup. They count in both tiles. |
| A great raider who can't commit | Status: Backup raider, all roles Backup, a note for the other officers. |

## How it's built (for the record)

- Extends the v0.10.1 officer roster (`Core/OfficerDir.lua`, shared only
  between officers by whisper, OR/OQ). New entry kinds: **role tiers**
  (Main/Backup per role; replaces the plain roles, which carry over as
  Main), **status**, **away weeks**, and **notes from several officers**
  (each officer's note kept with its author and date; today's single note
  carries over). Officers on v0.12.0 ignore the
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
4. **Window size**: 50+ rows in a 960 × 600 window means scrolling. Make
   the window resizable (taller) for this page? Default: yes.
