-- v0.11.0: boss assignments (blocks per boss, job lines with players).
local H = require("tests.helpers.load")

local BOB, CAT = "Player-1-B", "Player-1-C"

local function setup(myRank)
	local SK, W = H.load()
	W.member("Pip Hocus", W.player.guid, myRank or { rank = "Officer", rankIndex = 1 })
	W.member("Bob Stone", BOB, { rank = "Raid Leader", rankIndex = 2, class = "WARRIOR" })
	W.member("Cat Fern", CAT, { rank = "Member", rankIndex = 4, class = "PRIEST" })
	SK.Identity:ReadRoster()
	SK.Profile:BuildSelf()
	return SK, W
end

describe("v0.11.0 boss assignments", function()
	local SK, W, B, RA, e
	before_each(function()
		SK, W = setup()
		B, RA = SK.RaidBoard, SK.RaidAssign
		e = B:Create("ony", W.now + 3600)
		B:Get().signups[e.id] = { [CAT] = { s = "y", r = "HEALER", u = W.now }, [BOB] = { s = "y", r = "TANK", u = W.now } }
		B:SetPlace(e.id, CAT, "i")
		B:SetPlace(e.id, BOB, "i")
	end)

	it("officers add bosses, jobs and players; everyone sees their jobs", function()
		local key = assert(RA:AddBlock(e.id, "  Onyxia|cffff0000  "))
		local blocks = RA.Blocks(B:Get(), e.id)
		assert.equal("Onyxiacffff0000", blocks[1].name)
		assert.is_true(RA:AddLine(e.id, key, "mt"))
		assert.is_true(RA:AddLine(e.id, key, "th"))
		assert.is_false(RA:AddLine(e.id, key, "dance"))
		assert.is_true(RA:TogglePlayer(e.id, key, 1, BOB))
		assert.is_true(RA:TogglePlayer(e.id, key, 2, CAT))
		assert.same({ "Main tank on Onyxiacffff0000" }, RA.JobsOf(B:Get(), e.id, BOB))
		assert.is_true(RA:TogglePlayer(e.id, key, 2, CAT)) -- off again
		assert.same({}, RA.JobsOf(B:Get(), e.id, CAT))
		assert.is_true(RA:RemoveLine(e.id, key, 1))
		assert.equal(1, #RA.Blocks(B:Get(), e.id)[1].lines)
		assert.is_true(RA:DeleteBlock(e.id, key))
		assert.equal(0, #RA.Blocks(B:Get(), e.id))
		assert.is_nil((RA:AddBlock(e.id, "   ")))
		local SK2 = setup({ rank = "Member", rankIndex = 4 })
		assert.is_nil((SK2.RaidAssign:AddBlock(e.id, "Onyxia")))
	end)

	it("copies last raid's bosses and jobs, keeping only players In now", function()
		local old = B:Create("ony", W.now + 1800)
		local key = RA:AddBlock(old.id, "Onyxia")
		RA:AddLine(old.id, key, "mt")
		RA:TogglePlayer(old.id, key, 1, BOB)
		RA:TogglePlayer(old.id, key, 1, W.player.guid) -- not In the new raid
		assert.equal(1, RA:CopyLast(e.id))
		local blocks = RA.Blocks(B:Get(), e.id)
		assert.equal("Onyxia", blocks[1].name)
		assert.same({ BOB }, blocks[1].lines[1].g)
		local other = B:Create("hyjal", W.now + 7200)
		assert.equal(0, (RA:CopyLast(other.id)))
	end)

	it("is shared in RB; only officers' blocks, only known jobs, no links", function()
		local sent = H.captureSends(SK)
		local key = RA:AddBlock(e.id, "Onyxia")
		RA:AddLine(e.id, key, "int")
		W.advance(SK.RaidSync.CHANGE_DELAY + 1)
		SK.Sync:Flush()
		local as
		for _, x in ipairs(sent) do if x.msg.t == "RB" and #x.msg.as > 0 then as = x.msg.as[#x.msg.as] end end
		assert.equal("Onyxia", as.name)
		assert.equal("int", as.lines[1].t)
		local function deliver(b, sender, guid)
			SK.Sync:OnCommReceived(SK.PREFIX, H.peerMessage(SK, "RB", { as = { b } }, guid), "GUILD", sender)
		end
		local good = { e = e.id, k = "bob:1", name = "Trash", o = 5, lines = { { t = "cd", g = { CAT } } }, u = W.now, by = BOB }
		deliver(good, "Bob Stone", BOB)
		assert.equal("Trash", B:Get().assign[e.id]["bob:1"].name)
		deliver({ e = e.id, k = "cat:1", name = "Mine", o = 1, lines = {}, u = W.now, by = CAT }, "Cat Fern", CAT)
		assert.is_nil(B:Get().assign[e.id]["cat:1"])
		deliver({ e = e.id, k = "bob:2", name = "|Hitem:1|h[x]|h", o = 1, lines = {}, u = W.now, by = BOB }, "Bob Stone", BOB)
		deliver({ e = e.id, k = "bob:3", name = "X", o = 1, lines = { { t = "dance", g = {} } }, u = W.now, by = BOB }, "Bob Stone", BOB)
		deliver({ e = e.id, k = "bob:4", name = "X", o = 1, lines = { { t = "cd", g = { 1, 2, 3, 4, 5, 6 } } }, u = W.now, by = BOB },
			"Bob Stone", BOB)
		assert.is_nil(B:Get().assign[e.id]["bob:2"])
		assert.is_nil(B:Get().assign[e.id]["bob:3"])
		assert.is_nil(B:Get().assign[e.id]["bob:4"])
		assert.equal(0, #SK.errors)
	end)

	it("the Assignments tab: add a boss, a job, put a player on it", function()
		H.loadUI(SK)
		SK.DB.officer[W.player.guid] = true
		SK.DB.settings.raidsView = "assign"
		SK.MainFrame:Open("raids")
		local RT = SK.RaidsTab
		assert.is_true(RT.asgPage:IsShown())
		RT.asgName:SetText("Onyxia")
		RT:AddBoss()
		assert.is_not_nil(RT.asgBlock)
		RT.asgTask:Choose("mt")
		RT.asgLines.opts.onClick({ index = 1 }, "LeftButton")
		assert.equal(1, RT.asgLine)
		local bob
		for _, r in ipairs(RT.asgIn.items) do if r.guid == BOB then bob = r end end
		RT.asgIn.opts.onClick(bob)
		assert.same({ "Main tank on Onyxia" }, RA.JobsOf(B:Get(), e.id, BOB))
		assert.truthy(RT.MineText({ s = "y" }, "i", 2, { "Main tank on Onyxia" }):find("Main tank on Onyxia", 1, true))
		SK.DB.officer[W.player.guid] = nil
		RT:Refresh()
		assert.is_false(RT.asgAdd:IsShown())
		assert.equal(0, #SK.errors)
	end)
end)
