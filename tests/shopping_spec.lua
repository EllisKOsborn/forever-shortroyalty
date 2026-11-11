-- v0.4.5: shopping list (levelling tools step 2). Local only.
local H = require("tests.helpers.load")

-- Forever's data: Gray Woolen Shirt (2406) = 2 Bolt of Woolen Cloth (2997),
-- 1 Fine Thread (2321), 1 Gray Dye (4340); Woolen Cape (2402) = 1 Bolt of
-- Woolen Cloth, 1 Fine Thread; Bolt of Linen Cloth (2963) = 2 Linen Cloth (2589).
local SHIRT, CAPE, LINEN_BOLT = 2406, 2402, 2963
local WOOL_BOLT, THREAD, DYE, LINEN = 2997, 2321, 4340, 2589

local function byItem(rows)
	local out = {}
	for _, r in ipairs(rows) do out[r.itemID] = r end
	return out
end

describe("Shopping list", function()
	local SK, W
	before_each(function() SK, W = H.load() end)

	it("adds, counts, lowers and removes recipes, in the order added", function()
		assert.is_true(SK.Shopping.Add(SHIRT))
		SK.Shopping.Add(CAPE, 3)
		SK.Shopping.Add(SHIRT, 4)
		assert.equal(5, SK.Shopping.Crafts(SHIRT))
		assert.same({ { id = SHIRT, n = 5 }, { id = CAPE, n = 3 } }, SK.Shopping.Entries())
		SK.Shopping.Add(CAPE, -3)
		assert.equal(0, SK.Shopping.Crafts(CAPE))
		assert.equal(1, #SK.Shopping.Entries())
		SK.Shopping.Set(SHIRT, 5000)
		assert.equal(SK.Shopping.MAX_CRAFTS, SK.Shopping.Crafts(SHIRT))
		SK.Shopping.Clear()
		assert.equal(0, #SK.Shopping.Entries())
		assert.is_false(SK.Shopping.Set("x", 1))
	end)

	it("stops at the maximum number of recipes", function()
		for i = 1, SK.Shopping.MAX_RECIPES do assert.is_true(SK.Shopping.Set(i, 1)) end
		assert.is_false(SK.Shopping.Add(999999))
		assert.is_true(SK.Shopping.Add(1)) -- one already on it can still go up
	end)

	it("adds up reagents across recipes, with bags and bank", function()
		SK.Shopping.Set(SHIRT, 2)
		SK.Shopping.Set(CAPE, 3)
		W.bags[WOOL_BOLT], W.bank[WOOL_BOLT] = 2, 3
		W.bags[THREAD] = 10
		local rows, unknown = SK.Shopping.Rows()
		assert.equal(0, #unknown)
		local r = byItem(rows)
		assert.same({ need = 7, bags = 2, bank = 3, have = 5, short = 2 }, -- 2x2 + 3x1
			{ need = r[WOOL_BOLT].need, bags = r[WOOL_BOLT].bags, bank = r[WOOL_BOLT].bank,
				have = r[WOOL_BOLT].have, short = r[WOOL_BOLT].short })
		assert.equal(5, r[THREAD].need)
		assert.equal(0, r[THREAD].short)
		assert.equal(2, r[DYE].short)
		assert.same({ SHIRT, CAPE }, r[WOOL_BOLT].recipes)
		-- still-to-get first
		assert.is_true(rows[1].short > 0 and rows[2].short > 0)
		assert.equal(THREAD, rows[3].itemID)
	end)

	it("keeps the reagents for one craft, not the first 8 only, and notes recipes without data", function()
		local rows, unknown = SK.Shopping.Totals({ { id = 1, n = 2 }, { id = 2, n = 1 } }, function(id)
			if id == 2 then return nil end
			local r = {}
			for i = 1, 10 do r[i] = { i = 100 + i, q = 1 } end
			return r
		end, function() return nil end)
		assert.equal(10, #rows)
		assert.equal(2, rows[1].need)
		assert.is_nil(rows[1].have) -- the game couldn't count it
		assert.same({ 2 }, unknown)
	end)

	it("says when you know a recipe that makes a reagent", function()
		W.member("Pocus Hocus", W.player.guid)
		W.professions = { { name = "Tailoring", rank = 30, max = 75, skillLine = 197 } }
		SK.Identity:ReadRoster()
		SK.Profile:BuildSelf()
		SK.Profile:Own().recipes[197] = { [LINEN_BOLT] = 2996 }
		assert.equal(LINEN_BOLT, SK.Shopping.YouMake(2996))
		assert.is_nil(SK.Shopping.YouMake(WOOL_BOLT)) -- Bolt of Woolen Cloth: not learned
	end)

	it("copies as plain text", function()
		SK.Shopping.Set(LINEN_BOLT, 3)
		W.bags[LINEN] = 2
		local text = SK.Shopping.Text(SK.Shopping.Entries(), SK.Shopping.Rows(), function(_, isRecipe)
			return isRecipe and "|cffffffffBolt of Linen Cloth|r" or "Linen Cloth"
		end)
		assert.equal("Shopping list (Short Royalty)\nTo craft:\n- 3x Bolt of Linen Cloth\nStill to get:\n" ..
			"- 4 Linen Cloth (need 6, have 2)", text)
	end)

	it("is never part of a synced profile", function()
		SK.Shopping.Set(SHIRT, 1)
		W.member("Pocus Hocus", W.player.guid)
		SK.Identity:ReadRoster()
		SK.Profile:BuildSelf()
		local public = SK.Profile.Public(SK.Profile:Own(), SK.DB.settings.share)
		for k in pairs(public) do assert.is_nil(k:find("shop")) end
	end)
end)

describe("Professions → Shopping list", function()
	local SK, W
	before_each(function()
		SK, W = H.load()
		H.loadUI(SK)
	end)
	after_each(function() _G.IsShiftKeyDown = nil end)

	it("shows recipes and reagents, and refreshes when the list changes", function()
		SK.DB.settings.profView = "shopping"
		SK.MainFrame:Show("professions")
		local tab = SK.ProfessionsTab
		assert.is_true(tab.shopRecipes:IsShown())
		assert.truthy(tab.shopRecipes.emptyText:find("Shift-click", 1, true))
		SK.Shopping.Set(SHIRT, 2)
		assert.equal(SHIRT, tab.shopRecipes.items[1].recipeID)
		assert.equal(3, #tab.shopReagents.items)
		assert.truthy(tab.status:GetText():find("3 still to get", 1, true))
		W.bags[WOOL_BOLT], W.bags[THREAD], W.bags[DYE] = 4, 2, 2
		W.fire("BAG_UPDATE_DELAYED")
		assert.truthy(tab.status:GetText():find("you have everything", 1, true))
		assert.truthy(tab:CopyShopping():find("Already have:", 1, true))
		assert.equal(0, #SK.errors)
	end)

	it("Shift-click on a recipe adds it; a plain click still opens Crafters", function()
		local tab = SK.ProfessionsTab
		SK.MainFrame:Show("professions")
		_G.IsShiftKeyDown = function() return true end
		tab.allList.opts.onClick({ recipeID = CAPE, skillLine = 197, itemID = 2584 }, "LeftButton")
		tab.allList.opts.onClick({ recipeID = CAPE, skillLine = 197, itemID = 2584 }, "LeftButton")
		assert.equal(2, SK.Shopping.Crafts(CAPE))
		_G.IsShiftKeyDown = function() return false end
		tab.levelList.opts.onClick({ recipeID = CAPE, skillLine = 197, itemID = 2584 }, "LeftButton")
		assert.equal(2, SK.Shopping.Crafts(CAPE))
		assert.equal(CAPE, SK.CraftersTab.selected)
		assert.equal(0, #SK.errors)
	end)

	it("the Crafters panel's + List chip adds a craft", function()
		SK.CraftersTab:ShowRecipe(SHIRT, 197)
		assert.is_true(SK.CraftersTab.listButton:IsShown())
		SK.CraftersTab.listButton:GetScript("OnClick")(SK.CraftersTab.listButton)
		assert.equal(1, SK.Shopping.Crafts(SHIRT))
		assert.truthy(SK.CraftersTab.listButton.tooltip:find("1 craft", 1, true))
		assert.equal(0, #SK.errors)
	end)

	it("summary line", function()
		assert.equal("", SK.ProfessionsTab.ShopSummary(0, 0, 0, 0))
		local t = SK.ProfessionsTab.ShopSummary(2, 3, 0, 1)
		assert.truthy(t:find("2 recipes", 1, true) and t:find("3 reagents", 1, true) and
			t:find("you have everything", 1, true) and t:find("1 without reagent data", 1, true))
	end)
end)
