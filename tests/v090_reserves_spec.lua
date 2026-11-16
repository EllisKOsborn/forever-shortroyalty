-- v0.9.0 Reserve+ (not released): soft reserves with bonus points. The
-- owner's rules (16 Nov), each as a test.
local H = require("tests.helpers.load")

local BOB, CAT, DAN = "Player-1-B", "Player-1-C", "Player-1-D"
local MACE, TRINKET, DST = 101, 102, 103
local NOW = 1800000000

local function setup()
	local SK, W = H.load()
	W.member("Pip", W.player.guid, { rank = "Officer", rankIndex = 1 })
	W.member("Bob", BOB, { rank = "Raid Leader", rankIndex = 2 })
	W.member("Cat", CAT, { rank = "Member", rankIndex = 4 })
	W.member("Dan", DAN, { rank = "Member", rankIndex = 4 })
	SK.Identity:ReadRoster()
	return SK, W
end

-- A ledger built by hand: officer "O", entries one second apart.
local function ledger(R, entries)
	local store, c = R.New(), NOW
	for _, f in ipairs(entries) do
		c = c + 1
		local e = { by = "O", c = c }
		for k, v in pairs(f) do e[k] = v end
		e.id = e.by .. ":" .. string.format("%d", e.c)
		local ok, why = R.Merge(store, e, NOW + 1000, function() return true end)
		assert(ok, why)
	end
	return store
end

describe("v0.9.0 Reserve+ points", function()
	local R
	before_each(function()
		local SK = setup()
		R = SK.Reserves
	end)

	it("a night adds the bonus; no cap, so points keep growing", function()
		local nights = {}
		for n = 1, 30 do nights[n] = { k = "n", e = "raid" .. n, b = 10, g = { [CAT] = DST } } end
		local st = R.Replay(ledger(R, nights))
		assert.equal(300, R.PointsOf(st, CAT, DST)) -- three phases of DST, hundreds of points
	end)

	it("the owner's healer example: points stay on the item, a new item starts at 0", function()
		local st = R.Replay(ledger(R, {
			{ k = "n", e = "r1", b = 10, g = { [CAT] = MACE } },
			{ k = "n", e = "r2", b = 10, g = { [CAT] = MACE } },
			{ k = "n", e = "r3", b = 10, g = { [CAT] = TRINKET } }, -- switched to the trinket
		}))
		assert.equal(20, R.PointsOf(st, CAT, MACE))    -- kept for when they go back to it
		assert.equal(10, R.PointsOf(st, CAT, TRINKET)) -- built from scratch
		local items = R.ItemsOf(st, CAT)
		assert.equal(MACE, items[1].item)
	end)

	it("points belong to one character: alts don't share", function()
		local st = R.Replay(ledger(R, { { k = "n", e = "r1", b = 10, g = { [CAT] = MACE } } }))
		assert.equal(10, R.PointsOf(st, CAT, MACE))
		assert.equal(0, R.PointsOf(st, DAN, MACE))
	end)

	it("winning sets that item to 0 and leaves the others alone", function()
		local st = R.Replay(ledger(R, {
			{ k = "n", e = "r1", b = 10, g = { [CAT] = MACE } },
			{ k = "a", g = CAT, i = TRINKET, d = 40, r = "test" },
			{ k = "w", g = CAT, i = MACE, e = "r2" },
		}))
		assert.equal(0, R.PointsOf(st, CAT, MACE))
		assert.equal(40, R.PointsOf(st, CAT, TRINKET))
	end)

	it("the bonus is editable; a change counts from then on, not backwards", function()
		local st = R.Replay(ledger(R, {
			{ k = "n", e = "r1", b = 10, g = { [CAT] = MACE } },
			{ k = "s", b = 25 },
		}))
		assert.equal(10, R.PointsOf(st, CAT, MACE))
		assert.equal(25, st.bonus)
		assert.equal(R.DEFAULT_BONUS, R.Replay(R.New()).bonus)
	end)

	it("officers change points by hand, with a reason; a penalty can go below 0", function()
		local st = R.Replay(ledger(R, {
			{ k = "n", e = "r1", b = 10, g = { [CAT] = MACE } },
			{ k = "a", g = CAT, i = MACE, d = -30, r = "Left halfway through" },
		}))
		assert.equal(-20, R.PointsOf(st, CAT, MACE))
		local why = st.lines[CAT][MACE]
		assert.equal(2, #why)
		assert.equal("Left halfway through", why[2].r)
		assert.equal(-30, why[2].d)
	end)

	it("a mistaken bonus is undone, wherever the undo lands in the history", function()
		local store = ledger(R, {
			{ k = "n", e = "r1", b = 10, g = { [CAT] = MACE, [DAN] = TRINKET } }, -- Dan wasn't there
			{ k = "n", e = "r2", b = 10, g = { [CAT] = MACE } },
		})
		local night1 = R.Ordered(store)[1].id
		assert.is_true(R.Merge(store, { id = "O:" .. (NOW + 50), by = "O", c = NOW + 50, k = "x", x = night1, r = "Dan wasn't there" },
			NOW + 100, function() return true end))
		local st = R.Replay(store)
		assert.equal(10, R.PointsOf(st, CAT, MACE)) -- the whole night is undone
		assert.equal(0, R.PointsOf(st, DAN, TRINKET))
		assert.is_truthy(st.undone[night1])
	end)

	it("moves points to an alt the guild asked them to main (all, or some)", function()
		local st = R.Replay(ledger(R, {
			{ k = "n", e = "r1", b = 10, g = { [CAT] = MACE } },
			{ k = "n", e = "r2", b = 10, g = { [CAT] = MACE } },
			{ k = "n", e = "r3", b = 10, g = { [CAT] = TRINKET } },
			{ k = "m", g = CAT, i = MACE, g2 = DAN, i2 = DST, all = true, r = "Now maining Dan" },
			{ k = "m", g = CAT, i = TRINKET, g2 = DAN, i2 = TRINKET, d = 5, r = "Half" },
		}))
		assert.equal(0, R.PointsOf(st, CAT, MACE))
		assert.equal(20, R.PointsOf(st, DAN, DST))
		assert.equal(5, R.PointsOf(st, CAT, TRINKET))
		assert.equal(5, R.PointsOf(st, DAN, TRINKET))
	end)

	it("a bonus for a new character is just a change by hand", function()
		local st = R.Replay(ledger(R, { { k = "a", g = DAN, i = DST, d = 50, r = "Swapped to the tank we needed" } }))
		assert.equal(50, R.PointsOf(st, DAN, DST))
	end)

	it("everyone gets the same points whatever order entries arrive in", function()
		local a = ledger(R, {
			{ k = "n", e = "r1", b = 10, g = { [CAT] = MACE } },
			{ k = "w", g = CAT, i = MACE },
			{ k = "n", e = "r2", b = 10, g = { [CAT] = MACE } },
		})
		local b = R.New()
		local list = R.Ordered(a)
		for n = #list, 1, -1 do assert.is_true(R.Merge(b, list[n], NOW + 1000, function() return true end)) end
		assert.equal(10, R.PointsOf(R.Replay(b), CAT, MACE))
		assert.equal(R.PointsOf(R.Replay(a), CAT, MACE), R.PointsOf(R.Replay(b), CAT, MACE))
	end)
end)

describe("v0.9.0 Reserve+ the night", function()
	local R, st
	before_each(function()
		local SK = setup()
		R = SK.Reserves
		st = R.Replay(ledger(R, {
			{ k = "a", g = CAT, i = MACE, d = 100, r = "seed" },
			{ k = "a", g = DAN, i = MACE, d = 10, r = "seed" },
			{ k = "a", g = BOB, i = TRINKET, d = 80, r = "seed" },
		}))
	end)

	local function roll(g, n, max) return { guid = g, roll = n, min = 1, max = max or 100 } end

	it("roll + points on that reserve; the highest total wins", function()
		local rows = R.Rank(MACE, { roll(CAT, 5), roll(DAN, 90) }, { [CAT] = MACE, [DAN] = MACE }, st)
		assert.equal(CAT, rows[1].guid) -- 5 + 100 beats 90 + 10
		assert.equal(105, rows[1].total)
		assert.equal(100, rows[2].total)
	end)

	it("points only count on tonight's reserve", function()
		-- Bob has 80 on the trinket but reserved the mace tonight... and the trinket drops.
		local rows = R.Rank(TRINKET, { roll(BOB, 50), roll(CAT, 60) }, { [BOB] = MACE, [CAT] = TRINKET }, st)
		assert.equal(CAT, rows[1].guid) -- Cat reserved it (0 points on it) and beats a non-reserver
		assert.equal(0, rows[2].bonus)
		assert.is_false(rows[2].reserved)
	end)

	it("anyone can roll, but a reserver always beats a non-reserver", function()
		local rows = R.Rank(MACE, { roll(BOB, 100), roll(DAN, 1) }, { [DAN] = MACE }, st)
		assert.equal(DAN, rows[1].guid)
	end)

	it("nobody reserved it: plain rolls", function()
		local rows = R.Rank(DST, { roll(BOB, 40), roll(DAN, 70) }, {}, st)
		assert.equal(DAN, rows[1].guid)
	end)

	it("only the first 1-100 roll counts; ties are marked", function()
		local rows, ignored = R.Rank(DST, { roll(BOB, 40), roll(BOB, 99), roll(DAN, 99, 1000), roll(CAT, 40) }, {}, st)
		assert.equal(2, #rows)
		assert.equal(2, #ignored)
		assert.is_true(rows[1].tie)
		assert.is_true(rows[2].tie)
	end)

	it("end of night: there, boss killed, didn't win it", function()
		local picks = { [BOB] = MACE, [CAT] = TRINKET, [DAN] = DST, ["Player-1-Z"] = MACE }
		local present = function(g) return g ~= "Player-1-Z" end
		local killed = function(i) return i ~= DST end -- DST's boss wasn't killed
		local grants, skipped = R.NightGrants(picks, present, killed, { [CAT] = { [TRINKET] = true } })
		assert.same({ [BOB] = MACE }, grants)
		assert.equal("won it", skipped[CAT])
		assert.equal("boss not killed", skipped[DAN])
		assert.equal("not there", skipped["Player-1-Z"])
	end)
end)

describe("v0.9.0 Reserve+ trust", function()
	local SK, R
	before_each(function()
		SK = setup()
		R = SK.Reserves
	end)

	local function entry(by, c, f)
		local e = { by = by, c = c }
		for k, v in pairs(f) do e[k] = v end
		e.id = by .. ":" .. string.format("%d", c)
		return e
	end
	local isLead = function(g) return SK.RaidBoard.CanLead(g) end

	it("only officers and raid leaders (by our own roster) can change points", function()
		local store = R.New()
		assert.is_true(R.Merge(store, entry(BOB, NOW, { k = "a", g = CAT, i = MACE, d = 5 }), NOW, isLead))
		local ok, why = R.Merge(store, entry(CAT, NOW, { k = "a", g = CAT, i = MACE, d = 500 }), NOW, isLead)
		assert.is_false(ok)
		assert.equal("not an officer or raid leader", why)
	end)

	it("refuses bad shapes, future dates, links in reasons and duplicates", function()
		local store = R.New()
		local yes = function() return true end
		local bad = {
			entry(BOB, NOW, { k = "a", g = CAT, i = MACE, d = 0 }),
			entry(BOB, NOW, { k = "a", g = CAT, i = -1, d = 5 }),
			entry(BOB, NOW, { k = "a", g = CAT, i = MACE, d = 1.5 }),
			entry(BOB, NOW, { k = "a", g = CAT, i = MACE, d = 5, r = "|cffff0000red|r" }),
			entry(BOB, NOW, { k = "a", g = CAT, i = MACE, d = 5, r = string.rep("x", 81) }),
			entry(BOB, NOW, { k = "s", b = 5000 }),
			entry(BOB, NOW, { k = "m", g = CAT, i = MACE, g2 = CAT, i2 = MACE, all = true }),
			entry(BOB, NOW, { k = "m", g = CAT, i = MACE, g2 = DAN, i2 = MACE, d = -5 }),
			entry(BOB, NOW, { k = "q" }),
			entry(BOB, NOW + 1000, { k = "s", b = 5 }),
			{ id = "nope", by = BOB, c = NOW, k = "s", b = 5 },
		}
		for n, e in ipairs(bad) do assert.is_false((R.Merge(store, e, NOW, yes)), "case " .. n) end
		local grants = {}
		for n = 1, R.MAX_GRANTS + 1 do grants["Player-9-" .. n] = MACE end
		assert.is_false((R.Merge(store, entry(BOB, NOW, { k = "n", e = "r", b = 10, g = grants }), NOW, yes)))
		local ok = entry(BOB, NOW, { k = "s", b = 5, extra = "dropped" })
		assert.is_true(R.Merge(store, ok, NOW, yes))
		assert.is_nil(store.ledger[ok.id].extra)
		assert.is_false((R.Merge(store, ok, NOW, yes)))
	end)

	it("an undo can't be undone", function()
		local store = R.New()
		local yes = function() return true end
		R.Merge(store, entry(BOB, NOW, { k = "a", g = CAT, i = MACE, d = 5 }), NOW, yes)
		R.Merge(store, entry(BOB, NOW + 1, { k = "x", x = BOB .. ":" .. NOW }), NOW + 1, yes)
		R.Merge(store, entry(BOB, NOW + 2, { k = "x", x = BOB .. ":" .. (NOW + 1) }), NOW + 2, yes)
		assert.equal(0, R.PointsOf(R.Replay(store), CAT, MACE))
	end)

	it("in game: an officer's change is stored; a member's is refused", function()
		local e = R:Adjust(CAT, MACE, 20, "Welcome bonus")
		assert.is_truthy(e)
		assert.equal(20, R.PointsOf(R:State(), CAT, MACE))
		assert.is_truthy(R:Undo(e.id, "oops"))
		assert.equal(0, R.PointsOf(R:State(), CAT, MACE))
		assert.is_nil((R:Undo(e.id, "again")))
		assert.is_truthy(R:SetBonus(15))
		assert.equal(15, R:State().bonus)
		assert.is_truthy(R:Night("raid1", { [CAT] = MACE }))
		assert.equal(15, R.PointsOf(R:State(), CAT, MACE))
	end)

	it("in game: a member can't change points", function()
		local SK2, W2 = H.load()
		W2.member("Pip", W2.player.guid, { rank = "Member", rankIndex = 4 })
		SK2.Identity:ReadRoster()
		local e, why = SK2.Reserves:Adjust(CAT, MACE, 20, "please")
		assert.is_nil(e)
		assert.equal("only officers and raid leaders can change points", why)
	end)
end)
