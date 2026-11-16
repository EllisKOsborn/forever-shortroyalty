-- Reserve+ (v0.9.0, not released): soft reserves with bonus points, the
-- guild's TBC system. Plan and the owner's rules:
-- docs/proposals/loot-addon-plan.md.
--
-- Points belong to ONE character and ONE item. Each raid night you reserve
-- a few items (how many is set per raid by officers: 1 by default, e.g. 2
-- in Hyjal, 4 in a big raid). Every reserved item you didn't get that night
-- gains the bonus (no cap) if you were in the raid, or on the bench and
-- online when reserves were locked. Whether its boss died doesn't matter
-- (owner, 16 Nov: people reserving from the last bosses mustn't fall
-- behind). Winning an item sets its points to 0. Points on other items wait
-- until you reserve them again, and only tonight's reserves' points count.
--
-- Points are never stored as plain numbers. They are added up from a
-- HISTORY of changes ("ledger") that only officers and raid leaders write,
-- so every number can be explained and any change undone:
--
--   entry = { id = by .. ":" .. c, by = officer GUID, c = time made, k = kind, ... }
--     k = "n"  night bonus: e = raid id, b = bonus, g = { [guid] = { itemID, ... } }
--     k = "w"  won:         g = guid, i = itemID, e = raid id (optional)
--     k = "a"  adjust:      g = guid, i = itemID, d = +/- points, r = reason
--     k = "m"  move:        g, i (from) -> g2, i2 (to), d = points or all = true, r
--     k = "s"  settings:    b = bonus per night
--     k = "p"  settings:    raid = raid key, n = reserves per player there
--     k = "x"  undo:        x = id of the entry undone, r = reason
--
-- Entries never change once made (an undo is a new entry). Every player's
-- game replays them in the same order (time, then id), so everyone gets
-- the same points. Received entries are untrusted: ValidEntry checks the
-- shape, Merge checks against OUR OWN roster that the author is an officer
-- or raid leader (RaidBoard.IsLeadRank).
--
-- Stored per guild in guild.reserves = { ledger = { [id] = entry } }.
-- Pure parts (tested): ValidEntry, Merge, Replay, PointsOf, ItemsOf,
-- Rank, NightGrants, BenchAtLock, PicksFor, Count.
local _, SK = ...

local R = SK:NewModule("Reserves")
local Compat = SK.Compat

R.DEFAULT_BONUS = 10      -- points per night until an officer changes it
R.MAX_BONUS = 1000        -- the bonus setting can't be set above this
R.MAX_ADJUST = 100000     -- one manual change can't move more than this
R.MAX_ENTRIES = 20000     -- about 10 years of weekly raids with room to spare
R.MAX_GRANTS = 80         -- characters in one night bonus (40-player raid + bench)
R.MAX_REASON = 80         -- characters in a reason
R.MAX_FUTURE = 300        -- an entry dated more than 5 minutes ahead is refused
R.ROLL_MAX = 100          -- only /roll 1-100 counts
R.MAX_PICKS = 8           -- reserves per player per raid can be set up to this

R.KIND_NAME = { n = "Night bonus", w = "Won", a = "Changed by hand", m = "Moved", s = "Bonus changed",
	p = "Reserves changed", x = "Undone" }

---------------------------------------------------------------------------
-- Checks for anything received (untrusted)
---------------------------------------------------------------------------
local function int(v) return type(v) == "number" and v == v and v == math.floor(v) and v > -math.huge and v < math.huge end
local function str(v, max) return type(v) == "string" and #v > 0 and #v <= max end
local function item(v) return int(v) and v > 0 and v < 10000000 end
local function guid(v) return str(v, 64) end
-- Reasons are shown in the window and History: no colour codes, links or
-- textures ("|"), no line breaks.
local function reason(v) return v == nil or (type(v) == "string" and #v <= R.MAX_REASON and not v:find("[|%c]")) end

R.IsItem = item

-- Returns ok, why.
function R.ValidEntry(e, now)
	if type(e) ~= "table" then return false, "not a table" end
	if not guid(e.by) or not int(e.c) or e.id ~= e.by .. ":" .. string.format("%d", e.c) then return false, "bad id" end
	if e.c > now + R.MAX_FUTURE then return false, "from the future" end
	if not reason(e.r) then return false, "bad reason" end
	local k = e.k
	if k == "n" then
		if not str(e.e, 80) or not int(e.b) or e.b < 0 or e.b > R.MAX_BONUS then return false, "bad night" end
		if type(e.g) ~= "table" then return false, "bad night" end
		local n = 0
		for g, items in pairs(e.g) do
			n = n + 1
			if n > R.MAX_GRANTS or not guid(g) or type(items) ~= "table" then return false, "bad night" end
			local seen, c = {}, 0
			for k2, i in pairs(items) do
				c = c + 1
				if c > R.MAX_PICKS or not int(k2) or k2 < 1 or k2 > R.MAX_PICKS or not item(i) or seen[i] then return false, "bad night" end
				seen[i] = true
			end
			if c == 0 then return false, "bad night" end
		end
	elseif k == "w" then
		if not guid(e.g) or not item(e.i) or (e.e ~= nil and not str(e.e, 80)) then return false, "bad win" end
	elseif k == "a" then
		if not guid(e.g) or not item(e.i) or not int(e.d) or e.d == 0 or math.abs(e.d) > R.MAX_ADJUST then
			return false, "bad change"
		end
	elseif k == "m" then
		if not guid(e.g) or not item(e.i) or not guid(e.g2) or not item(e.i2) then return false, "bad move" end
		if e.g == e.g2 and e.i == e.i2 then return false, "bad move" end
		if e.all == true then
			if e.d ~= nil then return false, "bad move" end
		elseif e.all ~= nil or not int(e.d) or e.d <= 0 or e.d > R.MAX_ADJUST then
			return false, "bad move"
		end
	elseif k == "s" then
		if not int(e.b) or e.b < 0 or e.b > R.MAX_BONUS then return false, "bad setting" end
	elseif k == "p" then
		if not str(e.raid, 20) or not int(e.n) or e.n < 1 or e.n > R.MAX_PICKS then return false, "bad setting" end
	elseif k == "x" then
		if not str(e.x, 80) or e.x == e.id then return false, "bad undo" end
	else
		return false, "unknown kind"
	end
	return true
end

-- Copies only the fields its kind uses (nothing extra is stored or passed on).
local FIELDS = {
	n = { "e", "b", "g" }, w = { "g", "i", "e" }, a = { "g", "i", "d", "r" },
	m = { "g", "i", "g2", "i2", "d", "all", "r" }, s = { "b" }, p = { "raid", "n" }, x = { "x", "r" },
}
local function deep(v)
	if type(v) ~= "table" then return v end
	local t = {}
	for a, b in pairs(v) do t[a] = deep(b) end
	return t
end
local function copy(e)
	local out = { id = e.id, by = e.by, c = e.c, k = e.k }
	for _, f in ipairs(FIELDS[e.k]) do
		out[f] = deep(e[f])
	end
	return out
end

---------------------------------------------------------------------------
-- Merging (pure: ledger, entry, now, isLead(guid) -> bool)
---------------------------------------------------------------------------
function R.New() return { ledger = {} } end

function R.Count(store)
	return SK.Count(store.ledger)
end

-- Returns accepted, why. Entries never change, so a known id is skipped.
function R.Merge(store, e, now, isLead)
	local ok, why = R.ValidEntry(e, now)
	if not ok then return false, why end
	if not isLead(e.by) then return false, "not an officer or raid leader" end
	if store.ledger[e.id] then return false, "already have it" end
	if R.Count(store) >= R.MAX_ENTRIES then return false, "history full" end
	store.ledger[e.id] = copy(e)
	return true
end

---------------------------------------------------------------------------
-- Adding up (pure)
---------------------------------------------------------------------------
local function ordered(store)
	local list = {}
	for _, e in pairs(store.ledger) do list[#list + 1] = e end
	table.sort(list, function(a, b)
		if a.c ~= b.c then return a.c < b.c end
		return a.id < b.id
	end)
	return list
end
R.Ordered = ordered

-- Replays the history. Returns state = {
--   points = { [guid] = { [itemID] = points } },
--   bonus  = bonus per night now,
--   picks  = { [raid key] = reserves per player } (PicksFor gives the default),
--   undone = { [id] = id of the undo },
--   lines  = { [guid] = { [itemID] = { { id, c, k, d, r, by } ... } } } (why each number is what it is),
-- }
-- Undo entries are applied first (an undo can arrive before or after what
-- it undoes; undoing an undo isn't allowed).
function R.Replay(store)
	local list = ordered(store)
	local undone = {}
	for _, e in ipairs(list) do
		local t = e.k == "x" and store.ledger[e.x]
		if t and t.k ~= "x" then undone[e.x] = e.id end
	end
	local st = { points = {}, bonus = R.DEFAULT_BONUS, picks = {}, undone = undone, lines = {} }
	local function add(g, i, d, e)
		local p = st.points[g] or {}
		st.points[g] = p
		local before = p[i] or 0
		local after = d == "reset" and 0 or before + d
		p[i] = after
		local l = st.lines[g] or {}
		st.lines[g] = l
		l[i] = l[i] or {}
		local list2 = l[i]
		list2[#list2 + 1] = { id = e.id, c = e.c, k = e.k, d = after - before, r = e.r, by = e.by }
	end
	for _, e in ipairs(list) do
		if not undone[e.id] then
			if e.k == "n" then
				for g, items in pairs(e.g) do
					for _, i in ipairs(items) do add(g, i, e.b, e) end
				end
			elseif e.k == "w" then
				add(e.g, e.i, "reset", e)
			elseif e.k == "a" then
				add(e.g, e.i, e.d, e)
			elseif e.k == "m" then
				local have = st.points[e.g] and st.points[e.g][e.i] or 0
				local d = e.all and have or e.d
				if d ~= 0 then
					add(e.g, e.i, -d, e)
					add(e.g2, e.i2, d, e)
				end
			elseif e.k == "s" then
				st.bonus = e.b
			elseif e.k == "p" then
				st.picks[e.raid] = e.n
			end
		end
	end
	return st
end

-- Reserves per player in a raid (1 until officers set it for that raid).
function R.PicksFor(st, raidKey)
	return st and st.picks[raidKey] or 1
end

function R.PointsOf(st, g, i)
	return st.points[g] and st.points[g][i] or 0
end

-- One character's items with points (or a history), most points first.
function R.ItemsOf(st, g)
	local out = {}
	for i, p in pairs(st.points[g] or {}) do out[#out + 1] = { item = i, points = p } end
	table.sort(out, function(a, b)
		if a.points ~= b.points then return a.points > b.points end
		return a.item < b.item
	end)
	return out
end

---------------------------------------------------------------------------
-- The night (pure)
---------------------------------------------------------------------------
-- Who wins an item. rolls = list of { guid, roll, min, max } in the order
-- they were rolled; picks = { [guid] = { [itemID] = true } } tonight's reserves;
-- st = Replay state. Only the first 1-100 roll of each character counts.
-- Reservers of this item always come first, by roll + their points on it;
-- then everyone else by roll. Equal totals: more points wins; equal
-- totals and points: tie (re-roll). Returns rows (best first), each
-- { guid, roll, bonus, total, reserved, tie }, and the ignored rolls.
function R.Rank(itemID, rolls, picks, st)
	local rows, seen, ignored = {}, {}, {}
	for _, r in ipairs(rolls) do
		if type(r) == "table" and guid(r.guid) and int(r.roll) and r.min == 1 and r.max == R.ROLL_MAX
			and r.roll >= 1 and r.roll <= R.ROLL_MAX and not seen[r.guid] then
			seen[r.guid] = true
			local reserved = picks[r.guid] ~= nil and picks[r.guid][itemID] == true
			local bonus = reserved and R.PointsOf(st, r.guid, itemID) or 0
			rows[#rows + 1] = { guid = r.guid, roll = r.roll, bonus = bonus, total = r.roll + bonus, reserved = reserved, order = #rows + 1 }
		else
			ignored[#ignored + 1] = r
		end
	end
	-- Equal totals: more points wins (the guild's TBC rule, as in Kerath
	-- Raidcheck); equal totals AND points: a tie, re-roll.
	table.sort(rows, function(a, b)
		if a.reserved ~= b.reserved then return a.reserved end
		if a.total ~= b.total then return a.total > b.total end
		if a.bonus ~= b.bonus then return a.bonus > b.bonus end
		return a.order < b.order
	end)
	local top = rows[1]
	for _, r in ipairs(rows) do
		r.tie = top ~= nil and r ~= top and r.reserved == top.reserved and r.total == top.total and r.bonus == top.bonus or nil
		if r.tie then top.tie = true end
	end
	return rows, ignored
end

-- Who was on the bench when reserves were locked. picks = tonight's
-- reserves; inRaid(guid), online(guid) -> bool. Returns { [guid] =
-- "bench" (online, not in the raid) | "offline" }; people in the raid
-- aren't listed. Officers see this when they lock reserves.
function R.BenchAtLock(picks, inRaid, online)
	local out = {}
	for g in pairs(picks) do
		if not inRaid(g) then out[g] = online(g) and "bench" or "offline" end
	end
	return out
end

-- The end-of-night bonus. picks = { [guid] = { [itemID] = true } };
-- where(guid) -> "raid" (was in the raid tonight), "bench" (online on the
-- bench when reserves were locked), "offline" (on the bench but offline
-- then) or nil (not there); won = { [guid] = { [itemID] = true } } (items
-- given tonight). Whether the item's boss died doesn't matter (owner, 16
-- Nov). Returns grants { [guid] = { itemID, ... } (sorted) } and, for the
-- officer's check, skipped { [guid] = reason } for people who get nothing
-- and wonItems { [guid] = { itemID, ... } } for reserves they won.
function R.NightGrants(picks, where, won)
	local grants, skipped, wonItems = {}, {}, {}
	for g, set in pairs(picks) do
		local w = where(g)
		if w ~= "raid" and w ~= "bench" then
			skipped[g] = w == "offline" and "on the bench but offline at the lock" or "not there"
		else
			local items, got = {}, {}
			for i in pairs(set) do
				if won[g] and won[g][i] then got[#got + 1] = i else items[#items + 1] = i end
			end
			table.sort(items)
			table.sort(got)
			if #items > 0 then grants[g] = items end
			if #got > 0 then wonItems[g] = got end
			if #items == 0 then skipped[g] = "won it" end
		end
	end
	return grants, skipped, wonItems
end

---------------------------------------------------------------------------
-- The stored history and local actions (officers and raid leaders)
---------------------------------------------------------------------------
function R:Get(guild)
	guild = guild or SK.DBM:Guild()
	if not guild then return nil end
	guild.reserves = guild.reserves or R.New()
	guild.reserves.ledger = guild.reserves.ledger or {}
	return guild.reserves
end

local cache -- { n = entries, st = state }; replaying 20 000 entries on every redraw would be slow

function R:State()
	local store = self:Get()
	if not store then return nil end
	local n = R.Count(store)
	if not cache or cache.store ~= store or cache.n ~= n then
		cache = { store = store, n = n, st = R.Replay(store) }
	end
	return cache.st
end

local function me() return Compat.PlayerGUID() end
local function canLead(g) return SK.RaidBoard.CanLead(g) end

-- Makes, stores and shares one entry. Returns the entry, or nil and why.
function R:Add(fields)
	local store, by, now = self:Get(), me(), Compat.Now()
	if not store or not by then return nil, "no guild" end
	if not canLead(by) then return nil, "only officers and raid leaders can change points" end
	local e = { by = by, c = now }
	for k, v in pairs(fields) do e[k] = v end
	e.id = by .. ":" .. string.format("%d", e.c)
	while store.ledger[e.id] do -- two changes in the same second
		e.c = e.c + 1
		e.id = by .. ":" .. string.format("%d", e.c)
	end
	local ok, why = R.Merge(store, e, now, canLead)
	if not ok then return nil, why end
	SK:Fire("RESERVES_UPDATED")
	if SK.ReserveSync then SK.ReserveSync:Queue({ e.id }) end
	return store.ledger[e.id]
end

function R:Adjust(g, i, d, why) return self:Add({ k = "a", g = g, i = i, d = d, r = why }) end
function R:Move(g, i, g2, i2, d, why)
	if d == "all" then return self:Add({ k = "m", g = g, i = i, g2 = g2, i2 = i2, all = true, r = why }) end
	return self:Add({ k = "m", g = g, i = i, g2 = g2, i2 = i2, d = d, r = why })
end
function R:SetBonus(b) return self:Add({ k = "s", b = b }) end
function R:SetPicks(raidKey, n) return self:Add({ k = "p", raid = raidKey, n = n }) end
function R:Won(g, i, raidID) return self:Add({ k = "w", g = g, i = i, e = raidID }) end
function R:Night(raidID, grants)
	local st = self:State()
	return self:Add({ k = "n", e = raidID, b = st and st.bonus or R.DEFAULT_BONUS, g = grants })
end
function R:Undo(id, why)
	local store = self:Get()
	local t = store and store.ledger[id]
	if not t then return nil, "unknown change" end
	if t.k == "x" then return nil, "an undo can't be undone" end
	local st = self:State()
	if st and st.undone[id] then return nil, "already undone" end
	return self:Add({ k = "x", x = id, r = why })
end
