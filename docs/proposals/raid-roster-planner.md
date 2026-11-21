# Raid roster planner (built in v0.13.0, 21 Nov 2026)

Built from version 3 below with the four review fixes: an "All" summary
line, cell menus instead of cycling, clearer columns (Ony, away in the row,
item level gain, alts on hover), sortable columns and players without the
addon. Status/roles/notes are changed in the table; away weeks and Alt of on
the Character page; "Taller window" in the Roster ··· menu.

From the officers' feedback (21 Nov): raids open on 9 Dec, the guild grew
fast, and the officers don't all know everyone. They want **one overview**
for building the raid roster: who can fill which role as a **main or a
backup**, how each player's **levelling, gear and attunement** are going,
**notes** shared between officers, and **gaps** to work on before release.
Today they'd use a spreadsheet and check everyone's armory by hand; the
addon already has the level, gear, enchants and attunement data.

Pictures (mock-ups, made-up names): `docs/images/roster-planner.png`,
`docs/images/roster-planner-edit.png`.

## What it is (version 3, 21 Nov, after the officer's second round)

Officer's feedback on version 2: "much closer to what I envisioned"; remove
the coverage tiles (the table is enough); it's for the **static roster**,
not one raid (seeing who signed up for a chosen raid is a nice extra);
statuses **Raider** and **Backup** only, and they're **not the guild
ranks**; clicking a character should open the **full character view**.

The Roster page's **Officers** view becomes the **roster planner**
(officers and raid leaders with `/sr officer`; members never see it): one
row per person, like the officers' spreadsheet, with level, gear,
attunement and spec filled in from the addon.

1. **Role chips with counts**: All, Tanks 2+3 (mains + backups), Healers,
   DPS, **Not sorted** (no status or roles yet: the people to get to know).
   A role shows its mains, then its backups, then **unsorted people whose
   spec fits** (an unsorted Prot warrior under Tanks). Each group's header
   sums it up: "MAIN 2 · ALL 60 · ALL ATTUNED · BRANNOC AWAY WEEK 1".
2. **Filters**: Raider, Backup, **Needs a look** (not 60, not attuned,
   missing enchants or old data), search by name or note.
3. **The table**: name (class colour, "+2" = alts), spec, **Status**
   (Raider / Backup / not set) and **Tank / Healer / DPS** cells (Main
   filled, Backup outlined) that you **click to change**, level with "+4"
   in 7 days, item level, attuned, missing enchants, **Seen** (age of their
   data; orange after a week), note (hover for every note).
4. **Click a note cell** → a small **Notes** box opens under that row:
   every officer's note with who wrote it and when, a line to add one
   (Enter or Add), and your own notes can be edited or removed. Esc closes
   it. (Officer, 21 Nov: "add notes by clicking on the note cell".)
5. **Click a name** → their **full Character page** (gear, talents,
   professions, attunements) with an **Officers** box at the top of the
   middle column: status, roles, **away by reset week**, **notes with who
   wrote them and when** (several officers each add theirs), Add note.
   *Back to roster* returns to the planner.
6. **Sign-ups for** (optional menu): pick a raid to add a *Signed* column
   (signed up, tentative, can't come, no answer).

Pictures: `docs/images/roster-planner.png` (Tanks chosen),
`docs/images/roster-planner-note.png` (a note cell clicked),
`docs/images/roster-planner-character.png` (the Officers box).

### Earlier versions

- v1 had a row per role (a player up to three times) and tiny T/H/D
  badges; v2 moved to one row per person with clickable role cells, a Not
  sorted pile, spec, alts, seen, note authors and away weeks, with
  coverage tiles and a "Planning for raid and week" menu (both removed in
  v3 at the officer's request).

## Examples from the feedback

| Need | In the planner |
|---|---|
| Two main tanks, one misses the first reset | Both Tank: Main; tick "Wk 1" under Away for the absent one. The Tanks tile shows the gap for week 1 and the backups' progress. |
| Backup tanks | Tank: Backup. They show under Tanks after the mains, with level (+gain), item level, attunement and how fresh the data is. |
| DPS mains who can heal | DPS: Main, Healer: Backup. They count in both tiles. |
| A great raider who can't commit | Status: Backup, all roles Backup, a note for the other officers. |

## How it's built (for the record)

- Extends the v0.10.1 officer roster (`Core/OfficerDir.lua`, shared only
  between officers by whisper, OR/OQ). New entry kinds: **role tiers**
  (Main/Backup per role; replaces the plain roles, which carry over as
  Main), **status** (Raider/Backup; independent of guild ranks), **away weeks**, and **notes from several officers**
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

1. "Ready" in the group headers = level 60 and attuned (Onyxia). Add an
   officer-set item level target? Default: no for now.
2. Window: 50+ rows means scrolling in the 960 × 600 window. Make it taller
   / resizable for this page? Default: yes.
