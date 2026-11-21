# Security review (3 Nov 2026)

What could someone do to Short Royalty users, on purpose? This covers the
addon code, the sync protocol and how release zips are built. Every attack
below was tried against the stubbed WoW API (`tests/security_spec.lua`).
**None of it has been checked in game yet.**

## The short version

- **No one can run code on your computer or in your game through this
  addon.** Nothing it receives is ever run as code: no `loadstring`,
  `RunScript` or similar anywhere. WoW addons also can't touch files, the
  internet or your account, and can't send chat for you.
- **Nothing private leaks.** Notes, officer notes, gold, bags and chat are
  never sent (checked again: only `guild.profiles` copies go on the wire,
  and the `/sr debug` report and "Copy as text" don't include notes).
- What **was** possible: annoy or mislead people. Before this review,
  someone could break the addon's windows for the whole guild with one
  crafted message, pretend to be a guild member, freeze people's game, or
  put misleading text in their chat. Those are fixed (v0.2.5, below).
- What **is still** possible: a guild member who wants to cause trouble
  can make up profiles for members who are offline. There's no fix short of
  cryptographic signatures, which WoW's Lua can't do sensibly. See "Accepted
  risks".

## Who could attack

1. **A stranger** (any player in the region). Anyone can whisper an addon
   message to anyone, so strangers can reach the addon.
2. **A guild member** running a modified copy of the addon. Only members can
   send on the guild channel.
3. **Whoever controls the build**: GitHub Actions and the libraries the
   release zip downloads. Whatever ends up in the zip runs in everyone's game.

## Found and fixed

| # | Severity | Problem | Fix |
|---|---|---|---|
| 1 | **High** | **One bad profile broke the windows for the whole guild.** Only the top level of a profile was checked. A member could send, say, talent trees as text: the Roster tab crashed for everyone who received it, it was saved, and it was passed on to others by the backfill. | `Merge.Validate` now checks every field's type, size and count (e.g. ≤ 1,500 recipes per profession, ≤ 64-character names, real numbers only). Anything off is refused. Fields from newer versions are still allowed if they're plain values. |
| 2 | **High** | **A stranger could pretend to be a member.** If a sender's name didn't match the roster exactly, the addon fell back to matching the first word. First names aren't unique in Forever, so a stranger called "Bob Jones" could whisper a fake profile as our "Bob Smith" and have it treated as Bob's own. | A first-word match is accepted only on the guild channel (where only members can send) and remembered for the session; a whisper with a first-word match is accepted only from a sender already confirmed that way. Exact roster matches work as before. |
| 3 | Medium | **Freezing someone's game.** A 32 KB message can decompress to about 13 MB (a "zip bomb"), taking around a second of CPU each, 60 times a minute, and it was decoded **before** checking who sent it, so even strangers could do it. A bomb profile would also be saved, bloating SavedVariables. | Messages are dropped before decoding unless the sender could be a guild member, and only guild and whisper channels are accepted. Anything that decompresses to over 256 KB is refused (a worst-case real profile is under a quarter of that). After 3 bad messages, a sender is ignored until `/reload`. |
| 4 | Medium | **Misleading text in chat.** The "a guildmate has a newer version" notice printed the version text as sent, and before checking the sender. A stranger could make your chat say "Short Royalty 9.9 … get the fix at evil-site". | Version text must look like a version (`0.2.4`, `v0.2.4-3-gabc123`, `dev`), at most 32 characters, and the notice only appears for verified guild members. The same check applies to the Version column. |
| 5 | Low | **Fake links on the paper doll.** Gear entries were passed straight to the item tooltip and shift-click. | A gear entry must be exactly one item link. |
| 6 | Low | **Odd text in "Grats" messages.** Profession names from other players went into the pre-typed guild-chat text with links and colours intact. | Stripped to plain text (40 characters max) first. You still see the text and press Enter yourself. |
| 7 | Low | The rate-limit table remembered every sender forever. | Idle senders are forgotten. |
| 8 | Medium | **Build pipeline.** GitHub Actions used movable tags (`@v2`), and LibDataBroker was fetched from whatever its (unmaintained) repo's latest commit is. If either were taken over, a release zip could include someone else's code. The test workflow also had more permissions than it needs. | Actions pinned to exact commits; LibDataBroker pinned to the commit we already ship; the test workflow's token is read-only. |

`/sr debug` now shows **"Passes guildmates' safety check: yes"** (if it ever
says no, guildmates are refusing your data, and the reason is shown) and how
many senders were ignored this session.

## Accepted risks (can't be fixed, or not worth it)

- **Guild members can make up data about members who are offline.** A
  modified addon can send a fake "relayed" copy of anyone's profile (fake
  gear, fake attunement). Merge rules already limit this: the real owner's
  copy always wins as soon as they log in, and our own characters are never
  overwritten. Signing profiles would need public-key cryptography in Lua
  and a way to share keys, which is out of proportion for a 50-person guild.
  If someone does this, `/sr debug` and the Roster's "updated" times help
  spot it; remove them from the guild.
- **A guild member can still cost you about 3 seconds of CPU per session**
  (three bad messages before they're ignored).
- **LibDBIcon** is still fetched from the WowAce trunk when the zip is built
  (pinning needs a WowAce tag name, which couldn't be checked from here). It's
  the standard source most addons use.
- **Names with colour codes.** Faction, talent and profession names from
  other players can contain WoW colour/icon codes and show coloured in the
  Character tab. Harmless (FontStrings can't be clicked), so left alone.

## Checked and fine

- **Spoofed sender GUIDs:** a message's claimed GUID is only believed when
  the name the game reports agrees.
- **Overwriting your own characters:** impossible; `SK.DB.account` entries
  are skipped before any merge.
- **Future timestamps:** more than 5 minutes ahead is refused.
- **Flooding:** 60 messages per sender per minute; outgoing replies are
  de-duplicated per requester; requests are capped at 60 profiles.
- **Chat:** the addon never sends chat. "Post to guild chat" and "Grats" only
  pre-type text; you press Enter.
- **Vendored libraries** are byte-for-byte the upstream files (checked 3 Nov):
  LibSerialize v1.2.3, LibDeflate (upstream main, 1.0.2), and AceComm,
  ChatThrottleLib, CallbackHandler and LibStub from Ace3. LibSerialize's
  deserializer only builds plain values and tables.

## For future changes

- Any new profile field needs an entry in `Merge.FIELDS`, or it falls under
  the "plain extra field" rule and the UI must treat it as untrusted.
- Anything shown from another player's data is untrusted text. Never pass it
  to `loadstring`, `SetHyperlink` (unless it passed `Merge.IsItemLink`), or
  chat without stripping it.
- Keep `tests/security_spec.lua` green; add a case for every new message type.

## Addendum (7 Nov 2026, v0.3.6–v0.4.0)

New profile fields, all checked in `Merge.FIELDS` and display-only:
- `roles` (raid roles). `claims` ("This is my alt", v0.3.6) is still
  checked because v0.3.6 clients send it, but v0.4.0 ignores it. Officer alt
  links were built and removed before release (the officer flag would have
  been self-asserted).
- SQ/SO `a` (who runs the addon) only sets a local "seen" mark, never a
  version, so it can't trigger "newer version" notices.
- The Raids tab reads Blizzard's calendar (server data); no sync involved.

## Addendum (15 Nov 2026, v0.8.0 raids)

Two new GUILD-only message types, `RB` (raids and sign-ups) and `RD` (a
fingerprint per raid). Checked in `Core/RaidBoard.lua` and tested in
`tests/security_spec.lua` and `tests/v080_raids_spec.lua`:
- A raid is kept only if its creator (`by`) and whoever changed it (`eb`)
  are in an officer or raid leader rank **in the receiver's own roster**.
  Ranks come from Blizzard's roster, so a message can't promote anyone.
- Like relayed profiles, relayed items can't prove who wrote them: a member
  could forge a sign-up for someone else, or replay an officer's raid with a
  newer time. Accepted risk for a guild tool (same as profile relays); the
  damage is a wrong line-up entry. Attendance doesn't trust sign-ups for
  anything but the "Signed up" column and the bench suggestion.
- No free text: raids are a key from `Data/Attunements` plus numbers;
  sign-ups are y/t/n and a role from a fixed list. Only known fields are
  stored. Limits: 30 raids, 100 sign-ups per raid, 120 items per message,
  60 raids per digest, timestamps at most 5 minutes ahead, raids at most 60
  days ahead.
- Attendance is local only and never sent. (v0.8.1: see below.)

v0.8.1: attendance is shared between officers with `AR` (one record) and
`AQ` (what I hold), **WHISPER only**, sent only to officer/raid leader ranks
and accepted only from them, and only by a receiver who is one
(`Sync/AttendanceSync.lua`). `Attendance.ValidRecord` checks every field
(raid key, numbers, at most 120 people, sign-ups y/t/n, Bench `{v, u}`);
`Attendance.Copy` keeps only known fields. A rogue officer could send a
fuller fake record; accepted risk (officers are trusted by the guild).

## Addendum (18 Nov 2026, v0.9.1 Short Words witnesses)

WP / WQ / WA (`Sync/WordsSync.lua`) carry only day numbers, GUIDs and colour
patterns (`WS.Rows`: 1–6 rows of five 0/1/2, a green row only last, ≤ 41
chars): never letters, nothing that is run, linked or put in chat. Witnesses
store one entry per guild member who sent a WP themselves (bounded by the
roster). WQ lists at most 20 GUIDs; WA maps are read up to 20 entries. A
WA only changes our game for today, for a GUID on our own account, and only
when it has more rows than ours. Accepted risk: a guildmate could answer
with made-up colours and cost someone tries on that day's word.

## Addendum (20 Nov 2026, v0.10.0)

- `RB` gains `pk` (In / Bench choices): kept only if `by` is an officer or
  raid leader in the receiver's roster, the player is a member and the raid
  is known; v must be i, b or "-"; newest wins (`Board.ValidPlace`,
  `MergePlace`). Older versions ignore `pk`.
- Sign-ups may carry `b` (the officer who imported them from Discord):
  accepted only if `b` is a lead rank. Like relayed sign-ups, a forged one
  is possible; accepted risk.
- **Import sign-ups** only parses pasted text into GUIDs from our own roster;
  nothing from the paste is stored or shown except the unmatched lines,
  back to the officer who pasted them.

## Addendum (20 Nov 2026, v0.10.1 officer roster)

`OR` (entries) and `OQ` (what I hold), **WHISPER only**, between officer
and raid leader ranks only (sender, receiver and each entry's `by` checked
against the receiver's roster), like attendance. `OfficerDir.Valid`: keys
`r|n|a:guid`; roles only T/H/D once each; notes at most 300 characters with
no `|` or control characters (so no colours or links can be shown); alt =
a GUID string. Newest wins; 1500 entries at most. Notes are shown only in
the Officers view and its tooltip.


## Addendum (20 Nov 2026, v0.11.0 groups, assignments, away days)

- `RB` gains `gs` (group slots) and `as` (boss assignments). Both are kept
  only if `by` is an officer or raid leader in the receiver's roster and
  the raid is known; newest wins. Slots: group a number 0 to the raid's
  group count, mark one of l/e/a or empty, the player a member
  (`RaidGroups.ValidSlot`, `MergeSlot`). Assignments: the boss name is the
  only typed text: at most 30 characters, no `|` or control characters
  (no colours or links); tasks only from a fixed list; at most 12 lines of
  5 GUID strings; at most 24 blocks per raid (`RaidAssign.ValidBlock`,
  `MergeBlock`). Older versions ignore both.
- Profile field `away` (`Merge.FIELDS.away`): only `d` (at most 40
  strings shaped YYYY-MM-DD), `w` (at most 7 whole numbers 1 to 7) and `u`
  (a finite number). Anyone can say they're away on their own profile
  (that is the point); a forged copy goes through the usual profile hash
  and owner-copy rules.
- **Invite & arrange** only invites and moves names from our own roster and
  the game's own raid list; nothing received is passed to the game as text.

## Addendum (20 Nov 2026, v0.12.0 Discord bot)

- `discord-bot/` is a Cloudflare Worker; the addon still never goes online.
  Every request must carry Discord's Ed25519 signature (checked before the
  body is read as JSON); unsigned requests get 401.
- The only input from the game is the code an officer pastes into
  `/raid-post`: one header and at most 150 lines, each field checked (raid
  id `[\w:-]{3,80}`, raid key lower-case letters, size 1–40, times in a sane
  range, status y/t/n, role TANK/HEALER/DPS, place i/b). Names keep only
  letters, spaces, apostrophes and hyphens (no mentions, markup or links),
  40 characters at most. All bot messages send `allowed_mentions: { parse:
  [] }`.
- `/raid-post` is limited by Discord to Manage Events by default, and the
  bot checks again (Manage Events / Manage Server / Administrator or a role
  in `OFFICER_ROLES`). Sign-up buttons need a `/link`ed character; anyone
  can link any name (accepted: the officer importing sees the list, and a
  player's own in-game sign-up is never overwritten by an import).
- Secrets (bot token, public key, Cloudflare token) live only in GitHub
  secrets and the Worker's secrets; the workflow pins its actions to SHAs
  and wrangler to an exact version.
- Data kept: Discord user IDs, linked character names, sign-ups; raids and
  sign-ups are deleted 14 days after the start.

## Addendum (21 Nov 2026, v0.13.0 roster planner)

- New officer-roster kinds over the existing OR/OQ whispers (officers only,
  sender and `by` checked against the receiver's roster): `t` tiers (exactly
  three of `-mb`), `s` status (`r`, `b` or empty), `d` away days (up to 40
  dates YYYY-MM-DD), `m:<member>:<author>` notes (plain text, 300 characters,
  no `|` or control characters, and **`by` must be the author in the key**,
  so one officer can't write another's note). Older versions reject the new
  kinds without striking the sender. OR now sends at most 60 entries per
  message (notes are long) and still reads 120.
- The level/item level history is local to each officer's game (never sent).

## Addendum (21 Nov 2026, v0.14.0 raids from the calendar, attendance at the start)

- Raid events may carry `rs` (instance keys, at most 60 characters, known
  keys only, no repeats); `raid` must then be its first key, or `tbd` when
  it's empty. Older versions reject `tbd` nights as an unknown raid.
- Sign-ups may carry `w` (when they changed from Signed up): a number not
  after the sign-up's own change time, and never on a "Signed up" answer.
  A player could fake their own `w` (only makes them look worse).
- Groups per instance use slot ids `id@key`: the raid must exist and the key
  must be a known instance.
- Attendance records v2 (officers only, unchanged AR/AQ checks): every list
  is capped at `MAX_PEOPLE` and each value is checked (`o` only "s"/"l", `w`
  numbers, `pb` only true, sign-ups y/t/n). They have no `total`, so older
  versions refuse them instead of misreading them. Online status comes from
  each officer's own guild roster; merging keeps the best result per player.
