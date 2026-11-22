-- Reserve+ (v0.9.0, not released): soft reserves with bonus points, the
-- guild's TBC system. Plan and the owner's rules:
-- docs/proposals/loot-addon-plan.md.
--
-- Points belong to ONE character and ONE item. Each raid night you reserve
-- a few items (how many is set per raid by officers: 1 by default, e.g. 2
-- in Hyjal, 4 in a big raid); several may go on the same item for a double
-- bonus (still one roll). Every reserved item you didn't get that night
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
--     k = "l"  loot list:   raid = raid key, i = itemID (an item officers added,
--                           or one the officer's addon saw drop; undo removes it)
--     k = "x"  undo:        x = id of the entry undone, r = reason
--
-- Entries never change once made (an undo is a new entry). Every player's
-- game replays them in the same order (time, then id), so everyone gets
-- the same points. Received entries are untrusted: ValidEntry checks the
-- shape, Merge checks against OUR OWN roster that the author is an officer
-- or raid leader (RaidBoard.IsLeadRank).
--
-- Stored per guild in guild.reserves = {
--   ledger = { [id] = entry },
--   picks  = { [raid id] = { [guid] = { i = { itemID, ... }, u = time } } },
--            tonight's reserves, written by each player for themselves
--   locks  = { [raid id] = { by, u, x = true when unlocked, b = { [guid] =
--            "bench" | "offline" }, s = { [guid] = { itemID, ... } } } },
--            written by officers: who was on the bench at the lock, and a
--            copy of everyone's reserves at that moment
-- }
-- Raid ids are the v0.8.0 raid board's events (Core/RaidBoard.lua).
-- Pure parts (tested): ValidEntry, Merge, Replay, PointsOf, ItemsOf,
-- Rank, NightGrants, BenchAtLock, PicksFor, LootList, ValidPick, MergePick,
-- ValidLock, MergeLock, PicksOf, RaidCheck, PruneNights, Count.
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
	p = "Reserves changed", l = "Loot list", x = "Undone" }

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
			local c = 0
			for k2, i in pairs(items) do -- the same item twice = two reserves on it (double bonus)
				c = c + 1
				if c > R.MAX_PICKS or not int(k2) or k2 < 1 or k2 > R.MAX_PICKS or not item(i) then return false, "bad night" end
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
	elseif k == "l" then
		if not str(e.raid, 20) or not item(e.i) then return false, "bad loot item" end
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
	m = { "g", "i", "g2", "i2", "d", "all", "r" }, s = { "b" }, p = { "raid", "n" }, l = { "raid", "i" }, x = { "x", "r" },
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
function R.New() return { ledger = {}, picks = {}, locks = {} } end

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
	local st = { points = {}, bonus = R.DEFAULT_BONUS, picks = {}, loot = {}, undone = undone, lines = {} }
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
			elseif e.k == "l" then
				st.loot[e.raid] = st.loot[e.raid] or {}
				st.loot[e.raid][e.i] = e.id
			end
		end
	end
	return st
end

-- A raid's loot list, from three places, so nobody has to type it in:
--   1. the game's own Encounter Journal, if Forever turns it on for its
--      raids (read on every player's game: R.journal, see ReadJournal);
--   2. the bundled list (Data/Loot.lua, generated by tools/loot.js from
--      warcraft.wiki.gg and checked against Forever's item data);
--   3. items the officer's addon saw drop, or officers added (ledger kind l).
-- Returns a sorted list of item IDs and a set of the ones that came from
-- the guild ({ [itemID] = entry id }).
R.journal = {}  -- [raid key] = { itemID, ... } from the Encounter Journal (this session)
function R.LootList(st, raidKey, journal)
	local seen, out = {}, {}
	for _, i in ipairs((journal or R.journal)[raidKey] or {}) do
		if not seen[i] then seen[i] = true; out[#out + 1] = i end
	end
	local data = SK.Data.LOOT and SK.Data.LOOT[raidKey]
	for _, i in ipairs(data and data.items or {}) do
		if not seen[i] then seen[i] = true; out[#out + 1] = i end
	end
	local added = st and st.loot[raidKey] or {}
	for i in pairs(added) do
		if not seen[i] then seen[i] = true; out[#out + 1] = i end
	end
	table.sort(out)
	return out, added
end

-- What an item looks like (v0.14.1): { name, q (quality), icon (texture),
-- slot, type, listed }. The game names only items its own data holds, and
-- Forever holds raid loot back until the raid opens, so the page showed
-- "item 17068". The game's name, quality and icon win once it knows the
-- item; until then Data/Loot.lua's look (from the item's wiki tooltip,
-- tools/loot.js). Slot and type come only from the list. nil name = not
-- known anywhere (an item learned from a drop on another player's game
-- still loading here).
R.ICON_PATH = "Interface\\Icons\\"
function R.ItemLook(id)
	local data = SK.Data.LOOT_ITEMS and SK.Data.LOOT_ITEMS[id]
	local name = SK.CraftIndex.ItemName(id)
	local look = { listed = data ~= nil, slot = data and data.slot, type = data and data.type }
	if name then
		look.name, look.q, look.icon = name, Compat.ItemQuality(id), Compat.ItemIcon(id)
	end
	if data then
		look.name = look.name or data.name
		if look.q == nil then look.q = data.q end
		-- The game's icon for an item it doesn't know is a question mark: use
		-- the listed one unless the game knows the item.
		if (not name or not look.icon) and data.icon then look.icon = R.ICON_PATH .. data.icon end
	end
	return look
end

-- "Head, Cloth" / "One-Hand Axe" / "Trinket" / nil.
function R.SlotText(look)
	local slot, kind = look and look.slot, look and look.type
	if slot and kind then
		if slot:find("Hand$") then return slot .. " " .. kind end
		return slot .. ", " .. kind
	end
	return slot or kind
end

-- Reserves per player in a raid (1 until officers set it for that raid).
function R.PicksFor(st, raidKey)
	return st and st.picks[raidKey] or 1
end

-- v0.14.0 (owner: "One list for the night"): a night with several
-- instances has one list with all their loot, and the largest of their
-- reserve limits. A night still to be decided: no loot yet, 1 reserve.
function R.EventPicks(st, ev)
	local n
	for _, k in ipairs(SK.RaidBoard.Keys(ev)) do n = math.max(n or 0, R.PicksFor(st, k)) end
	return n or 1
end

function R.EventLoot(st, ev, journal)
	local seen, out = {}, {}
	for _, k in ipairs(SK.RaidBoard.Keys(ev)) do
		for _, i in ipairs((R.LootList(st, k, journal))) do
			if not seen[i] then seen[i] = true; out[#out + 1] = i end
		end
	end
	table.sort(out)
	return out
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
-- they were rolled; picks = { [guid] = { [itemID] = reserves on it (or true = 1) } };
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
			local n = picks[r.guid] and picks[r.guid][itemID]
			local reserved = n == true or (type(n) == "number" and n > 0)
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

-- The end-of-night bonus. picks = { [guid] = { [itemID] = reserves on it
-- (or true = 1) } }: two reserves on one item get the bonus twice (owner,
-- 16 Nov, as in Kerath Raidcheck), still one roll;
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
			for i, n in pairs(set) do
				if won[g] and won[g][i] then
					got[#got + 1] = i
				else
					for _ = 1, (n == true and 1 or n) do items[#items + 1] = i end
				end
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
-- Tonight's reserves and the officer's lock (pure)
---------------------------------------------------------------------------
-- A player's reserves for one raid night, as received. i = list of item
-- IDs (the same one twice = two reserves on it); an empty list = no reserve.
function R.ValidPick(p, now)
	if type(p) ~= "table" then return false, "not a table" end
	if not str(p.e, 80) or not guid(p.g) then return false, "bad id" end
	if type(p.i) ~= "table" then return false, "bad items" end
	local n = 0
	for k, i in pairs(p.i) do
		n = n + 1
		if n > R.MAX_PICKS or not int(k) or k < 1 or k > R.MAX_PICKS or not item(i) then return false, "bad items" end
	end
	if n ~= #p.i then return false, "bad items" end
	if not int(p.u) or p.u > now + R.MAX_FUTURE then return false, "bad time" end
	return true
end

-- ctx = { now, canWrite(guid) -> bool (the sender is that player, or an
-- officer), raidExists(id) -> bool, officer = sender is an officer }.
-- After an officer locks a raid only officers can change its reserves.
-- Newest wins. Returns accepted, why.
function R.MergePick(store, p, ctx)
	local ok, why = R.ValidPick(p, ctx.now)
	if not ok then return false, why end
	if not ctx.canWrite(p.g) then return false, "not their reserve" end
	if not ctx.raidExists(p.e) then return false, "unknown raid" end
	store.picks = store.picks or {}
	local lock = store.locks and store.locks[p.e]
	if lock and not lock.x and p.u > lock.u and not ctx.officer then return false, "locked" end
	local list = store.picks[p.e] or {}
	local have = list[p.g]
	if have and have.u >= p.u then return false, "not newer" end
	if not have and SK.Count(list) >= SK.RaidBoard.MAX_SIGNUPS then return false, "too many reserves" end
	local items = {}
	for k, i in ipairs(p.i) do items[k] = i end
	list[p.g] = { i = items, u = p.u }
	store.picks[p.e] = list
	return true
end

function R.ValidLock(l, now)
	if type(l) ~= "table" then return false, "not a table" end
	if not str(l.e, 80) or not guid(l.by) then return false, "bad id" end
	if not int(l.u) or l.u > now + R.MAX_FUTURE then return false, "bad time" end
	if l.x ~= nil and l.x ~= true then return false, "bad unlock" end
	local n = 0
	for g, v in pairs(type(l.b) == "table" and l.b or {}) do
		n = n + 1
		if n > SK.RaidBoard.MAX_SIGNUPS or not guid(g) or (v ~= "bench" and v ~= "offline") then return false, "bad bench" end
	end
	n = 0
	for g, items in pairs(type(l.s) == "table" and l.s or {}) do
		n = n + 1
		if n > SK.RaidBoard.MAX_SIGNUPS or not guid(g) or type(items) ~= "table" then return false, "bad copy" end
		local c = 0
		for k, i in pairs(items) do
			c = c + 1
			if c > R.MAX_PICKS or not int(k) or k < 1 or k > R.MAX_PICKS or not item(i) then return false, "bad copy" end
		end
	end
	if (l.b ~= nil and type(l.b) ~= "table") or (l.s ~= nil and type(l.s) ~= "table") then return false, "bad lock" end
	return true
end

-- isLead(guid) -> bool for the SENDER (and l.by). Newest wins.
function R.MergeLock(store, l, now, isLead, raidExists)
	local ok, why = R.ValidLock(l, now)
	if not ok then return false, why end
	if not isLead(l.by) then return false, "not an officer or raid leader" end
	if not raidExists(l.e) then return false, "unknown raid" end
	store.locks = store.locks or {}
	local have = store.locks[l.e]
	if have and have.u >= l.u then return false, "not newer" end
	local c = { e = l.e, by = l.by, u = l.u, x = l.x, b = {}, s = {} }
	for g, v in pairs(l.b or {}) do c.b[g] = v end
	for g, items in pairs(l.s or {}) do
		local t = {}
		for k, i in ipairs(items) do t[k] = i end
		c.s[g] = t
	end
	store.locks[l.e] = c
	return true
end

-- Tonight's reserves as { [guid] = { [itemID] = count } }: the copy taken
-- at the lock when the raid is locked, else the live picks. `limit` (the
-- raid's reserves per player) keeps only the first `limit` of each.
function R.PicksOf(store, raidID, limit)
	local lock = store.locks and store.locks[raidID]
	local src = {}
	if lock and not lock.x then
		for g, items in pairs(lock.s or {}) do src[g] = items end
	else
		for g, p in pairs(store.picks and store.picks[raidID] or {}) do src[g] = p.i end
	end
	local out = {}
	for g, items in pairs(src) do
		local set, n = {}, 0
		for _, i in ipairs(items) do
			if limit and n >= limit then break end
			n = n + 1
			set[i] = (set[i] or 0) + 1
		end
		if n > 0 then out[g] = set end
	end
	return out
end

-- Who reserved one item: { { guid, count } }, most reserves first.
function R.ReservedBy(picks, itemID)
	local out = {}
	for g, set in pairs(picks) do
		if set[itemID] then out[#out + 1] = { guid = g, count = set[itemID] } end
	end
	table.sort(out, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		return a.guid < b.guid
	end)
	return out
end

-- Raid check (as in Kerath Raidcheck): reservers who aren't in the raid,
-- and raid members without a reserve. inRaid = { [guid] = true }.
function R.RaidCheck(picks, inRaid)
	local missing, noReserve = {}, {}
	for g in pairs(picks) do
		if not inRaid[g] then missing[#missing + 1] = g end
	end
	for g in pairs(inRaid) do
		if not picks[g] then noReserve[#noReserve + 1] = g end
	end
	table.sort(missing)
	table.sort(noReserve)
	return missing, noReserve
end

-- Reserves and locks of raids the raid board no longer holds (it deletes
-- raids a week after they start). Returns how many raids were dropped.
function R.PruneNights(store, raidExists)
	local n = 0
	for id in pairs(store.picks or {}) do
		if not raidExists(id) then store.picks[id] = nil; n = n + 1 end
	end
	for id in pairs(store.locks or {}) do
		if not raidExists(id) then store.locks[id] = nil end
	end
	return n
end

---------------------------------------------------------------------------
-- The stored history and local actions (officers and raid leaders)
---------------------------------------------------------------------------
function R:Get(guild)
	guild = guild or SK.DBM:Guild()
	if not guild then return nil end
	guild.reserves = guild.reserves or R.New()
	guild.reserves.ledger = guild.reserves.ledger or {}
	guild.reserves.picks = guild.reserves.picks or {}
	guild.reserves.locks = guild.reserves.locks or {}
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
function R:AddLoot(raidKey, itemID) return self:Add({ k = "l", raid = raidKey, i = itemID }) end

local function raidExists(id)
	local board = SK.RaidBoard:Get()
	return board ~= nil and board.events[id] ~= nil
end
R.RaidExists = raidExists

-- The raid a night belongs to (its raid board event), or nil.
function R.Event(raidID)
	local board = SK.RaidBoard:Get()
	return board and board.events[raidID]
end

-- My reserves for a raid night: a list of item IDs (may be empty).
function R:MyPicks(raidID)
	local store, g = self:Get(), me()
	local p = store and g and store.picks[raidID] and store.picks[raidID][g]
	return p and p.i or {}
end

-- Sets my reserves for a raid night. items = list of item IDs (the same one
-- twice = two reserves on it). Returns true, or nil and why.
function R:SetMyPicks(raidID, items)
	local store, g, now = self:Get(), me(), Compat.Now()
	local ev = R.Event(raidID)
	if not store or not g or not ev or ev.x then return nil, "unknown raid" end
	local limit = R.EventPicks(self:State(), ev)
	if #items > limit then return nil, "this raid allows " .. limit .. (limit == 1 and " reserve" or " reserves") end
	local lock = store.locks[raidID]
	local officer = canLead(g)
	if lock and not lock.x and not officer then return nil, "reserves are locked" end
	local have = store.picks[raidID] and store.picks[raidID][g]
	local p = { e = raidID, g = g, i = items, u = math.max(now, have and have.u + 1 or 0) }
	local ok, why = R.MergePick(store, p, { now = now, canWrite = function() return true end,
		raidExists = raidExists, officer = officer })
	if not ok then return nil, why end
	SK:Fire("RESERVES_UPDATED")
	if SK.ReserveSync then SK.ReserveSync:QueuePick(raidID, g) end
	return true
end

-- Officers: lock (or unlock) a raid night's reserves. The lock remembers
-- who on the bench (signed up, not in the raid group) was online, and a
-- copy of everyone's reserves. inRaid/online: guid -> bool.
function R:Lock(raidID, unlock, inRaid, online)
	local store, by, now = self:Get(), me(), Compat.Now()
	if not store or not by then return nil, "no guild" end
	if not canLead(by) then return nil, "only officers and raid leaders can lock reserves" end
	if not raidExists(raidID) then return nil, "unknown raid" end
	local have = store.locks[raidID]
	local l = { e = raidID, by = by, u = math.max(now, have and have.u + 1 or 0), b = {}, s = {} }
	if unlock then
		l.x = true
	else
		local picks = store.picks[raidID] or {}
		for g, p in pairs(picks) do
			if #p.i > 0 then l.s[g] = p.i end
		end
		-- Bench: signed up (or reserved), not in the raid group.
		local board = SK.RaidBoard:Get()
		local signed = {}
		for g, su in pairs(board and board.signups[raidID] or {}) do
			if su.s == "y" or su.s == "t" then signed[g] = true end
		end
		for g in pairs(l.s) do signed[g] = true end
		for g, state in pairs(R.BenchAtLock(signed, inRaid, online)) do l.b[g] = state end
	end
	local ok, why = R.MergeLock(store, l, now, canLead, raidExists)
	if not ok then return nil, why end
	SK:Fire("RESERVES_UPDATED")
	if SK.ReserveSync then SK.ReserveSync:QueueLock(raidID) end
	return store.locks[raidID]
end

-- Reads the Encounter Journal's loot for our raids (once per session, and
-- again on request). Never in combat.
function R:ReadJournal()
	if Compat.InCombat() then return end
	local names = {}
	for _, raid in ipairs(SK.Data.ShownAttunements()) do names[raid.key] = raid.name end
	local found, seen = Compat.JournalRaidLoot(names)
	R.journalSeen = seen
	for key, list in pairs(found) do
		if #list > 0 then R.journal[key] = list end
	end
	if next(found) then SK:Fire("RESERVES_UPDATED") end
end

function R:OnLogin()
	SK.After(35, function()
		local store = self:Get()
		if store then R.PruneNights(store, raidExists) end
		R:ReadJournal()
	end)
end
