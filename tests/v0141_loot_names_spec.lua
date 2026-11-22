-- v0.14.1 (not released): the Loot page shows items by name, quality
-- colour and icon, also the ones the game can't name yet (Forever holds
-- raid loot back until the raid opens: the page showed "item 17068").
local H = require("tests.helpers.load")

local STORMRAGE, BACKPACK, UNKNOWN = 16900, 17966, 290001

local function setup()
	local SK, W = H.load()
	local me = W.player.guid
	W.member("Pip", me, { rank = "Officer", rankIndex = 1 })
	W.member("Bob Stout", "Player-1-B", { rank = "Raid Leader", rankIndex = 2 })
	SK.Identity:ReadRoster()
	SK.Profile:BuildSelf()
	return SK, W
end

describe("v0.14.1 item looks in Data/Loot.lua", function()
	it("every listed item has a name, a quality and a safe icon name", function()
		local SK = setup()
		local looks = SK.Data.LOOT_ITEMS
		assert.is_table(looks)
		local n = 0
		for _, raid in pairs(SK.Data.LOOT) do
			for _, id in ipairs(raid.items) do
				n = n + 1
				local info = looks[id]
				assert.is_table(info, "no look for item " .. id)
				assert.is_string(info.name)
				assert.is_nil(info.name:find("[|%c]"), "name with a chat code: " .. id)
				assert.is_true(info.q == nil or (info.q >= 0 and info.q <= 7))
				if info.icon then assert.truthy(info.icon:match("^[a-z0-9_%-]+$"), "odd icon for " .. id) end
				for _, k in ipairs({ "slot", "type" }) do
					if info[k] then assert.is_nil(info[k]:find("[|%c]")) end
				end
			end
		end
		assert.is_true(n >= 18)
		assert.equal("Deathbringer", looks[17068].name)
	end)
end)

describe("v0.14.1 Reserves.ItemLook", function()
	it("uses the list's look while the game can't name the item", function()
		local SK = setup()
		local look = SK.Reserves.ItemLook(STORMRAGE)
		assert.equal("Stormrage Cover", look.name)
		assert.equal(4, look.q)
		assert.equal("Interface\\Icons\\inv_helmet_09", look.icon)
		assert.equal("Head, Leather", SK.Reserves.SlotText(look))
		assert.is_true(look.listed)
	end)

	it("the game's own name, quality and icon win once it knows the item", function()
		local SK, W = setup()
		W.itemNames[BACKPACK], W.itemCached[BACKPACK], W.itemQuality[BACKPACK] = "Onyxia Hide Backpack (game)", true, 3
		local look = SK.Reserves.ItemLook(BACKPACK)
		assert.equal("Onyxia Hide Backpack (game)", look.name)
		assert.equal(3, look.q)
		assert.equal(134400, look.icon)
	end)

	it("an item nobody lists and the game doesn't know has no name", function()
		local SK = setup()
		local look = SK.Reserves.ItemLook(UNKNOWN)
		assert.is_nil(look.name)
		assert.is_false(look.listed)
	end)

	it("slot text", function()
		local SK = setup()
		local T = SK.Reserves.SlotText
		assert.equal("One-Hand Axe", T({ slot = "One-Hand", type = "Axe" }))
		assert.equal("Trinket", T({ slot = "Trinket" }))
		assert.equal("Bag", T({ type = "Bag" }))
		assert.is_nil(T({}))
		assert.is_nil(T(nil))
	end)
end)

describe("v0.14.1 the Loot page", function()
	local SK, W, LT
	before_each(function()
		SK, W = setup()
		H.loadUI(SK)
		LT = SK.LootTab
		local board = SK.RaidBoard:Get()
		local by = "Player-1-B"
		assert(SK.RaidBoard.MergeEvent(board, { id = by .. ":" .. W.now, by = by, c = W.now, raid = "ony", at = W.now + 1800, u = W.now },
			W.now, function() return true end))
	end)

	it("item text: icon, quality colour and name; 'item N' only when nothing knows it", function()
		local text = LT.ItemText(STORMRAGE)
		assert.truthy(text:find("Stormrage Cover", 1, true))
		assert.truthy(text:find("|TInterface\\Icons\\inv_helmet_09:", 1, true))
		assert.truthy(text:find("|c", 1, true))
		assert.is_nil(LT.ItemText(STORMRAGE, true):find("|T", 1, true))
		assert.equal("Stormrage Cover", LT.ItemName(STORMRAGE))
		assert.equal("item " .. UNKNOWN, LT.ItemName(UNKNOWN))
		assert.equal("Stormrage Cover ×2, Deathbringer", LT.PicksText({ STORMRAGE, STORMRAGE, 17068 }, LT.ItemName))
	end)

	it("the Reserves list is in name order, with no 'item N' rows, and rows have tooltips", function()
		SK.DB.settings.lootView = "reserves"
		SK.MainFrame:Open("loot")
		local items = LT.itemList.items
		assert.is_true(#items >= 18)
		for n, r in ipairs(items) do
			assert.is_nil(LT.ItemName(r.item):find("^item %d"), "unnamed item " .. r.item)
			if n > 1 then assert.is_true(LT.ItemName(items[n - 1].item):lower() <= LT.ItemName(r.item):lower()) end
		end
		assert.is_function(LT.itemList.opts.onEnter)
		-- Both tooltip kinds: the list's look, and the game's own item.
		LT.ItemTip(UIParent, STORMRAGE)
		W.itemNames[BACKPACK], W.itemCached[BACKPACK] = "Onyxia Hide Backpack", true
		LT.ItemTip(UIParent, BACKPACK)
		LT.ItemTip(UIParent, UNKNOWN)
		assert.equal(0, #SK.errors)
	end)
end)
