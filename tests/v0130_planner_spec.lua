-- v0.13.0: the raid roster planner (officers' feedback, 21 Nov): role tiers
-- (Main / Backup), Raider / Backup status, away weeks, notes from several
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

describe("v0.13.0 officer roster: tiers, status, away weeks, notes", function()
	local SK, W, OD
	before_each(function()
		SK, W = setup()
		OD = SK.OfficerDir
	end)

	it("sets Main / Backup per role, Raider / Backup and away weeks", function()
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
		assert.is_true(OD:ToggleAway(CAT, 3))
		assert.is_true(OD:ToggleAway(CAT, 1))
		assert.equal("1,3", OD:Get()["w:" .. CAT].v)
		assert.is_true(OD:ToggleAway(CAT, 3))
		assert.same({ [1] = true }, OD.AwayOf(OD:Get(), CAT))
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
		assert.is_true(OD.Merge(dir, "w:" .. CAT, { v = "1,2", u = now, by = BOB }, now, lead, member))
		assert.is_false(OD.Merge(dir, "w:" .. EVE, { v = "0", u = now, by = BOB }, now, lead, member))
		assert.is_false(OD.Merge(dir, "w:" .. EVE, { v = "1,x", u = now, by = BOB }, now, lead, member))
		assert.is_false(OD.Merge(dir, "w:" .. EVE, { v = string.rep("1,", 13) .. "1", u = now, by = BOB }, now, lead, member))
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
			progress = SK.DB.rosterProgress, isOwn = function(g) return SK.DB.account[g] == true end })
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
		assert.equal("Protection", r["Bob Stone"].spec)
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
		assert.is_true(OD:ToggleAway(BOB, RP.PlanWeek(W.now)))
		local rows = build()
		local items = RP.View(rows, { role = "T", week = RP.PlanWeek(W.now) })
		assert.is_true(items[1].section)
		assert.truthy(items[1].text:find("MAIN 1", 1, true))
		assert.truthy(items[1].text:find("ALL AT 60", 1, true))
		assert.truthy(items[1].away:find("BOB STONE AWAY WEEK", 1, true))
		assert.equal("Bob Stone", items[2].name)
		assert.truthy(items[3].text:find("BACKUP 1", 1, true))
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

	it("remembers progress once a day and shows the last week's gain", function()
		local store = SK.DB.rosterProgress
		local rows = build()
		W.now = W.now - 8 * 86400
		RP.Record(store, { { guid = CAT, level = 54, ilvl = 50 } }, W.now)
		W.now = W.now + 8 * 86400
		RP.Record(store, rows, W.now)
		RP.Record(store, rows, W.now)
		assert.equal(2, #store[CAT])
		local r = byName(build())
		assert.equal(4, r["Cat Fern"].levelGain)
		assert.equal(4.4, r["Cat Fern"].ilvlGain)
		assert.is_nil(r["Bob Stone"].levelGain)
		W.now = W.now + 60 * 86400
		RP.Record(store, rows, W.now)
		assert.equal(1, #store[CAT])
	end)

	it("sums up the guild and labels reset weeks", function()
		local s = RP.Summary(build())
		assert.equal(1, s.at60 - (byName(build())["Pip Hocus"].level >= 60 and 1 or 0))
		assert.equal(1, s.attuned)
		assert.truthy(RP.SummaryText(s):find("attuned to Onyxia", 1, true))
		assert.equal(1, RP.Week(RP.RESET0))
		assert.equal(2, RP.Week(RP.RESET0 + 7 * 86400))
		assert.equal(1, RP.PlanWeek(RP.RESET0 - 86400))
		assert.equal("Week 1 (9 Dec)", RP.WeekLabel(1))
		assert.same({ 6, 7, 8, 9 }, RP.WeeksOffered(W.now))
	end)
end)
