-- v0.9.0 Reserve+ (not released): loot lists, tonight's reserves, the
-- officer's lock, sharing them, and the officer's loot night.
local H = require("tests.helpers.load")

local ME
local BOB, CAT, DAN, EVE = "Player-1-B", "Player-1-C", "Player-1-D", "Player-1-E"
local DEATHBRINGER, SHARD, NEW_ITEM = 17068, 17064, 290001

local function setup(myRank)
	local SK, W = H.load()
	ME = W.player.guid
	W.member("Pip", ME, myRank or { rank = "Officer", rankIndex = 1 })
	W.member("Bob Stout", BOB, { rank = "Raid Leader", rankIndex = 2 })
	W.member("Cat Nip", CAT, { rank = "Member", rankIndex = 4 })
	W.member("Dan Dee", DAN, { rank = "Member", rankIndex = 4 })
	W.member("Eve Ning", EVE, { rank = "Member", rankIndex = 4, online = false })
	SK.Identity:ReadRoster()
	SK.Profile:BuildSelf()
	return SK, W
end

-- A raid tonight made by an officer (Bob), as if it arrived over sync.
local function raidTonight(SK, W, raidKey)
	local board = SK.RaidBoard:Get()
	local e = { id = BOB .. ":" .. W.now, by = BOB, c = W.now, raid = raidKey or "ony", at = W.now + 1800, u = W.now }
	assert(SK.RaidBoard.MergeEvent(board, e, W.now, function() return true end))
	return e.id
end

local function deliver(SK, t, fields, sender, fromGUID)
	SK.Sync:OnCommReceived(SK.PREFIX, H.peerMessage(SK, t, fields, fromGUID), "GUILD", sender)
end

describe("v0.9.0 loot lists", function()
	it("Onyxia's bundled list, plus items officers added or saw drop", function()
		local SK = setup()
		local R = SK.Reserves
		local list = R.LootList(R:State(), "ony")
		assert.is_true(#list >= 18)
		assert.is_nil(SK.Data.LOOT.barrow.items[1]) -- new raid: nothing published yet
		assert.is_truthy(R:AddLoot("barrow", NEW_ITEM))
		local b, added = R.LootList(R:State(), "barrow")
		assert.same({ NEW_ITEM }, b)
		assert.is_truthy(added[NEW_ITEM])
		-- Undo removes it again.
		assert.is_truthy(R:Undo(added[NEW_ITEM], "wrong raid"))
		assert.same({}, (R.LootList(R:State(), "barrow")))
	end)
end)

describe("v0.9.0 tonight's reserves", function()
	local SK, W, R, id
	before_each(function()
		SK, W = setup()
		R = SK.Reserves
		id = raidTonight(SK, W)
	end)

	local function ctx(from, officer)
		return { now = W.now, officer = officer, raidExists = R.RaidExists, canWrite = function(g) return g == from or officer end }
	end

	it("each player sets their own; the raid's limit counts; the same item twice is fine", function()
		assert.is_true(R:SetMyPicks(id, { SHARD }))
		assert.same({ SHARD }, R:MyPicks(id))
		local ok, why = R:SetMyPicks(id, { SHARD, SHARD })
		assert.is_nil(ok)
		assert.equal("this raid allows 1 reserve", why)
		assert.is_truthy(R:SetPicks("ony", 2))
		assert.is_true(R:SetMyPicks(id, { SHARD, SHARD }))
		assert.same({ [SHARD] = 2 }, R.PicksOf(R:Get(), id)[ME])
	end)

	it("nobody can set someone else's reserve, except an officer", function()
		local store = R:Get()
		assert.is_false((R.MergePick(store, { e = id, g = CAT, i = { SHARD }, u = W.now }, ctx(DAN))))
		assert.is_true((R.MergePick(store, { e = id, g = CAT, i = { SHARD }, u = W.now }, ctx(CAT))))
		assert.is_true((R.MergePick(store, { e = id, g = CAT, i = { DEATHBRINGER }, u = W.now + 1 }, ctx(BOB, true))))
		assert.is_false((R.MergePick(store, { e = id, g = CAT, i = { SHARD }, u = W.now }, ctx(CAT)))) -- older
		assert.is_false((R.MergePick(store, { e = "nope", g = CAT, i = { SHARD }, u = W.now + 5 }, ctx(CAT))))
		assert.is_false((R.MergePick(store, { e = id, g = CAT, i = { 1.5 }, u = W.now + 5 }, ctx(CAT))))
		assert.is_false((R.MergePick(store, { e = id, g = CAT, i = { [3] = SHARD }, u = W.now + 5 }, ctx(CAT))))
	end)

	it("the lock: only officers; it records the bench (online or not) and a copy of the reserves", function()
		local store = R:Get()
		assert(R.MergePick(store, { e = id, g = CAT, i = { SHARD }, u = W.now }, ctx(CAT)))
		assert(R.MergePick(store, { e = id, g = DAN, i = { DEATHBRINGER }, u = W.now }, ctx(DAN)))
		assert(R.MergePick(store, { e = id, g = EVE, i = { DEATHBRINGER }, u = W.now }, ctx(EVE)))
		local inRaid = function(g) return g == CAT or g == ME end
		local lock = R:Lock(id, false, inRaid, SK.Compat.MemberOnline)
		assert.is_truthy(lock)
		assert.same({ [DAN] = "bench", [EVE] = "offline" }, lock.b)
		assert.same({ SHARD }, lock.s[CAT])
		-- After the lock, players can't change; the copy is what counts.
		local ok = R.MergePick(store, { e = id, g = CAT, i = { DEATHBRINGER }, u = W.now + 10 }, ctx(CAT))
		assert.is_false(ok)
		assert.equal(1, R.PicksOf(store, id)[CAT][SHARD])
		-- Members can't lock.
		local SK2, W2 = setup({ rank = "Member", rankIndex = 4 })
		local id2 = raidTonight(SK2, W2)
		assert.is_nil((SK2.Reserves:Lock(id2, false, function() return false end, function() return true end)))
	end)

	it("raid check and who reserved an item", function()
		local picks = { [CAT] = { [SHARD] = 1 }, [DAN] = { [SHARD] = 2 }, [EVE] = { [DEATHBRINGER] = 1 } }
		local missing, noReserve = R.RaidCheck(picks, { [CAT] = true, [DAN] = true, [BOB] = true })
		assert.same({ EVE }, missing)
		assert.same({ BOB }, noReserve)
		local by = R.ReservedBy(picks, SHARD)
		assert.equal(DAN, by[1].guid)
		assert.equal(2, by[1].count)
	end)

	it("reserves of raids the board deleted are pruned", function()
		local store = R:Get()
		assert(R.MergePick(store, { e = id, g = CAT, i = { SHARD }, u = W.now }, ctx(CAT)))
		SK.RaidBoard:Get().events[id] = nil
		assert.equal(1, R.PruneNights(store, R.RaidExists))
		assert.is_nil(store.picks[id])
	end)
end)

describe("v0.9.0 sharing points and reserves", function()
	local SK, W, R, id
	before_each(function()
		SK, W = setup({ rank = "Member", rankIndex = 4 })
		R = SK.Reserves
		id = raidTonight(SK, W)
	end)

	local function entry(by, c, f)
		local e = { by = by, c = c }
		for k, v in pairs(f) do e[k] = v end
		e.id = by .. ":" .. string.format("%d", c)
		return e
	end

	it("points history only from an officer sender, whatever the entry says", function()
		-- Cat (a member) passes on an entry that claims Bob (an officer) made it.
		deliver(SK, "LE", { l = { entry(BOB, W.now, { k = "a", g = CAT, i = SHARD, d = 500 }) } }, "Cat Nip", CAT)
		assert.equal(0, R.PointsOf(R:State(), CAT, SHARD))
		-- Bob sends it himself.
		deliver(SK, "LE", { l = { entry(BOB, W.now, { k = "a", g = CAT, i = SHARD, d = 20, r = "Welcome" }) } }, "Bob Stout", BOB)
		assert.equal(20, R.PointsOf(R:State(), CAT, SHARD))
		-- An officer may pass on another officer's entry, but not a member's.
		deliver(SK, "LE", { l = { entry(CAT, W.now + 1, { k = "a", g = CAT, i = SHARD, d = 999 }) } }, "Bob Stout", BOB)
		assert.equal(20, R.PointsOf(R:State(), CAT, SHARD))
	end)

	it("reserves from their owner or an officer; locks only from officers", function()
		deliver(SK, "LP", { q = { { e = id, g = DAN, i = { SHARD }, u = W.now } } }, "Cat Nip", CAT)
		assert.is_nil(R:Get().picks[id] and R:Get().picks[id][DAN])
		deliver(SK, "LP", { q = { { e = id, g = DAN, i = { SHARD }, u = W.now } } }, "Dan Dee", DAN)
		assert.same({ SHARD }, R:Get().picks[id][DAN].i)
		deliver(SK, "LP", { k = { { e = id, by = CAT, u = W.now, b = {}, s = {} } } }, "Cat Nip", CAT)
		assert.is_nil(R:Get().locks[id])
		deliver(SK, "LP", { k = { { e = id, by = BOB, u = W.now, b = { [DAN] = "bench" }, s = { [DAN] = { SHARD } } } } }, "Bob Stout", BOB)
		assert.equal("bench", R:Get().locks[id].b[DAN])
	end)

	it("my own reserve goes out on the guild channel; a member never sends history", function()
		local sent = H.captureSends(SK)
		assert.is_true(R:SetMyPicks(id, { SHARD }))
		W.advance(5)
		SK.Sync:Flush()
		local kinds = {}
		for _, s in ipairs(sent) do kinds[s.msg.t] = (kinds[s.msg.t] or 0) + 1 end
		assert.equal(1, kinds.LP)
		assert.is_nil(kinds.LE)
	end)

	it("history fingerprints by week; an officer answers what differs", function()
		local SK2, W2 = setup()
		local R2 = SK2.Reserves
		assert.is_truthy(R2:Adjust(CAT, SHARD, 10, "a"))
		W2.advance(10)
		local sent = H.captureSends(SK2)
		deliver(SK2, "LQ", { w = {}, r = {} }, "Cat Nip", CAT)
		W2.advance(10)
		SK2.Sync:Flush()
		local got = false
		for _, s in ipairs(sent) do if s.msg.t == "LE" then got = true end end
		assert.is_true(got)
		local d = SK2.ReserveSync.LedgerDigest(R2:Get())
		assert.equal(1, SK.Count(d))
	end)
end)

describe("v0.9.0 the officer's loot night", function()
	local SK, W, R, LN, id
	before_each(function()
		SK, W = setup()
		R, LN = SK.Reserves, SK.LootNight
		SK.DB.officer[ME] = true
		id = raidTonight(SK, W)
		W.raid = { { name = "Pip", guid = ME }, { name = "Bob Stout", guid = BOB }, { name = "Cat Nip", guid = CAT } }
	end)

	it("tonight's raid, and names from chat", function()
		assert.equal(id, LN.Tonight(SK.RaidBoard:Get(), W.now).id)
		assert.is_nil(LN.Tonight(SK.RaidBoard:Get(), W.now + 10 * 3600))
		local members = SK.Compat.RaidMembers()
		assert.equal(CAT, LN.MatchName("Cat Nip", members))
		assert.equal(CAT, LN.MatchName("Cat", members))
		assert.is_nil(LN.MatchName("Zed", members))
	end)

	it("reads rolls, drops, kills; learns new items; awards; saves the bonus once", function()
		local store = R:Get()
		assert(R.MergePick(store, { e = id, g = CAT, i = { DEATHBRINGER }, u = W.now },
			{ now = W.now, raidExists = R.RaidExists, canWrite = function() return true end }))
		assert(R.MergePick(store, { e = id, g = BOB, i = { DEATHBRINGER }, u = W.now },
			{ now = W.now, raidExists = R.RaidExists, canWrite = function() return true end }))
		assert(R.MergePick(store, { e = id, g = DAN, i = { SHARD }, u = W.now },
			{ now = W.now, raidExists = R.RaidExists, canWrite = function() return true end }))
		assert.is_truthy(R:Lock(id, false, function(g) return g ~= DAN end, function() return true end))
		W.fire("ENCOUNTER_END", 1084, "Onyxia", 9, 40, 1)
		W.loot = { { itemID = DEATHBRINGER, quality = 4 }, { itemID = NEW_ITEM, quality = 4 }, { itemID = 2589, quality = 1 } }
		W.fire("LOOT_OPENED")
		W.fire("LOOT_OPENED") -- the same corpse again
		local night = LN:Night(id)
		assert.equal(2, #night.drops)
		assert.equal(1, #night.kills)
		assert.is_truthy(R:State().loot.ony[NEW_ITEM]) -- learned and shared
		LN:Select(id, DEATHBRINGER)
		W.fire("CHAT_MSG_SYSTEM", "Cat Nip rolls 20 (1-100)")
		W.fire("CHAT_MSG_SYSTEM", "Bob Stout rolls 90 (1-100)")
		W.fire("CHAT_MSG_SYSTEM", "Not a roll")
		assert.equal(2, #night.rolls[DEATHBRINGER])
		local rows = R.Rank(DEATHBRINGER, night.rolls[DEATHBRINGER], R.PicksOf(store, id), R:State())
		assert.equal(BOB, rows[1].guid)
		assert.is_truthy(LN:Award(id, DEATHBRINGER, BOB))
		-- End of night: Cat +10 (in the raid), Dan +10 (bench, online at the lock), Bob won it.
		local endRows, grants = LN.EndRows(night, R.PicksOf(store, id), store.locks[id])
		assert.same({ DEATHBRINGER }, grants[CAT])
		assert.same({ SHARD }, grants[DAN])
		assert.is_nil(grants[BOB])
		assert.equal(3, #endRows)
		LN:ToggleOut(id, DAN) -- the officer leaves Dan out
		assert.is_truthy(LN:SaveNight(id))
		assert.equal(10, R.PointsOf(R:State(), CAT, DEATHBRINGER))
		assert.equal(0, R.PointsOf(R:State(), DAN, SHARD))
		assert.is_nil((LN:SaveNight(id))) -- only once
	end)

	it("texts for raid chat", function()
		assert.equal("Deathbringer: reserved by Cat (20), Bob. Reservers /roll now (roll + points wins).",
			LN.PostText("Deathbringer", { { name = "Cat", points = 20 }, { name = "Bob" } }))
		assert.equal("Deathbringer goes to Bob (110).", LN.AwardText("Deathbringer", "Bob", 110))
	end)

	it("parses rolls from the game's own text", function()
		local n, roll, lo, hi = SK.Compat.ParseRoll("Fizz Wick rolls 57 (1-100)")
		assert.equal("Fizz Wick", n)
		assert.equal(57, roll)
		assert.equal(1, lo)
		assert.equal(100, hi)
		assert.is_nil(SK.Compat.ParseRoll("Fizz says hi"))
	end)

	it("nothing happens for non-officers", function()
		SK.DB.officer[ME] = nil
		W.loot = { { itemID = DEATHBRINGER, quality = 4 } }
		W.fire("LOOT_OPENED")
		assert.is_nil(LN:Night(id))
	end)
end)
