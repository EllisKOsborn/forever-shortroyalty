-- v0.11.0: absences (days and weekdays a player can't raid), shared in
-- the profile, shown on the calendar, line-ups and groups.
local H = require("tests.helpers.load")

local CAT = "Player-1-C"

describe("v0.11.0 absences", function()
	local SK, W, A, B
	before_each(function()
		SK, W = H.load()
		W.now = os.time({ year = 2026, month = 12, day = 2, hour = 15 }) -- Wednesday
		W.member("Pip Hocus", W.player.guid, { rank = "Officer", rankIndex = 1 })
		W.member("Cat Fern", CAT, { class = "PRIEST" })
		SK.Identity:ReadRoster()
		SK.Profile:BuildSelf()
		A, B = SK.Absences, SK.RaidBoard
	end)

	local function at(day, hour) return os.time({ year = 2026, month = 12, day = day, hour = hour or 20 }) end

	it("knows weekdays from Monday and matches days and weekdays", function()
		assert.equal(3, A.Weekday(at(2)))   -- Wednesday
		assert.equal(1, A.Weekday(at(7)))   -- Monday
		assert.equal(7, A.Weekday(at(6)))   -- Sunday
		local away = { d = { "2026-12-11" }, w = { 2 }, u = 1 }
		assert.is_true(A.IsAway(away, at(11)))
		assert.is_true(A.IsAway(away, at(8)))  -- a Tuesday
		assert.is_false(A.IsAway(away, at(10)))
		assert.is_false(A.IsAway(nil, at(10)))
	end)

	it("my days and weekdays go into my profile; past days drop out", function()
		assert.is_true(A:ToggleDay(at(11)))
		local own = SK.Profile:Own()
		assert.same({ "2026-12-11" }, own.away.d)
		assert.same({}, own.away.w) -- v0.16.0: weekdays can't be set any more
		assert.is_true(SK.Merge.Validate(SK.DBM:Guild().profiles[W.player.guid]))
		assert.same({ false, "that day has passed" }, { A:ToggleDay(at(1)) })
		W.now = at(12, 12)
		assert.is_nil(A.Field(A:Saved(), W.now)) -- nothing left from today on
		assert.is_true(A:ToggleDay(at(14)))
		assert.is_true(A:ToggleDay(at(14))) -- off again
		assert.is_false(A:IsMyDay(at(14)))
	end)

	it("marking a raid day away answers Can't come", function()
		local e = B:Create("ony", at(11))
		B:SignUp(e.id, "y", "HEALER")
		A:ToggleDay(at(11))
		assert.equal("n", B:Get().signups[e.id][W.player.guid].s)
	end)

	it("a guildmate's absence shows on the line-up, the groups and the calendar", function()
		local e = B:Create("ony", at(11))
		B:Get().signups[e.id] = { [CAT] = { s = "y", r = "HEALER", u = W.now } }
		local guild = SK.DBM:Guild()
		guild.profiles[CAT] = { guid = CAT, name = "Cat Fern", class = "PRIEST", away = { d = { "2026-12-11" }, u = W.now } }
		local rows, s = B.LineUp(B:Get(), e, B.Ctx())
		assert.is_true(rows[1].away)
		assert.equal(1, s.away)
		local found
		for _, r in ipairs(B.Readiness(s)) do if r.text:find("marked away", 1, true) then found = true end end
		assert.is_true(found)
		assert.same({ CAT }, A.AwayOn(guild, at(11)))
		H.loadUI(SK)
		assert.truthy(SK.RaidsTab.SlotText(rows[1]):find("away", 1, true))
		local g = SK.RaidsTab.MonthGrid(2026, 12, B:Get(), W.now, W.player.guid, nil, guild)
		assert.equal(1, g.cells[12].awayCount)
		-- a bad away field is refused
		local p = { guid = CAT, name = "Cat Fern", class = "PRIEST", updated = W.now, away = { d = { "next friday" }, u = 1 } }
		p.hash = SK.Profile.HashOf(p)
		assert.is_false((SK.Merge.Validate(p)))
	end)

	it("the calendar: right-click marks a day", function()
		H.loadUI(SK)
		SK.DB.settings.raidsView = "calendar"
		SK.MainFrame:Open("raids")
		local RT = SK.RaidsTab
		local fri = RT.calCells[12]
		assert.equal(11, fri.cell.day)
		fri:GetScript("OnClick")(fri, "RightButton")
		assert.is_true(A:IsMyDay(at(11)))
		assert.is_true(RT.calCells[12].cell.away)
		assert.is_nil(RT.calWeek) -- v0.16.0: the "Away every" chips are gone
		assert.equal(0, #SK.errors)
	end)

	it("v0.16.2: counts players, not each of their characters", function()
		local guild = SK.DBM:Guild()
		local ALT1, ALT2, DOG = "Player-1-A1", "Player-1-A2", "Player-1-D"
		W.member("Alt One", ALT1, { class = "MAGE" })
		W.member("Alt Two", ALT2, { class = "ROGUE" })
		W.member("Dog Star", DOG, { class = "HUNTER" })
		SK.Identity:ReadRoster()
		local away = { d = { "2026-12-11" }, u = W.now }
		local fam = { CAT, ALT1, ALT2 }
		guild.profiles[CAT] = { guid = CAT, name = "Cat Fern", level = 60, family = fam, away = away }
		guild.profiles[ALT1] = { guid = ALT1, name = "Alt One", level = 20, family = fam, away = away }
		guild.profiles[ALT2] = { guid = ALT2, name = "Alt Two", level = 10, family = fam }
		-- a stranger listing Cat as family (one-way) doesn't pick up her days
		guild.profiles[DOG] = { guid = DOG, name = "Dog Star", level = 60, family = { DOG, CAT } }
		assert.same({ CAT }, A.AwayOn(guild, at(11)))
		H.loadUI(SK)
		local g = SK.RaidsTab.MonthGrid(2026, 12, B:Get(), W.now, W.player.guid, nil, guild)
		assert.equal(1, g.cells[12].awayCount)
	end)

	it("v0.16.2: the raid's line-up lists players away that day who didn't sign up", function()
		local guild = SK.DBM:Guild()
		local DOG, EEL = "Player-1-D", "Player-1-E"
		W.member("Dog Star", DOG, { class = "HUNTER" })
		W.member("Eel Wave", EEL, { class = "MAGE" })
		SK.Identity:ReadRoster()
		local e = B:Create("ony", at(11))
		B:Get().signups[e.id] = { [CAT] = { s = "y", r = "HEALER", u = W.now } }
		guild.profiles[CAT] = { guid = CAT, name = "Cat Fern", class = "PRIEST", away = { d = { "2026-12-11" }, u = W.now } }
		guild.profiles[DOG] = { guid = DOG, name = "Dog Star", class = "HUNTER", away = { d = { "2026-12-11" }, u = W.now } }
		local ctx = B.Ctx()
		local rows = B.LineUp(B:Get(), e, ctx)
		local extra = B.AwayRows(B:Get(), e, ctx, rows)
		-- Cat signed up (her row already says away); Dog didn't, so he gets a row
		assert.equal(1, #extra)
		assert.equal(DOG, extra[1].guid)
		assert.equal("Away", extra[1].statusName)
		assert.is_true(extra[1].awayOnly)
		-- a day an officer set counts only when the officer directory is passed
		local dir = { [SK.OfficerDir.Key("d", EEL)] = { v = "2026-12-11", u = W.now, by = W.player.guid } }
		assert.equal(1, #B.AwayRows(B:Get(), e, ctx, rows))
		assert.equal(2, #B.AwayRows(B:Get(), e, ctx, rows, dir))
		-- the Raids page shows them, with the count
		H.loadUI(SK)
		SK.DB.settings.raidsView = "upcoming"
		SK.MainFrame:Open("raids")
		SK.RaidsTab:ShowRaid(e.id)
		local found
		for _, r in ipairs(SK.RaidsTab.lineup.items) do if r.guid == DOG then found = r end end
		assert.truthy(found)
		assert.truthy(SK.RaidsTab.counts:GetText():find("1 away", 1, true))
		assert.equal(0, #SK.errors)
	end)
end)
