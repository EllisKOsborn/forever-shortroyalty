# FojjiCore vs Short Royalty (11 Nov 2026)

The owner asked: review FojjiCore, cross-check it against Short Royalty,
and find areas to improve, mostly professions but broader too.

**Ground rules.** FojjiCore is **All Rights Reserved** (CurseForge project
`fojjicore`, about 6.4 million downloads, supports Forever). Only its public
feature list and changelogs were read (CurseForge description, files
4.0.37, 4.0.3, 4.0.0, 3.8.3, 3.7.5). **No code was read or copied**, and
none may be. Its levelling routes "follow the wow-professions.com Forever
guides", so they're hand-curated. Ours must keep using **Forever's own
data** (owner's rule).

## 1. Professions: side by side

| Feature | FojjiCore | Short Royalty (v0.4.8) | Gap |
|---|---|---|---|
| Recipe browser | Any profession, filter by skill, source, quality; sort by skill, name, rarity | All recipes search (name, group, material), per-profession list, filters: one crafter, favourites, nobody knows | **Filters by skill colour / learn level / source / quality** |
| Where a recipe is learnt | Yes, nearest trainer, vendor map pins | No ("Forever's data doesn't say") | **Biggest gap: see 3.1** |
| Levelling route | Skill to top, cost per step, step cards with trainer/vendor pins, follows a written guide (includes recipes you'll learn) | Route: skill to cap, cheapest per point from TSM/vendor prices, **learned recipes only** | **Can't plan recipes you haven't learned yet** |
| Shopping list | Whole route, tooltip have/need, export to Auctionator, "you craft" for bolts (4.0.37) | Shopping list, have (bags + bank) / still to get, "you make it", Copy, Add all from Route | **Item tooltip line; TSM export; cost intermediates by their reagents** |
| Prices | Own auction scan; prices in tooltips; profit column | TSM or Auctionator API (TSM confirmed in game), remembered vendor prices, Profit view (owner-only) | Players without TSM get vendor prices only |
| Placement | Opens beside the profession window or on its own | Own window only | **Panel docked to the profession window** |
| Skill-up colours | Not described | Forever's ranges, checked against the window (102 match) | Ours is ahead |
| Who in the guild can craft it | **Not described** (no data sharing between players at all) | Crafters tab, item tooltips, coverage board, cooldown board, specialisations | **Ours is ahead: this is our niche** |

## 2. Broader: side by side

| Area | FojjiCore | Short Royalty | Verdict |
|---|---|---|---|
| Data shared between guildmates | None (sends routes to a group, shares BiS setups, map links) | Gear, talents, professions, recipes, cooldowns, attunements, reps, synced over the guild channel | Our core. Keep investing here |
| Dungeon journal, maps, quests | Full journal, hand-drawn maps, dungeon quests, popout bar | None | Don't copy; recommend FojjiCore for this |
| BiS / gear | BiS manager, gear score, upgrades, wishlist, drop alert | Character tab (gear, ilvl, enchant check, 3D model) | Possible small add: guild-wide "who has item X" (we already sync gear) |
| Raids | Timers, packs, attendance, loot history, roles, invites | Raids tab removed (v0.4.1); Overview raid countdown and Onyxia attunement | If raids come back: guild-specific only (attunement + sign-ups), not timers |
| Attunements | Not mentioned | Onyxia attunement in Roster/Character/Overview | Ours is ahead |
| Guild tools | Invite by rank, keyword invites, guild repair, leaderboards for games | Roster with versions, "not seen with the addon", alts grouping, Overview | Different focus |
| Quality-of-life | Auto-sell greys, auto-repair, auto-quest, fast loot, train-all, mute sounds, tooltips with IDs | None | Out of scope (other addons do it) |
| Fun | Chess, Deathroll, Solitaire… | None | Out of scope |

**Takeaway.** FojjiCore is a solo/dungeon toolbox with a strong professions
module, but **nothing is shared between guildmates**. Short Royalty's edge
is the guild: who can craft what, who's attuned, everyone's gear and
cooldowns. Improve professions where Forever's data allows, and keep the
guild angle front and centre.

## 3. Recommended improvements (professions first)

Sizes: S = small, M = medium, L = large.

### 3.1 Where to learn each recipe, from Forever's data (M) **[top pick]**
Checked on 11 Nov in Forever's own tables (wago.tools build 1.60.1.70888):
`ItemSparse` has the recipe items with **RequiredSkill / RequiredSkillRank**
(the skill needed to learn them) and **BuyPrice** (what a vendor charges),
for example "Pattern: Red Woolen Bag" = Tailoring 90, 5s; "Pattern: Azure
Silk Gloves" = Tailoring 120, 10s. Recipes with no recipe item are taught by
a trainer. Plan:
- `tools/recipes.js`: link recipe items to the recipes they teach (via
  `ItemXItemEffect` / `ItemEffect` / `SpellEffect`; to be worked out and
  checked against two sources), and store `source = "trainer"` or
  `{ item, learnAt, buyPrice }`.
- Also probe `C_TradeSkillUI.GetRecipeSourceText(recipeID)`: Blizzard's own
  profession window calls it for unlearned recipes ("Unlearned recipe:
  Trainer / Vendor / Drop …"), and `recipeInfo.disabledReason`. Not in the
  generated docs, so `/sr debug` must show what Forever returns first.
- Shows in recipe tooltips, the Crafters panel and All recipes ("Learn:
  Pattern, Tailoring 90, 5s from a vendor" / "Learn: trainer").
- What we still can't do: map pins and "nearest trainer" (NPC locations
  aren't in the client data). Link to Wowhead for that.

### 3.2 Route planner can include recipes you haven't learned (M, after 3.1)
With learn levels known for recipe items (and trainer ranks if
`GetRecipeSourceText`/`disabledReason` give them), the route can say
"at 135, buy Pattern: Azure Silk Cloak (15s) and craft it", counting the
pattern's price (TSM, or the vendor price) in the cost. Keeps "Forever data
only" and stays our own work, not a copied guide.

### 3.3 Shopping list on item tooltips (S)
Hover a reagent anywhere (bags, auction house) → "Shopping list: need 7,
have 3". We already hook item tooltips for crafters.

### 3.4 Cost intermediates by their reagents (S)
FojjiCore 4.0.37 shows "you craft" for bolts. We say "you make it" but still
price the bolt at auction price. Improve: when you know the recipe, use the
cheaper of buying it and making it, and optionally **expand** it into raw
materials on the shopping list (Bolt of Woolen Cloth → Wool Cloth).

### 3.5 Copy the shopping list for TSM (S)
FojjiCore exports to Auctionator; the owner uses TSM. Add "Copy for TSM"
(the item list in TSM's import format) so a TSM shopping search is one paste.
Check TSM's import format against its docs first (their API site was down
on 11 Nov).

### 3.6 Panel beside the profession window (M)
A small Short Royalty panel docked to the right of Blizzard's profession
window: your next route step, the colour/points-left of the selected recipe,
and who in the guild also makes it. Our own frame anchored to theirs (no
taint: we don't touch Blizzard's frames).

### 3.7 Recipe filters (S)
All recipes / one profession: filter by colour for you (orange/yellow/
green), by source (trainer / recipe item, after 3.1) and by quality; sort by
learn level.

### 3.8 Guild-shared prices (M, owner decision)
Guildmates without TSM only get vendor prices, so their Route costs are
rough. One TSM user could share market prices for profession items over the
guild channel. Trade-offs: more sync traffic, prices must be validated like
every received field, and it touches the owner's wish to keep Profit to
themselves (prices themselves aren't Profit, but they make it easy to work
out). **Ask before building.**

### Broader ideas (later, smaller)
- **"Who has item X"** in the guild (gear is already synced): useful for
  BiS hunting and raid prep. S–M.
- **Train-all / trainer reminder:** "You can learn 3 new recipes at your
  trainer" once 3.1 knows trainer recipes and your skill. S.
- Don't build: dungeon journal, BiS manager, raid timers, QoL automation,
  games. FojjiCore and others already do these well; doing them again would
  dilute the guild focus.

## 4. Suggested order
1. 3.1 recipe sources (with a `/sr debug` probe for `GetRecipeSourceText`)
2. 3.3 tooltip line + 3.4 intermediates + 3.5 TSM copy (small, together)
3. 3.2 route with unlearned recipes
4. 3.6 docked panel, 3.7 filters
5. 3.8 only if the owner wants it

Sources: [FojjiCore on CurseForge](https://www.curseforge.com/wow/addons/fojjicore),
[file 4.0.37](https://www.curseforge.com/wow/addons/fojjicore/files/9558651),
[4.0.3](https://www.curseforge.com/wow/addons/fojjicore/files/9414720),
[4.0.0](https://www.curseforge.com/wow/addons/fojjicore/files/9360495),
[3.8.3](https://www.curseforge.com/wow/addons/fojjicore/files/9294920),
[3.7.5](https://www.curseforge.com/wow/addons/fojjicore/files/9285303).
Forever data: wago.tools `ItemSparse`, `ItemEffect`, `SpellEffect` for build
1.60.1.70888. Blizzard UI source (Gethe/wow-ui-source, `forever` branch):
`Blizzard_ProfessionsRecipeSchematicForm.lua` calls `GetRecipeSourceText`.
