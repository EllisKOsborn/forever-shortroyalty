-- v0.5.0: where to learn each recipe (Forever's recipe items, trainers you
-- visit, the game's own text). Local only.
local H = require("tests.helpers.load")

-- Forever's data: Pattern: Red Woolen Bag (5772) teaches Red Woolen Bag (6688)
-- at Tailoring 90; Pattern: Azure Silk Gloves (7114) teaches 3854 at 120.
-- Bolt of Linen Cloth (2963) and Azure Silk Hood (8760) have no recipe item.
local RED_BAG, GLOVES, LINEN_BOLT, HOOD = 6688, 3854, 2963, 8760

describe("Recipe items from Forever's data", function()
	local SK
	before_each(function() SK = H.load() end)

	it("links patterns to the recipes they teach, with the skill needed", function()
		assert.same({ 5772, 90 }, { SK.RecipeDB.RecipeItem(RED_BAG) })
		assert.same({ 7114, 120 }, { SK.RecipeDB.RecipeItem(GLOVES) })
		assert.is_nil(SK.RecipeDB.RecipeItem(LINEN_BOLT)) -- trainer
		assert.is_nil(SK.RecipeDB.RecipeItem(HOOD))       -- trainer
		local n = 0
		for _ in pairs(SK.Data.RECIPE_ITEMS) do n = n + 1 end
		assert.is_true(n > 1500 and n < SK.RecipeDB.Count())
	end)

	it("every recipe item is for a recipe in the list", function()
		for recipeID, e in pairs(SK.Data.RECIPE_ITEMS) do
			assert.truthy(SK.RecipeDB.Get(recipeID), "recipe " .. recipeID)
			assert.is_true(e[1] > 0 and e[2] >= 0)
		end
	end)
end)

describe("Learn", function()
	local SK, W
	before_each(function()
		SK, W = H.load()
		W.member("Pocus Hocus", W.player.guid)
		W.professions = { { name = "Tailoring", rank = 125, max = 150, skillLine = 197 } }
		SK.Identity:ReadRoster()
		SK.Profile:BuildSelf()
	end)

	local function ctx()
		return { profName = "Tailoring", itemName = function(id) return ({ [5772] = "Pattern: Red Woolen Bag" })[id] end,
			price = function(id) if id == 5772 then return 500, "vendor" end end, money = SK.Prices.Money }
	end

	it("words a recipe item, a trainer and the game's own text", function()
		local L = SK.Learn
		assert.same({ "Learn from Pattern: Red Woolen Bag (Tailoring 90), 5s at a vendor" },
			L.Lines({ item = 5772, itemAt = 90 }, ctx()))
		assert.same({ "Trainer: Tailoring 125, 45s" }, L.Lines({ trainerAt = 125, trainerCost = 4500 }, ctx()))
		assert.same({ "Source: Trainer" }, L.Lines({ text = "Trainer" }, ctx()))
		assert.truthy(L.Lines({}, ctx())[1]:find("usually a trainer", 1, true))
	end)

	it("cleans game text: no colours, links or line breaks", function()
		assert.equal("Vendor: Alexandra Bolero, Zone: Stormwind City",
			SK.Learn.Plain("|cffffd200Vendor:|r Alexandra Bolero|n|cffffd200Zone:|r Stormwind City"))
		assert.is_nil(SK.Learn.Plain("  |n "))
		assert.is_nil(SK.Learn.Plain(nil))
		assert.equal(SK.Learn.MAX_TEXT, #SK.Learn.Plain(string.rep("a", 400)))
	end)

	it("matches a trainer's list to recipes by name, within the trainer's profession", function()
		local L = SK.Learn
		local index = { ["azure silk hood"] = { HOOD }, ["twin"] = { 1, 2 } }
		local found, matched = L.Match({
			{ name = "Azure Silk Hood", kind = "available", skill = "Tailoring", rank = 145, cost = 2200 },
			{ name = "Twin", kind = "available", skill = "Tailoring", rank = 50 },          -- two recipes: skipped
			{ name = "Azure Silk Hood", kind = "available", skill = "Juggling", rank = 1 }, -- not a profession
			{ name = "Journeyman Tailoring", kind = "available" },                          -- no skill: the rank itself
		}, function(skillLine) return skillLine == 197 and index or nil end)
		assert.same({ [HOOD] = { at = 145, cost = 2200 } }, found)
		assert.equal(1, matched)
	end)

	it("reads the trainer window when it opens and remembers what it teaches", function()
		_G.GetNumTrainerServices = function() return 2 end
		_G.GetTrainerServiceInfo = function(i) return ({ "Azure Silk Hood", "Header" })[i], ({ "available", "header" })[i] end
		_G.GetTrainerServiceSkillReq = function() return "Tailoring", 145, true end
		_G.GetTrainerServiceCost = function() return 2200 end
		W.spellNames = W.spellNames or {}
		local real = SK.Compat.SpellName
		SK.Compat.SpellName = function(id) return id == HOOD and "Azure Silk Hood" or real(id) end
		W.fire("TRAINER_SHOW")
		SK.Compat.SpellName = real
		_G.GetNumTrainerServices, _G.GetTrainerServiceInfo, _G.GetTrainerServiceSkillReq, _G.GetTrainerServiceCost =
			nil, nil, nil, nil
		assert.same({ at = 145, cost = 2200 }, { at = SK.DB.trainer[HOOD].at, cost = SK.DB.trainer[HOOD].cost })
		assert.same({ listed = 1, matched = 1 }, { listed = SK.Learn.lastTrainer.listed, matched = SK.Learn.lastTrainer.matched })
		-- trainable at 145 or more, not before
		assert.same({}, SK.Learn.Trainable(197, 140, {}))
		assert.same({ HOOD }, SK.Learn.Trainable(197, 145, {}))
		assert.same({}, SK.Learn.Trainable(197, 150, { [HOOD] = true }))
	end)

	it("stores the game's text and reasons from a profession scan, and /sr debug reports them", function()
		W.tradeskill = { skillLine = 197, name = "Tailoring", rank = 125, max = 150, recipes = {
			[LINEN_BOLT] = { learned = true, itemID = 2996, difficulty = 3 },
			[HOOD] = { learned = false, itemID = 7048, source = "|cffffd200Source:|r Trainer", reason = "Requires Tailoring (145)" },
		} }
		SK.Professions:Scan()
		W.advance(1)
		assert.same({ text = "Source: Trainer", reason = "Requires Tailoring (145)" }, SK.DB.recipeSource[HOOD])
		assert.is_nil(SK.DB.recipeSource[LINEN_BOLT]) -- learned: nothing stored
		local info = SK.Learn.Info(HOOD)
		assert.equal("Source: Trainer", info.text)
		H.loadUI(SK)
		local report = table.concat(SK.Commands.BuildReport(), "\n")
		assert.truthy(report:find("game's source text this session: 1 recipes", 1, true))
		assert.truthy(report:find("Requires Tailoring (145)", 1, true))
		assert.truthy(report:find("Trainers: 0 recipes remembered", 1, true))
	end)
end)

describe("Where to learn, in the UI", function()
	local SK, W
	before_each(function()
		SK, W = H.load()
		H.loadUI(SK)
		W.member("Pocus Hocus", W.player.guid)
		W.professions = { { name = "Tailoring", rank = 145, max = 150, skillLine = 197 } }
		SK.Identity:ReadRoster()
		SK.Profile:BuildSelf()
		local own = SK.Profile:Own()
		own.profs[197].scanned = W.now
		own.profs[197].primary = true
		own.recipes[197] = { [LINEN_BOLT] = 2996 }
	end)

	it("recipe tooltips say where to learn it, unless you know it", function()
		local lines = SK.Widgets.LearnLines(RED_BAG, 197)
		assert.truthy(lines[1]:find("Learn from", 1, true))
		assert.truthy(lines[1]:find("Tailoring 90", 1, true))
		assert.same({}, SK.Widgets.LearnLines(LINEN_BOLT, 197)) -- known
	end)

	it("Levelling counts recipes your trainer would teach you now", function()
		SK.DB.trainer[HOOD] = { at = 145, cost = 2200 }
		SK.DB.settings.profView = "levelling"
		SK.MainFrame:Show("professions")
		assert.truthy(SK.ProfessionsTab.status:GetText():find("1 to learn at your trainer", 1, true))
		assert.equal(0, #SK.errors)
	end)
end)
