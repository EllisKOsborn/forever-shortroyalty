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
--              u = last change, x = true when cancelled, eb = who changed it,
--              rs = v0.14.0 the night's instances "hyjal,ony", "" = to be
--                   decided (then raid = "tbd"); absent = just `raid`,
--              sr = v0.16.0 the first raid's id when made as a weekly series }
--   signup = { s = "y" (signed up) | "t" (tentative) | "n" (can't come),
--              r = "TANK" | "HEALER" | "DPS" | nil, u = last change,
--              w = v0.14.0 when they changed from Signed up to Tentative or
--                  Can't come (kept while they stay that way) }
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

-- v0.16.0 (weekly series): up to 60 raids that aren't cancelled, 150 in all
-- (cancelled ones are kept until a week after their date, so the cancel
-- reaches everyone). v0.15.1 and older keep 30 in all.
Board.MAX_EVENTS = 60
Board.MAX_STORED = 150
Board.MAX_WEEKS = 12            -- a weekly series made at once
Board.MAX_SIGNUPS = 100         -- sign-ups per raid
Board.MAX_FUTURE = 300          -- a change dated more than 5 minutes ahead is refused
-- v0.15.1 (owner: "there shouldn't really be a limit, let them make it
-- whenever they want"): no practical limit. A year and a bit only turns
-- away clearly broken dates. (v0.15.0 and older still drop raids more than
-- 60 days ahead until they're within 60 days, then pick them up.)
Board.AHEAD = 400 * 86400
Board.KEEP_AFTER = 7 * 86400    -- raids are deleted this long after they started
Board.LISTED_AFTER = 6 * 3600   -- still listed under Upcoming this long after the start

Board.STATUS_NAME = { y = "Signed up", t = "Tentative", n = "Can't come" }
Board.STATUS_GROUP = { y = "coming", t = "maybe", n = "out" }
-- v0.16.4 (owner: "I signed on Mana Tea but this is just an alt and now
-- needs to be removed"): a removed sign-up is kept as status "x" so the
-- removal syncs (newest wins); everything else treats it as no answer.
-- Older versions refuse "x" and keep showing the old answer.
Board.REMOVED = "x"

-- A sign-up that counts (nil when there's none or it was removed). Pure.
function Board.SignupOf(board, id, guid)
	local su = board and board.signups[id] and board.signups[id][guid or ""]
	if su and su.s ~= Board.REMOVED then return su end
	return nil
end
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
	-- v0.16.6 (owner: an officer's rank is "Loot Master"; the owner's own
	-- officer rank is "Addon Jesus"): those count too.
	return words:find(" officers? ") ~= nil or words:find(" raid ?leaders? ") ~= nil
		or words:find(" raid ?leads? ") ~= nil or words:find(" loot ?masters? ") ~= nil
		or words:find(" addon jesus ") ~= nil
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
-- v0.14.0: a raid night can be "to be decided" or cover several instances
-- (officer, 21 Nov). `raid` stays the first instance so older versions
-- still show the night; a night to be decided has raid = "tbd", which
-- older versions don't know and leave out. Pure.
---------------------------------------------------------------------------
Board.TBD = "tbd"

-- rs text -> list of keys in the order Raids shows them, or nil (bad).
function Board.ParseKeys(rs)
	if type(rs) ~= "string" or #rs > 60 then return nil end
	local want = {}
	for k in rs:gmatch("[^,]+") do
		if want[k] or not Board.Raid(k) then return nil end
		want[k] = true
	end
	if rs ~= "" and (rs:sub(1, 1) == "," or rs:sub(-1) == "," or rs:find(",,", 1, true)) then return nil end
	local out = {}
	for _, r in ipairs(SK.Data.ShownAttunements()) do
		if want[r.key] then out[#out + 1] = r.key end
	end
	return out
end

-- The night's instance keys (may be empty: to be decided).
function Board.Keys(ev)
	if ev.rs ~= nil then return Board.ParseKeys(ev.rs) or {} end
	if ev.raid == Board.TBD or not Board.Raid(ev.raid) then return {} end
	return { ev.raid }
end

function Board.Raids(ev)
	local out = {}
	for _, k in ipairs(Board.Keys(ev)) do out[#out + 1] = Board.Raid(k) end
	return out
end

-- "Onyxia's Lair + Hyjal Summit", short "Onyxia + Hyjal", or "Raid (to be
-- decided)" / "TBD".
function Board.EventName(ev, short)
	local names = {}
	for _, r in ipairs(Board.Raids(ev)) do names[#names + 1] = short and (r.short or r.name) or r.name end
	if #names == 0 then return short and "TBD" or "Raid (to be decided)" end
	return table.concat(names, " + ")
end

-- The biggest instance's size, or nil when to be decided.
function Board.EventSize(ev)
	local size
	for _, r in ipairs(Board.Raids(ev)) do size = math.max(size or 0, r.size or 0) end
	return size
end

-- The instance whose attunement counts (Onyxia's amulet), else the first.
function Board.AttRaid(ev)
	local list = Board.Raids(ev)
	for _, r in ipairs(list) do if r.status ~= "none" then return r end end
	return list[1]
end

-- Fields for keys: one instance keeps the v0.8.0 shape (no rs).
function Board.RaidFields(keys)
	if #keys == 1 then return keys[1], nil end
	if #keys == 0 then return Board.TBD, "" end
	return keys[1], table.concat(keys, ",")
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
	if e.rs ~= nil then
		local keys = Board.ParseKeys(e.rs)
		if not keys then return false, "bad raids" end
		if e.raid ~= (keys[1] or Board.TBD) then return false, "bad raids" end
	elseif not Board.Raid(e.raid) then
		return false, "unknown raid"
	end
	if not finite(e.at) or not finite(e.u) then return false, "bad time" end
	if e.u > now + Board.MAX_FUTURE then return false, "from the future" end
	if e.at > now + Board.AHEAD or e.at < now - Board.KEEP_AFTER - 86400 then return false, "too far away" end
	if e.x ~= nil and e.x ~= true then return false, "bad cancel" end
	if e.eb ~= nil and not str(e.eb, 64) then return false, "bad editor" end
	if e.sr ~= nil and not str(e.sr, 80) then return false, "bad series" end
	return true
end

function Board.ValidSignup(s, now)
	if type(s) ~= "table" then return false, "not a table" end
	if not str(s.e, 80) or not str(s.g, 64) then return false, "bad id" end
	if not Board.STATUS_NAME[s.s] and s.s ~= Board.REMOVED then return false, "bad status" end
	if s.r ~= nil and not ROLE_ORDER[s.r] then return false, "bad role" end
	if not finite(s.u) or s.u > now + Board.MAX_FUTURE then return false, "bad time" end
	if s.b ~= nil and not str(s.b, 64) then return false, "bad officer" end
	if s.w ~= nil and (not finite(s.w) or s.w > s.u or s.s == "y" or s.s == Board.REMOVED) then return false, "bad change" end
	return true
end

-- v0.14.0: when a sign-up moves away from "y", remember when (attendance
-- counts changed sign-ups); back to "y" forgets it. Pure.
function Board.ChangedAt(have, status, now)
	if status == "y" or status == Board.REMOVED then return nil end
	if have and have.s == "y" then return now end
	return have and have.w or nil
end

-- v0.10.0 raid roster: an officer puts a signed-up player In or on the
-- Bench ("-" = undecided again). Everyone sees it.
--   place = { e = raid id, g = player, v = "i" | "b" | "-", u = changed, by = officer }
Board.PLACE_NAME = { i = "In", b = "Bench" }
local PLACE_ORDER = { i = 1, b = 2 }
function Board.ValidPlace(p, now)
	if type(p) ~= "table" then return false, "not a table" end
	if not str(p.e, 80) or not str(p.g, 64) or not str(p.by, 64) then return false, "bad id" end
	if p.v ~= "i" and p.v ~= "b" and p.v ~= "-" then return false, "bad place" end
	if not finite(p.u) or p.u > now + Board.MAX_FUTURE then return false, "bad time" end
	return true
end

---------------------------------------------------------------------------
-- Merging (pure: board, item, now, roster checks)
---------------------------------------------------------------------------
-- Raids that aren't cancelled.
function Board.LiveCount(board)
	local n = 0
	for _, e in pairs(board.events) do if not e.x then n = n + 1 end end
	return n
end

-- v0.16.0: the start times of a weekly series, same local time each week
-- (whatever the clocks do). Pure.
function Board.WeeklyStarts(firstAt, weeks)
	local t = date("*t", firstAt)
	local out = {}
	for i = 0, (weeks or 1) - 1 do
		out[#out + 1] = time({ year = t.year, month = t.month, day = t.day + 7 * i, hour = t.hour, min = t.min, sec = 0 })
	end
	return out
end

function Board.New() return { events = {}, signups = {}, places = {}, slots = {}, assign = {} } end

-- isLead(guid) -> bool. Returns accepted, reason.
function Board.MergeEvent(board, e, now, isLead)
	local ok, why = Board.ValidEvent(e, now)
	if not ok then return false, why end
	if not isLead(e.by) or (e.eb and not isLead(e.eb)) then return false, "not an officer or raid leader" end
	local have = board.events[e.id]
	if have and have.u >= e.u then return false, "not newer" end
	if not have then
		if SK.Count(board.events) >= Board.MAX_STORED then return false, "too many raids" end
		if not e.x and Board.LiveCount(board) >= Board.MAX_EVENTS then return false, "too many raids" end
	end
	board.events[e.id] = { id = e.id, by = e.by, c = e.c, raid = e.raid, rs = e.rs, at = e.at, u = e.u, x = e.x, eb = e.eb,
		sr = e.sr }
	return true
end

-- isMember(guid) -> bool. A sign-up needs its raid. `b` = the officer who
-- added it for the player (v0.10.0 import from Discord): must be a lead
-- rank (isLead); a player's own sign-up has no `b`.
function Board.MergeSignup(board, s, now, isMember, isLead)
	local ok, why = Board.ValidSignup(s, now)
	if not ok then return false, why end
	if not isMember(s.g) then return false, "not a member" end
	if s.b and not (isLead and isLead(s.b)) then return false, "not an officer or raid leader" end
	if not board.events[s.e] then return false, "unknown raid" end
	local list = board.signups[s.e]
	if not list then
		list = {}
		board.signups[s.e] = list
	end
	local have = list[s.g]
	if have and have.u >= s.u then return false, "not newer" end
	if not have and SK.Count(list) >= Board.MAX_SIGNUPS then return false, "raid full of sign-ups" end
	list[s.g] = { s = s.s, r = s.r, u = s.u, b = s.b, w = s.w }
	return true
end

-- An officer's In / Bench choice (v0.10.0). Newest wins.
function Board.MergePlace(board, p, now, isMember, isLead)
	local ok, why = Board.ValidPlace(p, now)
	if not ok then return false, why end
	if not isLead(p.by) then return false, "not an officer or raid leader" end
	if not isMember(p.g) then return false, "not a member" end
	if not board.events[p.e] then return false, "unknown raid" end
	board.places = board.places or {}
	local list = board.places[p.e]
	if not list then
		list = {}
		board.places[p.e] = list
	end
	local have = list[p.g]
	if have and have.u >= p.u then return false, "not newer" end
	if not have and SK.Count(list) >= Board.MAX_SIGNUPS then return false, "too many" end
	list[p.g] = { v = p.v, u = p.u, by = p.by }
	return true
end

-- "i", "b" or nil.
function Board.PlaceOf(board, id, guid)
	local p = board.places and board.places[id] and board.places[id][guid]
	return p and PLACE_ORDER[p.v] and p.v or nil
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
	for id in pairs(board.places or {}) do
		if not board.events[id] then board.places[id] = nil end
	end
	for sid in pairs(board.slots or {}) do
		if not board.events[(SK.RaidGroups.SplitId(sid))] then board.slots[sid] = nil end
	end
	for id in pairs(board.assign or {}) do
		if not board.events[id] then board.assign[id] = nil end
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

-- v0.16.2: upcoming raids whose instances are decided: the ones reserves
-- are for (a raid "to be decided" has no loot list yet). Pure.
function Board.ReserveRaids(board, now)
	local out = {}
	for _, e in ipairs(Board.Upcoming(board, now)) do
		if #Board.Keys(e) > 0 then out[#out + 1] = e end
	end
	return out
end

-- Counts of one raid's sign-ups: { y, t, n }.
function Board.Counts(board, id)
	local c = { y = 0, t = 0, n = 0 }
	for _, s in pairs(board.signups[id] or {}) do if c[s.s] then c[s.s] = c[s.s] + 1 end end
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
		-- v0.10.0: In / Bench choices count too.
		local placed = {}
		for guid in pairs(board.places and board.places[id] or {}) do placed[#placed + 1] = guid end
		table.sort(placed)
		for _, guid in ipairs(placed) do parts[#parts + 1] = "P" .. guid .. "=" .. string.format("%d", board.places[id][guid].u) end
		-- v0.11.0: groups and marks too.
		-- v0.14.0: per instance too ("id@key").
		for _, sid in ipairs(SK.RaidGroups.SlotIds(board, id)) do
			local grouped = {}
			for guid in pairs(board.slots[sid]) do grouped[#grouped + 1] = guid end
			table.sort(grouped)
			local tag = sid == id and "G" or ("G" .. sid:sub(#id + 2) .. ":")
			for _, guid in ipairs(grouped) do parts[#parts + 1] = tag .. guid .. "=" .. string.format("%d", board.slots[sid][guid].u) end
		end
		local blocks = {}
		for k in pairs(board.assign and board.assign[id] or {}) do blocks[#blocks + 1] = k end
		table.sort(blocks)
		for _, k in ipairs(blocks) do parts[#parts + 1] = "A" .. k .. "=" .. string.format("%d", board.assign[id][k].u) end
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
	local raid = Board.AttRaid(ev) or { status = "none" }
	local rows, profiles = {}, {}
	for guid, su in pairs(board.signups[ev.id] or {}) do
		if su.s ~= Board.REMOVED then -- v0.16.4: a removed sign-up is as if never signed up
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
				place = Board.PlaceOf(board, ev.id, guid), byOfficer = su.b ~= nil,
				away = SK.Absences and SK.Absences.IsAway(SK.Absences.Of(ctx.guild, guid), ev.at) or false, -- v0.11.0
			}
			if p and ctx.guild then profiles[guid] = ctx.guild.profiles[guid] or p end
		end
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
		local pa, pb = PLACE_ORDER[a.place or ""] or 3, PLACE_ORDER[b.place or ""] or 3
		if pa ~= pb then return pa < pb end
		if a.group ~= b.group then return GROUP_ORDER[a.group] < GROUP_ORDER[b.group] end
		local ra, rb = ROLE_ORDER[a.role or ""] or 4, ROLE_ORDER[b.role or ""] or 4
		if ra ~= rb then return ra < rb end
		return a.name:lower() < b.name:lower()
	end)

	local s = { coming = 0, maybe = 0, out = 0,
		roles = { TANK = 0, HEALER = 0, DPS = 0, unknown = 0 }, guesses = 0,
		notAttuned = 0, noItem = 0, enchants = 0, stale = 0, noData = 0,
		ilvlMin = nil, ilvlMax = nil, duplicates = dupes, size = Board.EventSize(ev),
		placedIn = 0, placedBench = 0, inRoles = { TANK = 0, HEALER = 0, DPS = 0, unknown = 0 }, away = 0 }
	for _, r in ipairs(rows) do
		s[r.group] = s[r.group] + 1
		if r.away and r.group ~= "out" then s.away = s.away + 1 end
		if r.place == "i" then
			s.placedIn = s.placedIn + 1
			s.inRoles[r.role or "unknown"] = s.inRoles[r.role or "unknown"] + 1
		elseif r.place == "b" then
			s.placedBench = s.placedBench + 1
		end
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

-- v0.16.2 (owner: "if someone's absence overlaps with a scheduled raid,
-- show it in this view; it shouldn't only show away if they're signed, as
-- they realistically wouldn't be signing"): extra line-up rows for players
-- away on the raid's day who have no sign-up on any of their characters.
-- One row per player (the main of linked characters). officerDir: only
-- passed for officers, so days an officer set never reach members. Pure
-- apart from the ctx.
function Board.AwayRows(_, ev, ctx, rows, officerDir)
	local A = SK.Absences
	local guild = ctx.guild
	if not (A and guild and ev and ev.at) then return {} end
	local groupOf = A.Players(guild)
	local answered = {}
	for _, r in ipairs(rows or {}) do
		local g = groupOf[r.guid]
		answered[g and g.main or r.guid] = true
	end
	local day = date("%Y-%m-%d", ev.at)
	local out = {}
	for guid, m in pairs(guild.members or {}) do
		local g = groupOf[guid]
		local key = g and g.main or guid
		if not m.leftAt and not answered[key] then
			local away = A.IsAway(A.Of(guild, guid), ev.at)
				or (officerDir ~= nil and SK.OfficerDir.AwayOf(officerDir, guid)[day] == true)
			if away then
				answered[key] = true
				local mm = guild.members[key] or m
				local p = ctx.profile(key)
				local gearHidden = p and p.hidden and p.hidden.gear
				local tree
				if p and not gearHidden then local _, t = SK.Talents.Summary(p.talents); tree = t end
				local att = SK.Attunements.StateOf(p, Board.AttRaid(ev) or { status = "none" })
				out[#out + 1] = {
					guid = key, name = mm.name or (p and p.name) or "?", class = mm.class or (p and p.class),
					level = mm.level or (p and p.level) or 0, status = "a", statusName = "Away",
					group = "away", awayOnly = true, away = false, online = mm.online or false,
					tree = tree, ilvl = (p and not gearHidden) and p.ilvl or nil, att = att, hasData = p ~= nil,
				}
			end
		end
	end
	table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
	return out
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

-- "Tanks 2 · Healers 6 · DPS 18 · 26 / 40"; once officers have put people
-- In (v0.10.0): "In 18 / 40: Tanks 2 · Healers 5 · DPS 11 · Bench 3".
function Board.CountsText(s)
	if (s.placedIn or 0) > 0 then
		local r = s.inRoles
		local parts = { (s.size and ("In " .. s.placedIn .. " / " .. s.size) or ("In " .. s.placedIn)) .. ": Tanks " .. r.TANK,
			"Healers " .. r.HEALER, "DPS " .. r.DPS }
		if r.unknown > 0 then parts[#parts + 1] = "Role unknown " .. r.unknown end
		parts[#parts + 1] = "Bench " .. s.placedBench
		return table.concat(parts, "  ·  ")
	end
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
	if (s.away or 0) > 0 then add(s.away .. " signed up but marked away that day", "spark") end
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
	local L = { string.format("%s, %s", Board.EventName(ev), Board.When(ev.at)), Board.CountsText(s) }
	for _, r in ipairs(Board.Readiness(s)) do L[#L + 1] = "- " .. r.text end
	L[#L + 1] = ""
	for _, r in ipairs(rows) do
		local parts = { r.name, r.statusName }
		if r.place then parts[#parts + 1] = Board.PLACE_NAME[r.place] end
		if r.role then parts[#parts + 1] = SK.Data.ROLE_NAMES[r.role] .. (r.roleGuess and " (guess)" or "") end
		if r.spec then parts[#parts + 1] = (r.tree and (r.tree .. " ") or "") .. r.spec end
		if r.ilvl then parts[#parts + 1] = string.format("ilvl %.0f", r.ilvl) end
		if r.att == "no" then parts[#parts + 1] = "not attuned" end
		L[#L + 1] = table.concat(parts, " · ")
	end
	return SK.Export.Plain(table.concat(L, "\n"))
end

---------------------------------------------------------------------------
-- Discord, without any program (v0.10.0; owner: "It shouldn't require any
-- PC programs"). Addons can't reach the internet, so the bridge is copy and
-- paste: an announcement to paste into Discord, and sign-ups pasted back
-- from Discord. Pure.
---------------------------------------------------------------------------
local function plainName(n) return (tostring(n or "?"):gsub("[%*_~`|>]", "")) end

-- The announcement. <t:...> shows each reader the time in their own zone.
function Board.DiscordText(ev, rows, s)
	local at = string.format("%d", ev.at)
	local size = Board.EventSize(ev)
	local L = { string.format("**%s%s**: <t:%s:F> (<t:%s:R>)", Board.EventName(ev), size and (" (" .. size .. ")") or "", at, at),
		"Sign up in game: /sr raids (Short Royalty addon)", Board.CountsText(s), "" }
	local function names(filter)
		local out = {}
		for _, r in ipairs(rows) do if filter(r) then out[#out + 1] = plainName(r.name) end end
		return out
	end
	local function add(title, list)
		if #list > 0 then L[#L + 1] = string.format("**%s (%d):** %s", title, #list, table.concat(list, ", ")) end
	end
	local picked = (s.placedIn or 0) > 0
	for _, role in ipairs(SK.Data.ROLES) do
		add((picked and "In, " or "") .. SK.Data.ROLE_NAMES[role] .. (role == "DPS" and "" or "s"), names(function(r)
			return r.role == role and (picked and r.place == "i" or (not picked and r.group == "coming"))
		end))
	end
	add(picked and "In, role unknown" or "Role unknown", names(function(r)
		return not r.role and (picked and r.place == "i" or (not picked and r.group == "coming"))
	end))
	if picked then
		add("Bench", names(function(r) return r.place == "b" end))
		add("Signed up, not picked yet", names(function(r) return not r.place and r.group == "coming" end))
	end
	add("Tentative", names(function(r) return r.group == "maybe" and not r.place end))
	add("Can't come", names(function(r) return r.group == "out" end))
	return SK.Export.Plain(table.concat(L, "\n"))
end

-- v0.12.0: the code for Short Royalty's own Discord bot (discord-bot/,
-- /raid-post). Fields are split by ";" because the game's text boxes read
-- "|" as a colour code. The bot checks every line. Pure.
--   SR1;id;raid key;raid name;size;start;made
--   Character Name;y|t|n;TANK|HEALER|DPS|;i|b|;changed
function Board.BotCode(ev, rows, signups, now)
	local function clean(s) return (tostring(s or ""):gsub("[;|%c]", "")) end
	-- v0.14.0: several instances = the first one's key and every name
	-- ("Onyxia's Lair + Hyjal Summit"); to be decided = key "tbd", size 40.
	local L = { "In Discord: type /raid-post, paste all of this into the box, then Submit.",
		string.format("SR1;%s;%s;%s;%d;%d;%d", clean(ev.id), clean(ev.raid), clean(Board.EventName(ev)),
			Board.EventSize(ev) or 40, ev.at, now) }
	for _, r in ipairs(rows) do
		local su = signups and signups[r.guid] or {}
		L[#L + 1] = string.format("%s;%s;%s;%s;%d", clean(r.name), su.s or r.status or "y", r.role or "",
			r.place or "", tonumber(su.u) or 0)
	end
	return table.concat(L, "\n")
end

local ROLE_WORDS = { tank = "TANK", tanks = "TANK", heal = "HEALER", heals = "HEALER", healer = "HEALER",
	healers = "HEALER", healing = "HEALER", dps = "DPS", damage = "DPS", melee = "DPS", ranged = "DPS" }
local STATUS_WORDS = { tentative = "t", maybe = "t", absence = "n", absent = "n", absences = "n", declined = "n",
	decline = "n", cant = "n", cannot = "n", no = "n", bench = "y", late = "y", signed = "y", accepted = "y",
	confirmed = "y", yes = "y" }

-- Sign-ups pasted from Discord (any bot's list, or names typed by hand).
-- Each line's guild member names count; a line's own words (tank, healer,
-- dps, tentative, absence...) say how, else the last heading above it.
-- members = { [guid] = { name = "First Surname" } }.
-- Returns { entries = { { guid, s, r } }, unmatched = { line... } }.
function Board.ParseImport(text, members)
	local full, first = {}, {}
	for guid, m in pairs(members or {}) do
		local n = type(m.name) == "string" and m.name:lower() or nil
		if n then
			full[n] = guid
			local w = n:match("^(%S+)")
			if w and #w >= 3 then first[w] = (first[w] == nil) and guid or false end
		end
	end
	local entries, order, unmatched = {}, {}, {}
	local sectionRole, sectionStatus = nil, "y"
	for raw in tostring(text or ""):gmatch("[^\r\n]+") do
		local line = raw:lower():gsub("<[^>]*>", " "):gsub(":[%w_]+:", " ")
		line = line:gsub("can't", " cant "):gsub("can%s?not", " cannot ")
		local words = {}
		for w in line:gsub("[%p%d]", " "):gmatch("%S+") do words[#words + 1] = w end
		local role, status
		for _, w in ipairs(words) do
			role = role or ROLE_WORDS[w]
			status = status or STATUS_WORDS[w]
		end
		local found, used = {}, {}
		for i = 1, #words - 1 do
			local g = full[words[i] .. " " .. words[i + 1]]
			if g and not used[g] then found[#found + 1], used[g], used[i], used[i + 1] = g, true, true, true end
		end
		for i, w in ipairs(words) do
			local g = not used[i] and not ROLE_WORDS[w] and not STATUS_WORDS[w] and (full[w] or first[w])
			if g and not used[g] then found[#found + 1], used[g] = g, true end
		end
		if #found == 0 then
			if role then sectionRole, sectionStatus = role, "y"
			elseif status then sectionRole, sectionStatus = nil, status
			elseif raw:find("%a") and #unmatched < 20 then unmatched[#unmatched + 1] = raw:sub(1, 60) end
		else
			for _, g in ipairs(found) do
				if not entries[g] then order[#order + 1] = g end
				entries[g] = { guid = g, s = status or sectionStatus, r = role or sectionRole }
			end
		end
	end
	local out = {}
	for _, g in ipairs(order) do out[#out + 1] = entries[g] end
	return { entries = out, unmatched = unmatched }
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
	guild.raidBoard.places = guild.raidBoard.places or {}
	guild.raidBoard.slots = guild.raidBoard.slots or {}
	guild.raidBoard.assign = guild.raidBoard.assign or {}
	return guild.raidBoard
end

local function me() return Compat.PlayerGUID() end

function Board.IsLeadSelf()
	return Board.CanLead(me())
end

-- Officers and raid leaders who typed /sr officer (it's remembered per
-- character) see the officer tools: making raids on the Calendar (v0.14.0),
-- Cancel, Attendance and the Roster's Officers view.
function Board.OfficerView()
	local guid = me()
	return guid ~= nil and SK.DB.officer[guid] == true and Board.CanLead(guid)
end

local function changed(keys)
	SK:Fire("RAIDS_UPDATED")
	if SK.RaidSync then SK.RaidSync:Queue(keys) end
end

-- keys = a raid key, or a list of keys (v0.14.0; empty = to be decided).
-- sr = v0.16.0 series id, or true for "this raid starts a series".
-- Returns the new event, or nil and why.
function Board:Create(keys, at, sr)
	local board, guid, now = self:Get(), me(), Compat.Now()
	if not board or not guid then return nil, "no guild" end
	if not Board.CanLead(guid) then return nil, "only officers and raid leaders can make raids" end
	if type(keys) == "string" then keys = { keys } end
	keys = type(keys) == "table" and Board.ParseKeys(table.concat(keys, ",")) or nil
	if not keys then return nil, "pick a raid" end
	if at < now - 3600 then return nil, "that time has passed" end
	if at > now + Board.AHEAD then return nil, "that's more than a year ahead" end
	if Board.LiveCount(board) >= Board.MAX_EVENTS or SK.Count(board.events) >= Board.MAX_STORED then
		Board.Prune(board, now)
	end
	local raid, rs = Board.RaidFields(keys)
	local e = { by = guid, c = now, raid = raid, rs = rs, at = at, u = now }
	e.id = guid .. ":" .. string.format("%d", now)
	while board.events[e.id] do
		e.c = e.c + 1
		e.id = guid .. ":" .. string.format("%d", e.c)
	end
	if sr == true then e.sr = e.id elseif type(sr) == "string" then e.sr = sr end
	local ok, why = Board.MergeEvent(board, e, now, function(g) return Board.CanLead(g) end)
	if not ok then return nil, why end
	changed({ "E:" .. e.id })
	return board.events[e.id]
end

-- v0.16.0: a weekly series (owner: "the ability to create recurring raids
-- would be very useful"): the same time and instances, `weeks` raids from
-- firstAt. Returns the raids made, or nil and why (nothing is made then).
function Board:CreateSeries(keys, firstAt, weeks)
	local board, now = self:Get(), Compat.Now()
	if not board then return nil, "no guild" end
	weeks = math.max(1, math.min(Board.MAX_WEEKS, math.floor(tonumber(weeks) or 1)))
	if weeks == 1 then
		local e, why = self:Create(keys, firstAt)
		return e and { e } or nil, why
	end
	local starts = Board.WeeklyStarts(firstAt, weeks)
	if starts[#starts] > now + Board.AHEAD then return nil, "the last one would be more than a year ahead" end
	Board.Prune(board, now)
	local room = Board.MAX_EVENTS - Board.LiveCount(board)
	if room < weeks then
		return nil, "only room for " .. math.max(0, room) .. " more raids (" .. Board.MAX_EVENTS .. " at most)"
	end
	local out = {}
	for i, at in ipairs(starts) do
		local e, why = self:Create(keys, at, i == 1 and true or out[1].sr)
		if not e then return (#out > 0) and out or nil, why end
		out[#out + 1] = e
	end
	return out
end

-- The raids of a series from this one on (not cancelled), by date. Pure.
function Board.SeriesFrom(board, id)
	local ev = board.events[id]
	local out = {}
	if not ev or not ev.sr then return out end
	for _, e in pairs(board.events) do
		if e.sr == ev.sr and not e.x and e.at >= ev.at then out[#out + 1] = e end
	end
	table.sort(out, function(a, b) return a.at < b.at end)
	return out
end

-- Officers: cancel this raid and the later ones of its series.
function Board:CancelSeries(id)
	local board, guid, now = self:Get(), me(), Compat.Now()
	if not board or not board.events[id] then return 0, "unknown raid" end
	if not Board.CanLead(guid) then return 0, "only officers and raid leaders can cancel raids" end
	local keys = {}
	for _, e in ipairs(Board.SeriesFrom(board, id)) do
		e.x, e.eb, e.u = true, guid, math.max(now, e.u + 1)
		keys[#keys + 1] = "E:" .. e.id
	end
	if #keys > 0 then changed(keys) end
	return #keys
end

-- v0.14.0: officers choose (or change) the night's instances later.
function Board:SetRaids(id, keys)
	local board, guid, now = self:Get(), me(), Compat.Now()
	local e = board and board.events[id]
	if not e or e.x then return false, "unknown raid" end
	if not Board.CanLead(guid) then return false, "only officers and raid leaders can change raids" end
	keys = type(keys) == "table" and Board.ParseKeys(table.concat(keys, ",")) or nil
	if not keys then return false, "bad raids" end
	local before = { id = e.id, raid = e.raid, rs = e.rs }
	e.raid, e.rs = Board.RaidFields(keys)
	e.eb, e.u = guid, math.max(now, e.u + 1)
	local out = { "E:" .. id }
	for _, k in ipairs(SK.RaidGroups.Rehome(board, before, e, guid, now)) do out[#out + 1] = k end
	changed(out)
	return true
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
	local u = math.max(now, have and have.u + 1 or 0)
	list[guid] = { s = status, r = ROLE_ORDER[role or ""] and role or nil, u = u, w = Board.ChangedAt(have, status, u) }
	if role and ROLE_ORDER[role] then SK.DB.raidRole[guid] = role end
	changed({ "S:" .. id .. "|" .. guid })
	return true
end

-- v0.16.4: take a character off a raid. Officers can remove anyone; a
-- player can remove their own characters (this account). Returns ok, why.
function Board:RemoveSignup(id, guid)
	local board, now, mine = self:Get(), Compat.Now(), me()
	local e = board and board.events[id]
	if not e then return false, "unknown raid" end
	local have = board.signups[id] and board.signups[id][guid or ""]
	if not have or have.s == Board.REMOVED then return false, "not signed up" end
	local own = SK.DB.account[guid] ~= nil or guid == mine
	if not own and not Board.CanLead(mine) then return false, "only officers can remove someone else" end
	board.signups[id][guid] = { s = Board.REMOVED, u = math.max(now, have.u + 1), b = (not own) and mine or nil }
	local keys = { "S:" .. id .. "|" .. guid }
	if board.places[id] and board.places[id][guid] and Board.CanLead(mine) then
		board.places[id][guid] = { v = "-", u = math.max(now, board.places[id][guid].u + 1), by = mine }
		keys[#keys + 1] = "P:" .. id .. "|" .. guid
	end
	changed(keys)
	return true
end

-- Officers: put a signed-up player In ("i"), on the Bench ("b") or back
-- to undecided ("-"). Everyone sees it (v0.10.0).
function Board:SetPlace(id, guid, v)
	local board, officer, now = self:Get(), Compat.PlayerGUID(), Compat.Now()
	if not board or not board.events[id] then return false, "unknown raid" end
	if not Board.CanLead(officer) then return false, "only officers and raid leaders can pick the raid" end
	if v ~= "i" and v ~= "b" and v ~= "-" then return false, "bad place" end
	local list = board.places[id] or {}
	board.places[id] = list
	local have = list[guid]
	list[guid] = { v = v, u = math.max(now, have and have.u + 1 or 0), by = officer }
	changed({ "P:" .. id .. "|" .. guid })
	return true
end

-- Officers: sign-ups pasted from Discord (ParseImport's entries). A sign-up
-- the player made themselves in game is kept. Returns added, updated, kept.
function Board:Import(id, entries)
	local board, officer, now = self:Get(), Compat.PlayerGUID(), Compat.Now()
	local e = board and board.events[id]
	if not e or e.x then return nil, "unknown raid" end
	if not Board.CanLead(officer) then return nil, "only officers and raid leaders can import sign-ups" end
	local list = board.signups[id] or {}
	board.signups[id] = list
	local added, updated, kept, keys = 0, 0, 0, {}
	for _, x in ipairs(entries or {}) do
		local have = list[x.guid]
		if have and not have.b then
			kept = kept + 1
		elseif not have and SK.Count(list) >= Board.MAX_SIGNUPS then
			kept = kept + 1
		elseif not have or have.s ~= x.s or (x.r and have.r ~= x.r) then
			local u = math.max(now, have and have.u + 1 or 0)
			list[x.guid] = { s = x.s, r = x.r or (have and have.r), u = u, b = officer, w = Board.ChangedAt(have, x.s, u) }
			if have then updated = updated + 1 else added = added + 1 end
			keys[#keys + 1] = "S:" .. id .. "|" .. x.guid
		end
	end
	if #keys > 0 then changed(keys) end
	return added, updated, kept
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
