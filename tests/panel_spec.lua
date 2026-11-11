-- luacheck: globals ProfessionsFrame EventRegistry
-- v0.5.3: the panel beside Blizzard's profession window, and recipe filters.
local H = require("tests.helpers.load")

local SHIRT, CAPE, RED_BAG = 2406, 2402, 6688

describe("Panel beside the profession window", function()
	local SK, W, selected
	before_each(function()
		SK, W = H.load()
		H.loadUI(SK)
		W.member("Pocus Hocus", W.player.guid)
		W.professions = { { name = "Tailoring", rank = 85, max = 110, skillLine = 197 } }
		SK.Identity:ReadRoster()
		SK.Profile:BuildSelf()
		local own = SK.Profile:Own()
		own.profs[197].scanned = W.now
		own.recipes[197] = { [SHIRT] = 2587, [CAPE] = 2584 }
		_G.TSM_API = { GetCustomPriceValue = function() return 100 end }
		_G.ProfessionsFrame = CreateFrame("Frame")
		_G.EventRegistry = { RegisterCallback = function(_, event, fn)
			if event == "ProfessionsRecipeListMixin.Event.OnRecipeSelected" then selected = fn end
		end }
		SK.ProfPanel:OnInit()
		W.tradeskill = { skillLine = 197, name = "Tailoring", rank = 85, max = 110, recipes = {
			[SHIRT] = { learned = true, itemID = 2587, difficulty = 0 },
		} }
	end)
	after_each(function() _G.TSM_API, _G.ProfessionsFrame, _G.EventRegistry = nil, nil, nil end)

	it("says the next route step and, for a picked recipe, its colour, where to learn it and the guild", function()
		W.fire("TRADE_SKILL_SHOW")
		W.advance(1)
		local f = SK.ProfPanel.frame
		assert.truthy(f)
		assert.is_true(f:IsShown())
		assert.truthy(f.body:GetText():find("Next on your route", 1, true))
		assert.truthy(f.body:GetText():find("85 - ", 1, true))
		selected(nil, { recipeID = RED_BAG })
		local text = f.body:GetText()
		assert.truthy(text:find("Learn from", 1, true))
		assert.truthy(text:find("Guild:", 1, true))
		assert.is_nil(text:find("profit", 1, true)) -- Profit isn't unlocked
		f.add:GetScript("OnClick")(f.add)
		assert.equal(1, SK.Shopping.Crafts(RED_BAG))
		W.fire("TRADE_SKILL_CLOSE")
		assert.is_false(f:IsShown())
		assert.equal(0, #SK.errors)
	end)

	it("/sr panel turns it off and on; Hide turns it off", function()
		SK.Commands.Run("panel")
		assert.is_false(SK.DB.settings.profPanel)
		W.fire("TRADE_SKILL_SHOW")
		W.advance(1)
		assert.is_true(SK.ProfPanel.frame == nil or not SK.ProfPanel.frame:IsShown())
		SK.Commands.Run("panel")
		assert.is_true(SK.DB.settings.profPanel)
		W.fire("TRADE_SKILL_SHOW")
		W.advance(1)
		local f = SK.ProfPanel.frame
		assert.is_true(f:IsShown())
		f.hide:GetScript("OnClick")(f.hide)
		assert.is_false(SK.DB.settings.profPanel)
		assert.is_false(f:IsShown())
		assert.truthy(table.concat(SK.Commands.HELP, "\n"):find("/sr panel", 1, true))
	end)

	it("wording", function()
		local L = SK.ProfPanel.Lines
		local function text(o)
			local t = {}
			for _, l in ipairs(L(o)) do t[#t + 1] = l[1] end
			return table.concat(t, "\n")
		end
		assert.truthy(text({ atCap = true }):find("at your cap", 1, true))
		assert.truthy(text({ step = { stuck = true, from = 120 } }):find("Nothing you know gives points at 120", 1, true))
		assert.truthy(text({ step = { from = 85, to = 95, crafts = 10, learn = {} }, stepName = "Woolen Cape",
			total = "1g" }):find("85 - 95: 10x Woolen Cape (learn it first)", 1, true))
		assert.truthy(text({}):find("Open this window once", 1, true))
	end)
end)

describe("Recipe filters", function()
	local SK
	before_each(function() SK = H.load(); H.loadUI(SK) end)

	it("keeps what each filter asks for", function()
		local F = SK.ProfessionsTab.FilterRecipes
		local rows = { { recipeID = 1, skillLine = 197, name = "a" }, { recipeID = 2, skillLine = 197, name = "b" },
			{ recipeID = 3, skillLine = 197, name = "c" }, { recipeID = 4, skillLine = 171, name = "d" } }
		local function you(line) if line == 197 then return { skill = 100, known = { [3] = true } } end end
		local function learnAt(id) return ({ [1] = 120, [2] = 90, [4] = 10 })[id] end
		local function hasItem(id) return id == 1 or id == 4 end
		local function colourAt(id, skill) return id == 3 and skill < 110 and "yellow" or "grey" end
		local function ids(list)
			local out = {}
			for i, r in ipairs(list) do out[i] = r.recipeID end
			return out
		end
		assert.equal(rows, F(rows, "all", you, learnAt, hasItem, colourAt))
		assert.same({ 2 }, ids(F(rows, "learnable", you, learnAt, hasItem, colourAt))) -- 1 needs 120; 4: not your profession
		assert.same({ 4, 1 }, ids(F(rows, "item", you, learnAt, hasItem, colourAt)))  -- by learn level
		assert.same({ 2, 3 }, ids(F(rows, "trainer", you, learnAt, hasItem, colourAt)))
		assert.same({ 3 }, ids(F(rows, "points", you, learnAt, hasItem, colourAt)))
	end)

	it("All recipes has the Show menu", function()
		SK.DB.settings.profView = "recipes"
		SK.MainFrame:Show("professions")
		local tab = SK.ProfessionsTab
		assert.is_true(tab.showMenu:IsShown())
		tab.showMenu:Choose("item")
		assert.equal("item", tab.allFilter)
		assert.equal(0, #SK.errors)
	end)
end)
