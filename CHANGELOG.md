# Changelog

## v0.5.6 (not released yet): back to the basics of professions

The levelling tools weren't working as intended, so they're **removed for
now** and will come back reworked:

- Gone from the Professions tab: **Levelling**, **Route** and **Shopping
  list** (and the "+ List" button, Shift-click to add, and shopping lines in
  item tooltips).
- Gone: the **panel beside your profession window** and `/sr panel`.
- Kept: skill-up colours and "where to learn" in recipe tooltips, the All
  recipes **Show** filter, and **who wears it** (`/sr who`).
- If you had a Levelling, Route or Shopping list view open, the tab opens on
  Guild instead. Your saved shopping list stays in your saved data, unused.
- `/sr debug` now lists, per profession, any recipe you know that isn't in
  Forever's bundled recipe list, and names the profession of the last scan
  again (the game leaves it blank).

## v0.5.5 (11 Nov 2026): Professions upgrade

Everything from the professions review in one release: where to learn
recipes, a better shopping list, a smarter route, a panel beside your
profession window, and who wears what.

### Where to learn each recipe

- **Recipe tooltips say where to learn a recipe you don't know** (All
  recipes, a profession's list, Levelling, Route, Crafters):
  - **Recipe items** (patterns, plans, formulas, schematics…) from WoW
    Forever's own data, with the skill needed, for example "Learn from
    Pattern: Red Woolen Bag (Tailoring 90)", plus its price if TSM or a
    vendor you've visited knows it;
  - **Trainers:** open a profession trainer once and Short Royalty
    remembers what it teaches, the skill needed and the cost ("Trainer:
    Tailoring 145, 22s");
  - **the game's own "where from" text**, read while your profession window
    is open.
- **Levelling** says how many recipes a trainer you've visited would teach
  you now ("2 to learn at your trainer").
- `/sr debug` shows what the game gives for this, so we can check it.
- Everything stays on your computer. No map pins: where trainers and vendors
  stand isn't in the game's data (the Wowhead button has that).

### Shopping list upgrades

- **Item tooltips** show "Shopping list: need 7, have 3" for anything on
  your shopping list (in your bags, at the auction house, anywhere).
- **Make or buy:** a reagent you can make yourself (bolts, bars) is priced
  at the cheaper of buying it and making it from its own reagents. The
  shopping list and Route use this; prices say "(you make it)".
- **Raw materials** button on the Shopping list: reagents you make yourself
  become "make 4" and what they're made from is added (Bolt of Woolen
  Cloth → Wool Cloth).
- **Copy for TSM:** what you still need to buy as a TSM item list
  (`i:2589,i:2592…`) to import into a TSM group and shop it.

### Route with recipes you haven't learned

- **Route** can now plan with recipes you don't know yet (on by default;
  the **Recipes to learn** button turns it off):
  - recipe items (patterns, plans…) that have a price, from TSM or a vendor
    you've visited, from the skill they need;
  - recipes a trainer you've opened teaches, from the skill and cost it
    showed.
- A step says "learn at trainer" or "learn from recipe", and its tooltip
  what it costs. Learning costs are in the total, counted once.
- A recipe worth learning is judged on all the points it can give you on
  the way to your target, not only the first one.

### Panel beside the profession window, filters

- **A Short Royalty panel beside your profession window** (your own
  professions): the next step of your cheapest route, and for the recipe
  you pick in the window its colour, where to learn it and who in the guild
  makes it. **Route** opens the whole plan, **+ List** adds the recipe to
  your shopping list, **Hide** turns the panel off (`/sr panel` brings it
  back).
- **All recipes → Show:** everything, recipes you can learn now, recipes
  from recipe items, from trainers, or ones that still give you points. The
  learning ones are sorted by the skill they need.

### Who wears it

- **Item tooltips** say which guildmates wear the item ("Guild: worn by
  Fizzwick, Brambletoe (+2)"), from the gear they share. Anyone who hides
  their gear is never listed.
- **`/sr who`** followed by a Shift-clicked item (or part of its name) lists
  who in the guild wears it.
- The Settings tick box is now *Show guild crafters and wearers in item
  tooltips*.

## v0.4.8 (11 Nov 2026): Cheapest levelling route

- **Professions → Route** (new view): the cheapest way from your skill to
  your cap with the recipes you've learned. For each stretch of points it
  says which recipe to craft, how many times, and what it costs.
- At each point it picks the recipe that costs least **per skill point**,
  counting what you'd get for **selling what you make**. Prices come from
  TradeSkillMaster if you have it, and from the vendor prices Short Royalty
  remembers when you visit a vendor.
- Orange recipes always give a point; yellow and green only sometimes, so
  their number of crafts is an average (the original game's chance; not
  confirmed for Forever yet).
- **Add all to shopping list** puts every craft on your shopping list.
- When none of your recipes gives points any more, it tells you to visit
  your trainer (Forever's data doesn't say what trainers teach).

## v0.4.7 (11 Nov 2026): fixes

- **Fixed: the skill-up colour check in `/sr debug` counted false
  differences.** Just after a profession window opens, the game can report
  your skill as 0 for a moment; recipes were compared at skill 0 then. Those
  moments are now skipped and the count starts again.

## v0.4.6 (11 Nov 2026): Profit

- **Professions → Profit** (new view): every recipe you've learned in one
  profession with what its reagents cost, what it sells for and the
  profit, best first.
- **Auction prices from Auctionator or TradeSkillMaster**, whichever you
  have (a menu picks one if you have both). Without either you get vendor
  prices only.
- **Vendor prices are remembered** each time you open a vendor, and each
  reagent is priced the cheaper way (vendor or auction house).
- Auction sales count the 5% auction house cut. Recipes that make several
  items (ammo makes 200) count them all, from Forever's own data.
- **Shopping list:** shows roughly what the rest of your reagents cost, and
  each reagent's price when you point at it.
- `/sr debug` says whether Auctionator and TSM answered.
- Everything stays on your computer; nothing new is sent to guildmates.
- **Fixed: drop-down menus hid the line under the mouse** (for example the
  profession menu in Levelling). The hover bar now sits behind the text.

## v0.4.5 (11 Nov 2026): Shopping list

- **Professions → Shopping list** (new view): pick recipes and how many
  times you'll craft each, and see every reagent they add up to, how many
  you **have in your bags and bank**, and how many are **still to get**.
- **Adding recipes:** Shift-click a recipe in All recipes, Levelling or a
  profession's recipe list, or press **+ List** next to Star on the
  Crafters tab. Change the number with **−** and **+** (hold Shift for 5),
  right-click a recipe to take it off, or **Clear list**.
- Says when **you can make a reagent yourself** (a recipe you've learned
  makes it, like Bolt of Woolen Cloth for Tailoring).
- **Copy** gives the list as plain text, for Discord or a note.
- Saved on your computer only; nothing new is sent to guildmates, so it
  works whatever version they have.
- Reagents come from your game, or from WoW Forever's own data when you
  haven't opened that profession window (never from Classic or Retail).

## v0.4.4 (11 Nov 2026): Levelling helper

- **Professions → Levelling** (new view): pick one of your professions and
  see every recipe you've learned that still gives skill-ups at your skill,
  best first: its colour for you (orange, yellow, green), how many points
  until it turns grey, and where it turns yellow, green and grey.
- **Only WoW Forever's own data.** The skill-up numbers come from Forever's
  game files for the current build (1.60.1.70888), not Classic or Retail.
  Forever changed many of them: Gray Woolen Shirt, for example, turns
  yellow at 90 and grey at 110.
- **Checked against your game.** Each time you open a profession window,
  Short Royalty compares its colours with the window's; `/sr debug` shows
  how many matched and any that didn't.
- Recipe tooltips (Professions, All recipes, Crafters) and the Crafters panel
  show where a recipe turns yellow, green and grey, and its colour for you if
  you've learned it.
- Recipes you haven't learned aren't in the Levelling list: Forever's data
  doesn't say at what skill a trainer or recipe teaches them.
- The "Height is not a stat." tagline is gone from the game: the window's
  title bar now shows just **SHORT ROYALTY**, and the minimap button's
  tooltip and the AddOns list description no longer have it. The AddOns
  list description no longer mentions raid sign-ups either (the Raids tab
  was removed in v0.4.1).
- The addon's icon is now our **crest** instead of the game's bomb icon, in
  the AddOns list and on the minimap button.

## v0.4.3 (11 Nov 2026): character model

- **A 3D model on the Character tab**, between the gear slots. Drag to turn
  it, scroll to zoom; the **Model** button switches back to item level,
  talents and enchants.
- If the character is **your target or in your group**, it's their real
  look. Otherwise it's **their gear on your character**, switched to their
  race where the game allows. Their face, hair and gender can't be shown:
  the game only lets addons build models of players who are actually there.
- Nothing new is sent between players, so it works with guildmates on any
  version that shares gear.

## v0.4.2 (10 Nov 2026): fixes from the first big in-game report

From a `/sr debug` on v0.4.1 with 39 members and 24 sharing data:

- **Fixed a Lua error** ("attempt to index local 'guild'"). The game can say
  "no guild" for a moment (a loading screen, just after login); a message
  arriving right then failed. The addon now waits 15 seconds before
  believing it, and messages that arrive without a guild are set aside
  instead of failing.
- **Fixed: profession recipes could be lost.** If the game's profession list
  came back incomplete for a moment, the missing professions lost their
  recorded recipes and went back to "open your profession window". Their
  recipes are now kept and given back when the profession reappears. (If
  yours were lost, open those windows once more; the orange bar says which.)
- **"Send errors" no longer counts whispers to someone who just logged off.**
  That's normal, and it could wrongly trigger the "Sending to guildmates is
  failing" message. `/sr debug` shows them separately, and real errors now
  name Blizzard's reason.

## v0.4.1 (8 Nov 2026): Raids tab taken out for now

- **The Raids tab is gone again.** It wasn't set up right yet, so Short
  Royalty stays focused on crafting and professions for now. Raids will come
  back later, re-planned. "My roles" went with it (nothing else used it).
- Still here: the Overview's raid countdown and Onyxia attunement card, and
  the Roster's raid attunement filter.
- Everything else from v0.4.0 stays: the simpler "who has the addon" on the
  Overview, the Alt rank left out of it, and scrolling menus.
- Works with guildmates on v0.3.3 and later.

## v0.4.0 (7 Nov 2026): Raids

A new **Raids** tab, after Crafters, built on **Blizzard's guild calendar**.
Read-only for now: signing up still happens in Blizzard's calendar.

- **Upcoming raids** for the next 30 days (calendar events of type Raid),
  with day and time. The raid is worked out from the title (Ony, Onyxia, BD,
  Barrow, Hyjal); if not, pick it from a menu.
- **Who signed up**, read from the calendar: status, name, **role**, spec,
  item level and **attunement** for that raid. Members without the addon
  still show. Role counts ("Tanks 2 · Healers 6 · DPS 18 · 26 / 40") and a
  readiness line: missing tanks or healers, tentatives, not attuned, no
  amulet in bags, item-level range, missing enchants, old data, and anyone
  signed up on two characters.
- **My roles:** pick your main and second raid role at the top of the tab
  (per character). Guildmates see it; until then, roles are a greyed guess
  from class and talents.
- **New raid** opens Blizzard's calendar; **Copy** gives the line-up as text.
- Sign-ups are only read while Blizzard's calendar window is closed, never in
  combat or chat lockdown. `/sr debug` has a new Raids line.
- Works with guildmates on v0.3.3 and later (the new `roles` profile field
  is simply ignored by older versions).
- **Simpler "who has the addon" on the Overview:** two numbers, **Have
  Short Royalty** and **Not seen with the addon yet** (they add up to your
  member count), and the list of names. It counts characters: an alt shows
  as "not seen" until its player logs in on it once with the addon. The
  button is **Not seen yet**.
- **The Alt rank is left out of the Overview.** Characters in a rank named
  "Alt" or "Alts" no longer count in members, online, who has the addon,
  data health or raid numbers (pointing at Members says how many were left
  out). They still count in Professions and Recipes, since alts are often
  the crafters, and they're still in the Roster (listed after the real gaps
  in "Not seen yet").
- **Removed the alt guessing from v0.3.6** to keep things simple: the
  Battle.net matching, guild-note matching, **This is my alt** and the
  separate "Alts of players who have it" line are gone, and so is **Make
  this my main** (your highest-level character is shown as the main). Alts
  still link themselves once they've logged in with the addon, so Roster
  grouping and Crafters' "on <alt>" whispers work as before. Professions and
  recipes were never affected: every character shares its own.
- Fixed: in v0.3.6, pointing at an alt the addon had guessed could show a
  Lua error in the Roster tooltip.
- Long dropdown menus scroll with the mouse wheel.

## v0.3.6 (7 Nov 2026): fewer people wrongly listed as "doesn't have it"

People who do have Short Royalty were showing under **Don't have it yet** on
the Overview. Three causes, three fixes:

- **Guildmates on an old version** (v0.3.2 or earlier) send messages newer
  versions can't read, and those were thrown away before the addon noted who
  sent them. Now they count as having it: the Roster's Version column says
  **old** (orange), and Data health counts them under "Running an old Short
  Royalty", so you know to tell them to update.
- **Alts** that haven't logged in with the addon yet are now listed
  separately, as **Alts of players who have it** (point at it for "Bobby, alt
  of Bob"). The game doesn't tell addons which characters belong to one
  player, so Short Royalty uses three clues:
  - the same **Battle.net account**, where the game shares it (it may only do
    that for your Battle.net friends: `/sr debug` says how many it found);
  - **This is my alt**: a new button on the Character tab when you look at
    one of your characters that hasn't logged in with the addon. Your
    guildmates then see it as your alt. Click again to undo;
  - **guild notes**: a note (or officer note, if you can read it) that names
    exactly one guildmate who has the addon, like "Bob's alt".
  The Roster's Version column says **alt** for them.
- **Guildmates who are never online at the same time as you.** You only
  heard that someone has the addon when you were both online. Now, when
  someone logs in, their addon passes on who it has seen running Short
  Royalty, so everyone's list fills in over time. Older versions just ignore
  the extra information.

## v0.3.5 (7 Nov 2026)

- **Overview: the full list of who doesn't have Short Royalty.** "and 4 more"
  wasn't much use. Now point at **Don't have it yet** (or the names under it)
  and a tooltip lists everyone, two names per line, online first. Very large
  lists stop at 60 names; **Without addon** shows the rest in the Roster.
- Releases now publish themselves: once a new version is on `main`, GitHub
  builds the zip, makes the release and uploads it to CurseForge.

## v0.3.4 (7 Nov 2026): one crafter's recipes, who has the addon, profession reminder

- **Hard-to-miss profession reminder.** Until you've opened each of your
  crafting profession windows once, an orange bar sits under the tabs on
  every tab ("Your guild can't see your recipes yet. Open your Alchemy and
  Tailoring windows once.") with a gold **Open Alchemy** button that opens
  the window for you. It moves on to the next profession, and goes away by
  itself when they're all done. The button is off in combat. No bar if you
  chose not to share recipes. The login chat line now points to it.
- **Professions: click a crafter to see their recipes.** In one profession
  (say Tailoring), clicking a name used to jump to the Character tab. Now it
  shows only that person's recipes on the right, with their name and skill
  above. **Only they know** lists the recipes nobody else in the guild has.
  A **Character** button opens their character sheet; **Everyone** (or
  clicking the name again) shows the whole guild's recipes again. An empty
  list says why (private recipes, or the window never opened with the addon).
- **Overview: who has Short Royalty.** The Guild section now says how many
  members **have Short Royalty** and how many **don't have it yet**, and lists
  the first ten who don't (online first, with a dot, so you can ask them
  now). **Without addon** opens the Roster with all of them on top. "Have it"
  means we've heard from them or have their data; trial accounts can't send,
  so they count as not having it.
- "Online now" also says how many of those online run the addon. Data health
  now flags members who **have the addon but whose data hasn't reached you**
  (the case to report), instead of repeating the "don't have it" count.
- Roster: the Version column sorts members without the addon first; hovering
  someone without data says whether they have the addon or not.
- Getting started's "Get guildmates to install it" counts everyone who has
  it, not just who's online right now.

## v0.3.3 (7 Nov 2026): guildmates can see each other

**Everyone has to update.** v0.3.3 can't exchange data with v0.3.2 or
earlier (its messages are packaged differently), and `/sr debug` says so if a
guildmate is still on an old version.

- **Fixed: nobody could see anyone else's data.** In the first test between
  two players (7 Nov), every profile arrived broken ("bad compression") and was
  thrown away. Small messages worked, so the Roster showed people, but never
  their gear, talents or recipes. Big messages were split by the message
  library (AceComm), and those split messages didn't survive the trip between
  two players. Tests in game proved the chat itself is fine: every single
  message arrived complete and in order. So Short Royalty now splits big
  messages **itself** into numbered pieces, each a complete message of its own,
  and rebuilds them by number in whatever order they arrive.
- If a piece ever goes missing, `/sr debug` now names the sender and the
  missing piece ("Last incomplete message: from Aura Guardian: 4 of 5 pieces
  (missing 3)"), instead of the vague "bad compression".
- `/sr debug` also counts pieces received, messages waiting, ones given up on,
  duplicates and malformed pieces.
## v0.3.2 (7 Nov 2026): every recipe, search, Getting started, CurseForge

- **Every recipe in the game.** Professions → **All recipes** lists all
  ~2,250 profession recipes in Forever, learned or not. Search by name, by
  the profession window's group ("camping") or by a material ("thorium bar"
  shows everything that uses it), or pick a profession to see them all. The
  list comes from the game's own data for the Forever build (via
  wago.tools); names come from your game.
- **Nobody knows** on each profession now lists every recipe nobody in the
  guild has learned, not only what your own window showed.
- **Reagents everywhere:** shown even with the profession window closed and
  for recipes nobody knows.
- **Wowhead link** for any recipe (Crafters panel), to copy into your browser.
- **Getting started** checklist on the Overview for new players, and a
  welcome line the first time Short Royalty loads.
- **On CurseForge** from this version (project 1788068).
- Fix: item names the game can't load are no longer asked for again and
  again (they could slow down searches).

## v0.3.1 (7 Nov 2026): Short Royalty

The guild is now **Short Royalty**, and so is the addon. Works alongside
guildmates on **this version only**: the sync channel was renamed too,
so earlier test builds (`ShortKings`) and this one don't see each other.

- **New name everywhere you can read it:** the window title, the AddOns
  list, chat messages, tooltips, the minimap button, `/sk debug`, README and
  pictures.
- **Saved data follows future guild renames.** Guild data is stored under
  the guild's name, so a rename would start everyone from an empty roster.
  Now, when most of an old guild's members are in your new roster, its data
  moves over automatically. A different guild's data is never taken.
- Slash commands: **`/sr`** and **`/shortroyalty`** (`/sk` still works).
- **The addon folder is now `ShortRoyalty`** and the download is
  **`ShortRoyalty-vX.Y.Z-forever.zip`**. If you tried an earlier test build,
  **delete the old `ShortKings` folder** from AddOns. Its saved settings don't
  carry over (nobody had real data yet), and it can't sync with this version.

## v0.3.0 (6 Nov 2026): Professions

A new **Professions** tab, after Crafters. Works alongside guildmates on
v0.2.5 and later (no new message types).

- **Guild board:** every profession, crafting first, then gathering, then
  secondary, including the ones nobody has. Characters, how many at 300,
  online now, top skill, when recipes were last recorded, and
  specialisations. Click a row to open that profession.
- **One profession:** its crafters (status, alt of, skill, specialisation,
  how old their recipe list is, orange after a week, Whisper) and its
  recipes with crafter counts. Filters: All, Only one crafter, Favourites,
  and Nobody knows (only when the game's window lists unlearned recipes).
  Click a recipe to open it in Crafters.
- **Cooldown board:** everyone's profession cooldowns, ready first, with
  how long ago we last heard from that player (orange after a day).
- **Specialisations** from the original game (Engineering, Leatherworking,
  Blacksmithing), read from your spellbook. A spell only counts when the
  game's own name for it matches, so nobody gets a wrong label. Shared as a
  small new field that older versions simply ignore.
- **Reagents** in the Crafters panel and recipe tooltips, with how many you
  have in your bags. Read from your own game and kept on your computer;
  never sent.
- **Favourites:** right-click a recipe or crafter to star it. A Favourites
  filter in Crafters and Professions. Saved on your computer only.
- **Gathering professions can have recipes** in Forever (Herbalism's
  camping items, for example), so they're recorded, searchable and listed
  like any other profession.
- **Title font fix:** the Chakra Petch titles could fall back to the game
  font (seen in an in-game report). The font is now loaded with the addon,
  and `/sk debug` says how many texts got it.
- **Reminder to reopen a profession window** when your skill has gone up 15
  or more since you last opened it: on the tab, and in chat at most once
  every three days. Can be turned off in Settings.

## v0.2.7 (5 Nov 2026): profession checks

Nothing changes in how the addon works. `/sk debug` gets a new block,
**"Profession checks for v0.3"**, that records what the game shows before
the Professions tab is built:

- whether the profession window lists recipes you haven't learned (and
  whether its "show unlearned" filter is on);
- the window's recipe categories by name, with a few examples each (to see
  how Forever's Blueprints and camp objects appear);
- the reagents the game reports for a recipe you know and one you don't,
  with the window open and closed;
- whether you know each original-game specialisation (Gnomish/Goblin,
  Dragonscale/Elemental/Tribal, Armorsmith/Weaponsmith and the master
  smiths), and the game's own name for each spell ID.

## v0.2.6 (5 Nov 2026): hotfix

- **False "send errors" fixed.** v0.2.5 counted every *successful* send as an
  error (the message libraries report "sent: true", not Blizzard's result
  number), so after 5 sends it would have shown "Sending to guildmates is
  failing". Messages were going out fine; only the counting was wrong.
  Seen in the owner's `/sk debug` ("Send errors: 3, last: true").

## v0.2.5 (5 Nov 2026): launch-day fixes and security fixes

**Launch-day fixes** from the first in-game test (5 Nov 2026, build 70790):

- **Sync was switched off by mistake.** Blizzard's "addon chat restricted"
  check says *restricted* on normal Forever realms (Blizzard only uses it for
  an esports tool), so v0.2.2–v0.2.4 never sent anything. A real test send to
  the guild worked, so Short Kings now only blocks trial accounts and trusts
  each send's own result instead. If sends keep failing, it says so once in
  chat, and `/sk debug` shows the error.
- **Missing-enchant warnings only at max level (60).** Levelling gear is no
  longer flagged.
- Confirmed in game: interface 16001, your character's ID stays the same
  between logins, and addon messages name the sender "First Surname" (the
  same as the guild roster).

**Security fixes** from a security review (`docs/SECURITY-REVIEW.md`). Works
alongside guildmates on v0.2.2 to v0.2.4: the protocol is unchanged, this
version is just stricter about what it accepts.

- **One bad profile can no longer break the addon for the guild.** Every
  field of an incoming profile is checked (types, sizes, counts); anything
  malformed is refused instead of saved and passed on.
- **No impersonation by first name.** A whisper whose sender only matches a
  member by first name is accepted only once that sender has been seen on
  the guild channel this session.
- **No zip bombs.** Messages from people who can't be guild members, or on
  channels we never use, are dropped before decoding; anything that
  decompresses to over 256 KB is refused; after 3 bad messages a sender is
  ignored until `/reload`.
- **No made-up chat text.** The "newer version" notice and the Version
  column only show real version numbers from verified members.
- Gear entries must be a single item link; profession names are plain text
  in the pre-typed "Grats" message; the rate-limit table forgets idle senders.
- `/sk debug` shows whether your own data passes guildmates' check, and how
  many senders were ignored.
- Build: GitHub Actions pinned to exact commits, LibDataBroker pinned to a
  commit, and the test workflow has a read-only token.

## v0.2.4 (3 Nov 2026): new tagline

- New tagline: **Height is not a stat.** (in the title bar, the minimap
  tooltip and the AddOns list). Nothing else changed since v0.2.3; still
  not run in game yet.

## v0.2.3 (3 Nov 2026): the new look

A new look for every window. Nothing about sync, saved data or features
changed, so it works alongside guildmates still on v0.2.2. **It hasn't been
run in game yet:** if anything looks wrong, send the `/sk debug` text (and a
screenshot if you can). Settings → **Reduce motion** turns the animations off.

- **Black and gold.** True black surfaces, gold for the active tab, the one
  main button on a screen and key numbers; the gnome's **pink beard** for
  whatever you pick (selected rows, filters, check boxes) and the new crest;
  **dynamite orange only for alerts and sync status** (old data, missing
  enchants, updates, the sync dot). No gradients.
- **One theme file.** `UI/Theme.lua` holds every colour (0–1 RGBA), font,
  size, spacing step, border and motion timing; a test fails if a colour is
  hard-coded anywhere else.
- **Type.** Chakra Petch (free, SIL OFL, bundled) for the title, tabs and
  section headings; the game's Arial Narrow for everything else, with the
  same Korean, Chinese and Russian fallbacks Blizzard uses, so names in any
  alphabet show. If the bundled font can't load, the game font is used and
  `/sk debug` says so.
- **Overview** is now three columns set like a spec sheet instead of six
  equal boxes; the raid countdown is the one big number.
- **Character** details are sections in two columns (talents, professions,
  cooldowns / attunements, reputation) instead of one long text block.
- **Lists:** quiet headers with a sort arrow, right-aligned numbers, a dash
  for missing values, round status dots, row hover, and a sentence when a
  list is empty ("Nobody matches …", "You're not in a guild …").
- **Crafters:** loading placeholders while item names arrive; long item
  names wrap instead of being cut off; the side panel keeps its frame and
  explains itself when nothing is picked.
- **Motion** (AnimationGroups only, 80–180 ms): the window fades and grows
  in, the gold underline glides between tabs, rows highlight on hover, menus
  drop from their button, and the sync dot sends out a ring when new data
  arrives (at most every 8 s). Clicking again mid-animation carries on from
  where it was instead of starting over. Opening with `/sk` or closing with
  Esc stays instant. New setting: **Reduce motion**.
- **Hit areas:** small buttons (Grats, Whisper, chips, check boxes with
  their labels) have click areas of at least 24 px.
- **Fits the screen:** the window shrinks itself if your UI scale and screen
  size would push it off the edge.
- Title bar: crest, sync status with a dot, and a Lua-error count when
  something went wrong (hover for what to do). Own close button.
- `preview/index.html`: a browser mock-up of every window with full, empty,
  loading, error and worst-case data, plus a before/after view.
- Fixed while stress-testing: "1 characters"-style plurals; the status dot
  could drift left when the status text was cut off; the Settings window-size
  buttons ran into the status column.

## v0.2.2 (2 Nov 2026): first release, for launch day

The first downloadable release, and the version the guild starts with when
Forever launches on 4 Nov. It includes everything below (v0.1.0 to v0.2.1
were never released separately). **It hasn't been run in game yet:** it's
built against Blizzard's Forever 1.60.1 interface code and tested with a
simulated client. Please report problems with the `/sk debug` text.

New in this version:


- New **Overview** tab, first in the window: the guild at a glance in six
  cards, each with a button to the place where you can act on it.
  - **Guild**: members, roughly how many players, online, online with Short
    Kings, shared data, and levels by band.
  - **Raids**: days until 9 Dec; Barrow Deeps and Hyjal (no attunement,
    level 60 count); Onyxia attuned / not / unknown and amulets not in bags.
  - **Data health**: no data, older than a week, profession windows not
    opened, old addon versions.
  - **Professions**: characters per crafting profession, how many at 300,
    professions nobody has, gathering counts.
  - **Recipes**: total, crafters, and recipes only one character knows.
  - **Recent milestones**: level-ups, profession 75/150/225/300, Onyxia
    attunement and new recipes, with a **Grats** button that pre-fills guild
    chat. Worked out locally, kept on your computer only (last 50), never sent.
- The window opens on the Overview once, then remembers your last tab.
- Setting: **Record guild milestones (Overview)**.
- Roster: *Oldest first* view (used by the Data health card).
- Fixed: buttons are explicitly enabled when created (the test stub could
  treat a never-enabled button as disabled).

## v0.2.1 (included in v0.2.2)

Launch readiness, after reviewing the GPT, Manus and Perplexity plans
(`docs/PLAN-REVIEW.md`).

- **Attunements match Forever's first raid wave** (Blizzard's raid overview):
  Barrow Deeps and Hyjal Summit need **no attunement**; Onyxia's Lair needs
  the Drakefire Amulet quest **and** the amulet in your bags. Members with the
  quest done but the amulet banked get an orange "!" and "Drakefire Amulet not
  in bags". Molten Core, Blackwing Lair and Naxxramas are hidden until they're
  announced. The raid picker shows raid sizes.
- **`/sk debug` for launch day:** a "Live-client checks" block at the top
  (interface number, whether your character's GUID stays the same between
  logins, the addon-message sender format, whether the profession window
  lists unlearned recipes, whether the calendar works, error count), and the
  **last 10 Lua errors** caught in Short Kings code, so problems show up even
  without an error addon. One failing part no longer stops the rest.
- **Sync safety:** messages over 32 KB are refused before unpacking (a large
  crafter profile is about 11 KB), oversized messages are never sent, and
  each guildmate is limited to 60 messages a minute.
- **Sharing preview** in Settings: "What guildmates see from you", built from
  the same public copy that is sent, plus what is never shared and a reminder
  that copies already sent stay until replaced.
- **Old data is labelled:** data more than a week old shows in orange in the
  Roster's Data column, with "may be out of date" in the tooltip and on the
  Character tab. Crafters tooltips say when a crafter's recipes were recorded.
- **Copy as text** (for Discord): a **Copy** button on the Roster (the list
  as shown, including the raid view) and on the Crafters side panel. Plain
  text, no colour codes; notes are never included, and your own gear and
  talents are left out if you don't share them.
- The Roster counter says when a newer Short Kings is out ("Short Kings 0.2.2
  is out (you have 0.2.1)").
- Mockups updated (Copy buttons, raid sizes, Settings preview and the
  tooltip setting that was missing from the v0.2.0 picture).

## v0.2.0 (included in v0.2.2)

- New **Crafters** tab: search an item or recipe name (3+ letters), see one
  row per recipe with icon, quality-coloured name, profession and
  "N crafters (N online)". Click a result for the crafters, online first,
  with skill level, "alt of X" or "on <alt>", and a **Whisper** button.
  **Post to guild chat** pre-fills the chat box; you press Enter.
- **"Crafted by" on item tooltips**: "Short Kings: Bramble (online), Dabble
  +2 more". Setting: *Show guild crafters in item tooltips* (on by default).
- `/sk debug` reports the crafter index, the tooltip hook and name loading,
  and probes every new API.

## v0.1.2 (included in v0.2.2)

- Roster: a **Raid** picker (*All raids*, Onyxia's Lair, Molten Core,
  Blackwing Lair, Barrow Deeps, Hyjal Summit, Naxxramas). With a raid picked:
  an **Attuned** column (yes / no / unknown), **All / Attuned / Not attuned /
  Unknown** filter buttons, a counter ("23 attuned · 9 not · 6 unknown"), a
  **Max level only** box (on by default), one row per character, and
  "alt of X" in the tooltip. The choice is remembered.
- Character: **Ask for latest** asks the character (or their online alt)
  for fresh data. Works only while they're online with Short Kings, at most
  once every 30 s. The answering player's addon re-reads their character first.
- **Faster updates:** your changes are announced 30 s after they happen
  (was 60 s).
- Fixed "Updated now ago" on the Character tab (now "Updated just now").

## v0.1.1 (included in v0.2.2)

- Roster: **status dots** (online with addon / without / offline), a **Ver**
  column with "needs an update", **alts grouped under their main**, public
  and officer **notes** in tooltips and search.
- Character: **missing-enchant markers**, an alts list, notes, and a
  **Make this my main** button.
- **Cooldowns** stay accurate without opening the profession window.
- **Privacy**: choose whether to share your gear/talents and your recipes.

## v0.1.0 (included in v0.2.2)

- Collects, for every character you log in on: name, class, race, level,
  guild rank, talents (points per tree plus each talent), equipped gear with
  item links, average item level, professions and skill levels, known recipes
  (scanned when you open a profession window), profession cooldowns,
  reputations and attunements.
- Shares that data with guildmates who also have the addon
  (hash-then-fetch over the guild addon channel).
- Window (`/sk` or the minimap button) with **Roster**, **Character** and
  **Settings** tabs, in the Short Kings plum, magenta and ember colours.
- `/sk debug` gives a copyable report of what the addon can see on your client.
