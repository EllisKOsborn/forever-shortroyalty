# Short Royalty: project notes for Claude

Read this first in every session. Keep it current: if you change a decision,
the status or a convention, update this file in the same commit.

## Names (7 Nov 2026)
- The guild and the addon are now **Short Royalty** (was "Short Kings"). Use
  that name everywhere a person can read it: titles, chat, tooltips, docs.
- **Technical names were renamed too (v0.3.1)**, because the addon hadn't
  been rolled out yet (no saved data to lose): folder and TOC
  `ShortRoyalty/ShortRoyalty.toc`, SavedVariables `ShortRoyaltyDB`, addon
  message prefix `ShortRoyalty`, frame names, media paths
  `Interface\AddOns\ShortRoyalty\Media\`, release zip
  `ShortRoyalty-vX.Y.Z-forever.zip` (`.pkgmeta` package-as). Releases up to
  v0.3.0 were `ShortKings`; v0.3.1 can't talk to them (different prefix).
  Still unchanged: the Lua namespace variable `SK` (invisible). The owner
  renamed the repo to `forever-shortroyalty` (11 Nov; GitHub redirects the
  old `forever-shortkings` URL; links updated in v0.4.4).
  **From now on** the folder, SavedVariables and prefix are fixed: changing
  them after rollout would wipe saved data or split the guild.
- Slash commands: `/sr`, `/shortroyalty`, and `/sk` (kept, short).
- The CHANGELOG's past entries and the outside proposal files keep the old
  name (they're history).

## What this is
A World of Warcraft: **Forever** addon for the guild **Short Royalty**
(Alliance, PvE, about 50 members). Members browse each other's gear,
talents, professions, recipes, attunements and reputations in game. Data is
shared only over the guild **addon channel**: no website, no server, no uploads.

## Start here (handover, 12 Nov 2026)
- **v0.5.6 (released 12 Nov on `main`): levelling tools REMOVED** (owner, 12 Nov: "I want to rollback the changes
  for levelling, route, shopping list and profit. They're just not working
  as intended and requires more work from you to get right. So, remove for
  now."). Gone: `Core/Shopping.lua`, `Core/Prices.lua`, `Core/Route.lua`,
  `UI/ProfPanel.lua` (owner chose to remove the panel too), the Professions
  views levelling/route/shopping/profit (`VIEWS` = board, recipes,
  cooldowns; a saved removed view falls back to board), Crafters "+ List",
  Shift-click to add, the item-tooltip shopping line, `/sr profit`,
  `/sr panel`, the Prices/TSM debug lines, Compat price/merchant/item-count/
  ShiftDown/ProfessionsFrame/OnRecipeSelected, their tests and pictures, DB
  defaults (saved `shopping`/`vendorBuy`/`unlocked` are left alone, unused).
  **Kept (owner chose):** skill-up colours (`W.SkillUpText/SkillUpTip`,
  `RecipeDB` ranges, colour check), where to learn (`Core/Learn.lua`,
  `W.LearnLines`, now without a recipe-item price; `SK.Money` in Init for
  trainer costs), the All recipes Show filter, who wears it. `RecipeDB.SkillUps`
  and `Learn.Trainable` stay (tested, unused) for the rework. The notes on
  v0.4.4–v0.5.5 below describe the removed code (git history has it). Lessons
  in PLAN.md section 13. **Don't rebuild them unless the owner asks**; plan
  the rework with them first.
- **Released:** v0.5.5 on `main` (11 Nov: professions upgrade from PLAN.md
  section 14: where to learn, shopping upgrades, route with recipes to learn,
  panel beside the profession window, filters, who wears it; the unreleased
  steps v0.5.0–v0.5.3 shipped inside it, so code comments say v0.5.0–v0.5.5;
  next release is v0.5.6), after v0.4.8 (11 Nov: cheapest levelling route,
  open to everyone), after v0.4.7 (11 Nov: colour-check fix, Profit hidden
  and owner-only), after v0.4.6 (11 Nov: Profit, menu hover fix), after
  v0.4.5 (11 Nov: shopping list) and v0.4.4
  (11 Nov: levelling helper, crest icon, tagline removed everywhere in game,
  links to the renamed repo) and v0.4.3 (11 Nov, character model, released
  from another chat). **Two chats
  have pushed to `main`:** always `git fetch origin main` and merge before
  pushing to it, and check the newest CHANGELOG version first. Releasing =
  owner says "put it on main": merge `main`, date the CHANGELOG heading,
  bump the README badge, push `main` (automatic release).
- v0.4.6 = **Profit** (step 3) and the menu hover fix (`W.Menu` rows used a
  solid texture on the HIGHLIGHT layer, which draws over text; now
  BACKGROUND, shown on enter). TESTING 155–160. **Get the owner's `/sr debug`
  "Prices:" line** (TESTING 156): the Auctionator/TSM calls are unverified.
- (Removed in v0.5.6, history:) **Profit was hidden and owner-only (owner, 11 Nov: "I don't want others
  seeing this just yet whilst I make money"; "sr profit is only for me")**:
  the Profit view only shows after `/sr profit` (`SK.DB.unlocked.profit`,
  account-wide, toggles; not in `/sr` help), and only on the owner's account
  (`Prices.OWNERS` = their main's GUID; `Prices.IsOwnerAccount` also accepts
  any character in `SK.DB.account`, so alts count). For anyone else
  `/sr profit` prints the help like any unknown command, and a hand-edited
  `unlocked.profit` does nothing. The code is public, so it's hidden, not
  secret (the owner was told). Ask whether the route planner goes behind
  it too (asked 11 Nov, answer unclear). The
  README doesn't list it (an owner-approved exception to "What's inside lists
  everything"); don't advertise it in README/CHANGELOG until the owner says.
  Prices themselves are local and never synced. The owner has **TSM only**
  (no Auctionator).
- v0.4.8 = **cheapest levelling route** (step 4, the
  last of PLAN.md section 13), **open to everyone** (owner, 11 Nov). TESTING
  163–166. `Core/Route.lua`: `Route.Chance(range, skill)` = 1 below yellow,
  else (grey - skill) / (grey - yellow) (the original game's rule, an
  estimate for Forever), `Route.Gain` (orange gives `ups`), pure
  `Route.Plan(recipes, from, to)` (per point the lowest net cost per
  expected point; priced before unpriced; consecutive points merge into
  steps; crafts rounded up per step; a last `{ stuck, from }` step when
  nothing gives points), `Route.Recipes` (learned recipes with a range;
  net = cost minus resale from `Prices.Recipe`), `Route.AddToShopping`.
  UI: Professions view `route` (shares `settings.levelProf`; target = the
  profession's current max; `ROUTE_COLUMNS`; "earn …" when net < 0).
  Tests: `tests/route_spec.lua`. The README pictures no longer show the
  Profit chip (owner-only); `docs/images/profit.png` was removed.
- **v0.5.0 (in v0.5.5) where to learn** (PLAN.md 14). Data:
  `Data/Recipes.lua` `SK.Data.RECIPE_ITEMS[recipe] = { item, learnAt }`
  (1682; link = `ItemXItemEffect` → `ItemEffect` with **TriggerType 6
  ("learn") whose SpellID is the recipe itself**; kept only if in
  `ItemSparse`, named, not "OLD/TEST/…", and `RequiredSkill` = the recipe's
  profession; learnAt = `RequiredSkillRank`; lowest learnAt wins). Spot
  check: trainer recipes (Bolt of Linen, Azure Silk Hood…) have none;
  Pattern: Red Woolen Bag 5772 → 6688 @90. `ItemSparse.BuyPrice` is NOT
  used (every item has one). `Core/Learn.lua`: trainers remembered on
  TRAINER_SHOW/UPDATE (`Compat.TrainerServices`: GetNumTrainerServices,
  GetTrainerServiceInfo, …SkillReq, …Cost; matched by lower-case spell
  name within the trainer's profession, recipes with a recipe item
  excluded, ambiguous names skipped) → `SK.DB.trainer`; the game's text
  (`Compat.RecipeSourceText` = probed `C_TradeSkillUI.GetRecipeSourceText`,
  plus `disabledReason`) stored during scans → `SK.DB.recipeSource`;
  `Learn.Lines` (pure wording), `W.LearnLines` in every recipe tooltip
  (`W.SkillUpTip`) and the Crafters panel; Levelling "N to learn at your
  trainer" (`Learn.Trainable`). `/sr debug` "Where to learn" and
  "Trainers" lines (TESTING 167–170).
- **v0.5.1 (in v0.5.5) shopping upgrades.** `Prices.Make(itemID)`
  (reagent cost per item via a recipe you know, depth ≤ 3) and `Prices.Buy`
  now picks vendor / ah / **make** (`Prof.ViaText`); `Shopping.Expand`
  (raw materials, `settings.shopRaw`, rows get `make`, `Shop.Cost` skips
  them), `Shopping.ItemNeed` (cached, dirty on SHOPPING_CHANGED/BAG/BANK) →
  `Tooltip.ShoppingText` on item tooltips (shown even with crafter lines
  off), `Shopping.TSMList` ("i:1,i:2"; **TSM accepting it is unverified**,
  TESTING 174). Tests: `tests/shopping2_spec.lua`.
- **v0.5.2 (in v0.5.5) route with recipes to learn.**
  `Route.HowToLearn` (recipe item with a price via `Prices.Buy`, or a
  remembered trainer; cheaper wins), `Route.Recipes(skillLine, known,
  toLearn)`, `Route.Plan` honours `learnAt`, adds `learnCost /
  (min(grey, to) - skill)` per point until paid, puts `learn` on the first
  step and the cost once in the total. `settings.routeLearn` (default on),
  chip "Recipes to learn". `Prices.Batch(fn, ...)` caches `Buy` per item
  during a refresh (Route, Profit). TESTING 175–177.
- **v0.5.3 (in v0.5.5) panel + filters.** `UI/ProfPanel.lua`: own
  frame `ShortRoyaltyProfPanel` (strata HIGH) anchored TOPLEFT to
  `ProfessionsFrame` TOPRIGHT (`Compat.ProfessionsFrame` = rawget global;
  Blizzard_Professions loads on demand) on TRADE_SKILL_SHOW (+0.2 s, own
  trade skill only), hidden on TRADE_SKILL_CLOSE; selected recipe via
  `Compat.OnRecipeSelected` = `EventRegistry:RegisterCallback(
  "ProfessionsRecipeListMixin.Event.OnRecipeSelected")` (fired in
  Blizzard_ProfessionsRecipeList.lua with recipeInfo). Content: next step
  from `Route.ForProfession` (new; also used by RefreshRoute), `W.SkillUpText`,
  `W.LearnLines`, guild crafters, profit line only when unlocked; pure
  `ProfPanel.Lines`. `settings.profPanel`, `/sr panel` (in help), Hide
  button. Filters: All recipes "Show" menu (`Prof.SHOW_ITEMS`, pure
  `Prof.FilterRecipes`). Mock-up `docs/mockups/panel.html` →
  `docs/images/panel.png` (render.js PAGES). Tests: `tests/panel_spec.lua`.
  TESTING 178–181. **Unverified in game:** the anchor and the EventRegistry
  event.
- **v0.5.5 who wears it.** `Core/GearIndex.lua`: pure
  `GI.Build(profiles)` (item IDs from shared gear links, once per person),
  `GI.Wearers` (online first), `GI.Text`, `GI.Search` (loaded names, ≥ 3
  letters); dirty on PROFILE_UPDATED/SELF_UPDATED/ROSTER_UPDATED. Item
  tooltips "Guild: worn by …" (same setting as crafters, label renamed);
  `/sr who <link|id|name>` (`Commands.Who`, in help). Tests:
  `tests/gear_index_spec.lua`. TESTING 182–183.
- **Guild-shared prices: dropped** (owner, 11 Nov: "I don't think price
  sharing is what we should add at all"). Don't propose it again unless asked.
- **Redesign (owner, 11 Nov: "the interface is now very cluttered"; likes
  FojjiCore, EllesmereUI and Polestar):** to be done in a separate chat from
  **`docs/prompts/next-design-v2.md`** (v0.6.0). Licences: Polestar GPL v3
  (github.com/fitzforge/polestar), EllesmereUI custom all rights reserved,
  FojjiCore All Rights Reserved: **inspiration only**, never code/art.
- **Next:** v0.5.6 is released; ask the owner what's next (next version
  v0.5.7, or v0.6.0 for the redesign). Still useful from v0.5.5: TESTING 167–169, 181–185.
- **Earlier:** the levelling tools (PLAN.md section 13) are all
  built. **FojjiCore review (11 Nov): `docs/FOJJICORE-REVIEW.md`** (All
  Rights Reserved: features only, never code). Top pick: recipe sources from
  Forever's data (`ItemSparse` RequiredSkill/RequiredSkillRank/BuyPrice for
  recipe items; probe `C_TradeSkillUI.GetRecipeSourceText`). **Owner: "add
  all of this in"** → plan in **PLAN.md section 14** (v0.5.0 recipe sources
  incl. trainers remembered at `TRAINER_SHOW` via `GetTrainerServiceInfo/
  SkillReq/Cost`, v0.5.1 shopping upgrades, v0.5.2 route with unlearned
  recipes, v0.5.3 docked panel + filters, v0.5.4 guild prices after owner
  decisions, v0.5.5 who-has-item). **Forever data only** (wago.tools product `wowf`), never
  Retail/Classic. Don't copy Profession Master (All Rights Reserved).
- **Skill-up colours checked 11 Nov**: 102 match; the 13 differences were all
  a skill-0 read (fixed in v0.4.7, released 11 Nov; TESTING 161). The
  route planner can build on the colours; confirm 0 differ after v0.4.7.
- **Open questions for the owner:** see "Waiting on the user" below.
- Handover prompt used to start the next chat: `docs/prompts/next-chat.md`.

## The person you're working with
- **Not a developer**, often on their **phone**. Explain steps in plain
  language, keep replies short, and put long material in repo files.
- Wants you to **push back** on bad ideas and to **plan first** for big changes.
- Relays questions and requests from guild members.
- **Never claim anything works in game** until they confirm it. Everything so
  far is tested only against a stubbed WoW API.

## Platform facts (verified, keep using the same sources)
- Forever client **1.60.1** (live build **70790** at launch; the API source
  matches it), Mainline (12.x) UI with Midnight "secret value"
  restrictions. TOC game type `camelot` (alias `forever`).
- TOC **`## Interface: 16001`**: **confirmed in game** on 5 Nov 2026.
  Single TOC with no suffix. The BigWigs packager detects it as Forever.
- **Confirmed in game on 5 Nov 2026** (owner's first `/sr debug`):
  - `SendAddonMessage(..., "GUILD")` returns **0 (Success)** and arrives,
    even though `C_ChatInfo.AreOutgoingAddonChatMessagesRestricted()` returns
    **true**. That flag only gates Blizzard's esports CooldownBroadcaster.
    **Never use it to block sending**: trust the send result (v0.2.5).
  - Our AceComm callback gets **`true`/`false`** ("did it send"), not
    Blizzard's numeric `SendAddonMessageResult`: ChatThrottleLib passes
    `(arg, didSend, code)` and AceComm forwards only `didSend`.
    `Sync.SendOutcome` handles both (v0.2.6 fix: v0.2.5 counted `true` as an error).
  - Addon-message sender = **"First Surname"** with a space, exactly like the
    roster name. `UnitFullName("player")` returns the surname as the *realm*
    (`"Pocus", "Hocus"`). `GetGuildInfo`'s realm is an internal name
    (`CAMWOWEU5Realm3PvE`).
  - Player GUIDs (`Player-6937-…`) stay the same between logins.
  - The real release zip is `ShortRoyalty-vX.Y.Z-forever.zip`. The owner first
    installed GitHub's "Source code (zip)" by mistake (version "dev",
    LibDataBroker and LibDBIcon missing).
  - `C_QuestLog.GetTitleForQuestID` returns nil for uncached quests (it isn't
    proof that a quest is missing). Item 16309 (Drakefire Amulet) resolves.
  - The guild is called **"Short Royalty"** (renamed 7 Nov 2026; it was
    "Sweaty Pumpers" at launch because "Short Kings" was taken). Data is keyed
    per guild name; `DBM.AdoptRenamedGuild` carries a renamed guild's data
    over to the new key (v0.3.1).
- **Source of truth for APIs:** Blizzard's UI source, `forever` branch of
  Gethe/wow-ui-source. Sparse-clone it and grep
  `Interface/AddOns/Blizzard_APIDocumentationGenerated/` plus the
  `*/Camelot/*` UI files:
  ```sh
  git clone --depth 1 --branch forever --filter=blob:none --sparse https://github.com/Gethe/wow-ui-source.git src
  cd src && git sparse-checkout set Interface/AddOns/Blizzard_APIDocumentationGenerated
  ```
  warcraft.wiki.gg's 1.60.1 API-change page was **wrong** about some
  removals (e.g. `C_SkillInfo.GetSkillLineInfo` still exists). Trust the
  source, not the wiki.
- Verified facts:
  - Item/spell names: `C_Item.GetItemNameByID`, `C_Item.RequestLoadItemDataByID`
    (event `ITEM_DATA_LOAD_RESULT` itemID, success), `C_Spell.GetSpellName`,
    `C_Spell.RequestLoadSpellData` (`SPELL_DATA_LOAD_RESULT`). Quality:
    `C_Item.GetItemQualityByID` + `C_Item.GetItemQualityColor`.
  - Item tooltips: `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, fn)`
    (`Item` = 0); `data.id` is the item ID.
  - Chat box: `ChatFrameUtil.OpenChat(text)` (edit box parses a leading
    `/g `); whisper `ChatFrameUtil.SendTell(name)` (both in
    `Blizzard_ChatFrameBase/Shared/ChatFrameUtil.lua`). `ChatFrame_OpenChat`
    is only a fallback.
  - Professions use `C_TradeSkillUI`; the Classic `GetTradeSkillInfo` and
    `GetCraftInfo` are gone.
  - Talents are `C_Traits` trees.
  - **Confirmed in game 5 Nov (owner's v0.2.7 `/sr debug`, level 1, no
    profession yet):** every profession API we probe exists on the client
    (`GetRecipeSchematic`, `GetCategoryInfo`, `GetCategories`,
    `GetShowLearned`/`GetShowUnlearned`, `GetAllRecipeIDs`,
    `GetFilteredRecipeIDs`, `GetRecipeCooldown`, `C_SpellBook.IsSpellKnown`,
    `IsPlayerSpell`); only the Classic `GetNumTalentTabs`, `GetTalentTabInfo`,
    `GetNumTradeSkills`, `GetTradeSkillInfo`, `GetCraftInfo`, `GetFactionInfo`
    are missing. The window's filter defaults to **show unlearned = no**. All
    10 specialisation spell IDs resolve to the expected names → `status = "ok"`.
    Only 1 of 19 members had the addon, so no sync between players has
    happened yet.
  - **Confirmed in game 6 Nov (second v0.2.7 report, Herbalism 4/75):**
    - The window **lists unlearned recipes** (`GetAllRecipeIDs`: 0 learned,
      3 listed) even with "show unlearned" off, so "Nobody knows" works.
    - **Gathering professions have recipes in Forever**: Herbalism has a
      category **"Camping"** (id 2716, parent "Herbalism"): Seed Hybridizer
      (recipe 1263070 → item 279947), Greenhouse, Incense Candle. So never
      assume `Data.GATHERING` means "no recipes".
    - `GetCategoryInfo` works (name + parent).
    - `GetRecipeSchematic` returns reagents **for an unlearned recipe with the
      window open** (Seed Hybridizer: 4× 13465, 1× 8925, 2× 14047).
    - The display font was reported **"NO, using the game font"** (first
      SetFont with the bundled .ttf failed). v0.3.0 preloads it as XML Font
      objects (`ShortRoyaltyDisplay13/20/24` in `Media/Fonts.xml`) and checks
      `GetFont()`; unconfirmed whether that fixes it.
    - Still unknown: reagents with the window **closed**, reagents for a
      learned recipe, `IsSpellKnown` for a spec owner. Drakefire Amulet name
      was nil in both reports (uncached; it resolved on 5 Nov).
  - Profession APIs (from the source, 5 Nov):
    `C_TradeSkillUI.GetRecipeSchematic(recipeSpellID, isRecraft)` →
    `reagentSlotSchematics[i].reagents[j].itemID|currencyID`,
    `.quantityRequired`, `.required`; `GetShowLearned`/`GetShowUnlearned`;
    `GetRecipeInfo` has `categoryID`. `GetCategoryInfo`/`GetCategories`,
    `GetAllRecipeIDs`, `GetFilteredRecipeIDs` are **not** in the generated
    docs (Blizzard's Forever UI calls `GetCategoryInfo`), so probe them.
    Known spells: `C_SpellBook.IsSpellKnown(spellID)` (global
    `IsPlayerSpell` not in the docs, but present in game). Specialisation
    spell IDs (`Data/Professions.lua` `SPECIALISATIONS`) match on wowhead
    classic, classicdb.ch and the client's own names.
  - The guild roster is `C_Club` plus legacy `GetGuildRosterInfo`.
  - `C_Calendar` exists, but `AddEvent` is restricted.
  - `SendChatMessage` is **restricted** (only send on a button press, or
    prefill the chat box instead).
  - Whisper with `ChatFrameUtil.SendTell` (`ChatFrame_SendTell` is gone).
  - `TooltipDataProcessor` exists.
  - `C_Spell.GetSpellCooldown` returns a table.
  - Trial accounts can't send addon messages.
- **Confirmed in game 7 Nov (owner's v0.3.6 `/sr debug`, build 70862):** no
  Lua errors; own profile passes the safety check; a guildmate's message
  arrived ("Slay Qween"). The game shared Battle.net accounts for only
  **3 of 27** members (most likely the owner's Battle.net friends), one
  reason the alt guessing was dropped in v0.4.0. "Sent 0" in that report = taken in the
  first 10–20 s after login (the first HI waits that long); recheck if it
  stays 0.
- **Confirmed in game 10 Nov (owner's v0.4.1 `/sr debug`, level 34, 39
  members, 24 with data, 16 crafters, 322 recipes):**
  - **Sync between players works** (sent 72, received 230, accepted 38; 265
    numbered pieces received, 1 message given up on: likely a sender's
    lockdown retry, which re-sends under a new id). First real confirmation
    of protocol 2.
  - The display font loads ("7 texts ok, 0 failed").
  - Alts link themselves ("Family: 1").
  - `IsInGuild()`/`GetGuildInfo` can be **momentarily empty** mid-session:
    `SK.guildKey` went nil and SQ handling crashed (fixed v0.4.2:
    `Identity.NO_GUILD_AFTER` 15 s, `Sync:IsPaused` "no guild", guard in
    `Sync:Handle`).
  - Tailoring/First Aid went from "scanned yes" (7 Nov) to "scanned NO":
    most likely an **incomplete profession read** dropped them (or the
    owner ran TESTING 116's reset). Fixed v0.4.2 with `SK.DB.scanKeep`.
  - "Send errors: 9, last: not sent": whispers to players who had logged off
    (`Enum.SendAddonMessageResult.TargetOffline` = 12; also NotInGuild 10,
    ChannelThrottle 8). v0.4.2 sends each wire straight to
    `ChatThrottleLib:SendAddonMessage` to get the code (callback
    `(arg, didSend, code)`); outcome "offline" isn't an error.
- **Confirmed in game 11 Nov (owner's v0.4.6 `/sr debug`, build 70888,
  level 39, 39 members, 25 with data):**
  - **TSM's API works**: `TSM_API.GetCustomPriceValue("DBMarket", "i:2589")`
    = 26c, `DBMinBuyout` = 19c (Linen Cloth). Profit uses TSM.
  - **Auctionator API: "no"** (`Auctionator.API.v1.GetAuctionPriceByItemID`
    not found). Unknown yet whether Auctionator is installed on that
    character; asked the owner.
  - **Vendor price learning works**: 31 prices remembered from merchants.
    `C_Item.GetItemInfo` sell price works (Linen Cloth 13c).
  - Send errors 0 (v0.4.2 fix holds); no Lua errors; all 5 professions
    "scanned yes".
  - **Skill-up colours: 102 match, 13 differ**, and every example was
    "at skill 0" (Cooking recipes 6412, 6416, 7753, 7827, 2538): the scan
    read the skill as 0 just after the window opened. So the colour rule
    (yellow at low, green at floor((low+high)/2), grey at high) matched
    everything compared at a real skill. v0.4.7 skips skill 0 in the check
    and restarts the count (`RecipeDB.CHECK_VERSION` 2). Saving a scan
    already ignored rank 0 (`Profile:SetScan`, `SetScanRank`).
  - `relativeDifficulty` (Nilable in the docs) **is filled in Forever**.
- **Confirmed in game 12 Nov (owner's v0.5.5 `/sr debug`, build 70888,
  Tailoring 124/150, 49 of 471 learned):**
  - **Skill-up colours: 245 match, 0 differ**: the colour rule holds.
  - **`C_TradeSkillUI.GetRecipeSourceText` gives nothing** (0 of 422
    unlearned recipes after a Tailoring scan) and `disabledReason` is empty
    too. "Where to learn" relies on Forever's data and remembered trainers.
  - `GetBaseProfessionInfo().professionName` is **empty** ("Last scan: ,");
    the scan now falls back to the profile's profession name (v0.5.6).
  - The window also lists the "SEASON OF DISCOVERY" category (54 recipes),
    which our data leaves out on purpose.
  - 50 vendor prices remembered; TSM works; no Lua errors; send errors 0.
- **Realmless:** characters have two-part names that are unique per region.
  Key everything by **player GUID**. The `sender` format in addon messages is
  unconfirmed, so `Core/Identity.lua` matches it several ways.
- Forever launches **4 Nov 2026** (written 2 Nov; update once the live client
  has been checked). Raids open 9 Dec: Barrow Deeps (10) and Hyjal Summit (20)
  need **no attunement**; Onyxia's Lair (40) needs the **Drakefire Amulet
  (item 16309) in your bags**, not equipped (Blizzard's raid overview, checked
  2 Nov). Molten Core, BWL and Naxxramas aren't in the first wave.

## Rules
- **`Core/Compat.lua` is the only file that calls client-specific APIs.**
  Detect each API at runtime and degrade gracefully.
- **Never guess IDs** (quests, factions, spells). Verify them against two
  sources or mark them `status = "todo"` in `Data/*.lua`.
- **Don't copy code** from other guild-sync addons (Perpetua has no licence).
  Reading their feature lists is fine. Credit sources in README.
- Pause sync in combat, in every instance type (party/raid/pvp/arena/scenario)
  and during `C_ChatInfo.InChatMessagingLockdown()`. All sends go through
  ChatThrottleLib (directly since v0.4.2, `Sync.transport`, same wire format
  as AceComm single-part; receiving stays on AceComm).
- **Security** (`docs/SECURITY-REVIEW.md`, 3 Nov): everything received is
  untrusted. New profile fields need a check in `Merge.FIELDS`; never run,
  link or chat received text unchecked; keep `tests/security_spec.lua` green.
  Loose (first-name) sender matches count only on GUILD, or by whisper from a
  sender confirmed on GUILD this session. GitHub Actions are pinned to commit
  SHAs (update the SHA and the `# vN` comment together).
- **Privacy:** notes and officer notes are never synced. Our own characters
  keep a **full** profile in `ShortRoyaltyDB.own[guid]`, and only the
  **public** copy (`Profile.Public`, which respects the share toggles) goes
  into `guild.profiles` and onto the wire.
- Every change ships with:
  - busted tests;
  - a clean `luacheck .`;
  - updates to `README.md` ("What's inside" lists **everything**), `CHANGELOG.md` and `TESTING.md`;
  - updated mockups in `docs/mockups/` when the UI changes (`node docs/mockups/render.js <font>`).
- Commit as you go. Never create a PR unless asked. Push to your designated branch.
- **`main`** holds the released state (created 2 Nov 2026 with v0.2.0;
  v0.2.2 pushed 2 Nov). Push to `main` only when the user asks; the README's
  test badge tracks it.
- **Releases are automatic since v0.3.5:** every push to `main` runs
  `.github/workflows/release.yml`; if CHANGELOG.md's top heading is a dated
  version (`## v0.3.6 (8 Nov 2026)`) with no GitHub release yet, it tags that
  commit and starts itself again on the tag (`gh workflow run --ref <tag>`;
  the packager skips a tagged branch push, and GITHUB_TOKEN tag pushes don't
  start workflows, but workflow_dispatch does), which builds the zip, GitHub
  Release and CurseForge upload. A heading containing "not released" (keep
  using `## vX.Y.Z (not released yet)` on the working branch) or an existing
  release does nothing. So **before pushing to `main`, date the
  top CHANGELOG heading**, bump the README badge, and never push a dated
  heading to `main` that the owner hasn't asked to release. The owner no
  longer publishes on the website. Earlier: pushing a tag `vX.Y.Z` on `main` runs `.github/workflows/release.yml`
  (BigWigs packager): it builds `ShortRoyalty-vX.Y.Z.zip` and a GitHub Release
  whose notes come from CHANGELOG.md (`.pkgmeta` manual-changelog). First
  release: **v0.2.2** (2 Nov 2026, the launch build); **v0.2.3** (3 Nov, the new
  look); **v0.2.4** (3 Nov, tagline "Height is not a stat."); **v0.2.5** (5 Nov,
  launch-day fixes: sync no longer blocked by the misleading flag, enchant
  check at max level, plus the security fixes); **v0.2.6** (5 Nov, hotfix: successful
  sends were counted as errors; the owner publishes it on the website because
  tag pushes from cloud sessions drop); **v0.2.7** (5 Nov, `/sr debug`
  profession checks only, for v0.3 Step 1); **v0.3.0** (6 Nov, the Professions
  tab, reagents, favourites, specialisations, reminders); **v0.3.1** (7 Nov,
  renamed to Short Royalty, technical names included; first zip named
  `ShortRoyalty-…`); **v0.3.2** (7 Nov, every recipe from wago.tools
  data, search, Wowhead links, Getting started; first release for CurseForge,
  project **1788068**); **v0.3.3** (7 Nov, sync fix: our own numbered
  pieces, protocol 2; can't talk to v0.3.2 or earlier); **v0.3.4** (7 Nov,
  crafter's recipes in Professions, who has the addon on the Overview, orange
  profession reminder bar with an Open button); **v0.3.5** (7 Nov, full
  "doesn't have the addon" list on hover; first automatic release); **v0.3.6**
  (7 Nov, old versions / alts / never-online-together no longer listed as
  "doesn't have it"); **v0.4.0** (7 Nov, Raids tab read-only, simpler "who has
  the addon", Alt rank left out of the Overview, alt guessing removed);
  **v0.4.1** (8 Nov, Raids tab removed again: "keep it as crafting and
  professions for now"); **v0.4.2** (10 Nov, fixes from the first big
  in-game report: guild-nil error, lost profession scans, false send errors); **v0.4.3** (11 Nov, character model on the
  Character tab; the CI test build now uploads); **v0.4.4** (11 Nov,
  levelling helper, crest icon, no tagline in game); **v0.4.5** (11 Nov,
  shopping list); **v0.4.6** (11 Nov, Profit with Auctionator/TSM prices,
  menu hover fix); **v0.4.7** (11 Nov, colour-check fix; Profit hidden,
  owner-only); **v0.4.8** (11 Nov, cheapest levelling route); **v0.5.5**
  (11 Nov, professions upgrade); **v0.5.6** (12 Nov, levelling tools removed). Tag only when
  the user asks.

## Layout
```
ShortRoyalty.toc  embeds.xml  Commands.lua (/sk, /sr debug report)
Core/     Init (events, timers, modules), Log (+ error capture: SK:Safe,
          SK:RecordError), Compat, DB (SavedVariables, pruning), Identity
          (roster, sender→GUID, Status dots, GUID-stability check), Alts
          (mutual-link groups), CraftIndex (recipe/item → crafters, async
          names), Favourites (local stars), Reagents (GetRecipeSchematic
          cache, local), ProfBoard (numbers for the Professions tab),
          RecipeDB (every recipe + search, skill-up colours), Learn
          (where to learn: recipe items, trainers), GearIndex (who wears
          it), Onboarding (Getting started),
          Export (plain text for Copy), Feed (local milestones,
          never synced), Overview (numbers for the Overview tab)
Data/     Professions, Recipes (GENERATED by tools/recipes.js), Attunements
          (quest IDs), Factions, Enchants
Collect/  Character, Talents, Professions (recipe scan), Reputation,
          Attunements, Profile (full/public copies, cooldowns, main)
Sync/     Codec (LibSerialize stable → LibDeflate), Merge (rules), Sync (protocol)
UI/       Theme (EVERY colour/font/size/spacing/motion value), Motion
          (AnimationGroups, Reduce motion), Widgets (Button, CloseButton,
          Tab, Chip, Check, Menu, SearchBox, List, TextPanel, Block, Sheet),
          MainFrame, OverviewTab (first tab, three spec-sheet columns),
          RosterTab (+ raid filter, Oldest first), CharacterTab (+ Ask for
          latest), CraftersTab (+ reagents, Favourites chip), ProfessionsTab
          (board / one profession / cooldowns), SettingsTab, DebugWindow,
          Minimap, Tooltip
Media/    Fonts.xml (Arial Narrow families + CJK fallback), Fonts/ (Chakra
          Petch, OFL), Textures/ (crest, arrow, close, dot, ring, star .tga)
preview/  browser mock-up of every window (theme.css/js generated)
tools/    textures.js (draws Media/Textures), preview-tokens.js, recipes.js
          (Data/Recipes.lua from wago.tools)
Libs/     vendored Ace3 bits, LibSerialize, LibDeflate; LDB + LibDBIcon via .pkgmeta
tests/    busted specs; tests/helpers/wow.lua is the stubbed WoW API
docs/     FEATURE-REVIEW.md, SECURITY-REVIEW.md, mockups/render.js, images/ (+ before/), prompts/,
          design/ (Lamborghini reference); DESIGN.md + PRODUCT.md at the root
```

## Sync protocol (prefix `ShortRoyalty`, protocol 2)

**Transport (protocol 2, v0.3.3):** every encoded message goes out through
`Sync/Frames.lua`: up to 250 bytes as one message (`"\030" .. data`), longer
ones as numbered pieces (`"\031" .. id(2) .. seq .. total .. data`, 240
data bytes each), so **AceComm never splits anything**. The receiver rebuilds
by number in any order, gives up after 120 s without a new piece (reported in
/sr debug as "Last incomplete message"), keeps at most 4 unfinished messages
per sender, and drops strangers before storing pieces. The 60-per-minute
limit counts whole messages; raw pieces have their own cap (1500).
Why: on 7 Nov the first two-player test (owner + Aura, different server IDs
6937/6855) lost every profile to "bad compression", although in-game tests
showed single addon messages arrive intact (all byte values, 255 bytes,
GUILD and WHISPER, 20 in a row in order). AceComm/ChatThrottleLib reassemble
correctly in simulation, so the multi-part messages broke in transit between
players. **Don't go back to AceComm multi-part messages.**
| Msg | Channel | Purpose |
|---|---|---|
| `HI` | GUILD | Own account's characters `{g, u, h}`. Sent at login, every 10 min, and 30 s after changes (debounced) |
| `RQ` | WHISPER | Request profiles. Also "Ask for latest" (max 1 per target per 30 s); an RQ for the logged-in character rebuilds it first (not in combat, max every 10 s) |
| `PR` | WHISPER | One profile per message |
| `SQ` | GUILD | Once per session: what I hold, and (`a`, v0.3.6) who I know runs the addon |
| `SO` | GUILD | Backfill offer, random 2–8 s delay, suppressed if someone else offers first |

Merge rules (`Sync/Merge.lua`, tested):
- The character must be a guild member.
- Timestamps more than 5 min in the future are rejected.
- The hash must match the content.
- Our own characters are never overwritten.
- An owner copy beats any relay copy.
- A relay copy is accepted only if strictly newer.

Alts link only when **both** profiles list each other in `family`.

Input limits (v0.2.1): `Codec.MAX_ENCODED` 32 KB (worst-case profile ~11 KB),
max 60 incoming messages per sender per minute (`Sync.RATE_MAX`), and
oversized outgoing messages are recorded as errors, not sent. v0.2.5 adds
`Codec.MAX_DECODED` 256 KB, `Merge.LIMITS` per field, only GUILD/WHISPER
accepted, strangers dropped before decoding, and `Sync.MAX_STRIKES` (3 bad
messages → sender ignored for the session).

## Dev environment notes (cloud sessions)
- Lua 5.1 tooling: `apt-get install lua5.1 liblua5.1-0-dev luarocks`, then
  `luarocks --lua-version=5.1 install busted luacheck`. GitHub *archive*
  downloads are blocked by the proxy: when a rock fails, `git clone` its
  repo at the tag and run `luarocks make <rockspec>` (lua-term and
  mediator_lua needed this).
- Run `busted --lua=lua5.1` and `luacheck .`. CI (`.github/workflows/ci.yml`)
  runs both and builds a test zip artifact.
  The artifact (**ShortRoyalty-test-build**, bottom of each Tests run in the
  Actions tab) needs `include-hidden-files: true` because it's under
  `.release/`; without it nothing was uploaded (fixed 11 Nov). This is how the
  owner tests a branch without a release. On a **release commit** (already tagged by
  release.yml) the packager refuses to build ("Found future tag"), so the
  test-build job skips itself there (`git tag --points-at HEAD`); with
  `if-no-files-found: error` it would otherwise fail (it did on v0.4.3).
- Mockups: Playwright and Chromium are preinstalled. The stand-in font is
  Marcellus from fonts.gstatic.com (don't commit the font).

## Status (history, newest entries further down; current state: "Start here")
- **v0.3.1 (Short Royalty rename)** on `main` 7 Nov (the owner publishes the
  release): new name everywhere, technical names too (folder, SavedVariables,
  prefix, zip `ShortRoyalty-vX.Y.Z-forever.zip`), `DBM.AdoptRenamedGuild`
  (saved guild data follows future renames), `/sr` + `/shortroyalty` + `/sk`.
- v0.3.0 Professions released 6 Nov (see CHANGELOG).
- **v0.3.2** (7 Nov): every recipe, search, Getting started, CurseForge
  (project 1788068). Two Claude sessions worked on `main` the same morning:
  always `git fetch origin main` and merge before pushing to `main`.
- **v0.2.5 released 5 Nov**: the first build after an in-game test (owner,
  solo: loads, GUID stable, interface 16001, a test send worked). It
  includes the security fixes from `docs/SECURITY-REVIEW.md`. Sync between
  two players has **not** been tested yet (v0.2.2–v0.2.4 never sent
  anything because of the flag bug).
  v0.2.2 = the Overview dashboard (owner asked for it before the test gate).
  (`docs/prompts/next-v0.1.2-v0.2.md` is done; v0.2.1 = launch readiness
  from `docs/PLAN-REVIEW.md`.)
- Roadmap and future plans: `PLAN.md` section 7. Background and reasoning:
  `docs/FEATURE-REVIEW.md`.
- Outside proposals (`docs/GPT-PLAN.md`, `docs/MANUS-PLAN.md`,
  `docs/PERPLEXITY-PLAN.md`) were reviewed on 2 Nov: verdicts in
  `docs/PLAN-REVIEW.md`, agreed order in **PLAN.md section 7** (the single
  roadmap). Don't build from the proposal files directly.
- **Next (5 Nov):** **v0.3 Professions**: `docs/prompts/next-v0.3-professions.md`
  (the guild says professions matter most; Raids moves to v0.4, still before
  9 Dec). v0.2.6 hotfix is on `main` (5 Nov); the owner publishes the release.
  **v0.2.7** (probes only: `/sr debug` block "Profession checks for v0.3",
  `Commands.ProfessionProbes`) is on `main`; the tag push dropped, so the
  owner publishes the release on the website. **v0.3.0 Professions is built**
  on `claude/affectionate-archimedes-tirbrl` (owner said "do all of them";
  reminders must stay rare). **Released as v0.3.0 on 6 Nov** at the owner's
  request (on `main`; tag push may drop, the owner publishes on the website).
  Not tested in game yet: TESTING 87–97, and reagents with the window closed.
  The owner says the titles **look fine in game** even though v0.2.7's
  /sr debug reported the display font as failed (the check may have been a
  false alarm; v0.3.0's debug line counts it per text).
  **CurseForge:** project ID **1788068** is in the TOC (`X-Curse-Project-ID`);
  the release workflow uploads when the `CF_API_KEY` GitHub secret exists
  (owner's job, `docs/CURSEFORGE.md`). **v0.3.2 released 7 Nov** (on `main`,
  built on top of the v0.3.1 rename from another session): every recipe in the
  game from wago.tools data, All recipes search, Wowhead links, Getting
  started, CurseForge ID. Not tested in game: TESTING 87–107.
- **v0.3.3 (sync fix, 7 Nov)**, from branch `claude/short-kings-addon-hlf0t4`,
  built on `main` after v0.3.2: our own numbered pieces (`Sync/Frames.lua`,
  protocol 2) because AceComm multi-part messages arrived corrupted between
  two players (see "Sync protocol" below). Released v0.3.2 and earlier can't
  share profiles between players at all; v0.3.3 can't talk to them either.
  On `main` 7 Nov (the owner publishes the release; it uploads to CurseForge
  automatically). TESTING 108–110.
- **v0.3.4 (on `main` 7 Nov; the owner publishes the release)**, from `claude/short-kings-addon-hlf0t4`,
  owner's request: clicking a crafter in one profession shows **their**
  recipes (`ProfessionsTab:PickCrafter`, `ProfBoard.Recipes(ctx, line,
  filter, crafterGUID)`), with **Character** and **Everyone** buttons; the
  Overview's Guild section counts who has Short Royalty and lists up to 10
  who don't (`Overview.Build` → `hasAddon`, `without`, `addonNoData`;
  `Identity.HasAddon` = own account, a version heard (HI), or any profile).
  *Without addon* = `RosterTab:ShowWithoutAddon` (Version column sorts
  no-addon first). Also the orange **profession reminder bar** (owner picked
  "banner on every tab" + "open it for me" from a list of options):
  `Professions.Banner(own, share)` (pure), `MainFrame:UpdateBanner` (the
  window grows by `SIZES.banner + SP.m` so tab layouts don't move),
  `Compat.ShowProfession(skillLine)` → Blizzard's `OpenProfessionUIToSkillLine`
  (Blizzard_Professions bootstrap) or `C_TradeSkillUI.OpenTradeSkill`, neither
  restricted in the forever source; not in combat. Unconfirmed in game.
  TESTING 111–117. (`Compat.OpenProfession` is the old *read which window is
  open* function; don't confuse them.)
- **v0.3.4 published 7 Nov** by the owner (GitHub release with the zip).
- **v0.3.5 (on `main` 7 Nov, released automatically)**: Block rows take `tip = function(tooltip)`
  (an invisible hover frame per row, `W.Block`); the Overview's "Don't have it
  yet" row and its names use `OverviewTab.WithoutTip` (all names, two per
  line, capped at `TIP_NAMES` 60). TESTING 118.
- **v0.3.6 (on `main` 7 Nov, released automatically)**: fewer false "doesn't have it" (owner:
  "it's all of those reasons, fix all"):
  - old protocol (`\133…`, v0.3.2 and earlier) from an exact roster name →
    `m.oldAddon` (local): counts as having it, Roster "old", Overview outdated;
  - alts (all removed again in v0.4.0): `Core/Accounts.lua` (`Links` pure, `Current` caches Battle.net ids
    60 s) links an addon-less character to a user by **bnet** (same
    `bnetAccountId` from C_Club member info, or `C_BattleNet.GetAccountInfoByGUID`
    for friends: `Compat.AccountIDs`; unknown whether the game fills it for
    guildmates, /sr debug reports the count), **claim** (profile field
    `claims`, from "This is my alt" on the Character tab, `SK.DB.myAlts`,
    validated in `Merge.FIELDS`; older versions accept it as a plain extra
    field), or **note** (note/officer note names exactly one user's first
    name, ≥ 3 letters). Overview `altsOf` + "Alts of players who have it"
    row; Roster Version "alt". Display only, never sent;
  - relay: SQ and SO carry `a` = GUIDs known to run the addon
    (`Sync.KnownUsers`); receivers set `m.addonRelay` (no version, so relays
    can't fake "newer version" notices). An SQ with `a` gets an SO even with
    no profiles to offer (`g = {}`, which doesn't use the accept-one slot).
  TESTING 119–123.
- **v0.4.0 Raids, read-only (on `main` 7 Nov, released automatically)**. It also carries the v0.3.7 wording change (that
  version was never released, its CHANGELOG entry is folded into v0.4.0).
  Built from `docs/prompts/next-v0.4-raids.md` with these decisions:
  - `Compat` calendar layer: `GuildEvents`, `CalendarNow`
    (`C_DateAndTime.GetCurrentCalendarTime`), `CalendarOpenEvent(ev)`
    (`SetAbsMonth` to now, then find the event's index on its day with
    `GetNumDayEvents`/`GetDayEvent` by eventID, then `OpenEvent(offset, day,
    index)`), `CalendarInvites`, `CalendarCloseEvent`, `CalendarShown`
    (`CalendarFrame`), `ToggleCalendar` (Blizzard_Calendar bootstrap). All
    verified in the forever source; `CalendarStatus` enum 0–8, event type
    Raid = 0.
  - `Core/Raids.lua`: pure `Match` (whole-word title keywords from
    `Data/Attunements.lua`, or the player's pick in `SK.DB.raidPick`),
    `Upcoming` (raid type, 6 h ago to 30 days ahead), `LineUp` (role from
    `profile.roles` or `Data.GuessRole`; counts; readiness incl. duplicates
    via `Alts.Groups`), `Text` (Copy). `Raids:Read` only when
    `Raids.Blocked()` is nil (calendar window closed, not combat, not chat
    lockdown), one at a time, 5 s timeout, cache per eventID for the session.
  - Roles: **on the Raids tab** ("My roles", two menus) rather than
    Settings (Settings' column is full). Per character in `SK.DB.roles`,
    shared as `profile.roles = { main, second }` (validated in
    `Merge.FIELDS`; older versions accept it as a plain extra field). Role
    guesses (`Data/Roles.lua`) are by class and tree ORDER, `status = "todo"`.
  - `W.Menu:Choose(value)` added (tests and code); menus show `W.MENU_ROWS`
    (12) rows and scroll with the mouse wheel.
  - **Alt guessing removed (owner chose "B", 7 Nov)** after researching how
    other addons handle alts (GRM: manual alt groups; others: guild notes;
    none can see accounts) and briefly building officer alt links. Gone:
    `Core/Accounts.lua` (Battle.net / note / claim matching),
    `Compat.AccountIDs`, "This is my alt", the officer "Alt of…" menu,
    **Make this my main** (and the profile `main` field; `Alts.Groups` picks
    the highest level, older clients' votes still count), the Getting
    started "mark your main" step, Roster "alt", the Overview alts line.
    Kept: automatic family linking (Roster grouping, Crafters "on <alt>",
    Raids double sign-up), `m.oldAddon`, the SQ/SO `a` relay, and the
    `claims` validator (v0.3.6 clients still send it; ignored). Overview:
    **Have Short Royalty** + **Not seen with the addon yet** = members,
    counted per character. Don't bring the guessing back unless asked.
  - **Alt rank (owner, 7 Nov):** the guild's rank named "Alt" is only used for
    alts and is accurate. `Identity.IsAltRank(m)` = rank name has the word
    "alt"/"alts". `Overview.Build` leaves those characters out of everything
    (members, online, have / not seen, levels, data health, raids) except the
    Professions card (alts are crafters); `o.altRank` = how many (Members
    tooltip). Roster "Not seen yet" sorts them after real gaps. The owner
    doesn't want an "Alts" line on the Overview. TESTING 135.
    TESTING 132–134.
  - Not yet: sign-up buttons, reminders, invite everyone (v0.4.1, after the
    in-game test). TESTING 125–131.
- **v0.4.1 (on `main` 8 Nov, released automatically): the Raids tab was
  removed** at the owner's request ("the raid section just isn't set up right
  yet … keep it as crafting and professions for now"). Gone: `UI/RaidsTab.lua`,
  `Core/Raids.lua`, `Data/Roles.lua`, the Compat calendar layer (only the
  `CalendarStatus` probe stays), "My roles" (`SK.DB.roles`, profile `roles`
  no longer sent; the `roles` validator stays because v0.4.0 clients send
  it), raid title keywords, `tests/raids_spec.lua`, the preview screen and
  `docs/images/raids.png`. Kept: the Overview Raids card (countdown,
  attunement) and the Roster raid attunement filter, scrolling menus,
  `W.Menu:Choose`. The v0.4.0 notes above describe how the tab was built
  (git history has the code) if raids come back; re-plan with the owner
  first. TESTING 136.
- **v0.4.2 (on `main` 10 Nov, released automatically)**: three fixes from the owner's
  v0.4.1 report (see "Confirmed in game 10 Nov"): guild-nil crash, lost
  profession scans (`SK.DB.scanKeep[guid][skillLine] = { scanned, rank,
  recipes }`, restored when the profession returns at ≥ that rank), and
  send results (`Sync.SendOutcome(result, dist)` → "offline";
  `stats.targetOffline`). Tests: `tests/v042_spec.lua` (loads the real
  ChatThrottleLib). TESTING 137–139.
- **v0.4.3 released 11 Nov** (pushed to `main` at the owner's request after
  testing the CI test build; the owner said the model "looks good"). **Version
  clash:** branch `claude/short-kings-addon-hlf0t4` (levelling helper) also
  called itself v0.4.3; it merged `main` and became **v0.4.4** (TESTING
  145–149). Character model details:
  character model on the Character tab (owner asked 11 Nov). Decisions:
  - Forever has **no API to build a player model from data** (face, hair,
    skin, gender: only the barber shop and character select can). Models come
    only from a present unit. So: `Compat.ShowGearModel(scene, {guid, raceFile,
    gear})` = real model via `SetModelByUnit(unit)` when `Compat.UnitForGUID`
    finds them (player/target/focus/mouseover/party/raid), else
    `SetModelByUnit("player", …, autoDress=false, …, customRaceID)` +
    `Undress` + `TryOn(link, "MAINHANDSLOT"/"SECONDARYHANDSLOT")`. Same setup as
    Blizzard's dressing room: `CreateFrame("ModelScene", nil, p,
    "ModelSceneMixinTemplate")`, `TransitionToModelSceneID(596, …)`,
    `GetPlayerActor(nil, nil, raceFile, gender)`. Race via
    `C_CreatureInfo.GetRaceInfo` → `Compat.RaceID`. **Nothing new synced**
    (gender was considered and dropped: it can't change the body).
  - `settings.charModel` (default on), `CharacterTab:UpdateModel` rebuilds
    only when guid / profile hash / "is here" changes, never in combat;
    PLAYER_TARGET_CHANGED and GROUP_ROSTER_UPDATE refresh it. Untested in
    game: TESTING 140–144 (does customRaceID really swap race?).
  - The GitHub repo is now **EllisKOsborn/forever-shortroyalty** (old URL
    redirects).
- **v0.4.4 (on `main` 11 Nov, released automatically; built as "v0.4.3" before the version clash): Levelling helper**, step 1 of the
  levelling tools the owner wants after seeing Profession Master (CurseForge,
  All Rights Reserved: never copy its code; it already supports Forever).
  Owner's rule: **"take the cheapest and most efficient route for WoW
  Forever. Do not use Retail or Classic data, only from Forever."**
  - `tools/recipes.js` adds `MinSkillLineRank, TrivialSkillLineRankLow,
    TrivialSkillLineRankHigh, NumSkillUps` from Forever's SkillLineAbility
    (product `wowf`), entries `{ id, item, cat, reag, min, low, high, ups }`.
    Regenerated from build **1.60.1.70888** (recipe list identical otherwise).
    Fixed: a build number given on the command line was ignored.
  - Colours (`RecipeDB.Range/ColourAt/PointsLeft/SkillUps/IKnow/MySkill`):
    yellow at `low`, green at floor((low+high)/2), grey at `high`, orange
    below yellow. Forever's numbers differ from Classic (Gray Woolen Shirt
    90/100/110). **`MinSkillLineRank` is 1 for >90% of recipes in Forever,
    so it isn't the learn level**: the trainer/recipe requirement isn't in
    the data. So only **learned** recipes get a "for you" colour or appear in
    Levelling. 38 recipes have no range (placeholders) and 1 has high < low:
    `Range` returns nil for them.
  - The green midpoint rule is unverified for Forever: `RecipeDB.CheckColour`
    compares ours with `GetRecipeInfo().relativeDifficulty` (0 orange …
    3 grey) for every learned recipe on each scan; `SK.DB.colourCheck`
    (per build, 5 examples) → `/sr debug` "Skill-up colours vs your
    profession window". If it differs, fix the rule before building on it.
  - UI: Professions view **Levelling** (`settings.levelProf`, menu of your
    professions with recipes; `LEVEL_COLUMNS`), `W.SkillUpText/SkillUpTip`
    in recipe tooltips and the Crafters panel. Theme colours `skillOrange/
    skillYellow/skillGreen/skillGrey` (Blizzard's DIFFICULT/FAIR/EASY/
    TRIVIAL_DIFFICULTY_COLOR), `Theme.SkillColour/SkillRange`.
  - Next steps (owner chose to build in order): shopping list, profit via
    Auctionator's public API (or vendor prices), then the cheapest-route
    planner. Trainer costs and recipe sources aren't in Forever's data.
  - TESTING 145–147. Mock-up `profView=levelling` uses real Forever numbers.
  - Also in v0.4.4 (owner): the window's title bar no longer shows the
    "Height is not a stat." subtitle; the title is centred on the crest.
    Then (owner) removed from the minimap tooltip and TOC Notes too:
    `SK.TAGLINE` no longer exists; the tagline lives only in the README/
    preview banner art. TOC Notes: "Guild gear, talents, professions and
    recipes for the Short Royalty guild." TESTING 148.
  - Also in v0.4.4 (owner): the icon is the crest, not `INV_Misc_Bomb_04`:
    TOC `## IconTexture: Interface\AddOns\ShortRoyalty\Media\Textures\crest`,
    `MM.ICON = Theme.TEX.crest`, full texcoords (LibDBIcon `iconCoords`).
    Unconfirmed in game that the AddOns list shows a custom .tga. TESTING 149.
- **v0.4.5 (on `main` 11 Nov, released automatically): Shopping list**, step 2 of the
  levelling tools. `Core/Shopping.lua`: `SK.DB.shopping.list = { { id =
  recipeID, n = crafts } }` (local, max 50 recipes, 999 crafts; event
  `SHOPPING_CHANGED`), pure `Shop.Totals(entries, reagentsOf, countOf)`,
  `Shop.YouMake(itemID)` (a learned recipe makes it), `Shop.Text` (Copy).
  Reagents: `Reagents.All` (game read, else bundled data; no 8-slot cap).
  Counts: `Compat.ItemCounts` → bags, and `C_Item.GetItemCount(id, true,
  false, true, true)` (bank, reagent bank, account bank; verified in the
  forever source). Unknown whether the bank count works away from the bank
  (TESTING 152). UI: Professions view `shopping` (recipes 400 px with −/+
  buttons, reagents on the right; Copy, Clear list), Shift-click on any
  recipe list (`Prof.AddToList`, `Compat.ShiftDown`), Crafters "+ List"
  chip. Refreshes on BAG_UPDATE_DELAYED / PLAYERBANKSLOTS_CHANGED. The
  Professions status line now starts after the view chips. Tests:
  `tests/shopping_spec.lua` (set `_G.IsShiftKeyDown`: busted gives spec
  files their own globals).
- **v0.4.6 (on `main` 11 Nov, released automatically): Profit**, step 3. Owner: the guild
  uses **both Auctionator and TSM**. `Core/Prices.lua`: `P.Source()`
  (`settings.priceSource` auto/auctionator/tsm; auto = Auctionator first),
  `P.Auction` (TSM tries `DBMarket`, then `DBMinBuyout`), `P.Buy` (cheaper of
  remembered vendor price and auction), `P.Sell` (auction after `P.AH_CUT`
  5%, unconfirmed for Forever, or vendor sell price if higher), pure
  `P.Craft(reagents, outputID, yield, prices)` (cost/profit nil when any
  reagent lacks a price: never guessed), `P.Rows`, `P.Money`. Vendor buy
  prices: `SK.DB.vendorBuy[itemID]` (cheapest seen, local) from
  MERCHANT_SHOW/UPDATE via `Compat.MerchantItems` (`GetMerchantNumItems`,
  `GetMerchantItemID`, `C_MerchantFrame.GetItemInfo` price/stackCount, as in
  Blizzard's Forever Mainline MerchantFrame.lua; currency and extended-cost
  items skipped). `Compat.PriceAddons/AuctionatorPrice/TSMPrice/
  VendorSellPrice` (C_Item.GetItemInfo 11th return), all pcall'd, results
  must be numbers 0..1e12. **API names are from memory**, not docs:
  Auctionator's official code isn't on GitHub and TSM's API site
  (api.tradeskillmaster.com/addon/) returned 503 on 11 Nov; `/sr debug`
  "Prices:" line reports what answers. Items per craft: `Data/Recipes.lua`
  9th field from SpellEffect `EffectBasePointsF` (same build 1.60.1.70888;
  only that field was added; 0 = makes no item), `RecipeDB` `yield`,
  `Reagents.Yield` (game's `quantityMin` once read, else data, else 1).
  UI: Professions view `profit` (shares `settings.levelProf` with
  Levelling; Prices menu; `PROFIT_COLUMNS`; tooltips per reagent), Shopping
  "About … to buy" (`Shop.Cost`, `Prof.ShopCostText`). Tests:
  `tests/prices_spec.lua`.
- **v0.3.7 (folded into v0.4.0, never released)**: wording only. The owner asked whether
  to remove alt features; advice was no (removing them wouldn't fix the
  per-character gap and would lose roster grouping and "on alt" whispers).
  "Don't have it yet" → **"Not seen with the addon yet"**, button "Not seen
  yet". Pending: owner's in-game test of the Warband currency API
  (`C_CurrencyInfo.RequestCurrencyDataForAccountCharacters` +
  `FetchCurrencyDataFromAccountCharacters(currencyID)` → characterGUID/name of
  the player's own characters holding an account-transferable currency;
  Forever loads Blizzard_CurrencyTransfer). If it lists alts, build automatic
  "my alts" claims on it. TESTING 124.
- **CurseForge uploads are automatic** (checked 7 Nov: the v0.3.2 Release run
  logged "Uploading ShortRoyalty-v0.3.2-forever.zip (1.60.1 release) …
  Success!"). Owner still renames the project from "Short Kings" and archives
  the old files (`docs/CURSEFORGE.md`).
  Plan and what was left out: **PLAN.md section 11**.
- Earlier plan: PLAN.md **section 10, "Once Forever is live"**: the in-game test
  gate (TESTING.md, `/sr debug` "Live-client checks"), its decision table,
  fixes only (now **v0.2.5**: v0.2.3 = new look, v0.2.4 = tagline). Raids is now
  **v0.4** before 9 Dec (`docs/prompts/next-v0.4-raids.md`); Professions is v0.3.
- Calendar facts (1.60.1 docs): invites carry `guid`; no role field; only
  `AddEvent` is `HasRestrictions`; `GetDayEvent`/`EventGetInvite` are secret
  during chat lockdown; `C_PartyInfo.InviteUnit` and `ConvertToRaid` exist.
- Decisions in v0.1.2/v0.2.0:
  - Roster raid mode uses a **second List** with its own columns (Attuned
    replaces Professions and Ver) instead of rebuilding the List widget.
  - Attunement shows "unknown" when the player hides gear/talents.
  - Attuned marks use the ready-check atlases (`UI-LFG-ReadyMark` etc.):
    the game font has no ✓/✗ glyphs.
  - CraftIndex lives in `Core/` (no UI); `Identity.Status` moved there from
    RosterTab so Sync and CraftIndex can use it.
  - Names: `C_Item.GetItemNameByID` / `C_Spell.GetSpellName`, with
    `RequestLoad*` + `ITEM_DATA_LOAD_RESULT` / `SPELL_DATA_LOAD_RESULT`
    (event approach, not the Item mixin), at most 200 requests per search.
  - "Post to guild chat" uses `ChatFrameUtil.OpenChat("/g …")`; never
    `SendChatMessage`.
- Decisions in v0.3.0:
  - Specialisation detection: known (`C_SpellBook.IsSpellKnown`) **and**
    (`status = "ok"` or the client's spell name equals the Data name). Synced
    as `profs[skillLine].specs` (spell IDs); display only for IDs in
    `SK.Data.SPEC_BY_SPELL`.
  - Reagents are local only (`ShortRoyaltyDB.reagents`, keyed by game build),
    learned during scans and on demand. Never in profiles.
  - Favourites: `ShortRoyaltyDB.favourites` (local). Right-click to star.
  - Nudges: `Professions.NUDGE_POINTS` 15, `NUDGE_EVERY` 3 days, once per
    session, `settings.profNudges`; scan ranks in `ShortRoyaltyDB.scanRank`.
  - "At 300" uses `SK.Data.SKILL_CAP` (original-game cap; confirm in game).
  - Clicking a recipe in Professions opens it in Crafters
    (`CraftersTab:ShowRecipe`), including recipes nobody knows.
- Decisions in v0.3.2 (built as "v0.3.1" before the rename took that number):
  - (v0.4.3) `node tools/recipes.js` with no build fetches the newest Forever
    build; `node tools/recipes.js 1.60.1.70888` pins one.
  - Recipe list: `node tools/recipes.js [build]` downloads SkillLineAbility,
    TradeSkillCategory, SpellEffect (Effect 24 = create item) and SpellReagents
    CSVs from wago.tools (product `wowf` = Forever) and writes
    `Data/Recipes.lua` (IDs, category, item, reagents; **no names**).
    Categories named Season of Discovery / PROTOTYPE / [DNT] are excluded.
    Rerun it after a Forever patch. Verified against the owner's game: Seed
    Hybridizer's reagents match exactly.
  - **Don't scrape Wowhead** (terms forbid it); link to it instead:
    `https://www.wowhead.com/forever/item=<id>` or `/spell=<id>` (path
    checked 7 Nov).
  - `Compat.SpellExists` (`C_Spell.DoesSpellExist`) hides recipes the client
    lacks. Name loads are budgeted (`CI.SetBudget`, 200 per search); names the
    game can't load are not re-requested (`CI.failedItems`).
  - Getting started: `Core/Onboarding.lua` (pure `Steps`), shown in the
    Overview's milestones slot; `settings.seen[tab]`, `settings.onboarding.hidden`,
    `settings.welcomed`.
- Decisions in v0.2.2:
  - Overview numbers come from `Core/Overview.lua` (pure); attunement logic
    lives in `Collect/Attunements.lua` (`Att.StateOf`), shared by Roster,
    Character and Overview.
  - Milestones (`Core/Feed.lua`) are derived from old vs new profile copies
    in `Sync` (PR accepted) and `Profile:Commit`; first copy = no events;
    stored in `ShortRoyaltyDB.feed` (max 50), never sent.
  - The window opens on the Overview once (`settings.overviewShown`), then
    the last tab.

## Design refresh (merged into `main` and released as v0.2.3, 3 Nov 2026)
- Built on branch `design/refresh`, merged into `main` and tagged **v0.2.3**
  when the owner asked (they chose to release before the in-game test).
  Untested in game: fixes from the test round go into **v0.2.5**.
- Visual rules live in `DESIGN.md`. Nothing visual is hard-coded outside
  `UI/Theme.lua` (`tests/design_spec.lua` enforces it). Colours: gold = where
  you are / one primary action / key figure; beard pink = selections and the
  crest; spark orange = alerts and sync status only.
- Widgets keep no ad-hoc fields read before they're set: the test stub
  returns a function for any unknown field, so state lives in plain tables
  (Theme's border map, Motion's group map) or is initialised at creation.
- After changing Theme.lua: `node tools/preview-tokens.js`, then
  `node docs/mockups/render.js` (Chrome headless or Playwright → PNG). The
  README pictures (incl. before-after.png and palette.png) come from it;
  the old pictures live in `docs/images/before/`.
- Local test tools on the owner's Mac were built in a session scratch folder
  (not persistent); rebuild with lua.org 5.1.5 + LuaRocks if needed.

## Waiting on the user (remind them when relevant)
Full post-launch checklist: PLAN.md section 10.
Done on 5 Nov: interface 16001 confirmed, the addon loads, GUID stable,
a test send worked. The Mac AddOns path is still not confirmed by name
(the owner installed successfully).
0. **Owner, 11 Nov (v0.4.5 in game): "All works fine"**, only the menu
   hover bug (fixed in v0.4.6). Their Levelling menu listed Tailoring
   120/150, Enchanting 79/150, Cooking 93/150, First Aid 41/75, Fishing
   91/150. Still not reported: the items below.
1. v0.4.4 is out: a new `/sr debug` (skill-up colour check, TESTING 145;
   send errors after the v0.4.2 fix; Tailoring/First Aid stay "scanned yes",
   TESTING 138), TESTING 140–144 (character model) and 145–149 (levelling,
   crest icon, no tagline).
2. v0.4.5 is out: TESTING 150–154, especially whether the bank count
   works away from the bank (152).
2c. v0.5.5 is out: TESTING 167–183. Most useful: `/sr debug` lines "Where to
   learn" and "Trainers" (after opening a profession window and a trainer),
   where the panel sits, and whether TSM accepts "Copy for TSM".
2b. v0.4.6: "Prices:" line received 11 Nov (TSM works, Auctionator "no").
   Still: is Auctionator installed? Do Profit's numbers look right (157)?
   And the colour-check line after opening a profession window.
3. The Warband currency `/run` test (TESTING 124): if it lists their own
   alts, automatic "my alts" can be built on it. Otherwise alts stay as now.
4. Onyxia attunement: whether any Horde members exist (Horde chain differs), and
   in-game check that the Drakefire Amulet check works.

## Answers already given to the guild (stay consistent)
- **Alts:** linked automatically once each alt has logged in with the addon
  (same guild). The highest-level character is shown as the main (the
  "Make this my main" button was removed in v0.4.0). An alt shows as "not
  seen with the addon" until its player logs in on it once.
- **Recipes:** the full recipe list per profession is recorded and synced
  (refreshed when the profession window is opened). Since v0.2.0 the
  Crafters tab searches it by item name and item tooltips list crafters.
- **Update speed:** comes from players' own games, not Blizzard's armory.
  Since v0.1.2, changes reach guildmates in about 30–60 seconds while
  they're online ("Ask for latest" on the Character tab gets it sooner).
  Offline members show their last state. Paused in instances and combat.
  Recipes refresh when the profession window is opened.
