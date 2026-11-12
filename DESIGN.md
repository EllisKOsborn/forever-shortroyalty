# Short Royalty design system

The look of the in-game addon. Every value here lives in `UI/Theme.lua`;
this file says why. v0.6.0 (12 Nov 2026) is a calmer redesign the owner
picked from three directions (`docs/design/v0.6-directions.html`: the
sidebar, "B"), inspired by FojjiCore, EllesmereUI and Polestar. Inspiration
only: none of their code, textures, icons or layouts is copied (two are All
Rights Reserved, one is GPL). It keeps the earlier base: true black, the
guild's mascot (a gnome with a pink beard and lit dynamite), Chakra Petch.

## Mode
Operate. People open the window to find a person, a crafter or a number in
a few seconds. Familiar patterns (a sidebar, tabs, lists, switches) stay
familiar; the brand lives in colour, type and a few precise details.

## Layout
- **Window** 960 × 600 (shrinks to fit small screens). **Sidebar** 184 on
  the left: crest and name, the sections **Guild** (Overview, Roster,
  Character) and **Crafting** (Find a crafter, Professions), then Settings,
  and the sync status at the bottom (dot, "Synced", guild and who's online,
  or "Update: … is out").
- **Page header** 60: the page title (display, uppercase) and **one
  sentence** saying what the page is for. The close button on its right.
- **Page tabs** (Professions: Guild / Recipes / Cooldowns; Settings:
  General / Advanced) sit under the header: plain text, accent underline.
  A page has one row of tabs at most; a new feature gets a tab or a sidebar
  line, never another row of buttons.
- **Content** 744 wide (`Theme.SIZES.contentW`). Two columns of cards on
  the Overview and Settings.

Why: the old top row of tabs was full, and Professions' own views looked
exactly like its filter chips. Two levels (sidebar, page tabs) look
different, and the sidebar has room for Levelling or Raids when they return.

## Less at once
- **Hide until needed.** Names (who doesn't have the addon), explanations,
  rank, version, data age and specialisations live in tooltips. Recipe
  tooltips show three of our lines (who can make it, what it needs, a
  Shift hint); the full item, skill-up colours, where to learn and the
  click hints appear while **Shift** is held (`W.RecipeTip`, redrawn on
  `MODIFIER_STATE_CHANGED`).
- **Only what's wrong.** "Needs a look" lists only problems; "All good"
  otherwise.
- **Quiet actions.** Per-row actions (Whisper, Grats, Ask for latest) are
  quiet text links; one filled button per page at most.
- **Options menus.** Rarely changed toggles go in a small ··· menu
  (Roster: Group alts, Copy).

## Colour roles
| Role | Value | Used for | Never for |
|---|---|---|---|
| void | `#000000` at 96 % | window ground | |
| side | `#0C0C0E` | the sidebar | |
| surface / raised / pressed | `#111111` / `#1C1C1C` / `#0A0A0A` | panels, hover and the active sidebar item, press | |
| rule / line / lineStrong | `#161616` / `#2A2A2A` / `#444444` | row rules, panel edges, control borders | boxes around everything |
| text / dim / faint | `#F5F5F5` / `#A6A6A6` / `#707070` | names and numbers / labels and sentences / hints, disabled, missing | |
| **accent** | pink `#F06BB0` (default), gold `#FFC000` or the player's class colour | where you are (sidebar marker and icon, tab underline, focused search), what you picked (selected rows, chips, switches, ticks), the one filled button, one key figure | warnings, decoration |
| onAccent | black or white, whichever has more contrast (`Theme.InkOn`) | text on an accent fill | |
| **spark** | `#FF6A1A` | alerts only: old data, missing enchants, an update, errors, the reminder bars | anything else |
| good / bad | `#4CC38A` / `#E5484D` | synced, online, attuned, ready, shared / not attuned | |

The accent is one colour (v0.6.0; before, gold meant "where you are" and
pink "what you picked", so three bright colours competed). The UI never
names gold or the beard pink directly (`tests/design_spec.lua` enforces
it): `Theme.SetAccent` sets the accent from Settings and repaints
accent-painted textures at once. Class colours and item-quality colours are
the game's and are left alone. No gradients, no glows, no shadows; depth is
a tone step.

## Type
- **Display: Chakra Petch SemiBold** (SIL OFL, bundled), uppercase: the
  page title (20), the sidebar name (15), the big figures (24), headings
  (13) and the small labels over panels (11). Never for names or player
  text (no Cyrillic or CJK).
- **Body: Inter** (SIL OFL, bundled, v0.6.0 default) or the game's **Arial
  Narrow** (Settings → Font, after a reload), via `Media/Fonts.xml` font
  families with Blizzard's Korean, Chinese and Russian fallbacks. Inter is
  wider, so each size is a point smaller (`Theme.INTER_SIZE`: 13 → 12,
  12 → 11, 15 → 14, 20 → 18); nothing under 11.
- WoW has no letter-spacing, so uppercase is kept to short words.

## Space and size
4-point scale: 2, 4, 8, 12, 16, 20, 32. 16 margins. Sidebar items 30, page
tabs 30, list rows 22, card rows 28, setting rows 42 (name and a sentence),
number strip 58, controls 24 (20 inside rows), switches 28 × 16, every
click area at least 24. Numbers right-aligned; a missing value is a dim
dash.

## Components
Sidebar item (icon, label, accent bar when active), page tabs, ghost
button (outline), primary button (accent fill), quiet link (dim, accent on
hover), chip (accent tint when picked), switch (accent when on), slider,
colour swatches, check box, menu, options menu (···), search box, list
(quiet header, sort arrow on the sorted column only), **card** (a small
uppercase label over a flat panel of rows; clickable rows get a chevron),
**number strip**, **settings card** (rows with a name, a sentence and a
control), block (Character sections), sheet. Every list and panel has an
empty sentence that says why and what to do; lists show loading bars;
errors are counted at the bottom of the sidebar.

## Motion
AnimationGroups only; quadratic ease-out. Window in 180 ms (fade + 97 →
100 % scale), out 120 ms; pages appear at once; row hover fades in 80 ms
and vanishes at once; menus 150 ms from their button; sync ring 400 ms, at
most every 8 s. **Reduce motion** turns everything off.

## Textures
`tools/textures.js` draws them; all power-of-two `.tga`: crest 64, the six
sidebar icons 32 (white outlines, tinted), pill 32 (switch track), arrow,
chevron, close, dot, star 16, ring 32.
