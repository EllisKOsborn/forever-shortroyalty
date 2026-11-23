-- Absences (v0.11.0): players mark the days they can't raid: single days,
-- or a weekday every week. Account-wide (SK.DB.away), shared in every one
-- of the player's profiles as the field `away` (checked by
-- Merge.FIELDS.away; older versions keep it as a plain extra field), so it
-- reaches the guild like gear does. Marking a day away also answers
-- "Can't come" to raids that day this character had signed up for.
--
--   away = { d = { "2026-12-11", ... } (local dates), w = { 1..7 } (Monday = 1), u = changed }
--
-- v0.16.0 (owner): no more "away every weekday" chips; players enter a
-- range of days instead (SetRange, ClearRun). Our own `w` is cleared once
-- (DB migrate); weekdays from older versions still count when received.
--
-- Pure parts (tested): Weekday, IsAway, Field, Of, Run, DayAt.
local _, SK = ...

local Abs = SK:NewModule("Absences")
local Compat = SK.Compat

Abs.MAX_DAYS = 40
Abs.RANGE_DAYS = 28 -- longest range entered in one go
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

-- Noon on the day `offset` days after `at`'s day (local time, safe over
-- summer/winter time changes). Pure.
function Abs.DayAt(at, offset)
	local t = date("*t", at)
	return time({ year = t.year, month = t.month, day = t.day + (offset or 0), hour = 12 })
end

-- The run of back-to-back away days (single days only) around `at`:
-- firstAt, lastAt, or nil when that day isn't marked. Pure.
function Abs.Run(saved, at)
	local d = type(saved) == "table" and saved.d or {}
	local function on(off) return d[date("%Y-%m-%d", Abs.DayAt(at, off))] == true end
	if not on(0) then return nil end
	local lo, hi = 0, 0
	while lo > -Abs.MAX_DAYS and on(lo - 1) do lo = lo - 1 end
	while hi < Abs.MAX_DAYS and on(hi + 1) do hi = hi + 1 end
	return Abs.DayAt(at, lo), Abs.DayAt(at, hi)
end

-- "10-14 Dec", "30 Nov-2 Dec", "10 Dec". Pure.
function Abs.RangeText(firstAt, lastAt)
	local a, b = date("*t", firstAt), date("*t", lastAt)
	if a.year == b.year and a.month == b.month and a.day == b.day then return (date("%d %b", firstAt):gsub("^0", "")) end
	if a.year == b.year and a.month == b.month then
		return tostring(a.day) .. "-" .. (date("%d %b", lastAt):gsub("^0", ""))
	end
	return (date("%d %b", firstAt):gsub("^0", "")) .. "-" .. (date("%d %b", lastAt):gsub("^0", ""))
end

-- What goes in the profile: dates from today on, sorted, at most MAX_DAYS;
-- nil when nothing was ever marked. v0.16.4 (owner: "I've marked myself as
-- no longer being away … but it's still showing as away"): once marked,
-- an empty list still goes out with its time, so it beats the older copy
-- on the player's alts (Abs.Of takes the newest). Pure.
function Abs.Field(saved, now)
	if type(saved) ~= "table" then return nil end
	local today = date("%Y-%m-%d", now)
	local d, w = {}, {}
	for key in pairs(saved.d or {}) do if key >= today then d[#d + 1] = key end end
	table.sort(d)
	while #d > Abs.MAX_DAYS do table.remove(d) end
	for i = 1, 7 do if saved.w and saved.w[i] then w[#w + 1] = i end end
	if #d == 0 and #w == 0 and not saved.u then return nil end
	return { d = d, w = w, u = saved.u or now }
end

-- A member's absences: from their profile, or the newest of their linked
-- characters' (the same player). Pure apart from the guild table.
function Abs.Of(guild, guid)
	local p = guild and guild.profiles[guid]
	local best = p and p.away
	for _, alt in ipairs(p and p.family or {}) do
		local ap = guild.profiles[alt]
		-- v0.16.2: only a two-way link counts (as in Alts), so nobody picks up
		-- someone else's away days by listing them as family.
		local linked = false
		for _, back in ipairs(ap and type(ap.family) == "table" and ap.family or {}) do
			if back == guid then linked = true end
		end
		if linked and ap.away and (not best or (ap.away.u or 0) > (best.u or 0)) then best = ap.away end
	end
	return best
end

-- Linked characters grouped per player (Alts.Groups over current members).
function Abs.Players(guild)
	local members = guild and guild.members or {}
	return (SK.Alts.Groups(guild and guild.profiles or {}, function(guid)
		return members[guid] ~= nil and not members[guid].leftAt
	end))
end

-- Players (with the addon) away on that day: { guid... }, one per player
-- (the main of linked characters). v0.16.2: it counted every character, and
-- each alt carries its player's away days, so one player with two alts
-- showed as "3 away" (owner's screenshot). groupOf: Abs.Players(guild),
-- passed in when asking for many days.
function Abs.AwayOn(guild, at, groupOf)
	groupOf = groupOf or Abs.Players(guild)
	local out, seen = {}, {}
	for guid, m in pairs(guild and guild.members or {}) do
		if not m.leftAt and Abs.IsAway(Abs.Of(guild, guid), at) then
			local group = groupOf[guid]
			local key = group and group.main or guid
			if not seen[key] then
				seen[key] = true
				out[#out + 1] = key
			end
		end
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

-- Raids on days I'm away: answer Can't come. all = true (I've just marked
-- the days): also where I'd said yes or maybe. v0.16.4 (GM: "automatically
-- select can't come for any raids that are or will be created on those
-- dates"): raids I haven't answered get Can't come too, also raids made
-- later (on RAIDS_UPDATED and at login). A later Sign up of my own stays:
-- only unanswered raids are answered for me. Returns how many.
function Abs.DeclineClashes(now, all)
	local B = SK.RaidBoard
	local board = B and B:Get()
	local me = Compat.PlayerGUID()
	if not board or not me then return 0 end
	local mine = Abs:Mine(now)
	if not mine then return 0 end
	local n = 0
	for _, e in ipairs(B.Upcoming(board, now)) do
		if Abs.IsAway(mine, e.at) then
			local su = board.signups[e.id] and board.signups[e.id][me]
			if not su or (all and (su.s == "y" or su.s == "t")) then
				if B:SignUp(e.id, "n", su and su.r or nil) then n = n + 1 end
			end
		end
	end
	return n
end
local declineClashes = function(now) return Abs.DeclineClashes(now, true) end

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

-- v0.16.0: away from `fromAt`'s day for `days` days (1 = just that day).
function Abs:SetRange(fromAt, days)
	local now = Compat.Now()
	if type(days) ~= "number" or days < 1 or days > Abs.RANGE_DAYS then return false, "too many days" end
	if date("%Y-%m-%d", fromAt) < date("%Y-%m-%d", now) then return false, "that day has passed" end
	local s = self:Saved()
	for i = 0, days - 1 do s.d[date("%Y-%m-%d", Abs.DayAt(fromAt, i))] = true end
	changed()
	return true
end

-- Not away after all: clears the whole run of days around `at`.
function Abs:ClearRun(at)
	local s = self:Saved()
	local first, last = Abs.Run(s, at)
	if not first then return false end
	local today = date("%Y-%m-%d", Compat.Now())
	local i = 0
	while true do
		local key = date("%Y-%m-%d", Abs.DayAt(first, i))
		if key >= today then s.d[key] = nil end
		if key >= date("%Y-%m-%d", last) then break end
		i = i + 1
	end
	changed()
	return true
end

function Abs:OnLogin()
	SK:On("RAIDS_UPDATED", function()
		SK:Debounce("awaydecline", 2, function() Abs.DeclineClashes(Compat.Now(), false) end)
	end)
	SK.After(20, function() Abs.DeclineClashes(Compat.Now(), false) end)
end

function Abs:IsMyDay(at)
	return Abs.IsAway(self:Mine(), at)
end
