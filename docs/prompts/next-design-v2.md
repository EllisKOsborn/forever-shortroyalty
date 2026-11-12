# Prompt for the redesign chat (written 11 Nov 2026)

Paste the text below into a new Claude Code chat on this repository
(branch `claude/short-kings-addon-hlf0t4`). Attach screenshots of the
addons you like (see "Before you start") in the same message if you can.

---

You're redesigning the look of **Short Royalty**, our guild's WoW Forever
addon. Read `CLAUDE.md` first (especially "Start here", "The person you're
working with" and "Rules"), then `DESIGN.md`, `UI/Theme.lua`,
`UI/Widgets.lua` and `docs/images/*.png` (the current look).

## Why
The interface has become **cluttered**. Since v0.4.4 a lot was added to
the Professions tab and to tooltips. (Levelling, Route, Shopping list,
Profit and the panel beside the profession window were removed again in
v0.5.6, to be reworked later: design so they can come back without clutter.) I really
like the look of three addons: **FojjiCore**, **EllesmereUI** and
**Polestar**. I want Short Royalty to feel like them: clean, calm,
modern, and easy to use.

## What we know about those three (checked 11 Nov 2026)
- **Polestar** (WoW Forever levelling guides, curseforge.com/wow/addons/polestar,
  source github.com/fitzforge/polestar): **GPL v3**. "Skins, colour schemes,
  your own accent or class colour, and EllesmereUI's look when it is
  installed"; a "standard, compact or transparent window"; "a tidy quest
  log"; Inter as an optional font; one options page (`/polestar options`).
- **EllesmereUI** (curseforge.com/wow/addons/EllesmereUI, source
  github.com/EllesmereGaming/EllesmereUI): **custom licence, all rights
  reserved**. "A polished interface with a cohesive aesthetic", "keep your
  UI clean and lightweight", "minimal layout", pixel-perfect alignment,
  modules you switch on and off.
- **FojjiCore** (curseforge.com/wow/addons/fojjicore): **All Rights
  Reserved**. "one clean addon", "eighteen themes, each with its own
  colours", one menu (`/fc`).
- Their pages describe the look only loosely, so **work from my screenshots**
  (and the screenshots on their CurseForge pages, if you can see them),
  and ask me what I like about each.

## Hard rules
- **Inspiration only.** Don't copy code, textures, icons, fonts or layouts
  pixel for pixel from any of them: EllesmereUI and FojjiCore are all
  rights reserved, and Polestar's GPL would force our MIT addon onto the
  GPL. Our own artwork is drawn by `tools/textures.js`. Fonts we bundle
  must be OFL or similar (we already ship Chakra Petch with `OFL.txt`;
  **Inter** is OFL too, if we want it: bundle its licence and check
  `Media/Fonts.xml` loading like the existing fonts).
- **Plan first and show me before building.** I'm not a developer and
  often on my phone: give me short, plain explanations and **pictures**
  (mock-ups from `preview/index.html` rendered by `docs/mockups/render.js`
  into `docs/images/`, or an Artifact page with the options side by side).
  Let me pick before you change the addon.
- Every visual value lives in `UI/Theme.lua` (`tests/design_spec.lua`
  enforces colours); update `DESIGN.md` with the new rules and why.
- Keep everything that works: features, saved data, sync (no wire
  changes), `/sr` commands.
- Forever is the Mainline (12.x) UI with "secret values": no taint, don't
  restyle Blizzard's frames, `Core/Compat.lua` is the only place for
  client calls.
- Tests (`busted --lua=lua5.1`), `luacheck .`, README/CHANGELOG/TESTING
  and mock-ups updated with every change. Don't push to `main` until I say
  "put it on main". Next version: **v0.6.0**.

## What I'd like out of it
1. **An audit of the clutter** (short, with pictures): every screen, what
   competes for attention, what could hide until needed. Known hot spots:
   - Professions tab: view buttons, toolbars and long status lines.
   - Recipe tooltips: skill-up range, where to learn and crafters can
     stack into many lines.
   - Overview density, the Settings tab (its column is full).
2. **Two or three directions** to choose from, each as mock-ups of the
   Overview, Roster, Professions and Settings, for
   example:
   - **Minimal dark** (EllesmereUI-like): flat panels, hairline borders, one
     accent colour, generous spacing, fewer boxes.
   - **Guide-style** (Polestar-like): a left sidebar for sections instead of
     rows of buttons, standard / compact / transparent window.
   - **Themed** (FojjiCore-like): the same layout with a few colour themes.
3. **Accent colour choice:** guild pink (our crest), gold, or your class
   colour, picked in Settings (and maybe EllesmereUI's accent when it's
   installed, like Polestar does; only if its public API allows it).
4. **Fewer, clearer controls:** a two-level navigation for Professions
   (e.g. Guild / Recipes / Cooldowns, with room for levelling tools later),
   toggles moved into a small options menu, status lines shortened, and
   tooltips trimmed to the 2–3 lines that matter with the rest on Shift.
5. **A tidy Settings page** in sections (Sharing, Display, Professions),
   like Polestar's single options page.
6. Then build the direction I pick, screen by screen, with before/after
   pictures, keeping every feature working.

## Before you start
Ask me for screenshots of the parts of FojjiCore, EllesmereUI and Polestar
I like most (window, menus, lists, tooltips, options page), and which of
our screens bother me most. Don't start building until I've picked a
direction.
