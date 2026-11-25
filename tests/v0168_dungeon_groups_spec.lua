-- v0.16.8: dungeon groups (owner: "create dungeon groups as well - for UBRS
-- being the main one"). Owner's answers: anyone can make one, UBRS only,
-- raids only count for attendance and the Raider check, no soft reserves.
local H = require("tests.helpers.load")

local BOB, CAT, DAN, EVE = "Player-1-B", "Player-1-C", "Player-1-D", "Player-1-E"

-- The player is a plain member unless `rank` says otherwise.
local function setup(rank)
	local SK, W = H.load()
	W.now = os.time({ year = 2026, month = 12, day = 2, hour = 15 })
	W.member("Pip", W.player.guid, rank or { rank = "Member", rankIndex = 4 })
	W.member("Bob", BOB, { rank = "Officer", rankIndex = 1 })
	W.member("Cat", CAT, { rank = "Member", rankIndex = 4 })
	W.member("Dan", DAN, { rank = "Member", rankIndex = 4 })
	W.member("Eve", EVE, { rank = "Member", rankIndex = 4 })
	SK.Identity:ReadRoster()
	SK.Profile:BuildSelf()
	return SK, W
end

describe("v0.16.8 dungeon groups: the rules", function()
	it("knows UBRS (10 players) as a dungeon and never mixes it with raids", function()
		local SK = setup()
		local B = SK.RaidBoard
		local r = B.Raid("ubrs")
		assert.same({ "Upper Blackrock Spire", "UBRS", 10, true }, { r.name, r.short, r.size, r.dungeon })
		assert.is_true(B.IsDungeon({ raid = "ubrs" }))
		assert.is_false(B.IsDungeon({ raid = "ony" }))
		assert.is_false(B.IsDungeon({ raid = "tbd", rs = "" }))
		assert.is_false(B.IsDungeon({ raid = "ony", rs = "ony,ubrs" }))
		assert.equal("dungeon group", B.Kind({ raid = "ubrs" }))
		assert.equal(2, SK.RaidGroups.Groups("ubrs"))
		-- Picking a dungeon drops the raids, and the other way round.
		H.loadUI(SK)
		local RT = SK.RaidsTab
		assert.same({ "ubrs" }, RT.ToggleKey({ "hyjal", "ony" }, "ubrs"))
		assert.same({ "ony" }, RT.ToggleKey({ "ubrs" }, "ony"))
	end)

	it("lets a member make a dungeon group, not a raid, at most 3 coming up", function()
		local SK, W = setup()
		local B = SK.RaidBoard
		assert.is_nil((B:Create({ "ony" }, W.now + 3600)))
		local _, why = B:Create({}, W.now + 3600)
		assert.truthy(why:find("dungeon group", 1, true))
		for i = 1, 3 do assert.truthy(B:Create({ "ubrs" }, W.now + i * 3600)) end
		local e, why2 = B:Create("ubrs", W.now + 5 * 3600)
		assert.is_nil(e)
		assert.truthy(why2:find("3 dungeon groups", 1, true))
		-- A weekly series counts too.
		local SK2, W2 = setup()
		local list, why3 = SK2.RaidBoard:CreateSeries({ "ubrs" }, W2.now + 3600, 4)
		assert.is_nil(list)
		assert.truthy(why3:find("only room for 3", 1, true))
	end)

	it("lets the maker (and officers) run their group, nobody else", function()
		local SK, W = setup()
		local B, RG, RA = SK.RaidBoard, SK.RaidGroups, SK.RaidAssign
		local e = B:Create({ "ubrs" }, W.now + 3600)
		assert.is_true(B.CanManage(e.id))
		assert.is_true(B:SetPlace(e.id, CAT, "i"))
		assert.is_true((RG:Move(e.id, CAT, { kind = "group", n = 1 })))
		assert.truthy((RA:AddBlock(e.id, "Rend")))
		-- It stays a dungeon group: no raid instances, even from an officer.
		local ok, why = B:SetRaids(e.id, { "ony" })
		assert.is_false(ok)
		assert.truthy(why:find("only hold dungeons", 1, true))
		-- Someone else's group: no.
		local isLead = function(g) return B.CanLead(g) end
		local isMember = function(g) return SK.Identity:IsMember(g) end
		assert.is_false(B.MayManage(B:Get(), e.id, CAT, isLead, isMember))
		assert.is_true(B.MayManage(B:Get(), e.id, BOB, isLead, isMember))
		assert.is_true(B:Cancel(e.id))
		-- A raid made by an officer: the member can't change it.
		local board = B:Get()
		board.events["Player-1-B:5"] = { id = "Player-1-B:5", by = BOB, c = 5, raid = "ony", at = W.now + 7200, u = 5 }
		assert.is_false(B.CanManage("Player-1-B:5"))
		assert.is_false((B:SetPlace("Player-1-B:5", CAT, "i")))
		assert.is_false((B:Cancel("Player-1-B:5")))
	end)

	it("accepts a member's dungeon group from another game, not a member's raid", function()
		local SK, W = setup()
		local B, RG = SK.RaidBoard, SK.RaidGroups
		local board = B.New()
		local isLead = function(g) return B.CanLead(g) end
		local isMember = function(g) return SK.Identity:IsMember(g) end
		local function ev(c, raid, extra)
			local e = { id = CAT .. ":" .. c, by = CAT, c = c, raid = raid, at = W.now + c, u = W.now }
			for k, v in pairs(extra or {}) do e[k] = v end
			return e
		end
		assert.is_true((B.MergeEvent(board, ev(1, "ubrs"), W.now, isLead, isMember)))
		local ok, why = B.MergeEvent(board, ev(2, "ony"), W.now, isLead, isMember)
		assert.is_false(ok)
		assert.equal("not an officer or raid leader", why)
		-- Changed by someone else who isn't an officer: no. By an officer: yes.
		assert.is_false((B.MergeEvent(board, ev(1, "ubrs", { u = W.now + 1, eb = DAN }), W.now, isLead, isMember)))
		assert.is_true((B.MergeEvent(board, ev(1, "ubrs", { u = W.now + 2, eb = BOB, x = true }), W.now, isLead, isMember)))
		-- At most 3 live groups per member.
		for c = 3, 5 do assert.is_true((B.MergeEvent(board, ev(c, "ubrs"), W.now, isLead, isMember))) end
		ok, why = B.MergeEvent(board, ev(6, "ubrs"), W.now, isLead, isMember)
		assert.is_false(ok)
		assert.equal("too many dungeon groups", why)
		-- Not a member any more: no.
		assert.is_false((B.MergeEvent(B.New(), ev(7, "ubrs"), W.now, isLead, function() return false end)))
		-- In/Bench and groups from the maker: yes; from another member: no.
		local id = CAT .. ":3"
		assert.is_true((B.MergePlace(board, { e = id, g = DAN, v = "i", u = W.now, by = CAT }, W.now, isMember, isLead)))
		assert.is_false((B.MergePlace(board, { e = id, g = DAN, v = "b", u = W.now + 1, by = EVE }, W.now, isMember, isLead)))
		assert.is_true((RG.MergeSlot(board, { e = id, g = DAN, n = 1, m = "", u = W.now, by = CAT }, W.now, isMember, isLead)))
		assert.is_false((RG.MergeSlot(board, { e = id, g = DAN, n = 2, m = "", u = W.now + 1, by = EVE }, W.now, isMember, isLead)))
	end)

	it("leaves dungeon groups out of attendance, reserves and loot nights", function()
		local SK, W = setup({ rank = "Officer", rankIndex = 1 })
		local B = SK.RaidBoard
		local d = B:Create({ "ubrs" }, W.now + 30) -- the nearer one
		local r = B:Create({ "ony" }, W.now + 60)
		local ids = {}
		for _, e in ipairs(SK.Attendance.EventsNow(B:Get(), W.now)) do ids[#ids + 1] = e.id end
		assert.same({ r.id }, ids)
		ids = {}
		for _, e in ipairs(B.ReserveRaids(B:Get(), W.now)) do ids[#ids + 1] = e.id end
		assert.same({ r.id }, ids)
		assert.equal(r.id, SK.LootNight.Tonight(B:Get(), W.now).id)
		assert.truthy(d)
	end)
end)

describe("v0.16.8 dungeon groups: the Raids page", function()
	it("a member makes a UBRS group from the calendar and runs it", function()
		local SK, W = setup()
		H.loadUI(SK)
		local B, RT = SK.RaidBoard, SK.RaidsTab
		SK.DB.settings.newRaid = { minutes = 20 * 60, keys = { "ony" } } -- an officer's old form: ignored
		SK.DB.settings.raidsView = "calendar"
		SK.MainFrame:Open("raids")
		local c = RT.calCells[10]
		RT:CalendarDay(c.cell, c, 10)
		local box = RT.dayBox
		assert.equal("NEW DUNGEON GROUP", box.newLabel:GetText())
		assert.is_true(box.dkeys[1]:IsShown())
		assert.is_false(box.keys[1]:IsShown())
		assert.truthy(box.what:GetText():find("Upper Blackrock Spire (10)", 1, true))
		box.create:GetScript("OnClick")(box.create)
		assert.truthy(RT.dayResult:find("Made", 1, true))
		local e = B:Get().events[RT.selected]
		assert.same({ "ubrs" }, B.Keys(e))
		RT:CloseDay()
		RT:ShowRaid(e.id)
		RT:Refresh()
		assert.is_true(RT.Manage())
		assert.equal("Upper Blackrock Spire (10)", RT.title:GetText())
		assert.is_false(RT.keyChips[1]:IsShown()) -- instance chips stay with officers
		assert.is_false(RT.reserveBtn:IsShown())
		local items = RT:DetailOptions()
		assert.equal("Cancel this dungeon group", items[#items].text)
		B:SignUp(e.id, "y", "TANK")
		RT:CyclePlace({ guid = W.player.guid, place = nil })
		assert.equal("i", B.PlaceOf(B:Get(), e.id, W.player.guid))
		SK.DB.settings.raidsView = "groups"
		RT:Refresh()
		assert.is_true(RT.grpFill:IsShown())
		assert.is_true(RT.grpBoxes[2]:IsShown())
		assert.is_false(RT.grpBoxes[3]:IsShown())
		assert.equal(0, #SK.errors)
	end)
end)
