# Raid sign-ups and attendance (plan, 15 Nov 2026)

Nothing built yet. Waiting on the owner's go-ahead (questions at the end).

## The request (Guild Master, relayed 15 Nov)
> Raid signups in game, with attendance tracking, including being able to
> see people who were signed and online for the raid but weren't actually
> in the raid (i.e. people on the bench). This is stuff that I'd normally
> track manually in a spreadsheet.

## Owner's decisions (15 Nov)
- **No Blizzard calendar.** v0.4.0's "not set up right" meant it interacted
  weirdly with the calendar, and making everything in the calendar made the
  addon feel unnecessary. Raids are **made and signed up for in the
  addon**. This replaces PLAN.md section 6's calendar design.
- **Spreadsheet columns:** *On time, whole raid* · *Late / didn't attend
  the whole raid* · *Didn't attend*, plus **Bench** as a separate tick.

## What v0.4.0 solved, and what we keep from it
v0.4.0 (tag `v0.4.0`, removed in v0.4.1) read sign-ups from the calendar and
showed role, spec, item level and attunement per person, role counts, a
readiness line (missing tanks/healers, not attuned, same player on two
characters) and a Copy button. **We keep the line-up and readiness ideas**
(and can reuse that code from git history). **We drop** everything that
touched the calendar: reading events, opening them, title keywords.

It never had: making raids, attendance, bench, history, spreadsheet export,
officer-only controls. Those are the new work.

## How it would work

### 1. Officers make a raid
- **Raids** page in the sidebar's Guild group. Officers get **New raid**:
  pick the raid from a list (Barrow Deeps, Hyjal, Onyxia), date, start time,
  and optionally a size. **No free text** at first (titles and notes would be
  the first free text on the wire; that's a security review of its own).
- Who counts as an officer: **checked by every receiver**, not just the
  sender, so nobody can fake it. The game tells any client what a rank may do
  (`C_GuildInfo.GuildControlGetRankFlags(rankOrder)`, and the sender's rank
  from the roster). Rule: "ranks that can read officer chat" (to confirm in
  game which flag that is). Officers can edit or cancel raids they made; the
  Guild Master can edit any.

### 2. Members sign up in the addon
- On the Raids page (and a small "New raid on Friday" line on the Overview):
  **Sign up / Tentative / Can't come**, and the role (Tank / Healer / DPS,
  defaulting to a guess from talents).
- Everyone with the addon sees the list: name, status, role, spec, item
  level, attunement, role counts, readiness. A sign-up can only come from
  the player themself; officers can also add or mark someone by hand.

### 3. Sharing without a server
- New addon messages, all small and checked like profiles: **raid** (made
  or changed by an officer) and **sign-up** (one player, one raid, newest
  wins). Everyone stores them and passes them on with the existing
  "what do you have / I have newer" exchange, so a raid reaches people who
  log in after the officer has gone offline.
- Old raids are deleted after 90 days (attendance records stay with the
  officers).

### 4. Attendance during the raid
Runs on the game of any officer who is in the raid group:
- at the start time and every few minutes after it (between pulls, never
  during chat lockdown), note **who is in the raid group**
  (`GetRaidRosterInfo`, used by Blizzard's own raid window in the Forever
  UI) and **who in the guild is online** (the roster we already read);
- on each boss kill as well.

After the raid (or when the officer presses **End raid**), each guild member
gets one result:

| Column | Rule (proposed, adjustable) |
|---|---|
| **On time, whole raid** | In the group within 10 min of the start and until the end (gaps under 10 min ignored) |
| **Late / not the whole raid** | In the group, but joined later or left earlier than that |
| **Didn't attend** | Signed up (or tentative) and never in the group |
| **Bench** tick | Signed up, **online during the raid**, and not in the group. Suggested automatically; the officer can tick or untick it |
| (extra) Came without signing up | In the group but not signed up: counted as attended, marked |

Members who said **Can't come** go in their own list, not "Didn't attend"
(tell the owner; easy to change).

### 5. History and the spreadsheet
- Saved on the officer's computer per raid: date, raid, each name, column,
  bench tick, minutes in the raid.
- Raids page, officers only: the last raids, and per member over 30/60/90
  days (on time %, late, missed, benched).
- **Copy as spreadsheet**: tab-separated text (columns: Date, Raid, Name,
  On time, Late, Didn't attend, Bench) that pastes straight into Google
  Sheets or Excel, for one raid or the whole history.
- Later, if wanted: officers share attendance records with each other.

### Honest trade-offs of dropping the calendar
- Members **without the addon** (14 of 46 right now) can't see raids or sign
  up. Officers can add them by hand, and attendance still works for them
  (the raid group and the roster come from the game).
- A raid only spreads while someone who has it is online. With 32 members
  on the addon that's rarely a problem.

## Steps (each one checked in game before the next)
1. **Probe release** (small): `/sr debug` gains a "Raid checks" block:
   `C_GuildInfo.IsGuildOfficer`, the permission flags per rank, the
   sender's rank from the roster, `GetRaidRosterInfo` in a group (a
   dungeon group works), whether the guild roster's "online" still reads
   inside an instance, and lockdown. **The Guild Master should run it too**
   (the owner's report says "Can view officer notes: no", so the owner
   isn't an officer).
2. **v0.8.0 Raids and sign-ups**: New raid (officers), sign-up buttons,
   line-up and readiness, sharing.
3. **v0.8.1 Attendance**: recording, End raid, history, Copy as spreadsheet.
4. Later: reminders before a raid, "Invite everyone signed up", sharing
   attendance between officers, free-text notes.

Raids open **9 Dec**: step 1 this week, step 2 the week after, step 3
before the first raid. A guild dungeon run can test step 3 early.

## Questions for the owner
1. Who may make raids: every officer rank, or only the ranks you choose?
2. Left early: same column as late? (Proposed: yes, "Late / not the whole
   raid".)
3. Go ahead with step 1?
