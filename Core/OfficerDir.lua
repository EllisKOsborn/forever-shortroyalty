-- Officer roster (v0.10.1): what officers and raid leaders record about
-- members, for the Roster page's Officers view. Shared only between officer
-- and raid leader ranks, by whisper (Sync/OfficerSync.lua); members never
-- receive it.
--
-- guild.officerDir = { ["r:" .. guid] = entry, ["n:" .. guid] = …, ["a:" .. guid] = … }
--   r  roles: any of "T", "H", "D" (Tank, Healer, DPS), "" = none
--   n  note: plain text, at most NOTE_MAX characters, "" = none
--   a  alt of: the main's GUID, "" = not an alt
--   (v0.13.0, the roster planner; older versions reject these kinds safely)
--   t  role tiers: 3 letters for Tank, Healer, DPS, each "m" main, "b" backup
--      or "-" (e.g. "mb-"); replaces r, which still reads as mains
--   s  status: "r" Raider, "b" Backup, "s" Social (v0.14.0), "" not set
--      (not the guild rank)
--   d  away days an officer marked: "2026-12-09,2026-12-10" (local dates), "" = none
--   m  one officer's note: key "m:" .. guid .. ":" .. author GUID; only the
--      author can write it (by must be the author). n stays as a legacy note.
--   entry = { v = value, u = changed, by = officer GUID }; newest wins.
--
-- Pure parts (tested): Key, Split, CleanNote, Valid, Merge, RolesOf,
-- RolesText, NoteOf, AltOf, Rows, TiersOf, StatusOf, AwayOf, NotesOf.
local _, SK = ...

local OD = SK:NewModule("OfficerDir")
local Compat = SK.Compat

OD.NOTE_MAX = 300
OD.MAX_ENTRIES = 4000
OD.MAX_AWAY = 40
OD.MAX_FUTURE = 300
OD.ROLE_LETTERS = { T = "TANK", H = "HEALER", D = "DPS" }
OD.ROLE_ORDER = { "T", "H", "D" }

function OD.Key(kind, guid, author)
	if author then return kind .. ":" .. guid .. ":" .. author end
	return kind .. ":" .. guid
end
-- kind, member GUID (and the author for "m").
function OD.Split(key)
	if type(key) ~= "string" then return nil end
	local guid, author = key:match("^m:([^:]+):([^:]+)$")
	if guid then return "m", guid, author end
	return key:match("^([rnatsd]):([^:]+)$")
end

-- Plain text only: no colour codes, links or line breaks; trimmed; cut.
function OD.CleanNote(text)
	text = tostring(text or ""):gsub("|", ""):gsub("[%c]", " "):gsub("%s+", " ")
	text = text:gsub("^%s+", ""):gsub("%s+$", "")
	if #text > OD.NOTE_MAX then text = text:sub(1, OD.NOTE_MAX) end
	return text
end

local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
local function str(v, max) return type(v) == "string" and #v <= max end

-- Is one received entry well formed? Everything received is untrusted.
function OD.Valid(key, e, now)
	local kind, guid, author = OD.Split(key)
	if not kind or #guid > 64 or (author and #author > 64) then return false, "bad key" end
	if type(e) ~= "table" or not finite(e.u) or e.u > now + OD.MAX_FUTURE then return false, "bad time" end
	if not str(e.by, 64) or e.by == "" then return false, "bad officer" end
	local v = e.v
	if kind == "r" then
		if not str(v, 3) or not v:match("^[THD]*$") then return false, "bad roles" end
		local seen = {}
		for c in v:gmatch(".") do
			if seen[c] then return false, "bad roles" end
			seen[c] = true
		end
	elseif kind == "n" or kind == "m" then
		if not str(v, OD.NOTE_MAX) or v:find("[|%c]") then return false, "bad note" end
		if kind == "m" and e.by ~= author then return false, "not the author" end
	elseif kind == "t" then
		if not str(v, 3) or not (v == "" or v:match("^[-mb][-mb][-mb]$")) then return false, "bad tiers" end
	elseif kind == "s" then
		if v ~= "" and v ~= "r" and v ~= "b" and v ~= "s" then return false, "bad status" end
	elseif kind == "d" then
		if not str(v, 11 * OD.MAX_AWAY) then return false, "bad days" end
		for day in v:gmatch("[^,]*") do
			if day ~= "" and not day:match("^%d%d%d%d%-%d%d%-%d%d$") then return false, "bad days" end
		end
		if v ~= "" and (v:sub(1, 1) == "," or v:sub(-1) == "," or v:find(",,", 1, true)) then return false, "bad days" end
	elseif not str(v, 64) then
		return false, "bad alt"
	end
	return true
end

-- isLead(guid), isMember(guid). Returns accepted, reason.
function OD.Merge(dir, key, e, now, isLead, isMember)
	local ok, why = OD.Valid(key, e, now)
	if not ok then return false, why end
	local _, guid = OD.Split(key)
	if not isLead(e.by) then return false, "not an officer or raid leader" end
	if not isMember(guid) then return false, "not a member" end
	local have = dir[key]
	if have and have.u >= e.u then return false, "not newer" end
	if not have and SK.Count(dir) >= OD.MAX_ENTRIES then return false, "too many" end
	dir[key] = { v = e.v, u = e.u, by = e.by }
	return true
end

-- Roles as { TANK = true, ... } (nil when none set).
function OD.RolesOf(dir, guid)
	local e = dir and dir[OD.Key("r", guid)]
	if not e or e.v == "" then return nil end
	local out = {}
	for c in e.v:gmatch(".") do out[OD.ROLE_LETTERS[c]] = true end
	return out
end

-- "Tank, Healer" in a fixed order, or nil.
function OD.RolesText(dir, guid, short)
	local r = OD.RolesOf(dir, guid)
	if not r then return nil end
	local parts = {}
	for _, c in ipairs(OD.ROLE_ORDER) do
		local role = OD.ROLE_LETTERS[c]
		if r[role] then parts[#parts + 1] = short and (role == "HEALER" and "Heal" or SK.Data.ROLE_NAMES[role]) or SK.Data.ROLE_NAMES[role] end
	end
	return table.concat(parts, short and " " or ", ")
end

function OD.NoteOf(dir, guid)
	local e = dir and dir[OD.Key("n", guid)]
	return e and e.v ~= "" and e.v or nil
end

-- v0.13.0 roster planner -----------------------------------------------------
OD.TIER_ORDER = { "TANK", "HEALER", "DPS" }

-- { TANK = "m" | "b", ... } (empty when none). The tiers entry wins; the
-- older plain roles (v0.10.1) count as mains.
function OD.TiersOf(dir, guid)
	local out = {}
	local t = dir and dir[OD.Key("t", guid)]
	if t then
		for i, role in ipairs(OD.TIER_ORDER) do
			local c = t.v:sub(i, i)
			if c == "m" or c == "b" then out[role] = c end
		end
		return out
	end
	for role in pairs(OD.RolesOf(dir, guid) or {}) do out[role] = "m" end
	return out
end

function OD.TiersString(tiers)
	local s = ""
	for _, role in ipairs(OD.TIER_ORDER) do s = s .. (tiers[role] or "-") end
	return s
end

-- "r" Raider, "b" Backup, "s" Social, or nil.
function OD.StatusOf(dir, guid)
	local e = dir and dir[OD.Key("s", guid)]
	return e and e.v ~= "" and e.v or nil
end

-- Days an officer marked them away: { ["2026-12-09"] = true }.
function OD.AwayOf(dir, guid)
	local out = {}
	local e = dir and dir[OD.Key("d", guid)]
	for day in ((e and e.v) or ""):gmatch("[^,]+") do out[day] = true end
	return out
end

-- Every officer's note on a member, newest first: { { by, text, u, mine } }.
-- A legacy single note (v0.10.1) counts as its writer's unless they've
-- written a newer one of their own.
function OD.NotesOf(dir, guid, me)
	local out, authors = {}, {}
	local prefix = "m:" .. guid .. ":"
	for key, e in pairs(dir or {}) do
		if key:sub(1, #prefix) == prefix and e.v ~= "" then
			local author = key:sub(#prefix + 1)
			authors[author] = true
			out[#out + 1] = { by = author, text = e.v, u = e.u, mine = author == me }
		end
	end
	local n = dir and dir[OD.Key("n", guid)]
	if n and n.v ~= "" and not authors[n.by] then
		out[#out + 1] = { by = n.by, text = n.v, u = n.u, mine = n.by == me, legacy = true }
	end
	table.sort(out, function(a, b) if a.u ~= b.u then return a.u > b.u end return a.by < b.by end)
	return out
end

function OD.AltOf(dir, guid)
	local e = dir and dir[OD.Key("a", guid)]
	return e and e.v ~= "" and e.v or nil
end

-- One row per member for the Officers view. att = { [guid] = Attendance
-- totals row } for the period shown. Alts sit under their main: the
-- officers' link first, else the automatic one (both characters logged in
-- with the addon). Sorted by main, then main first, then name.
function OD.Rows(guild, dir, filter, att)
	local rows = {}
	if not guild then return rows end
	filter = filter and filter ~= "" and filter:lower() or nil
	local profiles = {}
	for guid, p in pairs(guild.profiles or {}) do
		local m = guild.members[guid]
		if m and not m.leftAt then profiles[guid] = p end
	end
	local groupOf = SK.Alts.Groups(profiles, function(g) return profiles[g] ~= nil end)
	for guid, m in pairs(guild.members) do
		if not m.leftAt then
			local main, how = OD.AltOf(dir, guid), "officer"
			if main and not (guild.members[main] and not guild.members[main].leftAt) then main = nil end
			if not main then
				local g = groupOf[guid]
				if g and #g.members > 1 and g.main ~= guid then main, how = g.main, "auto" end
			end
			local t = att and att[guid]
			local mainM = main and guild.members[main]
			local note = OD.NoteOf(dir, guid)
			local row = {
				guid = guid, name = m.name or "?", class = m.class, level = m.level or 0, rank = m.rank or "",
				rankIndex = m.rankIndex or 99, online = m.online, roles = OD.RolesText(dir, guid, true) or "",
				note = note, main = main, mainName = mainM and mainM.name or nil, altHow = main and how or nil,
				raids = t and (t.full + t.late + t.missed) or 0, pct = t and t.pct or nil, bench = t and t.bench or 0,
			}
			row.sortKey = ((row.mainName or row.name) .. (main and " 1 " or " 0 ") .. row.name):lower()
			local hay = (row.name .. " " .. row.rank .. " " .. row.roles .. " " .. (note or "") .. " " .. (row.mainName or "")):lower()
			if not filter or hay:find(filter, 1, true) then rows[#rows + 1] = row end
		end
	end
	table.sort(rows, function(a, b) return a.sortKey < b.sortKey end)
	return rows
end

---------------------------------------------------------------------------
-- Stored data and officers' changes
---------------------------------------------------------------------------
function OD:Get(guild)
	guild = guild or SK.DBM:Guild()
	if not guild then return nil end
	guild.officerDir = guild.officerDir or {}
	return guild.officerDir
end

-- kind "r" (roles string), "n" (note), "a" (main GUID or ""), and since
-- v0.13.0 "t" (tiers), "s" (status), "w" (away weeks), "m" (my own note).
-- Officers only.
function OD:Set(kind, guid, v)
	local dir, me, now = self:Get(), Compat.PlayerGUID(), Compat.Now()
	if not dir or not me then return false, "no guild" end
	if not SK.RaidBoard.CanLead(me) then return false, "only officers and raid leaders can change this" end
	if kind == "n" or kind == "m" then v = OD.CleanNote(v) end
	if kind == "a" and v == guid then v = "" end
	local key = OD.Key(kind, guid, kind == "m" and me or nil)
	local have = dir[key]
	local e = { v = v or "", u = math.max(now, have and have.u + 1 or 0), by = me }
	local ok, why = OD.Valid(key, e, now + 1)
	if not ok then return false, why end
	dir[key] = e
	SK:Fire("OFFICERDIR_UPDATED")
	if SK.OfficerSync then SK.OfficerSync:Share(key) end
	return true
end

-- Toggle one role (TANK/HEALER/DPS) for a character.
function OD:ToggleRole(guid, role)
	local have = OD.RolesOf(self:Get(), guid) or {}
	have[role] = not have[role] or nil
	local s = ""
	for _, c in ipairs(OD.ROLE_ORDER) do
		if have[OD.ROLE_LETTERS[c]] then s = s .. c end
	end
	return self:Set("r", guid, s)
end

-- v0.13.0: Main / Backup / nil for one role.
function OD:SetTier(guid, role, tier)
	local tiers = OD.TiersOf(self:Get(), guid)
	tiers[role] = (tier == "m" or tier == "b") and tier or nil
	return self:Set("t", guid, OD.TiersString(tiers))
end

function OD:SetStatus(guid, status)
	return self:Set("s", guid, (status == "r" or status == "b" or status == "s") and status or "")
end

-- Mark or clear one day ("2026-12-09"). Days before today are dropped.
function OD:ToggleAway(guid, day)
	local away = OD.AwayOf(self:Get(), guid)
	away[day] = not away[day] or nil
	local today = date("%Y-%m-%d", Compat.Now())
	local days = {}
	for d in pairs(away) do if d >= today then days[#days + 1] = d end end
	table.sort(days)
	while #days > OD.MAX_AWAY do table.remove(days) end
	return self:Set("d", guid, table.concat(days, ","))
end

-- Write (or, with "", remove) my own note. A legacy note I wrote moves into it.
function OD:SetMyNote(guid, text)
	local dir, me = self:Get(), Compat.PlayerGUID()
	local ok, why = self:Set("m", guid, text)
	if not ok then return ok, why end
	local legacy = dir and dir[OD.Key("n", guid)]
	if legacy and legacy.v ~= "" and legacy.by == me then self:Set("n", guid, "") end
	return true
end
