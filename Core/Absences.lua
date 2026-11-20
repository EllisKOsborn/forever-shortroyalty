-- Absences (v0.11.0): players mark the days they can't raid: single days,
-- or a weekday every week. Account-wide (SK.DB.away), shared in every one
-- of the player's profiles as the field `away` (checked by
-- Merge.FIELDS.away; older versions keep it as a plain extra field), so it
-- reaches the guild like gear does. Marking a day away also answers
-- "Can't come" to raids that day this character had signed up for.
--
--   away = { d = { "2026-12-11", ... } (local dates), w = { 1..7 } (Monday = 1), u = changed }
--
-- Pure parts (tested): Weekday, IsAway, Field, Of.
local _, SK = ...

local Abs = SK:NewModule("Absences")
local Compat = SK.Compat

Abs.MAX_DAYS = 40
Abs.WEEKDAYS = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }

-- Monday = 1 … Sunday = 7, in local time.
function Abs.Weekday(at)
	return (date("*t", at).wday + 5) % 7 + 1
end

function Abs.IsAway(away, at)
	if type(away) ~= "table" then return false end
	local key = date("%Y-%m-%d", at)
	for _, d in ipairs(away.d or {}) do if d == key then return true end end
	local wd = Abs.Weekday(at)
	for _, w in ipairs(away.w or {}) do if w == wd then return true end end
	return false
end

-- What goes in the profile: dates from today on, sorted, at most MAX_DAYS;
-- nil when there's nothing. Pure.
function Abs.Field(saved, now)
	if type(saved) ~= "table" then return nil end
	local today = date("%Y-%m-%d", now)
	local d, w = {}, {}
	for key in pairs(saved.d or {}) do if key >= today then d[#d + 1] = key end end
	table.sort(d)
	while #d > Abs.MAX_DAYS do table.remove(d) end
	for i = 1, 7 do if saved.w and saved.w[i] then w[#w + 1] = i end end
	if #d == 0 and #w == 0 then return nil end
	return { d = d, w = w, u = saved.u or now }
end

-- A member's absences: from their profile, or the newest of their linked
-- characters' (the same player). Pure apart from the guild table.
function Abs.Of(guild, guid)
	local p = guild and guild.profiles[guid]
	local best = p and p.away
	for _, alt in ipairs(p and p.family or {}) do
		local ap = guild.profiles[alt]
		if ap and ap.away and (not best or (ap.away.u or 0) > (best.u or 0)) then best = ap.away end
	end
	return best
end

-- Guild members (with the addon) away on that day: { guid... }.
function Abs.AwayOn(guild, at)
	local out = {}
	for guid, m in pairs(guild and guild.members or {}) do
		if not m.leftAt and Abs.IsAway(Abs.Of(guild, guid), at) then out[#out + 1] = guid end
	end
	return out
end

---------------------------------------------------------------------------
-- My own absences
---------------------------------------------------------------------------
function Abs:Saved()
	SK.DB.away = SK.DB.away or { d = {}, w = {} }
	SK.DB.away.d = SK.DB.away.d or {}
	SK.DB.away.w = SK.DB.away.w or {}
	return SK.DB.away
end

function Abs:Mine(now)
	return Abs.Field(self:Saved(), now or Compat.Now())
end

-- Raids on days I'm now away: answer Can't come where I'd said yes or maybe.
local function declineClashes(now)
	local B = SK.RaidBoard
	local board = B:Get()
	local me = Compat.PlayerGUID()
	local mine = Abs:Mine(now)
	for _, e in ipairs(board and B.Upcoming(board, now) or {}) do
		local su = board.signups[e.id] and board.signups[e.id][me or ""]
		if su and (su.s == "y" or su.s == "t") and Abs.IsAway(mine, e.at) then B:SignUp(e.id, "n", su.r) end
	end
end

local function changed()
	local now = Compat.Now()
	Abs:Saved().u = now
	if SK.Profile and SK.Profile.SetAway then SK.Profile:SetAway() end
	declineClashes(now)
	SK:Fire("ABSENCES_UPDATED")
	SK:Fire("RAIDS_UPDATED")
end

-- A day (any time on it). Days before today can't be marked.
function Abs:ToggleDay(at)
	local now = Compat.Now()
	local key = date("%Y-%m-%d", at)
	if key < date("%Y-%m-%d", now) then return false, "that day has passed" end
	local s = self:Saved()
	s.d[key] = not s.d[key] or nil
	changed()
	return true
end

function Abs:ToggleWeekday(wd)
	if type(wd) ~= "number" or wd < 1 or wd > 7 then return false end
	local s = self:Saved()
	s.w[wd] = not s.w[wd] or nil
	changed()
	return true
end

function Abs:IsMyDay(at)
	return Abs.IsAway(self:Mine(), at)
end
