-- v0.10.0: the raid roster (officers put signed-up players In or on the
-- Bench, everyone sees it) and the Discord bridge without any program
-- (Copy for Discord, Import sign-ups from Discord).
local H = require("tests.helpers.load")

local BOB, CAT, DAN, EVE = "Player-1-B", "Player-1-C", "Player-1-D", "Player-1-E"

local function setup(myRank)
	local SK, W = H.load()
	W.member("Pip Hocus", W.player.guid, myRank or { rank = "Officer", rankIndex = 1 })
	W.member("Bob Stone", BOB, { rank = "Raid Leader", rankIndex = 2, class = "WARRIOR" })
	W.member("Cat Fern", CAT, { rank = "Member", rankIndex = 4, class = "PRIEST" })
	W.member("Dan Moss", DAN, { rank = "Member", rankIndex = 4, class = "MAGE" })
	W.member("Eve Moss", EVE, { rank = "Member", rankIndex = 4, class = "ROGUE" })
	SK.Identity:ReadRoster()
	SK.Profile:BuildSelf()
	return SK, W
end

local function deliver(SK, t, fields, sender, guid, dist)
	SK.Sync:OnCommReceived(SK.PREFIX, H.peerMessage(SK, t, fields, guid), dist or "GUILD", sender)
end

describe("v0.10.0 raid roster: In and Bench", function()
	local SK, W, B, e
	before_each(function()
		SK, W = setup()
		B = SK.RaidBoard
		e = B:Create("ony", W.now + 3600)
		local list = { [CAT] = { s = "y", r = "HEALER", u = W.now }, [DAN] = { s = "y", r = "DPS", u = W.now },
			[EVE] = { s = "t", r = "DPS", u = W.now } }
		B:Get().signups[e.id] = list
	end)

	it("officers put people In or on the Bench; members can't", function()
		assert.is_true(B:SetPlace(e.id, CAT, "i"))
		assert.is_true(B:SetPlace(e.id, DAN, "b"))
		assert.equal("i", B.PlaceOf(B:Get(), e.id, CAT))
		assert.equal("b", B.PlaceOf(B:Get(), e.id, DAN))
		assert.is_true(B:SetPlace(e.id, DAN, "-"))
		assert.is_nil(B.PlaceOf(B:Get(), e.id, DAN))
		assert.is_false(B:SetPlace(e.id, DAN, "maybe"))
		local SK2, W2 = setup({ rank = "Member", rankIndex = 4 })
		local e2 = SK2.RaidBoard.MergeEvent(SK2.RaidBoard:Get(), { id = BOB .. ":1", by = BOB, c = 1, raid = "ony",
			at = W2.now + 60, u = W2.now }, W2.now, function() return true end)
		assert.is_true(e2)
		assert.is_false(SK2.RaidBoard:SetPlace(BOB .. ":1", CAT, "i"))
	end)

	it("the line-up puts In first, then Bench, and counts the people In by role", function()
		B:SetPlace(e.id, CAT, "i")
		B:SetPlace(e.id, EVE, "b")
		local rows, s = B.LineUp(B:Get(), e, B.Ctx())
		assert.equal(CAT, rows[1].guid)
		assert.equal(EVE, rows[2].guid)
		assert.equal(DAN, rows[3].guid)
		assert.equal(1, s.placedIn)
		assert.equal(1, s.placedBench)
		assert.equal("In 1 / 40: Tanks 0  ·  Healers 1  ·  DPS 0  ·  Bench 1", B.CountsText(s))
		assert.truthy(B.Text(e, rows, s):find("Cat Fern · Signed up · In", 1, true))
	end)

	it("everyone sees their own place", function()
		H.loadUI(SK)
		assert.truthy(SK.RaidsTab.MineText({ s = "y", r = "DPS" }, "i"):find("You're in", 1, true))
		assert.truthy(SK.RaidsTab.MineText({ s = "y" }, "b"):find("You're on the bench", 1, true))
		assert.is_nil(SK.RaidsTab.MineText({ s = "y" }, nil):find("bench", 1, true))
		B:Get().signups[e.id][W.player.guid] = { s = "y", u = W.now }
		B:SetPlace(e.id, W.player.guid, "b")
		local o = SK.Overview.Build(SK.DBM:Guild(), W.now)
		assert.equal("b", o.nextRaid.place)
		assert.truthy(SK.OverviewTab.RaidText(o):find("on the bench", 1, true))
	end)

	it("choices are shared, checked against the roster, and count in the digest", function()
		local sent = H.captureSends(SK)
		local d1 = B.Digest(B:Get())[e.id]
		B:SetPlace(e.id, CAT, "i")
		assert.are_not.equal(d1, B.Digest(B:Get())[e.id])
		W.advance(SK.RaidSync.CHANGE_DELAY + 1)
		SK.Sync:Flush()
		local rb
		for _, x in ipairs(sent) do if x.msg.t == "RB" and #x.msg.pk > 0 then rb = x.msg end end
		assert.same({ e = e.id, g = CAT, v = "i", u = W.now - SK.RaidSync.CHANGE_DELAY - 1, by = W.player.guid }, rb.pk[1])

		-- received: an officer's choice, relayed by a member, is fine
		deliver(SK, "RB", { pk = { { e = e.id, g = DAN, v = "b", u = W.now, by = BOB } } }, "Cat Fern", CAT)
		assert.equal("b", B.PlaceOf(B:Get(), e.id, DAN))
		-- a member's own "choice" isn't
		deliver(SK, "RB", { pk = { { e = e.id, g = EVE, v = "i", u = W.now, by = CAT } } }, "Cat Fern", CAT)
		assert.is_nil(B.PlaceOf(B:Get(), e.id, EVE))
		-- junk
		deliver(SK, "RB", { pk = { { e = e.id, g = EVE, v = "x", u = W.now, by = BOB }, "x", { e = {} } } }, "Bob Stone", BOB)
		assert.is_nil(B.PlaceOf(B:Get(), e.id, EVE))
		assert.equal(0, #SK.errors)
	end)

	it("officers click a name to go In, Bench, undecided; members open the character", function()
		H.loadUI(SK)
		SK.DB.officer[W.player.guid] = true
		SK.MainFrame:Open("raids")
		local RT = SK.RaidsTab
		RT.selected = e.id
		local row = { guid = CAT }
		RT.lineup.opts.onClick(row, "LeftButton")
		assert.equal("i", B.PlaceOf(B:Get(), e.id, CAT))
		RT.lineup.opts.onClick({ guid = CAT, place = "i" }, "LeftButton")
		assert.equal("b", B.PlaceOf(B:Get(), e.id, CAT))
		RT.lineup.opts.onClick({ guid = CAT, place = "b" }, "LeftButton")
		assert.is_nil(B.PlaceOf(B:Get(), e.id, CAT))
		SK.DB.officer[W.player.guid] = nil
		RT.lineup.opts.onClick({ guid = CAT }, "LeftButton")
		assert.is_nil(B.PlaceOf(B:Get(), e.id, CAT))
		assert.equal("character", SK.MainFrame.current)
		assert.equal(0, #SK.errors)
	end)
end)

describe("v0.10.0 Discord without a program", function()
	local SK, W, B, e
	before_each(function()
		SK, W = setup()
		B = SK.RaidBoard
		e = B:Create("ony", W.now + 3600)
	end)

	it("Copy for Discord: time in each reader's zone, names by role, In and Bench", function()
		B:Get().signups[e.id] = { [CAT] = { s = "y", r = "HEALER", u = W.now }, [DAN] = { s = "y", r = "DPS", u = W.now },
			[EVE] = { s = "n", u = W.now } }
		local rows, s = B.LineUp(B:Get(), e, B.Ctx())
		local text = B.DiscordText(e, rows, s)
		assert.truthy(text:find("**Onyxia's Lair (40)**: <t:" .. string.format("%d", e.at) .. ":F>", 1, true))
		assert.truthy(text:find("**Healers (1):** Cat Fern", 1, true))
		assert.truthy(text:find("**DPS (1):** Dan Moss", 1, true))
		assert.truthy(text:find("**Can't come (1):** Eve Moss", 1, true))
		assert.is_nil(text:find("|c", 1, true))
		B:SetPlace(e.id, CAT, "i")
		B:SetPlace(e.id, DAN, "b")
		rows, s = B.LineUp(B:Get(), e, B.Ctx())
		text = B.DiscordText(e, rows, s)
		assert.truthy(text:find("**In, Healers (1):** Cat Fern", 1, true))
		assert.truthy(text:find("**Bench (1):** Dan Moss", 1, true))
	end)

	local members
	before_each(function()
		members = {}
		for guid, m in pairs(SK.DBM:Guild().members) do members[guid] = { name = m.name } end
	end)

	it("reads a pasted sign-up list: headings, names, first names, statuses", function()
		local text = table.concat({
			"Onyxia's Lair - Friday 20:00",
			":shield: Tanks (1)",
			"1 Bob Stone",
			"Healers",
			"<:priest:123> Cat",
			"DPS (2)",
			"Dan Moss, Eve Moss",
			"Tentative",
			"Zed Unknown",
			"pip hocus - tank late",
			"Absence",
		}, "\n")
		local r = B.ParseImport(text, members)
		local got = {}
		for _, x in ipairs(r.entries) do got[x.guid] = x end
		assert.same({ guid = BOB, s = "y", r = "TANK" }, got[BOB])
		assert.same({ guid = CAT, s = "y", r = "HEALER" }, got[CAT])
		assert.same({ guid = DAN, s = "y", r = "DPS" }, got[DAN])
		assert.same({ guid = EVE, s = "y", r = "DPS" }, got[EVE])
		assert.same({ guid = W.player.guid, s = "y", r = "TANK" }, got[W.player.guid]) -- its own words win
		assert.equal(5, #r.entries)
		assert.same({ "Onyxia's Lair - Friday 20:00", "Zed Unknown" }, r.unmatched)
	end)

	it("a first name shared by two members isn't guessed; can't come and tentative work", function()
		local r = B.ParseImport("Moss\nDan Moss - can't make it\nEve Moss (tentative)", members)
		assert.equal(2, #r.entries)
		assert.same({ guid = DAN, s = "n" }, r.entries[1])
		assert.same({ guid = EVE, s = "t" }, r.entries[2])
		assert.same({ "Moss" }, r.unmatched)
	end)

	it("imports as the officer, keeping sign-ups players made in game themselves", function()
		local list = { [CAT] = { s = "n", u = W.now } } -- Cat said can't come in game
		B:Get().signups[e.id] = list
		local parsed = B.ParseImport("Tanks\nBob Stone\nHealers\nCat Fern", members)
		local added, updated, kept = B:Import(e.id, parsed.entries)
		assert.same({ 1, 0, 1 }, { added, updated, kept })
		assert.equal("n", list[CAT].s)
		assert.same({ s = "y", r = "TANK", u = W.now, b = W.player.guid }, list[BOB])
		-- importing again changes nothing; a new role updates
		assert.same({ 0, 0, 1 }, { B:Import(e.id, parsed.entries) })
		assert.same({ 0, 1, 0 }, { B:Import(e.id, { { guid = BOB, s = "t" } }) })
		local SK2 = setup({ rank = "Member", rankIndex = 4 })
		assert.is_nil(SK2.RaidBoard:Import(e.id, parsed.entries))
	end)

	it("an imported sign-up is only accepted from an officer", function()
		local board = B.New()
		board.events.x = { id = "x" }
		local member = function() return true end
		local lead = function(g) return g == BOB end
		assert.is_true(B.MergeSignup(board, { e = "x", g = CAT, s = "y", u = W.now, b = BOB }, W.now, member, lead))
		assert.is_false(B.MergeSignup(board, { e = "x", g = DAN, s = "y", u = W.now, b = CAT }, W.now, member, lead))
		assert.is_true(B.MergeSignup(board, { e = "x", g = DAN, s = "y", u = W.now }, W.now, member, lead))
		assert.equal(BOB, board.signups.x[CAT].b)
	end)

	it("the officer's paste box imports and says what it did", function()
		H.loadUI(SK)
		SK.DB.officer[W.player.guid] = true
		SK.MainFrame:Open("raids")
		local RT = SK.RaidsTab
		RT.selected = e.id
		RT:ImportDiscord()
		local D = SK.DebugWindow
		assert.is_true(D.asking)
		local msg = D.onSubmit("Healers\nCat Fern\nNobody Here")
		assert.truthy(msg:find("Added 1, updated 0", 1, true))
		assert.truthy(msg:find("Nobody Here", 1, true))
		assert.equal("HEALER", B:Get().signups[e.id][CAT].r)
		D:ShowText("x", "y")
		assert.is_false(D.asking)
		local names = {}
		for _, it in ipairs(RT:DetailOptions()) do names[#names + 1] = it.text end
		assert.same({ "Copy the line-up as text", "Copy for Discord", "Import sign-ups from Discord", "Cancel this raid" }, names)
		RT:CopyDiscord()
		assert.equal(0, #SK.errors)
	end)
end)
