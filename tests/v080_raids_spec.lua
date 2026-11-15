-- v0.8.0 Raids: raids made in the addon by officers and raid leaders,
-- sign-ups, sharing them, attendance (on time / late / didn't attend /
-- bench), the spreadsheet, /sr officer and the page.
local H = require("tests.helpers.load")

local ME = nil -- set per test (W.player.guid)
local BOB, CAT, DAN, EVE = "Player-1-B", "Player-1-C", "Player-1-D", "Player-1-E"

local function setup(myRank)
	local SK, W = H.load()
	ME = W.player.guid
	W.member("Pip", ME, myRank or { rank = "Officer", rankIndex = 1 })
	W.member("Bob", BOB, { rank = "Raid Leader", rankIndex = 2 })
	W.member("Cat", CAT, { rank = "Member", rankIndex = 4 })
	W.member("Dan", DAN, { rank = "Member", rankIndex = 4 })
	W.member("Eve", EVE, { rank = "Member", rankIndex = 4, online = false })
	SK.Identity:ReadRoster()
	SK.Profile:BuildSelf()
	return SK, W
end

local function deliver(SK, t, fields, sender, fromGUID, dist)
	SK.Sync:OnCommReceived(SK.PREFIX, H.peerMessage(SK, t, fields, fromGUID), dist or "GUILD", sender)
end

local function eventFrom(by, c, at, extra)
	local e = { id = by .. ":" .. string.format("%d", c), by = by, c = c, raid = "ony", at = at, u = c }
	for k, v in pairs(extra or {}) do e[k] = v end
	return e
end

describe("v0.8.0 who may make raids", function()
	it("officers, raid leaders and the Guild Master; nobody else", function()
		local SK = setup()
		local lead = SK.RaidBoard.IsLeadRank
		assert.is_true(lead({ rank = "Officer", rankIndex = 1 }))
		assert.is_true(lead({ rank = "Officers", rankIndex = 1 }))
		assert.is_true(lead({ rank = "Raid Leader", rankIndex = 2 }))
		assert.is_true(lead({ rank = "RaidLeader", rankIndex = 2 }))
		assert.is_true(lead({ rank = "Raid Lead", rankIndex = 2 }))
		assert.is_true(lead({ rank = "Officer Alt", rankIndex = 3 }))
		assert.is_true(lead({ rank = "Short King", rankIndex = 0 })) -- the Guild Master, whatever the rank is called
		assert.is_false(lead({ rank = "Member", rankIndex = 4 }))
		assert.is_false(lead({ rank = "Raider", rankIndex = 3 }))
		assert.is_false(lead({ rank = "Leader of fun", rankIndex = 3 }))
		assert.is_false(lead({ rank = "Officer", rankIndex = 1, leftAt = 5 })) -- left the guild
		assert.is_false(lead(nil))
		assert.is_true(SK.RaidBoard.CanLead(BOB))
		assert.is_false(SK.RaidBoard.CanLead(CAT))
	end)
end)

describe("v0.8.0 raid board", function()
	local SK, W, B
	before_each(function()
		SK, W = setup()
		B = SK.RaidBoard
	end)

	it("an officer makes a raid; members can't", function()
		local e = assert(B:Create("ony", W.now + 3600))
		assert.equal(ME, e.by)
		assert.equal(ME .. ":" .. string.format("%d", W.now), e.id)
		assert.is_true(B.ValidEvent(e, W.now))
		assert.equal(1, #B.Upcoming(B:Get(), W.now))
		local SK2, W2 = setup({ rank = "Member", rankIndex = 4 })
		local none, why = SK2.RaidBoard:Create("ony", W2.now + 3600)
		assert.is_nil(none)
		assert.truthy(why:find("officers", 1, true))
		assert.is_nil(select(1, B:Create("nope", W.now + 3600)))
		assert.is_nil(select(1, B:Create("ony", W.now - 7200))) -- already passed
	end)

	it("signs up with a role, changes the answer, and remembers the role", function()
		local e = B:Create("hyjal", W.now + 3600)
		assert.is_true(B:SignUp(e.id, "y", "HEALER"))
		local su = B:Get().signups[e.id][ME]
		assert.equal("y", su.s)
		assert.equal("HEALER", su.r)
		assert.equal("HEALER", (B.MyRole()))
		W.now = W.now + 10
		assert.is_true(B:SignUp(e.id, "n", "HEALER"))
		assert.equal("n", B:Get().signups[e.id][ME].s)
		assert.is_true(B:Get().signups[e.id][ME].u > su.u - 1)
		assert.same({ y = 0, t = 0, n = 1 }, B.Counts(B:Get(), e.id))
		assert.is_false(B:SignUp(e.id, "maybe"))
	end)

	it("cancelled raids drop out of the list and old raids are pruned", function()
		local e = B:Create("ony", W.now + 3600)
		assert.is_true(B:Cancel(e.id))
		assert.equal(0, #B.Upcoming(B:Get(), W.now))
		assert.is_true(B:Get().events[e.id].x)
		local e2 = B:Create("ony", W.now + 3600)
		B:SignUp(e2.id, "y")
		assert.equal(2, B.Prune(B:Get(), W.now + 3600 + B.KEEP_AFTER + 1))
		assert.is_nil(B:Get().signups[e2.id])
	end)

	it("checks everything received", function()
		local board, now = B.New(), W.now
		local lead = function(g) return g == BOB end
		assert.is_true(B.MergeEvent(board, eventFrom(BOB, now, now + 3600), now, lead))
		assert.same({ false, "not newer" }, { B.MergeEvent(board, eventFrom(BOB, now, now + 3600), now, lead) })
		assert.same({ false, "not an officer or raid leader" }, { B.MergeEvent(board, eventFrom(CAT, now, now + 3600), now, lead) })
		-- someone else's raid "cancelled" by a non-officer
		assert.is_false(B.MergeEvent(board, eventFrom(BOB, now, now + 3600, { u = now + 5, x = true, eb = CAT }), now, lead))
		assert.is_false(B.MergeEvent(board, eventFrom(BOB, now + 1, now + 3600, { id = "x" }), now, lead))
		assert.is_false(B.MergeEvent(board, eventFrom(BOB, now + 2, now + 3600, { raid = "naxx" }), now, lead))
		assert.is_false(B.MergeEvent(board, eventFrom(BOB, now + 3, now + 3600, { u = now + 3600 }), now, lead))
		assert.is_false(B.MergeEvent(board, eventFrom(BOB, now + 4, now + 90 * 86400), now, lead))
		assert.is_false(B.MergeEvent(board, eventFrom(BOB, now + 5, now + 3600, { x = "yes" }), now, lead))
		assert.is_false(B.MergeEvent(board, "raid", now, lead))
		-- a real cancellation by an officer
		assert.is_true(B.MergeEvent(board, eventFrom(BOB, now, now + 3600, { u = now + 5, x = true, eb = BOB }), now, lead))
		-- only the fields we know are stored
		local e = eventFrom(BOB, now + 9, now + 3600, { extra = string.rep("x", 1000) })
		assert.is_true(B.MergeEvent(board, e, now, lead))
		assert.is_nil(board.events[e.id].extra)

		local id = eventFrom(BOB, now, now).id
		local member = function(g) return g ~= "Player-9-X" end
		assert.is_true(B.MergeSignup(board, { e = id, g = CAT, s = "y", r = "TANK", u = now }, now, member))
		assert.is_false(B.MergeSignup(board, { e = id, g = CAT, s = "t", u = now }, now, member)) -- not newer
		assert.is_false(B.MergeSignup(board, { e = id, g = "Player-9-X", s = "y", u = now }, now, member))
		assert.is_false(B.MergeSignup(board, { e = "nope", g = DAN, s = "y", u = now }, now, member))
		assert.is_false(B.MergeSignup(board, { e = id, g = DAN, s = "yes", u = now }, now, member))
		assert.is_false(B.MergeSignup(board, { e = id, g = DAN, s = "y", r = "BARD", u = now }, now, member))
		assert.is_false(B.MergeSignup(board, { e = id, g = DAN, s = "y", u = now + 3600 }, now, member))
	end)

	it("limits how many raids and sign-ups are kept", function()
		local board, now = B.New(), W.now
		local lead = function() return true end
		for i = 1, B.MAX_EVENTS do assert.is_true(B.MergeEvent(board, eventFrom(BOB, now - i, now + i), now, lead)) end
		assert.same({ false, "too many raids" }, { B.MergeEvent(board, eventFrom(BOB, now - 999, now + 5), now, lead) })
		local id = eventFrom(BOB, now - 1, now + 1).id
		for i = 1, B.MAX_SIGNUPS do
			assert.is_true(B.MergeSignup(board, { e = id, g = "Player-1-" .. i, s = "y", u = now }, now, lead))
		end
		assert.is_false(B.MergeSignup(board, { e = id, g = "Player-1-999", s = "y", u = now }, now, lead))
	end)

	it("builds the line-up: role counts, guesses, readiness and Copy text", function()
		local e = B:Create("ony", W.now + 3600)
		B:SignUp(e.id, "y", "HEALER")
		local board = B:Get()
		board.signups[e.id][CAT] = { s = "y", u = W.now }
		board.signups[e.id][DAN] = { s = "t", r = "TANK", u = W.now }
		board.signups[e.id][EVE] = { s = "n", u = W.now }
		local rows, s = B.LineUp(board, e, B.Ctx())
		assert.equal(4, #rows)
		assert.equal("Pip", rows[1].name)        -- coming, healer
		assert.equal("coming", rows[2].group)    -- Cat, role unknown (no profile)
		assert.equal("Dan", rows[3].name)        -- tentative
		assert.equal("Eve", rows[4].name)        -- can't come
		assert.equal(2, s.coming)
		assert.equal(1, s.maybe)
		assert.equal(1, s.out)
		assert.equal(1, s.roles.HEALER)
		assert.same({ "No tanks yet" }, s.missing)
		assert.truthy(B.CountsText(s):find("2 / 40", 1, true))
		local text = B.Text(e, rows, s)
		assert.truthy(text:find("Onyxia's Lair", 1, true))
		assert.truthy(text:find("No tanks yet", 1, true))
		assert.is_nil(text:find("|c", 1, true))
	end)

	it("digests change when a sign-up changes", function()
		local e = B:Create("ony", W.now + 3600)
		local d1 = B.Digest(B:Get())[e.id]
		W.now = W.now + 5
		B:SignUp(e.id, "y")
		local d2 = B.Digest(B:Get())[e.id]
		assert.are_not.equal(d1, d2)
		assert.equal(8, #d2)
	end)

	it("offers the next 14 days and half-hour start times in local time", function()
		local day = B.DayStart(W.now, 2)
		local t = os.date("*t", day)
		assert.equal(0, t.hour)
		assert.equal(0, t.min)
		local at = B.StartAt(day, 20 * 60 + 30)
		local t2 = os.date("*t", at)
		assert.equal(20, t2.hour)
		assert.equal(30, t2.min)
		assert.equal(t.day, t2.day)
	end)
end)

describe("v0.8.0 sharing raids", function()
	local SK, W, B, sent
	before_each(function()
		SK, W = setup()
		B = SK.RaidBoard
		sent = H.captureSends(SK)
	end)

	local function sentOf(t)
		local out = {}
		for _, s in ipairs(sent) do if s.msg.t == t then out[#out + 1] = s end end
		return out
	end

	it("announces a new raid and a sign-up on the guild channel", function()
		local e = B:Create("ony", W.now + 3600)
		W.advance(SK.RaidSync.CHANGE_DELAY + 1)
		SK.Sync:Flush()
		local rb = sentOf("RB")
		assert.equal(1, #rb)
		assert.equal("GUILD", rb[1].dist)
		assert.equal(e.id, rb[1].msg.e[1].id)
		B:SignUp(e.id, "y", "DPS")
		W.advance(SK.RaidSync.CHANGE_DELAY + 1)
		SK.Sync:Flush()
		rb = sentOf("RB")
		assert.equal(2, #rb)
		assert.equal(0, #rb[2].msg.e) -- the raid was already sent
		assert.equal(ME, rb[2].msg.su[1].g)
		assert.equal("DPS", rb[2].msg.su[1].r)
	end)

	it("accepts a raid from a raid leader and refuses one from a member", function()
		deliver(SK, "RB", { e = { eventFrom(BOB, W.now, W.now + 3600) } }, "Bob", BOB)
		deliver(SK, "RB", { e = { eventFrom(CAT, W.now, W.now + 3600) } }, "Cat", CAT)
		local board = B:Get()
		assert.is_not_nil(board.events[eventFrom(BOB, W.now, 0).id])
		assert.is_nil(board.events[eventFrom(CAT, W.now, 0).id])
		assert.equal(1, SK.RaidSync.stats.rejected)
		-- a member's sign-up for it, relayed by Bob
		local id = eventFrom(BOB, W.now, 0).id
		deliver(SK, "RB", { su = { { e = id, g = CAT, s = "y", u = W.now } } }, "Bob", BOB)
		assert.equal("y", board.signups[id][CAT].s)
		-- only on the guild channel
		deliver(SK, "RB", { su = { { e = id, g = DAN, s = "y", u = W.now } } }, "Bob", BOB, "WHISPER")
		assert.is_nil(board.signups[id][DAN])
	end)

	it("answers a digest with the raids the asker lacks, unless someone answers first", function()
		local e = B:Create("ony", W.now + 3600)
		W.advance(SK.RaidSync.CHANGE_DELAY + 1)
		SK.Sync:Flush()
		sent = H.captureSends(SK)
		deliver(SK, "RD", { d = {} }, "Cat", CAT)
		W.advance(SK.RaidSync.ANSWER_MAX + 1)
		SK.Sync:Flush()
		assert.equal(1, #sentOf("RB"))
		assert.equal(e.id, sentOf("RB")[1].msg.e[1].id)

		-- Another RD; Bob answers with the same copy before our delay ends.
		sent = H.captureSends(SK)
		deliver(SK, "RD", { d = {} }, "Dan", DAN)
		local copy = SK.CopyTable(B:Get().events[e.id])
		deliver(SK, "RB", { e = { copy } }, "Bob", BOB)
		W.advance(SK.RaidSync.ANSWER_MAX + 1)
		SK.Sync:Flush()
		assert.equal(0, #sentOf("RB"))
	end)

	it("doesn't answer a digest that matches", function()
		B:Create("ony", W.now + 3600)
		W.advance(SK.RaidSync.CHANGE_DELAY + 1)
		SK.Sync:Flush()
		sent = H.captureSends(SK)
		deliver(SK, "RD", { d = B.Digest(B:Get()) }, "Cat", CAT)
		W.advance(SK.RaidSync.ANSWER_MAX + 1)
		SK.Sync:Flush()
		assert.equal(0, #sent)
	end)

	it("asks again when someone lists a raid we don't have", function()
		deliver(SK, "RD", { d = { [BOB .. ":1"] = "0000abcd" } }, "Bob", BOB)
		W.advance(SK.RaidSync.ANSWER_MAX + 1)
		SK.Sync:Flush()
		assert.equal(1, #sentOf("RD"))
	end)

	it("answers with a newer copy when an older one goes by", function()
		local e = B:Create("ony", W.now + 3600)
		B:SignUp(e.id, "y")
		W.advance(SK.RaidSync.CHANGE_DELAY + 1)
		SK.Sync:Flush()
		sent = H.captureSends(SK)
		W.now = W.now + 60
		B:Get().signups[e.id][ME].u = W.now -- our copy is newer than what Cat relays
		deliver(SK, "RB", { su = { { e = e.id, g = ME, s = "t", u = W.now - 60 } } }, "Cat", CAT)
		assert.equal("y", B:Get().signups[e.id][ME].s)
		W.advance(SK.RaidSync.ANSWER_MAX + 1)
		SK.Sync:Flush()
		assert.equal(1, #sentOf("RB"))
		assert.equal("y", sentOf("RB")[1].msg.su[1].s)
	end)

	it("shrugs off junk and huge messages", function()
		deliver(SK, "RB", { e = "raid", su = { 1, "x", { e = {}, g = 5 } } }, "Bob", BOB)
		deliver(SK, "RD", { d = "all" }, "Bob", BOB)
		deliver(SK, "RD", { d = { [1] = 2, [string.rep("x", 500)] = "y" } }, "Bob", BOB)
		local many = {}
		for i = 1, 1000 do many[i] = eventFrom(BOB, W.now - i, W.now + 3600) end
		deliver(SK, "RB", { e = many }, "Bob", BOB)
		assert.is_true(SK.Count(B:Get().events) <= B.MAX_EVENTS)
		W.advance(SK.RaidSync.ANSWER_MAX + 1)
		assert.equal(0, #SK.errors)
	end)

	it("splits big boards into several messages under the size limit", function()
		local e = B:Create("ony", W.now + 3600)
		local list = {}
		for i = 1, 100 do list["Player-1-" .. i] = { s = "y", r = "DPS", u = W.now } end
		B:Get().signups[e.id] = list
		local keys = SK.RaidSync.raidKeys(B:Get(), e.id)
		SK.RaidSync:Queue(keys)
		W.advance(SK.RaidSync.CHANGE_DELAY + 1)
		for _ = 1, 5 do SK.Sync:Flush() end
		local n = 0
		for _, s in ipairs(sentOf("RB")) do n = n + #s.msg.su + #s.msg.e end
		assert.equal(101, n)
		assert.is_true(#sentOf("RB") >= 1)
		assert.equal(0, #SK.errors)
	end)
end)

describe("v0.8.0 attendance rules", function()
	local SK, A
	local START = 1800000000
	before_each(function()
		SK = setup()
		A = SK.Attendance
	end)

	-- Snapshots every 2 min from 10 min before the start to 3 h after.
	local function play(rec, who)
		for t = START - 600, START + 3 * 3600, 120 do
			local inGroup, online = {}, {}
			for guid, f in pairs(who) do
				local state = f(t - START)
				if state == "in" then inGroup[guid] = true; online[guid] = true end
				if state == "on" then online[guid] = true end
			end
			local names = {}
			for guid in pairs(who) do names[guid] = { name = guid:sub(-1), class = "MAGE" } end
			A.AddSnapshot(rec, t, inGroup, online, names, rec.signups)
		end
	end

	local function result(rows, guid)
		for _, r in ipairs(rows) do if r.guid == guid then return r end end
	end

	it("sorts people into the owner's columns", function()
		local rec = A.NewRecord({ id = "x", raid = "ony", at = START }, "me", START - 600)
		rec.signups = {
			A1 = { s = "y" }, A2 = { s = "y" }, A3 = { s = "y" }, A4 = { s = "y" }, A5 = { s = "t" },
			A6 = { s = "n" }, A7 = { s = "y" },
		}
		play(rec, {
			A1 = function() return "in" end,                               -- whole raid
			A2 = function(t) return t >= 40 * 60 and "in" or "on" end,       -- 40 min late (benched first)
			A3 = function(t) return t <= 90 * 60 and "in" or "off" end,      -- left after 90 min
			A4 = function() return "off" end,                              -- never came
			A5 = function() return "on" end,                               -- tentative, online all raid, not in
			A6 = function() return "off" end,                              -- said can't come
			A7 = function(t) return (t > 60 * 60 and t < 66 * 60) and "on" or "in" end, -- 5 minutes away
			A8 = function() return "in" end,                               -- came without signing up
		})
		local rows = A.Rows(rec)
		assert.equal("full", result(rows, "A1").result)
		assert.equal("late", result(rows, "A2").result)
		assert.is_true(result(rows, "A2").bench)       -- 40 minutes online, not in the group
		assert.equal("late", result(rows, "A3").result) -- left early goes in the late column
		assert.equal("missed", result(rows, "A4").result)
		assert.is_false(result(rows, "A4").bench)
		assert.equal("missed", result(rows, "A5").result)
		assert.is_true(result(rows, "A5").bench)
		assert.equal("declined", result(rows, "A6").result)
		assert.equal("full", result(rows, "A7").result)  -- a short gap is fine
		assert.equal("full", result(rows, "A8").result)
		assert.equal("No", result(rows, "A8").signedName)
		assert.is_false(result(rows, "A1").bench)
		local s = A.Summary(rows)
		assert.same({ full = 3, late = 2, missed = 2, declined = 1, bench = 2 }, s)
		assert.equal(3 * 3600, rec.total)
	end)

	it("lets an officer tick or untick Bench", function()
		local store = A:Store()
		local rec = A.NewRecord({ id = "x", raid = "ony", at = START }, "me", START)
		rec.signups = { A4 = { s = "y" } }
		play(rec, { A4 = function() return "off" end })
		store.x = rec
		assert.is_false(result(A.Rows(rec), "A4").bench)
		A:ToggleBench("x", "A4")
		assert.is_true(result(A.Rows(rec), "A4").bench)
		A:ToggleBench("x", "A4")
		assert.is_false(result(A.Rows(rec), "A4").bench)
		assert.is_nil(rec.bench.A4) -- back to the automatic answer
	end)

	it("copies as a spreadsheet: tabs by default, commas with quotes if asked", function()
		local rec = A.NewRecord({ id = "x", raid = "ony", at = START }, "me", START)
		rec.signups = { A1 = { s = "y" }, A4 = { s = "y" } }
		play(rec, { A1 = function() return "in" end, A4 = function() return "on" end })
		rec.people.A1.name = "Pocus, the Tall"
		local text = A.Sheet({ rec }, "\t")
		local lines = {}
		for l in text:gmatch("[^\n]+") do lines[#lines + 1] = l end
		assert.equal(3, #lines)
		assert.equal(table.concat(A.SHEET_COLUMNS, "\t"), lines[1])
		local cells = {}
		for c in (lines[2] .. "\t"):gmatch("([^\t]*)\t") do cells[#cells + 1] = c end
		assert.same({ os.date("%Y-%m-%d", START), "Onyxia's Lair", "Pocus, the Tall", "Yes", "1", "", "", "", "180" }, cells)
		assert.truthy(lines[3]:find("\t\t1\t1\t0$")) -- didn't attend, bench, 0 minutes
		local csv = A.Sheet({ rec }, ",")
		assert.truthy(csv:find('"Pocus, the Tall"', 1, true))
		assert.truthy(csv:find('"On time, whole raid"', 1, true))
	end)

	it("adds raids up per person", function()
		local recs = {}
		for i = 1, 3 do
			local rec = A.NewRecord({ id = "r" .. i, raid = "ony", at = START + i * 86400 }, "me", START)
			rec.signups = { A1 = { s = "y" } }
			A.AddSnapshot(rec, rec.at + 60, i < 3 and { A1 = true } or {}, {}, { A1 = { name = "Al" } }, rec.signups)
			recs[i] = rec
		end
		local t = A.Totals(recs)
		assert.equal(1, #t)
		assert.equal(3, t[1].raids)
		assert.equal(2, t[1].full)
		assert.equal(1, t[1].missed)
		assert.equal(67, t[1].pct)
	end)
end)

describe("v0.8.0 recording", function()
	local SK, W, B, A
	before_each(function()
		SK, W = setup()
		B, A = SK.RaidBoard, SK.Attendance
		SK.DB.officer[ME] = true
	end)

	local function group()
		W.raid = { { name = "Pip", guid = ME }, { name = "Bob", guid = BOB }, { name = "Cat", guid = CAT } }
	end

	it("starts in the raid group at raid time, checks every 2 minutes, and stops after leaving", function()
		local e = B:Create("ony", W.now + 20 * 60)
		B:Get().signups[e.id] = { [DAN] = { s = "y", u = W.now } } -- online, not in the group
		A:Tick(W.now)
		assert.is_nil(A.current) -- not in a raid group
		group()
		A:Tick(W.now)
		assert.is_not_nil(A.current)
		assert.equal(1, A.current.snaps)
		A:Tick(W.now + 60)
		assert.equal(1, A.current.snaps)
		W.combat = true
		A:Tick(W.now + 20 * 60 + 130)
		assert.equal(1, A.current.snaps)
		assert.is_true(A.pendingSnap)
		W.combat = false
		A:Tick(W.now + 20 * 60 + 140)
		assert.equal(2, A.current.snaps)
		W.raid = nil
		A:Tick(W.now + 40 * 60)
		assert.is_not_nil(A.current)
		A:Tick(W.now + 40 * 60 + A.LEFT_AFTER)
		assert.is_nil(A.current)
		local rec = A:Store()[e.id]
		assert.equal(W.now + 40 * 60, rec.ended)
		local rows = A.Rows(rec)
		local byGuid = {}
		for _, r in ipairs(rows) do byGuid[r.guid] = r end
		assert.equal("full", byGuid[BOB].result)
		assert.equal("missed", byGuid[DAN].result)
		assert.equal("No", byGuid[CAT].signedName)
		-- an ended raid doesn't start again by itself, Resume does
		group()
		A:Tick(W.now + 41 * 60)
		assert.is_nil(A.current)
		assert.is_true(A:Resume(e.id))
		assert.is_not_nil(A.current)
	end)

	it("matches raid members by name when the game hides their GUID", function()
		B:Create("ony", W.now + 60)
		group()
		W.raidHideGuid = true
		A:Tick(W.now + 120)
		assert.is_not_nil(A.current.people[BOB].first)
	end)

	it("records nothing unless the officer tools are on", function()
		B:Create("ony", W.now + 60)
		SK.DB.officer[ME] = nil
		group()
		A:Tick(W.now + 120)
		assert.is_nil(A.current)
	end)

	it("stops 6 hours after the start", function()
		local e = B:Create("ony", W.now + 60)
		group()
		A:Tick(W.now + 120)
		A:Tick(e.at + A.LONGEST + 1)
		assert.is_nil(A.current)
		assert.equal(e.at + A.LONGEST, A:Store()[e.id].ended)
	end)
end)

describe("v0.8.0 /sr officer and the page", function()
	it("/sr officer answers only officers and raid leaders", function()
		local SK, W = setup({ rank = "Member", rankIndex = 4 })
		H.loadUI(SK)
		SK.Commands.Run("officer")
		assert.is_nil(SK.DB.officer[ME])
		assert.truthy(W.prints[#W.prints]:find("/sr", 1, true)) -- the help
		local SK2, W2 = setup()
		H.loadUI(SK2)
		SK2.Commands.Run("officer")
		assert.is_true(SK2.DB.officer[W2.player.guid])
		assert.is_true(SK2.RaidBoard.OfficerView())
		SK2.Commands.Run("officer")
		assert.is_nil(SK2.DB.officer[W2.player.guid])
	end)

	it("members see Raids only; officers also New raid and Attendance", function()
		local SK, W = setup()
		H.loadUI(SK)
		SK.DB.settings.raidsView = "attendance"
		assert.equal("upcoming", SK.RaidsTab.View(false))
		assert.equal("attendance", SK.RaidsTab.View(true))
		local e = SK.RaidBoard:Create("ony", W.now + 3600)
		SK.MainFrame:Open("raids")
		local RT = SK.RaidsTab
		assert.equal(e.id, RT.selected)
		assert.is_false(RT.views.tabs[3]:IsShown())
		RT.signButtons[1]:GetScript("OnClick")(RT.signButtons[1])
		assert.equal("y", SK.RaidBoard:Get().signups[e.id][ME].s)
		assert.truthy(RT.mine:GetText():find("Signed up", 1, true))
		SK.DB.officer[ME] = true
		RT:Refresh()
		assert.is_true(RT.views.tabs[3]:IsShown())
		assert.is_true(RT.attPage:IsShown())
		SK.DB.settings.attView = "totals"
		RT:Refresh()
		SK.DB.settings.raidsView = "new"
		SK.DB.settings.newRaid = { raid = "barrow", day = 1, minutes = 19 * 60 + 30 }
		RT:Refresh()
		RT:CreateRaid()
		assert.equal(2, #SK.RaidBoard.Upcoming(SK.RaidBoard:Get(), W.now))
		RT:CopyLineUp()
		assert.equal(0, #SK.errors)
	end)

	it("the Overview shows the next raid and my answer", function()
		local SK, W = setup()
		H.loadUI(SK)
		local e = SK.RaidBoard:Create("ony", W.now + 3600)
		local o = SK.Overview.Build(SK.DBM:Guild(), W.now)
		assert.equal(e.id, o.nextRaid.ev.id)
		local text = SK.OverviewTab.RaidText(o)
		assert.truthy(text:find("Onyxia's Lair", 1, true))
		assert.truthy(text:find("not signed up", 1, true))
		SK.RaidBoard:SignUp(e.id, "t")
		o = SK.Overview.Build(SK.DBM:Guild(), W.now)
		assert.truthy(SK.OverviewTab.RaidText(o):find("Tentative", 1, true))
	end)

	it("/sr debug has a Raids block", function()
		local SK = setup()
		H.loadUI(SK)
		local text = table.concat(SK.Commands.BuildReport(), "\n")
		assert.truthy(text:find("== Raids (v0.8.0) ==", 1, true))
		assert.truthy(text:find("can make raids: yes", 1, true))
		assert.truthy(text:find("1 Officer (raids)", 1, true))
	end)
end)
