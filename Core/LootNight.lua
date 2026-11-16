-- Reserve+ loot night (v0.9.0): what the loot officer's addon does during
-- a raid. Only with the officer tools on (/sr officer, Officer or Raid
-- Leader rank). Local to the officer's game (SK.DB.lootNight); what matters
-- for everyone (wins, the end-of-night bonus, learned loot) goes into the
-- shared points history through Core/Reserves.lua.
--
--   night = { e = raid id, raid = raid key, started,
--             kills  = { { id, name, at } },          boss kills (ENCOUNTER_END)
--             drops  = { { i = itemID, at, k = kill index } }, seen in loot windows
--             rolls  = { [itemID] = { { guid, name, roll, min, max, at } } },
--             current = itemID being rolled for,
--             won    = { [guid] = { [itemID] = true } },
--             awards = { { i, g, at, id = history entry } },
--             seen   = { [guid] = true },           in the raid group at some point
--             out    = { [guid] = true },           left out of the bonus by the officer
--             saved  = history entry id once the bonus is saved }
--
-- Pure parts (tested): Tonight, MatchName, AddRoll, AddDrops, Where,
-- EndRows, PostText, AwardText.
local _, SK = ...

local LN = SK:NewModule("LootNight")
local Compat = SK.Compat
local R, Board = SK.Reserves, SK.RaidBoard

LN.BEFORE = 3 * 3600       -- a raid counts as "tonight" from 3 h before its start
LN.AFTER = 8 * 3600        -- until 8 h after
LN.MIN_QUALITY = 3         -- rare and better drops are listed and learned
LN.KEEP = 10               -- nights kept on this computer

---------------------------------------------------------------------------
-- Pure helpers
---------------------------------------------------------------------------
-- Tonight's raid: not cancelled, starting within BEFORE..AFTER of now; the
-- one closest to its start wins.
function LN.Tonight(board, now)
	local best, bestD
	for _, e in pairs(board and board.events or {}) do
		if not e.x and e.at - LN.BEFORE <= now and now <= e.at + LN.AFTER then
			local d = math.abs(now - e.at)
			if not bestD or d < bestD or (d == bestD and e.id < best.id) then best, bestD = e, d end
		end
	end
	return best
end

-- A name from chat ("First Surname", or just "First") -> a raid member's
-- GUID. members = { { name, guid } }. Exact name first, then a first name
-- that only one member has.
function LN.MatchName(name, members)
	if type(name) ~= "string" then return nil end
	local lower = name:lower()
	for _, m in ipairs(members) do
		if m.guid and m.name and m.name:lower() == lower then return m.guid end
	end
	local first = lower:match("^(%S+)")
	local found
	for _, m in ipairs(members) do
		if m.guid and m.name and m.name:lower():match("^(%S+)") == first then
			if found then return nil end
			found = m.guid
		end
	end
	return found
end

-- Records a roll for the item being rolled for. Returns true if kept.
function LN.AddRoll(night, guid, name, roll, lo, hi, at)
	if not night.current or not guid then return false end
	night.rolls[night.current] = night.rolls[night.current] or {}
	local list = night.rolls[night.current]
	if #list >= 80 then return false end
	list[#list + 1] = { guid = guid, name = name, roll = roll, min = lo, max = hi, at = at }
	return true
end

-- Adds the items of one loot window. The same corpse can be opened many
-- times, so per kill only the most copies seen at once are kept.
-- items = { { itemID, quality } }. Returns the item IDs that are new drops.
function LN.AddDrops(night, items, at)
	local k = #night.kills
	local inWindow, have = {}, {}
	for _, it in ipairs(items) do
		if (it.quality or 0) >= LN.MIN_QUALITY then inWindow[it.itemID] = (inWindow[it.itemID] or 0) + 1 end
	end
	for _, d in ipairs(night.drops) do
		if d.k == k then have[d.i] = (have[d.i] or 0) + 1 end
	end
	local new = {}
	for i, n in pairs(inWindow) do
		for _ = (have[i] or 0) + 1, n do
			night.drops[#night.drops + 1] = { i = i, at = at, k = k }
			new[#new + 1] = i
		end
	end
	table.sort(new)
	return new
end

-- Where someone was tonight, for NightGrants: "raid" if seen in the raid
-- group, else what the lock recorded ("bench" / "offline"), else nil.
function LN.Where(night, lock)
	return function(g)
		if night.seen[g] then return "raid" end
		return lock and not lock.x and lock.b and lock.b[g] or nil
	end
end

-- The end-of-night list for the officer's check: one row per reserver,
-- { guid, items, result = "bonus" | "won" | "nothing" | "out", why }.
-- grants exclude anyone the officer left out.
function LN.EndRows(night, picks, lock)
	local grants, skipped, wonItems = R.NightGrants(picks, LN.Where(night, lock), night.won)
	local rows = {}
	for g, set in pairs(picks) do
		local items = {}
		for i, n in pairs(set) do for _ = 1, n do items[#items + 1] = i end end
		table.sort(items)
		local row = { guid = g, items = items, won = wonItems[g] }
		if grants[g] then
			row.result = night.out[g] and "out" or "bonus"
			row.bonusItems = grants[g]
			row.why = night.seen[g] and "In the raid" or "On the bench, online at the lock"
		elseif skipped[g] == "won it" then
			row.result, row.why = "won", "Won it: points go to 0"
		else
			row.result = "nothing"
			row.why = skipped[g] == "not there" and "Not there" or "On the bench, offline at the lock"
		end
		rows[#rows + 1] = row
	end
	local final = {}
	for g, items in pairs(grants) do
		if not night.out[g] then final[g] = items end
	end
	return rows, final
end

-- Text for raid chat (typed into the chat box for the officer to send).
function LN.PostText(name, reservers)
	if #reservers == 0 then return string.format("%s: nobody reserved it. /roll for main spec.", name) end
	local parts = {}
	for _, r in ipairs(reservers) do
		parts[#parts + 1] = r.name .. (r.points and r.points ~= 0 and (" (" .. r.points .. ")") or "")
	end
	return string.format("%s: reserved by %s. Reservers /roll now (roll + points wins).", name, table.concat(parts, ", "))
end

function LN.AwardText(name, winner, total)
	return string.format("%s goes to %s%s.", name, winner, total and (" (" .. total .. ")") or "")
end

---------------------------------------------------------------------------
-- The stored nights and actions (officer)
---------------------------------------------------------------------------
local function store()
	SK.DB.lootNight = SK.DB.lootNight or {}
	return SK.DB.lootNight
end

function LN.New(ev, now)
	return { e = ev.id, raid = ev.raid, started = now, kills = {}, drops = {}, rolls = {}, won = {},
		awards = {}, seen = {}, out = {} }
end

-- The night for a raid id; create = make it if missing (officers only).
function LN:Night(raidID, create)
	local nights = store()
	local n = nights[raidID]
	if not n and create then
		local ev = R.Event(raidID)
		if not ev then return nil end
		n = LN.New(ev, Compat.Now())
		nights[raidID] = n
		-- Keep the newest few.
		local list = {}
		for id, x in pairs(nights) do list[#list + 1] = { id = id, at = x.started or 0 } end
		table.sort(list, function(a, b) return a.at > b.at end)
		for i = LN.KEEP + 1, #list do nights[list[i].id] = nil end
	end
	return n
end

function LN.Active()
	return Board.OfficerView() and Compat.InRaidGroup()
end

-- The raid running now (for the officer), and its night.
function LN:Current(create)
	local ev = LN.Tonight(Board:Get(), Compat.Now())
	if not ev then return nil end
	return ev, self:Night(ev.id, create)
end

-- Everyone in the raid group counts as "seen" tonight.
function LN:NoteRaid(night)
	for _, m in ipairs(Compat.RaidMembers()) do
		if m.guid then night.seen[m.guid] = true end
	end
end

function LN:Changed()
	SK:Debounce("lootnightui", 0.5, function() SK:Fire("LOOTNIGHT_UPDATED") end)
end

function LN:OnRoll(msg)
	if not LN.Active() then return end
	local name, roll, lo, hi = Compat.ParseRoll(msg)
	if not name then return end
	local _, night = self:Current(false)
	if not night or not night.current then return end
	local guid = LN.MatchName(name, Compat.RaidMembers())
	if LN.AddRoll(night, guid, name, roll, lo, hi, Compat.Now()) then self:Changed() end
end

function LN:OnLootOpened()
	if not LN.Active() then return end
	local ev, night = self:Current(true)
	if not night then return end
	self:NoteRaid(night)
	local new = LN.AddDrops(night, Compat.LootItems(), Compat.Now())
	if #new > 0 then
		-- Learn items the raid's list doesn't have yet (shared with everyone).
		local list = {}
		for _, i in ipairs(R.LootList(R:State(), ev.raid)) do list[i] = true end
		for _, i in ipairs(new) do
			if not list[i] then R:AddLoot(ev.raid, i); list[i] = true end
		end
		if not night.current then night.current = new[1] end
		self:Changed()
	end
end

function LN:OnEncounterEnd(id, name, success)
	if not LN.Active() or not (success == 1 or success == true) then return end
	local _, night = self:Current(true)
	if not night then return end
	night.kills[#night.kills + 1] = { id = id, name = name, at = Compat.Now() }
	self:NoteRaid(night)
	self:Changed()
end

-- Officer picks the item to roll for (also an item added by hand).
function LN:Select(raidID, itemID)
	local night = self:Night(raidID, true)
	if not night then return end
	night.current = itemID
	self:Changed()
end

-- Adds an item by hand (it dropped, but the loot window wasn't read).
function LN:AddItem(raidID, itemID)
	local night = self:Night(raidID, true)
	if not night or not R.IsItem(itemID) then return end
	night.drops[#night.drops + 1] = { i = itemID, at = Compat.Now(), k = #night.kills, hand = true }
	night.current = itemID
	self:Changed()
end

-- Gives an item: records the win (points to 0) for everyone to see.
function LN:Award(raidID, itemID, guid)
	local night = self:Night(raidID, true)
	if not night then return nil, "no raid" end
	local e, why = R:Won(guid, itemID, raidID)
	if not e then return nil, why end
	night.won[guid] = night.won[guid] or {}
	night.won[guid][itemID] = true
	night.awards[#night.awards + 1] = { i = itemID, g = guid, at = Compat.Now(), id = e.id }
	night.seen[guid] = true
	self:NoteRaid(night)
	self:Changed()
	return e
end

function LN:ToggleOut(raidID, guid)
	local night = self:Night(raidID, true)
	if not night then return end
	night.out[guid] = not night.out[guid] or nil
	self:Changed()
end

-- Saves the end-of-night bonus once. Returns the history entry or nil, why.
function LN:SaveNight(raidID)
	local night = self:Night(raidID, false)
	if not night then return nil, "no loot night for this raid" end
	if night.saved then return nil, "already saved" end
	if LN.Active() then self:NoteRaid(night) end
	local st, rs = R:State(), R:Get()
	local ev = R.Event(raidID)
	local picks = R.PicksOf(rs, raidID, ev and R.PicksFor(st, ev.raid))
	local _, grants = LN.EndRows(night, picks, rs.locks[raidID])
	if not next(grants) then return nil, "nobody gets a bonus" end
	local e, why = R:Night(raidID, grants)
	if not e then return nil, why end
	night.saved = e.id
	self:Changed()
	return e
end

SK:RegisterEvent("CHAT_MSG_SYSTEM", function(_, msg) LN:OnRoll(msg) end)
SK:RegisterEvent("LOOT_OPENED", function() LN:OnLootOpened() end)
SK:RegisterEvent("ENCOUNTER_END", function(_, id, name, _, _, success) LN:OnEncounterEnd(id, name, success) end)
