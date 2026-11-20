# OXM (oxm.gg) compared with Short Royalty (20 Nov 2026)

The guild pointed at OXM and the owner asked for "something exactly like
this". Read on 20 Nov: the homepage, the setup guide, the whole FAQ, and the
split-roster demo (`/preview/split-roster/demo-split-1`). Nothing built.

## What OXM is

- A **website plus a Discord bot**, not an in-game addon. "OXM never reads
  the game." It already supports **WoW Forever** (forever.oxm.gg).
- **Free**, run by the raiding guild *Progress*, paid for by donations
  (about €450 a month for hosting). 150,000+ raiders, 3,500+ guilds.
- Sign-in is through **Discord**. A guild is tied to a Discord server, and
  Discord roles decide who gets in.
- Gear comes from Blizzard's **Armory** (Battle.net sync every ~12 h), or by
  pasting an export from the WoWSimsExporter addon.
- Things reach the game only by **copy and paste**: the MRT raid-group
  string, a Gargul soft-reserve string, WeakAura assignment strings.

## The split-roster demo (the page they linked)

- A raid ("Wed · Feb 11", split "Alpha") with **groups of five**, named
  (Physical 1, Physical 2, Caster 1, Caster 2, Healer 1), up to 25 slots.
- **Drag players** from an *Available* panel into the groups. The panel is
  split into Mains, Clones and Alts, with **PRIO** and **PUG** tags, a
  search box and filters (All / Available / Partly).
- Counts at the top: 20 / 25, mains 10, and tanks / healers / melee /
  ranged. Each player shows their spec and a type badge (M main, C1/C2
  clone, A alt).
- Lists for **Late** (with a time), **Early** (leaving early) and
  **Absent**. A character already on another raid that evening shows
  "Another char on this roster".
- Buttons: **Announce** (posts to Discord), **Invite** (raid invites),
  **MRT** (copies the groups for the MRT addon), **Assignments**.
- Raid settings: guild / community / PUG, manual or sign-up, loot mode
  (loot council, soft reserve, roll), confirmations, and "DM review" (the
  bot messages players).

## Feature by feature

Effort: S = a day or less, M = a few days, L = a week or more.

| OXM | Short Royalty today | Inside an addon? | Effort |
|---|---|---|---|
| Discord sign-ups, bot, announcements, DMs | Copy for Discord / Import (v0.10.0) | **No.** Addons can't reach the internet | n/a |
| Website, phone app, Discord login | The in-game window | **No** | n/a |
| Gear from the Armory, WoWSimsExporter import | Read **live from the game** and shared | Better in game | done |
| Raid sign-ups, tentative, decline | Yes (v0.8.0) | Yes | done |
| **Split roster: groups of 5, drag and drop** | In / Bench only (v0.10.0) | **Yes** | M |
| Available panel: mains / alts, PRIO / PUG tags | Alts linked; Officers view (v0.10.1) | Yes | S |
| Late / Early / Absent marks on a raid | No | Yes | S |
| **Absence calendar** (incl. "never Tuesdays") | No | Yes | M |
| Several raids or splits a night, "another char on this roster" | One raid per event, alts warned in readiness | Yes | M |
| **Invite** everyone on the roster | No | Yes (`C_PartyInfo.InviteUnit`, in Forever's docs; maybe one click per invite, to confirm in game) | S |
| **MRT export** of groups | No | Yes, and the addon can probably **set the groups in game** itself (`SetRaidSubgroup`/`SwapRaidSubgroup`, used by Blizzard's own Forever raid window; to confirm in game) | S |
| Raid schedule, recurring raids | Calendar (v0.10.2); owner said no auto-schedule | Yes | M |
| **Boss assignments** with arena maps, templates | No | Text assignments: yes (M). Drawn maps: L | M–L |
| WeakAura assignment strings | No | Possible, needs each WA's format | L |
| **Auto-split solver** (class balance, roles, loot) | No | Yes, a simpler one | L |
| Soft reserves, Gargul export | **Reserve+** (v0.9.0): bonus points, in game | Yes | done |
| Loot council, loot history, RCLootCouncil import | Loot night and history in Reserve+ | Partly | M |
| **BiS lists**, gear planner (EP weights) | No | BiS lists: M; planner: L | M–L |
| Guild bank requests and gold loans | No | Yes | M |
| Recruiting, guild finder, PUG board | No | **No** (outside the guild) | n/a |
| Attendance | Yes (v0.8.0, shared v0.8.1) | Yes | done |
| Roles, notes, alts for officers | Yes (v0.10.1) | Yes | done |

## What Short Royalty has that OXM doesn't

- It **reads the game itself**: gear, talents, professions, recipes,
  attunements, cooldowns, who's online, who's in the raid group. OXM only
  knows what the Armory or a pasted export says.
- **Item tooltips** (crafters, who wears it, reserves). OXM: "does not
  publish your lists to an in-game addon or show BIS owners on item
  tooltips."
- Everyone works **in game**: no account, no Discord login, no website.

## Recommendation

1. **Don't rebuild OXM.** Most of what makes it OXM (Discord bot, website,
   Armory, recruiting, PUG board) **can't run inside an addon**, and the
   rest is years of work by another team. It's also free and already
   supports Forever. We copy no code, design or art either way; ideas are
   fine.
2. Two sensible paths:
   - **A. Use both.** OXM for Discord sign-ups and planning, Short Royalty
     for everything in game. Bridge them by paste: OXM's MRT and Gargul
     strings already go into the game. We could read OXM's MRT string to
     set groups in game, and add a "Copy roster for OXM" if their import
     takes one (to check). Least work, gets the Discord part they wanted.
   - **B. Build the raid-night parts of OXM inside Short Royalty**, in this
     order (each released for testing):
     1. **Split roster**: groups of 5 with drag and drop from an
        Available list (mains, alts, PRIO/PUG tags), role counts,
        Late / Early / Absent marks, "another character on this raid".
        Everyone sees their group. (M)
     2. **Set groups in game**: an officer leading the raid presses one
        button and the addon invites people (one click each, the game
        requires it) and moves them into those groups. (S–M)
     3. **Absences**: members mark nights they can't make (once, or every
        week); officers see it on the roster and calendar. (M)
     4. **Boss assignments** as text per boss (tanks, interrupts, healers),
        shown to the people assigned, with templates. (M)
     5. **Auto-split**: fill a roster from sign-ups by roles, mains first,
        class balance. (L)
     6. **BiS lists** per class and spec, feeding Reserve+ and loot. (M–L)
3. My suggestion: **A for Discord**, plus **B1–B3** inside Short Royalty,
   because the game's own data (online, in the group, gear) is where an
   addon beats a website. Then see what the guild still misses.

## Questions for the owner

1. **Path:** A (use OXM for Discord and planning), B (build it in the
   addon), or A + B1–B3?
2. For B1, **how many raid groups**: same as the raid size (Barrow Deeps
   10 = 2 groups, Hyjal 20 = 4, Onyxia 40 = 8)?
3. Should members see **which group** they're in, or only In / Bench?
4. Is "split" needed (two raid teams on the same night)?
