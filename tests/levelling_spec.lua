-- v0.4.4: skill-up colours from Forever's own data, and the Levelling view.
local H = require("tests.helpers.load")

-- Bolt of Linen Cloth in Forever's SkillLineAbility: orange 1, yellow 25, grey 50.
local LINEN = 2963

describe("Skill-up ranges from Forever's data", function()
	local SK
	before_each(function() SK = H.load() end)

	it("nearly every recipe has a range, from the Forever build; the rest show no colour", function()
		assert.truthy(SK.Data.RECIPE_SOURCE.build:match("^1%.60%."))
		local with, without = 0, 0
		for _, list in pairs(SK.Data.RECIPE_LIST) do
			for _, e in ipairs(list) do
				if e[6] > 0 and e[7] >= e[6] then with = with + 1
				else
					without = without + 1
					assert.is_nil(SK.RecipeDB.Range(e[1]))
				end
			end
		end
		assert.is_true(with > 2000)
		assert.is_true(without < 50)
	end)

	it("Bolt of Linen Cloth: orange from 1, yellow 25, green 37, grey 50", function()
		assert.same({ orange = 1, yellow = 25, green = 37, grey = 50, ups = 1 }, SK.RecipeDB.Range(LINEN))
		assert.equal("orange", SK.RecipeDB.ColourAt(LINEN, 1))
		assert.equal("orange", SK.RecipeDB.ColourAt(LINEN, 24))
		assert.equal("yellow", SK.RecipeDB.ColourAt(LINEN, 25))
		assert.equal("green", SK.RecipeDB.ColourAt(LINEN, 37))
		assert.equal("grey", SK.RecipeDB.ColourAt(LINEN, 50))
		assert.equal(13, SK.RecipeDB.PointsLeft(LINEN, 37))
		assert.equal(0, SK.RecipeDB.PointsLeft(LINEN, 60))
		assert.is_nil(SK.RecipeDB.ColourAt(1, 10)) -- not a recipe
	end)

	it("lists only LEARNED recipes that still give skill-ups, best colour first", function()
		-- Forever's own numbers (not Classic): Bolt of Linen 25/37/50,
		-- Gray Woolen Shirt 90/100/110 (spell 2406), Woolen Cape 80/97/115 (2402).
		local known = { [LINEN] = true, [2406] = true, [2402] = true }
		local rows = SK.RecipeDB.SkillUps(197, 85, known)
		local ids = {}
		for _, r in ipairs(rows) do ids[#ids + 1] = r.recipeID .. ":" .. r.colour end
		assert.same({ "2406:orange", "2402:yellow" }, ids) -- linen is grey at 85
		assert.equal(0, #SK.RecipeDB.SkillUps(197, 85, {})) -- nothing learned: nothing listed
	end)

	it("Forever's 'orange from' is 1 for nearly everything, so it isn't shown", function()
		local ones, total = 0, 0
		for _, e in ipairs(SK.Data.RECIPE_LIST[197]) do
			total = total + 1
			if e[5] <= 1 then ones = ones + 1 end
		end
		assert.is_true(ones / total > 0.9)
		H.loadUI(SK)
		local text = SK.Theme.SkillRange(SK.RecipeDB.Range(LINEN))
		assert.truthy(text:find("25", 1, true) and text:find("37", 1, true) and text:find("50", 1, true))
		assert.is_nil(text:find("1|r", 1, true)) -- no "orange from 1"
	end)
end)

describe("Checking our colours against the profession window", function()
	local SK, W
	before_each(function()
		SK, W = H.load()
		W.member("Pocus Hocus", W.player.guid)
		W.professions = { { name = "Tailoring", rank = 30, max = 75, skillLine = 197 } }
		SK.Identity:ReadRoster()
		SK.Profile:BuildSelf()
	end)

	it("counts matches and keeps examples of differences, per build", function()
		W.tradeskill = { skillLine = 197, name = "Tailoring", rank = 30, max = 75, recipes = {
			[LINEN] = { learned = true, itemID = 2996, difficulty = 1 },  -- yellow: matches
			[3915] = { learned = true, itemID = 4344, difficulty = 3 },   -- grey: we say orange (1/35/60)
		} }
		SK.Professions:Scan()
		W.advance(1)
		local c = SK.DB.colourCheck
		assert.equal(1, c.match)
		assert.equal(1, c.differ)
		assert.same({ recipe = 3915, skill = 30, game = "grey", ours = "orange" }, c.examples[1])
	end)
end)

describe("Professions → Levelling", function()
	local SK, W
	before_each(function()
		SK, W = H.load()
		H.loadUI(SK)
		W.member("Pocus Hocus", W.player.guid)
		W.professions = { { name = "Tailoring", rank = 30, max = 75, skillLine = 197 },
			{ name = "Cooking", rank = 10, max = 75, skillLine = 185 } }
		SK.Identity:ReadRoster()
		SK.Profile:BuildSelf()
		local own = SK.Profile:Own()
		own.profs[197].scanned = W.now
		own.recipes[197] = { [LINEN] = 2996 }
		own.profs[197].primary = true
		own.profs[185].primary = false -- Cooking is a secondary profession
	end)

	it("shows your first primary profession's skill-ups, learned first", function()
		SK.DB.settings.profView = "levelling"
		SK.MainFrame:Show("professions")
		local tab = SK.ProfessionsTab
		assert.is_true(tab.levelList:IsShown())
		assert.equal(197, SK.ProfessionsTab.LevelProfession())
		assert.equal(LINEN, tab.levelList.items[1].recipeID)
		assert.is_true(tab.levelList.items[1].known)
		assert.truthy(tab.status:GetText():find("1 learned recipe still give skill-ups", 1, true))
		assert.equal(0, #SK.errors)
	end)

	it("switches profession and asks you to open a window it hasn't seen", function()
		SK.DB.settings.profView = "levelling"
		SK.MainFrame:Show("professions")
		local tab = SK.ProfessionsTab
		tab.levelMenu:Choose(185)
		assert.equal(185, SK.DB.settings.levelProf)
		assert.truthy(tab.status:GetText():find("Open your Cooking window once", 1, true))
		assert.equal(0, #SK.errors)
	end)

	it("recipe tooltips say the range and your colour", function()
		local text = SK.Widgets.SkillUpText(LINEN, 197)
		assert.truthy(text:find("Yellow · green · grey at", 1, true))
		assert.truthy(text:find("for you (30): ", 1, true)) -- learned
		assert.truthy(text:find("yellow", 1, true))
		assert.is_nil(SK.Widgets.SkillUpText(2406, 197):find("for you", 1, true)) -- not learned: no colour for you
		assert.is_nil(SK.Widgets.SkillUpText(1, 197))
	end)

	it("no professions: says so", function()
		local own = SK.Profile:Own()
		own.profs = {}
		SK.DB.settings.profView = "levelling"
		SK.MainFrame:Show("professions")
		assert.truthy(SK.ProfessionsTab.levelList.emptyText:find("haven't learned a profession", 1, true))
		assert.equal(0, #SK.errors)
	end)
end)
