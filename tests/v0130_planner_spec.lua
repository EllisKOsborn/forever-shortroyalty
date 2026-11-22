-- v0.13.0: the raid roster planner (officers' feedback, 21 Nov): role tiers
-- (Main / Backup), Raider / Backup status, away days, notes from several
-- officers, and one table of players with level, gear and attunement.
local H = require("tests.helpers.load")

local BOB, CAT, DAN, EVE, FAY = "Player-1-B", "Player-1-C", "Player-1-D", "Player-1-E", "Player-1-F"

local function setup(myRank)
	local SK, W = H.load()
	W.member("Pip Hocus", W.player.guid, myRank or { rank = "Officer", rankIndex = 1 })
	W.member("Bob Stone", BOB, { rank = "Raid Leader", rankIndex = 2, class = "WARRIOR", level = 60 })
	W.member("Cat Fern", CAT, { rank = "Member", rankIndex = 4, class = "PRIEST", level = 58 })
	W.member("Dan Moss", DAN, { rank = "Alt", rankIndex = 5, class = "MAGE", level = 20 })
	W.member("Eve Moss", EVE, { rank = "Member", rankIndex = 4, class = "WARRIOR", level = 55 })
	W.member("Fay Reed", FAY, { rank = "Member", rankIndex = 4, class = "ROGUE", level = 40 })
	SK.Identity:ReadRoster()
	SK.Profile:BuildSelf()
	return SK, W
end

local function profile(SK, guid, fields)
	local guild = SK.DBM:Guild()
	local p = { name = guild.members[guid].name, class = guild.members[guid].class, level = 60, updated = 1800000000,
		gear = {}, att = {} }
	for k, v in pairs(fields or {}) do p[k] = v end
	guild.profiles[guid] = p
	return p
end

local function prot() return { trees = { { n = "Arms", p = 5 }, { n = "Fury", p = 5 }, { n = "Protection", p = 31 } } } end
local function holy() return { trees = { { n = "Discipline", p = 21 }, { n = "Holy", p = 30 }, { n = "Shadow", p = 0 } } } end

describe("v0.13.0 officer roster: tiers, status, away days, notes", function()
	local SK, W, OD
	before_each(function()
		SK, W = setup()
		OD = SK.OfficerDir
	end)

	it("sets Main / Backup per role, Raider / Backup and away days", function()
		assert.is_true(OD:SetTier(CAT, "HEALER", "m"))
		assert.is_true(OD:SetTier(CAT, "DPS", "b"))
		assert.same({ HEALER = "m", DPS = "b" }, OD.TiersOf(OD:Get(), CAT))
		assert.equal("-mb", OD:Get()["t:" .. CAT].v)
		assert.is_true(OD:SetTier(CAT, "DPS", nil))
		assert.same({ HEALER = "m" }, OD.TiersOf(OD:Get(), CAT))
		assert.is_true(OD:SetStatus(CAT, "b"))
		assert.equal("b", OD.StatusOf(OD:Get(), CAT))
		assert.is_true(OD:SetStatus(CAT, nil))
		assert.is_nil(OD.StatusOf(OD:Get(), CAT))
		local d1, d2 = date("%Y-%m-%d", W.now + 86400), date("%Y-%m-%d", W.now + 3 * 86400)
		assert.is_true(OD:ToggleAway(CAT, d2))
		assert.is_true(OD:ToggleAway(CAT, d1))
		assert.equal(d1 .. "," .. d2, OD:Get()["d:" .. CAT].v)
		assert.is_true(OD:ToggleAway(CAT, d2))
		assert.same({ [d1] = true }, OD.AwayOf(OD:Get(), CAT))
		-- Past days drop out when the list changes.
		assert.is_true(OD:ToggleAway(CAT, "2020-01-01"))
		assert.same({ [d1] = true }, OD.AwayOf(OD:Get(), CAT))
		local SK2 = setup({ rank = "Member", rankIndex = 4 })
		assert.is_false(SK2.OfficerDir:SetTier(CAT, "TANK", "m"))
	end)

	it("reads v0.10.1 roles as mains until tiers are set", function()
		assert.is_true(OD:ToggleRole(BOB, "TANK"))
		assert.is_true(OD:ToggleRole(BOB, "DPS"))
		assert.same({ TANK = "m", DPS = "m" }, OD.TiersOf(OD:Get(), BOB))
		assert.is_true(OD:SetTier(BOB, "DPS", "b"))
		assert.same({ TANK = "m", DPS = "b" }, OD.TiersOf(OD:Get(), BOB))
	end)

	it("keeps one note per officer, newest first, and moves a legacy note", function()
		assert.is_true(OD:Set("n", CAT, "Old shared note"))
		local notes = OD.NotesOf(OD:Get(), CAT, W.player.guid)
		assert.equal(1, #notes)
		assert.is_true(notes[1].mine and notes[1].legacy)
		W.now = W.now + 10
		assert.is_true(OD:SetMyNote(CAT, "Great healer"))
		notes = OD.NotesOf(OD:Get(), CAT, W.player.guid)
		assert.equal(1, #notes)
		assert.equal("Great healer", notes[1].text)
		assert.is_nil(notes[1].legacy)
		assert.equal("", OD:Get()["n:" .. CAT].v)
		-- Another officer's note arrives.
		local dir = OD:Get()
		local lead = function(g) return g == BOB or g == W.player.guid end
		local member = function() return true end
		assert.is_true(OD.Merge(dir, "m:" .. CAT .. ":" .. BOB, { v = "Said yes to week 1", u = W.now + 5, by = BOB },
			W.now, lead, member))
		notes = OD.NotesOf(dir, CAT, W.player.guid)
		assert.equal(2, #notes)
		assert.equal(BOB, notes[1].by)
		assert.is_false(notes[1].mine)
		-- Removing mine leaves theirs.
		assert.is_true(OD:SetMyNote(CAT, ""))
		assert.equal(1, #OD.NotesOf(dir, CAT, W.player.guid))
	end)

	it("checks the new kinds when received; nobody writes another officer's note", function()
		local dir, now = {}, W.now
		local lead = function(g) return g == BOB or g == W.player.guid end
		local member = function() return true end
		assert.is_true(OD.Merge(dir, "t:" .. CAT, { v = "mb-", u = now, by = BOB }, now, lead, member))
		assert.is_false(OD.Merge(dir, "t:" .. EVE, { v = "mx-", u = now, by = BOB }, now, lead, member))
		assert.is_false(OD.Merge(dir, "t:" .. EVE, { v = "mbmb", u = now, by = BOB }, now, lead, member))
		assert.is_true(OD.Merge(dir, "s:" .. CAT, { v = "r", u = now, by = BOB }, now, lead, member))
		assert.is_false(OD.Merge(dir, "s:" .. EVE, { v = "core", u = now, by = BOB }, now, lead, member))
		assert.is_true(OD.Merge(dir, "d:" .. CAT, { v = "2026-12-09,2026-12-10", u = now, by = BOB }, now, lead, member))
		assert.is_false(OD.Merge(dir, "d:" .. EVE, { v = "9 Dec", u = now, by = BOB }, now, lead, member))
		assert.is_false(OD.Merge(dir, "d:" .. EVE, { v = "2026-12-09,", u = now, by = BOB }, now, lead, member))
		assert.is_false(OD.Merge(dir, "d:" .. EVE, { v = string.rep("2026-12-09,", 41) .. "2026-12-09", u = now, by = BOB },
			now, lead, member))
		assert.is_false(OD.Merge(dir, "w:" .. EVE, { v = "1", u = now, by = BOB }, now, lead, member))
		assert.is_false(OD.Merge(dir, "m:" .. CAT .. ":" .. W.player.guid, { v = "forged", u = now, by = BOB }, now, lead, member))
		assert.same({ false, "not the author" }, { OD.Valid("m:" .. CAT .. ":" .. W.player.guid, { v = "x", u = now, by = BOB }, now) })
		assert.is_false(OD.Merge(dir, "m:" .. CAT .. ":" .. BOB, { v = "a|Hlink", u = now, by = BOB }, now, lead, member))
		assert.is_false(OD.Merge(dir, "m:" .. CAT, { v = "x", u = now, by = BOB }, now, lead, member))
		assert.is_false(OD.Merge(dir, "q:" .. CAT, { v = "x", u = now, by = BOB }, now, lead, member))
	end)

	it("reaches another officer by whisper", function()
		assert.is_true(OD:SetTier(CAT, "HEALER", "b"))
		assert.is_true(OD:SetMyNote(CAT, "Can heal"))
		local SK2, W2 = setup({ rank = "Officer", rankIndex = 1 })
		local msg = { t = "OR", d = {} }
		for key, e in pairs(OD:Get()) do msg.d[key] = e end
		-- From Bob (raid leader): his own note can't be one written by Pip.
		msg.d["m:" .. CAT .. ":" .. BOB] = { v = "Bob's", u = W2.now, by = BOB }
		local fields = { d = msg.d }
		SK2.Sync:OnCommReceived(SK2.PREFIX, H.peerMessage(SK2, "OR", fields, BOB), "WHISPER", "Bob Stone")
		local dir2 = SK2.OfficerDir:Get()
		assert.same({ HEALER = "b" }, SK2.OfficerDir.TiersOf(dir2, CAT))
		assert.equal(2, #SK2.OfficerDir.NotesOf(dir2, CAT, W2.player.guid))
		assert.equal(0, #SK2.errors)
	end)
end)

describe("v0.13.0 roster planner rows and views", function()
	local SK, W, OD, RP
	before_each(function()
		SK, W = setup()
		OD, RP = SK.OfficerDir, SK.RosterPlan
		profile(SK, BOB, { talents = prot(), ilvl = 62, att = { ony = true } })
		profile(SK, CAT, { level = 58, talents = holy(), ilvl = 54.4, updated = W.now - 9 * 86400 })
		profile(SK, EVE, { level = 55, talents = prot(), ilvl = 50, att = { ony = false } })
	end)

	local function build()
		return RP.Build({ guild = SK.DBM:Guild(), dir = OD:Get(), now = W.now, me = W.player.guid,
			isOwn = function(g) return SK.DB.account[g] == true end })
	end
	local function byName(rows)
		local out = {}
		for _, r in ipairs(rows) do out[r.name] = r end
		return out
	end

	it("has one row per player, without Alt-rank characters", function()
		local r = byName(build())
		assert.is_nil(r["Dan Moss"])
		assert.truthy(r["Fay Reed"])
		assert.equal("Prot", r["Bob Stone"].spec)
		assert.equal("yes", r["Bob Stone"].att)
		assert.is_true(r["Bob Stone"].ready)
		assert.is_false(r["Bob Stone"].needsLook)
		assert.is_true(r["Cat Fern"].needsLook) -- 58, and data 9 days old
		assert.equal("9d", RP.AgeText(r["Cat Fern"].age))
		assert.is_false(r["Fay Reed"].hasData)
		assert.equal("no addon", RP.AgeText(r["Fay Reed"].age))
		assert.equal("TANK", r["Eve Moss"].guess)
		assert.is_true(r["Eve Moss"].close)
	end)

	it("folds an officer-linked alt into its main", function()
		assert.is_true(OD:Set("a", FAY, BOB))
		local r = byName(build())
		assert.is_nil(r["Fay Reed"])
		assert.same({ "Fay Reed" }, r["Bob Stone"].alts)
	end)

	it("shows a role's mains, backups and unsorted players whose spec fits", function()
		assert.is_true(OD:SetTier(BOB, "TANK", "m"))
		assert.is_true(OD:SetTier(CAT, "TANK", "b"))
		assert.is_true(OD:ToggleAway(BOB, date("%Y-%m-%d", W.now + 2 * 86400)))
		local rows = build()
		local items = RP.View(rows, { role = "T" })
		assert.is_true(items[1].section)
		assert.truthy(items[1].text:find("MAIN 1", 1, true))
		assert.truthy(items[1].text:find("ALL AT 60", 1, true))
		assert.equal("AWAY THIS WEEK: BOB STONE", items[1].away)
		assert.equal("Bob Stone", items[2].name)
		assert.truthy(items[3].text:find("OFF 1", 1, true))
		assert.equal("Cat Fern", items[4].name)
		assert.equal("NOT SORTED YET, SPEC FITS", items[5].text)
		assert.equal("Eve Moss", items[6].name)
		assert.equal(6, #items)
		local c = RP.Counts(rows)
		assert.same({ m = 1, b = 1 }, c.T)
		assert.equal(3, c.notSorted) -- Pip, Eve and Fay
	end)

	it("filters by status, needs a look and search; sorts inside groups", function()
		assert.is_true(OD:SetStatus(BOB, "r"))
		assert.is_true(OD:SetStatus(CAT, "b"))
		assert.is_true(OD:SetMyNote(CAT, "Ask about Onyxia"))
		local rows = build()
		assert.equal(1, #RP.View(rows, { role = "A", status = "r" }))
		assert.equal("Cat Fern", RP.View(rows, { role = "A", search = "onyxia" })[1].name)
		for _, r in ipairs(RP.View(rows, { role = "A", needs = true })) do assert.is_true(r.needsLook) end
		local nots = RP.View(rows, { role = "N" })
		for _, r in ipairs(nots) do assert.is_false(r.sorted) end
		-- GroupSort keeps headers on top whichever way a column sorts.
		assert.is_true(OD:SetTier(BOB, "TANK", "m"))
		assert.is_true(OD:SetTier(EVE, "TANK", "m"))
		local items = RP.View(build(), { role = "T" })
		local desc = false
		local cmp = RP.GroupSort(function(a, b) return a.level < b.level end, function() return desc end)
		table.sort(items, cmp)
		assert.is_true(items[1].section)
		assert.equal("Eve Moss", items[2].name)
		desc = true
		table.sort(items, function(a, b) return cmp(b, a) end)
		assert.is_true(items[1].section)
		assert.equal("Bob Stone", items[2].name)
	end)

	it("sums up the guild and says away days in words", function()
		local s = RP.Summary(build())
		assert.equal(1, s.at60 - (byName(build())["Pip Hocus"].level >= 60 and 1 or 0))
		assert.equal(1, s.attuned)
		assert.truthy(RP.SummaryText(s):find("attuned to Onyxia", 1, true))
		local function key(i) return date("%Y-%m-%d", W.now + i * 86400) end
		local function day(i) return tostring(tonumber(date("%d", W.now + i * 86400))) end
		-- A run of days, a single day, a weekly day, and nothing.
		local days = RP.AwayDays({ [key(2)] = true, [key(3)] = true, [key(4)] = true, [key(10)] = true }, nil, W.now)
		assert.equal(4, #days)
		local text = RP.AwayText(days, nil)
		assert.truthy(text:find(day(2) .. "-" .. day(4), 1, true) or text:find(day(2) .. " ", 1, true))
		assert.truthy(text:find(day(10), 1, true))
		local weekly = { w = { 2 } }
		local wd = RP.AwayDays({}, weekly, W.now)
		assert.equal(4, #wd)
		assert.equal("Every Tue", RP.AwayText(wd, weekly))
		assert.is_nil(RP.AwayText({}, nil))
	end)
end)

describe("v0.13.0 roster planner page", function()
	local SK, W, R, OD
	before_each(function()
		SK, W = setup()
		profile(SK, BOB, { talents = prot(), ilvl = 62, att = { ony = true } })
		profile(SK, CAT, { level = 58, talents = holy(), ilvl = 54 })
		H.loadUI(SK)
		SK.DB.officer[W.player.guid] = true
		SK.DB.settings.roster.officer = true
		SK.MainFrame:Open("roster")
		R, OD = SK.RosterTab, SK.OfficerDir
		R:Refresh()
	end)

	local function itemNamed(name)
		for _, it in ipairs(R.offList.items) do if it.name == name then return it end end
	end

	it("fits the planner's columns in the page", function()
		local total = 0
		for _, c in ipairs(R.PLAN_COLUMNS) do total = total + c.width end
		assert.equal(SK.Theme.SIZES.contentW - SK.Theme.SPACE.m, total)
		assert.is_true(R.PLAN_COLUMNS[#R.PLAN_COLUMNS].width >= 80) -- the note keeps some room
	end)

	it("lists players with counts on the chips and the guild summary", function()
		assert.is_true(R.offPanel:IsShown())
		assert.truthy(itemNamed("Bob Stone"))
		assert.is_nil(itemNamed("Dan Moss"))
		assert.truthy(R.planSummary:GetText():find("attuned to Onyxia", 1, true))
		assert.truthy(R.roleChips[1].label:GetText():find("All", 1, true))
		assert.equal(0, #SK.errors)
	end)

	it("sets status and roles from a cell's menu, and filters by role", function()
		local bob = itemNamed("Bob Stone")
		local anchor = W.stub()
		R.cellMenu:Open(anchor, R.CellItems(bob, "TANK"))
		assert.is_true(R.cellMenu:Run("Main"))
		R.cellMenu:Open(anchor, R.CellItems(itemNamed("Cat Fern"), "TANK"))
		assert.is_true(R.cellMenu:Run("Off"))
		R.cellMenu:Open(anchor, R.CellItems(itemNamed("Cat Fern"), "status"))
		assert.is_true(R.cellMenu:Run("Backup"))
		assert.same({ TANK = "m" }, OD.TiersOf(OD:Get(), BOB))
		assert.equal("b", OD.StatusOf(OD:Get(), CAT))
		R.roleChips[2]:GetScript("OnClick")(R.roleChips[2]) -- Tanks
		local items = R.offList.items
		assert.is_true(items[1].section)
		assert.equal("Bob Stone", items[2].name)
		assert.equal("Cat Fern", items[4].name)
		assert.truthy(R.roleChips[2].label:GetText():find("1+1", 1, true))
		R.statusChips[2]:GetScript("OnClick")(R.statusChips[2]) -- Backup only
		for _, it in ipairs(R.offList.items) do
			if not it.section then assert.equal("b", it.status) end
		end
		assert.equal(0, #SK.errors)
	end)

	it("opens a character from a name and notes from the note cell", function()
		R.offList.opts.onClick(itemNamed("Cat Fern"), "LeftButton")
		assert.equal("character", SK.MainFrame.current)
		SK.MainFrame:Open("roster")
		R:OpenNotes(itemNamed("Cat Fern"), W.stub())
		assert.is_true(R.noteBox:IsShown())
		R.noteBox.edit:SetText("Keen healer, ask about week 1")
		R:SaveMyNote()
		assert.is_false(R.noteBox:IsShown())
		assert.equal("Keen healer, ask about week 1", itemNamed("Cat Fern").note)
		R:OpenNotes(itemNamed("Cat Fern"), W.stub())
		assert.equal("Keen healer, ask about week 1", R.noteBox.edit:GetText())
		R.noteBox.edit:SetText("")
		R:SaveMyNote()
		assert.is_nil(itemNamed("Cat Fern").note)
		assert.equal(0, #SK.errors)
	end)

	it("shows sign-ups for a raid instead of Seen", function()
		local e = SK.RaidBoard:Create("ony", W.now + 86400)
		SK.RaidBoard:Get().signups[e.id] = { [CAT] = { s = "y", r = "HEALER", u = W.now } }
		R.signupMenu:Choose(e.id)
		assert.equal(e.id, R.signupsFor)
		assert.equal("y", itemNamed("Cat Fern").signed)
		R.signupMenu:Choose("")
		assert.is_nil(R.signupsFor)
		assert.equal(0, #SK.errors)
	end)
end)

describe("v0.13.0 Officers on the Character page", function()
	it("shows status, roles, notes and away days, and sets Alt of", function()
		local SK, W = setup()
		profile(SK, CAT, { level = 58, talents = holy(), ilvl = 54 })
		H.loadUI(SK)
		SK.DB.officer[W.player.guid] = true
		local OD, C = SK.OfficerDir, SK.CharacterTab
		assert.is_true(OD:SetStatus(CAT, "b"))
		assert.is_true(OD:SetTier(CAT, "HEALER", "m"))
		assert.is_true(OD:SetMyNote(CAT, "Keen healer"))
		C:ShowCharacter(CAT)
		assert.is_true(C.offStrip:IsShown())
		local sec = C.colA.sections[1]
		assert.equal("Officers", sec.title)
		assert.equal("Backup", sec.rows[1].value)
		assert.equal("Main", sec.rows[3].value)
		assert.equal("-", sec.rows[5].value) -- Away
		assert.truthy(sec.rows[6].text:find("Keen healer", 1, true))
		assert.is_true(OD:ToggleAway(CAT, date("%Y-%m-%d", W.now + 86400)))
		C:Refresh()
		assert.truthy(C.colA.sections[1].rows[5].value:find(tostring(tonumber(date("%d", W.now + 86400))), 1, true))
		C.altMenu:Choose(BOB)
		assert.equal(BOB, OD.AltOf(OD:Get(), CAT))
		-- A player without the addon still gets the Officers section.
		C:ShowCharacter(FAY)
		assert.equal("Officers", C.colB.sections[1].title)
		-- Members don't see any of it.
		SK.DB.officer[W.player.guid] = nil
		C:ShowCharacter(CAT)
		assert.is_false(C.offStrip:IsShown())
		assert.equal(0, #SK.errors)
	end)
end)

describe("v0.13.0 taller window", function()
	it("toggles from the Roster page's ··· menu", function()
		local SK = setup()
		H.loadUI(SK)
		SK.MainFrame:Open("roster")
		assert.equal(0, SK.MainFrame.TallH())
		assert.is_true(SK.RosterTab.options:Run("Taller window"))
		assert.equal(SK.MainFrame.TALL, SK.MainFrame.TallH())
		assert.is_true(SK.RosterTab.options:Run("Taller window"))
		assert.equal(0, SK.MainFrame.TallH())
		assert.equal(0, #SK.errors)
	end)
end)

describe("v0.13.0 Auto-fill uses the roster planner", function()
	it("puts Raiders and officer-set mains ahead", function()
		local SK = setup()
		local RG = SK.RaidGroups
		local function r(guid, name, role) return { guid = guid, name = name, role = role, status = "y" } end
		local L = { count = 2, groups = { {}, {} }, unplaced = {}, bench = {},
			available = { r("g1", "Aa", "TANK"), r("g2", "Bb", "TANK"), r("g3", "Cc", "TANK") } }
		-- Only two tank spots (10-man target): Cc is the main tank, Aa a Backup raider.
		local plan = { g3 = { status = "r", tiers = { TANK = "m" } }, g1 = { status = "b", tiers = { TANK = "m" } } }
		local moves = RG.AutoFill(L, "barrow", {}, plan)
		local benched = {}
		for _, m in ipairs(moves) do if m.kind == "bench" then benched[m.guid] = true end end
		assert.is_nil(benched.g3)
		assert.is_true(benched.g1) -- the Backup raider waits; the unsorted tank gets the second spot
		assert.is_nil(benched.g2)
	end)
end)

describe("v0.13.0 away calendar", function()
	it("shows their own and officer-set days, marks a day from the calendar, and flags a raid clash", function()
		local SK, W = setup()
		H.loadUI(SK)
		local R, OD = SK.RosterTab, SK.OfficerDir
		SK.DB.officer[W.player.guid] = true
		SK.DB.settings.roster.officer = true
		local e = SK.RaidBoard:Create("ony", W.now + 2 * 86400)
		assert.truthy(e)
		SK.MainFrame:Open("roster")
		local function rowOf(guid)
			for _, it in ipairs(R.offList.items) do if it.guid == guid then return it end end
		end
		assert.is_nil(rowOf(CAT).awayText)
		R:OpenAway(rowOf(CAT), W.stub())
		assert.is_true(R.awayBox:IsShown())
		-- Click the raid day's cell in the calendar.
		local raidKey = date("%Y-%m-%d", e.at)
		local hit
		for _, c in ipairs(R.awayBox.cells) do
			if c.cell and date("%Y-%m-%d", c.cell.at) == raidKey then hit = c end
		end
		assert.truthy(hit)
		assert.equal(1, #hit.cell.raids)
		hit:GetScript("OnClick")(hit)
		assert.is_true(OD.AwayOf(OD:Get(), CAT)[raidKey])
		local r = rowOf(CAT)
		assert.truthy(r.awayText)
		assert.is_true(r.awayClash)
		assert.is_true(r.awayNow)
		R:CloseAway()
		assert.is_false(R.awayBox:IsShown())
		assert.equal(0, #SK.errors)
	end)
end)
