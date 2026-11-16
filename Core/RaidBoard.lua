-- Raid board (v0.8.0): guild raids made in the addon by officers and raid
-- leaders, and everyone's sign-ups. Blizzard's calendar isn't used (owner,
-- 15 Nov: it "interacted weirdly with the in-game calendar" and making
-- raids there made the addon feel unnecessary).
--
-- Stored per guild in guild.raidBoard = { events = { [id] = event },
-- signups = { [id] = { [guid] = signup } } } and shared over the addon
-- channel by Sync/RaidSync.lua.
--
--   event  = { id = by .. ":" .. c, by = creator GUID, c = created (time),
--              raid = key in Data/Attunements, at = start (server time),
--              u = last change, x = true when cancelled, eb = who changed it }
--   signup = { s = "y" (signed up) | "t" (tentative) | "n" (can't come),
--              r = "TANK" | "HEALER" | "DPS" | nil, u = last change }
--
-- Every receiver checks, against its own copy of the guild roster, that an
-- event's creator (and whoever changed it) is in an officer or raid leader
-- rank, so a message can't make someone else an officer.
--
-- Pure parts (tested): IsLeadRank, ValidEvent, ValidSignup, MergeEvent,
-- MergeSignup, Prune, Upcoming, Digest, LineUp, CountsText, Readiness, Text.
local _, SK = ...

local Board = SK:NewModule("RaidBoard")
local Compat = SK.Compat

Board.MAX_EVENTS = 30           -- raids kept (upcoming and recent)
Board.MAX_SIGNUPS = 100         -- sign-ups per raid
Board.MAX_FUTURE = 300          -- a change dated more than 5 minutes ahead is refused
Board.AHEAD = 60 * 86400        -- a raid can start at most 60 days ahead
Board.KEEP_AFTER = 7 * 86400    -- raids are deleted this long after they started
Board.LISTED_AFTER = 6 * 3600   -- still listed under Upcoming this long after the start
Board.DAYS_SHOWN = 14           -- days offered by New raid

Board.STATUS_NAME = { y = "Signed up", t = "Tentative", n = "Can't come" }
Board.STATUS_GROUP = { y = "coming", t = "maybe", n = "out" }
local GROUP_ORDER = { coming = 1, maybe = 2, out = 3 }
local ROLE_ORDER = { TANK = 1, HEALER = 2, DPS = 3 }

---------------------------------------------------------------------------
-- Who may make raids
---------------------------------------------------------------------------
-- Officer and Raid Leader ranks (owner, 15 Nov), and the Guild Master.
-- Matched on the rank's name like the Alt rank (Identity.IsAltRank): any
-- rank whose name has the word "officer" or "raid leader" ("Raid Leader",
-- "Officers", "Officer Alt", "RaidLeader", "Raid Lead"). Ranks come from
-- Blizzard's roster, so every player's game agrees.
function Board.IsLeadRank(m)
	if type(m) ~= "table" or m.leftAt then return false end
	if m.rankIndex == 0 then return true end -- the Guild Master
	if type(m.rank) ~= "string" then return false end
	local words = " " .. (m.rank:lower():gsub("[%p%c]", " "):gsub("%s+", " ")) .. " "
	return words:find(" officers? ") ~= nil or words:find(" raid ?leaders? ") ~= nil
		or words:find(" raid ?leads? ") ~= nil
end

-- The addon's creator (owner, 16 Nov: "Just give me access to all these
-- things. I'm the addon creator and they're fine with it."): their main
-- character counts as an officer for raids, attendance and Reserve+, while
-- they're in the guild. It's in the code, so every player's game agrees.
-- The same GUID the owner-only Profit view used (v0.4.7).
Board.CREATORS = { ["Player-6937-001743F0"] = true }

function Board.CanLead(guid, guild)
	guild = guild or SK.DBM:Guild()
	if guild == nil or type(guid) ~= "string" then return false end
	local m = guild.members[guid]
	if Board.CREATORS[guid] and m and not m.leftAt then return true end
	return Board.IsLeadRank(m)
end

-- The raids shown (first wave: Barrow Deeps, Hyjal Summit, Onyxia's Lair).
function Board.Raid(key)
	for _, r in ipairs(SK.Data.ShownAttunements()) do
		if r.key == key then return r end
	end
end

---------------------------------------------------------------------------
-- Checks for anything received (untrusted)
---------------------------------------------------------------------------
local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
local function str(v, max) return type(v) == "string" and #v > 0 and #v <= max end

function Board.ValidEvent(e, now)
	if type(e) ~= "table" then return false, "not a table" end
	if not str(e.by, 64) or not finite(e.c) or e.id ~= e.by .. ":" .. string.format("%d", e.c) then
		return false, "bad id"
	end
	if not Board.Raid(e.raid) then return false, "unknown raid" end
	if not finite(e.at) or not finite(e.u) then return false, "bad time" end
	if e.u > now + Board.MAX_FUTURE then return false, "from the future" end
	if e.at > now + Board.AHEAD or e.at < now - Board.KEEP_AFTER - 86400 then return false, "too far away" end
	if e.x ~= nil and e.x ~= true then return false, "bad cancel" end
	if e.eb ~= nil and not str(e.eb, 64) then return false, "bad editor" end
	return true
end

function Board.ValidSignup(s, now)
	if type(s) ~= "table" then return false, "not a table" end
	if not str(s.e, 80) or not str(s.g, 64) then return false, "bad id" end
	if not Board.STATUS_NAME[s.s] then return false, "bad status" end
	if s.r ~= nil and not ROLE_ORDER[s.r] then return false, "bad role" end
	if not finite(s.u) or s.u > now + Board.MAX_FUTURE then return false, "bad time" end
	return true
end

---------------------------------------------------------------------------
-- Merging (pure: board, item, now, roster checks)
---------------------------------------------------------------------------
function Board.New() return { events = {}, signups = {} } end

-- isLead(guid) -> bool. Returns accepted, reason.
function Board.MergeEvent(board, e, now, isLead)
	local ok, why = Board.ValidEvent(e, now)
	if not ok then return false, why end
	if not isLead(e.by) or (e.eb and not isLead(e.eb)) then return false, "not an officer or raid leader" end
	local have = board.events[e.id]
	if have and have.u >= e.u then return false, "not newer" end
	if not have and SK.Count(board.events) >= Board.MAX_EVENTS then return false, "too many raids" end
	board.events[e.id] = { id = e.id, by = e.by, c = e.c, raid = e.raid, at = e.at, u = e.u, x = e.x, eb = e.eb }
	return true
end

-- isMember(guid) -> bool. A sign-up needs its raid.
function Board.MergeSignup(board, s, now, isMember)
	local ok, why = Board.ValidSignup(s, now)
	if not ok then return false, why end
	if not isMember(s.g) then return false, "not a member" end
	if not board.events[s.e] then return false, "unknown raid" end
	local list = board.signups[s.e]
	if not list then
		list = {}
		board.signups[s.e] = list
	end
	local have = list[s.g]
	if have and have.u >= s.u then return false, "not newer" end
	if not have and SK.Count(list) >= Board.MAX_SIGNUPS then return false, "raid full of sign-ups" end
	list[s.g] = { s = s.s, r = s.r, u = s.u }
	return true
end

-- Delete raids that started more than KEEP_AFTER ago (attendance records
-- are kept separately) and sign-ups without a raid. Returns how many.
function Board.Prune(board, now)
	local n = 0
	for id, e in pairs(board.events) do
		if e.at < now - Board.KEEP_AFTER then
			board.events[id], board.signups[id] = nil, nil
			n = n + 1
		end
	end
	for id in pairs(board.signups) do
		if not board.events[id] then board.signups[id] = nil end
	end
	return n
end

-- Raids still to come (or started less than LISTED_AFTER ago), soonest
-- first. Cancelled raids are left out.
function Board.Upcoming(board, now)
	local out = {}
	for _, e in pairs(board and board.events or {}) do
		if not e.x and e.at >= now - Board.LISTED_AFTER then out[#out + 1] = e end
	end
	table.sort(out, function(a, b)
		if a.at ~= b.at then return a.at < b.at end
		return a.id < b.id
	end)
	return out
end

-- Counts of one raid's sign-ups: { y, t, n }.
function Board.Counts(board, id)
	local c = { y = 0, t = 0, n = 0 }
	for _, s in pairs(board.signups[id] or {}) do c[s.s] = c[s.s] + 1 end
	return c
end

-- A short fingerprint of each raid and its sign-ups, so two players can
-- see which raids they disagree about without sending them. Pure.
local function hash(text)
	local h = 5381
	for i = 1, #text do h = (h * 33 + text:byte(i)) % 4294967296 end
	return string.format("%08x", h)
end
Board.Hash = hash

function Board.Digest(board)
	local out = {}
	for id, e in pairs(board.events) do
		local parts = { string.format("%d", e.u) }
		local guids = {}
		for guid in pairs(board.signups[id] or {}) do guids[#guids + 1] = guid end
		table.sort(guids)
		for _, guid in ipairs(guids) do parts[#parts + 1] = guid .. "=" .. string.format("%d", board.signups[id][guid].u) end
		out[id] = hash(table.concat(parts, ","))
	end
	return out
end

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------
-- "Fri 11 Dec, 20:00" in the player's own time zone.
function Board.When(at)
	return date("%a %d %b, %H:%M", at)
end

function Board.ShortWhen(at, now)
	if date("%Y-%m-%d", at) == date("%Y-%m-%d", now) then return "Today " .. date("%H:%M", at) end
	if date("%Y-%m-%d", at) == date("%Y-%m-%d", now + 86400) then return "Tomorrow " .. date("%H:%M", at) end
	return date("%a %d %b %H:%M", at)
end

---------------------------------------------------------------------------
-- Line-up for one raid (from v0.4.0's Raids tab)
---------------------------------------------------------------------------
-- ctx = { guild, now, profile = fn(guid), isOwn = fn(guid) }
-- Returns rows (coming first, then by role and name) and a summary.
function Board.LineUp(board, ev, ctx)
	local raid = Board.Raid(ev.raid)
	local rows, profiles = {}, {}
	for guid, su in pairs(board.signups[ev.id] or {}) do
		local p = ctx.profile(guid)
		local m = ctx.guild and ctx.guild.members[guid]
		local class = (m and m.class) or (p and p.class)
		local role, guess = su.r, false
		if not role then role, guess = SK.Data.GuessRole(class, p and p.talents), true end
		local gearHidden = p and p.hidden and p.hidden.gear
		local spec, tree
		if p and not gearHidden then spec, tree = SK.Talents.Summary(p.talents) end
		local att, attNote = SK.Attunements.StateOf(p, raid)
		rows[#rows + 1] = {
			guid = guid, name = (m and m.name) or (p and p.name) or "?", class = class,
			level = (m and m.level) or (p and p.level) or 0,
			status = su.s, statusName = Board.STATUS_NAME[su.s], group = Board.STATUS_GROUP[su.s],
			role = role, roleGuess = role ~= nil and guess or false,
			spec = spec, tree = tree, ilvl = (p and not gearHidden) and p.ilvl or nil,
			att = att, attNote = attNote, hasData = p ~= nil, online = m and m.online or false,
			stale = p ~= nil and not ctx.isOwn(guid) and type(p.updated) == "number"
				and ctx.now - p.updated > SK.Overview.STALE_AFTER or false,
			enchants = (p and p.gear and not gearHidden) and #SK.Data.Enchants.Missing(p.gear, p.class, p.level) or 0,
		}
		if p and ctx.guild then profiles[guid] = ctx.guild.profiles[guid] or p end
	end

	-- The same player signed up on two characters (mutually linked alts).
	local groupOf = SK.Alts.Groups(profiles, function(g) return profiles[g] ~= nil end)
	local seen, dupes = {}, {}
	for _, r in ipairs(rows) do
		local g = groupOf[r.guid]
		if g and #g.members > 1 and (r.group == "coming" or r.group == "maybe") then
			if seen[g] then
				r.duplicateOf, dupes[#dupes + 1] = seen[g], r.name .. " and " .. seen[g]
			else
				seen[g] = r.name
			end
		end
	end

	table.sort(rows, function(a, b)
		if a.group ~= b.group then return GROUP_ORDER[a.group] < GROUP_ORDER[b.group] end
		local ra, rb = ROLE_ORDER[a.role or ""] or 4, ROLE_ORDER[b.role or ""] or 4
		if ra ~= rb then return ra < rb end
		return a.name:lower() < b.name:lower()
	end)

	local s = { coming = 0, maybe = 0, out = 0,
		roles = { TANK = 0, HEALER = 0, DPS = 0, unknown = 0 }, guesses = 0,
		notAttuned = 0, noItem = 0, enchants = 0, stale = 0, noData = 0,
		ilvlMin = nil, ilvlMax = nil, duplicates = dupes, size = raid and raid.size or nil }
	for _, r in ipairs(rows) do
		s[r.group] = s[r.group] + 1
		if r.group == "coming" then
			local k = r.role or "unknown"
			s.roles[k] = s.roles[k] + 1
			if r.roleGuess then s.guesses = s.guesses + 1 end
			if r.att == "no" then s.notAttuned = s.notAttuned + 1 end
			if r.attNote then s.noItem = s.noItem + 1 end
			if r.enchants > 0 then s.enchants = s.enchants + 1 end
			if r.stale then s.stale = s.stale + 1 end
			if not r.hasData then s.noData = s.noData + 1 end
			if r.ilvl then
				s.ilvlMin = math.min(s.ilvlMin or r.ilvl, r.ilvl)
				s.ilvlMax = math.max(s.ilvlMax or r.ilvl, r.ilvl)
			end
		end
	end
	s.missing = {}
	if s.coming > 0 then
		if s.roles.TANK == 0 then s.missing[#s.missing + 1] = "No tanks yet" end
		if s.roles.HEALER == 0 then s.missing[#s.missing + 1] = "No healers yet" end
	end
	return rows, s
end

-- The usual ctx for LineUp: this guild, now, saved profiles.
function Board.Ctx()
	local guild = SK.DBM:Guild()
	return {
		guild = guild, now = Compat.Now(),
		profile = function(g) return SK.Profile:Get(g, guild) end,
		isOwn = function(g) return SK.DB.account[g] or false end,
	}
end

-- "Tanks 2 · Healers 6 · DPS 18 · 26 / 40"
function Board.CountsText(s)
	local parts = { "Tanks " .. s.roles.TANK, "Healers " .. s.roles.HEALER, "DPS " .. s.roles.DPS }
	if s.roles.unknown > 0 then parts[#parts + 1] = "Role unknown " .. s.roles.unknown end
	parts[#parts + 1] = s.size and (s.coming .. " / " .. s.size) or (s.coming .. " coming")
	return table.concat(parts, "  ·  ")
end

-- Readiness lines: { text, tone } for the page and Copy.
function Board.Readiness(s)
	local out = {}
	local function add(text, tone) out[#out + 1] = { text = text, tone = tone or "dim" } end
	for _, m in ipairs(s.missing) do add(m, "bad") end
	if s.maybe > 0 then add(s.maybe .. " tentative") end
	if s.size and s.coming > s.size then add((s.coming - s.size) .. " more than the raid holds (bench)", "spark") end
	if s.notAttuned > 0 then add(s.notAttuned .. " not attuned", "bad") end
	if s.noItem > 0 then add(s.noItem .. " without the amulet in their bags", "spark") end
	if s.ilvlMin then add(string.format("Item level %.0f to %.0f", s.ilvlMin, s.ilvlMax)) end
	if s.enchants > 0 then add(s.enchants .. " missing enchants", "spark") end
	if s.stale > 0 then add(s.stale .. " with data older than a week", "spark") end
	if s.guesses > 0 then add(s.guesses .. " roles guessed from talents") end
	for _, d in ipairs(s.duplicates) do add("Signed up twice: " .. d, "spark") end
	return out
end

-- Plain text for Copy (Discord). No colour codes.
function Board.Text(ev, rows, s)
	local raid = Board.Raid(ev.raid)
	local L = { string.format("%s, %s", raid and raid.name or "Raid", Board.When(ev.at)), Board.CountsText(s) }
	for _, r in ipairs(Board.Readiness(s)) do L[#L + 1] = "- " .. r.text end
	L[#L + 1] = ""
	for _, r in ipairs(rows) do
		local parts = { r.name, r.statusName }
		if r.role then parts[#parts + 1] = SK.Data.ROLE_NAMES[r.role] .. (r.roleGuess and " (guess)" or "") end
		if r.spec then parts[#parts + 1] = (r.tree and (r.tree .. " ") or "") .. r.spec end
		if r.ilvl then parts[#parts + 1] = string.format("ilvl %.0f", r.ilvl) end
		if r.att == "no" then parts[#parts + 1] = "not attuned" end
		L[#L + 1] = table.concat(parts, " · ")
	end
	return SK.Export.Plain(table.concat(L, "\n"))
end

---------------------------------------------------------------------------
-- New raid: the days and times offered (local time). Pure.
---------------------------------------------------------------------------
-- Midnight (local) of the day `now` falls on, plus `days`.
function Board.DayStart(now, days)
	local t = date("*t", now)
	return time({ year = t.year, month = t.month, day = t.day + (days or 0), hour = 0, min = 0, sec = 0, isdst = t.isdst })
end

-- Start time for a day (midnight) and minutes after midnight.
function Board.StartAt(dayStart, minutes)
	local t = date("*t", dayStart)
	return time({ year = t.year, month = t.month, day = t.day, hour = math.floor(minutes / 60), min = minutes % 60, sec = 0 })
end

---------------------------------------------------------------------------
-- The stored board and local actions
---------------------------------------------------------------------------
function Board:Get(guild)
	guild = guild or SK.DBM:Guild()
	if not guild then return nil end
	guild.raidBoard = guild.raidBoard or Board.New()
	guild.raidBoard.events = guild.raidBoard.events or {}
	guild.raidBoard.signups = guild.raidBoard.signups or {}
	return guild.raidBoard
end

local function me() return Compat.PlayerGUID() end

function Board.IsLeadSelf()
	return Board.CanLead(me())
end

-- Officers and raid leaders who typed /sr officer (it's remembered per
-- character) see New raid, Cancel and Attendance.
function Board.OfficerView()
	local guid = me()
	return guid ~= nil and SK.DB.officer[guid] == true and Board.CanLead(guid)
end

local function changed(keys)
	SK:Fire("RAIDS_UPDATED")
	if SK.RaidSync then SK.RaidSync:Queue(keys) end
end

-- Returns the new event, or nil and why.
function Board:Create(raidKey, at)
	local board, guid, now = self:Get(), me(), Compat.Now()
	if not board or not guid then return nil, "no guild" end
	if not Board.CanLead(guid) then return nil, "only officers and raid leaders can make raids" end
	if not Board.Raid(raidKey) then return nil, "pick a raid" end
	if at < now - 3600 then return nil, "that time has passed" end
	if SK.Count(board.events) >= Board.MAX_EVENTS then Board.Prune(board, now) end
	local e = { by = guid, c = now, raid = raidKey, at = at, u = now }
	e.id = guid .. ":" .. string.format("%d", now)
	while board.events[e.id] do
		e.c = e.c + 1
		e.id = guid .. ":" .. string.format("%d", e.c)
	end
	local ok, why = Board.MergeEvent(board, e, now, function(g) return Board.CanLead(g) end)
	if not ok then return nil, why end
	changed({ "E:" .. e.id })
	return board.events[e.id]
end

function Board:Cancel(id)
	local board, guid, now = self:Get(), me(), Compat.Now()
	local e = board and board.events[id]
	if not e then return false, "unknown raid" end
	if not Board.CanLead(guid) then return false, "only officers and raid leaders can cancel raids" end
	e.x, e.eb, e.u = true, guid, math.max(now, e.u + 1)
	changed({ "E:" .. id })
	return true
end

-- status "y" | "t" | "n", role or nil.
function Board:SignUp(id, status, role)
	local board, guid, now = self:Get(), me(), Compat.Now()
	local e = board and board.events[id]
	if not e or e.x then return false, "unknown raid" end
	if not Board.STATUS_NAME[status] then return false, "bad status" end
	local list = board.signups[id] or {}
	board.signups[id] = list
	local have = list[guid]
	list[guid] = { s = status, r = ROLE_ORDER[role or ""] and role or nil, u = math.max(now, have and have.u + 1 or 0) }
	if role and ROLE_ORDER[role] then SK.DB.raidRole[guid] = role end
	changed({ "S:" .. id .. "|" .. guid })
	return true
end

-- My role for sign-ups: the last one picked, else a guess from talents.
function Board.MyRole()
	local guid = me()
	local picked = guid and SK.DB.raidRole[guid]
	if picked then return picked, false end
	local own = SK.Profile:Own()
	local role = own and SK.Data.GuessRole(own.class, own.talents)
	return role, true
end

-- The next raid that isn't cancelled (for the Overview), or nil.
function Board.Next(board, now)
	return Board.Upcoming(board, now)[1]
end

function Board:OnLogin()
	SK.After(30, function()
		local board = self:Get()
		if board then Board.Prune(board, Compat.Now()) end
	end)
end
