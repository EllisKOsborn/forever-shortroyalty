-- Raids page (v0.8.0). Everyone: upcoming guild raids, who's coming, and
-- Sign up / Tentative / Can't come with a role. Officers and raid leaders
-- who typed /sr officer also make raids on the Calendar (v0.14.0: the New
-- raid tab is gone), Cancel and Attendance (shared
-- between officers; v0.8.1: no spreadsheet, it all stays in the addon). The rules live in Core/RaidBoard.lua and
-- Core/Attendance.lua.
local _, SK = ...

local RT = SK:NewModule("RaidsTab")
local Theme, W, Compat = SK.Theme, SK.Widgets, SK.Compat
local Board, Att = SK.RaidBoard, SK.Attendance
local S, SP = Theme.SIZES, Theme.SPACE

RT.VIEWS = { { "upcoming", "Raids" }, { "groups", "Groups" }, { "assign", "Assignments" }, { "calendar", "Calendar" },
	{ "attendance", "Attendance" } }
RT.OFFICER_VIEWS = { attendance = true }
RT.LEFT_W = 270
RT.RIGHT_W = S.contentW - RT.LEFT_W - SP.xl
RT.ATT_LEFT_W = 270
RT.ATT_RIGHT_W = S.contentW - RT.ATT_LEFT_W - SP.xl
RT.DAYS = { { 30, "30 days" }, { 60, "60 days" }, { 90, "90 days" }, { 0, "All" } }

RT.EVENT_COLUMNS = {
	{ key = "when", title = "When", width = 130, sort = function(a, b) return a.at < b.at end },
	{ key = "raid", title = "Raid", width = 82 },
	{ key = "signed", title = "Signed", width = RT.LEFT_W - 130 - 82, align = "RIGHT" },
}
RT.LINEUP_COLUMNS = {
	{ key = "name", title = "Name", width = 118, sort = function(a, b) return a.name:lower() < b.name:lower() end },
	{ key = "status", title = "Status", width = 78 },
	{ key = "place", title = "Raid", width = 48 },
	{ key = "role", title = "Role", width = 56 },
	{ key = "spec", title = "Spec", width = 60 },
	{ key = "ilvl", title = "ilvl", width = 32, align = "RIGHT", sort = function(a, b) return (a.ilvl or 0) < (b.ilvl or 0) end },
	{ key = "att", title = "Attuned", width = RT.RIGHT_W - 118 - 78 - 48 - 56 - 60 - 32 - SP.m, align = "RIGHT" },
}
RT.RECORD_COLUMNS = {
	{ key = "date", title = "Date", width = 96 },
	{ key = "raid", title = "Raid", width = 110 },
	{ key = "came", title = "Came", width = RT.ATT_LEFT_W - 96 - 110 - SP.m, align = "RIGHT" },
}
-- v0.14.0: "Changed" = when they moved from Signed up to Tentative or
-- Can't come (v0.8.0 group records show minutes in the group there).
RT.PEOPLE_COLUMNS = {
	{ key = "name", title = "Name", width = 130, sort = function(a, b) return a.name:lower() < b.name:lower() end },
	{ key = "signed", title = "Signed up", width = 78 },
	{ key = "result", title = "Result", width = 90 },
	{ key = "bench", title = "Bench", width = 50, align = "CENTER" },
	{ key = "mins", title = "Changed", width = RT.ATT_RIGHT_W - 130 - 78 - 90 - 50 - SP.m, align = "RIGHT",
		sort = function(a, b) return (a.changed or a.inS) < (b.changed or b.inS) end },
}
local function pctSort(a, b) return (a.pct or -1) < (b.pct or -1) end
local function by(k) return function(a, b) return (a[k] or 0) < (b[k] or 0) end end
RT.TOTAL_COLUMNS = {
	{ key = "name", title = "Name", width = 150, sort = function(a, b) return a.name:lower() < b.name:lower() end },
	{ key = "raids", title = "Raids", width = 56, align = "RIGHT", sort = by("raids") },
	{ key = "full", title = "On time", width = 66, align = "RIGHT", sort = by("full") },
	{ key = "late", title = "Late", width = 52, align = "RIGHT", sort = by("late") },
	{ key = "missed", title = "No-show", width = 72, align = "RIGHT", sort = by("missed") },
	{ key = "bench", title = "Bench", width = 56, align = "RIGHT", sort = by("bench") },
	{ key = "changed", title = "Changed", width = 74, align = "RIGHT", sort = by("changed") },
	{ key = "late24", title = "<24h", width = 56, align = "RIGHT", sort = by("changedLate") },
	{ key = "pct", title = "Attended", width = S.contentW - 150 - 56 - 66 - 52 - 72 - 56 - 74 - 56 - SP.m,
		align = "RIGHT", sort = pctSort },
}

local STATUS_TONE = { y = "good", t = "text", n = "faint", a = "bad" }
-- Short names in the list; the full ones are in the tooltip and the spreadsheet.
RT.RESULT_SHORT = { full = "On time", late = "Late / part", missed = "Didn't attend", declined = "Can't come" }
local RESULT_TONE = { full = "good", late = "spark", missed = "bad", maybe = "dim", declined = "faint" }

---------------------------------------------------------------------------
-- Pure helpers (tested)
---------------------------------------------------------------------------
-- Which page tab to show: officer tabs fall back to Raids for everyone else.
function RT.View(officer)
	local v = SK.DB.settings.raidsView
	if v == "new" then return "calendar" end -- v0.14.0: raids are made on the Calendar
	if RT.OFFICER_VIEWS[v] and not officer then return "upcoming" end
	if v ~= "attendance" and v ~= "calendar" and v ~= "groups" and v ~= "assign" then return "upcoming" end
	return v
end

---------------------------------------------------------------------------
-- Calendar (v0.10.2): a month grid, weeks from Monday, raids on their days
-- (cancelled ones left out). Pure apart from the clock; tested.
---------------------------------------------------------------------------
RT.CAL_PER_DAY = 3 -- raids shown in a day; more says "+N more"
RT.WEEKDAYS = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }

-- { title = "December 2026", cells = 42 x { at (local noon), day, inMonth,
-- today, past, raids = { { id, at, text, mine, place } } } }.
-- v0.11.0: mine = my absences, guild = for how many are away each day.
function RT.MonthGrid(year, month, board, now, me, mine, guild)
	local first = time({ year = year, month = month, day = 1, hour = 12 })
	local t = date("*t", first)
	local back = (t.wday + 5) % 7 -- days since Monday
	local byDay = {}
	for _, e in pairs(board and board.events or {}) do
		if not e.x then
			local k = date("%Y-%m-%d", e.at)
			byDay[k] = byDay[k] or {}
			table.insert(byDay[k], e)
		end
	end
	local todayKey = date("%Y-%m-%d", now)
	local todayStart = Board.DayStart(now, 0)
	local players = guild and SK.Absences.Players(guild) -- v0.16.2: count players, not characters
	local cells = {}
	for i = 1, 42 do
		local at = time({ year = year, month = month, day = 1 - back + (i - 1), hour = 12 })
		local d = date("*t", at)
		local key = date("%Y-%m-%d", at)
		local raids = {}
		local list = byDay[key] or {}
		table.sort(list, function(a, b) return a.at < b.at end)
		for _, e in ipairs(list) do
			local su = Board.SignupOf(board, e.id, me)
			raids[#raids + 1] = { id = e.id, at = e.at, text = date("%H:%M", e.at) .. " " .. Board.EventName(e, true),
				mine = su and su.s or nil, place = Board.PlaceOf(board, e.id, me or "") }
		end
		cells[i] = { at = at, day = d.day, inMonth = d.month == month, today = key == todayKey,
			past = at < todayStart, raids = raids, away = SK.Absences.IsAway(mine, at),
			awayCount = guild and at >= todayStart and #SK.Absences.AwayOn(guild, at, players) or 0 }
	end
	return { title = date("%B %Y", first), cells = cells }
end

-- The month shown, moved by delta months.
function RT.ShiftMonth(year, month, delta)
	local m = month + delta
	return year + math.floor((m - 1) / 12), (m - 1) % 12 + 1
end

-- Rows for the left list of raids.
function RT.EventRows(board, now, me)
	local rows = {}
	for _, e in ipairs(Board.Upcoming(board, now)) do
		local mine = Board.SignupOf(board, e.id, me)
		rows[#rows + 1] = { id = e.id, at = e.at, when = Board.ShortWhen(e.at, now), raidName = Board.EventName(e, true),
			size = Board.EventSize(e), counts = Board.Counts(board, e.id), mine = mine and mine.s, ev = e }
	end
	return rows
end

-- "You: Signed up as Healer  ·  You're in" / "You haven't answered yet".
-- place = "i" | "b" | nil (v0.10.0: officers' pick, shown to everyone);
-- group = 1..8 when they're In with a group (v0.11.0).
RT.PLACE_TEXT = { i = Theme.Paint("good", "You're in"), b = Theme.Paint("accent", "You're on the bench") }
function RT.MineText(su, place, group, jobs)
	local tail = place and ("  ·  " .. RT.PLACE_TEXT[place] ..
		((place == "i" and group and group > 0) and Theme.Paint("good", ", group " .. group) or "")) or ""
	if jobs and #jobs > 0 then
		tail = tail .. "  ·  " .. Theme.Paint("accent", jobs[1] .. (#jobs > 1 and (" +" .. (#jobs - 1)) or ""))
	end
	if not su then return Theme.Paint("spark", "You haven't answered yet") .. tail end
	local role = su.r and SK.Data.ROLE_NAMES[su.r]
	return "You: " .. Theme.Paint(STATUS_TONE[su.s], Board.STATUS_NAME[su.s]) .. (role and su.s ~= "n" and (" as " .. role) or "")
		.. (su.b and Theme.Paint("faint", " (added by an officer)") or "") .. tail
end

-- The line at the top of Attendance: the raid being checked, else who
-- recorded the raid picked below (v0.8.1: records come from every officer).
-- v0.14.0: signed up and online at the start = attended; no raid group.
function RT.RecordingText(rec, now, shown)
	if rec and not rec.ended and now <= rec.at + Att.LATE_FOR then
		return string.format("%s %s (%s)  ·  online at the start = on time, by %s = late", Theme.Paint("good", "Checking"),
			Board.EventName(rec), Board.ShortWhen(rec.at, now), date("%H:%M", rec.at + Att.LATE_FOR))
	end
	if shown then
		local who = SK.Identity:Member(shown.by)
		local how = shown.v == 2 and ("checked from " .. date("%H:%M", shown.began)) or Theme.Count(shown.snaps, "check")
		return string.format("%s, %s  ·  recorded by %s  ·  %s", Board.EventName(shown), Board.When(shown.at),
			who and Theme.ClassText(who.name, who.class) or "an officer", how)
	end
	return "Attendance is taken by itself at each raid's start time: signed up and online = there. Any officer's " ..
		"or raid leader's game that's online then does it."
end

-- "2d before", "5h before", "40m before" (the start). Pure.
function RT.BeforeText(at, w)
	local d = at - w
	if d >= 86400 then return math.floor(d / 86400) .. "d before" end
	if d >= 3600 then return math.floor(d / 3600) .. "h before" end
	if d >= 0 then return math.floor(d / 60) .. "m before" end
	return "after the start"
end

---------------------------------------------------------------------------
-- Cells
---------------------------------------------------------------------------
local C = Theme.Code

local function setEventCell(fs, r, col)
	if col.key == "when" then
		fs:SetText(r.when)
	elseif col.key == "raid" then
		fs:SetText(r.raidName .. (r.mine and (" " .. Theme.Paint(STATUS_TONE[r.mine], "•")) or ""))
	elseif col.key == "signed" then
		fs:SetText(r.counts.y .. (r.size and (C("faint") .. " / " .. r.size .. "|r") or ""))
	end
end

local function setLineUpCell(fs, r, col)
	local k = col.key
	if k == "name" then
		fs:SetText((r.online and (SK.RosterTab.DOT.addon .. " ") or "") .. Theme.ClassText(r.name, r.class) ..
			(r.duplicateOf and (" " .. C("spark") .. "2x|r") or "") .. (r.away and (" " .. C("bad") .. "away|r") or ""))
	elseif k == "status" then
		fs:SetText(Theme.Paint(STATUS_TONE[r.status], r.statusName))
	elseif k == "place" then
		fs:SetText(r.place == "i" and Theme.Paint("good", "In") or r.place == "b" and Theme.Paint("accent", "Bench") or Theme.DASH)
	elseif k == "role" then
		fs:SetText(r.role and Theme.Paint(r.roleGuess and "faint" or "text", SK.Data.ROLE_NAMES[r.role]) or Theme.DASH)
	elseif k == "spec" then
		fs:SetText(r.tree and (C("dim") .. r.tree .. "|r") or Theme.DASH)
	elseif k == "ilvl" then
		fs:SetText(r.ilvl and string.format("%.0f", r.ilvl) or Theme.DASH)
	elseif k == "att" then
		local t = { yes = Theme.Paint("good", "yes"), no = Theme.Paint("bad", "no"), none = Theme.Paint("faint", "n/a") }
		fs:SetText(t[r.att] or Theme.DASH)
	end
end

local function setRecordCell(fs, r, col)
	if col.key == "date" then
		fs:SetText(date("%a %d %b", r.at))
	elseif col.key == "raid" then
		fs:SetText(Board.EventName(r, true) .. ((Att.checking == r and not r.ended) and (" " .. Theme.Paint("good", "•")) or ""))
	elseif col.key == "came" then
		local s = Att.Summary(Att.Rows(r))
		fs:SetText(tostring(s.full + s.late))
	end
end

local function setPersonCell(fs, r, col)
	local k = col.key
	if k == "name" then
		fs:SetText(Theme.ClassText(r.name, r.class))
	elseif k == "signed" then
		fs:SetText(Theme.Paint(r.signed and STATUS_TONE[r.signed] or "faint", r.signedName))
	elseif k == "result" then
		local short = r.v == 2 and Att.RESULT_SHORT2 or RT.RESULT_SHORT
		fs:SetText(Theme.Paint(RESULT_TONE[r.result], short[r.result]))
	elseif k == "bench" then
		fs:SetText(r.bench and Theme.Paint("accent", "yes") or Theme.DASH)
	elseif k == "mins" then
		if r.v ~= 2 then
			fs:SetText(string.format("%d min", math.floor(r.inS / 60 + 0.5)))
		elseif r.changed and r.recAt then
			fs:SetText(Theme.Paint(r.changedLate and "spark" or "dim", RT.BeforeText(r.recAt, r.changed)))
		else
			fs:SetText(Theme.DASH)
		end
	end
end

local function setTotalCell(fs, r, col)
	local k = col.key
	if k == "name" then
		fs:SetText(Theme.ClassText(r.name, r.class))
	elseif k == "pct" then
		fs:SetText(r.pct and (r.pct .. "%") or Theme.DASH)
	elseif k == "missed" then
		fs:SetText(r.missed > 0 and Theme.Paint("bad", tostring(r.missed)) or "0")
	elseif k == "changed" then
		fs:SetText(r.changed > 0 and (r.changed .. Theme.Paint("faint", " / " .. r.signedUp)) or "0")
	elseif k == "late24" then
		fs:SetText(r.changedLate > 0 and Theme.Paint("spark", tostring(r.changedLate)) or "0")
	else
		fs:SetText(tostring(r[k] or 0))
	end
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
-- v0.16.5 (a guild officer thought the Sign up / Tentative / Can't come
-- buttons were tabs filtering the list): "YOUR ANSWER" above them and
-- "OFFICERS" beside the instance chips, so the two are clearly apart.
RT.SIGN_LABEL_H = 18
RT.SIGN_Y = 44 + SP.xs + RT.SIGN_LABEL_H

function RT:Build(page)
	self.page = page
	local s = SK.DB.settings
	self.views = W.SubTabs(page, RT.VIEWS, function(k)
		s.raidsView = k
		RT:Refresh()
	end)
	self.views:SetPoint("TOPLEFT", 0, 0)
	self.views:SetPoint("TOPRIGHT", 0, 0)
	local top = -(S.subTabs + SP.m)

	-------------------------------------------------------------------------
	-- Raids: the list on the left, the selected raid on the right
	-------------------------------------------------------------------------
	local up = CreateFrame("Frame", nil, page)
	up:SetPoint("TOPLEFT", 0, top)
	up:SetPoint("BOTTOMRIGHT")
	self.upcoming = up
	self.events = W.List(up, {
		columns = RT.EVENT_COLUMNS, setCell = setEventCell,
		onClick = function(r) RT.selected = r.id; RT:Refresh() end,
	})
	self.events:SetPoint("TOPLEFT")
	self.events:SetPoint("BOTTOMLEFT")
	self.events:SetWidth(RT.LEFT_W)
	self.events.sortCol = 1

	local d = CreateFrame("Frame", nil, up)
	d:SetPoint("TOPLEFT", RT.LEFT_W + SP.xl, 0)
	d:SetPoint("BOTTOMRIGHT")
	self.detail = d
	self.title = Theme.Text(d, "title", "text")
	self.title:SetPoint("TOPLEFT", 0, -SP.xxs)
	self.sub = Theme.Text(d, "small", "dim")
	self.sub:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -SP.xs)
	self.sub:SetJustifyH("LEFT")
	self.sub:SetWordWrap(false)
	self.options = W.OptionsButton(d, function() return RT:DetailOptions() end, "Copy the line-up, cancel the raid")
	self.options:SetPoint("TOPRIGHT", 0, 0)
	self.title:SetPoint("RIGHT", self.options, "LEFT", -SP.s, 0)
	self.title:SetJustifyH("LEFT")
	self.title:SetWordWrap(false)
	-- v0.14.0 officers: which instances this night is (none = to be decided).
	self.keyChips = {}
	local kprev
	local avail = SK.Data.ShownAttunements()
	for i = #avail, 1, -1 do
		local r = avail[i]
		local c = W.Chip(d, r.short or r.name, function()
			local board = Board:Get()
			local ev = board and RT.selected and board.events[RT.selected]
			if not ev then return end
			local ok, why = Board:SetRaids(ev.id, RT.ToggleKey(Board.Keys(ev), r.key))
			if not ok then SK:Print("Couldn't change it: %s.", tostring(why)) end
			RT:Refresh()
		end)
		c.value = r.key
		c.tooltip = "Officers: is this night " .. r.name .. "? Pick one or more; none = to be decided."
		if kprev then c:SetPoint("RIGHT", kprev, "LEFT", -SP.xxs, 0) else c:SetPoint("TOPRIGHT", 0, -(S.control + SP.xxs)) end
		self.keyChips[#self.keyChips + 1] = c
		kprev = c
	end

	self.answerLabel = Theme.Text(d, "label", "dim")
	self.answerLabel:SetText("YOUR ANSWER")
	self.answerLabel:SetPoint("TOPLEFT", 0, -(RT.SIGN_Y - RT.SIGN_LABEL_H + 2))
	self.officerLabel = Theme.Text(d, "label", "dim")
	self.officerLabel:SetText("OFFICERS")
	self.officerLabel:SetPoint("RIGHT", self.keyChips[#self.keyChips], "LEFT", -SP.s, 0)
	self.signButtons = {}
	local prev
	for _, b in ipairs({ { "y", "Sign up" }, { "t", "Tentative" }, { "n", "Can't come" } }) do
		local btn = W.Button(d, b[2], nil, S.control, function() RT:SignUp(b[1]) end)
		btn.status = b[1]
		-- Your answer stays marked, like a picked chip.
		local paint = btn.Paint
		function btn:Paint(state)
			paint(self, state)
			if self.active and not self.disabled then
				Theme.Solid(self.bg, "accent", Theme.ALPHA.selected)
				Theme.SetBorderColor(self, "accent")
			end
		end
		if prev then btn:SetPoint("LEFT", prev, "RIGHT", SP.s, 0) else btn:SetPoint("TOPLEFT", 0, -(RT.SIGN_Y)) end
		self.signButtons[#self.signButtons + 1] = btn
		prev = btn
	end
	self.role = W.Menu(d, {
		width = 110,
		items = function()
			local out = {}
			for _, r in ipairs(SK.Data.ROLES) do out[#out + 1] = { value = r, text = SK.Data.ROLE_NAMES[r] } end
			return out
		end,
		get = function() return (Board.MyRole()) end,
		set = function(v)
			local guid = Compat.PlayerGUID()
			if guid then SK.DB.raidRole[guid] = v end
			local board = Board:Get()
			local mine = RT.selected and board and Board.SignupOf(board, RT.selected, guid)
			if mine then Board:SignUp(RT.selected, mine.s, v) end
			RT:Refresh()
		end,
	})
	self.role:SetPoint("LEFT", prev, "RIGHT", SP.m, 0)
	self.role.tooltip = "Your role for raids (remembered). Until you pick one, it's a guess from your talents."
	-- v0.16.0 (owner: "after signing up and the raid is no longer TBD" I
	-- should be able to go to the soft reserves): opens the Loot page on it.
	self.reserveBtn = W.Button(d, "Reserve loot", 140, S.controlSmall + 2, function()
		if RT.selected then SK.LootTab:ShowRaid(RT.selected) end
	end, "primary")
	self.reserveBtn:SetPoint("TOPRIGHT", 0, -(RT.SIGN_Y + S.control + SP.s - 3))
	self.reserveBtn.tooltip = "Pick your soft reserves for this raid on the Loot page."
	self.mine = Theme.Text(d, "body", "text")
	self.mine:SetPoint("TOPLEFT", 0, -(RT.SIGN_Y + S.control + SP.s))
	self.mine:SetPoint("RIGHT", self.reserveBtn, "LEFT", -SP.s, 0)
	self.mine:SetJustifyH("LEFT")
	self.mine:SetWordWrap(false)
	self.counts = Theme.Text(d, "small", "dim")
	self.counts:SetPoint("TOPLEFT", self.mine, "BOTTOMLEFT", 0, -SP.xs)
	self.ready = Theme.Text(d, "small", "dim")
	self.ready:SetPoint("TOPLEFT", self.counts, "BOTTOMLEFT", 0, -SP.xs)
	self.ready:SetPoint("RIGHT", 0, 0)
	self.ready:SetJustifyH("LEFT")
	self.ready:SetJustifyV("TOP")
	self.ready:SetWordWrap(true)
	self.ready:SetHeight(32)
	self.lineup = W.List(d, {
		columns = RT.LINEUP_COLUMNS, setCell = setLineUpCell,
		-- Officers: click = In, Bench, undecided in turn; right-click = their
		-- character. Everyone else: click = their character.
		onClick = function(r, button, row)
			-- v0.16.4: right-click = a small menu (their character; remove from
			-- this raid for officers and for your own characters).
			if button == "RightButton" and row then return RT.rowMenu:Open(row, RT.RowItems(r)) end
			if Board.OfficerView() then return RT:CyclePlace(r) end
			SK.CharacterTab:ShowCharacter(r.guid)
		end,
		onEnter = function(row, r)
			GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
			Theme.TipLine(GameTooltip, Theme.ClassText(r.name, r.class))
			Theme.TipLine(GameTooltip, r.awayOnly and "Away that day (marked away, not signed up)" or
				(r.statusName .. (r.place and ("  ·  " .. Board.PLACE_NAME[r.place]) or "") ..
				(r.byOfficer and "  ·  added by an officer" or "")), r.awayOnly and "bad" or "dim")
			if Board.OfficerView() and not r.awayOnly then
				Theme.TipLine(GameTooltip, "Click: In, then Bench, then undecided. Right-click: their character, or remove them.",
					"accent", true)
			else
				Theme.TipLine(GameTooltip, "Click to open their character. Right-click for more.", "accent", true)
			end
			GameTooltip:Show()
		end,
	})
	self.rowMenu = W.PopMenu(d, 190)
	self.lineup:SetPoint("TOPLEFT", 0, -(RT.SIGN_Y + S.control + SP.s + 18 + SP.xs + 16 + SP.xs + 32 + SP.s))
	self.lineup:SetPoint("BOTTOMRIGHT")
	self.lineup:SetEmptyText("Nobody has answered yet.")
	self.empty = Theme.Text(d, "body", "dim")
	self.empty:SetPoint("TOPLEFT", 0, -SP.xxs)
	self.empty:SetPoint("RIGHT", 0, 0)
	self.empty:SetJustifyH("LEFT")
	self.empty:SetWordWrap(true)

	self:BuildCalendar(page, top)
	self:BuildGroups(page, top)
	self:BuildAssign(page, top)

	-------------------------------------------------------------------------
	-- Attendance (officers)
	-------------------------------------------------------------------------
	local at = CreateFrame("Frame", nil, page)
	at:SetPoint("TOPLEFT", 0, top)
	at:SetPoint("BOTTOMRIGHT")
	self.attPage = at
	self.recording = Theme.Text(at, "small", "dim")
	self.recording:SetPoint("TOPLEFT", 0, -SP.xs)
	self.recording:SetPoint("RIGHT", 0, 0)
	self.recording:SetJustifyH("LEFT")
	self.recording:SetWordWrap(true)

	local chipsY = -(S.control + SP.m)
	self.modeChips = {}
	prev = nil
	for _, m in ipairs({ { "raids", "By raid" }, { "totals", "Totals" } }) do
		local c = W.Chip(at, m[2], function() s.attView = m[1]; RT:Refresh() end)
		c.value = m[1]
		if prev then c:SetPoint("LEFT", prev, "RIGHT", SP.xs, 0) else c:SetPoint("TOPLEFT", 0, chipsY) end
		self.modeChips[#self.modeChips + 1] = c
		prev = c
	end
	self.dayChips = {}
	local dprev = nil
	for _, dd in ipairs(RT.DAYS) do
		local c = W.Chip(at, dd[2], function() s.attDays = dd[1]; RT:Refresh() end)
		c.value = dd[1]
		if dprev then c:SetPoint("LEFT", dprev, "RIGHT", SP.xs, 0) else c:SetPoint("LEFT", prev, "RIGHT", SP.l, 0) end
		self.dayChips[#self.dayChips + 1] = c
		dprev = c
	end
	local listTop = chipsY - (S.controlSmall + 2) - SP.m
	self.records = W.List(at, {
		columns = RT.RECORD_COLUMNS, setCell = setRecordCell,
		onClick = function(r) RT.record = r.id; RT:Refresh() end,
	})
	self.records:SetPoint("TOPLEFT", 0, listTop)
	self.records:SetPoint("BOTTOMLEFT")
	self.records:SetWidth(RT.ATT_LEFT_W)
	self.records:SetEmptyText("No raids recorded yet.")
	self.people = W.List(at, {
		columns = RT.PEOPLE_COLUMNS, setCell = setPersonCell,
		onClick = function(r) if RT.record then Att:ToggleBench(RT.record, r.guid) end end,
		onEnter = function(row, r)
			GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
			Theme.TipLine(GameTooltip, Theme.ClassText(r.name, r.class))
			Theme.TipLine(GameTooltip, r.resultName, RESULT_TONE[r.result])
			if r.v == 2 then
				if r.changed then
					Theme.TipLine(GameTooltip, "Changed from Signed up to " .. r.signedName .. " on " ..
						date("%a %d %b, %H:%M", r.changed) .. " (" .. RT.BeforeText(r.recAt, r.changed) .. ")",
						r.changedLate and "spark" or "dim", true)
				end
				Theme.TipLine(GameTooltip, r.benchAuto and "Bench ticked: officers had them on the Bench." or
					"Bench is ticked by itself for people on the Bench who were online.", "faint", true)
			else
				Theme.TipDouble(GameTooltip, "In the raid group", math.floor(r.inS / 60 + 0.5) .. " min", "dim", "text")
				Theme.TipDouble(GameTooltip, "Online, not in the group", math.floor(r.bnS / 60 + 0.5) .. " min", "dim", "text")
				Theme.TipLine(GameTooltip, r.benchAuto and "Bench was ticked automatically." or "Bench wasn't ticked automatically.", "faint")
			end
			Theme.TipLine(GameTooltip, "Click to tick or untick Bench", "accent")
			GameTooltip:Show()
		end,
	})
	self.people:SetPoint("TOPLEFT", RT.ATT_LEFT_W + SP.xl, listTop)
	self.people:SetPoint("BOTTOMRIGHT")
	self.people:SetEmptyText("Pick a raid on the left.")
	self.totals = W.List(at, { columns = RT.TOTAL_COLUMNS, setCell = setTotalCell })
	self.totals:SetPoint("TOPLEFT", 0, listTop)
	self.totals:SetPoint("BOTTOMRIGHT")
	self.totals:SetEmptyText("No raids recorded in this period.")
	self.totals.sortCol = 1

	SK:On("RAIDS_UPDATED", function() if page:IsShown() then RT:Refresh() end end)
	SK:On("ATTENDANCE_UPDATED", function() if page:IsShown() then RT:Refresh() end end)
	SK:On("ROSTER_UPDATED", function() if page:IsShown() then SK:Debounce("raidstab", 1, function() RT:Refresh() end) end end)
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
function RT:SignUp(status)
	if not RT.selected then return end
	local role = Board.MyRole()
	local ok, why = Board:SignUp(RT.selected, status, role)
	if not ok then SK:Print("Couldn't answer: %s.", tostring(why)) end
	RT:Refresh()
end

-- v0.14.0: officers make a raid from a Calendar day (the day box). The
-- form remembers the time and instances: settings.newRaid = { minutes,
-- keys = { "ony", ... } } (no instance = to be decided). Returns the event
-- or nil and why.
function RT:CreateRaid(dayAt)
	local form = RT.NewRaidForm()
	local at = Board.StartAt(Board.DayStart(dayAt or Compat.Now(), 0), form.minutes or 20 * 60)
	-- v0.16.0: form.weeks > 1 = a weekly series. Returns the first raid,
	-- or nil and why; and how many were made.
	local list, why = Board:CreateSeries(form.keys, at, form.weeks or 1)
	local e = list and list[1]
	if e then RT.selected = e.id end
	RT:Refresh()
	return e, why, list and #list or 0
end

-- "Just this day", "Weekly, 4 raids" ... (the day box's Repeat menu).
function RT.RepeatItems()
	local out = { { value = 1, text = "Just this day" } }
	for n = 2, Board.MAX_WEEKS do out[#out + 1] = { value = n, text = "Weekly, " .. n .. " raids" } end
	return out
end

function RT.NewRaidForm()
	local s = SK.DB.settings
	s.newRaid = type(s.newRaid) == "table" and s.newRaid or {}
	local form = s.newRaid
	if type(form.keys) ~= "table" then form.keys = { form.raid or "ony" } end
	return form
end

-- Officers: the night's instances, toggled one at a time.
function RT.ToggleKey(keys, key)
	local out, had = {}, false
	for _, k in ipairs(keys) do
		if k == key then had = true else out[#out + 1] = k end
	end
	if not had then out[#out + 1] = key end
	return Board.ParseKeys(table.concat(out, ",")) or {}
end

-- Officers: undecided -> In -> Bench -> undecided.
RT.NEXT_PLACE = { i = "b", b = "-" }
-- v0.16.2 (owner: keep Away and Can't come separate, count them together):
-- "3 can't come (1 away)". Away = no answer but marked away that day, or
-- answered Can't come and marked away. Pure.
function RT.OutText(rows)
	local out, away = 0, 0
	for _, r in ipairs(rows) do
		if r.awayOnly then
			out, away = out + 1, away + 1
		elseif r.group == "out" then
			out = out + 1
			if r.away then away = away + 1 end
		end
	end
	return out .. " can't come" .. (away > 0 and (" (" .. Theme.Paint("bad", away .. " away") .. ")") or "")
end

-- v0.16.4: the line-up's right-click menu. Remove = officers, or one of
-- your own characters; not for "Away" rows (nothing to remove).
function RT.RowItems(r)
	local items = { { text = "Open their character", onClick = function() SK.CharacterTab:ShowCharacter(r.guid) end } }
	local own = SK.DB.account[r.guid] ~= nil or r.guid == Compat.PlayerGUID()
	if not r.awayOnly and (own or Board.OfficerView()) then
		items[#items + 1] = { text = "Remove from this raid", onClick = function() RT:RemoveRow(r) end }
	end
	return items
end

function RT:RemoveRow(r)
	if not RT.selected then return end
	local ok, why = Board:RemoveSignup(RT.selected, r.guid)
	if ok then SK:Print("%s was taken off this raid.", r.name)
	else SK:Print("Couldn't remove them: %s.", tostring(why)) end
	RT:Refresh()
end

function RT:CyclePlace(r)
	if not RT.selected then return end
	if r.awayOnly then return SK.CharacterTab:ShowCharacter(r.guid) end -- not signed up: nothing to place
	local ok, why = Board:SetPlace(RT.selected, r.guid, RT.NEXT_PLACE[r.place or ""] or "i")
	if not ok then SK:Print("Couldn't change it: %s.", tostring(why)) end
	RT:Refresh()
end

function RT:CopyDiscord()
	local board = Board:Get()
	local ev = board and RT.selected and board.events[RT.selected]
	if not ev then return end
	local rows, sum = Board.LineUp(board, ev, RT.Ctx())
	SK.DebugWindow:ShowText("Copy for Discord", Board.DiscordText(ev, rows, sum))
end

-- Officers (v0.12.0): the code for Short Royalty's Discord bot.
function RT:CopyBot()
	local board = Board:Get()
	local ev = board and RT.selected and board.events[RT.selected]
	if not ev then return end
	local rows = Board.LineUp(board, ev, RT.Ctx())
	SK.DebugWindow:ShowText("Post with the Discord bot", Board.BotCode(ev, rows, board.signups[ev.id], Compat.Now()))
end

-- Officers: paste sign-ups from Discord.
function RT:ImportDiscord()
	local id = RT.selected
	if not id then return end
	SK.DebugWindow:AskText("Import sign-ups from Discord",
		"Paste the sign-up list from Discord (the bot's Copy for the addon, or any list), then press Import. " ..
			"Names must match characters in the guild.",
		"Import", function(text) return RT.DoImport(id, text) end)
end

-- Returns the line shown under the paste box. Pure apart from the board.
function RT.DoImport(id, text)
	local guild = SK.DBM:Guild()
	local members = {}
	for guid, m in pairs(guild and guild.members or {}) do
		if not m.leftAt then members[guid] = { name = m.name } end
	end
	local parsed = Board.ParseImport(text, members)
	local added, updated, kept = Board:Import(id, parsed.entries)
	if not added then return Theme.Paint("bad", "Not imported: " .. tostring(updated)) end
	local msg = string.format("Added %d, updated %d, kept %d (signed up in game themselves).", added, updated, kept)
	if #parsed.unmatched > 0 then
		msg = msg .. " Not matched: " .. table.concat(parsed.unmatched, "; ", 1, math.min(#parsed.unmatched, 6)) ..
			(#parsed.unmatched > 6 and (" and " .. (#parsed.unmatched - 6) .. " more") or "")
	end
	RT:Refresh()
	return msg
end

function RT:DetailOptions()
	local items = {
		{ text = "Copy the line-up as text", onClick = function() RT:CopyLineUp() end },
		{ text = "Copy for Discord", onClick = function() RT:CopyDiscord() end },
	}
	if Board.OfficerView() and RT.selected then
		items[#items + 1] = { text = "Post with the Discord bot", onClick = function() RT:CopyBot() end }
		items[#items + 1] = { text = "Import sign-ups from Discord", onClick = function() RT:ImportDiscord() end }
		items[#items + 1] = { text = "Cancel this raid", onClick = function()
			local ok, why = Board:Cancel(RT.selected)
			if not ok then SK:Print("Couldn't cancel: %s.", tostring(why)) end
			RT.selected = nil
			RT:Refresh()
		end }
		-- v0.16.0: a weekly series.
		local board = Board:Get()
		local later = board and #Board.SeriesFrom(board, RT.selected) or 0
		if later > 1 then
			items[#items + 1] = { text = "Cancel this and the " .. (later - 1) .. " later in the series", onClick = function()
				local n = Board:CancelSeries(RT.selected)
				SK:Print("Cancelled %d raids.", n)
				RT.selected = nil
				RT:Refresh()
			end }
		end
	end
	return items
end

function RT:CopyLineUp()
	local board = Board:Get()
	local ev = board and RT.selected and board.events[RT.selected]
	if not ev then return end
	local rows, sum = Board.LineUp(board, ev, RT.Ctx())
	SK.DebugWindow:ShowText("Raid line-up", Board.Text(ev, rows, sum))
end

function RT:ShowRaid(id)
	RT.selected = id
	SK.DB.settings.raidsView = "upcoming"
	SK.MainFrame:Select("raids")
end

RT.Ctx = Board.Ctx

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
function RT:Description()
	if RT.View(Board.OfficerView()) == "calendar" then
		return Board.OfficerView() and "Click a day to make a raid on it, or to mark yourself away."
			or "Click a day to mark yourself away. Officers see it when they plan raids."
	end
	if Board.OfficerView() then return "Guild raids, sign-ups and attendance (officer tools on: /sr officer turns them off)" end
	return "Guild raids made by officers and raid leaders. Sign up here so they know who's coming."
end

function RT:RefreshUpcoming(board, now, me)
	local rows = RT.EventRows(board or Board.New(), now, me)
	local found = false
	for _, r in ipairs(rows) do if r.id == RT.selected then found = true end end
	if not found then RT.selected = rows[1] and rows[1].id or nil end
	self.events:SetItems(rows)
	self.events:SetSelected(function(r) return r.id == RT.selected end)
	self.events:SetEmptyText(Board.OfficerView() and "No raids yet. Make one on the Calendar: click a day."
		or "No raids yet. Officers and raid leaders make them.")

	local ev = board and RT.selected and board.events[RT.selected]
	local shown = ev ~= nil
	for _, f in ipairs({ self.title, self.sub, self.options, self.role, self.mine, self.counts, self.ready, self.lineup,
		self.answerLabel }) do
		f:SetShown(shown)
	end
	local officer = Board.OfficerView()
	for _, c in ipairs(self.keyChips) do c:SetShown(shown and officer) end
	self.officerLabel:SetShown(shown and officer)
	self.reserveBtn:SetShown(false)
	for _, b in ipairs(self.signButtons) do b:SetShown(shown) end
	self.empty:SetShown(not shown)
	if not shown then
		self.empty:SetText(#rows == 0 and "When a raid is made it shows here, and you can sign up with one click." or "")
		return
	end
	local creator = SK.Identity:Member(ev.by)
	local keys = Board.Keys(ev)
	local size = Board.EventSize(ev)
	self.title:SetText(Board.EventName(ev, #keys > 1) .. (size and (" (" .. size .. ")") or ""))
	local on = {}
	for _, k in ipairs(keys) do on[k] = true end
	for _, c in ipairs(self.keyChips) do c:SetActive(on[c.value] == true) end
	-- v0.16.2: the line stops before the officers' instance chips (a long
	-- name ran under them).
	self.sub:ClearAllPoints()
	self.sub:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -SP.xs)
	if officer then
		self.sub:SetPoint("RIGHT", self.officerLabel, "LEFT", -SP.s, 0)
	else
		self.sub:SetPoint("RIGHT", self.detail, "RIGHT", 0, 0)
	end
	self.sub:SetText(Board.When(ev.at) .. (creator and ("  ·  made by " .. Theme.ClassText(creator.name, creator.class)) or ""))
	local mine = Board.SignupOf(board, ev.id, me)
	for _, b in ipairs(self.signButtons) do
		b.active = mine ~= nil and mine.s == b.status
		b:Paint("rest")
	end
	self.role:Refresh()
	-- Reserve loot: signed up or tentative, and the instances are decided.
	local canReserve = mine ~= nil and (mine.s == "y" or mine.s == "t") and #keys > 0 and not ev.x
	self.reserveBtn:SetShown(canReserve)
	if canReserve then
		local R = SK.Reserves
		local picks = #R:MyPicks(ev.id)
		self.reserveBtn:SetText(string.format("Reserve loot  %d/%d", picks, R.EventPicks(R:State(), ev)))
	end
	local myGroup = SK.RaidGroups.SlotOf(board, SK.RaidGroups.SlotId(ev), me or "")
	self.mine:SetText(RT.MineText(mine, Board.PlaceOf(board, ev.id, me or ""), myGroup,
		SK.RaidAssign.JobsOf(board, ev.id, me or "")))
	local rows2, sum = Board.LineUp(board, ev, RT.Ctx())
	-- v0.16.2: players away that day who didn't answer, after everyone else.
	local awayRows = Board.AwayRows(board, ev, RT.Ctx(), rows2, Board.OfficerView() and SK.OfficerDir:Get() or nil)
	for _, r in ipairs(awayRows) do rows2[#rows2 + 1] = r end
	self.counts:SetText(Board.CountsText(sum) .. "  ·  " .. sum.maybe .. " tentative  ·  " .. RT.OutText(rows2))
	local parts = {}
	for i, r in ipairs(Board.Readiness(sum)) do
		if i > 4 then break end
		parts[#parts + 1] = Theme.Paint(r.tone, r.text)
	end
	self.ready:SetText(table.concat(parts, C("faint") .. "  ·  |r"))
	self.lineup:SetItems(rows2)
end

function RT:RefreshAttendance(now)
	local s = SK.DB.settings
	local mode = s.attView == "totals" and "totals" or "raids"
	local days = s.attDays or 30
	local store = Att:Store() or {}
	local list = Att.Sorted(store)
	if not RT.record or not store[RT.record] then RT.record = Att.checking and Att.checking.id or (list[1] and list[1].id) end
	local rec = RT.record and store[RT.record]
	self.recording:SetText(RT.RecordingText(Att.checking, now, mode == "raids" and rec or nil))
	for _, c in ipairs(self.modeChips) do c:SetActive(c.value == mode) end
	for _, c in ipairs(self.dayChips) do
		c:SetShown(mode == "totals")
		c:SetActive(c.value == days)
	end
	self.records:SetShown(mode == "raids")
	self.people:SetShown(mode == "raids")
	self.totals:SetShown(mode == "totals")
	if mode == "raids" then
		self.records:SetItems(list)
		self.records:SetSelected(function(r) return r.id == RT.record end)
		local rows = rec and Att.Rows(rec) or {}
		for _, r in ipairs(rows) do r.recAt = rec.at end
		self.people:SetItems(rows)
	else
		self.totals:SetItems(Att.Totals(Att.Sorted(store, days > 0 and (now - days * 86400) or nil)))
	end
end

function RT:Refresh()
	if not self.page then return end
	local officer = Board.OfficerView()
	for _, t in ipairs(self.views.tabs) do t:SetShown(not RT.OFFICER_VIEWS[t.key] or officer) end
	local view = RT.View(officer)
	self.views:SetActive(view)
	self.upcoming:SetShown(view == "upcoming")
	self.attPage:SetShown(view == "attendance")
	self.calPage:SetShown(view == "calendar")
	self.grpPage:SetShown(view == "groups")
	self.asgPage:SetShown(view == "assign")
	if view ~= "groups" then RT:CancelCarry() end
	if view ~= "calendar" then RT:CloseDay() end
	if SK.MainFrame.current == "raids" then SK.MainFrame:UpdateHeader() end
	local now = Compat.Now()
	if view == "upcoming" then
		self:RefreshUpcoming(Board:Get(), now, Compat.PlayerGUID())
	elseif view == "groups" then
		self:RefreshGroups(now)
	elseif view == "assign" then
		self:RefreshAssign(now)
	elseif view == "calendar" then
		self:RefreshCalendar(now)
	else
		self:RefreshAttendance(now)
	end
end

---------------------------------------------------------------------------
-- Groups page (v0.11.0): the raid's groups of five. Officers drag a name
-- (or click it, then click where it goes) into a group, onto the Bench or
-- back to Available; dropping on someone swaps the two. Right-click marks
-- late, leaving early, absent. Everyone else sees it read-only.
---------------------------------------------------------------------------
RT.GRP_SIDE_W = 200
RT.GRP_W = S.contentW - RT.GRP_SIDE_W - SP.l
RT.GRP_COLS = 4
RT.GRP_ROW = 18
local ROLE_LETTER = { TANK = "T", HEALER = "H", DPS = "D" }
local MARK_TONE = { l = "spark", e = "spark", a = "bad" }

-- One player's line: name in class colour, role letter, mark. Pure.
function RT.SlotText(r)
	if not r then return Theme.Paint("faint", "empty") end
	local mark = r.mark and r.mark ~= "" and (" " .. Theme.Paint(MARK_TONE[r.mark], SK.RaidGroups.MARK_SHORT[r.mark])) or ""
	if r.away then mark = mark .. " " .. Theme.Paint("bad", "away") end
	return Theme.ClassText(r.name, r.class) .. " " .. Theme.Paint(r.roleGuess and "faint" or "dim", ROLE_LETTER[r.role or ""] or "?") .. mark
end

-- What the line under the menu says.
function RT.GroupsHint(officer, mine)
	if officer then
		return "Drag a name into a group, onto the Bench or back to Available (or click it, then click where it goes). " ..
			"Right-click: late, leaving early, absent."
	end
	if mine and mine > 0 then return "You're in group " .. mine .. "." end
	return "Officers and raid leaders arrange the groups; you'll see yours here."
end

-- The upcoming raids, for the Groups and Assignments menus.
function RT.RaidItems()
	local out, now = {}, Compat.Now()
	for _, e in ipairs(Board.Upcoming(Board:Get() or Board.New(), now)) do
		out[#out + 1] = { value = e.id, text = Board.ShortWhen(e.at, now) .. "  " .. Board.EventName(e, true) }
	end
	return out
end

local function dropTarget(frame, target)
	frame.drop = target
	RT.dropTargets[#RT.dropTargets + 1] = frame
end

function RT:BuildGroups(page, top)
	local gp = CreateFrame("Frame", nil, page)
	gp:SetPoint("TOPLEFT", 0, top)
	gp:SetPoint("BOTTOMRIGHT")
	gp:Hide()
	self.grpPage = gp
	RT.dropTargets = {}
	self.grpMenu = W.Menu(gp, {
		width = 260,
		items = RT.RaidItems,
		get = function() return RT.selected end,
		set = function(v) RT.selected, RT.setupMsg = v, nil; RT:Refresh() end,
	})
	self.grpMenu:SetPoint("TOPLEFT", 0, 0)
	-- Officers: set the game's group up from the plan, one step per press.
	self.grpSetup = W.Button(gp, "Invite & arrange", nil, S.control, function()
		RT.setupMsg = SK.RaidGroups:Setup(RT.selected, RT.grpKey)
		RT:Refresh()
	end, "primary")
	self.grpSetup:SetPoint("TOPRIGHT", 0, 0)
	self.grpFill = W.Button(gp, "Auto-fill", nil, S.control, function()
		local placed, benched = SK.RaidGroups:Fill(RT.selected, RT.grpKey)
		RT.setupMsg = placed and string.format("Auto-fill: %s placed, %d on the bench. Move anyone you like.",
			Theme.Count(placed, "player"), benched) or tostring(benched)
		RT:Refresh()
	end)
	self.grpFill:SetPoint("RIGHT", self.grpSetup, "LEFT", -SP.s, 0)
	self.grpFill.tooltip = "Fills the empty spots from the sign-ups: signed up before tentative, then attendance and " ..
		"item level; enough tanks and healers; nobody marked away. What you've placed stays."
	self.grpSetup.tooltip = "Invites everyone In who is online, makes it a raid, then moves everyone into their group. " ..
		"Press it again after each step (the game asks for a press to make a raid)."
	self.grpCounts = Theme.Text(gp, "small", "dim")
	self.grpCounts:SetPoint("LEFT", self.grpMenu, "RIGHT", SP.m, 0)
	self.grpCounts:SetPoint("RIGHT", self.grpFill, "LEFT", -SP.m, 0)
	self.grpCounts:SetJustifyH("RIGHT")
	self.grpCounts:SetWordWrap(false)
	-- v0.14.0: a night with several instances has groups per instance.
	self.grpKeys = {}
	local kprev
	local avail = SK.Data.ShownAttunements()
	for i = #avail, 1, -1 do
		local r = avail[i]
		local c = W.Chip(gp, r.short or r.name, function()
			RT.grpKey = r.key
			RT:CancelCarry()
			RT:Refresh()
		end)
		c.value = r.key
		c.tooltip = "Groups for " .. r.name .. " (this night has more than one raid)."
		if kprev then c:SetPoint("RIGHT", kprev, "LEFT", -SP.xxs, 0) else c:SetPoint("TOPRIGHT", 0, -(S.control + SP.xs)) end
		self.grpKeys[#self.grpKeys + 1] = c
		kprev = c
	end
	self.grpKeysLeft = kprev
	self.grpHint = Theme.Text(gp, "small", "faint")
	self.grpHint:SetPoint("TOPLEFT", 0, -(S.control + SP.s))
	self.grpHint:SetPoint("RIGHT", 0, 0)
	self.grpHint:SetJustifyH("LEFT")
	self.grpHint:SetWordWrap(false)
	local y0 = S.control + SP.s + 16 + SP.s
	local colW = math.floor(RT.GRP_W / RT.GRP_COLS)
	local boxH = RT.GRP_ROW * (SK.RaidGroups.SIZE + 1) + SP.xs
	self.grpBoxes = {}
	for g = 1, SK.RaidGroups.MAX_GROUPS do
		local box = CreateFrame("Frame", nil, gp)
		box:SetSize(colW - SP.xs, boxH)
		box:SetPoint("TOPLEFT", ((g - 1) % RT.GRP_COLS) * colW, -(y0 + math.floor((g - 1) / RT.GRP_COLS) * (boxH + SP.s)))
		Theme.Panel(box, { bg = "surface", border = "line" })
		box:EnableMouse(true)
		box.title = Theme.Text(box, "label", "dim")
		box.title:SetPoint("TOPLEFT", SP.s, -SP.xxs - 1)
		box.title:SetText(("Group " .. g):upper())
		box:SetScript("OnMouseUp", function(selfBox, button)
			if button == "LeftButton" and RT.carry then RT:DropOn(selfBox.drop) end
		end)
		dropTarget(box, { kind = "group", n = g })
		box.slots = {}
		for i = 1, SK.RaidGroups.SIZE do
			local b = CreateFrame("Button", nil, box)
			b:SetHeight(RT.GRP_ROW)
			b:SetPoint("TOPLEFT", SP.xs, -(RT.GRP_ROW * i))
			b:SetPoint("RIGHT", -SP.xs, 0)
			b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			b:RegisterForDrag("LeftButton")
			b.hl = b:CreateTexture(nil, "BACKGROUND")
			b.hl:SetAllPoints()
			Theme.Solid(b.hl, "accent", Theme.ALPHA.selected)
			b.hl:Hide()
			b.text = Theme.Text(b, "small", "text")
			b.text:SetPoint("LEFT", SP.xs, 0)
			b.text:SetPoint("RIGHT", -SP.xxs, 0)
			b.text:SetJustifyH("LEFT")
			b.text:SetWordWrap(false)
			b:SetScript("OnClick", function(selfB, button) RT:SlotClick(selfB.item, selfB.drop, button) end)
			b:SetScript("OnDragStart", function(selfB) if selfB.item then RT:StartCarry(selfB.item, true) end end)
			b:SetScript("OnDragStop", function() RT:StopDrag() end)
			b:SetScript("OnEnter", function(selfB) RT:SlotTip(selfB, selfB.item) end)
			b:SetScript("OnLeave", function() GameTooltip:Hide() end)
			b.item = false
			dropTarget(b, { kind = "group", n = g, slot = true })
			box.slots[i] = b
		end
		self.grpBoxes[g] = box
	end
	-- Right side: Available (signed up, not placed) and Bench.
	local side = CreateFrame("Frame", nil, gp)
	side:SetPoint("TOPLEFT", RT.GRP_W + SP.l, -y0)
	side:SetPoint("BOTTOMRIGHT")
	local function sideList(title, kind)
		local l = W.List(side, {
			columns = { { key = "name", title = title, width = RT.GRP_SIDE_W - SP.m } },
			setCell = function(fs, r) fs:SetText(RT.SlotText(r)) end,
			onClick = function(r, button) RT:SlotClick(r, { kind = kind }, button) end,
			onEnter = function(row, r) RT:SlotTip(row, r) end,
			decorate = function(row)
				row:RegisterForDrag("LeftButton")
				row:SetScript("OnDragStart", function(selfRow) if selfRow.item then RT:StartCarry(selfRow.item, true) end end)
				row:SetScript("OnDragStop", function() RT:StopDrag() end)
			end,
		})
		l:EnableMouse(true)
		l:SetScript("OnMouseUp", function(selfL, button) if button == "LeftButton" and RT.carry then RT:DropOn(selfL.drop) end end)
		dropTarget(l, { kind = kind })
		return l
	end
	self.grpAvail = sideList("Available", "available")
	self.grpAvail:SetPoint("TOPLEFT")
	self.grpAvail:SetPoint("TOPRIGHT")
	self.grpAvail:SetHeight(230)
	self.grpBench = sideList("Bench", "bench")
	self.grpBench:SetPoint("TOPLEFT", self.grpAvail, "BOTTOMLEFT", 0, -SP.s)
	self.grpBench:SetPoint("BOTTOMRIGHT")
	self.grpEmpty = Theme.Text(gp, "body", "dim")
	self.grpEmpty:SetPoint("TOPLEFT", 0, -y0)
	self.grpEmpty:SetWidth(RT.GRP_W)
	self.grpEmpty:SetJustifyH("LEFT")
	self.grpEmpty:SetWordWrap(true)
	-- The name that follows the cursor while dragging.
	local drag = CreateFrame("Frame", nil, UIParent)
	drag:SetSize(160, RT.GRP_ROW)
	drag:SetFrameStrata("TOOLTIP")
	Theme.Panel(drag, { bg = "raised", border = "accent" })
	drag.text = Theme.Text(drag, "small", "text")
	drag.text:SetPoint("LEFT", SP.xs, 0)
	drag:Hide()
	drag:SetScript("OnUpdate", function(selfD)
		local x, y = GetCursorPosition()
		local sc = UIParent:GetEffectiveScale()
		selfD:ClearAllPoints()
		selfD:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / sc + 12, y / sc - 8)
	end)
	self.grpDrag = drag
	gp:SetScript("OnHide", function() RT:CancelCarry() end)
end

function RT:SlotTip(owner, r)
	if not r then return end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	Theme.TipLine(GameTooltip, Theme.ClassText(r.name, r.class))
	Theme.TipLine(GameTooltip, r.statusName .. (r.role and ("  ·  " .. SK.Data.ROLE_NAMES[r.role]) or "") ..
		(r.mark and r.mark ~= "" and ("  ·  " .. SK.RaidGroups.MARK_NAME[r.mark]) or ""), "dim")
	if r.ilvl then Theme.TipLine(GameTooltip, string.format("Item level %.0f%s", r.ilvl, r.tree and ("  ·  " .. r.tree) or ""), "dim") end
	if Board.OfficerView() then
		Theme.TipLine(GameTooltip, "Drag (or click) to move. Right-click: late, leaving early, absent.", "accent", true)
	end
	GameTooltip:Show()
end

-- Officers: pick a player up (drag, or a click), put them down on a click.
function RT:StartCarry(r, dragging)
	if not Board.OfficerView() or not RT.selected then return end
	RT.carry = { guid = r.guid, name = r.name }
	RT.dragging = dragging and true or false
	if dragging then
		self.grpDrag.text:SetText(RT.SlotText(r))
		self.grpDrag:Show()
	end
	RT:Refresh()
end

function RT:CancelCarry()
	RT.carry, RT.dragging = nil, false
	if self.grpDrag then self.grpDrag:Hide() end
end

-- Drag ended: drop on whatever is under the cursor (a filled slot first,
-- so dropping on a player swaps), else nothing.
function RT:StopDrag()
	if not RT.carry then return end
	self.grpDrag:Hide()
	local best
	for _, f in ipairs(RT.dropTargets) do
		if f:IsVisible() and f:IsMouseOver() and (not best or (f.drop.slot and not best.drop.slot)) then best = f end
	end
	if best then
		RT:DropOn(best.drop, type(best.item) == "table" and best.item.guid or nil)
	else
		RT:CancelCarry()
		RT:Refresh()
	end
end

function RT:DropOn(target, onto)
	local carry = RT.carry
	RT:CancelCarry()
	if not carry or not target or not RT.selected then return RT:Refresh() end
	local t = { kind = target.kind, n = target.n }
	local ok, why = SK.RaidGroups:Move(RT.selected, carry.guid, t, onto ~= carry.guid and onto or nil, RT.grpKey)
	if not ok then SK:Print("Couldn't move %s: %s.", tostring(carry.name), tostring(why)) end
	RT:Refresh()
end

-- A click on a player or a slot.
function RT:SlotClick(r, target, button)
	if button == "RightButton" then
		if r and Board.OfficerView() and RT.selected then
			local ok, why = SK.RaidGroups:CycleMark(RT.selected, r.guid, RT.grpKey)
			if not ok then SK:Print("Couldn't mark them: %s.", tostring(why)) end
			RT:Refresh()
		elseif r then
			SK.CharacterTab:ShowCharacter(r.guid)
		end
		return
	end
	if not Board.OfficerView() then
		if r then SK.CharacterTab:ShowCharacter(r.guid) end
		return
	end
	if RT.carry then
		if r and r.guid == RT.carry.guid then RT:CancelCarry(); return RT:Refresh() end
		return RT:DropOn(target, r and r.guid or nil)
	end
	if r then RT:StartCarry(r, false) end
end

function RT:RefreshGroups(now)
	local board = Board:Get() or Board.New()
	local me = Compat.PlayerGUID()
	local up = Board.Upcoming(board, now)
	local found = false
	for _, e in ipairs(up) do if e.id == RT.selected then found = true end end
	if not found then RT.selected = up[1] and up[1].id or nil end
	self.grpMenu:Refresh()
	local ev = RT.selected and board.events[RT.selected]
	local officer = Board.OfficerView()
	for _, box in ipairs(self.grpBoxes) do box:Hide() end
	self.grpAvail:SetShown(ev ~= nil)
	self.grpBench:SetShown(ev ~= nil)
	self.grpEmpty:SetShown(ev == nil)
	local keys = ev and Board.Keys(ev) or {}
	local want = {}
	for _, k in ipairs(keys) do want[k] = true end
	if not want[RT.grpKey or ""] then RT.grpKey = keys[1] end
	for _, c in ipairs(self.grpKeys) do
		c:SetShown(#keys > 1 and want[c.value] == true)
		c:SetActive(c.value == RT.grpKey)
	end
	self.grpHint:ClearAllPoints()
	self.grpHint:SetPoint("TOPLEFT", 0, -(S.control + SP.s))
	if #keys > 1 then self.grpHint:SetPoint("RIGHT", self.grpKeysLeft, "LEFT", -SP.s, 0) else self.grpHint:SetPoint("RIGHT", 0, 0) end
	if ev and #keys == 0 then
		-- To be decided: groups come once the night's instances are picked.
		self.grpAvail:Hide()
		self.grpBench:Hide()
		self.grpEmpty:Show()
		ev = nil
		self.grpEmptyText = officer and "This raid is still to be decided. Pick its instance(s) on the Raids page " ..
			"(the chips next to its title), then arrange the groups here."
			or "This raid is still to be decided. Groups come once the officers pick the instance(s)."
	else
		self.grpEmptyText = nil
	end
	if not ev then
		self.grpSetup:Hide()
		self.grpFill:Hide()
		self.grpCounts:SetText("")
		self.grpHint:SetText("")
		self.grpEmpty:SetText(self.grpEmptyText or "No raids yet. When one is made, its groups show here.")
		return
	end
	local rows, sum = Board.LineUp(board, ev, RT.Ctx())
	local L = SK.RaidGroups.Layout(board, ev, rows, RT.grpKey)
	local marks = {}
	for _, k in ipairs({ "l", "e", "a" }) do
		if L.marks[k] > 0 then marks[#marks + 1] = SK.RaidGroups.MARK_NAME[k] .. " " .. L.marks[k] end
	end
	if (sum.away or 0) > 0 then marks[#marks + 1] = Theme.Paint("bad", "Away " .. sum.away) end
	self.grpCounts:SetText(Board.CountsText(sum) .. (#marks > 0 and ("  ·  " .. table.concat(marks, "  ·  ")) or ""))
	local mine = (SK.RaidGroups.SlotOf(board, L.sid, me or ""))
	if Board.PlaceOf(board, ev.id, me or "") ~= "i" then mine = 0 end
	self.grpSetup:SetShown(officer)
	self.grpFill:SetShown(officer)
	self.grpHint:SetText(RT.carry and Theme.Paint("accent", "Moving " .. RT.carry.name ..
		": click a group, the Bench or Available. Click them again to stop.")
		or (officer and RT.setupMsg and Theme.Paint("text", RT.setupMsg)) or RT.GroupsHint(officer, mine))
	for g = 1, L.count do
		local box = self.grpBoxes[g]
		box:Show()
		local list = L.groups[g]
		box.title:SetText(("Group " .. g):upper() .. "  " .. #list .. "/" .. SK.RaidGroups.SIZE)
		Theme.SetBorderColor(box, (g == mine) and "accent" or "line")
		for i, b in ipairs(box.slots) do
			local r = list[i]
			b.item = r or false -- false, not nil: an empty slot
			b.text:SetText(RT.SlotText(r))
			b.hl:SetShown(r ~= nil and RT.carry ~= nil and r.guid == RT.carry.guid)
		end
	end
	local avail = {}
	for _, r in ipairs(L.unplaced) do avail[#avail + 1] = r end
	for _, r in ipairs(L.available) do avail[#avail + 1] = r end
	self.grpAvail:SetItems(avail)
	self.grpAvail:SetEmptyText(#rows == 0 and "Nobody has signed up yet." or "Everyone signed up is placed.")
	self.grpAvail:SetSelected(function(r) return RT.carry ~= nil and r.guid == RT.carry.guid end)
	self.grpBench:SetItems(L.bench)
	self.grpBench:SetEmptyText("Nobody on the bench.")
	self.grpBench:SetSelected(function(r) return RT.carry ~= nil and r.guid == RT.carry.guid end)
end

---------------------------------------------------------------------------
-- Assignments page (v0.11.0): bosses on the left, the picked boss's jobs
-- in the middle, the players In on the right. Officers: type a boss name
-- and Add boss, add a task line, click a line then click names to put
-- them on it (click again to take them off). Right-click deletes.
---------------------------------------------------------------------------
RT.ASG_BOSS_W = 190
RT.ASG_IN_W = 190
RT.ASG_MID_W = S.contentW - RT.ASG_BOSS_W - RT.ASG_IN_W - 2 * SP.l

-- A line's players as text. Pure apart from the roster.
function RT.LinePlayers(l, guild)
	local names = {}
	for _, g in ipairs(l.g) do
		local m = guild and guild.members[g]
		names[#names + 1] = m and Theme.ClassText(m.name, m.class) or "?"
	end
	return #names > 0 and table.concat(names, ", ") or Theme.Paint("faint", "nobody yet")
end

function RT:BuildAssign(page, top)
	local ap = CreateFrame("Frame", nil, page)
	ap:SetPoint("TOPLEFT", 0, top)
	ap:SetPoint("BOTTOMRIGHT")
	ap:Hide()
	self.asgPage = ap
	self.asgMenu = W.Menu(ap, {
		width = 240,
		items = RT.RaidItems,
		get = function() return RT.selected end,
		set = function(v) RT.selected, RT.asgBlock, RT.asgLine = v, nil, nil; RT:Refresh() end,
	})
	self.asgMenu:SetPoint("TOPLEFT", 0, 0)
	-- Officers: boss name box, Add boss, Copy from last raid.
	local box = CreateFrame("EditBox", nil, ap)
	box:SetSize(150, S.control)
	box:SetAutoFocus(false)
	box:SetMaxLetters(SK.RaidAssign.NAME_MAX)
	box:SetTextInsets(SP.s, SP.s, 0, 0)
	Theme.Font(box, "body", "text")
	Theme.Panel(box, { bg = "surface", border = "lineStrong" })
	box:SetPoint("LEFT", self.asgMenu, "RIGHT", SP.m, 0)
	box:SetScript("OnEnterPressed", function() RT:AddBoss() end)
	box:SetScript("OnEscapePressed", function(selfB) selfB:ClearFocus() end)
	self.asgName = box
	self.asgAdd = W.Button(ap, "Add boss", nil, S.control, function() RT:AddBoss() end, "primary")
	self.asgAdd:SetPoint("LEFT", box, "RIGHT", SP.s, 0)
	self.asgAdd.tooltip = "Type the boss's name (or Trash) in the box, then Add boss."
	self.asgCopy = W.Button(ap, "Copy last raid", nil, S.control, function()
		local n, why = SK.RaidAssign:CopyLast(RT.selected)
		RT.asgMsg = n > 0 and ("Copied " .. Theme.Count(n, "boss", "bosses") .. " from the last raid.") or tostring(why)
		RT:Refresh()
	end)
	self.asgCopy:SetPoint("LEFT", self.asgAdd, "RIGHT", SP.s, 0)
	self.asgCopy.tooltip = "Copies the bosses and jobs from the last raid of the same kind. " ..
		"Players stay on a job only if they're In this raid."
	self.asgHint = Theme.Text(ap, "small", "faint")
	self.asgHint:SetPoint("TOPLEFT", 0, -(S.control + SP.s))
	self.asgHint:SetPoint("RIGHT", 0, 0)
	self.asgHint:SetJustifyH("LEFT")
	self.asgHint:SetWordWrap(false)
	local y0 = S.control + SP.s + 16 + SP.s
	self.asgBosses = W.List(ap, {
		columns = { { key = "name", title = "Bosses", width = RT.ASG_BOSS_W - SP.m } },
		setCell = function(fs, b) fs:SetText(b.name .. Theme.Paint("faint", "  " .. #b.lines)) end,
		onClick = function(b, button)
			if button == "RightButton" and Board.OfficerView() then
				SK.RaidAssign:DeleteBlock(RT.selected, b.key)
				RT.asgBlock = nil
			else
				RT.asgBlock, RT.asgLine = b.key, nil
			end
			RT:Refresh()
		end,
	})
	self.asgBosses:SetPoint("TOPLEFT", 0, -y0)
	self.asgBosses:SetPoint("BOTTOMLEFT")
	self.asgBosses:SetWidth(RT.ASG_BOSS_W)
	local mid = CreateFrame("Frame", nil, ap)
	mid:SetPoint("TOPLEFT", RT.ASG_BOSS_W + SP.l, -y0)
	mid:SetSize(RT.ASG_MID_W, 10)
	mid:SetPoint("BOTTOM")
	self.asgTask = W.Menu(mid, {
		width = 170,
		items = function()
			local out = { { value = "", text = "Add a job…" } }
			for _, t in ipairs(SK.RaidAssign.TASKS) do out[#out + 1] = { value = t[1], text = t[2] } end
			return out
		end,
		get = function() return "" end,
		set = function(v)
			if v ~= "" and RT.asgBlock then
				local ok, why = SK.RaidAssign:AddLine(RT.selected, RT.asgBlock, v)
				if not ok then SK:Print("Couldn't add it: %s.", tostring(why)) end
				RT:Refresh()
			end
		end,
	})
	self.asgTask:SetPoint("TOPLEFT")
	self.asgLines = W.List(mid, {
		columns = { { key = "task", title = "Job", width = 100 }, { key = "who", title = "Who", width = RT.ASG_MID_W - 100 - SP.m } },
		setCell = function(fs, l, col)
			if col.key == "task" then fs:SetText(SK.RaidAssign.TASK_NAME[l.t]) else fs:SetText(RT.LinePlayers(l, SK.DBM:Guild())) end
		end,
		onClick = function(l, button)
			if not Board.OfficerView() then return end
			if button == "RightButton" then
				SK.RaidAssign:RemoveLine(RT.selected, RT.asgBlock, l.index)
				RT.asgLine = nil
			else
				RT.asgLine = (RT.asgLine ~= l.index) and l.index or nil
			end
			RT:Refresh()
		end,
	})
	self.asgLines:SetPoint("TOPLEFT", 0, -(S.control + SP.s))
	self.asgLines:SetPoint("BOTTOMRIGHT")
	self.asgIn = W.List(ap, {
		columns = { { key = "name", title = "In this raid", width = RT.ASG_IN_W - SP.m } },
		setCell = function(fs, r) fs:SetText(RT.SlotText(r)) end,
		onClick = function(r)
			if not (Board.OfficerView() and RT.asgBlock and RT.asgLine) then return end
			local ok, why = SK.RaidAssign:TogglePlayer(RT.selected, RT.asgBlock, RT.asgLine, r.guid)
			if not ok then SK:Print("Couldn't change it: %s.", tostring(why)) end
			RT:Refresh()
		end,
	})
	self.asgIn:SetPoint("TOPRIGHT", 0, -y0)
	self.asgIn:SetPoint("BOTTOMRIGHT")
	self.asgIn:SetWidth(RT.ASG_IN_W)
end

function RT:AddBoss()
	local key, why = SK.RaidAssign:AddBlock(RT.selected, self.asgName:GetText() or "")
	if key then
		RT.asgBlock, RT.asgLine = key, nil
		self.asgName:SetText("")
		self.asgName:ClearFocus()
		RT.asgMsg = nil
	else
		RT.asgMsg = tostring(why)
	end
	RT:Refresh()
end

function RT:RefreshAssign(now)
	local board = Board:Get() or Board.New()
	local up = Board.Upcoming(board, now)
	local found = false
	for _, e in ipairs(up) do if e.id == RT.selected then found = true end end
	if not found then RT.selected = up[1] and up[1].id or nil end
	self.asgMenu:Refresh()
	local ev = RT.selected and board.events[RT.selected]
	local officer = Board.OfficerView() and ev ~= nil
	for _, f in ipairs({ self.asgName, self.asgAdd, self.asgCopy, self.asgTask }) do f:SetShown(officer) end
	local blocks = ev and SK.RaidAssign.Blocks(board, ev.id) or {}
	local block
	for _, b in ipairs(blocks) do if b.key == RT.asgBlock then block = b end end
	if not block then block = blocks[1]; RT.asgBlock = block and block.key or nil; RT.asgLine = nil end
	self.asgBosses:SetItems(blocks)
	self.asgBosses:SetSelected(function(b) return b.key == RT.asgBlock end)
	self.asgBosses:SetEmptyText(not ev and "No raids yet." or officer and "Type a boss name above and press Add boss."
		or "No assignments yet.")
	local lines = {}
	for i, l in ipairs(block and block.lines or {}) do lines[i] = { t = l.t, g = l.g, index = i } end
	if RT.asgLine and not lines[RT.asgLine] then RT.asgLine = nil end
	self.asgLines:SetItems(lines)
	self.asgLines:SetSelected(function(l) return l.index == RT.asgLine end)
	self.asgLines:SetEmptyText(block and (officer and "Add a job with the menu above." or "No jobs for this boss yet.") or "")
	self.asgTask:SetShown(officer and block ~= nil)
	self.asgTask:Refresh()
	local inRows = {}
	if ev then
		local rows = Board.LineUp(board, ev, RT.Ctx())
		for _, r in ipairs(rows) do if r.place == "i" then inRows[#inRows + 1] = r end end
	end
	self.asgIn:SetItems(inRows)
	self.asgIn:SetEmptyText("Nobody is In yet (Groups or the Raids tab).")
	local onLine = {}
	if block and RT.asgLine and block.lines[RT.asgLine] then
		for _, g in ipairs(block.lines[RT.asgLine].g) do onLine[g] = true end
	end
	self.asgIn:SetSelected(function(r) return onLine[r.guid] == true end)
	local jobs = ev and SK.RaidAssign.JobsOf(board, ev.id, Compat.PlayerGUID() or "") or {}
	local hint
	if RT.asgMsg then hint = Theme.Paint("text", RT.asgMsg)
	elseif officer and RT.asgLine then
		hint = Theme.Paint("accent", "Click names on the right to put them on this job (click again to take them off).")
	elseif officer then hint = "Click a job, then names on the right. Right-click a job or a boss to delete it."
	elseif #jobs > 0 then hint = "Your jobs: " .. table.concat(jobs, ", ")
	else hint = ev and "You have no jobs in this raid." or "" end
	self.asgHint:SetText(hint)
end

---------------------------------------------------------------------------
-- Calendar page
---------------------------------------------------------------------------
local RAID_TONE = { y = "good", t = "text", n = "faint" }

function RT:BuildCalendar(page, top)
	local cal = CreateFrame("Frame", nil, page)
	cal:SetPoint("TOPLEFT", 0, top)
	cal:SetPoint("BOTTOMRIGHT")
	cal:Hide()
	self.calPage = cal
	self.calPrev = W.Button(cal, "<", S.control + SP.s, S.control, function() RT:MoveMonth(-1) end)
	self.calPrev:SetPoint("TOPLEFT", 0, 0)
	self.calNext = W.Button(cal, ">", S.control + SP.s, S.control, function() RT:MoveMonth(1) end)
	self.calNext:SetPoint("LEFT", self.calPrev, "RIGHT", SP.xs, 0)
	self.calTitle = Theme.Text(cal, "title", "text")
	self.calTitle:SetPoint("LEFT", self.calNext, "RIGHT", SP.m, 0)
	self.calToday = W.Button(cal, "Today", nil, S.control, function() RT.calMonth = nil; RT:Refresh() end)
	self.calToday:SetPoint("TOPRIGHT", 0, 0)
	-- (v0.16.0: the "Away every" weekday chips were removed, owner; away
	-- dates are entered as a range in the day box.)
	local cw = math.floor(S.contentW / 7)
	local headY = S.control + SP.s
	for i, name in ipairs(RT.WEEKDAYS) do
		local l = Theme.Text(cal, "label", "dim")
		l:SetPoint("TOPLEFT", (i - 1) * cw + SP.xs, -headY)
		l:SetText(name:upper())
	end
	local gridY = headY + W.CARD_LABEL_H
	local ch = math.floor((S.window[2] - S.pageHead - SP.xs - SP.l - S.subTabs - SP.m - gridY) / 6)
	self.calCells = {}
	for i = 1, 42 do
		local c = CreateFrame("Button", nil, cal)
		c:SetSize(cw - SP.xxs, ch - SP.xxs)
		c:SetPoint("TOPLEFT", ((i - 1) % 7) * cw, -(gridY + math.floor((i - 1) / 7) * ch))
		c.bg = c:CreateTexture(nil, "BACKGROUND")
		c.bg:SetAllPoints()
		Theme.Border(c, "line")
		c.dayText = Theme.Text(c, "small", "dim")
		c.dayText:SetPoint("TOPLEFT", SP.xs, -SP.xxs)
		c.awayText = Theme.Text(c, "micro", "faint")
		c.awayText:SetPoint("BOTTOMRIGHT", -SP.xs, SP.xxs)
		c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		c:SetScript("OnEnter", function(selfC)
			local cell = selfC.cell
			if not cell then return end
			GameTooltip:SetOwner(selfC, "ANCHOR_RIGHT")
			Theme.TipLine(GameTooltip, date("%A %d %B", cell.at))
			if cell.away then Theme.TipLine(GameTooltip, "You're away", "bad") end
			if cell.awayCount > 0 then Theme.TipLine(GameTooltip, Theme.Count(cell.awayCount, "player") .. " away", "dim") end
			if not cell.past then
				Theme.TipLine(GameTooltip, Board.OfficerView() and "Click: mark yourself away, or make a raid on this day."
					or "Click: mark yourself away (or not).", "accent")
			end
			GameTooltip:Show()
		end)
		c:SetScript("OnLeave", function() GameTooltip:Hide() end)
		c.lines = {}
		for j = 1, RT.CAL_PER_DAY + 1 do
			local b = CreateFrame("Button", nil, c)
			b:SetHeight(14)
			b:SetPoint("TOPLEFT", SP.xs, -(SP.xxs + 15 + (j - 1) * 14))
			b:SetPoint("RIGHT", -SP.xxs, 0)
			b.text = Theme.Text(b, "micro", "text")
			b.text:SetPoint("LEFT")
			b.text:SetPoint("RIGHT")
			b.text:SetJustifyH("LEFT")
			b.text:SetWordWrap(false)
			b:SetScript("OnClick", function(selfB) if selfB.id then RT:ShowRaid(selfB.id) end end)
			b:SetScript("OnEnter", function(selfB)
				if not selfB.tip then return end
				GameTooltip:SetOwner(selfB, "ANCHOR_RIGHT")
				Theme.TipLine(GameTooltip, selfB.tip)
				Theme.TipLine(GameTooltip, "Click to open the raid", "accent")
				GameTooltip:Show()
			end)
			b:SetScript("OnLeave", function() GameTooltip:Hide() end)
			c.lines[j] = b
		end
		-- v0.14.0: click = the day box (away for everyone; officers make a
		-- raid there). Right-click still toggles away straight away.
		c:SetScript("OnClick", function(selfC, button)
			if button == "RightButton" then
				if selfC.cell and not selfC.cell.past then SK.Absences:ToggleDay(selfC.cell.at) end
				return RT:Refresh()
			end
			RT:CalendarDay(selfC.cell, selfC, i)
		end)
		self.calCells[i] = c
	end
	self:BuildDay(cal)
end

---------------------------------------------------------------------------
-- v0.16.0: the away menu: "Just this day", then "Until Mon 14 Dec" for
-- up to Absences.RANGE_DAYS days. Pure apart from date().
function RT.AwayItems(fromAt)
	local A = SK.Absences
	local out = { { value = 1, text = "Just this day" } }
	if not fromAt then return out end
	for n = 2, A.RANGE_DAYS do
		local at = A.DayAt(fromAt, n - 1)
		out[#out + 1] = { value = n, text = "Until " .. date("%a ", at) .. (date("%d %b", at):gsub("^0", "")) }
	end
	return out
end

---------------------------------------------------------------------------
-- The day box (v0.14.0): click a Calendar day. Everyone: that day's raids
-- and "I'm away this day". Officers: New raid there, with the start time
-- and the night's instances (none picked = to be decided), any day up to
-- a year ahead (Board.AHEAD; v0.15.1, was 60 days).
---------------------------------------------------------------------------
RT.DAY_W = 300
RT.AWAY_MENU_W = 170
RT.DAY_LINES = 4

function RT:BuildDay(cal)
	local box = CreateFrame("Frame", nil, cal)
	box:SetSize(RT.DAY_W, 100)
	box:SetFrameStrata("FULLSCREEN_DIALOG")
	box:EnableMouse(true)
	Theme.Panel(box, { bg = "raised", border = "accent" })
	box:Hide()
	self.dayBox = box
	box.title = Theme.Text(box, "body", "text")
	box.title:SetPoint("TOPLEFT", SP.m, -SP.s)
	box.close = W.CloseButton(box, function() RT:CloseDay() end)
	box.close:SetPoint("TOPRIGHT", -SP.xs, -SP.xs)
	box.lines = {}
	for j = 1, RT.DAY_LINES do
		local b = CreateFrame("Button", nil, box)
		b:SetHeight(16)
		b:SetPoint("LEFT", SP.m, 0)
		b:SetPoint("RIGHT", -SP.m, 0)
		b.text = Theme.Text(b, "small", "text")
		b.text:SetAllPoints()
		b.text:SetJustifyH("LEFT")
		b.text:SetWordWrap(false)
		b:SetScript("OnClick", function(selfB) if selfB.id then RT:CloseDay(); RT:ShowRaid(selfB.id) end end)
		b:SetScript("OnEnter", function(selfB)
			GameTooltip:SetOwner(selfB, "ANCHOR_RIGHT")
			Theme.TipLine(GameTooltip, "Click to open the raid", "accent")
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		box.lines[j] = b
	end
	-- v0.16.0 (owner): away for a range of days, e.g. 10-14 Dec: the day
	-- clicked is the first, the menu picks the last.
	box.awayUntil = W.Menu(box, {
		width = RT.AWAY_MENU_W,
		items = function() return RT.AwayItems(RT.dayCell and RT.dayCell.at) end,
		get = function() return RT.awayDays or 1 end,
		set = function(v)
			RT.awayDays = v
			RT:DrawDay()
		end,
	})
	box.awayUntil.tooltip = "The last day you're away. The day you clicked is the first."
	box.away = W.Button(box, "I'm away", nil, S.control, function()
		local cell = RT.dayCell
		if not cell then return end
		local A = SK.Absences
		if A.Run(A:Saved(), cell.at) then A:ClearRun(cell.at) else A:SetRange(cell.at, RT.awayDays or 1) end
		RT.awayDays = nil
		RT:Refresh()
		RT:DrawDay()
	end)
	box.away.tooltip = "Officers and guildmates see it, and raids you'd signed up for on those days are answered Can't come."
	-- Officers: New raid.
	box.newLabel = Theme.Text(box, "label", "dim")
	box.newLabel:SetText("NEW RAID")
	box.time = W.Menu(box, {
		width = 90,
		items = function()
			local out = {}
			for m = 0, 23 * 60 + 30, 30 do out[#out + 1] = { value = m, text = string.format("%02d:%02d", math.floor(m / 60), m % 60) } end
			return out
		end,
		get = function() return RT.NewRaidForm().minutes or 20 * 60 end,
		set = function(v)
			RT.NewRaidForm().minutes = v
			RT:DrawDay()
		end,
	})
	box.time.tooltip = "Start time, in your own time zone (everyone sees it in theirs)."
	box.keys = {}
	local prev = box.time
	for _, r in ipairs(SK.Data.ShownAttunements()) do
		local c = W.Chip(box, r.short or r.name, function()
			local form = RT.NewRaidForm()
			form.keys = RT.ToggleKey(form.keys, r.key)
			RT:DrawDay()
		end)
		c.value = r.key
		c.tooltip = r.name .. " (" .. (r.size or "?") .. "). Pick one or more, or none: to be decided."
		c:SetPoint("LEFT", prev, "RIGHT", prev == box.time and SP.s or SP.xxs, 0)
		box.keys[#box.keys + 1] = c
		prev = c
	end
	-- v0.16.0: repeat weekly.
	box.repeatMenu = W.Menu(box, {
		width = 170,
		items = RT.RepeatItems,
		get = function() return RT.NewRaidForm().weeks or 1 end,
		set = function(v)
			RT.NewRaidForm().weeks = v
			RT:DrawDay()
		end,
	})
	box.repeatMenu.tooltip = "Make the same raid every week (same day and time), up to " .. Board.MAX_WEEKS ..
		" at once. Each one can be changed or cancelled on its own; the ··· menu cancels the rest of a series."
	box.create = W.Button(box, "Create raid", nil, S.control, function()
		local e, why, n = RT:CreateRaid(RT.dayCell and RT.dayCell.at)
		if e and n > 1 then
			RT.dayResult = Theme.Paint("good", "Made " .. n .. " raids: ") .. Board.EventName(e, true) .. ", " ..
				date("%As %H:%M", e.at) .. ", until " .. date("%d %b", Board.WeeklyStarts(e.at, n)[n])
		elseif e then
			RT.dayResult = Theme.Paint("good", "Made: ") .. Board.EventName(e, true) .. ", " .. date("%H:%M", e.at)
		else
			RT.dayResult = Theme.Paint("bad", "Not made: " .. tostring(why))
		end
		RT:DrawDay()
	end, "primary")
	box.what = Theme.Text(box, "small", "dim")
	box.what:SetJustifyH("LEFT")
	box.what:SetWordWrap(true)
	box.result = Theme.Text(box, "small", "text")
	box.result:SetJustifyH("LEFT")
	box.result:SetJustifyV("TOP")
	box.result:SetWordWrap(true)
end

-- Click on a day: the day box next to it (nothing for days before today).
function RT:CalendarDay(cell, frame, index)
	if not cell or cell.past then return self:CloseDay() end
	if self.dayCell and self.dayCell.at == cell.at and self.dayBox:IsShown() then return self:CloseDay() end
	self.dayCell, self.dayResult, self.awayDays = cell, nil, nil
	local box = self.dayBox
	box:ClearAllPoints()
	if frame then
		local col, row = ((index or 1) - 1) % 7, math.floor(((index or 1) - 1) / 7)
		local h = col >= 4 and "RIGHT" or "LEFT"
		local v = row >= 3 and "BOTTOM" or "TOP"
		box:SetPoint(v .. h, frame, v .. (h == "RIGHT" and "LEFT" or "RIGHT"), h == "RIGHT" and -SP.xxs or SP.xxs, 0)
	else
		box:SetPoint("CENTER")
	end
	box:Show()
	self:DrawDay()
end

function RT:CloseDay()
	if self.dayBox then self.dayBox:Hide() end
	self.dayCell = nil
end

function RT:DrawDay()
	local box, cell = self.dayBox, self.dayCell
	if not box or not cell then return end
	local now = Compat.Now()
	local board = Board:Get() or Board.New()
	-- The cell may be from before a change: find the day's raids again.
	local key = date("%Y-%m-%d", cell.at)
	local raids = {}
	for _, e in pairs(board.events) do
		if not e.x and date("%Y-%m-%d", e.at) == key then raids[#raids + 1] = e end
	end
	table.sort(raids, function(a, b) return a.at < b.at end)
	box.title:SetText(date("%A %d %B", cell.at))
	local y = SP.s + 20
	for j, b in ipairs(box.lines) do
		local e = raids[j]
		if e then
			local me = Compat.PlayerGUID() or ""
			local su = Board.SignupOf(board, e.id, me)
			b.id = e.id
			b.text:SetText(date("%H:%M", e.at) .. "  " .. Board.EventName(e, true) .. Theme.Paint("dim", "  ·  " ..
				(su and Board.STATUS_NAME[su.s] or "not signed up")))
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", SP.m, -y)
			b:SetPoint("RIGHT", -SP.m, 0)
			b:Show()
			y = y + 16
		else
			b.id = nil
			b:Hide()
		end
	end
	if #raids == 0 then y = y + SP.xxs end
	local A = SK.Absences
	local first, last = A.Run(A:Saved(), cell.at)
	box.awayUntil:SetShown(first == nil)
	box.away:ClearAllPoints()
	if first then
		-- Away already: one button clears the whole run (e.g. 10-14 Dec).
		box.away:SetText("Not away " .. A.RangeText(first, last) .. " after all")
		-- v0.16.2: buttons don't resize with their text, so set the width
		-- (the label ran out of the button and the box).
		box.away:SetWidth(RT.DAY_W - 2 * SP.m)
		box.away:SetPoint("TOPLEFT", SP.m, -(y + SP.xs))
	else
		box.away:SetText("I'm away")
		box.away:SetWidth(RT.DAY_W - 2 * SP.m - RT.AWAY_MENU_W - SP.xs)
		box.awayUntil:ClearAllPoints()
		box.awayUntil:SetPoint("TOPLEFT", SP.m, -(y + SP.xs))
		box.awayUntil:Refresh()
		box.away:SetPoint("LEFT", box.awayUntil, "RIGHT", SP.xs, 0)
	end
	y = y + SP.xs + S.control
	local officer = Board.OfficerView()
	-- The start time counts, not the day (v0.15.1: the last day was offered,
	-- then refused).
	local startAt = Board.StartAt(Board.DayStart(cell.at, 0), RT.NewRaidForm().minutes or 20 * 60)
	local canMake = officer and startAt <= now + Board.AHEAD
	for _, f in ipairs({ box.newLabel, box.time, box.repeatMenu, box.create, box.what, box.result }) do f:SetShown(canMake) end
	for _, c in ipairs(box.keys) do c:SetShown(canMake) end
	if canMake then
		box.newLabel:ClearAllPoints()
		box.newLabel:SetPoint("TOPLEFT", SP.m, -(y + SP.m))
		y = y + SP.m + W.CARD_LABEL_H
		box.time:ClearAllPoints()
		box.time:SetPoint("TOPLEFT", SP.m, -y)
		box.time:Refresh()
		local form = RT.NewRaidForm()
		local on = {}
		for _, k in ipairs(form.keys) do on[k] = true end
		for _, c in ipairs(box.keys) do c:SetActive(on[c.value] == true) end
		y = y + S.control + SP.xs
		box.repeatMenu:ClearAllPoints()
		box.repeatMenu:SetPoint("TOPLEFT", SP.m, -y)
		box.repeatMenu:Refresh()
		y = y + S.control + SP.xs
		local probe = { raid = (form.keys[1] or Board.TBD), rs = #form.keys == 1 and nil or table.concat(form.keys, ",") }
		box.what:ClearAllPoints()
		box.what:SetPoint("TOPLEFT", SP.m, -y)
		box.what:SetPoint("RIGHT", -SP.m, 0)
		box.what:SetText(#form.keys == 0 and "No instance picked: the raid is \"to be decided\". Pick them later on the Raids page."
			or (Board.EventName(probe) .. " (" .. Board.EventSize(probe) .. ")"))
		y = y + 28
		box.create:ClearAllPoints()
		box.create:SetPoint("TOPLEFT", SP.m, -y)
		y = y + S.control
		-- v0.15.1: the result on its own lines under the button (it was cut off).
		box.result:ClearAllPoints()
		box.result:SetPoint("TOPLEFT", SP.m, -(y + SP.xs))
		box.result:SetPoint("RIGHT", -SP.m, 0)
		box.result:SetText(RT.dayResult or "")
		box.result:SetShown(RT.dayResult ~= nil)
		if RT.dayResult then y = y + SP.xs + 28 end
	elseif officer then
		y = y + SP.s
		box.what:Show()
		box.what:ClearAllPoints()
		box.what:SetPoint("TOPLEFT", SP.m, -y)
		box.what:SetPoint("RIGHT", -SP.m, 0)
		box.what:SetText("Raids can be made up to a year ahead.")
		y = y + 16
	end
	box:SetHeight(y + SP.m)
end

function RT:MoveMonth(delta)
	local now = Compat.Now()
	local cur = RT.calMonth or { year = tonumber(date("%Y", now)), month = tonumber(date("%m", now)) }
	local y, m = RT.ShiftMonth(cur.year, cur.month, delta)
	RT.calMonth = { year = y, month = m }
	RT:Refresh()
end

function RT:RefreshCalendar(now)
	local cur = RT.calMonth or { year = tonumber(date("%Y", now)), month = tonumber(date("%m", now)) }
	local grid = RT.MonthGrid(cur.year, cur.month, Board:Get() or Board.New(), now, Compat.PlayerGUID(),
		SK.Absences:Mine(now), SK.DBM:Guild())
	self.calTitle:SetText(grid.title)
	for i, c in ipairs(self.calCells) do
		local cell = grid.cells[i]
		c.cell = cell
		if cell.today then
			Theme.Solid(c.bg, "accent", Theme.ALPHA.selected)
			Theme.SetBorderColor(c, "accent")
		else
			Theme.Solid(c.bg, cell.inMonth and "surface" or "void")
			Theme.SetBorderColor(c, "line")
		end
		c.dayText:SetText(tostring(cell.day) .. (cell.away and ("  " .. Theme.Paint("bad", "away")) or ""))
		c.awayText:SetText(cell.awayCount > 0 and (cell.awayCount .. " away") or "")
		c.dayText:SetTextColor(Theme.RGB(cell.today and "text" or (cell.inMonth and not cell.past) and "dim" or "faint"))
		for j, b in ipairs(c.lines) do
			local r = cell.raids[j]
			if j > RT.CAL_PER_DAY and #cell.raids > RT.CAL_PER_DAY then
				b.id, b.tip = cell.raids[RT.CAL_PER_DAY + 1].id, nil
				b.text:SetText(Theme.Paint("dim", "+" .. (#cell.raids - RT.CAL_PER_DAY) .. " more"))
				b:Show()
			elseif r and j <= RT.CAL_PER_DAY then
				b.id = r.id
				local status = r.place == "i" and "You're in" or r.place == "b" and "You're on the bench"
					or r.mine and Board.STATUS_NAME[r.mine] or "Not signed up"
				b.tip = r.text .. "  ·  " .. status
				local tone = r.place == "i" and "good" or r.place == "b" and "accent" or r.mine and RAID_TONE[r.mine] or "text"
				b.text:SetText(Theme.Paint(cell.past and "faint" or tone, r.text))
				b:Show()
			else
				b.id, b.tip = nil, nil
				b:Hide()
			end
		end
	end
end

-- v0.15.0: a wider window (Theme.SetWidth) gives the lists room: a third
-- to the raid lists on the left, the rest to names.
Theme.OnWidth(function()
	local extra = S.contentW - Theme.BASE_CONTENT_W
	local left = math.floor(extra / 3)
	RT.LEFT_W = 270 + left
	RT.RIGHT_W = S.contentW - RT.LEFT_W - SP.xl
	RT.ATT_LEFT_W = 270 + left
	RT.ATT_RIGHT_W = S.contentW - RT.ATT_LEFT_W - SP.xl
	Theme.Grow(RT.EVENT_COLUMNS, "raid", left)
	Theme.Grow(RT.LINEUP_COLUMNS, "name", extra - left)
	Theme.Grow(RT.RECORD_COLUMNS, "raid", left)
	Theme.Grow(RT.PEOPLE_COLUMNS, "name", extra - left)
	Theme.Grow(RT.TOTAL_COLUMNS, "name", extra)
	RT.GRP_SIDE_W = 200 + math.floor(extra / 4)
	RT.GRP_W = S.contentW - RT.GRP_SIDE_W - SP.l
	RT.ASG_BOSS_W = 190 + math.floor(extra / 4)
	RT.ASG_IN_W = 190 + math.floor(extra / 4)
	RT.ASG_MID_W = S.contentW - RT.ASG_BOSS_W - RT.ASG_IN_W - 2 * SP.l
end)

SK.MainFrame:AddTab("raids", "Raids", RT, { group = "guild", icon = Theme.TEX.raids })
