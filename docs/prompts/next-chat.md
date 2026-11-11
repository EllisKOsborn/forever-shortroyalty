# Prompt for the next chat (11 Nov 2026)

Paste the text below into a new Claude Code chat on this repository
(branch `claude/short-kings-addon-hlf0t4`).

---

You're continuing work on **Short Royalty**, our guild's WoW Forever addon.
Read `CLAUDE.md` first, especially **"Start here (handover, 11 Nov 2026)"**,
then `PLAN.md` section 13 (levelling tools) and the top of `CHANGELOG.md`.

Where we are:
- v0.4.4 is released (levelling helper, crest icon, tagline removed from
  the game), on top of v0.4.3 (character model).
- Next features, in this order:
  1. a **shopping list**: pick recipes and amounts, get the reagents
     needed and what I already have;
  2. **profit**: crafting cost vs selling price, from Auctionator if it's
     installed, otherwise vendor prices;
  3. a **cheapest levelling route** planner.
- Rule: use **only WoW Forever data**, never Retail or Classic. Take the
  cheapest and most efficient route for Forever. Don't copy other addons'
  code.

How I work:
- I'm not a developer and often on my phone. Keep replies short and plain.
- Push back on bad ideas. Plan with me before big changes.
- Don't release or push to `main` until I say "put it on main".
- Never say something works in game until I've confirmed it.

Start by telling me in a few lines what's waiting on me (from CLAUDE.md),
then propose a short plan for the shopping list before building it.
