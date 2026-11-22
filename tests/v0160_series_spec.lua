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

	it("away for a range of days from the day box; one button clears it", function()
		H.loadUI(SK)
		local A = SK.Absences
		local function on(day) return os.time({ year = 2026, month = 12, day = day, hour = 20 }) end
		-- pure parts
		assert.equal("10-14 Dec", A.RangeText(on(10), on(14)))
		assert.equal("30 Nov-2 Dec", A.RangeText(os.time({ year = 2026, month = 11, day = 30, hour = 12 }), on(2)))
		assert.equal("10 Dec", A.RangeText(on(10), on(10)))
		local items = RT.AwayItems(on(10))
		assert.equal("Just this day", items[1].text)
		assert.equal("Until Mon 14 Dec", items[5].text)
		assert.equal(A.RANGE_DAYS, #items)
		assert.same({ false, "too many days" }, { A:SetRange(on(10), A.RANGE_DAYS + 1) })
		-- the day box: 10 Dec, until 14 Dec
		SK.DB.settings.raidsView = "calendar"
		SK.MainFrame:Open("raids")
		local idx
		for i, c in ipairs(RT.calCells) do if os.date("%Y-%m-%d", c.cell.at) == "2026-12-10" then idx = i end end
		RT:CalendarDay(RT.calCells[idx].cell, RT.calCells[idx], idx)
		RT.dayBox.awayUntil:Choose(5)
		RT.dayBox.away:GetScript("OnClick")(RT.dayBox.away)
		for d = 10, 14 do assert.is_true(A:IsMyDay(on(d)), "day " .. d) end
		assert.is_false(A:IsMyDay(on(15)))
		assert.same({ "2026-12-10", "2026-12-11", "2026-12-12", "2026-12-13", "2026-12-14" }, SK.Profile:Own().away.d)
		assert.equal("Not away 10-14 Dec after all", RT.dayBox.away.label:GetText())
		assert.is_false(RT.dayBox.awayUntil:IsShown())
		-- clicking it again clears all five days
		RT.dayBox.away:GetScript("OnClick")(RT.dayBox.away)
		for d = 10, 14 do assert.is_false(A:IsMyDay(on(d))) end
		assert.equal(0, #SK.errors)
	end)

	it("an old 'away every' weekday of ours is cleared once", function()
		local db = SK.DBM:Load({ away = { d = {}, w = { [2] = true }, u = 1 } })
		assert.same({}, db.away.w)
		assert.is_true(db.away.u > 1)
	end)
end)
