-- v0.11.0: raid groups ("split roster"): officers put players into groups
-- of five, Bench or Available, with late / leaving early / absent marks.
local H = require("tests.helpers.load")

local BOB, CAT = "Player-1-B", "Player-1-C"

local function setup(myRank)
	local SK, W = H.load()
	W.member("Pip Hocus", W.player.guid, myRank or { rank = "Officer", rankIndex = 1 })
	W.member("Bob Stone", BOB, { rank = "Raid Leader", rankIndex = 2, class = "WARRIOR" })
	W.member("Cat Fern", CAT, { rank = "Member", rankIndex = 4, class = "PRIEST" })
	for i = 1, 12 do W.member("Raider " .. i, "Player-1-R" .. i, { class = "MAGE" }) end
	SK.Identity:ReadRoster()
	SK.Profile:BuildSelf()
	return SK, W
end

local function signUp(B, id, guids, now)
	B:Get().signups[id] = B:Get().signups[id] or {}
	for _, g in ipairs(guids) do B:Get().signups[id][g] = { s = "y", r = "DPS", u = now } end
end

describe("v0.11.0 raid groups", function()
	local SK, W, B, RG, e
	before_each(function()
		SK, W = setup()
		B, RG = SK.RaidBoard, SK.RaidGroups
		e = B:Create("barrow", W.now + 3600)
		local all = { BOB, CAT }
		for i = 1, 12 do all[#all + 1] = "Player-1-R" .. i end
		signUp(B, e.id, all, W.now)
	end)

	it("has a group per five players the raid holds", function()
		assert.equal(2, RG.Groups("barrow"))
		assert.equal(4, RG.Groups("hyjal"))
		assert.equal(8, RG.Groups("ony"))
	end)

	it("moves players into groups, onto the Bench and back; a full group refuses", function()
		assert.is_true(RG:Move(e.id, CAT, { kind = "group", n = 2 }))
		assert.equal("i", B.PlaceOf(B:Get(), e.id, CAT))
		assert.equal(2, (RG.SlotOf(B:Get(), e.id, CAT)))
		for i = 1, 5 do assert.is_true(RG:Move(e.id, "Player-1-R" .. i, { kind = "group", n = 1 })) end
		assert.same({ false, "group 1 is full" }, { RG:Move(e.id, "Player-1-R6", { kind = "group", n = 1 }) })
		assert.is_false(RG:Move(e.id, BOB, { kind = "group", n = 3 })) -- Barrow Deeps has two groups
		-- dropping on someone swaps: R6 (Available) into group 1 in R1's place
		assert.is_true(RG:Move(e.id, "Player-1-R6", { kind = "group", n = 1 }, "Player-1-R1"))
		assert.equal("i", B.PlaceOf(B:Get(), e.id, "Player-1-R6"))
		assert.is_nil(B.PlaceOf(B:Get(), e.id, "Player-1-R1"))
		assert.equal(0, (RG.SlotOf(B:Get(), e.id, "Player-1-R1")))
		-- two players in groups swap groups
		assert.is_true(RG:Move(e.id, CAT, { kind = "group", n = 1 }, "Player-1-R2"))
		assert.equal(1, (RG.SlotOf(B:Get(), e.id, CAT)))
		assert.equal(2, (RG.SlotOf(B:Get(), e.id, "Player-1-R2")))
		assert.is_true(RG:Move(e.id, CAT, { kind = "bench" }))
		assert.equal("b", B.PlaceOf(B:Get(), e.id, CAT))
		assert.equal(0, (RG.SlotOf(B:Get(), e.id, CAT)))
		assert.is_true(RG:Move(e.id, CAT, { kind = "available" }))
		assert.is_nil(B.PlaceOf(B:Get(), e.id, CAT))
	end)

	it("marks late, leaving early, absent in turn; members can't arrange", function()
		RG:Move(e.id, CAT, { kind = "group", n = 1 })
		RG:CycleMark(e.id, CAT)
		assert.equal("l", select(2, RG.SlotOf(B:Get(), e.id, CAT)))
		RG:CycleMark(e.id, CAT)
		RG:CycleMark(e.id, CAT)
		assert.equal("a", select(2, RG.SlotOf(B:Get(), e.id, CAT)))
		RG:CycleMark(e.id, CAT)
		assert.equal("", select(2, RG.SlotOf(B:Get(), e.id, CAT)))
		local SK2 = setup({ rank = "Member", rankIndex = 4 })
		assert.is_false(SK2.RaidGroups:Move(e.id, CAT, { kind = "bench" }))
	end)

	it("lays out groups, bench and available from the line-up", function()
		RG:Move(e.id, CAT, { kind = "group", n = 2 })
		RG:Move(e.id, BOB, { kind = "bench" })
		RG:CycleMark(e.id, CAT)
		B:Get().signups[e.id]["Player-1-R12"].s = "n"
		local rows = B.LineUp(B:Get(), e, B.Ctx())
		local L = RG.Layout(B:Get(), e, rows)
		assert.equal(2, L.count)
		assert.equal(0, #L.groups[1])
		assert.equal(CAT, L.groups[2][1].guid)
		assert.equal("l", L.groups[2][1].mark)
		assert.equal(BOB, L.bench[1].guid)
		assert.equal(11, #L.available)
		assert.equal(1, #L.declined)
		assert.equal(1, L.marks.l)
	end)

	it("is shared in RB and checked against the roster", function()
		local sent = H.captureSends(SK)
		RG:Move(e.id, CAT, { kind = "group", n = 2 })
		W.advance(SK.RaidSync.CHANGE_DELAY + 1)
		SK.Sync:Flush()
		local gs
		for _, x in ipairs(sent) do if x.msg.t == "RB" and #x.msg.gs > 0 then gs = x.msg.gs[1] end end
		assert.equal(2, gs.n)
		assert.equal(CAT, gs.g)
		local function deliver(fields, sender, guid)
			SK.Sync:OnCommReceived(SK.PREFIX, H.peerMessage(SK, "RB", fields, guid), "GUILD", sender)
		end
		local id = e.id
		deliver({ gs = { { e = id, g = BOB, n = 1, m = "e", u = W.now + 1, by = BOB } } }, "Bob Stone", BOB)
		assert.same({ 1, "e" }, { RG.SlotOf(B:Get(), id, BOB) })
		deliver({ gs = { { e = id, g = BOB, n = 2, m = "", u = W.now + 2, by = CAT } } }, "Cat Fern", CAT)
		assert.same({ 1, "e" }, { RG.SlotOf(B:Get(), id, BOB) })
		deliver({ gs = { { e = id, g = BOB, n = 9, m = "", u = W.now + 3, by = BOB },
			{ e = id, g = BOB, n = 1, m = "x", u = W.now + 3, by = BOB }, "junk" } }, "Bob Stone", BOB)
		assert.same({ 1, "e" }, { RG.SlotOf(B:Get(), id, BOB) })
		assert.equal(0, #SK.errors)
	end)
end)

describe("v0.11.0 Groups tab", function()
	it("officers click a name then a group; drag and drop works; members see their group", function()
		local SK, W = setup()
		H.loadUI(SK)
		local B, RG, RT = SK.RaidBoard, SK.RaidGroups, SK.RaidsTab
		local e = B:Create("hyjal", W.now + 3600)
		signUp(B, e.id, { W.player.guid, CAT, BOB }, W.now)
		SK.DB.officer[W.player.guid] = true
		SK.DB.settings.raidsView = "groups"
		SK.MainFrame:Open("raids")
		assert.is_true(RT.grpPage:IsShown())
		assert.is_true(RT.grpBoxes[4]:IsShown())
		assert.is_false(RT.grpBoxes[5]:IsShown())
		-- click Cat in Available, then group 3
		local cat
		for _, r in ipairs(RT.grpAvail.items) do if r.guid == CAT then cat = r end end
		RT.grpAvail.opts.onClick(cat, "LeftButton")
		assert.equal(CAT, RT.carry.guid)
		local box3 = RT.grpBoxes[3]
		box3:GetScript("OnMouseUp")(box3, "LeftButton")
		assert.is_nil(RT.carry)
		assert.equal(3, (RG.SlotOf(B:Get(), e.id, CAT)))
		-- drag Bob onto the Bench
		local bob
		for _, r in ipairs(RT.grpAvail.items) do if r.guid == BOB then bob = r end end
		RT:StartCarry(bob, true)
		RT.grpBench.IsMouseOver = function() return true end
		RT.grpBench.IsVisible = function() return true end
		RT:StopDrag()
		assert.equal("b", B.PlaceOf(B:Get(), e.id, BOB))
		-- right-click marks
		RT:SlotClick({ guid = CAT }, nil, "RightButton")
		assert.equal("l", select(2, RG.SlotOf(B:Get(), e.id, CAT)))
		-- my own group shows on the Raids tab line
		RG:Move(e.id, W.player.guid, { kind = "group", n = 1 })
		assert.truthy(RT.MineText({ s = "y" }, "i", 1):find("group 1", 1, true))
		assert.truthy(RT.GroupsHint(false, 1):find("group 1", 1, true))
		assert.truthy(RT.SlotText({ name = "Cat Fern", class = "PRIEST", role = "HEALER", mark = "a" }):find("absent", 1, true))
		-- members can't pick anyone up
		SK.DB.officer[W.player.guid] = nil
		RT:StartCarry(bob, false)
		assert.is_nil(RT.carry)
		assert.equal(0, #SK.errors)
	end)
end)
