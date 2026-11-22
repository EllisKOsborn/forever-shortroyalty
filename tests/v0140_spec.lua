-- v0.14.0: the officers' second round. Planner "Off" and "Social"; raid
-- nights to be decided or with several instances (groups per instance, one
-- reserve list); raids made from the Calendar (the day box, also "I'm away"
-- for everyone); attendance = signed up and online at the start, with
-- no-shows and changed sign-ups.
local H = require("tests.helpers.load")

local BOB, CAT, DAN, EVE = "Player-1-B", "Player-1-C", "Player-1-D", "Player-1-E"

local function setup()
	local SK, W = H.load()
	W.member("Pip", W.player.guid, { rank = "Officer", rankIndex = 1 })
	W.member("Bob", BOB, { rank = "Raid Leader", rankIndex = 2 })
	W.member("Cat", CAT, { rank = "Member", rankIndex = 4 })
	W.member("Dan", DAN, { rank = "Member", rankIndex = 4 })
	W.member("Eve", EVE, { rank = "Member", rankIndex = 4, online = false })
	SK.Identity:ReadRoster()
	SK.Profile:BuildSelf()
	return SK, W
end

local function rowOf(rows, guid)
	for _, r in ipairs(rows) do if r.guid == guid then return r end end
end

describe("v0.14.0 roster planner words", function()
	it("has Social as a status and calls the second tier Off", function()
		local SK = setup()
		local OD, RP = SK.OfficerDir, SK.RosterPlan
		assert.is_true(OD:SetStatus(CAT, "s"))
		assert.equal("s", OD.StatusOf(OD:Get(), CAT))
		assert.equal("Social", RP.STATUS_NAME.s)
		assert.equal("Off", RP.TIER_NAME.b)
		assert.is_true(OD.Valid("s:" .. CAT, { v = "s", u = 1, by = BOB }, 10))
		assert.is_false((OD.Valid("s:" .. CAT, { v = "x", u = 1, by = BOB }, 10)))
		-- Raiders, Backups, Social, then not set.
		local rows = { { status = "s", name = "a" }, { status = nil, name = "b" }, { status = "b", name = "c" } }
		table.sort(rows, RP.DefaultOrder)
		assert.same({ "c", "a", "b" }, { rows[1].name, rows[2].name, rows[3].name })
	end)
end)

describe("v0.14.0 raid nights", function()
	local SK, W, B
	before_each(function()
		SK, W = setup()
		B = SK.RaidBoard
	end)

	it("can be to be decided, or cover several instances", function()
		assert.same({ "hyjal", "ony" }, B.ParseKeys("ony,hyjal"))
		assert.same({}, B.ParseKeys(""))
		assert.is_nil(B.ParseKeys("ony,ony"))
		assert.is_nil(B.ParseKeys("mc"))
		assert.is_nil(B.ParseKeys("ony,"))
		local tbd = B:Create({}, W.now + 40 * 86400)
		assert.equal("tbd", tbd.raid)
		assert.equal("", tbd.rs)
		assert.equal("Raid (to be decided)", B.EventName(tbd))
		assert.is_nil(B.EventSize(tbd))
		local two = B:Create({ "ony", "hyjal" }, W.now + 3600)
		assert.equal("hyjal", two.raid)
		assert.equal("hyjal,ony", two.rs)
		assert.equal("Hyjal Summit + Onyxia's Lair", B.EventName(two))
		assert.equal("Hyjal + Onyxia", B.EventName(two, true))
		assert.equal(40, B.EventSize(two))
		assert.equal("ony", B.AttRaid(two).key)
		local one = B:Create("barrow", W.now + 3600)
		assert.is_nil(one.rs) -- one instance keeps the v0.8.0 shape
		assert.same({ "barrow" }, B.Keys(one))
		-- v0.15.1: no practical limit (a year and a bit).
		assert.truthy(B:Create({}, W.now + 200 * 86400))
		assert.is_nil((B:Create({}, W.now + 401 * 86400)))
	end)

	it("checks rs against raid when it arrives", function()
		local e = { id = BOB .. ":5", by = BOB, c = 5, raid = "hyjal", rs = "hyjal,ony", at = W.now + 60, u = 5 }
		assert.is_true(B.ValidEvent(e, W.now))
		e.raid = "ony"
		assert.is_false((B.ValidEvent(e, W.now)))
		e.raid, e.rs = "tbd", ""
		assert.is_true(B.ValidEvent(e, W.now))
		e.rs = nil
		assert.is_false((B.ValidEvent(e, W.now))) -- what older versions see: unknown raid
		e.raid, e.rs = "hyjal", "hyjal,bad"
		assert.is_false((B.ValidEvent(e, W.now)))
	end)

	it("officers pick the instances later; groups move with the instance", function()
		local RG = SK.RaidGroups
		local e = B:Create("ony", W.now + 3600)
		B:SignUp(e.id, "y")
		assert.is_true(RG:Move(e.id, W.player.guid, { kind = "group", n = 3 }))
		assert.equal(3, (RG.SlotOf(B:Get(), e.id, W.player.guid)))
		assert.is_true(B:SetRaids(e.id, { "ony", "hyjal" }))
		local ev = B:Get().events[e.id]
		assert.equal("hyjal,ony", ev.rs)
		assert.equal(e.id .. "@ony", RG.SlotId(ev, "ony"))
		assert.equal(3, (RG.SlotOf(B:Get(), e.id .. "@ony", W.player.guid)))
		-- Hyjal has its own groups.
		assert.is_true(RG:Move(e.id, W.player.guid, { kind = "group", n = 1 }, nil, "hyjal"))
		local L = RG.Layout(B:Get(), ev, B.LineUp(B:Get(), ev, B.Ctx()), "hyjal")
		assert.equal(4, L.count)
		assert.equal(1, #L.groups[1])
		L = RG.Layout(B:Get(), ev, B.LineUp(B:Get(), ev, B.Ctx()), "ony")
		assert.equal(8, L.count)
		assert.equal(1, #L.groups[3])
		-- The Bench is for the whole night: out of both instances' groups.
		assert.is_true(RG:Move(e.id, W.player.guid, { kind = "bench" }, nil, "ony"))
		assert.equal(0, (RG.SlotOf(B:Get(), e.id .. "@hyjal", W.player.guid)))
		-- Back to one instance.
		assert.is_true(RG:Move(e.id, W.player.guid, { kind = "group", n = 2 }, nil, "ony"))
		assert.is_true(B:SetRaids(e.id, { "ony" }))
		assert.equal(2, (RG.SlotOf(B:Get(), e.id, W.player.guid)))
		assert.is_false((B:SetRaids(e.id, { "nope" })))
	end)

	it("shares per-instance groups and prunes them with the raid", function()
		local RG = SK.RaidGroups
		local e = B:Create({ "hyjal", "ony" }, W.now + 3600)
		local board = B:Get()
		local s = { e = e.id .. "@ony", g = CAT, n = 2, m = "", u = W.now, by = BOB }
		assert.is_true(RG.MergeSlot(board, s, W.now, function() return true end, function() return true end))
		assert.is_false((RG.MergeSlot(board, { e = e.id .. "@mc", g = CAT, n = 2, m = "", u = W.now, by = BOB }, W.now,
			function() return true end, function() return true end)))
		local before = B.Digest(board)[e.id]
		board.slots[e.id .. "@ony"][CAT].u = W.now + 1
		assert.are_not.equal(before, B.Digest(board)[e.id])
		local keys = SK.RaidSync.raidKeys(board, e.id)
		local found = false
		for _, k in ipairs(keys) do if k == "G:" .. e.id .. "@ony|" .. CAT then found = true end end
		assert.is_true(found)
		board.events[e.id].at = W.now - 30 * 86400
		B.Prune(board, W.now)
		assert.is_nil(board.slots[e.id .. "@ony"])
	end)

	it("one reserve list for the night, with the larger limit", function()
		local R = SK.Reserves
		local st = { picks = { ony = 2, hyjal = 1 }, loot = { ony = { [111] = "x" }, hyjal = { [222] = "y" } } }
		local ev = { raid = "hyjal", rs = "hyjal,ony" }
		assert.equal(2, R.EventPicks(st, ev))
		local list = R.EventLoot(st, ev, {})
		local has = {}
		for _, i in ipairs(list) do has[i] = true end
		assert.is_true(has[111] and has[222])
		assert.equal(1, R.EventPicks(st, { raid = "tbd", rs = "" }))
		assert.same({}, R.EventLoot(st, { raid = "tbd", rs = "" }, {}))
	end)

	it("Discord texts name every instance", function()
		local e = B:Create({ "hyjal", "ony" }, W.now + 3600)
		local rows, sum = B.LineUp(B:Get(), e, B.Ctx())
		assert.truthy(B.DiscordText(e, rows, sum):find("Hyjal Summit + Onyxia's Lair (40)", 1, true))
		local code = B.BotCode(e, rows, {}, W.now)
		assert.truthy(code:find(";hyjal;Hyjal Summit + Onyxia's Lair;40;", 1, true))
		local tbd = B:Create({}, W.now + 7200)
		assert.truthy(B.BotCode(tbd, {}, {}, W.now):find(";tbd;Raid (to be decided);40;", 1, true))
	end)

	it("remembers when a sign-up moved away from Signed up", function()
		local e = B:Create("ony", W.now + 86400)
		B:SignUp(e.id, "t")
		assert.is_nil(B:Get().signups[e.id][W.player.guid].w) -- never signed up
		B:SignUp(e.id, "y")
		W.now = W.now + 100
		B:SignUp(e.id, "n")
		local su = B:Get().signups[e.id][W.player.guid]
		assert.equal(W.now, su.w)
		W.now = W.now + 100
		B:SignUp(e.id, "t")
		assert.equal(W.now - 100, B:Get().signups[e.id][W.player.guid].w) -- still the first change
		B:SignUp(e.id, "y")
		assert.is_nil(B:Get().signups[e.id][W.player.guid].w)
		assert.is_false((B.ValidSignup({ e = "x", g = "y", s = "y", u = 5, w = 4 }, 10))) -- w with Signed up
		assert.is_false((B.ValidSignup({ e = "x", g = "y", s = "n", u = 5, w = 6 }, 10))) -- after its change
		assert.is_true(B.ValidSignup({ e = "x", g = "y", s = "n", u = 5, w = 4 }, 10))
	end)
end)

describe("v0.14.0 Raids page", function()
	local SK, W, B, RT
	before_each(function()
		SK, W = setup()
		H.loadUI(SK)
		B, RT = SK.RaidBoard, SK.RaidsTab
		W.now = os.time({ year = 2026, month = 12, day = 2, hour = 15 })
		SK.DB.officer[W.player.guid] = true
	end)

	it("has no New raid tab; the Calendar's day box makes raids, months ahead too", function()
		for _, t in ipairs(RT.VIEWS) do assert.are_not.equal("new", t[1]) end
		SK.DB.settings.raidsView = "new" -- a saved old tab
		assert.equal("calendar", RT.View(true))
		SK.MainFrame:Open("raids")
		RT:MoveMonth(1) -- January
		local cell = RT.calCells[20]
		RT:CalendarDay(cell.cell, cell, 20)
		assert.is_true(RT.dayBox.create:IsShown())
		-- No instance picked: to be decided.
		local form = RT.NewRaidForm()
		form.keys = {}
		RT.dayBox.create:GetScript("OnClick")(RT.dayBox.create)
		local ev = B:Get().events[RT.selected]
		assert.equal("tbd", ev.raid)
		assert.equal(date("%Y-%m-%d", cell.cell.at), date("%Y-%m-%d", ev.at))
		-- Toggling instances in the box.
		RT.dayBox.keys[3]:GetScript("OnClick")(RT.dayBox.keys[3]) -- Onyxia
		RT.dayBox.keys[2]:GetScript("OnClick")(RT.dayBox.keys[2]) -- Hyjal
		assert.same({ "hyjal", "ony" }, RT.NewRaidForm().keys)
		RT:CloseDay()
		-- v0.15.1: three months on works too; a refusal shows in full.
		RT:MoveMonth(2)
		RT:CalendarDay(RT.calCells[20].cell, RT.calCells[20], 20)
		assert.is_true(RT.dayBox.create:IsShown())
		RT.dayBox.create:GetScript("OnClick")(RT.dayBox.create)
		assert.truthy(RT.dayResult:find("Made", 1, true))
		assert.is_true(RT.dayBox.result:IsShown())
		RT:CloseDay()
		-- More than a year on: the day box says so instead of offering Create.
		RT:MoveMonth(12)
		RT:CalendarDay(RT.calCells[20].cell, RT.calCells[20], 20)
		assert.is_false(RT.dayBox.create:IsShown())
		assert.equal(0, #SK.errors)
	end)

	it("officers set a night's instances from its title chips; Groups shows one instance at a time", function()
		local e = B:Create({}, W.now + 3600)
		RT:ShowRaid(e.id)
		RT:Refresh()
		assert.equal("Raid (to be decided)", RT.title:GetText())
		RT.keyChips[1]:GetScript("OnClick")(RT.keyChips[1]) -- the last chip first: Onyxia
		assert.same({ "ony" }, B.Keys(B:Get().events[e.id]))
		RT.keyChips[2]:GetScript("OnClick")(RT.keyChips[2]) -- Hyjal
		assert.same({ "hyjal", "ony" }, B.Keys(B:Get().events[e.id]))
		SK.DB.settings.raidsView = "groups"
		RT:Refresh()
		assert.equal("hyjal", RT.grpKey)
		assert.is_true(RT.grpBoxes[4]:IsShown())
		assert.is_false(RT.grpBoxes[5]:IsShown())
		RT.grpKeys[1]:GetScript("OnClick")(RT.grpKeys[1]) -- Onyxia
		assert.equal("ony", RT.grpKey)
		assert.is_true(RT.grpBoxes[8]:IsShown())
		assert.equal(0, #SK.errors)
	end)

	it("members can mark themselves away from the day box", function()
		SK.DB.officer[W.player.guid] = nil
		SK.DB.settings.raidsView = "calendar"
		SK.MainFrame:Open("raids")
		local c = RT.calCells[10]
		RT:CalendarDay(c.cell, c, 10)
		assert.is_true(RT.dayBox:IsShown())
		assert.is_false(RT.dayBox.create:IsShown())
		RT.dayBox.away:GetScript("OnClick")(RT.dayBox.away)
		assert.is_true(SK.Absences.IsAway(SK.Absences:Mine(W.now), c.cell.at))
		assert.equal("Not away 9 Dec after all", RT.dayBox.away.label:GetText())
	end)
end)

describe("v0.14.0 attendance: online at the start", function()
	local SK, W, B, A
	before_each(function()
		SK, W = setup()
		B, A = SK.RaidBoard, SK.Attendance
	end)

	local function online(guid, on)
		for _, e in ipairs(W.roster) do if e.guid == guid then e.online = on end end
		SK.Identity:ReadRoster()
	end

	it("on time, late, no-show, tentative; sign-ups changed before the start", function()
		local e = B:Create("ony", W.now + 3600)
		local su = B:Get().signups
		su[e.id] = {
			[BOB] = { s = "y", u = W.now },                       -- online at the start
			[CAT] = { s = "y", u = W.now },                       -- logs in 5 minutes late
			[DAN] = { s = "y", u = W.now },                       -- never comes
			[EVE] = { s = "t", u = W.now },                       -- tentative, offline
			[W.player.guid] = { s = "n", u = W.now, w = e.at - 3600 }, -- changed an hour before
		}
		B:Get().places[e.id] = { [BOB] = { v = "b", u = W.now, by = BOB } }
		online(CAT, false)
		online(DAN, false)
		A:Tick(e.at - 60)               -- asks for a fresh roster
		assert.is_nil(A:Store()[e.id])
		A:Tick(e.at + 10)
		local rec = A:Store()[e.id]
		assert.equal(2, rec.v)
		assert.is_nil(rec.total) -- older versions refuse it rather than show it wrong
		online(CAT, true)
		A:Tick(e.at + 5 * 60)
		A:Tick(e.at + A.LATE_FOR + 30)  -- closes it
		assert.equal(e.at + A.LATE_FOR, rec.ended)
		local rows = A.Rows(rec)
		assert.equal("full", rowOf(rows, BOB).result)
		assert.is_true(rowOf(rows, BOB).bench) -- online and on the Bench
		assert.equal("late", rowOf(rows, CAT).result)
		assert.equal("missed", rowOf(rows, DAN).result)
		assert.equal("maybe", rowOf(rows, EVE).result)
		local me = rowOf(rows, W.player.guid)
		assert.equal("full", me.result) -- online anyway
		assert.equal(e.at - 3600, me.changed)
		assert.is_true(me.changedLate)
		local t = A.Totals({ rec })
		local tot = {}
		for _, x in ipairs(t) do tot[x.guid] = x end
		assert.equal(1, tot[DAN].missed)
		assert.equal(0, tot[DAN].pct)
		assert.equal(1, tot[W.player.guid].changed)
		assert.equal(1, tot[W.player.guid].changedLate)
		assert.equal(1, tot[W.player.guid].signedUp)
		-- Nothing more once closed.
		A:Tick(e.at + 3600)
		assert.equal(rec.ended, A:Store()[e.id].ended)
	end)

	it("needs an officer or raid leader rank, not /sr officer", function()
		local e = B:Create("ony", W.now + 60)
		B:Get().signups[e.id] = { [BOB] = { s = "y", u = W.now } }
		SK.DB.officer[W.player.guid] = nil
		A:Tick(e.at + 30)
		assert.is_not_nil(A:Store()[e.id])
	end)

	it("an officer who logs in late counts who's online as on time; merging keeps the better result", function()
		local ev = { id = "x:1", raid = "ony", at = 1000 }
		local late = A.NewCheck(ev, BOB, 1600)
		A.AddCheck(late, 1600, { [CAT] = true }, {}, { [CAT] = { s = "y" }, [DAN] = { s = "y" } })
		assert.equal("s", late.o[CAT])
		local early = A.NewCheck(ev, W.player.guid, 1000)
		A.AddCheck(early, 1000, {}, {}, { [CAT] = { s = "y" }, [DAN] = { s = "y" } })
		A.AddCheck(early, 1300, { [DAN] = true }, {}, { [CAT] = { s = "y" }, [DAN] = { s = "y" } })
		assert.equal("l", early.o[DAN])
		local out, changed = A.Merge(early, A.Copy(late))
		assert.is_true(changed)
		assert.equal("s", out.o[CAT])
		assert.equal("l", out.o[DAN])
		assert.equal(1000, out.began)
		-- A v0.8.0 record and a v0.14.0 one don't mix.
		local old = A.NewRecord(ev, BOB, 1000)
		local kept, ch2 = A.Merge(old, A.Copy(late))
		assert.equal(old, kept)
		assert.is_false(ch2)
	end)

	it("checks received v0.14.0 records", function()
		local ev = { id = "x:1", raid = "tbd", rs = "", at = 1000 }
		local rec = A.NewCheck(ev, BOB, 1000)
		A.AddCheck(rec, 1000, { [CAT] = true }, { [CAT] = { name = "Cat" } }, { [CAT] = { s = "n", w = 900 } })
		assert.is_true(A.ValidRecord(A.Copy(rec), 2000))
		local bad = A.Copy(rec)
		bad.o[CAT] = "x"
		assert.is_false((A.ValidRecord(bad, 2000)))
		bad = A.Copy(rec)
		bad.w[CAT] = "soon"
		assert.is_false((A.ValidRecord(bad, 2000)))
		bad = A.Copy(rec)
		bad.v = 3
		assert.is_false((A.ValidRecord(bad, 2000)))
		bad = A.Copy(rec)
		bad.rs = "mc"
		assert.is_false((A.ValidRecord(bad, 2000)))
	end)

	it("the Attendance page shows results, changes and totals", function()
		H.loadUI(SK)
		local RT = SK.RaidsTab
		SK.DB.officer[W.player.guid] = true
		local e = B:Create("ony", W.now + 60)
		B:Get().signups[e.id] = { [BOB] = { s = "y", u = W.now }, [CAT] = { s = "t", u = W.now, w = W.now - 7200 } }
		A:Tick(e.at + 10)
		SK.DB.settings.raidsView = "attendance"
		SK.MainFrame:Open("raids")
		assert.truthy(RT.recording:GetText():find("Checking", 1, true))
		assert.equal(2, #RT.people.items)
		SK.DB.settings.attView = "totals"
		RT:Refresh()
		assert.equal(2, #RT.totals.items)
		assert.equal("2d before", RT.BeforeText(1000 + 2 * 86400 + 5, 1000))
		assert.equal("40m before", RT.BeforeText(3400, 1000))
		assert.equal(0, #SK.errors)
	end)
end)

describe("v0.14.2 no progress gains", function()
	it("has no level or item level gain, and forgets the old history", function()
		local SK = setup()
		assert.is_nil(SK.RosterPlan.Gain)
		assert.is_nil(SK.RosterPlan.Record)
		local db = SK.DBM:Load({ rosterProgress = { x = { { d = 1, l = 2 } } } })
		assert.is_nil(db.rosterProgress)
	end)
end)
