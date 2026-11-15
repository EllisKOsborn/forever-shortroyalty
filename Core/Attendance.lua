-- Attendance (v0.8.0): recorded on an officer's or raid leader's own game
-- while they're in the raid group, never sent to anyone. Stored per guild
-- in guild.attendance = { [raid id] = record }.
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
-- Pure parts (tested): NewRecord, AddSnapshot, Rows, Sheet, Totals.
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
function Att.NewRecord(ev, by, now)
	return { id = ev.id, raid = ev.raid, at = ev.at, by = by, began = now, last = nil, ended = nil,
		total = 0, snaps = 0, people = {}, signed = {}, bench = {} }
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
			if rec.bench[guid] ~= nil then bench = rec.bench[guid] end
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

-- Spreadsheet text (the owner's columns, 15 Nov): one line per person per
-- raid, ticks as 1 so the columns can be summed. sep = "\t" (pastes into
-- Google Sheets and Excel as columns) or ",".
Att.SHEET_COLUMNS = { "Date", "Raid", "Name", "Signed up", "On time, whole raid", "Late / not the whole raid",
	"Didn't attend", "Bench", "Minutes in raid" }
function Att.Sheet(records, sep)
	sep = sep or "\t"
	local function cell(v)
		v = SK.Export.Plain(tostring(v or ""))
		if sep == "," and v:find("[,\"]") then v = '"' .. v:gsub('"', '""') .. '"' end
		return v
	end
	local lines = {}
	local head = {}
	for i, c in ipairs(Att.SHEET_COLUMNS) do head[i] = cell(c) end
	lines[1] = table.concat(head, sep)
	for _, rec in ipairs(records) do
		local raid = SK.RaidBoard.Raid(rec.raid)
		for _, r in ipairs(Att.Rows(rec)) do
			lines[#lines + 1] = table.concat({
				cell(date("%Y-%m-%d", rec.at)), cell(raid and raid.name or rec.raid), cell(r.name), cell(r.signedName),
				r.result == "full" and "1" or "", r.result == "late" and "1" or "", r.result == "missed" and "1" or "",
				r.bench and "1" or "", string.format("%d", math.floor(r.inS / 60 + 0.5)),
			}, sep)
		end
	end
	return table.concat(lines, "\n")
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
	local s = Att.Summary(Att.Rows(rec))
	SK:Print("Attendance saved: %d on time, %d late, %d didn't attend, %d bench.", s.full, s.late, s.missed, s.bench)
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
			if want == r.benchAuto then rec.bench[guid] = nil else rec.bench[guid] = want end
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
