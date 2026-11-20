-- Officer roster (v0.10.1): what officers and raid leaders record about
-- members, for the Roster page's Officers view. Shared only between officer
-- and raid leader ranks, by whisper (Sync/OfficerSync.lua); members never
-- receive it.
--
-- guild.officerDir = { ["r:" .. guid] = entry, ["n:" .. guid] = …, ["a:" .. guid] = … }
--   r  roles: any of "T", "H", "D" (Tank, Healer, DPS), "" = none
--   n  note: plain text, at most NOTE_MAX characters, "" = none
--   a  alt of: the main's GUID, "" = not an alt
--   entry = { v = value, u = changed, by = officer GUID }; newest wins.
--
-- Pure parts (tested): Key, Split, CleanNote, Valid, Merge, RolesOf,
-- RolesText, NoteOf, AltOf, Rows.
local _, SK = ...

local OD = SK:NewModule("OfficerDir")
local Compat = SK.Compat

OD.NOTE_MAX = 300
OD.MAX_ENTRIES = 1500
OD.MAX_FUTURE = 300
OD.ROLE_LETTERS = { T = "TANK", H = "HEALER", D = "DPS" }
OD.ROLE_ORDER = { "T", "H", "D" }

function OD.Key(kind, guid) return kind .. ":" .. guid end
function OD.Split(key)
	if type(key) ~= "string" then return nil end
	return key:match("^([rna]):(.+)$")
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
	local kind, guid = OD.Split(key)
	if not kind or #guid > 64 then return false, "bad key" end
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
	elseif kind == "n" then
		if not str(v, OD.NOTE_MAX) or v:find("[|%c]") then return false, "bad note" end
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

-- kind "r" (roles string), "n" (note), "a" (main GUID or ""). Officers only.
function OD:Set(kind, guid, v)
	local dir, me, now = self:Get(), Compat.PlayerGUID(), Compat.Now()
	if not dir or not me then return false, "no guild" end
	if not SK.RaidBoard.CanLead(me) then return false, "only officers and raid leaders can change this" end
	if kind == "n" then v = OD.CleanNote(v) end
	if kind == "a" and v == guid then v = "" end
	local key = OD.Key(kind, guid)
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
