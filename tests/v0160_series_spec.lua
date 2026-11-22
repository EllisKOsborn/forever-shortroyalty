-- v0.16.0: weekly raid series from the Calendar's day box, cancelling the
-- rest of a series, and the Raids page's Reserve loot button.
local H = require("tests.helpers.load")

describe("v0.16.0 weekly series", function()
	local SK, W, B, RT
	before_each(function()
		SK, W = H.load()
		W.member("Pip", W.player.guid, { rank = "Officer", rankIndex = 1 })
		W.member("Bob", "Player-1-B", { rank = "Raid Leader", rankIndex = 2 })
		SK.Identity:ReadRoster()
		SK.Profile:BuildSelf()
		H.loadUI(SK)
		B, RT = SK.RaidBoard, SK.RaidsTab
		W.now = os.time({ year = 2026, month = 12, day = 2, hour = 15 })
		SK.DB.officer[W.player.guid] = true
	end)

	it("keeps the same local time each week", function()
		local first = os.time({ year = 2026, month = 12, day = 7, hour = 19, min = 30 })
		local starts = B.WeeklyStarts(first, 4)
		assert.equal(4, #starts)
		for i, at in ipairs(starts) do
			local t = os.date("*t", at)
			assert.equal(19, t.hour)
			assert.equal(30, t.min)
			assert.equal(os.date("%w", first), os.date("%w", at))
			if i > 1 then assert.is_true(at > starts[i - 1]) end
		end
	end)

	it("makes a series, cancels the rest of it, and keeps room limits", function()
		local first = os.time({ year = 2026, month = 12, day = 7, hour = 19 })
		local list = B:CreateSeries({ "ony" }, first, 8)
		assert.equal(8, #list)
		local sr = list[1].sr
		assert.equal(list[1].id, sr)
		for _, e in ipairs(list) do assert.equal(sr, e.sr) end
		assert.equal(8, #B.SeriesFrom(B:Get(), list[1].id))
		assert.equal(5, #B.SeriesFrom(B:Get(), list[4].id))
		assert.equal(5, B:CancelSeries(list[4].id))
		assert.is_true(B:Get().events[list[8].id].x)
		assert.is_nil(B:Get().events[list[3].id].x)
		assert.equal(3, B.LiveCount(B:Get()))
		-- Too many at once: nothing is made.
		for i = 1, B.MAX_EVENTS - 5 do B:Create("hyjal", W.now + i * 3600) end
		local none, why = B:CreateSeries({ "ony" }, first + 3600, 4)
		assert.is_nil(none)
		assert.truthy(why:find("only room for 2", 1, true))
		-- Older series fields arrive intact; a bad one is refused.
		local e = { id = "Player-1-B:5", by = "Player-1-B", c = 5, raid = "ony", at = W.now + 3600, u = 5, sr = "Player-1-B:5" }
		assert.is_true(B.ValidEvent(e, W.now))
		e.sr = string.rep("x", 100)
		assert.is_false((B.ValidEvent(e, W.now)))
	end)

	it("the day box's Repeat menu makes a weekly series", function()
		SK.DB.settings.raidsView = "calendar"
		SK.MainFrame:Open("raids")
		local c = RT.calCells[8]
		RT:CalendarDay(c.cell, c, 8)
		assert.is_true(RT.dayBox.repeatMenu:IsShown())
		RT.dayBox.repeatMenu:Choose(6)
		RT.NewRaidForm().keys = { "ony" }
		RT.dayBox.create:GetScript("OnClick")(RT.dayBox.create)
		assert.truthy(RT.dayResult:find("Made 6 raids", 1, true))
		assert.equal(6, B.LiveCount(B:Get()))
		-- The ··· menu offers cancelling the rest.
		local found
		for _, it in ipairs(RT:DetailOptions()) do
			if it.text:find("later in the series", 1, true) then found = it end
		end
		assert.truthy(found)
		found.onClick()
		assert.equal(0, B.LiveCount(B:Get()))
		assert.equal(0, #SK.errors)
	end)

	it("Reserve loot shows once signed up and the raid isn't to be decided, and opens the Loot page", function()
		local tbd = B:Create({}, W.now + 86400)
		B:SignUp(tbd.id, "y")
		RT:ShowRaid(tbd.id)
		RT:Refresh()
		assert.is_false(RT.reserveBtn:IsShown())
		assert.is_true(B:SetRaids(tbd.id, { "ony" }))
		RT:Refresh()
		assert.is_true(RT.reserveBtn:IsShown())
		RT.reserveBtn:GetScript("OnClick")(RT.reserveBtn)
		assert.equal("loot", SK.MainFrame.current)
		assert.equal(tbd.id, SK.LootTab.raidID)
		assert.equal("reserves", SK.DB.settings.lootView)
		B:SignUp(tbd.id, "n")
		RT:ShowRaid(tbd.id)
		RT:Refresh()
		assert.is_false(RT.reserveBtn:IsShown())
		assert.equal(0, #SK.errors)
	end)
end)
