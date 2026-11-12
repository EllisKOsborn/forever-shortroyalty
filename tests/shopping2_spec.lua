-- v0.5.1: shopping list upgrades (tooltips, make or buy, raw materials, TSM list).
local H = require("tests.helpers.load")

-- Forever's data: Bolt of Woolen Cloth (2964) = 3 Wool Cloth (2592) -> 1 bolt (2997).
-- Gray Woolen Shirt (2406) = 2 bolts, 1 Fine Thread (2321), 1 Gray Dye (4340).
local WOOL_BOLT_RECIPE, SHIRT = 2964, 2406
local BOLT, WOOL, THREAD, DYE = 2997, 2592, 2321, 4340

local function byItem(rows)
	local out = {}
	for _, r in ipairs(rows) do out[r.itemID] = r end
	return out
end

describe("Shopping list upgrades", function()
	local SK, W
	before_each(function()
		SK, W = H.load()
		W.member("Pocus Hocus", W.player.guid)
		W.professions = { { name = "Tailoring", rank = 100, max = 150, skillLine = 197 } }
		SK.Identity:ReadRoster()
		SK.Profile:BuildSelf()
		SK.Profile:Own().recipes[197] = { [WOOL_BOLT_RECIPE] = BOLT, [SHIRT] = 2587 }
		_G.TSM_API = { GetCustomPriceValue = function(src, item)
			if src == "VendorBuy" then return nil end
			return ({ ["i:" .. BOLT] = 100, ["i:" .. WOOL] = 20, ["i:" .. THREAD] = 5, ["i:" .. DYE] = 30 })[item]
		end }
	end)
	after_each(function() _G.TSM_API = nil end)

	it("prices a reagent you make at the cheaper of buying and making it", function()
		assert.same({ 60, WOOL_BOLT_RECIPE }, { SK.Prices.Make(BOLT) }) -- 3 x 20c
		assert.same({ 60, "make" }, { SK.Prices.Buy(BOLT) })
		assert.same({ 20, "ah" }, { SK.Prices.Buy(WOOL) }) -- nobody makes wool
		SK.Prices.LearnMerchant({ { itemID = BOLT, each = 50 } })
		assert.same({ 50, "vendor" }, { SK.Prices.Buy(BOLT) })
		-- the shirt's cost uses the cheapest bolt: 2 x 50 + 5 + 30
		assert.equal(135, SK.Prices.Recipe(SHIRT).cost)
	end)

	it("raw materials: bolts you're short of become crafts, and their wool is added", function()
		SK.Shopping.Set(SHIRT, 3)
		W.bags[BOLT] = 2
		local plain = byItem((SK.Shopping.Rows(false)))
		assert.equal(4, plain[BOLT].short)
		assert.is_nil(plain[WOOL])
		local rows = SK.Shopping.Rows(true)
		local r = byItem(rows)
		assert.equal(4, r[BOLT].make)   -- 6 needed, 2 in bags: make 4
		assert.equal(12, r[WOOL].need)  -- 4 x 3 wool
		-- cost leaves out what you make: 12 wool x 20 + 3 thread x 5 + 3 dye x 30
		assert.equal(345, (SK.Shopping.Cost(rows, function(id) return (SK.Prices.Buy(id)) end)))
		assert.truthy(SK.Shopping.Text(SK.Shopping.Entries(), rows, function() return "x" end):find("- make 4x x", 1, true))
	end)

	it("lists what's left to buy for TSM, without what you make or already have", function()
		SK.Shopping.Set(SHIRT, 1)
		W.bags[THREAD] = 5
		local list = SK.Shopping.TSMList(SK.Shopping.Rows(true))
		local ids = {}
		for id in list:gmatch("i:(%d+)") do ids[tonumber(id)] = true end
		assert.same({ [WOOL] = true, [DYE] = true }, ids)
		assert.equal("", SK.Shopping.TSMList({}))
	end)

	it("item tooltips: need, have, and make", function()
		SK.Shopping.Set(SHIRT, 2)
		W.bags[DYE] = 1
		SK.Shopping.Dirty()
		H.loadUI(SK)
		local T = SK.Tooltip
		assert.equal("Shopping list: need 2, have 1, 1 to get", T.ShoppingText(SK.Shopping.ItemNeed(DYE)))
		assert.is_nil(SK.Shopping.ItemNeed(424242))
		assert.equal("Shopping list: make 4 (need 4)", T.ShoppingText({ make = 4, need = 4 }))
		W.bags[DYE] = 5
		W.fire("BAG_UPDATE_DELAYED") -- the cache follows your bags
		assert.equal("Shopping list: need 2, have 5, got it", T.ShoppingText(SK.Shopping.ItemNeed(DYE)))
		SK.Shopping.Clear()
		assert.is_nil(SK.Shopping.ItemNeed(DYE))
	end)

	it("the Shopping list view has Raw materials and Copy for TSM", function()
		H.loadUI(SK)
		SK.Shopping.Set(SHIRT, 1)
		SK.DB.settings.profView = "shopping"
		SK.MainFrame:Show("professions")
		local tab = SK.ProfessionsTab
		tab.shopRaw:GetScript("OnClick")(tab.shopRaw)
		assert.is_true(SK.DB.settings.shopRaw)
		local found
		for _, r in ipairs(tab.shopReagents.items) do if r.itemID == WOOL then found = r end end
		assert.truthy(found)
		assert.truthy(tab:CopyTSM():find("i:" .. WOOL, 1, true))
		assert.equal("  (you make it)", tab.ViaText("make"))
		assert.equal(0, #SK.errors)
	end)
end)
