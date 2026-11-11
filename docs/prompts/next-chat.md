# Prompt for the next chat (11 Nov 2026)

Paste the text below into a new Claude Code chat on this repository
(branch `claude/short-kings-addon-hlf0t4`).

---

You're continuing work on **Short Royalty**, our guild's WoW Forever addon.
Read `CLAUDE.md` first, especially **"Start here (handover, 11 Nov 2026)"**,
then `PLAN.md` section 13 (levelling tools) and the top of `CHANGELOG.md`.

Where we are:
- Released: v0.4.3 (character model), v0.4.4 (levelling helper, crest
  icon, no tagline), v0.4.5 (shopping list) and v0.4.6 (**Profit** with
  Auctionator or TSM prices, vendor prices, menu hover fix).
- The guild uses both Auctionator and TSM. Whether the addon reads their
  prices correctly is checked by the `/sr debug` "Prices:" line.
- Next feature: the **cheapest levelling route** planner (PLAN.md section
  13 step 4). It depends on the skill-up colours being right, so check my
  `/sr debug` line "Skill-up colours vs your profession window" first.
- Rule: use **only WoW Forever data**, never Retail or Classic. Take the
  cheapest and most efficient route for Forever. Don't copy other addons'
  code.

How I work:
- I'm not a developer and often on my phone. Keep replies short and plain.
- Push back on bad ideas. Plan with me before big changes.
- Don't release or push to `main` until I say "put it on main".
- Never say something works in game until I've confirmed it.

Start by telling me in a few lines what's waiting on me (from CLAUDE.md),
then propose a short plan for the route planner before building it.
