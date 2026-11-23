-- Raid roster planner (v0.13.0, from the officers' feedback): the static
-- raid roster as one table, one row per player. Who can fill which role as a
-- main or a backup (officer-set, Core/OfficerDir.lua), how their levelling,
-- gear and attunement are going (from the addon's profiles), and officers'
-- notes. Officers only; members never see it.
--
-- Everything here is pure.
--   Build(ctx)         -> rows, one per player (alts folded into their main)
--   View(rows, opts)   -> items for the table: rows, and for a role its group
--                         headers (mains, backups, unsorted whose spec fits)
--   Counts(rows)       -> chip counts; Summary(rows) -> the "All" line
--   AwayDays / AwayText: who's away in the next three months (v0.16.4), in words
local _, SK = ...

local RP = SK:NewModule("RosterPlan")

RP.MAX_LEVEL = 60          -- Forever's level cap
RP.CLOSE_LEVEL = 55        -- "close": 55 to 59
RP.STALE = 7 * 86400       -- data older than this needs a look
RP.ROLE_KEYS = { T = "TANK", H = "HEALER", D = "DPS" }
RP.ROLE_TITLE = { T = "Tanks", H = "Healers", D = "DPS" }
RP.STATUS_NAME = { r = "Raider", b = "Backup", s = "Social" }
-- v0.14.0: the second tier reads "Off" (officers, 21 Nov); stored as "b".
RP.TIER_NAME = { m = "Main", b = "Off" }
-- Short talent tree names for the Spec column (the full name is in the tooltip).
RP.SHORT_SPEC = {
	Protection = "Prot", Restoration = "Resto", Discipline = "Disc", Retribution = "Ret", Enhancement = "Enh",
	Elemental = "Ele", ["Beast Mastery"] = "BM", Marksmanship = "MM", Survival = "Surv", Affliction = "Affli",
	Demonology = "Demo", Destruction = "Destro", Assassination = "Assa", Subtlety = "Sub", ["Feral Combat"] = "Feral",
	Balance = "Balance",
}

---------------------------------------------------------------------------
-- Away days (officer-set, and the player's own from Raids → Calendar)
---------------------------------------------------------------------------
-- days looked at from today (v0.16.4: was 28; the GM wants every date
-- people marked, "regardless if there is a raid on that date or not")
RP.AWAY_AHEAD = 90
local WEEKDAY = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }

local function dayAt(now, i)
	local t = date("*t", now)
	return time({ year = t.year, month = t.month, day = t.day + i, hour = 12 })
end

-- The away days from today: { { key, at, officer = bool, self = bool } }.
function RP.AwayDays(officerDays, selfAway, now, ahead)
	local out = {}
	for i = 0, (ahead or RP.AWAY_AHEAD) - 1 do
		local at = dayAt(now, i)
		local key = date("%Y-%m-%d", at)
		local off = officerDays and officerDays[key] == true
		local own = selfAway ~= nil and SK.Absences ~= nil and SK.Absences.IsAway(selfAway, at)
		if off or own then out[#out + 1] = { key = key, at = at, officer = off, self = own } end
	end
	return out
end

local function dayText(at) return tostring(tonumber(date("%d", at))) end

-- Back-to-back away days as ranges: { { first, last, officer, self } }
-- (officer/self: any day in it set by an officer / by the player). Days
-- covered by a weekly "Away every" (older versions) are left to that. Pure.
function RP.AwayRuns(days, selfAway)
	local weekly = {}
	for _, w in ipairs(selfAway and selfAway.w or {}) do weekly[w] = true end
	local runs, run = {}, nil
	for _, d in ipairs(days) do
		local wd = SK.Absences and SK.Absences.Weekday(d.at)
		if d.officer or not weekly[wd or 0] then
			if run and d.at - run.last < 1.5 * 86400 then run.last = d.at
			else
				run = { first = d.at, last = d.at }
				runs[#runs + 1] = run
			end
			run.officer = run.officer or d.officer or nil
			run.self = run.self or d.self or nil
		end
	end
	return runs
end

-- "9-15 Dec", "30 Nov-2 Dec", "9 Dec". Pure.
function RP.RunText(r)
	local m1, m2 = date("%b", r.first), date("%b", r.last)
	if r.first == r.last then return dayText(r.first) .. " " .. m1 end
	if m1 == m2 then return dayText(r.first) .. "-" .. dayText(r.last) .. " " .. m2 end
	return dayText(r.first) .. " " .. m1 .. "-" .. dayText(r.last) .. " " .. m2
end

-- "9-15 Dec", "9 Dec, 20 Dec", "Every Tue", "Every Tue, 9-15 Dec" ... or nil. Pure.
function RP.AwayText(days, selfAway)
	local weekly, parts = {}, {}
	for _, w in ipairs(selfAway and selfAway.w or {}) do weekly[w] = true end
	local every = {}
	for i = 1, 7 do if weekly[i] then every[#every + 1] = WEEKDAY[i] end end
	if #every > 0 then parts[#parts + 1] = "Every " .. table.concat(every, ", ") end
	local runs = RP.AwayRuns(days, selfAway)
	for i, r in ipairs(runs) do
		if i > 2 then
			parts[#parts + 1] = "+" .. (#runs - 2)
			break
		end
		parts[#parts + 1] = RP.RunText(r)
	end
	if #parts == 0 then return nil end
	return table.concat(parts, ", ")
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function onyRaid()
	for _, a in ipairs(SK.Data.ShownAttunements()) do
		if a.key == "ony" then return a end
	end
end

-- ctx = { guild, dir, now, me, isOwn(guid), signups = { [guid] = "y" | "t" | "n" },
--         raidDays = { ["2026-12-09"] = true } days with a raid on the board }
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
	local alts, chars = {}, {}
	for guid, main in pairs(mainOf) do
		alts[main] = alts[main] or {}
		table.insert(alts[main], live[guid].name or "?")
		chars[main] = chars[main] or { main }
		table.insert(chars[main], guid)
	end
	local weekEnd = dayAt(now, 7)
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
			local tiers = OD.TiersOf(dir, guid)
			local selfAway = SK.Absences and SK.Absences.Of(guild, guid) or nil
			local awayDays = RP.AwayDays(OD.AwayOf(dir, guid), selfAway, now)
			local clash, soon = false, false
			for _, d in ipairs(awayDays) do
				if ctx.raidDays and ctx.raidDays[d.key] then clash = true end
				if d.at < weekEnd then soon = true end
			end
			local notes = OD.NotesOf(dir, guid, ctx.me)
			local r = {
				guid = guid, name = m.name or (p and p.name) or "?", class = m.class or (p and p.class),
				level = level, rank = m.rank or "", online = m.online and true or false,
				hasData = p ~= nil, spec = spec, ilvl = ilvl, att = att, ench = ench, age = age,
				guess = p and SK.Data.GuessRole(m.class or p.class, p.talents) or nil,
				status = OD.StatusOf(dir, guid), tiers = tiers,
				awayDays = awayDays, selfAway = selfAway, awayText = RP.AwayText(awayDays, selfAway), awayClash = clash, awayNow = soon,
				notes = notes, note = notes[1] and notes[1].text or nil,
				alts = alts[guid] or {}, chars = chars[guid] or { guid }, signed = ctx.signups and ctx.signups[guid] or nil,
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
	local s = { people = #rows, at60 = 0, close = 0, attuned = 0, ench = 0, noAddon = 0 }
	for _, r in ipairs(rows) do
		if r.level >= RP.MAX_LEVEL then s.at60 = s.at60 + 1 elseif r.close then s.close = s.close + 1 end
		if r.att == "yes" then s.attuned = s.attuned + 1 end
		if (r.ench or 0) > 0 then s.ench = s.ench + 1 end
		if not r.hasData then s.noAddon = s.noAddon + 1 end
	end
	return s
end

function RP.SummaryText(s)
	local parts = {
		s.people .. (s.people == 1 and " player" or " players"),
		s.at60 .. " at 60",
		s.close .. " at 55-59",
		s.attuned .. " attuned to Onyxia",
		s.ench .. " missing enchants",
	}
	if s.noAddon > 0 then parts[#parts + 1] = s.noAddon .. " without the addon" end
	return table.concat(parts, "  ·  ")
end

local function groupLine(title, list)
	local at60, attuned, away = 0, 0, {}
	for _, r in ipairs(list) do
		if r.level >= RP.MAX_LEVEL then at60 = at60 + 1 end
		if r.att == "yes" then attuned = attuned + 1 end
		if r.awayNow then away[#away + 1] = r.name end
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
		awayText = ("Away this week: " .. table.concat(away, ", ", 1, math.min(#away, 3))
			.. (#away > 3 and " +" .. (#away - 3) or "")):upper()
	end
	return text, awayText
end

local function match(r, opts)
	if opts.status and r.status ~= opts.status then return false end
	if opts.needs and not r.needsLook then return false end
	if opts.search and opts.search ~= "" and not r.hay:find(opts.search:lower(), 1, true) then return false end
	return true
end

-- opts = { role = "A" | "T" | "H" | "D" | "N", status = nil | "r" | "b" | "s",
--          needs = bool, search = text }
-- Items get g (group) for sorting; group headers are { section = true, g,
-- text, away = "AWAY THIS WEEK: NAME" or nil }.
function RP.View(rows, opts)
	opts = opts or {}
	local items = {}
	local role = opts.role or "A"
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
	local t1, a1 = groupLine("Main", mains)
	local t2, a2 = groupLine("Off", backs)
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

-- Default order: Raiders, Backups, Social, then not set; then by name.
local STATUS_ORDER = { r = 1, b = 2, s = 3 }
function RP.DefaultOrder(a, b)
	local sa, sb = STATUS_ORDER[a.status or ""] or 4, STATUS_ORDER[b.status or ""] or 4
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
