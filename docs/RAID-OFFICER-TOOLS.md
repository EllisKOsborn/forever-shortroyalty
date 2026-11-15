# Raid sign-ups and attendance for officers (proposal, 15 Nov 2026)

Not built. A plan to talk through with the owner and the Guild Master (GM).

## The request (GM, relayed 15 Nov)
> Raid signups in game, with attendance tracking, including being able to
> see people who were signed and online for the raid but weren't actually
> in the raid (i.e. people on the bench). This is stuff that I'd normally
> track manually in a spreadsheet.

## What v0.4.0 already solved (built 7 Nov, removed in v0.4.1)
The code is in git history (v0.4.0 tag: `UI/RaidsTab.lua`, `Core/Raids.lua`,
the Compat calendar layer). It never had an in-game test.

| GM needs | v0.4.0 | Notes |
|---|---|---|
| Sign-ups in game | **Half** | Read Blizzard's calendar: who signed up, tentative, declined, standby. Signing up itself still happened in Blizzard's calendar window |
| Who's coming, with role/spec/ilvl/attunement | **Yes** | Role counts, readiness line (missing tanks/healers, not attuned, enchants, same player on two characters) |
| Members without the addon | **Yes** | The calendar is Blizzard's, so everyone counts |
| Copy the line-up as text | **Yes** | One event, as plain text |
| **Who actually came** | **No** | Never looked at the raid group |
| **Bench** (signed, online, not in the raid) | **No** | Needs the sign-ups + who was online + who was in the group, at raid time |
| **History over weeks** (attendance %) | **No** | Nothing was saved after the session |
| **Into the spreadsheet** | **No** | No export of attendance |
| Officer-only view | **No** | It was a tab for every member |

So the old work covers the **"before the raid"** half (reading sign-ups).
The GM's real pain is the **"during and after"** half, which was
deliberately left out (attendance was item D2, "later").

## What to do differently
1. **Build it for the officers first, not for everyone.** The GM is the
   customer. One **Raids** page in the sidebar's Guild group, shown only to ranks the game says are
   officers (`C_GuildInfo.IsGuildOfficer()`, checked in the Forever source).
   Members don't need to see attendance at all at first (they could later
   get just a Sign up button).
2. **Attendance is the core, sign-up display second.** v0.4.0 was a
   member-facing line-up screen. The new version records each raid.
3. **Keep Blizzard's calendar for sign-ups.** Still the right call: it works
   for people without the addon, it's stored on Blizzard's servers, and the
   addon isn't allowed to create events. Add **Sign up / Tentative / Decline
   buttons** later (the calls aren't restricted), so members don't have to
   open the calendar.
4. **Test the game calls before building**, like v0.2.7 did for
   professions: a small `/sr debug` block first. v0.4.0 was built blind
   and never checked. Same lesson as the levelling tools (built in one go,
   removed in v0.5.6): small steps, each checked in game.
5. **Ask what "not set up right" meant** about v0.4.0, so we don't repeat it.
6. **Match the GM's spreadsheet**: a **Copy as spreadsheet** button
   (tab-separated text that pastes straight into Google Sheets or Excel),
   with the same columns they already use.

## How attendance would work
Runs only on the officer's own game. Nothing new on the sync wire to start
with, so it can't be faked or spammed by others.

**Before the raid** (outside the instance, not in combat): read the
calendar event's sign-up list (the v0.4.0 code: name, GUID, status, plus
the sign-up's `notes`).

**During the raid** (the officer is in the raid group): a snapshot every
few minutes and on each boss kill:
- who is in the raid group (`GetRaidRosterInfo`: name, online, zone);
- who in the guild is online (the guild roster, which we already read).

**After the raid**, each person who signed up gets one of:

| Result | Meaning |
|---|---|
| **Attended** | In the raid group for most of the snapshots |
| **Partly** | Joined late or left early (how many minutes) |
| **Bench** | Signed up or on Standby, **online**, but not in the raid group |
| **No-show** | Signed up, but never online |
| **Declined** | Said no in the calendar |
| **Came without signing up** | In the raid, not on the calendar |

Saved per raid on the officer's computer (date, raid, every name and
result). The Raids page shows:
- the last raids, each with these lists;
- per member over 30/60/90 days: raids attended, benched, no-shows, % ;
- **Copy as spreadsheet** for one raid or the whole history.

**Later, if wanted:** share records between officers (only accepted from
officer ranks, owner copy wins, same rules as profiles); sign-up buttons;
a reminder 15 minutes before; "Invite everyone signed up".

## Things to check in game first (probe release)
- `GetRaidRosterInfo` / `GetNumGroupMembers` exist and work inside a raid
  instance (they're old global functions, not in Blizzard's generated docs).
- Whether the guild roster's "online" stays readable inside an instance.
- Which of these are blocked during combat or "chat lockdown" (Midnight's
  secret values). `C_Calendar.EventGetInvite` is (checked in the source),
  so sign-ups are read before the raid, and snapshots are taken between pulls.
- Calendar event IDs are the same on every officer's client (needed only if
  officers share records).
- `C_GuildInfo.IsGuildOfficer()` is true for the GM's officer ranks.

## Questions for the GM
1. What columns are in the spreadsheet today? (Paste a header row.)
2. What counts as "attended"? Whole raid, or any part? Do late arrivals count?
3. Does bench count as attendance (for loot priority)?
4. Is Blizzard's calendar how people sign up now, or Discord?
5. Only officers see attendance, or can members see their own?
6. Who will be in the raid running the addon: one officer, or several?

## Size and timing
- Probe release: small (a `/sr debug` block), can go out in the next release.
- Raids page with attendance + spreadsheet copy: medium (about the size of
  the v0.3.0 Professions work). Raids open **9 Dec**: probes this week, the
  page the week after, leaves about two weeks for testing with a real raid
  group (a dungeon group can stand in for some checks).
- Sign-up buttons, reminders and sharing between officers: after the first
  real raids.
