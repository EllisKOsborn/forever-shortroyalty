-- Shopping list (levelling tools step 2): recipes and how many times to
-- craft each, the reagents that adds up to, and how many you already have
-- in your bags and bank. Saved on this computer only (ShortRoyaltyDB.shopping),
-- never sent to anyone. Totals are pure functions; tested.
local _, SK = ...

local Shop = SK:NewModule("Shopping")
local Compat = SK.Compat

Shop.MAX_RECIPES = 50
Shop.MAX_CRAFTS = 999

local function list()
	local s = SK.DB.shopping
	s.list = type(s.list) == "table" and s.list or {}
	return s.list
end

local function find(recipeID)
	for i, e in ipairs(list()) do if e.id == recipeID then return i, e end end
end

local function changed() SK:Fire("SHOPPING_CHANGED") end

-- { { id = recipeID, n = crafts } } in the order they were added.
function Shop.Entries() return list() end

function Shop.Crafts(recipeID)
	local _, e = find(recipeID)
	return e and e.n or 0
end

-- Set how many times to craft it; 0 or less takes it off the list.
-- Returns false when the list is full.
function Shop.Set(recipeID, n)
	if type(recipeID) ~= "number" or type(n) ~= "number" then return false end
	n = math.min(math.floor(n), Shop.MAX_CRAFTS)
	local i, e = find(recipeID)
	if n <= 0 then
		if i then table.remove(list(), i); changed() end
		return true
	end
	if e then
		e.n = n
	else
		if #list() >= Shop.MAX_RECIPES then return false end
		table.insert(list(), { id = recipeID, n = n })
	end
	changed()
	return true
end

function Shop.Add(recipeID, n) return Shop.Set(recipeID, Shop.Crafts(recipeID) + (n or 1)) end

function Shop.Clear()
	SK.DB.shopping.list = {}
	changed()
end

-- itemID -> recipes in the game's data that make it (built once).
local makers
local function makersOf(itemID)
	if not makers then
		makers = {}
		for _, r in ipairs(SK.RecipeDB.List()) do
			if r.itemID > 0 then
				makers[r.itemID] = makers[r.itemID] or {}
				table.insert(makers[r.itemID], r.recipeID)
			end
		end
	end
	return makers[itemID]
end
function Shop.ResetMakers() makers = nil end

-- A recipe you've learned that makes this item, if any.
function Shop.YouMake(itemID)
	for _, id in ipairs(makersOf(itemID) or {}) do
		local r = SK.RecipeDB.Get(id)
		if r and SK.RecipeDB.IKnow(id, r.skillLine) then return id end
	end
end

-- Reagent totals, pure. entries = Shop.Entries(); reagentsOf(recipeID) ->
-- { { i | c, q } } or nil; countOf(itemID) -> bags, total (or nil).
-- Returns rows { itemID, currencyID, need, bags, bank, have, short, recipes },
-- still-to-get first, and the recipes the game has no reagents for.
function Shop.Totals(entries, reagentsOf, countOf)
	local byKey, rows, unknown = {}, {}, {}
	for _, e in ipairs(entries) do
		local reagents = reagentsOf(e.id)
		if not reagents or #reagents == 0 then
			unknown[#unknown + 1] = e.id
		else
			for _, x in ipairs(reagents) do
				local key = x.i and ("i" .. x.i) or ("c" .. tostring(x.c))
				local row = byKey[key]
				if not row then
					row = { itemID = x.i, currencyID = x.c, need = 0, recipes = {} }
					byKey[key] = row
					rows[#rows + 1] = row
				end
				row.need = row.need + x.q * e.n
				row.recipes[#row.recipes + 1] = e.id
			end
		end
	end
	for _, row in ipairs(rows) do
		if row.itemID then
			local bags, total = countOf(row.itemID)
			if bags then
				row.bags, row.have = bags, total or bags
				row.bank = row.have - bags
				row.short = math.max(row.need - row.have, 0)
			end
		end
	end
	table.sort(rows, function(a, b)
		local sa, sb = (a.short or 0) > 0, (b.short or 0) > 0
		if sa ~= sb then return sa end
		return (a.itemID or 0) < (b.itemID or 0)
	end)
	return rows, unknown
end

-- Raw materials (v0.5.1): reagents you make yourself and are short of
-- (bolts, bars) become crafts, so their own reagents are added; up to three
-- levels. Those rows get `make` = how many crafts. Pure apart from `totals`.
-- makerOf(itemID) -> recipeID you know; yieldOf(recipeID) -> items per craft.
function Shop.Expand(entries, rows, unknown, makerOf, yieldOf, totals)
	local all, made = {}, {}
	for i, e in ipairs(entries) do all[i] = e end
	for _ = 1, 3 do
		local added = false
		for _, r in ipairs(rows) do
			local short = r.have == nil and r.need or r.short
			local recipe = r.itemID and not made[r.itemID] and short and short > 0 and makerOf(r.itemID)
			if recipe then
				local crafts = math.ceil(short / math.max(1, yieldOf(recipe)))
				all[#all + 1] = { id = recipe, n = crafts }
				made[r.itemID] = crafts
				added = true
			end
		end
		if not added then break end
		rows, unknown = totals(all)
	end
	for _, r in ipairs(rows) do if r.itemID and made[r.itemID] then r.make = made[r.itemID] end end
	return rows, unknown
end

local function totals(entries) return Shop.Totals(entries, SK.Reagents.All, Compat.ItemCounts) end

function Shop.Rows(raw)
	local entries = list()
	local rows, unknown = totals(entries)
	if raw == nil then raw = SK.DB.settings.shopRaw end
	if not raw then return rows, unknown end
	return Shop.Expand(entries, rows, unknown, Shop.YouMake, SK.Reagents.Yield, totals)
end

-- Item tooltips (v0.5.1): { need, have, short, make } for an item on the
-- list, or nil. Rebuilt only when the list, bags or bank change.
local needCache
function Shop.ItemNeed(itemID)
	if #list() == 0 then return nil end
	if not needCache then
		needCache = {}
		for _, r in ipairs((Shop.Rows())) do if r.itemID then needCache[r.itemID] = r end end
	end
	return needCache[itemID]
end
function Shop.Dirty() needCache = nil end
SK:On("SHOPPING_CHANGED", Shop.Dirty)
SK:RegisterEvent("BAG_UPDATE_DELAYED", Shop.Dirty)
SK:RegisterEvent("PLAYERBANKSLOTS_CHANGED", Shop.Dirty)

-- TSM's item-list format ("i:2589,i:2592") for what you still have to buy (v0.5.1).
function Shop.TSMList(rows)
	local ids = {}
	for _, r in ipairs(rows) do
		local short = r.have == nil and r.need or r.short
		if r.itemID and not r.make and short and short > 0 then ids[#ids + 1] = "i:" .. r.itemID end
	end
	return table.concat(ids, ",")
end

-- What the still-to-get reagents cost: total copper and how many have no
-- price. buy(itemID) -> copper per item or nil. Pure.
function Shop.Cost(rows, buy)
	local total, missing = 0, 0
	for _, r in ipairs(rows) do
		local short = r.have == nil and r.need or r.short
		if short and short > 0 and not r.make then
			local each = r.itemID and buy(r.itemID) or nil
			if each then total = total + each * short else missing = missing + 1 end
		end
	end
	return total, missing
end

-- "3 recipes · 2 reagents still to get". Pure.
function Shop.Summary(entries, rows)
	local short = 0
	for _, r in ipairs(rows) do if (r.short or 0) > 0 then short = short + 1 end end
	return #entries, #rows, short
end

-- Plain text for Copy (Discord). nameOf(itemID or recipeID, isRecipe) -> name.
function Shop.Text(entries, rows, nameOf)
	local Plain = SK.Export.Plain
	local out = { "Shopping list (Short Royalty)" }
	if #entries == 0 then
		out[#out + 1] = "(empty)"
		return table.concat(out, "\n")
	end
	out[#out + 1] = "To craft:"
	for _, e in ipairs(entries) do
		out[#out + 1] = "- " .. e.n .. "x " .. Plain(nameOf(e.id, true) or ("recipe " .. e.id))
	end
	local still, got = {}, {}
	for _, r in ipairs(rows) do
		local name = r.itemID and Plain(nameOf(r.itemID) or ("item " .. r.itemID)) or "currency"
		if r.make then
			still[#still + 1] = "- make " .. r.make .. "x " .. name
		elseif r.have == nil then
			still[#still + 1] = "- " .. r.need .. " " .. name
		elseif r.short > 0 then
			still[#still + 1] = "- " .. r.short .. " " .. name .. " (need " .. r.need .. ", have " .. r.have .. ")"
		else
			got[#got + 1] = "- " .. r.need .. " " .. name
		end
	end
	if #still > 0 then
		out[#out + 1] = "Still to get:"
		for _, l in ipairs(still) do out[#out + 1] = l end
	end
	if #got > 0 then
		out[#out + 1] = "Already have:"
		for _, l in ipairs(got) do out[#out + 1] = l end
	end
	return table.concat(out, "\n")
end
