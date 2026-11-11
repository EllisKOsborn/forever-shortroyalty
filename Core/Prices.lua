-- Prices (levelling tools step 3): what a recipe's reagents cost, what the
-- item it makes sells for, and the profit. Auction prices come from
-- Auctionator or TradeSkillMaster when installed (Compat); vendor prices
-- are what merchants charged when you last visited them (remembered in
-- ShortRoyaltyDB.vendorBuy) and what vendors pay (the item's sell price).
-- Everything here stays on this computer. The sums are pure; tested.
local _, SK = ...

local P = SK:NewModule("Prices")
local Compat = SK.Compat

P.TSM_SOURCES = { "DBMarket", "DBMinBuyout" } -- tried in this order
-- The auction house keeps 5% of a sale in the original game; not yet
-- confirmed for Forever. Profit from auction sales is counted after it.
P.AH_CUT = 0.05
P.SOURCES = { "auto", "auctionator", "tsm" }

---------------------------------------------------------------------------
-- Vendor prices, learned at merchants
---------------------------------------------------------------------------
local function vendorBuy()
	local v = SK.DB.vendorBuy
	if type(v) ~= "table" then v = {}; SK.DB.vendorBuy = v end
	return v
end

-- Remember what this merchant charges (the cheapest seen per item).
function P.LearnMerchant(items)
	if type(items) ~= "table" then return 0 end
	local store, n = vendorBuy(), 0
	for _, it in ipairs(items) do
		if type(it.itemID) == "number" and type(it.each) == "number" and it.each > 0 then
			if not store[it.itemID] or it.each < store[it.itemID] then store[it.itemID] = it.each end
			n = n + 1
		end
	end
	if n > 0 then SK:Fire("PRICES_CHANGED") end
	return n
end

function P.VendorBuy(itemID) return vendorBuy()[itemID] end

function P.VendorKnown()
	local n = 0
	for _ in pairs(vendorBuy()) do n = n + 1 end
	return n
end

---------------------------------------------------------------------------
-- Auction prices
---------------------------------------------------------------------------
-- The addon prices come from: the player's pick, or the first installed.
function P.Source()
	local have = Compat.PriceAddons()
	local pick = SK.DB.settings.priceSource
	if pick == "auctionator" and have.auctionator then return "auctionator" end
	if pick == "tsm" and have.tsm then return "tsm" end
	if have.auctionator then return "auctionator" end
	if have.tsm then return "tsm" end
	return nil
end

P.SOURCE_NAMES = { auctionator = "Auctionator", tsm = "TSM" }

-- Copper per item at the auction house, or nil.
function P.Auction(itemID)
	local src = P.Source()
	if src == "auctionator" then return Compat.AuctionatorPrice(itemID) end
	if src == "tsm" then
		for _, s in ipairs(P.TSM_SOURCES) do
			local v = Compat.TSMPrice(itemID, s)
			if v and v > 0 then return v end
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- Buying reagents, selling what you make
---------------------------------------------------------------------------
-- Cheapest way to get one: a vendor you've visited, or the auction house.
-- Returns copper, "vendor" | "ah" (or nil).
function P.Buy(itemID, prices)
	prices = prices or P
	local v, a = prices.VendorBuy(itemID), prices.Auction(itemID)
	if v and (not a or v <= a) then return v, "vendor" end
	if a then return a, "ah" end
	return nil
end

-- What one is worth to you: the auction price after the cut, or what a
-- vendor pays, whichever is more. Returns copper, "ah" | "vendor" (or nil).
function P.Sell(itemID, prices)
	prices = prices or P
	local a, v = prices.Auction(itemID), prices.VendorSell(itemID)
	local net = a and math.floor(a * (1 - P.AH_CUT)) or nil
	if net and (not v or net >= v) then return net, "ah" end
	if v then return v, "vendor" end
	return nil
end

P.VendorSell = Compat.VendorSellPrice

-- One craft: cost of its reagents, what it makes is worth, and the profit.
-- reagents = { { i = itemID | c = currencyID, q } }, outputID, yield. Pure
-- with `prices` = { Buy(id), Sell(id) }. Missing prices are counted, never
-- guessed: cost/profit are nil when any reagent has no price.
function P.Craft(reagents, outputID, yield, prices)
	local out = { cost = 0, missing = 0, yield = yield or 1 }
	for _, x in ipairs(reagents or {}) do
		local each = x.i and prices.Buy(x.i) or nil
		if each then out.cost = out.cost + each * x.q else out.missing = out.missing + 1 end
	end
	if not reagents or #reagents == 0 then out.missing = out.missing + 1 end
	if out.missing > 0 then out.cost = nil end
	if outputID and outputID > 0 then
		local each, via = prices.Sell(outputID)
		if each then out.value, out.via = each * out.yield, via end
	end
	if out.cost and out.value then out.profit = out.value - out.cost end
	return out
end

function P.Recipe(recipeID)
	local r = SK.RecipeDB.Get(recipeID)
	local outputID = r and r.itemID or 0
	local learned = SK.DB.reagents.list and SK.DB.reagents.list[recipeID]
	if learned and learned.o and learned.o > 0 then outputID = learned.o end
	return P.Craft(SK.Reagents.All(recipeID), outputID, SK.Reagents.Yield(recipeID), P)
end

-- Your learned recipes in one profession, best profit first; recipes whose
-- profit can't be worked out go last. Pure apart from P.Recipe.
function P.Rows(skillLine, known, craft)
	craft = craft or P.Recipe
	local rows = {}
	for _, r in ipairs(SK.RecipeDB.List(skillLine)) do
		if known[r.recipeID] then
			local c = craft(r.recipeID)
			c.recipeID, c.itemID, c.skillLine = r.recipeID, r.itemID, skillLine
			rows[#rows + 1] = c
		end
	end
	table.sort(rows, function(a, b)
		if (a.profit ~= nil) ~= (b.profit ~= nil) then return a.profit ~= nil end
		if a.profit and b.profit and a.profit ~= b.profit then return a.profit > b.profit end
		return a.recipeID < b.recipeID
	end)
	return rows
end

---------------------------------------------------------------------------
-- Money as text: 12g 3s 40c (no colour codes; pure)
---------------------------------------------------------------------------
function P.Money(c)
	if type(c) ~= "number" then return nil end
	local neg = c < 0
	c = math.floor(math.abs(c) + 0.5)
	local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = g .. "g" end
	if s > 0 then parts[#parts + 1] = s .. "s" end
	if cp > 0 or #parts == 0 then parts[#parts + 1] = cp .. "c" end
	return (neg and "-" or "") .. table.concat(parts, " ")
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function scan() P.LearnMerchant(Compat.MerchantItems()) end
SK:RegisterEvent("MERCHANT_SHOW", scan)
SK:RegisterEvent("MERCHANT_UPDATE", scan)
