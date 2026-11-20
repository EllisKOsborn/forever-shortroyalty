-- Raids page (v0.8.0). Everyone: upcoming guild raids, who's coming, and
-- Sign up / Tentative / Can't come with a role. Officers and raid leaders
-- who typed /sr officer also get New raid, Cancel and Attendance (shared
-- between officers; v0.8.1: no spreadsheet, it all stays in the addon). The rules live in Core/RaidBoard.lua and
-- Core/Attendance.lua.
local _, SK = ...

local RT = SK:NewModule("RaidsTab")
local Theme, W, Compat = SK.Theme, SK.Widgets, SK.Compat
local Board, Att = SK.RaidBoard, SK.Attendance
local S, SP = Theme.SIZES, Theme.SPACE

RT.VIEWS = { { "upcoming", "Raids" }, { "calendar", "Calendar" }, { "new", "New raid" }, { "attendance", "Attendance" } }
RT.OFFICER_VIEWS = { new = true, attendance = true }
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
RT.PEOPLE_COLUMNS = {
	{ key = "name", title = "Name", width = 140, sort = function(a, b) return a.name:lower() < b.name:lower() end },
	{ key = "signed", title = "Signed up", width = 84 },
	{ key = "result", title = "Result", width = 110 },
	{ key = "bench", title = "Bench", width = 56, align = "CENTER" },
	{ key = "mins", title = "Mins", width = RT.ATT_RIGHT_W - 140 - 84 - 110 - 56 - SP.m, align = "RIGHT",
		sort = function(a, b) return a.inS < b.inS end },
}
local function pctSort(a, b) return (a.pct or -1) < (b.pct or -1) end
RT.TOTAL_COLUMNS = {
	{ key = "name", title = "Name", width = 180, sort = function(a, b) return a.name:lower() < b.name:lower() end },
	{ key = "raids", title = "Raids", width = 70, align = "RIGHT", sort = function(a, b) return a.raids < b.raids end },
	{ key = "full", title = "On time", width = 80, align = "RIGHT", sort = function(a, b) return a.full < b.full end },
	{ key = "late", title = "Late", width = 70, align = "RIGHT", sort = function(a, b) return a.late < b.late end },
	{ key = "missed", title = "Didn't attend", width = 100, align = "RIGHT", sort = function(a, b) return a.missed < b.missed end },
	{ key = "bench", title = "Bench", width = 70, align = "RIGHT", sort = function(a, b) return a.bench < b.bench end },
	{ key = "pct", title = "Attended", width = 90, align = "RIGHT", sort = pctSort },
}

local STATUS_TONE = { y = "good", t = "text", n = "faint" }
-- Short names in the list; the full ones are in the tooltip and the spreadsheet.
RT.RESULT_SHORT = { full = "On time", late = "Late / part", missed = "Didn't attend", declined = "Can't come" }
local RESULT_TONE = { full = "good", late = "spark", missed = "bad", declined = "faint" }

---------------------------------------------------------------------------
-- Pure helpers (tested)
---------------------------------------------------------------------------
-- Which page tab to show: officer tabs fall back to Raids for everyone else.
function RT.View(officer)
	local v = SK.DB.settings.raidsView
	if RT.OFFICER_VIEWS[v] and not officer then return "upcoming" end
	if v ~= "new" and v ~= "attendance" and v ~= "calendar" then return "upcoming" end
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
function RT.MonthGrid(year, month, board, now, me)
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
	local cells = {}
	for i = 1, 42 do
		local at = time({ year = year, month = month, day = 1 - back + (i - 1), hour = 12 })
		local d = date("*t", at)
		local key = date("%Y-%m-%d", at)
		local raids = {}
		local list = byDay[key] or {}
		table.sort(list, function(a, b) return a.at < b.at end)
		for _, e in ipairs(list) do
			local raid = Board.Raid(e.raid)
			local su = board.signups[e.id] and board.signups[e.id][me or ""]
			raids[#raids + 1] = { id = e.id, at = e.at, text = date("%H:%M", e.at) .. " " .. (raid and (raid.short or raid.name) or e.raid),
				mine = su and su.s or nil, place = Board.PlaceOf(board, e.id, me or "") }
		end
		cells[i] = { at = at, day = d.day, inMonth = d.month == month, today = key == todayKey,
			past = at < todayStart, raids = raids }
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
		local raid = Board.Raid(e.raid)
		local mine = board.signups[e.id] and board.signups[e.id][me or ""]
		rows[#rows + 1] = { id = e.id, at = e.at, when = Board.ShortWhen(e.at, now), raidName = raid and (raid.short or raid.name) or e.raid,
			size = raid and raid.size, counts = Board.Counts(board, e.id), mine = mine and mine.s, ev = e }
	end
	return rows
end

-- "You: Signed up as Healer  ·  You're in" / "You haven't answered yet".
-- place = "i" | "b" | nil (v0.10.0: officers' pick, shown to everyone).
RT.PLACE_TEXT = { i = Theme.Paint("good", "You're in"), b = Theme.Paint("accent", "You're on the bench") }
function RT.MineText(su, place)
	local tail = place and ("  ·  " .. RT.PLACE_TEXT[place]) or ""
	if not su then return Theme.Paint("spark", "You haven't answered yet") .. tail end
	local role = su.r and SK.Data.ROLE_NAMES[su.r]
	return "You: " .. Theme.Paint(STATUS_TONE[su.s], Board.STATUS_NAME[su.s]) .. (role and su.s ~= "n" and (" as " .. role) or "")
		.. (su.b and Theme.Paint("faint", " (added by an officer)") or "") .. tail
end

-- The line at the top of Attendance: what's being recorded, else who
-- recorded the raid picked below (v0.8.1: records come from every officer).
function RT.RecordingText(rec, now, shown)
	if not rec then
		if shown then
			local raid = Board.Raid(shown.raid)
			local by = SK.Identity:Member(shown.by)
			return string.format("%s, %s  ·  recorded by %s  ·  %s", raid and raid.name or "Raid", Board.When(shown.at),
				by and Theme.ClassText(by.name, by.class) or "an officer", Theme.Count(shown.snaps, "check"))
		end
		return "Not recording. It starts by itself when you're in a raid group from 30 minutes before a raid's start."
	end
	local raid = Board.Raid(rec.raid)
	return string.format("%s %s (%s)  ·  %s  ·  %s", Theme.Paint("good", "Recording"), raid and raid.name or "raid",
		Board.ShortWhen(rec.at, now), Theme.Count(rec.snaps, "check"),
		rec.last and ("last " .. Theme.Ago(rec.last, now)) or "first check soon")
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
			(r.duplicateOf and (" " .. C("spark") .. "2x|r") or ""))
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
		local raid = Board.Raid(r.raid)
		fs:SetText((raid and raid.name or r.raid) .. ((Att.current == r) and (" " .. Theme.Paint("good", "•")) or ""))
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
		fs:SetText(Theme.Paint(RESULT_TONE[r.result], RT.RESULT_SHORT[r.result]))
	elseif k == "bench" then
		fs:SetText(r.bench and Theme.Paint("accent", "yes") or Theme.DASH)
	elseif k == "mins" then
		fs:SetText(string.format("%d", math.floor(r.inS / 60 + 0.5)))
	end
end

local function setTotalCell(fs, r, col)
	local k = col.key
	if k == "name" then
		fs:SetText(Theme.ClassText(r.name, r.class))
	elseif k == "pct" then
		fs:SetText(r.pct and (r.pct .. "%") or Theme.DASH)
	else
		fs:SetText(tostring(r[k] or 0))
	end
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
local function label(parent, text)
	local fs = Theme.Text(parent, "label", "dim")
	fs:SetText(text:upper())
	return fs
end

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
	self.options = W.OptionsButton(d, function() return RT:DetailOptions() end, "Copy the line-up, cancel the raid")
	self.options:SetPoint("TOPRIGHT", 0, 0)

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
		if prev then btn:SetPoint("LEFT", prev, "RIGHT", SP.s, 0) else btn:SetPoint("TOPLEFT", 0, -(44 + SP.xs)) end
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
			local mine = RT.selected and board and board.signups[RT.selected] and board.signups[RT.selected][guid or ""]
			if mine then Board:SignUp(RT.selected, mine.s, v) end
			RT:Refresh()
		end,
	})
	self.role:SetPoint("LEFT", prev, "RIGHT", SP.m, 0)
	self.role.tooltip = "Your role for raids (remembered). Until you pick one, it's a guess from your talents."
	self.mine = Theme.Text(d, "body", "text")
	self.mine:SetPoint("TOPLEFT", 0, -(44 + SP.xs + S.control + SP.s))
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
		onClick = function(r, button)
			if Board.OfficerView() and button ~= "RightButton" then return RT:CyclePlace(r) end
			SK.CharacterTab:ShowCharacter(r.guid)
		end,
		onEnter = function(row, r)
			GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
			Theme.TipLine(GameTooltip, Theme.ClassText(r.name, r.class))
			Theme.TipLine(GameTooltip, r.statusName .. (r.place and ("  ·  " .. Board.PLACE_NAME[r.place]) or "") ..
				(r.byOfficer and "  ·  added by an officer" or ""), "dim")
			if Board.OfficerView() then
				Theme.TipLine(GameTooltip, "Click: In, then Bench, then undecided. Right-click: their character.", "accent", true)
			else
				Theme.TipLine(GameTooltip, "Click to open their character", "accent")
			end
			GameTooltip:Show()
		end,
	})
	self.lineup:SetPoint("TOPLEFT", 0, -(44 + SP.xs + S.control + SP.s + 18 + SP.xs + 16 + SP.xs + 32 + SP.s))
	self.lineup:SetPoint("BOTTOMRIGHT")
	self.lineup:SetEmptyText("Nobody has answered yet.")
	self.empty = Theme.Text(d, "body", "dim")
	self.empty:SetPoint("TOPLEFT", 0, -SP.xxs)
	self.empty:SetPoint("RIGHT", 0, 0)
	self.empty:SetJustifyH("LEFT")
	self.empty:SetWordWrap(true)

	-------------------------------------------------------------------------
	-- New raid (officers)
	-------------------------------------------------------------------------
	local nw = CreateFrame("Frame", nil, page)
	nw:SetPoint("TOPLEFT", 0, top)
	nw:SetPoint("BOTTOMRIGHT")
	self.newPage = nw
	s.newRaid = s.newRaid or {}
	local form = s.newRaid
	local y = 0
	local function field(text, menu)
		local l = label(nw, text)
		l:SetPoint("TOPLEFT", 0, -y)
		menu:SetPoint("TOPLEFT", 0, -(y + W.CARD_LABEL_H))
		y = y + W.CARD_LABEL_H + S.control + SP.l
		return menu
	end
	self.raidMenu = field("Raid", W.Menu(nw, {
		width = 240,
		items = function()
			local out = {}
			for _, r in ipairs(SK.Data.ShownAttunements()) do
				out[#out + 1] = { value = r.key, text = string.format("%s (%d)", r.name, r.size or 0) }
			end
			return out
		end,
		get = function() return form.raid or "ony" end,
		set = function(v) form.raid = v end,
	}))
	self.dayMenu = field("Day", W.Menu(nw, {
		width = 240,
		items = function()
			local out, now = {}, Compat.Now()
			for i = 0, Board.DAYS_SHOWN - 1 do
				local at = Board.DayStart(now, i)
				out[#out + 1] = { value = i, text = (i == 0 and "Today, " or i == 1 and "Tomorrow, " or "") .. date("%A %d %B", at) }
			end
			return out
		end,
		get = function() return form.day or 0 end,
		set = function(v) form.day = v end,
	}))
	self.timeMenu = field("Start time (your time)", W.Menu(nw, {
		width = 240,
		items = function()
			local out = {}
			for m = 0, 23 * 60 + 30, 30 do out[#out + 1] = { value = m, text = string.format("%02d:%02d", math.floor(m / 60), m % 60) } end
			return out
		end,
		get = function() return form.minutes or 20 * 60 end,
		set = function(v) form.minutes = v end,
	}))
	self.create = W.Button(nw, "Create raid", nil, S.control, function() RT:CreateRaid() end, "primary")
	self.create:SetPoint("TOPLEFT", 0, -y)
	self.createNote = Theme.Text(nw, "small", "dim")
	self.createNote:SetPoint("TOPLEFT", 0, -(y + S.control + SP.m))
	self.createNote:SetWidth(460)
	self.createNote:SetJustifyH("LEFT")
	self.createNote:SetWordWrap(true)
	self.createNote:SetText("Everyone with Short Royalty sees the raid within a minute (people who are offline " ..
		"get it when they log in) and can sign up from this page. Times show in each player's own time zone. " ..
		"To change a raid, cancel it from its ··· menu and make a new one.")
	self.createResult = Theme.Text(nw, "body", "text")
	self.createResult:SetPoint("TOPLEFT", self.createNote, "BOTTOMLEFT", 0, -SP.m)
	self.createResult:SetWidth(460)
	self.createResult:SetJustifyH("LEFT")

	self:BuildCalendar(page, top)

	-------------------------------------------------------------------------
	-- Attendance (officers)
	-------------------------------------------------------------------------
	local at = CreateFrame("Frame", nil, page)
	at:SetPoint("TOPLEFT", 0, top)
	at:SetPoint("BOTTOMRIGHT")
	self.attPage = at
	self.recording = Theme.Text(at, "small", "dim")
	self.recording:SetPoint("TOPLEFT", 0, -SP.xs)
	self.recording:SetPoint("RIGHT", -120, 0)
	self.recording:SetJustifyH("LEFT")
	self.recording:SetWordWrap(true)
	self.endRaid = W.Button(at, "End raid", nil, S.control, function() Att:Stop(Compat.Now()); RT:Refresh() end)
	self.endRaid:SetPoint("TOPRIGHT", 0, 0)
	self.endRaid.tooltip = "Stop recording now. It also stops by itself 15 minutes after you leave the raid group."
	self.resume = W.Button(at, "Resume", nil, S.control, function()
		if RT.record then Att:Resume(RT.record) end
		RT:Refresh()
	end)
	self.resume:SetPoint("TOPRIGHT", 0, 0)
	self.resume.tooltip = "Start recording this raid again (you're in a raid group in its time)."

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
			Theme.TipDouble(GameTooltip, "In the raid group", math.floor(r.inS / 60 + 0.5) .. " min", "dim", "text")
			Theme.TipDouble(GameTooltip, "Online, not in the group", math.floor(r.bnS / 60 + 0.5) .. " min", "dim", "text")
			Theme.TipLine(GameTooltip, r.benchAuto and "Bench was ticked automatically." or "Bench wasn't ticked automatically.", "faint")
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

function RT:CreateRaid()
	local form = SK.DB.settings.newRaid
	local now = Compat.Now()
	local at = Board.StartAt(Board.DayStart(now, form.day or 0), form.minutes or 20 * 60)
	local e, why = Board:Create(form.raid or "ony", at)
	if e then
		local raid = Board.Raid(e.raid)
		self.createResult:SetText(Theme.Paint("good", "Made: ") .. (raid and raid.name or "") .. ", " .. Board.When(e.at))
		RT.selected = e.id
		SK.DB.settings.raidsView = "upcoming"
	else
		self.createResult:SetText(Theme.Paint("bad", "Not made: " .. tostring(why)))
	end
	RT:Refresh()
end

-- Officers: undecided -> In -> Bench -> undecided.
RT.NEXT_PLACE = { i = "b", b = "-" }
function RT:CyclePlace(r)
	if not RT.selected then return end
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

-- Officers: paste sign-ups from Discord.
function RT:ImportDiscord()
	local id = RT.selected
	if not id then return end
	SK.DebugWindow:AskText("Import sign-ups from Discord",
		"Paste the sign-up list from Discord, then press Import. Names must match characters in the guild.",
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
		items[#items + 1] = { text = "Import sign-ups from Discord", onClick = function() RT:ImportDiscord() end }
		items[#items + 1] = { text = "Cancel this raid", onClick = function()
			local ok, why = Board:Cancel(RT.selected)
			if not ok then SK:Print("Couldn't cancel: %s.", tostring(why)) end
			RT.selected = nil
			RT:Refresh()
		end }
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
	self.events:SetEmptyText(Board.OfficerView() and "No raids yet. Make one under New raid."
		or "No raids yet. Officers and raid leaders make them.")

	local ev = board and RT.selected and board.events[RT.selected]
	local shown = ev ~= nil
	for _, f in ipairs({ self.title, self.sub, self.options, self.role, self.mine, self.counts, self.ready, self.lineup }) do
		f:SetShown(shown)
	end
	for _, b in ipairs(self.signButtons) do b:SetShown(shown) end
	self.empty:SetShown(not shown)
	if not shown then
		self.empty:SetText(#rows == 0 and "When a raid is made it shows here, and you can sign up with one click." or "")
		return
	end
	local raid = Board.Raid(ev.raid)
	local creator = SK.Identity:Member(ev.by)
	self.title:SetText(string.format("%s (%d)", raid and raid.name or ev.raid, raid and raid.size or 0))
	self.sub:SetText(Board.When(ev.at) .. (creator and ("  ·  made by " .. Theme.ClassText(creator.name, creator.class)) or ""))
	local mine = board.signups[ev.id] and board.signups[ev.id][me or ""]
	for _, b in ipairs(self.signButtons) do
		b.active = mine ~= nil and mine.s == b.status
		b:Paint("rest")
	end
	self.role:Refresh()
	self.mine:SetText(RT.MineText(mine, Board.PlaceOf(board, ev.id, me or "")))
	local rows2, sum = Board.LineUp(board, ev, RT.Ctx())
	self.counts:SetText(Board.CountsText(sum) .. "  ·  " .. sum.maybe .. " tentative  ·  " .. sum.out .. " can't come")
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
	self.endRaid:SetShown(Att.current ~= nil)
	local store = Att:Store() or {}
	local list = Att.Sorted(store)
	if not RT.record or not store[RT.record] then RT.record = Att.current and Att.current.id or (list[1] and list[1].id) end
	local rec = RT.record and store[RT.record]
	self.recording:SetText(RT.RecordingText(Att.current, now, mode == "raids" and rec or nil))
	local canResume = Att.current == nil and rec ~= nil and rec.ended ~= nil and Compat.InRaidGroup()
		and now <= rec.at + Att.LONGEST
	self.resume:SetShown(canResume and mode == "raids")
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
		self.people:SetItems(rec and Att.Rows(rec) or {})
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
	self.newPage:SetShown(view == "new")
	self.attPage:SetShown(view == "attendance")
	self.calPage:SetShown(view == "calendar")
	local now = Compat.Now()
	if view == "upcoming" then
		self:RefreshUpcoming(Board:Get(), now, Compat.PlayerGUID())
	elseif view == "calendar" then
		self:RefreshCalendar(now)
	elseif view == "new" then
		self.raidMenu:Refresh(); self.dayMenu:Refresh(); self.timeMenu:Refresh()
	else
		self:RefreshAttendance(now)
	end
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
	self.calHint = Theme.Text(cal, "small", "dim")
	self.calHint:SetPoint("RIGHT", self.calToday, "LEFT", -SP.m, 0)
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
		-- Officers: clicking an empty future day starts a New raid on it.
		c:SetScript("OnClick", function(selfC) RT:CalendarDay(selfC.cell) end)
		self.calCells[i] = c
	end
end

function RT:MoveMonth(delta)
	local now = Compat.Now()
	local cur = RT.calMonth or { year = tonumber(date("%Y", now)), month = tonumber(date("%m", now)) }
	local y, m = RT.ShiftMonth(cur.year, cur.month, delta)
	RT.calMonth = { year = y, month = m }
	RT:Refresh()
end

-- Officers: a day from today up to New raid's last day opens New raid on it.
function RT:CalendarDay(cell)
	if not cell or not Board.OfficerView() then return end
	local now = Compat.Now()
	local offset = math.floor((Board.DayStart(cell.at, 0) - Board.DayStart(now, 0)) / 86400 + 0.5)
	if offset < 0 or offset >= Board.DAYS_SHOWN then return end
	SK.DB.settings.newRaid = SK.DB.settings.newRaid or {}
	SK.DB.settings.newRaid.day = offset
	SK.DB.settings.raidsView = "new"
	RT:Refresh()
end

function RT:RefreshCalendar(now)
	local cur = RT.calMonth or { year = tonumber(date("%Y", now)), month = tonumber(date("%m", now)) }
	local grid = RT.MonthGrid(cur.year, cur.month, Board:Get() or Board.New(), now, Compat.PlayerGUID())
	self.calTitle:SetText(grid.title)
	self.calHint:SetText(Board.OfficerView() and "Click a day to make a raid on it" or "Click a raid to sign up")
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
		c.dayText:SetText(tostring(cell.day))
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

SK.MainFrame:AddTab("raids", "Raids", RT, { group = "guild", icon = Theme.TEX.raids })
