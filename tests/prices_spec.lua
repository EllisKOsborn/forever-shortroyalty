-- v0.4.6: prices and profit (levelling tools step 3). Local only.
local H = require("tests.helpers.load")

-- Forever's data: Bolt of Linen Cloth (2963) = 2 Linen Cloth (2589) -> 1 bolt (2996);
-- Crafted Light Shot (3947) = 1 Copper Bar (2840)... makes 200 (8067/8069).
local LINEN_BOLT, LINEN, BOLT = 2963, 2589, 2996

local function fakePrices(buy, sell)
	return {
		Buy = function(id) return buy[id] end,
		Sell = function(id) local v = sell[id]; if v then return v[1], v[2] end end,
	}
end

describe("Prices", function()
	local SK
	before_each(function()
		SK = H.load()
		_G.Auctionator, _G.TSM_API = nil, nil
	end)
	after_each(function() _G.Auctionator, _G.TSM_API = nil, nil end)

	it("formats money like the game: 12g 3s 40c", function()
		local M = SK.Prices.Money
		assert.equal("0c", M(0))
		assert.equal("40c", M(40))
		assert.equal("1s 5c", M(105))
		assert.equal("12g 3s 40c", M(120340))
		assert.equal("2g", M(20000))
		assert.equal("-1s", M(-100))
		assert.is_nil(M(nil))
	end)

	it("one craft: cost, value of everything it makes, profit; never guesses a missing price", function()
		local P = SK.Prices
		local c = P.Craft({ { i = LINEN, q = 2 } }, BOLT, 1, fakePrices({ [LINEN] = 30 }, { [BOLT] = { 100, "ah" } }))
		assert.same({ 60, 100, 40, "ah", 0 }, { c.cost, c.value, c.profit, c.via, c.missing })
		-- Makes 200 (Crafted Light Shot): value counts all of them.
		c = P.Craft({ { i = 1, q = 1 } }, 2, 200, fakePrices({ [1] = 500 }, { [2] = { 3, "vendor" } }))
		assert.same({ 500, 600, 100 }, { c.cost, c.value, c.profit })
		-- A reagent without a price: no cost and no profit, but the value is still shown.
		c = P.Craft({ { i = LINEN, q = 2 }, { i = 99, q = 1 } }, BOLT, 1,
			fakePrices({ [LINEN] = 30 }, { [BOLT] = { 100, "ah" } }))
		assert.same({ 1, 100 }, { c.missing, c.value })
		assert.is_nil(c.cost)
		assert.is_nil(c.profit)
		-- No reagent data at all counts as missing.
		assert.equal(1, P.Craft(nil, BOLT, 1, fakePrices({}, {})).missing)
	end)

	it("buys from the cheaper of a vendor you've visited and the auction house", function()
		local P = SK.Prices
		local fake = { VendorBuy = function(id) return ({ [1] = 50, [2] = 50 })[id] end,
			Auction = function(id) return ({ [1] = 80, [2] = 20, [3] = 10 })[id] end }
		assert.same({ 50, "vendor" }, { P.Buy(1, fake) })
		assert.same({ 20, "ah" }, { P.Buy(2, fake) })
		assert.same({ 10, "ah" }, { P.Buy(3, fake) })
		assert.is_nil(P.Buy(4, fake))
	end)

	it("sells at the auction price after the 5% cut, or to a vendor if that pays more", function()
		local P = SK.Prices
		local fake = { Auction = function(id) return ({ [1] = 1000, [2] = 100 })[id] end,
			VendorSell = function(id) return ({ [1] = 10, [2] = 99, [3] = 7 })[id] end }
		assert.same({ 950, "ah" }, { P.Sell(1, fake) })
		assert.same({ 99, "vendor" }, { P.Sell(2, fake) }) -- 100 - 5% = 95 < 99
		assert.same({ 7, "vendor" }, { P.Sell(3, fake) })
		assert.is_nil(P.Sell(4, fake))
	end)

	it("remembers the cheapest price merchants charged, per item", function()
		local P = SK.Prices
		assert.equal(2, P.LearnMerchant({ { itemID = 2321, each = 100 }, { itemID = 2324, each = 25 } }))
		P.LearnMerchant({ { itemID = 2321, each = 90 }, { itemID = 2324, each = 30 }, { itemID = "x", each = 1 } })
		assert.equal(90, P.VendorBuy(2321))
		assert.equal(25, P.VendorBuy(2324))
		assert.equal(2, P.VendorKnown())
		assert.equal(0, P.LearnMerchant(nil))
	end)

	it("reads a merchant's items for gold only (not currency or extended costs), price per single item", function()
		_G.GetMerchantNumItems = function() return 4 end
		_G.GetMerchantItemID = function(i) return ({ 2321, 2324, 3371, 99 })[i] end
		_G.C_MerchantFrame = { GetItemInfo = function(i)
			return ({ { price = 100, stackCount = 1 }, { price = 125, stackCount = 5 },
				{ price = 0, stackCount = 1 }, { price = 50, stackCount = 1, hasExtendedCost = true } })[i]
		end }
		local items = SK.Compat.MerchantItems()
		assert.same({ { itemID = 2321, each = 100 }, { itemID = 2324, each = 25 } }, items)
		_G.GetMerchantNumItems, _G.GetMerchantItemID, _G.C_MerchantFrame = nil, nil, nil
		assert.is_nil(SK.Compat.MerchantItems())
	end)

	it("uses Auctionator or TSM when installed, the player's pick first, and survives a broken API", function()
		local P = SK.Prices
		assert.is_nil(P.Source())
		assert.is_nil(P.Auction(LINEN))
		_G.TSM_API = { GetCustomPriceValue = function(src, item)
			if item ~= "i:" .. LINEN then return nil end
			return src == "DBMarket" and 120 or 90
		end }
		assert.equal("tsm", P.Source())
		assert.equal(120, P.Auction(LINEN))
		_G.Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function(caller, id)
			assert.equal("ShortRoyalty", caller)
			return id == LINEN and 110 or nil
		end } } }
		assert.equal("auctionator", P.Source()) -- automatic: Auctionator first
		assert.equal(110, P.Auction(LINEN))
		SK.DB.settings.priceSource = "tsm"
		assert.equal(120, P.Auction(LINEN))
		SK.DB.settings.priceSource = "auctionator"
		_G.Auctionator.API.v1.GetAuctionPriceByItemID = function() error("changed API") end
		assert.is_nil(P.Auction(LINEN)) -- an error is "no price", not a Lua error
		_G.Auctionator.API.v1.GetAuctionPriceByItemID = function() return -5 end
		assert.is_nil(P.Auction(LINEN)) -- nonsense is ignored
		assert.same({ auctionator = true, tsm = true }, SK.Compat.PriceAddons())
	end)

	it("uses Forever's items-per-craft, or the game's own number once it has said", function()
		assert.equal(1, SK.Reagents.Yield(LINEN_BOLT))
		assert.equal(200, SK.Reagents.Yield(3947)) -- Crafted Light Shot
		SK.DB.reagents.list = { [3947] = { o = 8067, n = 150, r = {} } }
		assert.equal(150, SK.Reagents.Yield(3947))
		assert.equal(1, SK.Reagents.Yield(424242)) -- unknown recipe
	end)

	it("lists learned recipes best profit first, unpriced last", function()
		local rows = SK.Prices.Rows(197, { [LINEN_BOLT] = true, [2406] = true, [2402] = true }, function(id)
			return ({ [LINEN_BOLT] = { profit = 5, missing = 0, yield = 1 }, [2406] = { missing = 1, yield = 1 },
				[2402] = { profit = 50, missing = 0, yield = 1 } })[id]
		end)
		local ids = {}
		for _, r in ipairs(rows) do ids[#ids + 1] = r.recipeID end
		assert.same({ 2402, LINEN_BOLT, 2406 }, ids)
	end)

	it("the shopping list adds up what's still to buy", function()
		local rows = { { itemID = 1, need = 5, have = 2, short = 3 }, { itemID = 2, need = 1, have = 1, short = 0 },
			{ itemID = 3, need = 2, have = 0, short = 2 }, { itemID = 4, need = 4 } }
		local total, missing = SK.Shopping.Cost(rows, function(id) return ({ [1] = 10, [4] = 1 })[id] end)
		assert.equal(34, total) -- 3 x 10 + 4 x 1 (count unknown: all of it)
		assert.equal(1, missing) -- item 3
	end)
end)

describe("Professions → Profit", function()
	local SK, W
	before_each(function()
		SK, W = H.load()
		H.loadUI(SK)
		W.member("Pocus Hocus", W.player.guid)
		W.professions = { { name = "Tailoring", rank = 30, max = 75, skillLine = 197 } }
		SK.Identity:ReadRoster()
		SK.Profile:BuildSelf()
		local own = SK.Profile:Own()
		own.profs[197].scanned = W.now
		own.profs[197].primary = true
		own.recipes[197] = { [LINEN_BOLT] = BOLT }
		_G.Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function(_, id)
			return ({ [LINEN] = 10, [BOLT] = 100 })[id]
		end } } }
		SK.DB.unlocked.profit = true
		SK.Prices.OWNERS[W.player.guid] = true
	end)
	after_each(function() _G.Auctionator, _G.TSM_API = nil, nil end)

	it("is hidden until /sr profit unlocks it, for the whole account (v0.4.7)", function()
		SK.DB.unlocked.profit = nil
		SK.DB.settings.profView = "profit"
		SK.MainFrame:Show("professions")
		local tab = SK.ProfessionsTab
		assert.is_false(tab.profitList:IsShown())
		assert.is_true(tab.board:IsShown()) -- falls back to the Guild board
		local chip
		for _, c in ipairs(tab.viewChips) do if c.value == "profit" then chip = c end end
		assert.is_false(chip:IsShown())
		SK.Commands.Run("profit")
		assert.is_true(SK.DB.unlocked.profit)
		assert.is_true(chip:IsShown())
		SK.DB.settings.profView = "profit"
		tab:Refresh()
		assert.is_true(tab.profitList:IsShown())
		SK.Commands.Run("profit")
		assert.is_nil(SK.DB.unlocked.profit)
		assert.is_false(tab.profitList:IsShown())
		assert.is_true(#SK.Commands.HELP > 0)
		assert.is_nil(table.concat(SK.Commands.HELP, "\n"):find("profit", 1, true))
		assert.equal(0, #SK.errors)
	end)

	it("only the owner's account can unlock it; for anyone else /sr profit is an unknown command", function()
		SK.Prices.OWNERS[W.player.guid] = nil
		SK.DB.unlocked.profit = nil
		SK.Commands.Run("profit")
		assert.is_nil(SK.DB.unlocked.profit)
		SK.DB.unlocked.profit = true -- even if someone edits their saved data
		assert.is_false(SK.ProfessionsTab.ProfitUnlocked())
		SK.DB.account["Player-6937-001743F0"] = true -- an alt on the owner's account
		assert.is_true(SK.ProfessionsTab.ProfitUnlocked())
		assert.equal(0, #SK.errors)
	end)

	it("shows your recipes with cost, value and profit", function()
		SK.DB.settings.profView = "profit"
		SK.MainFrame:Show("professions")
		local tab = SK.ProfessionsTab
		assert.is_true(tab.profitList:IsShown())
		local r = tab.profitList.items[1]
		assert.equal(LINEN_BOLT, r.recipeID)
		assert.same({ 20, 95, 75, "ah" }, { r.cost, r.value, r.profit, r.via })
		assert.truthy(tab.status:GetText():find("Prices from Auctionator", 1, true))
		assert.truthy(tab.status:GetText():find("1 make a profit", 1, true))
		tab.priceMenu:Choose("tsm") -- not installed: falls back to what is
		assert.equal("tsm", SK.DB.settings.priceSource)
		assert.truthy(tab.status:GetText():find("Prices from Auctionator", 1, true))
		assert.truthy(SK.ProfessionsTab.PriceItems()[3].text:find("not installed", 1, true))
		assert.equal(0, #SK.errors)
	end)

	it("uses TSM's vendor price list for thread and dyes, cheapest wins (v0.5.6)", function()
		local P, THREAD, DYE = SK.Prices, 2321, 2605
		assert.is_nil(P.VendorBuy(THREAD))
		_G.TSM_API = { GetCustomPriceValue = function(src, item)
			if src ~= "VendorBuy" then return nil end
			return ({ ["i:" .. THREAD] = 10, ["i:" .. DYE] = 100 })[item]
		end }
		assert.equal(10, P.VendorBuy(THREAD))
		SK.DB.vendorBuy[DYE] = 80 -- seen cheaper at a merchant
		assert.equal(80, P.VendorBuy(DYE))
		local v, via = P.Buy(THREAD)
		assert.same({ 10, "vendor" }, { v, via })
		local c = P.Craft({ { i = THREAD, q = 1 }, { i = DYE, q = 1 } }, 0, 1, P)
		assert.equal(90, c.cost)
	end)

	it("names the reagents that leave recipes unpriced (v0.5.6)", function()
		local c = SK.Prices.Craft({ { i = 5, q = 1 }, { i = 6, q = 2 } }, 0, 1, fakePrices({ [5] = 1 }, {}))
		assert.same({ 6 }, c.missingIDs)
		local top = SK.Prices.MissingTop({ { missingIDs = { 6, 7 } }, { missingIDs = { 6, 6 } }, { missingIDs = {} },
			{ missingIDs = { 8 } } }, 2)
		assert.same({ { 6, 2 }, { 7, 1 } }, top)
		assert.equal("", SK.ProfessionsTab.MissingText({}))
		assert.truthy(SK.ProfessionsTab.MissingText({ { 6, 2 } }):find("no price yet", 1, true))
	end)

	it("lists every recipe you know, even one missing from the bundled data (v0.5.6)", function()
		local UNKNOWN, ITS_ITEM = 99000001, 99000002 -- not in Data/Recipes.lua
		local own = SK.Profile:Own()
		own.recipes[197][UNKNOWN] = ITS_ITEM
		SK.DB.reagents.build = SK.Compat.BuildInfo().build
		SK.DB.reagents.list = { [UNKNOWN] = { o = ITS_ITEM, n = 1, r = { { i = LINEN, q = 1 } } } }
		_G.Auctionator.API.v1.GetAuctionPriceByItemID = function(_, id)
			return ({ [LINEN] = 10, [BOLT] = 100, [ITS_ITEM] = 50 })[id]
		end
		SK.DB.settings.profView = "profit"
		SK.MainFrame:Show("professions")
		local found
		for _, r in ipairs(SK.ProfessionsTab.profitList.items) do if r.recipeID == UNKNOWN then found = r end end
		assert.truthy(found)
		assert.same({ ITS_ITEM, 10 }, { found.itemID, found.cost })
		assert.equal(2, #SK.ProfessionsTab.profitList.items)
		local report = table.concat(SK.Commands.BuildReport(), "\n")
		assert.truthy(report:find("not in Forever's recipe list: 1 (" .. UNKNOWN .. ")", 1, true))
		assert.equal(0, #SK.errors)
	end)

	it("without a price addon it says so and still uses vendor prices", function()
		_G.Auctionator = nil
		SK.Prices.LearnMerchant({ { itemID = LINEN, each = 15 } })
		SK.DB.settings.profView = "profit"
		SK.MainFrame:Show("professions")
		local tab = SK.ProfessionsTab
		assert.truthy(tab.status:GetText():find("vendor prices only", 1, true))
		assert.equal(30, tab.profitList.items[1].cost)
		assert.equal(0, #SK.errors)
	end)

	it("the shopping list shows what the rest costs", function()
		SK.Shopping.Set(LINEN_BOLT, 3)
		SK.DB.settings.profView = "shopping"
		SK.MainFrame:Show("professions")
		assert.truthy(SK.ProfessionsTab.shopCost:GetText():find("About 60c to buy", 1, true))
		assert.equal("", SK.ProfessionsTab.ShopCostText(0, 0))
		assert.truthy(SK.ProfessionsTab.ShopCostText(0, 2):find("2 without a price", 1, true))
		assert.equal(0, #SK.errors)
	end)

	it("/sr debug reports whether each price addon answers", function()
		local text = table.concat(SK.Commands.BuildReport(), "\n")
		assert.truthy(text:find("Prices: Auctionator API yes (Linen Cloth 10c)", 1, true))
		assert.truthy(text:find("TSM API no", 1, true))
		assert.truthy(text:find("Vendor prices remembered: 0", 1, true))
	end)
end)
