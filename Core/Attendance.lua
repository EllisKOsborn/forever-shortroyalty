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
-- Pure parts (tested): NewRecord, AddSnapshot, Rows, Totals, BenchOf,
-- ValidRecord, Merge.
local _, SK = ...

local Att = SK:NewModule("Attendance")
local Compat = SK.Compat

Att.EVERY = 120            -- seconds between snapshots
Att.TICK = 15              -- how often we check
Att.MAX_GAP = 10 * 60      -- one snapshot counts for at most this long
Att.GRACE = 10 * 60        -- late / missed time allowed for "on time, whole raid"
Att.BENCH_MIN = 30 * 60
Att.BEFORE = 30 * 60       -- recording starts this long before a raid
Att.LONGEST = 6 * 3600     -- and stops this long after its start
Att.LEFT_AFTER = 15 * 60   -- out of a raid group this long: the recording ends
Att.MAX_RECORDS = 200

Att.RESULT_NAME = { full = "On time, whole raid", late = "Late / not the whole raid", missed = "Didn't attend",
	declined = "Said can't come" }
local RESULT_ORDER = { full = 1, late = 2, missed = 3, declined = 4 }
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

-- One row per person: { guid, name, class, signed, result, bench, benchAuto,
-- inS, bnS }. Sorted by result, then name.
function Att.Rows(rec)
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
	local s = { full = 0, late = 0, missed = 0, declined = 0, bench = 0 }
	for _, r in ipairs(rows) do
		s[r.result] = s[r.result] + 1
		if r.bench then s.bench = s.bench + 1 end
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
					bench = 0, declined = 0 }
				by[r.guid] = t
			end
			t.raids = t.raids + 1
			t[r.result] = t[r.result] + 1
			if r.bench then t.bench = t.bench + 1 end
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
function Att.ValidRecord(r, now)
	if type(r) ~= "table" then return false, "not a table" end
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
function Att.Merge(have, inc, recording)
	if not have then return Att.Copy(inc), true end
	local changed = false
	local out = have
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
-- Recording (stateful)
---------------------------------------------------------------------------
Att.current = nil       -- the record being written
Att.pendingSnap = false -- a boss died (or we were in combat): snapshot when we can
Att.lastTry = 0
Att.lastWhy = nil       -- why the last snapshot was skipped (debug)

function Att:Store(guild)
	guild = guild or SK.DBM:Guild()
	if not guild then return nil end
	guild.attendance = guild.attendance or {}
	return guild.attendance
end

-- Recording only runs for officers and raid leaders who typed /sr officer.
function Att.Enabled()
	return SK.RaidBoard.OfficerView()
end

-- The raid whose time it is: not cancelled, starting within BEFORE or
-- started less than LONGEST ago; the closest to its start wins. Pure.
function Att.EventNow(board, now)
	local best, bestD
	for _, e in pairs(board and board.events or {}) do
		if not e.x and now >= e.at - Att.BEFORE and now <= e.at + Att.LONGEST then
			local d = math.abs(now - e.at)
			if not bestD or d < bestD then best, bestD = e, d end
		end
	end
	return best
end

-- Who is in the raid group (online) and their names. GUIDs come from the
-- group, or from the roster by name when the game hides the GUID.
function Att.ReadGroup()
	local inGroup, names = {}, {}
	local members = Compat.RaidMembers()
	for _, m in ipairs(members) do
		local guid = m.guid or (m.name and SK.Identity:ResolveSender(m.name))
		if guid and m.online then
			inGroup[guid] = true
			names[guid] = { name = m.name, class = m.class }
		end
	end
	return inGroup, names, #members
end

function Att:Snapshot(now)
	local rec = self.current
	if not rec then return false end
	if Compat.InCombat() then self.pendingSnap, Att.lastWhy = true, "combat"; return false end
	if Compat.InChatLockdown() then self.pendingSnap, Att.lastWhy = true, "chat lockdown"; return false end
	local guild = SK.DBM:Guild()
	local inGroup, names = Att.ReadGroup()
	local online = {}
	for guid, m in pairs(guild and guild.members or {}) do
		if m.online and not m.leftAt then
			online[guid] = true
			if not names[guid] then names[guid] = { name = m.name, class = m.class } end
		elseif not names[guid] and m.name then
			names[guid] = { name = m.name, class = m.class }
		end
	end
	local board = SK.RaidBoard:Get(guild)
	Att.AddSnapshot(rec, now, inGroup, online, names, board and board.signups[rec.id] or {})
	self.pendingSnap, self.lastTry, Att.lastWhy = false, now, nil
	SK:Fire("ATTENDANCE_UPDATED")
	return true
end

function Att:Begin(ev, now)
	local store = self:Store()
	if not store then return nil end
	local rec = store[ev.id]
	if rec and rec.ended then return nil end -- ended by hand: Resume starts it again
	if not rec then
		rec = Att.NewRecord(ev, Compat.PlayerGUID(), now)
		store[ev.id] = rec
		local list = Att.Sorted(store)
		for i = Att.MAX_RECORDS + 1, #list do store[list[i].id] = nil end
		local raid = SK.RaidBoard.Raid(ev.raid)
		SK:Print("Recording attendance for %s (%s). It stops by itself; Raids > Attendance shows it.",
			raid and raid.name or "the raid", SK.RaidBoard.When(ev.at))
	end
	self.current = rec
	self.lastTry = 0
	SK:Fire("ATTENDANCE_UPDATED")
	return rec
end

function Att:Stop(at)
	local rec = self.current
	if not rec then return false end
	rec.ended = at or Compat.Now()
	self.current = nil
	rec.u = math.max(rec.u or 0, rec.ended)
	local s = Att.Summary(Att.Rows(rec))
	SK:Print("Attendance saved: %d on time, %d late, %d didn't attend, %d bench. Other officers get it when you're " ..
		"out of the instance.", s.full, s.late, s.missed, s.bench)
	if SK.AttendanceSync then SK.AttendanceSync:Share(rec.id) end
	SK:Fire("ATTENDANCE_UPDATED")
	return true
end

-- Start recording an ended raid again (in its time window).
function Att:Resume(id)
	local store = self:Store()
	local rec = store and store[id]
	if not rec then return false end
	rec.ended = nil
	self.current = rec
	self.lastTry = 0
	SK:Fire("ATTENDANCE_UPDATED")
	return true
end

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

function Att:Tick(now)
	now = now or Compat.Now()
	if not Att.Enabled() then return end
	local inRaid = Compat.InRaidGroup()
	local rec = self.current
	if not rec then
		if not inRaid then return end
		local ev = Att.EventNow(SK.RaidBoard:Get(), now)
		if not ev then return end
		rec = self:Begin(ev, now)
		if not rec then return end
	end
	if now > rec.at + Att.LONGEST then return self:Stop(math.min(now, rec.at + Att.LONGEST)) end
	if not inRaid then
		rec.leftAt = rec.leftAt or now
		if now - rec.leftAt >= Att.LEFT_AFTER then self:Stop(rec.leftAt) end
		return
	end
	rec.leftAt = nil
	if self.pendingSnap or now - self.lastTry >= Att.EVERY then self:Snapshot(now) end
end

function Att:OnLogin()
	SK:RegisterEvent("ENCOUNTER_END", function(_, _, _, _, _, success)
		if self.current and (success == 1 or success == true) then self.pendingSnap = true end
	end)
	SK:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		if self.current and self.pendingSnap then SK.After(2, function() self:Tick() end) end
	end)
	SK.NewTicker(Att.TICK, function() self:Tick() end)
end
