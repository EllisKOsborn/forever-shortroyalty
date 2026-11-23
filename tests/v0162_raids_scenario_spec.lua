-- v0.16.2: an end-to-end walk through the raid tools, the way officers and
-- members use them (owner: "run some tests on the raid section as a whole
-- to spot bugs or errors"). Every step checks that nothing raised a Lua
-- error, and what a player would see.
local H = require("tests.helpers.load")

local OFF, MEM, ALT, HEAL = "Player-1-OFF", "Player-1-MEM", "Player-1-ALT", "Player-1-HEAL"

describe("v0.16.2 raid section walk-through", function()
	local SK, W, B, RT, RG
	before_each(function()
		SK, W = H.load()
		W.now = os.time({ year = 2026, month = 12, day = 2, hour = 15 }) -- Wednesday
		W.player.guid = OFF
		W.member("Pip Hocus", OFF, { rank = "Officer", rankIndex = 1, class = "WARRIOR", level = 60 })
		W.member("Mem Ber", MEM, { class = "MAGE", level = 60 })
		W.member("Alt Ber", ALT, { class = "ROGUE", level = 30 })
		W.member("Hea Ler", HEAL, { class = "PRIEST", level = 60 })
		SK.Identity:ReadRoster()
		SK.Profile:BuildSelf()
		H.loadUI(SK)
		B, RT, RG = SK.RaidBoard, SK.RaidsTab, SK.RaidGroups
		SK.DB.officer[OFF] = true
	end)

	local function noErrors(step)
		assert.equal(0, #SK.errors, step .. ": " .. tostring(SK.errors[1] and SK.errors[1].msg or SK.errors[1]))
	end

	local function openView(view)
		SK.DB.settings.raidsView = view
		SK.MainFrame:Open("raids")
		RT:Refresh()
	end

	it("an officer's whole evening, every view, no errors", function()
		-- 1. A weekly series from the calendar, still to be decided.
		openView("calendar")
		local form = RT.NewRaidForm()
		form.keys, form.minutes, form.weeks = {}, 20 * 60, 8
		local thu = os.time({ year = 2026, month = 12, day = 10, hour = 12 })
		local first, why, n = RT:CreateRaid(thu)
		assert.truthy(first, why)
		assert.equal(8, n)
		noErrors("create series")
		-- 2. Every view, with officer tools on and off.
		for _, officer in ipairs({ true, false }) do
			SK.DB.officer[OFF] = officer or nil
			for _, v in ipairs({ "upcoming", "groups", "assign", "calendar", "attendance" }) do openView(v) end
		end
		SK.DB.officer[OFF] = true
		noErrors("every view")
		-- 3. Click every calendar day of this month and the next two.
		openView("calendar")
		for _ = 1, 3 do
			for i, c in ipairs(RT.calCells) do
				RT:CalendarDay(c.cell, c, i)
				RT:CloseDay()
			end
			RT:MoveMonth(1)
		end
		RT.calMonth = nil
		noErrors("calendar days")
		-- 4. Pick the instances, sign up, members answer, someone is away.
		B:SetRaids(first.id, { "hyjal", "ony" })
		RT:ShowRaid(first.id)
		RT:SignUp("y")
		local board = B:Get()
		board.signups[first.id][MEM] = { s = "y", r = "DPS", u = W.now }
		board.signups[first.id][HEAL] = { s = "t", r = "HEALER", u = W.now }
		SK.DBM:Guild().profiles[ALT] = { guid = ALT, name = "Alt Ber", class = "ROGUE",
			away = { d = { "2026-12-10" }, u = W.now } }
		openView("upcoming")
		RT:ShowRaid(first.id)
		noErrors("sign-ups")
		local names = {}
		for _, r in ipairs(RT.lineup.items) do names[r.guid] = r.statusName end
		assert.equal("Signed up", names[OFF])
		assert.equal("Away", names[ALT])
		-- 5. In / Bench, groups per instance, auto-fill, marks, assignments.
		RT:CyclePlace({ guid = MEM })
		for _, k in ipairs({ "hyjal", "ony" }) do
			RG:Fill(first.id, k)
			RG:Move(first.id, HEAL, { kind = "group", n = 2 }, false, k)
			RG:CycleMark(first.id, HEAL, k)
		end
		openView("groups")
		openView("assign")
		SK.RaidAssign:AddBlock(first.id, "Onyxia")
		openView("assign")
		noErrors("groups and assignments")
		-- 6. Every ··· menu item that doesn't need typing.
		openView("upcoming")
		RT:ShowRaid(first.id)
		for _, item in ipairs(RT:DetailOptions()) do
			if item.text and not item.text:find("Cancel", 1, true) and not item.text:find("Import", 1, true) and item.onClick then
				item.onClick()
			end
		end
		noErrors("menu items")
		-- 7. Import from Discord.
		RT.DoImport(first.id, "Mem Ber tank\nNobody Here dps")
		noErrors("import")
		-- 8. Cancel the rest of the series from the third raid.
		local series = B.SeriesFrom(board, first.id)
		assert.equal(8, #series)
		assert.equal(6, B:CancelSeries(series[3].id))
		assert.equal(2, #B.SeriesFrom(board, first.id))
		openView("calendar")
		openView("upcoming")
		noErrors("cancel series")
		-- 9. A week later, then a month later: prune, everything still opens.
		W.now = W.now + 8 * 86400
		openView("upcoming")
		openView("calendar")
		W.now = W.now + 40 * 86400
		B.Prune(board, W.now)
		for _, v in ipairs({ "upcoming", "groups", "assign", "calendar", "attendance" }) do openView(v) end
		noErrors("later")
	end)

	it("a member sees no officer tools and can still use everything", function()
		local e = B:Create("ony", os.time({ year = 2026, month = 12, day = 11, hour = 20 }))
		SK.DB.officer[OFF] = nil
		W.player.guid = MEM
		SK.Profile:BuildSelf()
		assert.is_false(B.OfficerView())
		for _, v in ipairs({ "upcoming", "groups", "assign", "calendar", "attendance" }) do openView(v) end
		openView("upcoming")
		RT:ShowRaid(e.id)
		RT:SignUp("y")
		assert.equal("y", B:Get().signups[e.id][MEM].s)
		-- members can't change raids
		assert.is_nil((B:Create("ony", W.now + 86400)))
		assert.is_false((B:Cancel(e.id)))
		assert.equal(0, (B:CancelSeries(e.id)))
		-- away from the day box
		openView("calendar")
		for i, c in ipairs(RT.calCells) do
			if os.date("%Y-%m-%d", c.cell.at) == "2026-12-11" then RT:CalendarDay(c.cell, c, i) end
		end
		RT.dayBox.away:GetScript("OnClick")(RT.dayBox.away)
		assert.equal("n", B:Get().signups[e.id][MEM].s) -- answered Can't come
		noErrors("member")
	end)

	it("what one officer sends, a fresh guildmate receives whole", function()
		local sent = H.captureSends(SK)
		local first = B:CreateSeries({ "ony" }, os.time({ year = 2026, month = 12, day = 10, hour = 20 }), 12)
		assert.equal(12, #first)
		for _, e in ipairs(first) do B:Get().signups[e.id] = { [MEM] = { s = "y", r = "DPS", u = W.now } } end
		B:CancelSeries(first[11].id)
		-- the RD answer path: everything for every raid
		local keys = {}
		for id in pairs(B:Get().events) do
			for _, k in ipairs(SK.RaidSync.raidKeys(B:Get(), id)) do keys[#keys + 1] = k end
		end
		SK.RaidSync.heard = {}
		SK.RaidSync:Queue(keys, "answer")
		SK.RaidSync:SendPending()
		SK.Sync:Flush()
		local rbs = {}
		for _, s in ipairs(sent) do if s.msg and s.msg.t == "RB" then rbs[#rbs + 1] = s.msg end end
		assert.is_true(#rbs >= 1)
		-- a guildmate with an empty board
		local guild = SK.DBM:Guild()
		guild.raidBoard = B.New()
		SK.RaidSync.heard = {}
		for _, m in ipairs(rbs) do SK.RaidSync:HandleRB(m, "Pip Hocus") end
		local board = B:Get()
		assert.equal(12, SK.Count(board.events))
		assert.equal(10, B.LiveCount(board))
		for _, e in ipairs(first) do
			assert.equal(first[1].sr, board.events[e.id].sr)
			assert.equal("y", board.signups[e.id][MEM].s)
		end
		noErrors("sync")
	end)

	it("the digest lists every raid held, not just 60", function()
		local board = B:Get()
		for i = 1, 70 do
			local id = OFF .. ":" .. (1000 + i)
			board.events[id] = { id = id, by = OFF, c = 1000 + i, raid = "ony", at = W.now + i * 3600, u = W.now, x = i > 30 or nil }
		end
		local sent = H.captureSends(SK)
		SK.RaidSync:SendDigest()
		SK.Sync:Flush()
		local rd
		for _, s in ipairs(sent) do if s.msg and s.msg.t == "RD" then rd = s.msg end end
		assert.truthy(rd)
		assert.equal(70, SK.Count(rd.d))
	end)

	it("no reserves (or reminders to reserve) for a raid still to be decided", function()
		local tbd = B:Create({}, os.time({ year = 2026, month = 12, day = 3, hour = 20 }))
		local ony = B:Create("ony", os.time({ year = 2026, month = 12, day = 4, hour = 20 }))
		B:SignUp(tbd.id, "y", "TANK")
		B:SignUp(ony.id, "y", "TANK")
		local list = B.ReserveRaids(B:Get(), W.now)
		assert.equal(1, #list)
		assert.equal(ony.id, list[1].id)
		for _, r in ipairs(SK.ReserveReminder.Raids(W.now, OFF)) do assert.are_not.equal(tbd.id, r.ev.id) end
		SK.LootTab.raidID = tbd.id
		SK.MainFrame:Open("loot")
		SK.LootTab:Show("reserves")
		assert.equal(ony.id, SK.LootTab.raidID) -- moved off the undecided raid
		noErrors("reserves")
	end)

	it("v0.16.4: away days answer Can't come for raids made before and after, but never undo a Sign up", function()
		local A = SK.Absences
		local function at(day) return os.time({ year = 2026, month = 12, day = day, hour = 20 }) end
		local before = B:Create("ony", at(11))
		local signed = B:Create("hyjal", at(12))
		B:SignUp(signed.id, "y", "TANK")
		assert.is_true(A:SetRange(at(10), 5)) -- 10-14 Dec
		local board = B:Get()
		assert.equal("n", board.signups[before.id][OFF].s) -- hadn't answered: Can't come
		assert.equal("n", board.signups[signed.id][OFF].s) -- had signed up: Can't come
		-- a raid made later on one of those days
		local later = B:Create("ony", at(13))
		assert.equal(1, A.DeclineClashes(W.now, false))
		assert.equal("n", board.signups[later.id][OFF].s)
		-- changed plans: signing up again sticks
		B:SignUp(later.id, "y", "DPS")
		assert.equal(0, A.DeclineClashes(W.now, false))
		assert.equal("y", board.signups[later.id][OFF].s)
		-- a raid on a day not marked is left alone
		local free = B:Create("ony", at(20))
		A.DeclineClashes(W.now, false)
		assert.is_nil(board.signups[free.id] and board.signups[free.id][OFF])
		noErrors("auto can't come")
	end)

	it("v0.16.4: the planner's Away column covers three months, as ranges", function()
		local RP = SK.RosterPlan
		local function key(d) return os.date("%Y-%m-%d", os.time({ year = 2026, month = 12, day = d, hour = 12 })) end
		local days = RP.AwayDays({ [key(10)] = true, [key(11)] = true, [key(12)] = true },
			{ d = { "2027-02-20", "2027-02-21" }, u = 1 }, W.now)
		local runs = RP.AwayRuns(days)
		assert.equal(2, #runs)
		assert.equal("10-12 Dec", RP.RunText(runs[1]))
		assert.is_true(runs[1].officer)
		assert.equal("20-21 Feb", RP.RunText(runs[2]))
		assert.is_true(runs[2].self)
	end)

	it("v0.16.4: clearing your away days wins over your alts' older copies", function()
		local A = SK.Absences
		local guild = SK.DBM:Guild()
		local fam = { OFF, ALT }
		local mark = W.now
		A:SetRange(os.time({ year = 2026, month = 12, day = 10, hour = 20 }), 3)
		-- the alt last logged in while away (its copy is older)
		guild.profiles[ALT] = { guid = ALT, name = "Alt Ber", family = fam, away = { d = { "2026-12-10" }, u = mark } }
		guild.profiles[OFF].family = fam
		SK.Profile:Own().family = fam
		W.now = W.now + 60
		A:ClearRun(os.time({ year = 2026, month = 12, day = 10, hour = 20 }))
		local mine = guild.profiles[OFF].away
		assert.truthy(mine) -- sent empty, with its time
		assert.same({}, mine.d)
		assert.is_true(SK.Merge.Validate(guild.profiles[OFF]))
		local at = os.time({ year = 2026, month = 12, day = 10, hour = 20 })
		assert.is_false(A.IsAway(A.Of(guild, OFF), at))
		assert.is_false(A.IsAway(A.Of(guild, ALT), at))
	end)

	it("v0.16.4: take a character off a raid (your alt, or anyone as an officer)", function()
		local e = B:Create("ony", os.time({ year = 2026, month = 12, day = 11, hour = 20 }))
		local board = B:Get()
		board.signups[e.id] = { [ALT] = { s = "y", r = "DPS", u = W.now - 10 }, [MEM] = { s = "t", u = W.now - 10 } }
		board.places[e.id] = { [ALT] = { v = "i", u = W.now - 10, by = OFF } }
		SK.DB.account[ALT] = { name = "Alt Ber" } -- one of my characters
		-- a member (not an officer) can remove their own alt, not someone else
		SK.DB.officer[OFF] = nil
		W.roster[1].rank, W.roster[1].rankIndex = "Member", 5
		SK.Identity:ReadRoster()
		assert.is_true(B:RemoveSignup(e.id, ALT))
		assert.same({ false, "only officers can remove someone else" }, { B:RemoveSignup(e.id, MEM) })
		assert.equal("x", board.signups[e.id][ALT].s)
		assert.is_nil(board.signups[e.id][ALT].b) -- own character: no officer mark
		local rows = B.LineUp(board, e, B.Ctx())
		assert.equal(1, #rows)
		assert.equal(MEM, rows[1].guid)
		assert.same({ y = 0, t = 1, n = 0 }, B.Counts(board, e.id))
		assert.is_nil(B.SignupOf(board, e.id, ALT))
		assert.same({ false, "not signed up" }, { B:RemoveSignup(e.id, ALT) })
		-- signing up again afterwards works
		W.now = W.now + 5
		W.player.guid = ALT
		assert.is_true(B:SignUp(e.id, "y", "DPS"))
		assert.equal("y", board.signups[e.id][ALT].s)
		W.player.guid = OFF
		-- an officer removes anyone; the In/Bench choice is cleared too
		W.roster[1].rank, W.roster[1].rankIndex = "Officer", 1
		SK.Identity:ReadRoster()
		W.now = W.now + 5
		assert.is_true(B:RemoveSignup(e.id, MEM))
		assert.equal(OFF, board.signups[e.id][MEM].b)
		-- received: "x" passes the checks, but never with a change time
		local ok = B.ValidSignup({ e = e.id, g = MEM, s = "x", u = W.now }, W.now)
		assert.is_true(ok)
		assert.is_false((B.ValidSignup({ e = e.id, g = MEM, s = "x", u = W.now, w = W.now }, W.now)))
		-- the menu: officers and own characters get "Remove"
		SK.DB.officer[OFF] = true
		local items = RT.RowItems({ guid = MEM, name = "Mem Ber" })
		assert.equal("Remove from this raid", items[2].text)
		assert.equal(1, #RT.RowItems({ guid = MEM, name = "Mem Ber", awayOnly = true }))
		openView("upcoming")
		RT:ShowRaid(e.id)
		noErrors("remove")
	end)
end)
