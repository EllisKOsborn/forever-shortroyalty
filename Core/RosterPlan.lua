-- Raid roster planner (v0.13.0, from the officers' feedback): the static
-- raid roster as one table, one row per player. Who can fill which role as a
-- main or a backup (officer-set, Core/OfficerDir.lua), how their levelling,
-- gear and attunement are going (from the addon's profiles), and officers'
-- notes. Officers only; members never see it.
--
-- Everything here is pure apart from Record (the local progress history).
--   Build(ctx)         -> rows, one per player (alts folded into their main)
--   View(rows, opts)   -> items for the table: rows, and for a role its group
--                         headers (mains, backups, unsorted whose spec fits)
--   Counts(rows)       -> chip counts; Summary(rows) -> the "All" line
--   Week / WeekStart / PlanWeek / WeekLabel: reset weeks from 9 Dec 2026
--   Record / Gain      -> each officer's own daily level / item level history
local _, SK = ...

local RP = SK:NewModule("RosterPlan")

RP.MAX_LEVEL = 60          -- Forever's level cap
RP.CLOSE_LEVEL = 55        -- "close": 55 to 59
RP.STALE = 7 * 86400       -- data older than this needs a look
RP.RESET0 = 1796774400     -- Wed 9 Dec 2026 00:00 UTC: raids open, week 1
RP.WEEK = 7 * 86400
RP.HISTORY_DAYS = 35
RP.GAIN_DAYS = 7
RP.ROLE_KEYS = { T = "TANK", H = "HEALER", D = "DPS" }
RP.ROLE_TITLE = { T = "Tanks", H = "Healers", D = "DPS" }
RP.STATUS_NAME = { r = "Raider", b = "Backup" }
RP.TIER_NAME = { m = "Main", b = "Backup" }
-- Short talent tree names for the Spec column (the full name is in the tooltip).
RP.SHORT_SPEC = {
	Protection = "Prot", Restoration = "Resto", Discipline = "Disc", Retribution = "Ret", Enhancement = "Enh",
	Elemental = "Ele", ["Beast Mastery"] = "BM", Marksmanship = "MM", Survival = "Surv", Affliction = "Affli",
	Demonology = "Demo", Destruction = "Destro", Assassination = "Assa", Subtlety = "Sub", ["Feral Combat"] = "Feral",
	Balance = "Balance",
}

---------------------------------------------------------------------------
-- Reset weeks
---------------------------------------------------------------------------
function RP.Week(t) return math.floor((t - RP.RESET0) / RP.WEEK) + 1 end
function RP.WeekStart(n) return RP.RESET0 + (n - 1) * RP.WEEK end
-- The week planned for: this week, or week 1 before raids open.
function RP.PlanWeek(now) return math.max(1, RP.Week(now)) end
function RP.WeekLabel(n, short)
	local t = RP.WeekStart(n)
	local day = tonumber(date("!%d", t)) or 0
	return (short and "" or "Week ") .. n .. " (" .. day .. date("! %b", t) .. ")"
end
-- Availability for the weeks offered: { { n, officer = bool, self = days } }.
-- officer = an officer marked the whole week away; self = how many days of
-- that week the player marked away themselves (Raids → Calendar). Pure.
function RP.Weeks(officerAway, selfAway, weeks)
	local out = {}
	for _, n in ipairs(weeks) do
		local days, start = 0, RP.WeekStart(n)
		if selfAway and SK.Absences then
			for d = 0, 6 do
				if SK.Absences.IsAway(selfAway, start + d * 86400 + 43200) then days = days + 1 end
			end
		end
		out[#out + 1] = { n = n, officer = officerAway[n] == true, self = days }
	end
	return out
end

-- The weeks offered for "away": the plan week and the next three.
function RP.WeeksOffered(now)
	local first, out = RP.PlanWeek(now), {}
	for i = 0, 3 do out[#out + 1] = first + i end
	return out
end

---------------------------------------------------------------------------
-- Progress history (local to each officer's game, never sent)
---------------------------------------------------------------------------
-- store[guid] = { { d = day, l = level, i = item level }, ... } oldest first.
function RP.Record(store, rows, now)
	local day = math.floor(now / 86400)
	for _, r in ipairs(rows) do
		if r.level and r.level > 0 then
			local h = store[r.guid] or {}
			store[r.guid] = h
			local last = h[#h]
			if last and last.d == day then
				last.l, last.i = r.level, r.ilvl or last.i
			else
				h[#h + 1] = { d = day, l = r.level, i = r.ilvl }
			end
			while #h > 0 and h[1].d < day - RP.HISTORY_DAYS do table.remove(h, 1) end
		end
	end
end

-- How much `field` ("l" or "i") rose over the last GAIN_DAYS days (nil when
-- unknown or not up). The baseline is the newest entry at least GAIN_DAYS
-- old, else the oldest entry from before today.
function RP.Gain(h, now, field, current)
	if not h or not current then return nil end
	local today = math.floor(now / 86400)
	local base
	for _, e in ipairs(h) do
		if e.d <= today - RP.GAIN_DAYS then base = e elseif not base and e.d < today then base = e end
	end
	if not base or not base[field] then return nil end
	local g = current - base[field]
	if g <= 0 then return nil end
	if field == "i" then g = math.floor(g * 10 + 0.5) / 10 end
	return g
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function onyRaid()
	for _, a in ipairs(SK.Data.ShownAttunements()) do
		if a.key == "ony" then return a end
	end
end

-- ctx = { guild, dir, now, me, progress, isOwn(guid), signups = { [guid] = "y" | "t" | "n" } }
function RP.Build(ctx)
	local guild, dir, now = ctx.guild, ctx.dir or {}, ctx.now
	local rows = {}
	if not guild then return rows end
	local OD = SK.OfficerDir
	local raid = ctx.raid or onyRaid()
	local live = {}
	for guid, m in pairs(guild.members) do
		if not m.leftAt then live[guid] = m end
	end
	local profiles = {}
	for guid, p in pairs(guild.profiles or {}) do
		if live[guid] then profiles[guid] = p end
	end
	local groupOf = SK.Alts.Groups(profiles, function(g) return profiles[g] ~= nil end)
	local mainOf = {}
	for guid in pairs(live) do
		local main = OD.AltOf(dir, guid)
		if main and not live[main] then main = nil end
		if not main then
			local g = groupOf[guid]
			if g and #g.members > 1 and g.main ~= guid and live[g.main] then main = g.main end
		end
		if main and main ~= guid then mainOf[guid] = main end
	end
	local alts = {}
	for guid, main in pairs(mainOf) do
		alts[main] = alts[main] or {}
		table.insert(alts[main], live[guid].name or "?")
	end
	local week = RP.PlanWeek(now)
	local offered = RP.WeeksOffered(now)
	for guid, m in pairs(live) do
		local altRank = SK.Identity.IsAltRank and SK.Identity.IsAltRank(m)
		if not mainOf[guid] and not altRank then
			local p = ctx.profile and ctx.profile(guid) or profiles[guid]
			local hidden = p and p.hidden and p.hidden.gear
			local spec, att, ench, ilvl
			if p and not hidden then
				local _, tree = SK.Talents.Summary(p.talents)
				spec = tree and (RP.SHORT_SPEC[tree] or tree) or nil
				ilvl = type(p.ilvl) == "number" and p.ilvl or nil
				ench = #SK.Data.Enchants.Missing(p.gear, p.class, p.level)
			end
			att = p and SK.Attunements.StateOf(p, raid) or nil
			local level = (p and p.level) or m.level or 0
			local own = ctx.isOwn and ctx.isOwn(guid)
			local age = p and (own and 0 or (type(p.updated) == "number" and math.max(0, now - p.updated) or nil)) or nil
			local hist = ctx.progress and ctx.progress[guid]
			local tiers = OD.TiersOf(dir, guid)
			local away = OD.AwayOf(dir, guid)
			local notes = OD.NotesOf(dir, guid, ctx.me)
			local r = {
				guid = guid, name = m.name or (p and p.name) or "?", class = m.class or (p and p.class),
				level = level, rank = m.rank or "", online = m.online and true or false,
				hasData = p ~= nil, spec = spec, ilvl = ilvl, att = att, ench = ench, age = age,
				guess = p and SK.Data.GuessRole(m.class or p.class, p.talents) or nil,
				status = OD.StatusOf(dir, guid), tiers = tiers, away = away, awayNow = away[week] or false,
				weeks = RP.Weeks(away, SK.Absences and SK.Absences.Of(guild, guid), offered),
				notes = notes, note = notes[1] and notes[1].text or nil,
				levelGain = RP.Gain(hist, now, "l", level), ilvlGain = RP.Gain(hist, now, "i", ilvl),
				alts = alts[guid] or {}, signed = ctx.signups and ctx.signups[guid] or nil,
			}
			table.sort(r.alts)
			r.ready = level >= RP.MAX_LEVEL and att == "yes"
			r.close = level >= RP.CLOSE_LEVEL and level < RP.MAX_LEVEL
			r.sorted = r.status ~= nil or next(tiers) ~= nil
			r.needsLook = not r.hasData or level < RP.MAX_LEVEL or att ~= "yes" or (ench or 0) > 0
				or (age ~= nil and age > RP.STALE)
			local hay = { r.name, r.spec or "", r.rank }
			for _, n in ipairs(notes) do hay[#hay + 1] = n.text end
			for _, a in ipairs(r.alts) do hay[#hay + 1] = a end
			r.hay = table.concat(hay, " "):lower()
			rows[#rows + 1] = r
		end
	end
	table.sort(rows, function(a, b) return a.name:lower() < b.name:lower() end)
	return rows
end

---------------------------------------------------------------------------
-- Counts, summary and the table's items
---------------------------------------------------------------------------
-- { all = n, notSorted = n, T = { m = n, b = n }, H = …, D = … }
function RP.Counts(rows)
	local c = { all = #rows, notSorted = 0, T = { m = 0, b = 0 }, H = { m = 0, b = 0 }, D = { m = 0, b = 0 } }
	for _, r in ipairs(rows) do
		if not r.sorted then c.notSorted = c.notSorted + 1 end
		for k, role in pairs(RP.ROLE_KEYS) do
			local t = r.tiers[role]
			if t then c[k][t] = c[k][t] + 1 end
		end
	end
	return c
end

function RP.Summary(rows)
	local s = { people = #rows, at60 = 0, close = 0, attuned = 0, ench = 0, noAddon = 0, gained = 0 }
	for _, r in ipairs(rows) do
		if r.level >= RP.MAX_LEVEL then s.at60 = s.at60 + 1 elseif r.close then s.close = s.close + 1 end
		if r.att == "yes" then s.attuned = s.attuned + 1 end
		if (r.ench or 0) > 0 then s.ench = s.ench + 1 end
		if not r.hasData then s.noAddon = s.noAddon + 1 end
		if r.level >= RP.MAX_LEVEL and r.levelGain then s.gained = s.gained + 1 end
	end
	return s
end

function RP.SummaryText(s)
	local parts = {
		s.people .. (s.people == 1 and " player" or " players"),
		s.at60 .. " at 60" .. (s.gained > 0 and (" (" .. s.gained .. " this week)") or ""),
		s.close .. " at 55-59",
		s.attuned .. " attuned to Onyxia",
		s.ench .. " missing enchants",
	}
	if s.noAddon > 0 then parts[#parts + 1] = s.noAddon .. " without the addon" end
	return table.concat(parts, "  ·  ")
end

local function groupLine(title, list, week)
	local at60, attuned, away = 0, 0, {}
	for _, r in ipairs(list) do
		if r.level >= RP.MAX_LEVEL then at60 = at60 + 1 end
		if r.att == "yes" then attuned = attuned + 1 end
		if r.away[week] then away[#away + 1] = r.name end
	end
	local n = #list
	local parts = { title .. " " .. n }
	if n > 0 then
		parts[#parts + 1] = (at60 == n and "all" or tostring(at60)) .. " at 60"
		parts[#parts + 1] = (attuned == n and "all" or tostring(attuned)) .. " attuned"
	end
	local text = table.concat(parts, "  ·  "):upper()
	local awayText
	if #away > 0 then
		awayText = (table.concat(away, ", ", 1, math.min(#away, 3)) .. (#away > 3 and " +" .. (#away - 3) or "")
			.. " away week " .. week):upper()
	end
	return text, awayText
end

local function match(r, opts)
	if opts.status and r.status ~= opts.status then return false end
	if opts.needs and not r.needsLook then return false end
	if opts.search and opts.search ~= "" and not r.hay:find(opts.search:lower(), 1, true) then return false end
	return true
end

-- opts = { role = "A" | "T" | "H" | "D" | "N", status = nil | "r" | "b",
--          needs = bool, search = text, week = n }
-- Items get g (group) for sorting; group headers are { section = true, g,
-- text, away = "NAME AWAY WEEK 1" or nil }.
function RP.View(rows, opts)
	opts = opts or {}
	local items = {}
	local role = opts.role or "A"
	local week = opts.week or 1
	if role == "A" or role == "N" then
		for _, r in ipairs(rows) do
			if (role == "A" or not r.sorted) and match(r, opts) then r.g = 1; items[#items + 1] = r end
		end
		return items
	end
	local key = RP.ROLE_KEYS[role]
	local mains, backs, fits = {}, {}, {}
	for _, r in ipairs(rows) do
		if match(r, opts) then
			local t = r.tiers[key]
			if t == "m" then mains[#mains + 1] = r
			elseif t == "b" then backs[#backs + 1] = r
			elseif not r.sorted and r.guess == key then fits[#fits + 1] = r end
		end
	end
	local function add(g, text, list, always, away)
		if #list == 0 and not always then return end
		items[#items + 1] = { section = true, g = g, text = text, away = away }
		for _, r in ipairs(list) do r.g = g; items[#items + 1] = r end
	end
	local t1, a1 = groupLine("Main", mains, week)
	local t2, a2 = groupLine("Backup", backs, week)
	add(1, t1, mains, true, a1)
	add(2, t2, backs, true, a2)
	add(3, "NOT SORTED YET, SPEC FITS", fits, false)
	return items
end

-- Order inside the table: group, its header first, then `cmp`. desc = the
-- List's descending flag (it calls the comparator with its arguments swapped).
function RP.GroupSort(cmp, isDesc)
	return function(x, y)
		local desc = isDesc and isDesc() or false
		if x.g ~= y.g then
			if desc then return (x.g or 0) > (y.g or 0) end
			return (x.g or 0) < (y.g or 0)
		end
		if (x.section or false) ~= (y.section or false) then
			if desc then return y.section == true end
			return x.section == true
		end
		if x.section then return false end
		return cmp(x, y)
	end
end

-- Default order: Raiders, then Backups, then not set; then by name.
local STATUS_ORDER = { r = 1, b = 2 }
function RP.DefaultOrder(a, b)
	local sa, sb = STATUS_ORDER[a.status or ""] or 3, STATUS_ORDER[b.status or ""] or 3
	if sa ~= sb then return sa < sb end
	return a.name:lower() < b.name:lower()
end

-- "now", "5h", "3d", or "no addon".
function RP.AgeText(age)
	if not age then return "no addon" end
	if age < 3600 then return "now" end
	if age < 86400 then return math.floor(age / 3600) .. "h" end
	return math.floor(age / 86400) .. "d"
end
