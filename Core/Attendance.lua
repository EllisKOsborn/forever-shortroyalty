-- Attendance (v0.8.0): recorded on an officer's or raid leader's own game
-- while they're in the raid group. Stored per guild in guild.attendance =
-- { [raid id] = record }. v0.8.1: shared with the other officers and raid
-- leaders by whisper (Sync/AttendanceSync.lua), never with members, and
-- seen only in the addon (owner, 15 Nov: "We didn't want anything in a
-- spreadsheet anymore").
--
-- Every EVERY seconds (and after each boss), outside combat and chat
-- lockdown, a snapshot notes who is in the raid group and who in the guild
-- is online. Each snapshot stands for the time since the one before it
-- (at most MAX_GAP), counted from the raid's start. After the raid:
--
--   full    "On time, whole raid": in the group within GRACE of the start
--           and missed at most GRACE of the recorded time
--   late    "Late / not the whole raid": in the group, but joined later or
--           left earlier than that (owner: left early goes here too)
--   missed  "Didn't attend": signed up or tentative, never in the group
--   bench   a separate tick: signed up or tentative, and online but not in
--           the group for at least BENCH_MIN (or half the raid if it was
--           shorter). Suggested automatically; officers can change it.
--
-- People who said "Can't come" are listed without a tick. People in the
-- raid who didn't sign up are listed as attended, marked "No".
--
-- v0.14.0 (officer, 21 Nov: "if you signed to a calendar event and are
-- online at the scheduled start time"): no raid group needed. Every
-- officer's or raid leader's game that's online at a raid's start looks at
-- the guild roster: signed up (or tentative) and online at the start =
-- on time; online within LATE_FOR = late (owner's choice); signed up and
-- not online by then = no-show. Sign-ups changed from Signed up to
-- Tentative or Can't come are kept with when (Board.ChangedAt). These
-- records have v = 2; the v0.8.0 group records above still show.
--
--   record v2 = { v = 2, id, by, raid, rs, at, began (first check), last,
--                 snaps (checks), ended (window closed), u,
--                 people = { [guid] = { name, class } }, signed = { [guid] = s },
--                 o = { [guid] = "s" on time | "l" late }, w = { [guid] = changed at },
--                 pb = { [guid] = true (officers had them on the Bench) }, bench }
--
-- Pure parts (tested): NewRecord, AddSnapshot, NewCheck, AddCheck, Rows,
-- Totals, BenchOf, ValidRecord, Merge.
local _, SK = ...

local Att = SK:NewModule("Attendance")
local Compat = SK.Compat

Att.TICK = 15              -- how often we check
Att.MAX_GAP = 10 * 60      -- one snapshot counts for at most this long
Att.GRACE = 10 * 60        -- late / missed time allowed for "on time, whole raid"
Att.BENCH_MIN = 30 * 60
Att.LONGEST = 6 * 3600     -- an open check is closed up to this long after the start
Att.MAX_RECORDS = 200
Att.LATE_FOR = 15 * 60     -- v0.14.0: online this soon after the start = late
Att.ON_TIME = 2 * 60       -- a check this soon after the start counts as "at the start"
Att.ROSTER_BEFORE = 90     -- ask the game for a fresh guild roster this long before
Att.CHANGED_LATE = 86400   -- a sign-up changed less than this before the start

Att.RESULT_NAME = { full = "On time, whole raid", late = "Late / not the whole raid", missed = "Didn't attend",
	declined = "Said can't come" }
-- v0.14.0 records (online at the start).
Att.RESULT_NAME2 = { full = "On time (online at the start)", late = "Late (online within 15 minutes)",
	missed = "No-show (signed up, not online)", maybe = "Tentative, not online", declined = "Said can't come" }
Att.RESULT_SHORT2 = { full = "On time", late = "Late", missed = "No-show", maybe = "Tentative", declined = "Can't come" }
local RESULT_ORDER = { full = 1, late = 2, missed = 3, maybe = 4, declined = 5 }
local SIGNED_NAME = { y = "Yes", t = "Tentative", n = "Can't come" }

---------------------------------------------------------------------------
-- Records (pure)
---------------------------------------------------------------------------
-- An officer's Bench choice for one person: true, false, or nil (automatic).
-- Stored as { v = true|false|nil, u = when } so choices merge between
-- officers (newest wins); a plain boolean is a v0.8.0 record.
function Att.BenchOf(rec, guid)
	local b = rec.bench and rec.bench[guid]
	if type(b) == "boolean" then return b end
	if type(b) == "table" then return b.v end
	return nil
end

function Att.NewRecord(ev, by, now)
	return { id = ev.id, raid = ev.raid, at = ev.at, by = by, began = now, last = nil, ended = nil,
		total = 0, snaps = 0, people = {}, signed = {}, bench = {}, u = now }
end

-- inGroup / online = { [guid] = true }; names = { [guid] = { name, class } };
-- signups = the raid's sign-ups { [guid] = { s, r } } at that moment.
function Att.AddSnapshot(rec, t, inGroup, online, names, signups)
	local from = math.max(rec.last or rec.at, rec.at)
	local dt = 0
	if t > rec.at then dt = math.max(0, math.min(t - from, Att.MAX_GAP)) end
	rec.total = rec.total + dt
	local function person(guid)
		local p = rec.people[guid]
		if not p then
			p = { inS = 0, bnS = 0 }
			rec.people[guid] = p
		end
		local n = names and names[guid]
		if n then p.name, p.class = n.name or p.name, n.class or p.class end
		return p
	end
	for guid, su in pairs(signups or {}) do
		rec.signed[guid] = su.s
		person(guid)
	end
	for guid in pairs(inGroup) do
		local p = person(guid)
		p.first = p.first or t
		p.last = t
		p.inS = p.inS + dt
	end
	for guid in pairs(online) do
		if not inGroup[guid] and rec.signed[guid] then
			local p = person(guid)
			p.bnS = p.bnS + dt
		end
	end
	rec.last = t
	rec.snaps = rec.snaps + 1
	rec.u = math.max(rec.u or 0, t)
	return dt
end

-- v0.14.0: a record of who's online at a raid's start.
function Att.NewCheck(ev, by, now)
	return { v = 2, id = ev.id, raid = ev.raid, rs = ev.rs, at = ev.at, by = by, began = now, snaps = 0,
		people = {}, signed = {}, o = {}, w = {}, pb = {}, bench = {}, u = now }
end

-- One check at time t. online = { [guid] = true }; names = { [guid] =
-- { name, class } }; signups = the raid's sign-ups now; places = the
-- raid's In / Bench ({ [guid] = { v } }). The first check counts as "at
-- the start" when it's late too (an officer who logged in after the start
-- can't tell who was online before them; another officer's record from
-- the start wins when they merge).
function Att.AddCheck(rec, t, online, names, signups, places)
	local first = rec.snaps == 0
	rec.began = math.min(rec.began or t, t)
	for guid, su in pairs(signups or {}) do
		rec.signed[guid] = su.s
		rec.w[guid] = su.s ~= "y" and su.w or nil
		local p = rec.people[guid] or {}
		rec.people[guid] = p
		local n = names and names[guid]
		if n then p.name, p.class = n.name or p.name, n.class or p.class end
		local pl = places and places[guid]
		rec.pb[guid] = (pl and pl.v == "b") or nil
	end
	for guid in pairs(online) do
		if rec.signed[guid] and not rec.o[guid] then
			rec.o[guid] = (first or t <= rec.at + Att.ON_TIME) and "s" or "l"
		end
	end
	rec.last = math.max(rec.last or t, t)
	rec.snaps = rec.snaps + 1
	rec.u = math.max(rec.u or 0, t)
end

local function rows2(rec)
	local rows = {}
	for guid, signed in pairs(rec.signed) do
		local p = rec.people[guid] or {}
		local o = rec.o[guid]
		local result = o == "s" and "full" or o == "l" and "late" or (signed == "y" and "missed")
			or (signed == "t" and "maybe") or "declined"
		local auto = o ~= nil and rec.pb[guid] == true
		local bench = auto
		local set = Att.BenchOf(rec, guid)
		if set ~= nil then bench = set end
		local w = rec.w[guid]
		rows[#rows + 1] = { guid = guid, name = p.name or "?", class = p.class, signed = signed,
			signedName = SIGNED_NAME[signed] or "No", result = result, resultName = Att.RESULT_NAME2[result],
			bench = bench and true or false, benchAuto = auto, inS = 0, bnS = 0, changed = w,
			changedLate = w ~= nil and rec.at - w < Att.CHANGED_LATE, v = 2 }
	end
	table.sort(rows, function(a, b)
		if a.result ~= b.result then return RESULT_ORDER[a.result] < RESULT_ORDER[b.result] end
		return a.name:lower() < b.name:lower()
	end)
	return rows
end

-- One row per person: { guid, name, class, signed, result, bench, benchAuto,
-- inS, bnS }. Sorted by result, then name.
function Att.Rows(rec)
	if rec.v == 2 then return rows2(rec) end
	local rows = {}
	local benchNeed = math.min(Att.BENCH_MIN, rec.total / 2)
	for guid, p in pairs(rec.people) do
		local signed = rec.signed[guid]
		local present = p.first ~= nil
		local result
		if present then
			local missed = rec.total - p.inS
			result = (p.first <= rec.at + Att.GRACE and missed <= Att.GRACE) and "full" or "late"
		elseif signed == "y" or signed == "t" then
			result = "missed"
		elseif signed == "n" then
			result = "declined"
		end
		if result then
			local auto = (signed == "y" or signed == "t") and rec.total > 0 and p.bnS > 0 and p.bnS >= benchNeed
			local bench = auto
			local set = Att.BenchOf(rec, guid)
			if set ~= nil then bench = set end
			rows[#rows + 1] = { guid = guid, name = p.name or "?", class = p.class, signed = signed,
				signedName = SIGNED_NAME[signed] or "No", result = result, resultName = Att.RESULT_NAME[result],
				bench = bench and true or false, benchAuto = auto and true or false, inS = p.inS, bnS = p.bnS,
				first = p.first }
		end
	end
	table.sort(rows, function(a, b)
		if a.result ~= b.result then return RESULT_ORDER[a.result] < RESULT_ORDER[b.result] end
		return a.name:lower() < b.name:lower()
	end)
	return rows
end

-- Counts for a record: { full, late, missed, declined, bench }.
function Att.Summary(rows)
	local s = { full = 0, late = 0, missed = 0, maybe = 0, declined = 0, bench = 0, changed = 0 }
	for _, r in ipairs(rows) do
		s[r.result] = s[r.result] + 1
		if r.bench then s.bench = s.bench + 1 end
		if r.changed then s.changed = s.changed + 1 end
	end
	return s
end

-- Records, newest first. `since` (time) leaves older ones out.
function Att.Sorted(store, since)
	local out = {}
	for _, rec in pairs(store or {}) do
		if not since or rec.at >= since then out[#out + 1] = rec end
	end
	table.sort(out, function(a, b) return a.at > b.at end)
	return out
end

-- Per person over the given records: { guid, name, class, raids, full, late,
-- missed, bench, declined }. "raids" counts every raid they're listed in.
function Att.Totals(records)
	local by = {}
	for _, rec in ipairs(records) do
		for _, r in ipairs(Att.Rows(rec)) do
			local t = by[r.guid]
			if not t then
				t = { guid = r.guid, name = r.name, class = r.class, raids = 0, full = 0, late = 0, missed = 0,
					bench = 0, declined = 0, maybe = 0, changed = 0, changedLate = 0, signedUp = 0 }
				by[r.guid] = t
			end
			t.raids = t.raids + 1
			t[r.result] = t[r.result] + 1
			if r.bench then t.bench = t.bench + 1 end
			-- v0.14.0: signed up at some point (now, or before a change).
			if r.signed == "y" or r.changed then t.signedUp = t.signedUp + 1 end
			if r.changed then t.changed = t.changed + 1 end
			if r.changedLate then t.changedLate = t.changedLate + 1 end
		end
	end
	local out = {}
	for _, t in pairs(by) do
		local asked = t.full + t.late + t.missed
		t.pct = asked > 0 and math.floor((t.full + t.late) / asked * 100 + 0.5) or nil
		out[#out + 1] = t
	end
	table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
	return out
end

---------------------------------------------------------------------------
-- Sharing between officers (v0.8.1): checks and merging (pure)
---------------------------------------------------------------------------
Att.MAX_PEOPLE = 120 -- people in one record
local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
local function str(v, max) return type(v) == "string" and #v > 0 and #v <= max end
local function optFinite(v) return v == nil or (finite(v) and v >= 0) end
local SIGNED = { y = true, t = true, n = true }

-- Is a received record well formed? Everything received is untrusted.
local function validV2(r, now)
	if not str(r.id, 80) or not str(r.by, 64) or not str(r.raid, 20) then return false, "bad id" end
	if r.rs ~= nil and not SK.RaidBoard.ParseKeys(r.rs) then return false, "bad raids" end
	for _, k in ipairs({ "at", "began", "snaps", "u" }) do
		if not finite(r[k]) or r[k] < 0 then return false, "bad " .. k end
	end
	if r.u > now + 300 then return false, "from the future" end
	if not optFinite(r.last) or not optFinite(r.ended) then return false, "bad time" end
	for _, k in ipairs({ "people", "signed", "o", "w", "pb", "bench" }) do
		if type(r[k]) ~= "table" then return false, "bad lists" end
	end
	local function each(list, check)
		local n = 0
		for guid, v in pairs(list) do
			n = n + 1
			if n > Att.MAX_PEOPLE or not str(guid, 64) or not check(v) then return false end
		end
		return true
	end
	if not each(r.people, function(p)
		return type(p) == "table" and (p.name == nil or str(p.name, 64)) and (p.class == nil or str(p.class, 20))
	end) then return false, "bad person" end
	if not each(r.signed, function(v) return SIGNED[v] end) then return false, "bad sign-up" end
	if not each(r.o, function(v) return v == "s" or v == "l" end) then return false, "bad online" end
	if not each(r.w, function(v) return finite(v) and v >= 0 end) then return false, "bad change" end
	if not each(r.pb, function(v) return v == true end) then return false, "bad bench" end
	if not each(r.bench, function(b) return type(b) == "table" and finite(b.u) and (b.v == nil or type(b.v) == "boolean") end) then
		return false, "bad bench"
	end
	return true
end

function Att.ValidRecord(r, now)
	if type(r) ~= "table" then return false, "not a table" end
	if r.v == 2 then return validV2(r, now) end
	if r.v ~= nil then return false, "unknown kind" end
	if not str(r.id, 80) or not str(r.by, 64) or not SK.RaidBoard.Raid(r.raid) then return false, "bad id" end
	for _, k in ipairs({ "at", "began", "total", "snaps", "u" }) do
		if not finite(r[k]) or r[k] < 0 then return false, "bad " .. k end
	end
	if r.u > now + 300 then return false, "from the future" end
	if not optFinite(r.last) or not optFinite(r.ended) then return false, "bad time" end
	local n = 0
	if type(r.people) ~= "table" or type(r.signed) ~= "table" or type(r.bench) ~= "table" then return false, "bad lists" end
	for guid, p in pairs(r.people) do
		n = n + 1
		if n > Att.MAX_PEOPLE or not str(guid, 64) or type(p) ~= "table" then return false, "bad person" end
		if not finite(p.inS) or not finite(p.bnS) or p.inS < 0 or p.bnS < 0 then return false, "bad minutes" end
		if not optFinite(p.first) or not optFinite(p.last) then return false, "bad person time" end
		if p.name ~= nil and not str(p.name, 64) then return false, "bad name" end
		if p.class ~= nil and not str(p.class, 20) then return false, "bad class" end
	end
	n = 0
	for guid, v in pairs(r.signed) do
		n = n + 1
		if n > Att.MAX_PEOPLE or not str(guid, 64) or not SIGNED[v] then return false, "bad sign-up" end
	end
	n = 0
	for guid, b in pairs(r.bench) do
		n = n + 1
		if n > Att.MAX_PEOPLE or not str(guid, 64) or type(b) ~= "table" or not finite(b.u)
			or (b.v ~= nil and type(b.v) ~= "boolean") then return false, "bad bench" end
	end
	return true
end

-- A clean copy with only the fields we know (what goes on the wire, and
-- what is stored from it).
function Att.Copy(r)
	if r.v == 2 then
		local out = { v = 2, id = r.id, by = r.by, raid = r.raid, rs = r.rs, at = r.at, began = r.began, last = r.last,
			ended = r.ended, snaps = r.snaps, u = r.u, people = {}, signed = {}, o = {}, w = {}, pb = {}, bench = {} }
		for guid, p in pairs(r.people) do out.people[guid] = { name = p.name, class = p.class } end
		for _, k in ipairs({ "signed", "o", "w", "pb" }) do
			for guid, v in pairs(r[k]) do out[k][guid] = v end
		end
		for guid, b in pairs(r.bench) do out.bench[guid] = { v = b.v, u = b.u } end
		return out
	end
	local out = { id = r.id, by = r.by, raid = r.raid, at = r.at, began = r.began, last = r.last, ended = r.ended,
		total = r.total, snaps = r.snaps, u = r.u, people = {}, signed = {}, bench = {} }
	for guid, p in pairs(r.people) do
		out.people[guid] = { name = p.name, class = p.class, inS = p.inS, bnS = p.bnS, first = p.first, last = p.last }
	end
	for guid, v in pairs(r.signed) do out.signed[guid] = v end
	for guid, b in pairs(r.bench) do
		if type(b) == "boolean" then out.bench[guid] = { v = b, u = 0 } else out.bench[guid] = { v = b.v, u = b.u } end
	end
	return out
end

-- Merge a received record into what we hold. The recording with more checks
-- wins (two officers may record the same raid; an ended copy beats a
-- running one with as many); Bench choices merge per person, newest wins.
-- `recording` = we are writing this record right now (keep our body).
-- Returns the record to store (or nil to keep ours unchanged), changed.
local function merge2(have, inc)
	local changed = false
	-- Online at the start beats late beats not seen, from either copy.
	for guid, v in pairs(inc.o) do
		local mine = have.o[guid]
		if inc.signed[guid] and (not mine or (mine == "l" and v == "s")) then have.o[guid] = v; changed = true end
	end
	-- The copy changed last knows the final sign-ups.
	if inc.u > have.u then
		for _, k in ipairs({ "signed", "w", "pb" }) do
			have[k] = {}
			for guid, v in pairs(inc[k]) do have[k][guid] = v end
		end
		changed = true
	end
	for guid, p in pairs(inc.people) do
		if not have.people[guid] then have.people[guid] = { name = p.name, class = p.class }; changed = true end
	end
	if inc.began < have.began then have.began = inc.began; changed = true end
	if inc.ended and not have.ended then have.ended = inc.ended; changed = true end
	if inc.snaps > have.snaps then have.snaps = inc.snaps; changed = true end
	return changed
end

function Att.Merge(have, inc, recording)
	if not have then return Att.Copy(inc), true end
	if (have.v == 2) ~= (inc.v == 2) then
		-- A v0.8.0 group record and a v0.14.0 one for the same raid: keep ours.
		return have, false
	end
	local changed = false
	local out = have
	if have.v == 2 then
		changed = merge2(have, inc)
		recording = true -- the body was merged above
	end
	if not recording and (inc.snaps > have.snaps or (inc.snaps == have.snaps and inc.ended and not have.ended)) then
		out = Att.Copy(inc)
		for guid, b in pairs(have.bench or {}) do out.bench[guid] = type(b) == "boolean" and { v = b, u = 0 } or b end
		changed = true
	end
	for guid, b in pairs(inc.bench) do
		local mine = out.bench[guid]
		local mineU = type(mine) == "table" and mine.u or (mine ~= nil and 0 or -1)
		if b.u > mineU then
			out.bench[guid] = { v = b.v, u = b.u }
			changed = true
		end
	end
	if changed then out.u = math.max(out.u or 0, inc.u) end
	return out, changed
end

---------------------------------------------------------------------------
-- Checking (stateful, v0.14.0)
---------------------------------------------------------------------------
Att.lastWhy = nil       -- why the last check was skipped (debug)
Att.checking = nil      -- the raid being checked right now (debug, UI)

function Att:Store(guild)
	guild = guild or SK.DBM:Guild()
	if not guild then return nil end
	guild.attendance = guild.attendance or {}
	return guild.attendance
end

-- Every officer's and raid leader's game checks (no /sr officer needed):
-- the more of them online at the start, the surer the result.
function Att.Enabled()
	return SK.RaidBoard.IsLeadSelf()
end

-- The raids to look at now: not cancelled, from ROSTER_BEFORE before the
-- start until LONGEST after it (to close what's still open). Pure.
function Att.EventsNow(board, now)
	local out = {}
	for _, e in pairs(board and board.events or {}) do
		if not e.x and now >= e.at - Att.ROSTER_BEFORE and now <= e.at + Att.LONGEST then out[#out + 1] = e end
	end
	table.sort(out, function(a, b) return a.at < b.at end)
	return out
end

local function trim(store)
	local list = Att.Sorted(store)
	for i = Att.MAX_RECORDS + 1, #list do store[list[i].id] = nil end
end

function Att:Check(ev, now)
	local store = self:Store()
	local guild = SK.DBM:Guild()
	local board = SK.RaidBoard:Get(guild)
	if not store or not board then return false end
	local signups = board.signups[ev.id] or {}
	if not next(signups) then Att.lastWhy = "nobody signed up"; return false end
	if Compat.InChatLockdown() then Att.lastWhy = "chat lockdown"; return false end
	local rec = store[ev.id]
	if rec and rec.v ~= 2 then Att.lastWhy = "an older record"; return false end
	if not rec then
		rec = Att.NewCheck(ev, Compat.PlayerGUID(), now)
		store[ev.id] = rec
		trim(store)
	end
	local online, names = {}, {}
	for guid, m in pairs(guild.members or {}) do
		if not m.leftAt then
			if m.online then online[guid] = true end
			names[guid] = { name = m.name, class = m.class }
		end
	end
	Att.AddCheck(rec, now, online, names, signups, board.places and board.places[ev.id])
	Att.checking, Att.lastWhy = rec, nil
	SK:Fire("ATTENDANCE_UPDATED")
	return true
end

-- The window has closed: save it and share it with the other officers.
function Att:Close(rec, at)
	rec.ended = at
	rec.u = math.max(rec.u or 0, at)
	if Att.checking == rec then Att.checking = nil end
	local s = Att.Summary(Att.Rows(rec))
	SK:Print("Attendance for %s: %d on time, %d late, %d no-show%s. Raids > Attendance shows it.",
		SK.RaidBoard.EventName(rec), s.full, s.late, s.missed, s.missed == 1 and "" or "s")
	if SK.AttendanceSync then SK.AttendanceSync:Share(rec.id) end
	SK:Fire("ATTENDANCE_UPDATED")
end

function Att:Tick(now)
	now = now or Compat.Now()
	if not Att.Enabled() then return end
	local store = self:Store()
	for _, ev in ipairs(Att.EventsNow(SK.RaidBoard:Get(), now)) do
		local rec = store and store[ev.id]
		if now < ev.at then
			-- A fresh roster for the start (the game's copy can be minutes old).
			if not self.asked or self.asked ~= ev.id then
				self.asked = ev.id
				Compat.RequestRoster()
			end
		elseif now <= ev.at + Att.LATE_FOR then
			if not (rec and rec.ended) then self:Check(ev, now) end
		elseif rec and rec.v == 2 and not rec.ended then
			self:Close(rec, ev.at + Att.LATE_FOR)
		end
	end
end

-- A bench tick an officer changed by hand (shared with the others).
function Att:ToggleBench(id, guid)
	local store = self:Store()
	local rec = store and store[id]
	if not rec then return end
	for _, r in ipairs(Att.Rows(rec)) do
		if r.guid == guid then
			local want = not r.bench
			local now = Compat.Now()
			rec.bench[guid] = { v = (want ~= r.benchAuto) and want or nil, u = now }
			rec.u = math.max(rec.u or 0, now)
			if SK.AttendanceSync then SK.AttendanceSync:Share(id) end
		end
	end
	SK:Fire("ATTENDANCE_UPDATED")
end

function Att:OnLogin()
	SK.NewTicker(Att.TICK, function() self:Tick() end)
end
