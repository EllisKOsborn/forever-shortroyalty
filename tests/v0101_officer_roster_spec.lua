-- v0.10.1: the officer roster (roles, notes, alt links, attendance %),
-- shared only between officers and raid leaders.
local H = require("tests.helpers.load")

local BOB, CAT, DAN = "Player-1-B", "Player-1-C", "Player-1-D"

local function setup(myRank)
	local SK, W = H.load()
	W.member("Pip Hocus", W.player.guid, myRank or { rank = "Officer", rankIndex = 1 })
	W.member("Bob Stone", BOB, { rank = "Raid Leader", rankIndex = 2, class = "WARRIOR" })
	W.member("Cat Fern", CAT, { rank = "Member", rankIndex = 4, class = "PRIEST" })
	W.member("Dan Moss", DAN, { rank = "Alt", rankIndex = 5, class = "MAGE" })
	SK.Identity:ReadRoster()
	SK.Profile:BuildSelf()
	return SK, W
end

local function deliver(SK, t, fields, sender, guid, dist)
	SK.Sync:OnCommReceived(SK.PREFIX, H.peerMessage(SK, t, fields, guid), dist or "WHISPER", sender)
end

describe("v0.10.1 officer roster data", function()
	local SK, W, OD
	before_each(function()
		SK, W = setup()
		OD = SK.OfficerDir
	end)

	it("officers set several roles, a note and an alt link; members can't", function()
		assert.is_true(OD:ToggleRole(CAT, "HEALER"))
		assert.is_true(OD:ToggleRole(CAT, "DPS"))
		assert.equal("Healer, DPS", OD.RolesText(OD:Get(), CAT))
		assert.equal("Heal DPS", OD.RolesText(OD:Get(), CAT, true))
		assert.is_true(OD:ToggleRole(CAT, "HEALER"))
		assert.equal("DPS", OD.RolesText(OD:Get(), CAT))
		assert.is_true(OD:Set("n", CAT, "  Great healer|cffff0000!|r\nAsk about Onyxia  "))
		assert.equal("Great healercffff0000!r Ask about Onyxia", OD.NoteOf(OD:Get(), CAT))
		assert.is_true(OD:Set("a", DAN, CAT))
		assert.equal(CAT, OD.AltOf(OD:Get(), DAN))
		assert.is_true(OD:Set("a", DAN, ""))
		assert.is_nil(OD.AltOf(OD:Get(), DAN))
		assert.is_true(OD:Set("n", CAT, string.rep("x", 400)))
		assert.equal(OD.NOTE_MAX, #OD.NoteOf(OD:Get(), CAT))
		local SK2 = setup({ rank = "Member", rankIndex = 4 })
		assert.is_false(SK2.OfficerDir:Set("n", CAT, "hi"))
	end)

	it("checks everything received", function()
		local dir, now = {}, W.now
		local lead = function(g) return g == BOB end
		local member = function(g) return g ~= "Player-9-X" end
		assert.is_true(OD.Merge(dir, "r:" .. CAT, { v = "TH", u = now, by = BOB }, now, lead, member))
		assert.same({ false, "not newer" }, { OD.Merge(dir, "r:" .. CAT, { v = "D", u = now, by = BOB }, now, lead, member) })
		assert.is_false(OD.Merge(dir, "r:" .. CAT, { v = "TT", u = now + 1, by = BOB }, now, lead, member))
		assert.is_false(OD.Merge(dir, "r:" .. CAT, { v = "X", u = now + 1, by = BOB }, now, lead, member))
		assert.is_false(OD.Merge(dir, "n:" .. CAT, { v = "a|Hitem", u = now, by = BOB }, now, lead, member))
		assert.is_false(OD.Merge(dir, "n:" .. CAT, { v = "hi", u = now, by = CAT }, now, lead, member))
		assert.is_false(OD.Merge(dir, "n:Player-9-X", { v = "hi", u = now, by = BOB }, now, lead, member))
		assert.is_false(OD.Merge(dir, "z:" .. CAT, { v = "hi", u = now, by = BOB }, now, lead, member))
		assert.is_false(OD.Merge(dir, "n:" .. CAT, { v = "hi", u = now + 3600, by = BOB }, now, lead, member))
		assert.is_true(OD.Merge(dir, "n:" .. CAT, { v = "hi", u = now, by = BOB }, now, lead, member))
	end)

	it("lists everyone with alts under their main and 30-day attendance", function()
		OD:Set("a", DAN, CAT)
		OD:ToggleRole(CAT, "HEALER")
		local att = { [CAT] = { full = 3, late = 1, missed = 1, bench = 2, pct = 80 } }
		local rows = OD.Rows(SK.DBM:Guild(), OD:Get(), nil, att)
		local names = {}
		for _, r in ipairs(rows) do names[#names + 1] = r.name end
		assert.same({ "Bob Stone", "Cat Fern", "Dan Moss", "Pip Hocus" }, names)
		assert.equal("Cat Fern", rows[3].mainName)
		assert.equal("officer", rows[3].altHow)
		assert.equal(80, rows[2].pct)
		assert.equal(5, rows[2].raids)
		assert.equal("Heal", rows[2].roles)
		assert.equal(1, #OD.Rows(SK.DBM:Guild(), OD:Get(), "heal", att))
		H.loadUI(SK)
		assert.equal("Attendance (30 days): 80% of 5 raids  ·  bench 2", SK.RosterTab.AttendanceText(rows[2], 30))
	end)
end)

describe("v0.10.1 officer roster sharing", function()
	local SK, W, OD, sent
	before_each(function()
		SK, W = setup()
		OD = SK.OfficerDir
		sent = H.captureSends(SK)
		SK.Identity:Member(BOB).addonSeen = W.now
		SK.Identity:Member(CAT).addonSeen = W.now -- a member with the addon: never sent to
	end)

	it("a change goes by whisper to officers online, not to members", function()
		OD:Set("n", CAT, "Bring flasks")
		W.advance(SK.OfficerSync.SHARE_DELAY + 1)
		SK.Sync:Flush()
		assert.equal(1, #sent)
		assert.equal("OR", sent[1].msg.t)
		assert.equal("WHISPER", sent[1].dist)
		assert.equal("Bob Stone", sent[1].target)
		assert.equal("Bring flasks", sent[1].msg.d["n:" .. CAT].v)
	end)

	it("takes entries only from officers, only by whisper, only as an officer", function()
		local d = { ["r:" .. CAT] = { v = "T", u = W.now, by = BOB } }
		deliver(SK, "OR", { d = d }, "Cat Fern", CAT)
		deliver(SK, "OR", { d = d }, "Bob Stone", BOB, "GUILD")
		assert.is_nil(OD.RolesOf(OD:Get(), CAT))
		deliver(SK, "OR", { d = d }, "Bob Stone", BOB)
		assert.same({ TANK = true }, OD.RolesOf(OD:Get(), CAT))
		local SK2 = setup({ rank = "Member", rankIndex = 4 })
		SK2.Sync:OnCommReceived(SK2.PREFIX, H.peerMessage(SK2, "OR", { d = d }, BOB), "WHISPER", "Bob Stone")
		assert.equal(0, SK2.Count(SK2.OfficerDir:Get()))
		deliver(SK, "OR", { d = { [1] = 2, x = "y", ["n:" .. CAT] = { v = {}, u = W.now, by = BOB } } }, "Bob Stone", BOB)
		deliver(SK, "OQ", { k = "all" }, "Bob Stone", BOB)
		assert.equal(0, #SK.errors)
	end)

	it("after login, officers ask each other and get what they're missing", function()
		OD:Set("n", CAT, "Bring flasks")
		W.advance(SK.OfficerSync.SHARE_DELAY + 1)
		SK.Sync:Flush()
		sent = H.captureSends(SK)
		SK.OfficerSync:SendQuery()
		SK.Sync:Flush()
		assert.equal("OQ", sent[1].msg.t)
		assert.is_number(sent[1].msg.k["n:" .. CAT])
		sent = H.captureSends(SK)
		deliver(SK, "OQ", { k = {} }, "Bob Stone", BOB)
		SK.Sync:Flush()
		assert.equal(1, #sent)
		assert.equal("Bring flasks", sent[1].msg.d["n:" .. CAT].v)
		sent = H.captureSends(SK)
		deliver(SK, "OQ", { k = { ["n:" .. CAT] = OD:Get()["n:" .. CAT].u } }, "Bob Stone", BOB)
		SK.Sync:Flush()
		assert.equal(0, #sent)
		deliver(SK, "OQ", { k = {} }, "Cat Fern", CAT)
		SK.Sync:Flush()
		assert.equal(0, #sent)
	end)
end)

describe("v0.10.1 Officers view on the Roster page (the planner since v0.13.0)", function()
	it("only officers with /sr officer see it", function()
		local SK, W = setup()
		H.loadUI(SK)
		SK.MainFrame:Open("roster")
		local R = SK.RosterTab
		assert.is_false(R.officerChip:IsShown())
		SK.DB.officer[W.player.guid] = true
		R:Refresh()
		assert.is_true(R.officerChip:IsShown())
		R.officerChip:GetScript("OnClick")(R.officerChip)
		assert.is_true(R.offPanel:IsShown())
		assert.is_false(R.list:IsShown())
		SK.DB.officer[W.player.guid] = nil
		R:Refresh()
		assert.is_false(R.offPanel:IsShown())
		assert.is_true(R.list:IsShown())
		assert.equal(0, #SK.errors)
	end)
end)
