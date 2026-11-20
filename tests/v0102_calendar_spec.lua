-- v0.10.2: the Raids page's Calendar tab (a month grid, weeks from Monday).
local H = require("tests.helpers.load")

describe("v0.10.2 raid calendar", function()
	local SK, W, B, RT
	before_each(function()
		SK, W = H.load()
		W.member("Pip Hocus", W.player.guid, { rank = "Officer", rankIndex = 1 })
		SK.Identity:ReadRoster()
		SK.Profile:BuildSelf()
		H.loadUI(SK)
		B, RT = SK.RaidBoard, SK.RaidsTab
		W.now = os.time({ year = 2026, month = 12, day = 2, hour = 15 }) -- Wednesday 2 Dec 2026
	end)

	it("lays out a month from Monday, with raids on their days", function()
		local e1 = B:Create("ony", os.time({ year = 2026, month = 12, day = 11, hour = 20 }))
		local e2 = B:Create("hyjal", os.time({ year = 2026, month = 12, day = 11, hour = 18, min = 30 }))
		local e3 = B:Create("barrow", os.time({ year = 2026, month = 12, day = 16, hour = 20 }))
		B:Cancel(e3.id)
		B:SignUp(e1.id, "y")
		B:SetPlace(e1.id, W.player.guid, "b")
		local g = RT.MonthGrid(2026, 12, B:Get(), W.now, W.player.guid)
		assert.equal("December 2026", g.title)
		assert.equal(42, #g.cells)
		assert.equal(30, g.cells[1].day)       -- Monday 30 Nov
		assert.is_false(g.cells[1].inMonth)
		assert.equal(1, g.cells[2].day)        -- Tuesday 1 Dec
		assert.is_true(g.cells[3].today)
		assert.is_true(g.cells[2].past)
		local fri = g.cells[12]                -- Friday 11 Dec
		assert.equal(11, fri.day)
		assert.equal(2, #fri.raids)
		assert.equal("18:30 Hyjal", fri.raids[1].text)
		assert.equal("20:00 Onyxia", fri.raids[2].text)
		assert.equal("y", fri.raids[2].mine)
		assert.equal("b", fri.raids[2].place)
		assert.equal(0, #g.cells[17].raids)   -- the cancelled raid on the 16th
		assert.same({ 2027, 1 }, { RT.ShiftMonth(2026, 12, 1) })
		assert.same({ 2026, 11 }, { RT.ShiftMonth(2026, 12, -1) })
		assert.same({ 2025, 12 }, { RT.ShiftMonth(2026, 12, -12) })
	end)

	it("opens on this month; clicking a raid opens it; officers click a day to make one", function()
		local e = B:Create("ony", os.time({ year = 2026, month = 12, day = 4, hour = 20 }))
		SK.DB.settings.raidsView = "calendar"
		SK.MainFrame:Open("raids")
		assert.is_true(RT.calPage:IsShown())
		assert.equal("December 2026", RT.calTitle:GetText())
		local fri = RT.calCells[5]
		assert.equal(4, fri.cell.day)
		fri.lines[1]:GetScript("OnClick")(fri.lines[1])
		assert.equal(e.id, RT.selected)
		assert.equal("upcoming", SK.DB.settings.raidsView)
		SK.DB.settings.raidsView = "calendar"
		RT:Refresh()
		RT:CalendarDay(RT.calCells[7].cell)   -- Sunday 6 Dec, not an officer view yet
		assert.equal("calendar", SK.DB.settings.raidsView)
		SK.DB.officer[W.player.guid] = true
		RT:CalendarDay(RT.calCells[7].cell)
		assert.equal("new", SK.DB.settings.raidsView)
		assert.equal(4, SK.DB.settings.newRaid.day)
		SK.DB.settings.raidsView = "calendar"
		RT:CalendarDay(RT.calCells[1].cell)   -- in the past: nothing
		assert.equal("calendar", SK.DB.settings.raidsView)
		RT:MoveMonth(1)
		assert.equal("January 2027", RT.calTitle:GetText())
		RT.calToday:GetScript("OnClick")(RT.calToday)
		assert.equal("December 2026", RT.calTitle:GetText())
		assert.equal(0, #SK.errors)
	end)
end)
