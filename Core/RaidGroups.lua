-- Raid groups (v0.11.0, "split roster"; idea from OXM, our own build):
-- officers put signed-up players into the raid's groups of five, and mark
-- them late, leaving early or absent. Everyone sees it.
--
-- Stored next to the raid board: board.slots[id][guid] = { n, m, u, by }
--   n   group 1..Groups(raid) (0 = not in a group)
--   m   mark: "l" late, "e" leaving early, "a" absent, "" none
--   u   last change, by = the officer
-- In a group always means In (board.places, v0.10.0); the Bench and the
-- Available list are places "b" and undecided. Shared in RB as `gs`
-- (Sync/RaidSync.lua); older versions ignore it.
--
-- Pure parts (tested): Groups, ValidSlot, MergeSlot, SlotOf, Layout.
local _, SK = ...

local RG = SK:NewModule("RaidGroups")
local Compat = SK.Compat

RG.SIZE = 5               -- players per group
RG.MAX_GROUPS = 8
RG.MARK_NAME = { l = "Late", e = "Leaving early", a = "Absent" }
RG.MARK_SHORT = { l = "late", e = "early", a = "absent" }
RG.NEXT_MARK = { [""] = "l", l = "e", e = "a", a = "" }

local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
local function str(v, max) return type(v) == "string" and #v > 0 and #v <= max end

-- Groups for a raid: its size / 5 (Barrow Deeps 2, Hyjal Summit 4, Onyxia 8).
function RG.Groups(raidKey)
	local raid = SK.RaidBoard.Raid(raidKey)
	local n = raid and raid.size and math.floor(raid.size / RG.SIZE) or RG.MAX_GROUPS
	return math.max(1, math.min(RG.MAX_GROUPS, n))
end

function RG.ValidSlot(s, now)
	if type(s) ~= "table" then return false, "not a table" end
	if not str(s.e, 80) or not str(s.g, 64) or not str(s.by, 64) then return false, "bad id" end
	if type(s.n) ~= "number" or s.n ~= math.floor(s.n) or s.n < 0 or s.n > RG.MAX_GROUPS then return false, "bad group" end
	if s.m ~= "" and not RG.MARK_NAME[s.m] then return false, "bad mark" end
	if not finite(s.u) or s.u > now + SK.RaidBoard.MAX_FUTURE then return false, "bad time" end
	return true
end

function RG.MergeSlot(board, s, now, isMember, isLead)
	local ok, why = RG.ValidSlot(s, now)
	if not ok then return false, why end
	if not isLead(s.by) then return false, "not an officer or raid leader" end
	if not isMember(s.g) then return false, "not a member" end
	if not board.events[s.e] then return false, "unknown raid" end
	board.slots = board.slots or {}
	local list = board.slots[s.e]
	if not list then
		list = {}
		board.slots[s.e] = list
	end
	local have = list[s.g]
	if have and have.u >= s.u then return false, "not newer" end
	if not have and SK.Count(list) >= SK.RaidBoard.MAX_SIGNUPS then return false, "too many" end
	list[s.g] = { n = s.n, m = s.m, u = s.u, by = s.by }
	return true
end

-- group (0 = none), mark ("" = none).
function RG.SlotOf(board, id, guid)
	local s = board.slots and board.slots[id] and board.slots[id][guid]
	if not s then return 0, "" end
	return s.n, s.m
end

-- The page's layout from the line-up rows (Board.LineUp): groups[1..n] =
-- rows (In with that group), unplaced = In without a group, bench, and
-- available = signed up or tentative, not yet In or Bench. Rows get
-- .group and .mark. A group over five (two officers at once) keeps all.
function RG.Layout(board, ev, rows)
	local count = RG.Groups(ev.raid)
	local out = { count = count, groups = {}, unplaced = {}, bench = {}, available = {}, declined = {},
		marks = { l = 0, e = 0, a = 0 } }
	for i = 1, count do out.groups[i] = {} end
	for _, r in ipairs(rows) do
		r.group, r.mark = RG.SlotOf(board, ev.id, r.guid)
		if r.mark ~= "" then out.marks[r.mark] = out.marks[r.mark] + 1 end
		if r.place == "i" then
			local g = out.groups[r.group]
			table.insert(g or out.unplaced, r)
		elseif r.place == "b" then
			table.insert(out.bench, r)
		elseif r.status == "y" or r.status == "t" then
			table.insert(out.available, r)
		else
			table.insert(out.declined, r)
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Officers' moves
---------------------------------------------------------------------------
local function setSlot(board, id, guid, n, m, officer, now)
	board.slots = board.slots or {}
	local list = board.slots[id] or {}
	board.slots[id] = list
	local have = list[guid]
	list[guid] = { n = n, m = m or (have and have.m) or "", u = math.max(now, have and have.u + 1 or 0), by = officer }
	return "G:" .. id .. "|" .. guid
end

-- target = { kind = "group", n = 1..8 } | { kind = "bench" } | { kind = "available" };
-- with swap = guid, the player already in that spot trades places.
-- Returns ok, why.
function RG:Move(id, guid, target, swap)
	local B = SK.RaidBoard
	local board, officer, now = B:Get(), Compat.PlayerGUID(), Compat.Now()
	local ev = board and board.events[id]
	if not ev or ev.x then return false, "unknown raid" end
	if not B.CanLead(officer) then return false, "only officers and raid leaders can arrange the raid" end
	local fromN = RG.SlotOf(board, id, guid)
	local fromPlace = B.PlaceOf(board, id, guid)
	if target.kind == "group" then
		if target.n < 1 or target.n > RG.Groups(ev.raid) then return false, "no such group" end
		if not swap then
			local inGroup = 0
			for g, s in pairs(board.slots and board.slots[id] or {}) do
				if g ~= guid and s.n == target.n and B.PlaceOf(board, id, g) == "i" then inGroup = inGroup + 1 end
			end
			if inGroup >= RG.SIZE then return false, "group " .. target.n .. " is full" end
		end
	end
	local keys = {}
	local function place(g, v) if B.PlaceOf(board, id, g) ~= (v ~= "-" and v or nil) then B:SetPlace(id, g, v) end end
	if target.kind == "group" then
		place(guid, "i")
		keys[#keys + 1] = setSlot(board, id, guid, target.n, nil, officer, now)
		if swap and swap ~= guid then
			-- The other player goes where this one came from.
			if fromPlace == "i" and fromN > 0 then
				keys[#keys + 1] = setSlot(board, id, swap, fromN, nil, officer, now)
			else
				place(swap, fromPlace or "-")
				keys[#keys + 1] = setSlot(board, id, swap, 0, nil, officer, now)
			end
		end
	elseif target.kind == "bench" then
		place(guid, "b")
		keys[#keys + 1] = setSlot(board, id, guid, 0, nil, officer, now)
	else
		place(guid, "-")
		keys[#keys + 1] = setSlot(board, id, guid, 0, nil, officer, now)
	end
	SK:Fire("RAIDS_UPDATED")
	if SK.RaidSync then SK.RaidSync:Queue(keys) end
	return true
end

-- Next mark in turn: none, late, leaving early, absent.
function RG:CycleMark(id, guid)
	local B = SK.RaidBoard
	local board, officer, now = B:Get(), Compat.PlayerGUID(), Compat.Now()
	if not board or not board.events[id] then return false, "unknown raid" end
	if not B.CanLead(officer) then return false, "only officers and raid leaders can mark players" end
	local n, m = RG.SlotOf(board, id, guid)
	local key = setSlot(board, id, guid, n, RG.NEXT_MARK[m] or "", officer, now)
	SK:Fire("RAIDS_UPDATED")
	if SK.RaidSync then SK.RaidSync:Queue({ key }) end
	return true
end
