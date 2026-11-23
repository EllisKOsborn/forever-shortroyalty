-- v0.16.7: the Raider check (guild rule: 80% attendance over two months;
-- owner: "attended 13 out of the last 16 raids", bench counts, Raider in
-- the planner and as the guild rank).
local H = require("tests.helpers.load")

local BOB, CAT, DAN, EVE = "Player-1-B", "Player-1-C", "Player-1-D", "Player-1-E"
local DAY = 86400

local function setup()
	local SK, W = H.load()
	W.member("Pip Hocus", W.player.guid, { rank = "Officer", rankIndex = 1 })
	W.member("Bob Stone", BOB, { rank = "Raider", rankIndex = 3, class = "WARRIOR", level = 60 })
	W.member("Cat Fern", CAT, { rank = "Member", rankIndex = 4, class = "PRIEST", level = 60 })
	W.member("Dan Moss", DAN, { rank = "Trial Raider", rankIndex = 5, class = "MAGE", level = 60 })
	W.member("Eve Moss", EVE, { rank = "Member", rankIndex = 4, class = "WARRIOR", level = 60 })
	SK.Identity:ReadRoster()
	SK.Profile:BuildSelf()
	return SK, W
end

-- 16 raids over 8 weeks (two a week). online(i) = { [guid] = true } at the
-- start of raid i; everyone listed in `signed` signed up "y".
local function raids(SK, now, signed, online, bench)
	local A = SK.Attendance
	local store = {}
	for i = 1, 16 do
		local at = now - i * 3.6 * DAY
		local ev = { id = "R" .. i, raid = "ony", at = at }
		local rec = A.NewCheck(ev, "Player-1-A", at)
		local su = {}
		for _, g in ipairs(signed) do su[g] = { s = "y" } end
		A.AddCheck(rec, at, online(i), {}, su)
		if bench and bench[i] then rec.bench[bench[i]] = { v = true, u = at } end
		rec.ended = at + A.LATE_FOR
		store[ev.id] = rec
	end
	return store
end

describe("v0.16.7 Raider check: counting", function()
	it("needs 80% of ALL raids in two months, bench counts, alts count for the main", function()
		local SK, W = setup()
		local Pr = SK.Promotion
		local now = W.now
		-- CAT: 13 of 16 (online except raids 1, 5, 9). DAN: signed every time
		-- but online only 12 times, plus one bench tick = 13. EVE: 12 of 16.
		local store = raids(SK, now, { CAT, DAN, EVE }, function(i)
			local o = {}
			if i ~= 1 and i ~= 5 and i ~= 9 then o[CAT] = true end
			if i > 4 then o[DAN] = true end
			if i > 4 then o[EVE] = true end
			return o
		end, { [2] = DAN })
		local c = Pr.Check(store, now, { [CAT] = { CAT }, [DAN] = { DAN }, [EVE] = { EVE }, [BOB] = { BOB } })
		assert.same({ 13, 16, 81, true }, { c[CAT].attended, c[CAT].raids, c[CAT].pct, c[CAT].ready })
		assert.same({ 13, true }, { c[DAN].attended, c[DAN].ready })
		assert.same({ 12, 75, false }, { c[EVE].attended, c[EVE].pct, c[EVE].ready })
		-- Not signed up at all counts as not attending.
		assert.same({ 0, false }, { c[BOB].attended, c[BOB].ready })
		-- An alt's raids count for the main (once per night).
		local both = Pr.Check(store, now, { [EVE] = { EVE, CAT } })
		assert.equal(15, both[EVE].attended) -- raid 1: neither was online
		assert.equal("13 of 16 raids (81%): ready for Raider", Pr.Text(c[CAT]))
		assert.equal("12 of 16 raids (75%)", Pr.Text(c[EVE]))
	end)

	it("isn't ready without two months of records or enough raids", function()
		local SK, W = setup()
		local Pr = SK.Promotion
		local all = raids(SK, W.now, { CAT }, function() return { [CAT] = true } end)
		-- Only the newest 4 raids recorded: 4 of 4 isn't enough.
		local recent = {}
		for i = 1, 4 do recent["R" .. i] = all["R" .. i] end
		local c = Pr.Check(recent, W.now, { [CAT] = { CAT } })
		assert.same({ 4, 4, false, false }, { c[CAT].attended, c[CAT].raids, c[CAT].covered, c[CAT].ready })
		assert.truthy(Pr.Text(c[CAT]):find("not two months of records yet", 1, true))
		-- Records reach back far enough, but only 6 raids in the window.
		local few = {}
		for i = 1, 6 do few["R" .. i] = all["R" .. i] end
		few.old = { v = 2, id = "old", raid = "ony", at = W.now - 59 * DAY, signed = {}, o = {}, w = {}, pb = {},
			people = {}, bench = {}, snaps = 1 }
		c = Pr.Check(few, W.now, { [CAT] = { CAT } })
		assert.is_true(c[CAT].covered)
		assert.is_false(c[CAT].ready)
		assert.truthy(Pr.Text(c[CAT]):find("fewer than 8 raids", 1, true))
		-- Raids older than 60 days drop out; a raid that hasn't started yet doesn't count.
		all.future = { v = 2, id = "future", raid = "ony", at = W.now + DAY, signed = {}, o = {}, w = {}, pb = {},
			people = {}, bench = {}, snaps = 0 }
		all.ancient = { v = 2, id = "ancient", raid = "ony", at = W.now - 70 * DAY, signed = {}, o = {}, w = {},
			pb = {}, people = {}, bench = {}, snaps = 1 }
		assert.equal(16, #Pr.Raids(all, W.now))
	end)
end)

describe("v0.16.7 Raider check: the guild rank", function()
	it("finds the Raider rank and how many steps someone is below it", function()
		local SK = setup()
		local Pr = SK.Promotion
		local members = SK.DBM:Guild().members
		assert.equal(3, Pr.RaiderRank(members)) -- "Raider", not "Trial Raider"
		assert.equal(1, Pr.StepsToRaider(members[CAT], 3))
		assert.equal(2, Pr.StepsToRaider(members[DAN], 3))
		assert.equal(0, Pr.StepsToRaider(members[BOB], 3))
		assert.equal(0, Pr.StepsToRaider(members[SK.Compat.PlayerGUID()], 3)) -- officers are above it
		assert.is_nil(Pr.RaiderRank({ { rank = "Trial Raider", rankIndex = 5 }, { rank = "Member", rankIndex = 4 } }))
		assert.equal(2, Pr.RaiderRank({ { rank = "Core Raiders", rankIndex = 2 }, { rank = "Member", rankIndex = 4 } }))
		assert.is_true(Pr.CanPromoteTo({ rankIndex = 1 }, 3))
		assert.is_false(Pr.CanPromoteTo({ rankIndex = 3 }, 3))
	end)
end)

describe("v0.16.7 Raider check: the planner", function()
	local SK, W, promoted
	before_each(function()
		SK, W = setup()
		H.loadUI(SK)
		SK.DB.officer[W.player.guid] = true
		promoted = {}
		_G.C_GuildInfo.Promote = function(name) promoted[#promoted + 1] = name end
		local guild = SK.DBM:Guild()
		guild.attendance = raids(SK, W.now, { CAT, DAN }, function(i)
			return { [CAT] = i > 3 or nil, [DAN] = true }
		end)
	end)
	after_each(function() _G.C_GuildInfo.Promote = nil end)

	it("marks who's ready, prints the officer notice, and makes them Raider", function()
		local R, Pr = SK.RosterTab, SK.Promotion
		local rows = R:PlanRows()
		local by = {}
		for _, r in ipairs(rows) do by[r.guid] = r end
		assert.is_true(by[CAT].promo.ready)
		assert.is_true(by[CAT].promo.todo)
		assert.equal(1, by[CAT].promo.steps)
		assert.equal(2, #R.promoReady)
		local text = Pr.NoticeText(R.promoReady)
		assert.equal("2 ready for Raider (80% of raids over two months): Cat Fern, Dan Moss. "
			.. "Roster > Officers to make them Raider.", text)
		-- The status menu starts with Make Raider.
		local items = R.CellItems(by[CAT], "status")
		assert.truthy(items[1].text:find("Make Raider", 1, true))
		assert.equal(5, #items)
		local ok, msg = Pr:MakeRaider(by[CAT])
		assert.is_true(ok)
		assert.equal("r", SK.OfficerDir.StatusOf(SK.OfficerDir:Get(), CAT))
		assert.same({ "Cat Fern" }, promoted)
		assert.truthy(msg:find("promote them to Raider", 1, true))
		-- Pressing again before the roster shows the new rank does nothing.
		msg = select(2, Pr:MakeRaider(by[CAT]))
		assert.same({ "Cat Fern" }, promoted)
		assert.truthy(msg:find("still waiting", 1, true))
		-- Two ranks below: one per press.
		msg = select(2, Pr:MakeRaider(by[DAN]))
		assert.truthy(msg:find("1 more to Raider", 1, true))
		-- Once they're Raider in both places, nothing is left to do.
		local guild = SK.DBM:Guild()
		guild.members[CAT].rank, guild.members[CAT].rankIndex = "Raider", 3
		rows = R:PlanRows()
		for _, r in ipairs(rows) do by[r.guid] = r end
		assert.is_true(by[CAT].promo.ready)
		assert.is_false(by[CAT].promo.todo)
		assert.equal(4, #R.CellItems(by[CAT], "status"))
	end)

	it("doesn't promote when my rank can't, but still sets the status", function()
		local guild = SK.DBM:Guild()
		guild.members[SK.Compat.PlayerGUID()].rankIndex = 4
		local by = {}
		for _, r in ipairs(SK.RosterTab:PlanRows()) do by[r.guid] = r end
		local ok, msg = SK.Promotion:MakeRaider(by[CAT])
		assert.is_true(ok)
		assert.same({}, promoted)
		assert.equal("r", SK.OfficerDir.StatusOf(SK.OfficerDir:Get(), CAT))
		assert.truthy(msg:find("can't promote", 1, true))
	end)

	it("shows the check on the Character page and in the summary line", function()
		SK.CharacterTab:ShowCharacter(CAT)
		local found
		local C = SK.CharacterTab
		local col = type(C.colA.sections) == "table" and C.colA.sections[1] and C.colA or C.colB
		for _, row in ipairs(col.sections[1].rows) do
			if row.label == "Raider check" then found = row.value end
		end
		assert.equal("13 of 16 raids (81%): ready for Raider", found)
		SK.DB.settings.roster.officer = true
		SK.MainFrame:Open("roster")
		SK.RosterTab:Refresh()
		assert.truthy(SK.RosterTab.planSummary:GetText():find("2 ready for Raider", 1, true))
	end)
end)
