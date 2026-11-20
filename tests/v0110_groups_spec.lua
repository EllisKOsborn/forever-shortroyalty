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

describe("v0.11.0 Invite & arrange", function()
	local SK, W, B, RG, e
	local function R(i) return "Player-1-R" .. i end
	before_each(function()
		SK, W = setup()
		B, RG = SK.RaidBoard, SK.RaidGroups
		e = B:Create("ony", W.now + 3600)
		local all = {}
		for i = 1, 12 do all[i] = R(i) end
		signUp(B, e.id, all, W.now)
		for i = 1, 6 do RG:Move(e.id, R(i), { kind = "group", n = 1 + (i > 5 and 1 or 0) }) end
		W.invited = {}
		_G.C_PartyInfo = { InviteUnit = function(name) W.invited[#W.invited + 1] = name end,
			ConvertToRaid = function() W.converted = true end }
		W.party = {}
		_G.UnitName = function(u)
			local i = tonumber(tostring(u):match("^party(%d)$"))
			if u == "player" then return "Pip" end
			return i and W.party[i] or nil
		end
		_G.UnitIsGroupLeader = function() return true end
	end)

	it("plans invites and moves without the game", function()
		local L = RG:Plan(e.id)
		local plan = RG.InvitePlan(L, { [R(2)] = true }, { [R(1)] = true, [R(2)] = true, [R(6)] = true }, W.player.guid)
		assert.same({ R(1), R(6) }, { plan[1].guid, plan[2].guid })
		local want = { a = 1, b = 1, c = 2 }
		assert.same({ op = "set", index = 3, group = 2 },
			RG.NextMove({ { index = 1, guid = "a", subgroup = 1 }, { index = 2, guid = "b", subgroup = 1 },
				{ index = 3, guid = "c", subgroup = 1 } }, want))
		-- group 2 full of people who belong elsewhere: swap
		local members = { { index = 1, guid = "c", subgroup = 1 } }
		for i = 2, 6 do members[i] = { index = i, guid = "x" .. i, subgroup = 2 } end
		assert.same({ op = "swap", a = 1, b = 2 }, RG.NextMove(members, { c = 2 }))
		assert.is_nil(RG.NextMove({ { index = 1, guid = "a", subgroup = 1 } }, { a = 1 }))
	end)

	it("one step per press: invite four, make it a raid, invite the rest, arrange", function()
		for i = 1, 12 do SK.DBM:Guild().members[R(i)].online = true end
		assert.truthy(RG:Setup(e.id):find("Invited 4", 1, true))
		assert.equal(4, #W.invited)
		W.party = { "Raider 1", "Raider 2" }
		W.raid = nil
		_G.GetNumGroupMembers = function() return W.raid and #W.raid or (#W.party > 0 and #W.party + 1 or 0) end
		assert.truthy(RG:Setup(e.id):find("Made it a raid", 1, true))
		assert.is_true(W.converted)
		W.raid = { { name = "Pip Hocus", guid = W.player.guid }, { name = "Raider 1", guid = R(1) }, { name = "Raider 6", guid = R(6) } }
		W.moves = {}
		_G.SetRaidSubgroup = function(i, g) W.moves[#W.moves + 1] = { i, g } end
		W.invited = {}
		local msg = RG:Setup(e.id)
		assert.truthy(msg:find("Arranging", 1, true))
		assert.equal(4, #W.invited) -- R2-R5 (R1 and R6 are in)
		assert.same({ 3, 2 }, W.moves[1]) -- everyone starts in group 1 here: Raider 6 (raid index 3) to group 2
		assert.is_not_nil(RG.arranging)
		W.combat = true
		RG:ArrangeStep()
		assert.is_nil(RG.arranging)
		assert.equal(0, #SK.errors)
	end)

	it("only for officers, not in combat", function()
		W.combat = true
		assert.equal("Not in combat.", RG:Setup(e.id))
		local SK2 = setup({ rank = "Member", rankIndex = 4 })
		assert.truthy(SK2.RaidGroups:Setup(e.id):find("Only officers", 1, true))
	end)
end)

describe("v0.11.0 Auto-fill", function()
	it("fills tanks, healers and DPS, keeps officers' picks, skips the away, benches the rest", function()
		local SK, W = H.load()
		W.member("Pip Hocus", W.player.guid, { rank = "Officer", rankIndex = 1 })
		local classes = { "WARRIOR", "WARRIOR", "WARRIOR", "PRIEST", "PRIEST", "PRIEST", "PRIEST", "MAGE", "ROGUE", "HUNTER",
			"MAGE", "ROGUE", "MAGE" }
		local roles = { "TANK", "TANK", "TANK", "HEALER", "HEALER", "HEALER", "HEALER", "DPS", "DPS", "DPS", "DPS", "DPS", "DPS" }
		for i = 1, #classes do W.member("Raider " .. i, "Player-1-R" .. i, { class = classes[i] }) end
		SK.Identity:ReadRoster()
		SK.Profile:BuildSelf()
		local B, RG = SK.RaidBoard, SK.RaidGroups
		local e = B:Create("barrow", W.now + 3600)
		local list = {}
		for i = 1, #classes do list["Player-1-R" .. i] = { s = i == 13 and "t" or "y", r = roles[i], u = W.now } end
		B:Get().signups[e.id] = list
		SK.DBM:Guild().profiles["Player-1-R11"] = { guid = "Player-1-R11", away = { d = { os.date("%Y-%m-%d", e.at) }, u = 1 } }
		RG:Move(e.id, "Player-1-R12", { kind = "group", n = 2 }) -- an officer's pick stays
		local placed, benched = RG:Fill(e.id)
		assert.equal(9, placed)
		local L = RG.Layout(B:Get(), e, B.LineUp(B:Get(), e, B.Ctx()))
		local roleCount = { TANK = 0, HEALER = 0, DPS = 0 }
		for n = 1, 2 do
			assert.equal(5, #L.groups[n])
			for _, r in ipairs(L.groups[n]) do roleCount[r.role] = roleCount[r.role] + 1 end
		end
		assert.same({ TANK = 2, HEALER = 3, DPS = 5 }, roleCount)
		assert.equal(2, (RG.SlotOf(B:Get(), e.id, "Player-1-R12")))
		assert.is_nil(B.PlaceOf(B:Get(), e.id, "Player-1-R11")) -- away: left out
		assert.equal("b", B.PlaceOf(B:Get(), e.id, "Player-1-R3")) -- third tank: bench
		assert.is_true(benched >= 2)
		assert.equal("melee", RG.DpsKind({ class = "SHAMAN", tree = "Enhancement" }))
		assert.equal("caster", RG.DpsKind({ class = "SHAMAN", tree = "Elemental" }))
		assert.equal(0, #SK.errors)
	end)
end)
