-- Raider check (v0.16.7, the guild's rule: "will be automatically promoted
-- to Raider when they have had at least 80% attendance over a two-month
-- period"; owner, 23 Nov: "signed and been available at raid start … for
-- 80% of the raids in a 2 month window. Basically check if they've
-- attended 13 out of the last 16 raids. Bench counts as attending. Raider
-- in both areas" = the planner's status and the guild rank).
--
-- Counted from the officers' attendance records (Core/Attendance.lua):
--   a raid   = one attendance record (one raid night) that started in the
--              last DAYS days and whose start check is over;
--   attended = signed up and online at the start (On time or Late), or
--              ticked Bench, on any of the player's characters;
--   ready    = attended at least PCT % of ALL those raids (not just the
--              ones they signed up for), at least MIN_RAIDS raids in the
--              window, and records going back FULL_DAYS days (so nobody
--              is "ready" after two weeks of 4 out of 4).
-- Nothing is promoted on its own: officers see who's ready and press
-- "Make Raider" (planner status, and one guild rank per press via
-- C_GuildInfo.Promote, which the game allows from addons).
local _, SK = ...

local Pr = SK:NewModule("Promotion")
local Compat = SK.Compat

Pr.DAYS = 60         -- the window ("two months")
Pr.PCT = 80          -- attended this share of the raids in it
Pr.MIN_RAIDS = 8     -- at least this many raids in the window
Pr.FULL_DAYS = 56    -- records must reach back this far (8 weeks)
Pr.NOTICE_AFTER = 200 -- seconds after login (after officers' records arrive)
Pr.PROMOTE_WAIT = 15 -- seconds before another promotion of the same person
Pr.ATTENDED = { full = true, late = true }

---------------------------------------------------------------------------
-- Counting (pure)
---------------------------------------------------------------------------
-- The raids that count at `now`, newest first.
function Pr.Raids(records, now)
	local from, Att = now - Pr.DAYS * 86400, SK.Attendance
	local out = {}
	for _, rec in pairs(records or {}) do
		if type(rec) == "table" and type(rec.at) == "number" and rec.at >= from
			and rec.at + Att.LATE_FOR <= now then
			out[#out + 1] = rec
		end
	end
	table.sort(out, function(a, b) return a.at > b.at end)
	return out
end

-- Do the records reach back far enough to judge two months?
function Pr.Covered(records, now)
	local oldest
	for _, rec in pairs(records or {}) do
		if type(rec) == "table" and type(rec.at) == "number" and (not oldest or rec.at < oldest) then oldest = rec.at end
	end
	return oldest ~= nil and oldest <= now - Pr.FULL_DAYS * 86400
end

-- Who attended one record: { [guid] = true }.
function Pr.AttendedIn(rec)
	local out = {}
	for _, r in ipairs(SK.Attendance.Rows(rec)) do
		if Pr.ATTENDED[r.result] or r.bench then out[r.guid] = true end
	end
	return out
end

-- players = { [mainGuid] = { guid, guid, … } } (their characters).
-- Returns { [mainGuid] = { attended, raids, pct, ready, covered } }.
function Pr.Check(records, now, players)
	local raids = Pr.Raids(records, now)
	local covered = Pr.Covered(records, now)
	local sets = {}
	for i, rec in ipairs(raids) do sets[i] = Pr.AttendedIn(rec) end
	local out = {}
	for main, chars in pairs(players or {}) do
		local n = 0
		for _, set in ipairs(sets) do
			for _, g in ipairs(chars) do
				if set[g] then n = n + 1; break end
			end
		end
		local total = #raids
		local pct = total > 0 and math.floor(n / total * 100 + 0.5) or nil
		out[main] = { attended = n, raids = total, pct = pct, covered = covered,
			ready = covered and total >= Pr.MIN_RAIDS and n / total * 100 >= Pr.PCT }
	end
	return out
end

-- "13 of 16 raids (81%)", plus why they aren't ready yet when they aren't.
function Pr.Text(c)
	if not c or c.raids == 0 then return "no recorded raids in the last two months" end
	local s = string.format("%d of %d raids (%d%%)", c.attended, c.raids, c.pct or 0)
	if c.ready then return s .. ": ready for Raider" end
	if not c.covered then return s .. ": not two months of records yet" end
	if c.raids < Pr.MIN_RAIDS then return s .. ": fewer than " .. Pr.MIN_RAIDS .. " raids recorded" end
	return s
end

---------------------------------------------------------------------------
-- The guild rank (pure)
---------------------------------------------------------------------------
local function words(name)
	return " " .. (name:lower():gsub("[%p%c]", " "):gsub("%s+", " ")) .. " "
end

-- The Raider rank's index (0 = Guild Master), read from the ranks members
-- hold. A rank named exactly "Raider(s)" wins; otherwise the highest rank
-- with the word "raider" that isn't a trial rank. nil when none is seen.
function Pr.RaiderRank(members)
	local exact, loose
	for _, m in pairs(members or {}) do
		if type(m) == "table" and not m.leftAt and type(m.rank) == "string" and type(m.rankIndex) == "number" then
			local w = words(m.rank)
			if w == " raider " or w == " raiders " then
				if not exact or m.rankIndex < exact then exact = m.rankIndex end
			elseif w:find(" raiders? ") and not w:find(" trials? ") then
				if not loose or m.rankIndex < loose then loose = m.rankIndex end
			end
		end
	end
	return exact or loose
end

-- How many ranks they are below Raider (0 = Raider or higher, nil = unknown).
function Pr.StepsToRaider(m, raiderIndex)
	if not raiderIndex or type(m) ~= "table" or type(m.rankIndex) ~= "number" then return nil end
	return math.max(0, m.rankIndex - raiderIndex)
end

-- Can I (my member entry) promote someone up to the Raider rank? The game
-- lets you give ranks below your own only.
function Pr.CanPromoteTo(me, raiderIndex)
	return type(me) == "table" and type(me.rankIndex) == "number" and raiderIndex ~= nil
		and raiderIndex > me.rankIndex
end

---------------------------------------------------------------------------
-- Rows for the planner (pure): adds r.promo to each RosterPlan row.
---------------------------------------------------------------------------
function Pr.Annotate(rows, records, now, members)
	local players = {}
	for _, r in ipairs(rows) do players[r.guid] = r.chars or { r.guid } end
	local checks = Pr.Check(records, now, players)
	local raiderIndex = Pr.RaiderRank(members)
	local ready = {}
	for _, r in ipairs(rows) do
		local c = checks[r.guid]
		local steps = Pr.StepsToRaider(members and members[r.guid], raiderIndex)
		c.steps = steps
		-- Something still to do: the planner status, or the guild rank.
		c.todo = c.ready and (r.status ~= "r" or (steps ~= nil and steps > 0))
		r.promo = c
		if c.todo then ready[#ready + 1] = r end
	end
	table.sort(ready, function(a, b) return a.name:lower() < b.name:lower() end)
	return ready, raiderIndex
end

-- The chat line for officers: nil when nobody is waiting.
function Pr.NoticeText(ready)
	if #ready == 0 then return nil end
	local names = {}
	for i, r in ipairs(ready) do
		if i > 6 then break end
		names[#names + 1] = r.name
	end
	local more = #ready > 6 and (" and " .. (#ready - 6) .. " more") or ""
	return string.format("%d ready for Raider (%d%% of raids over two months): %s%s. Roster > Officers to make them Raider.",
		#ready, Pr.PCT, table.concat(names, ", "), more)
end

---------------------------------------------------------------------------
-- Actions (officers)
---------------------------------------------------------------------------
Pr.pending = {} -- guid -> { at, from } a promotion we asked the game for

function Pr:Records(guild)
	local store = SK.Attendance:Store(guild)
	return store or {}
end

-- Planner status Raider, then one guild rank up (if below Raider). Returns
-- ok, message.
function Pr:MakeRaider(r)
	local guild = SK.DBM:Guild()
	if not guild then return false, "not in a guild" end
	local said = {}
	if r.status ~= "r" then
		local ok, why = SK.OfficerDir:SetStatus(r.guid, "r")
		if not ok then return false, tostring(why) end
		said[#said + 1] = "status set to Raider"
	end
	local m = guild.members[r.guid]
	local raiderIndex = Pr.RaiderRank(guild.members)
	local steps = Pr.StepsToRaider(m, raiderIndex)
	if not raiderIndex then
		said[#said + 1] = "no guild rank called Raider seen, so their rank wasn't changed"
	elseif steps and steps > 0 then
		local me = guild.members[Compat.PlayerGUID() or ""]
		local wait = Pr.pending[r.guid]
		local now = Compat.Now()
		if wait and wait.from == m.rankIndex and now - wait.at < Pr.PROMOTE_WAIT then
			said[#said + 1] = "still waiting for the game to show their new rank"
		elseif not Pr.CanPromoteTo(me, raiderIndex) or not Compat.CanGuildPromote() then
			said[#said + 1] = "your guild rank can't promote to Raider, so their rank wasn't changed"
		elseif Compat.GuildPromote(m.name) then
			Pr.pending[r.guid] = { at = now, from = m.rankIndex }
			Compat.RequestRoster()
			said[#said + 1] = steps == 1 and "asked the game to promote them to Raider"
				or ("asked the game to promote them one rank (" .. (steps - 1) .. " more to Raider: press again)")
		else
			said[#said + 1] = "the game didn't take the promotion; use the guild window"
		end
	end
	if #said == 0 then said[1] = "already Raider" end
	return true, table.concat(said, "; ")
end

function Pr:Notice()
	if self.noticed or not (SK.RaidBoard.OfficerView and SK.RaidBoard.OfficerView()) then return end
	local guild = SK.DBM:Guild()
	if not guild or not SK.RosterTab or not SK.RosterTab.PlanRows then return end
	local rows = SK.RosterTab:PlanRows()
	local ready = Pr.Annotate(rows, self:Records(guild), Compat.Now(), guild.members)
	local text = Pr.NoticeText(ready)
	self.noticed = true
	if text then SK:Print("%s", text) end
end

function Pr:OnLogin()
	SK.After(Pr.NOTICE_AFTER, function() self:Notice() end)
end
