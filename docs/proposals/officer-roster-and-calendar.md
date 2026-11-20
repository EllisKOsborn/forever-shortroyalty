# Officer roster management and raid calendar (review, 20 Nov 2026)

A guild officer asked for two views (message relayed by the owner on
20 Nov). This compares each point with what Short Royalty v0.9.4 already
does, and proposes what to build. **Nothing here is built yet.** Loot is
handled separately (Reserve+, v0.9.0; Nura's points).

## What they asked for, and what exists

### Roster management

| Ask | Today (v0.9.4) | Gap |
|---|---|---|
| See all members across all ranks, with their characters and alts | **Roster** page: everyone, every rank, sortable and searchable. Alts fold under the main **automatically, but only once each alt has logged in with the addon**. Alt rank is recognised | Officers can't link alts by hand, so alts that never ran the addon stay separate. Not an officer-only view |
| Assign one or more roles (Tank, Healer, DPS) per player or character | Each player picks **one** role when signing up (remembered per character; guessed from talents until picked) | Officers can't set roles, and there's only one role per character |
| Comments and notes on players | Roster shows Blizzard's **guild note** and **officer note** (officer note only if your rank can read it), read-only | No notes of our own. Blizzard's officer note is short and only editable in the guild window |
| Build and manage the raid roster with a clear overview | Each raid's line-up: who signed up, role, spec, item level, attunement, counts, warnings | Officers can't pick who's **in**, who's **bench**, or groups. Members can't see "you're in / benched" |
| Later: attendance in this view | Attendance tab has per-raid results and 30/60/90-day totals (shared between officers since v0.8.1) | Not shown in the Roster |

### Raid calendar and sign-ups

| Ask | Today (v0.9.4) | Gap |
|---|---|---|
| A calendar like retail | A **list** of upcoming raids, with sign-up buttons | No month grid |
| Manual scheduling | **Yes**: New raid (officers and raid leaders, `/sr officer`) | Can't edit a raid's time (cancel + remake), no title or notes |
| Automatic scheduling (e.g. publish the next raid 5 days ahead) | No | Needs a saved weekly schedule (below) |
| Discord: publish there, sign up there, synced both ways | **No, and the addon can't do it on its own** (below) | Needs a separate program |
| Attendance = signed up **and online at the start** of the raid | Recorded while an officer is **in the raid group**: on time / late / didn't attend, Bench = signed up and online 30+ min but not in the group | Not "online at the start" as such, and nothing is recorded if no officer is in a raid group |

## Discord: the honest answer

WoW addons **can't reach the internet**: no Discord, no website, nothing.
Blizzard blocks it. The addon can only talk to other players' addons in game
and save a file on the player's own computer when they log out or `/reload`.

Two-way sync would need **two extra pieces outside the game**:
1. a **Discord bot** running somewhere all the time (a small server, or
   paid hosting), and
2. a **companion program** on an officer's PC that reads the addon's saved
   file and writes sign-ups back into it.

Even then, sign-ups made in Discord would only reach the game when that
officer **logs in or types `/reload`**, and the game's sign-ups would only
reach Discord after they log out or reload. It's how WarcraftLogs and the
TSM desktop app work, so it's allowed, but it's a separate project, it
breaks this addon's "no server" design, and someone has to keep the bot and
PC running.

**Recommendation:** keep the **addon as the one place to sign up**, and add
a **"Copy for Discord"** button on each raid: a ready-made announcement
(raid, date and time, who's signed up by role) that an officer pastes into
Discord. If the guild still wants two-way sync after that, plan it as its
own project.

## Proposed build (in order)

1. **Attendance "online at the start"** (small). At each raid's start time,
   any officer with `/sr officer` on who's online notes who in the guild is
   online, **no raid group needed**. New column **Online at start**; shared
   between officers like the rest of attendance. The in-group tracking
   (on time / late / bench) stays as extra detail.
2. **Raid schedule** (small–medium). Officers save the weekly raid nights
   (raid, day, time). Any officer's game creates the next one automatically
   **5 days ahead** (the number is a setting). The same raid can't be made
   twice, even if several officers log in. Catch: an officer has to log in
   at some point in those 5 days.
3. **Officer roster** (medium–large), a new **Officers** tab on the Roster
   page (with `/sr officer`):
   - **roles**: officers tick Tank / Healer / DPS (several allowed) per
     character; sign-ups default to them;
   - **officer notes**: our own notes per player, any length, shared only
     between officers (by whisper, like attendance);
   - **alts**: officers link a character to its main by hand;
   - **attendance %** column (from the Attendance totals).
4. **Raid roster builder** (medium). On each raid: officers mark signed-up
   players **In** or **Bench** (and later groups 1–8). Members see "You're in"
   or "You're on the bench". Counts by role update as you pick.
5. **Calendar month view** (medium). A month grid on the Raids page with
   raids on their days; click one to open it. The list stays.
6. **Copy for Discord** (small), as above.

## Questions for the officers

1. **Discord:** is a "Copy for Discord" announcement enough, or is two-way
   sync a must (with the bot and companion program it needs)?
2. **Attendance:** should "signed up and online at the start" **replace**
   on time / late / didn't attend, or sit beside it?
3. **Roles and notes:** officers only, or can members see the roles
   officers gave them? (Notes would stay officers only.)
4. **Raid roster:** should members see whether they're in or on the bench?
5. **Schedule:** the raid nights and times (e.g. Wed and Sun, 20:00), and
   how many days ahead to publish (5?).
6. **Order:** which of 1–6 first? Raids open on 9 Dec.
