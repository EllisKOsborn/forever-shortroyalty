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

---------------------------------------------------------------------------
-- Invite & arrange (v0.11.0): an officer leading the raid sets the game's
-- group up from the plan. One step per button press, because the game only
-- lets a party become a raid from a press: invite the first four, make it
-- a raid, invite the rest; then players are moved into their groups one
-- move at a time as the game confirms each (GROUP_ROSTER_UPDATE).
---------------------------------------------------------------------------
RG.ARRANGE_FOR = 30   -- seconds an arrangement may take
RG.ARRANGE_MOVES = 80 -- moves at most

-- want = { [guid] = group } for everyone In with a group. Pure.
function RG.Want(L)
	local want = {}
	for n, list in ipairs(L.groups) do
		for _, r in ipairs(list) do want[r.guid] = n end
	end
	return want
end

-- Who to invite: In (with or without a group), online, not already in the
-- group, not me; group order first. Pure. inGroup/online = { [guid] = true }.
function RG.InvitePlan(L, inGroup, online, me)
	local out = {}
	local function add(r) if r.guid ~= me and online[r.guid] and not inGroup[r.guid] then out[#out + 1] = r end end
	for _, list in ipairs(L.groups) do for _, r in ipairs(list) do add(r) end end
	for _, r in ipairs(L.unplaced) do add(r) end
	return out
end

-- The next move to bring the raid closer to the plan, or nil when done.
-- members = { { index, guid, subgroup } }. Pure.
function RG.NextMove(members, want)
	local count = {}
	for _, m in ipairs(members) do if m.subgroup then count[m.subgroup] = (count[m.subgroup] or 0) + 1 end end
	for _, m in ipairs(members) do
		local g = m.guid and want[m.guid]
		if g and m.subgroup ~= g then
			if (count[g] or 0) < RG.SIZE then return { op = "set", index = m.index, group = g } end
			for _, o in ipairs(members) do
				if o.subgroup == g and want[o.guid or ""] ~= g then return { op = "swap", a = m.index, b = o.index } end
			end
		end
	end
	return nil
end

-- The raid's members with GUIDs (by name when the game hides them).
function RG.Members()
	local out = {}
	for _, m in ipairs(Compat.RaidMembers()) do
		m.guid = m.guid or (m.name and SK.Identity:ResolveSender(m.name))
		out[#out + 1] = m
	end
	return out
end

function RG:Plan(id)
	local B = SK.RaidBoard
	local board = B:Get()
	local ev = board and board.events[id]
	if not ev then return nil end
	return RG.Layout(board, ev, B.LineUp(board, ev, B.Ctx()))
end

-- The button. Returns the sentence to show.
function RG:Setup(id)
	local B = SK.RaidBoard
	if not B.CanLead(Compat.PlayerGUID()) then return "Only officers and raid leaders can set the raid up." end
	if Compat.InCombat() then return "Not in combat." end
	local L = self:Plan(id)
	if not L then return "Pick a raid first." end
	local state = Compat.GroupState()
	if state ~= "none" and not Compat.IsLeaderOrAssist() then return "You need to lead the group (or be an assistant)." end
	local inGroup, online = {}, {}
	if state == "raid" then
		for _, m in ipairs(RG.Members()) do if m.guid then inGroup[m.guid] = true end end
	else
		for _, name in ipairs(Compat.PartyNames()) do
			local g = SK.Identity:ResolveSender(name)
			if g then inGroup[g] = true end
		end
	end
	local guild = SK.DBM:Guild()
	for guid, m in pairs(guild and guild.members or {}) do if m.online and not m.leftAt then online[guid] = true end end
	local todo = RG.InvitePlan(L, inGroup, online, Compat.PlayerGUID())
	local partySize = state == "none" and 1 or (#Compat.PartyNames() + 1)
	if state == "party" and partySize + #todo > RG.SIZE then
		local ok = Compat.ConvertToRaid()
		return ok and "Made it a raid. Press again to invite the rest and arrange the groups."
			or "Couldn't make it a raid. Use the game's Convert to Raid, then press again."
	end
	local room = state == "raid" and (40 - #RG.Members()) or (RG.SIZE - partySize)
	local invited = 0
	for i = 1, math.min(#todo, room) do
		if Compat.InviteUnit(todo[i].name) then invited = invited + 1 end
	end
	if state == "none" then
		return invited > 0 and ("Invited " .. invited .. ". When one has joined, press again.") or "Nobody In is online to invite."
	end
	if state == "party" then return "Invited " .. invited .. "." end
	self:StartArrange(id)
	return (invited > 0 and ("Invited " .. invited .. ". ") or "") .. "Arranging the groups…"
end

function RG:StartArrange(id)
	self.arranging = { id = id, moves = 0, until_ = Compat.Now() + RG.ARRANGE_FOR }
	self:ArrangeStep()
end

-- One move; the next comes when the game reports the change.
function RG:ArrangeStep()
	local a = self.arranging
	if not a then return end
	if Compat.InCombat() or Compat.Now() > a.until_ or a.moves >= RG.ARRANGE_MOVES then
		self.arranging = nil
		return SK:Print("Stopped arranging the groups (combat or it took too long). Press Invite & arrange again.")
	end
	local L = self:Plan(a.id)
	local op = L and RG.NextMove(RG.Members(), RG.Want(L))
	if not op then
		self.arranging = nil
		SK:Fire("RAIDS_UPDATED")
		return SK:Print("Raid groups arranged.")
	end
	a.moves = a.moves + 1
	if op.op == "set" then Compat.SetRaidSubgroup(op.index, op.group) else Compat.SwapRaidSubgroup(op.a, op.b) end
end

function RG:OnLogin()
	SK:RegisterEvent("GROUP_ROSTER_UPDATE", function()
		if self.arranging then SK:Debounce("arrange", 0.3, function() self:ArrangeStep() end) end
	end)
end

---------------------------------------------------------------------------
-- Auto-fill (v0.11.0): fill the empty spots from the sign-ups. Keeps what
-- officers already placed; skips players marked away and a second
-- character of the same player; signed up before tentative, then higher
-- attendance (officers' records), then item level. Aims for TARGETS tanks
-- and healers; healers one per group first, tanks in the first groups,
-- then melee, ranged and casters together. Whoever doesn't fit: Bench.
---------------------------------------------------------------------------
RG.TARGETS = { [10] = { TANK = 2, HEALER = 3 }, [20] = { TANK = 2, HEALER = 5 }, [40] = { TANK = 4, HEALER = 10 } }
local MELEE = { WARRIOR = true, ROGUE = true, PALADIN = true }
local RANGED = { HUNTER = true }
local HYBRID_MELEE = { Feral = true, ["Feral Combat"] = true, Enhancement = true }

-- "melee" | "ranged" | "caster" for a DPS row. Pure.
function RG.DpsKind(r)
	if MELEE[r.class or ""] then return "melee" end
	if RANGED[r.class or ""] then return "ranged" end
	if (r.class == "DRUID" or r.class == "SHAMAN") and HYBRID_MELEE[r.tree or ""] then return "melee" end
	return "caster"
end

-- L = Layout(…); pct = { [guid] = attendance % }.
-- Returns moves = { { guid, kind = "group", n } | { guid, kind = "bench" } }. Pure.
-- plan (v0.13.0, optional): { [guid] = { status = "r" | "b" | nil, tiers = { TANK = "m" | "b" } } }
-- from the roster planner: Raiders before Backups, and an officer-set main
-- for the role they signed up as before a backup.
local PLAN_STATUS = { r = 1, b = 3 }
local PLAN_TIER = { m = 1, b = 2 }
function RG.AutoFill(L, raidKey, pct, plan)
	local raid = SK.RaidBoard.Raid(raidKey)
	local size = raid and raid.size or L.count * RG.SIZE
	local target = RG.TARGETS[size] or { TANK = math.max(1, math.floor(size / 10)), HEALER = math.ceil(size / 4) }
	pct = pct or {}
	-- What's already decided.
	local filled, have = {}, { TANK = 0, HEALER = 0, DPS = 0 }
	for n = 1, L.count do
		filled[n] = #L.groups[n]
		for _, r in ipairs(L.groups[n]) do have[r.role or "DPS"] = (have[r.role or "DPS"] or 0) + 1 end
	end
	local moves, free = {}, 0
	for n = 1, L.count do free = free + (RG.SIZE - filled[n]) end
	-- Candidates: In without a group first (officers chose them), then Available.
	local pool = {}
	local function consider(r, chosen)
		if r.away or r.duplicateOf then return end -- away, or the same player's second character
		r.chosen = chosen
		pool[#pool + 1] = r
	end
	for _, r in ipairs(L.unplaced) do consider(r, true) end
	for _, r in ipairs(L.available) do consider(r, false) end
	plan = plan or {}
	local function planRank(r)
		local p = plan[r.guid]
		if not p then return 2, 3 end
		return PLAN_STATUS[p.status or ""] or 2, PLAN_TIER[(p.tiers or {})[r.role or "DPS"] or ""] or 3
	end
	table.sort(pool, function(a, b)
		if a.chosen ~= b.chosen then return a.chosen end
		if a.status ~= b.status then return a.status == "y" end
		local sa, ta = planRank(a)
		local sb, tb = planRank(b)
		if sa ~= sb then return sa < sb end
		if ta ~= tb then return ta < tb end
		local pa, pb = pct[a.guid] or -1, pct[b.guid] or -1
		if pa ~= pb then return pa > pb end
		if (a.ilvl or 0) ~= (b.ilvl or 0) then return (a.ilvl or 0) > (b.ilvl or 0) end
		return a.name:lower() < b.name:lower()
	end)
	-- Pick by role: chosen always; tanks and healers up to their targets; then DPS.
	local picked, bench = {}, {}
	local function take(r)
		if free <= 0 then bench[#bench + 1] = r return end
		picked[#picked + 1] = r
		free = free - 1
		local role = r.role or "DPS"
		have[role] = (have[role] or 0) + 1
	end
	local rest = {}
	for _, r in ipairs(pool) do if r.chosen then take(r) else rest[#rest + 1] = r end end
	for _, role in ipairs({ "TANK", "HEALER" }) do
		local left = {}
		for _, r in ipairs(rest) do
			if (r.role or "DPS") == role and have[role] < target[role] and free > 0 then take(r) else left[#left + 1] = r end
		end
		rest = left
	end
	for _, r in ipairs(rest) do
		if (r.role or "DPS") ~= "TANK" and (r.role or "DPS") ~= "HEALER" then take(r) else bench[#bench + 1] = r end
	end
	-- Groups: healers round-robin, tanks from group 1, then DPS by kind.
	local function firstOpen(from)
		for n = from or 1, L.count do if filled[n] < RG.SIZE then return n end end
		for n = 1, L.count do if filled[n] < RG.SIZE then return n end end
	end
	local function put(r, n)
		filled[n] = filled[n] + 1
		moves[#moves + 1] = { guid = r.guid, kind = "group", n = n }
	end
	local heal, tank, dps = {}, {}, {}
	for _, r in ipairs(picked) do
		if r.role == "HEALER" then heal[#heal + 1] = r elseif r.role == "TANK" then tank[#tank + 1] = r else dps[#dps + 1] = r end
	end
	local rr = 1
	for _, r in ipairs(heal) do
		local n = firstOpen(rr)
		put(r, n)
		rr = rr % L.count + 1
	end
	for _, r in ipairs(tank) do put(r, firstOpen(1)) end
	local order = { melee = 1, ranged = 2, caster = 3 }
	table.sort(dps, function(a, b)
		local ka, kb = order[RG.DpsKind(a)], order[RG.DpsKind(b)]
		if ka ~= kb then return ka < kb end
		return a.name:lower() < b.name:lower()
	end)
	for _, r in ipairs(dps) do put(r, firstOpen(1)) end
	for _, r in ipairs(bench) do moves[#moves + 1] = { guid = r.guid, kind = "bench" } end
	return moves
end

-- The button. Returns how many players it placed and benched.
function RG:Fill(id)
	local B = SK.RaidBoard
	if not B.CanLead(Compat.PlayerGUID()) then return nil, "only officers and raid leaders can fill the raid" end
	local board = B:Get()
	local ev = board and board.events[id]
	if not ev then return nil, "unknown raid" end
	local rows = B.LineUp(board, ev, B.Ctx())
	local L = RG.Layout(board, ev, rows)
	local pct = {}
	local A = SK.Attendance
	for _, t in ipairs(A.Totals(A.Sorted(A:Store() or {}, Compat.Now() - 60 * 86400))) do pct[t.guid] = t.pct end
	local placed, benched = 0, 0
	local plan, dir = {}, SK.OfficerDir:Get()
	for _, r in ipairs(rows) do
		plan[r.guid] = { status = SK.OfficerDir.StatusOf(dir, r.guid), tiers = SK.OfficerDir.TiersOf(dir, r.guid) }
	end
	for _, m in ipairs(RG.AutoFill(L, ev.raid, pct, plan)) do
		if self:Move(id, m.guid, { kind = m.kind, n = m.n }) then
			if m.kind == "bench" then benched = benched + 1 else placed = placed + 1 end
		end
	end
	return placed, benched
end
