-- Professions tab (v0.3): the guild's coverage board, one profession at a
-- time (crafters and recipes), and the cooldown board. Numbers come from
-- Core/ProfBoard.lua; clicking a recipe opens it in the Crafters tab.
-- In one profession, clicking a crafter shows that crafter's recipes on the
-- right (v0.3.4), with a Character button to open their character sheet.
-- Shopping list (v0.4.5): recipes to craft and the reagents they add up to.
-- Profit (v0.4.6): your learned recipes' cost, value and profit.
local _, SK = ...

local Prof = SK:NewModule("ProfessionsTab")
local Theme, W, Compat = SK.Theme, SK.Widgets, SK.Compat
local PB, CI, Fav = SK.ProfBoard, SK.CraftIndex, SK.Favourites
local S, SP = Theme.SIZES, Theme.SPACE

Prof.CRAFTERS_W = 440
Prof.RECIPES_W = S.window[1] - 2 * SP.l - Prof.CRAFTERS_W - SP.l

local VIEWS = { { "board", "Guild" }, { "recipes", "All recipes" }, { "cooldowns", "Cooldowns" },
	{ "levelling", "Levelling" }, { "route", "Route" }, { "shopping", "Shopping list" }, { "profit", "Profit" } }
local VIEW_OK = { board = true, recipes = true, cooldowns = true, levelling = true, route = true, shopping = true,
	profit = true }
Prof.SHOP_W = 400
local RECIPE_FILTERS = {
	{ "all", "All" }, { "one", "Only one crafter" }, { "fav", "Favourites" }, { "nobody", "Nobody knows" },
}

local function dot(status) return SK.RosterTab.DOT[status] or SK.RosterTab.DOT.offline end

local function recordedText(ts, now)
	if not ts then return Theme.DASH end
	local ago = Theme.Ago(ts, now)
	local text = ago == "now" and ago or (ago .. " ago")
	if Theme.IsStale(ts, now) then return Theme.Paint("spark", text) end
	return Theme.Paint("dim", text)
end

local function whisperButton(row)
	row.whisper = W.Button(row, "Whisper", 60, S.controlSmall, function(b)
		if b.target then Compat.SendTell(SK.Identity:WhisperTarget(b.target)) end
	end)
	row.whisper:SetPoint("RIGHT", -SP.xxs, 0)
	row.whisper.disabledTooltip = "Offline"
	row.widgets[#row.widgets + 1] = row.whisper
end

local function updateWhisper(row, c)
	row.whisper.target = c.whisper
	row.whisper:SetDisabled(c.whisper == nil)
	row.whisper:SetShown(not SK.DB.account[c.guid])
end

---------------------------------------------------------------------------
-- Columns (each list: its width minus the 12 px scroll bar)
---------------------------------------------------------------------------
-- Board: 848 - 12 = 836.
local BOARD_COLUMNS = {
	{ key = "name", title = "Profession", width = 170 },
	{ key = "chars", title = "Characters", width = 88, align = "RIGHT" },
	{ key = "atMax", title = "At " .. SK.Data.SKILL_CAP, width = 70, align = "RIGHT" },
	{ key = "online", title = "Online", width = 70, align = "RIGHT" },
	{ key = "top", title = "Top skill", width = 80, align = "RIGHT" },
	{ key = "scan", title = "Latest recipes", width = 112, align = "RIGHT" },
	{ key = "specs", title = "Specialisations", width = 246 },
}

-- Crafters: 440 - 12 = 428.
local CRAFTER_COLUMNS = {
	{ key = "name", title = "Character", width = 152 },
	{ key = "skill", title = "Skill", width = 50, align = "RIGHT" },
	{ key = "spec", title = "Speciality", width = 92 },
	{ key = "scan", title = "Recipes", width = 70, align = "RIGHT" },
	{ key = "btn", title = "", width = 64 },
}

-- Recipes: 392 - 12 = 380.
local RECIPE_COLUMNS = {
	{ key = "name", title = "Recipe", width = 290 },
	{ key = "count", title = "Crafters", width = 90, align = "RIGHT" },
}

-- Levelling (v0.4.4): 836.
local LEVEL_COLUMNS = {
	{ key = "name", title = "Recipe", width = 300 },
	{ key = "colour", title = "For you", width = 96 },
	{ key = "left", title = "Grey in", width = 80, align = "RIGHT" },
	{ key = "range", title = "Yellow · green · grey at", width = 230 },
	{ key = "known", title = "", width = 130, align = "RIGHT" },
}

-- Shopping list, recipes: 400 - 12 = 388.
local SHOP_RECIPE_COLUMNS = {
	{ key = "name", title = "Recipe", width = 252 },
	{ key = "crafts", title = "Crafts", width = 60, align = "RIGHT" },
	{ key = "btn", title = "", width = 76 },
}

-- Shopping list, reagents: 848 - 400 - 16 - 12 = 420.
local SHOP_REAGENT_COLUMNS = {
	{ key = "name", title = "Reagent", width = 240 },
	{ key = "need", title = "Need", width = 50, align = "RIGHT" },
	{ key = "have", title = "Have", width = 50, align = "RIGHT" },
	{ key = "short", title = "Still to get", width = 80, align = "RIGHT" },
}

-- Cheapest route (v0.4.8): 836.
local ROUTE_COLUMNS = {
	{ key = "skill", title = "Skill", width = 110 },
	{ key = "name", title = "Recipe", width = 300 },
	{ key = "colour", title = "Starts", width = 90 },
	{ key = "crafts", title = "Crafts", width = 90, align = "RIGHT" },
	{ key = "cost", title = "Cost", width = 120, align = "RIGHT" },
	{ key = "per", title = "Per point", width = 126, align = "RIGHT" },
}

-- Profit (v0.4.6): 836.
local PROFIT_COLUMNS = {
	{ key = "name", title = "Recipe", width = 286 },
	{ key = "colour", title = "For you", width = 80 },
	{ key = "cost", title = "Reagents cost", width = 120, align = "RIGHT" },
	{ key = "value", title = "Sells for", width = 120, align = "RIGHT" },
	{ key = "profit", title = "Profit", width = 120, align = "RIGHT" },
	{ key = "via", title = "Sold at", width = 110, align = "RIGHT" },
}

-- All recipes: 836.
local ALL_COLUMNS = {
	{ key = "name", title = "Recipe", width = 330 },
	{ key = "prof", title = "Profession", width = 130 },
	{ key = "group", title = "Group", width = 266 },
	{ key = "count", title = "Crafters", width = 110, align = "RIGHT" },
}

-- Cooldowns: 836.
local COOLDOWN_COLUMNS = {
	{ key = "name", title = "Cooldown", width = 270 },
	{ key = "who", title = "Crafter", width = 190 },
	{ key = "left", title = "Ready in", width = 110, align = "RIGHT" },
	{ key = "asof", title = "As of", width = 140, align = "RIGHT" },
	{ key = "btn", title = "", width = 126 },
}

local function setBoardCell(fs, r, col)
	local k = col.key
	if k == "name" then
		fs:SetText(r.chars > 0 and r.name or Theme.Paint("dim", r.name))
	elseif k == "chars" then
		fs:SetText(r.chars > 0 and r.chars or Theme.Paint("spark", "nobody"))
	elseif k == "atMax" then
		fs:SetText(r.chars > 0 and r.atMax or Theme.DASH)
	elseif k == "online" then
		fs:SetText(r.online > 0 and Theme.Paint("good", r.online) or (r.chars > 0 and Theme.Paint("dim", 0) or Theme.DASH))
	elseif k == "top" then
		fs:SetText(r.top > 0 and r.top or Theme.DASH)
	elseif k == "scan" then
		fs:SetText(recordedText(r.lastScan, Prof.now))
	elseif k == "specs" then
		local t = PB.SpecText(r.specs)
		fs:SetText(t ~= "" and Theme.Paint("dim", t) or "")
	end
end

local function setCrafterCell(fs, c, col)
	local k = col.key
	if k == "name" then
		local star = c.fav and (Theme.Star("beard") .. " ") or ""
		local extra = c.via and Theme.Paint("good", "  on " .. (c.viaName or "alt"))
			or (c.altOf and Theme.Paint("dim", "  alt of " .. c.altOf)) or ""
		fs:SetText(dot(c.status) .. " " .. star .. Theme.ClassText(c.name, c.class) .. extra)
	elseif k == "skill" then
		fs:SetText(c.skill > 0 and c.skill or Theme.DASH)
	elseif k == "spec" then
		fs:SetText(#c.specs > 0 and Theme.Paint("dim", table.concat(c.specs, ", ")) or "")
	elseif k == "scan" then
		if c.hidden then fs:SetText(Theme.Paint("dim", "private"))
		elseif not c.scanned and SK.Data.GATHERING[Prof.skillLine] then fs:SetText("")
		else fs:SetText(recordedText(c.scanned, Prof.now)) end
	else
		fs:SetText("")
	end
end

local function recipeIcon(r)
	local tex = r.itemID > 0 and Compat.ItemIcon(r.itemID) or Compat.SpellIcon(r.recipeID)
	return tex and ("|T" .. tex .. ":14:14:0:0:64:64:5:59:5:59|t ") or ""
end

local function setLevelCell(fs, r, col)
	local k = col.key
	if k == "name" then
		local name = SK.CraftIndex.NameOf({ recipeID = r.recipeID, itemID = r.itemID }) or "..."
		local hex = r.itemID > 0 and Compat.ItemQualityHex(r.itemID)
		fs:SetText(recipeIcon(r) .. (hex and ("|c" .. hex .. name .. "|r") or name))
	elseif k == "colour" then
		fs:SetText(Theme.SkillColour(r.colour))
	elseif k == "left" then
		fs:SetText(Theme.Paint("dim", Theme.Count(r.left, "point")))
	elseif k == "range" then
		fs:SetText(Theme.SkillRange(r.range))
	else
		fs:SetText(r.range.ups > 1 and Theme.Paint("dim", "+" .. r.range.ups .. " per craft") or "")
	end
end

local function setRecipeCell(fs, r, col)
	if col.key == "name" then
		local hex = r.itemID > 0 and Compat.ItemQualityHex(r.itemID)
		local name = hex and ("|c" .. hex .. r.name .. "|r") or r.name
		fs:SetText((r.fav and (Theme.Star("beard") .. " ") or "") .. recipeIcon(r) .. name)
	else
		if r.count == 0 then fs:SetText(Theme.Paint("spark", "nobody"))
		elseif r.count == 1 then fs:SetText(Theme.Paint("spark", "1"))
		else fs:SetText(r.count) end
	end
end

local function setAllCell(fs, r, col)
	local k = col.key
	if k == "name" then
		setRecipeCell(fs, r, col)
	elseif k == "prof" then
		fs:SetText(Theme.Paint("dim", PB.ProfessionName(Prof.ctx, r.skillLine)))
	elseif k == "group" then
		local g = r.group ~= "" and r.group or Theme.DASH
		if r.match == "material" and r.matched then g = g .. Theme.Paint("dim", "  ·  uses " .. r.matched) end
		fs:SetText(Theme.Paint("dim", g))
	else
		setRecipeCell(fs, r, col)
	end
end

local function setShopRecipeCell(fs, r, col)
	local k = col.key
	if k == "name" then
		local name = SK.CraftIndex.NameOf({ recipeID = r.recipeID, itemID = r.itemID }) or "..."
		local hex = r.itemID > 0 and Compat.ItemQualityHex(r.itemID)
		fs:SetText(recipeIcon(r) .. (hex and ("|c" .. hex .. name .. "|r") or name))
	elseif k == "crafts" then
		fs:SetText(r.n)
	else
		fs:SetText("")
	end
end

local function setShopReagentCell(fs, r, col)
	local k = col.key
	if k == "name" then
		local icon = r.itemID and Compat.ItemIcon(r.itemID)
		local name = r.itemID and (CI.ItemName(r.itemID) or "...") or "Currency"
		local make = r.makeWith and Theme.Paint("dim", "  you make it") or ""
		fs:SetText((icon and ("|T" .. icon .. ":14:14:0:0:64:64:5:59:5:59|t ") or "") .. name .. make)
	elseif k == "need" then
		fs:SetText(r.need)
	elseif k == "have" then
		fs:SetText(r.have == nil and Theme.DASH or Theme.Paint(r.have >= r.need and "good" or "text", r.have))
	else
		if r.make then fs:SetText(Theme.Paint("good", "make " .. r.make))
		elseif r.have == nil then fs:SetText(Theme.Paint("dim", "?"))
		elseif r.short > 0 then fs:SetText(Theme.Paint("spark", r.short))
		else fs:SetText(Theme.Paint("good", "got it")) end
	end
end

local function shopButtons(row)
	row.minus = W.Button(row, "-", 30, S.controlSmall, function(b)
		if b.recipeID then SK.Shopping.Add(b.recipeID, -(Compat.ShiftDown() and 5 or 1)) end
	end, "quiet")
	row.plus = W.Button(row, "+", 30, S.controlSmall, function(b)
		if b.recipeID then SK.Shopping.Add(b.recipeID, Compat.ShiftDown() and 5 or 1) end
	end, "quiet")
	row.plus:SetPoint("RIGHT", -SP.xxs, 0)
	row.minus:SetPoint("RIGHT", row.plus, "LEFT", -SP.xxs, 0)
	row.plus.tooltip = "One more craft (Shift: 5 more)"
	row.minus.tooltip = "One fewer (Shift: 5 fewer). At 0 it leaves the list."
	row.widgets[#row.widgets + 1] = row.minus
	row.widgets[#row.widgets + 1] = row.plus
end

local function updateShopButtons(row, r)
	row.minus.recipeID, row.plus.recipeID = r.recipeID, r.recipeID
end

-- Shift-click on any recipe list: add one craft to the shopping list.
function Prof.AddToList(recipeID)
	local ok = SK.Shopping.Add(recipeID, 1)
	local name = CI.NameOf({ recipeID = recipeID, itemID = (SK.RecipeDB.Get(recipeID) or {}).itemID or 0 })
		or ("recipe " .. recipeID)
	if ok then
		SK:Print("Shopping list: " .. name .. " x" .. SK.Shopping.Crafts(recipeID) .. ".")
	else
		SK:Print("Your shopping list is full (" .. SK.Shopping.MAX_RECIPES .. " recipes).")
	end
	return ok
end

local function recipeClick(r, button)
	if button ~= "RightButton" and Compat.ShiftDown() then return Prof.AddToList(r.recipeID) end
	if button == "RightButton" then Fav.ToggleRecipe(r.recipeID)
	else SK.CraftersTab:ShowRecipe(r.recipeID, r.skillLine) end
end

local SHIFT_TIP = "Shift-click to add it to your shopping list"

local function money(c) return SK.Prices.Money(c) end
local NO_PRICE = "no price"

local function setProfitCell(fs, r, col)
	local k = col.key
	if k == "name" then
		local name = SK.CraftIndex.NameOf({ recipeID = r.recipeID, itemID = r.itemID }) or "..."
		local hex = r.itemID > 0 and Compat.ItemQualityHex(r.itemID)
		local made = r.yield > 1 and Theme.Paint("dim", "  x" .. r.yield) or ""
		fs:SetText(recipeIcon(r) .. (hex and ("|c" .. hex .. name .. "|r") or name) .. made)
	elseif k == "colour" then
		local skill = SK.RecipeDB.MySkill(r.skillLine)
		fs:SetText(skill and Theme.SkillColour(SK.RecipeDB.ColourAt(r.recipeID, skill)) or "")
	elseif k == "cost" then
		local first = not r.cost and r.missingIDs and r.missingIDs[1]
		fs:SetText(r.cost and money(r.cost) or (first and Theme.Paint("spark", "needs " .. (CI.ItemName(first) or "...")))
			or Theme.Paint("dim", NO_PRICE))
	elseif k == "value" then
		fs:SetText(r.value and money(r.value) or Theme.Paint("dim", NO_PRICE))
	elseif k == "profit" then
		if not r.profit then fs:SetText(Theme.DASH)
		else fs:SetText(Theme.Paint(r.profit > 0 and "good" or "spark", money(r.profit))) end
	else
		fs:SetText(Theme.Paint("dim", r.via == "ah" and "auction" or r.via == "vendor" and "vendor" or ""))
	end
end

-- Tooltip lines for one craft: each reagent's price and where it's from.
function Prof.ProfitTip(tip, r)
	local P = SK.Prices
	for _, x in ipairs(SK.Reagents.All(r.recipeID) or {}) do
		local name = x.i and (CI.ItemName(x.i) or "...") or "currency"
		local each, via = nil, nil
		if x.i then each, via = P.Buy(x.i) end
		Theme.TipLine(tip, x.q .. " " .. name .. ":  " .. (each and (money(each * x.q) ..
			Theme.Paint("dim", Prof.ViaText(via))) or Theme.Paint("spark", NO_PRICE)), "text")
	end
	if r.value then
		Theme.TipLine(tip, "Makes " .. r.yield .. ", worth " .. money(r.value) .. (r.via == "ah" and
			Theme.Paint("dim", "  (auction price after the " .. math.floor(P.AH_CUT * 100) .. "% cut)") or
			Theme.Paint("dim", "  (what a vendor pays)")), "text", true)
	end
	if r.missing > 0 then
		Theme.TipLine(tip, "Reagents without a price: open the vendor that sells them (you don't need to buy), " ..
			"or scan the auction house with Auctionator or TSM.", "dim", true)
	end
end

-- Money after selling what you make: a negative cost is money earned.
local function netMoney(c)
	if c < 0 then return Theme.Paint("good", "earn " .. money(-c)) end
	return money(c)
end

local function setRouteCell(fs, s, col)
	local k = col.key
	if s.stuck then
		if k == "skill" then fs:SetText(s.from .. "+")
		elseif k == "name" then
			fs:SetText(Theme.Paint("spark", "Nothing you know" .. (SK.DB.settings.routeLearn ~= false and " or can learn" or "") ..
				" gives points here: visit your trainer"))
		else fs:SetText("") end
		return
	end
	if k == "skill" then
		fs:SetText(s.from .. Theme.Paint("dim", " - ") .. s.to)
	elseif k == "name" then
		local name = SK.CraftIndex.NameOf({ recipeID = s.recipeID, itemID = s.itemID or 0 }) or "..."
		local hex = (s.itemID or 0) > 0 and Compat.ItemQualityHex(s.itemID)
		fs:SetText(recipeIcon({ recipeID = s.recipeID, itemID = s.itemID or 0 }) .. (hex and ("|c" .. hex .. name .. "|r") or name) ..
			(s.learn and Theme.Paint("good", s.learn.trainer and "  learn at trainer" or "  learn from recipe") or ""))
	elseif k == "colour" then
		fs:SetText(Theme.SkillColour(SK.RecipeDB.ColourAt(s.recipeID, s.from)))
	elseif k == "crafts" then
		fs:SetText(s.crafts)
	elseif k == "cost" then
		fs:SetText(s.cost and netMoney(s.cost) or Theme.Paint("dim", NO_PRICE))
	else
		fs:SetText(s.cost and Theme.Paint("dim", netMoney(math.floor(s.cost / (s.to - s.from) + 0.5))) or "")
	end
end

local function setCooldownCell(fs, r, col)
	local k = col.key
	if k == "name" then
		fs:SetText(CI.SpellName(r.recipeID) or ("Recipe " .. r.recipeID))
	elseif k == "who" then
		fs:SetText(dot(r.status) .. " " .. Theme.ClassText(r.name, r.class))
	elseif k == "left" then
		fs:SetText(r.ready and Theme.Paint("good", "Ready") or PB.TimeLeft(r.left))
	elseif k == "asof" then
		if not r.asOf then fs:SetText(Theme.DASH)
		else
			local ago = Theme.Ago(r.asOf, Prof.now)
			local t = (r.guid == Compat.PlayerGUID() or ago == "now") and "now" or (ago .. " ago")
			fs:SetText(Theme.Paint(r.stale and "spark" or "dim", t))
		end
	else
		fs:SetText("")
	end
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
function Prof:Build(page)
	self.page = page
	self.filter = "all"
	local settings = SK.DB.settings

	-- Toolbar: Guild / Cooldowns, or a back button in the profession view.
	self.viewChips = {}
	local prev
	for _, v in ipairs(VIEWS) do
		local c = W.Chip(page, v[2], function()
			settings.profView = v[1]
			Prof.skillLine = nil
			Prof:Refresh()
		end)
		c.value = v[1]
		if prev then c:SetPoint("LEFT", prev, "RIGHT", SP.xs, 0) else c:SetPoint("TOPLEFT", 0, -1) end
		self.viewChips[#self.viewChips + 1] = c
		prev = c
	end
	self.back = W.Button(page, "All professions", nil, S.control, function()
		Prof.skillLine = nil
		Prof:Refresh()
	end)
	self.back:SetPoint("TOPLEFT", 0, 0)
	self.heading = Theme.Text(page, "title", "text")
	self.heading:SetPoint("LEFT", self.back, "RIGHT", SP.m, 0)
	self.status = Theme.Text(page, "small", "dim")
	self.status:SetPoint("TOPRIGHT", 0, -SP.xs)
	self.status:SetPoint("LEFT", prev, "RIGHT", SP.m, 0)
	self.status:SetJustifyH("RIGHT")
	self.status:SetWordWrap(false)

	local top = -(S.control + SP.m)
	-- The reminder line ("your Tailoring went up"), only when there is one.
	self.nudge = Theme.Text(page, "small", "spark")
	self.nudge:SetPoint("TOPLEFT", 0, top)
	self.nudge:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	self.nudge:SetWordWrap(true)

	self.board = W.List(page, {
		columns = BOARD_COLUMNS, setCell = setBoardCell,
		onClick = function(r) Prof:Open(r.skillLine) end,
		onEnter = function(row, r)
			GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
			GameTooltip:AddLine(r.name)
			if r.chars == 0 then
				Theme.TipLine(GameTooltip, "Nobody in the guild has this profession yet.", "spark")
			else
				Theme.TipLine(GameTooltip, Theme.Count(r.chars, "character") .. ", " .. r.online .. " online", "dim")
			end
			Theme.TipLine(GameTooltip, "Click to see crafters and recipes", "gold")
			GameTooltip:Show()
		end,
	})
	self.board:SetPoint("TOPLEFT", 0, top)
	self.board:SetPoint("BOTTOMRIGHT")

	self.cooldowns = W.List(page, {
		columns = COOLDOWN_COLUMNS, setCell = setCooldownCell,
		decorate = whisperButton, update = updateWhisper,
		onEnter = function(row, r)
			GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
			GameTooltip:AddLine(CI.SpellName(r.recipeID) or ("Recipe " .. r.recipeID))
			Theme.TipLine(GameTooltip, Theme.ClassText(r.name, r.class))
			Theme.TipLine(GameTooltip, "A cooldown only updates while its owner is online.", "dim", true)
			if r.stale then
				Theme.TipLine(GameTooltip, "We last heard from them " .. (r.asOf and (Theme.Ago(r.asOf) .. " ago") or
					"a while ago") .. ": it may be ready already.", "spark", true)
			end
			GameTooltip:Show()
		end,
		onClick = function(r) SK.CharacterTab:ShowCharacter(r.guid) end,
	})
	self.cooldowns:SetPoint("TOPLEFT", 0, top)
	self.cooldowns:SetPoint("BOTTOMRIGHT")

	-- All recipes: every recipe in the game (Data/Recipes.lua), searchable by
	-- name, the window's group ("camping") or material ("thorium bar").
	self.query, self.allProf = "", nil
	self.search = W.SearchBox(page, 300, "Search recipes, groups or materials", function(text)
		Prof.query = text
		Prof:Refresh()
	end)
	self.search:SetPoint("TOPLEFT", 0, top)
	self.profMenu = W.Menu(page, {
		width = 170,
		items = function()
			local items = { { value = "all", text = "All professions" } }
			local ids = {}
			for id in pairs(SK.Data.RECIPE_LIST or {}) do ids[#ids + 1] = id end
			table.sort(ids, function(a, b) return PB.ProfessionName(Prof.ctx or {}, a) < PB.ProfessionName(Prof.ctx or {}, b) end)
			for _, id in ipairs(ids) do items[#items + 1] = { value = id, text = PB.ProfessionName(Prof.ctx or {}, id) } end
			return items
		end,
		get = function() return Prof.allProf or "all" end,
		set = function(v)
			Prof.allProf = v ~= "all" and v or nil
			Prof:Refresh()
		end,
	})
	self.profMenu:SetPoint("LEFT", self.search, "RIGHT", SP.s, 0)
	self.profMenu.tooltip = "Pick a profession to list all its recipes"
	-- v0.5.3: show only some recipes, for you.
	self.allFilter = "all"
	self.showMenu = W.Menu(page, {
		width = 180,
		items = function() return Prof.SHOW_ITEMS end,
		get = function() return Prof.allFilter or "all" end,
		set = function(v)
			Prof.allFilter = v
			Prof:Refresh()
		end,
	})
	self.showMenu:SetPoint("LEFT", self.profMenu, "RIGHT", SP.s, 0)
	self.showMenu.tooltip = "Show only some recipes: ones you can learn now, by where they're learnt, or ones that " ..
		"still give you points"
	self.allList = W.List(page, {
		columns = ALL_COLUMNS, setCell = setAllCell,
		onEnter = function(row, r)
			GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
			if r.itemID > 0 and GameTooltip.SetItemByID then GameTooltip:SetItemByID(r.itemID)
			else GameTooltip:SetText(r.name) end
			local reagents = SK.Reagents.Text(SK.Reagents.Lines(r.recipeID), Theme.Code)
			if reagents then Theme.TipLine(GameTooltip, "Needs: " .. reagents, "dim", true) end
			W.SkillUpTip(GameTooltip, r.recipeID, r.skillLine)
			Theme.TipLine(GameTooltip, r.count > 0 and Theme.Count(r.count, "crafter") .. " in the guild" or
				"Nobody in the guild knows it yet", r.count > 0 and "good" or "spark")
			Theme.TipLine(GameTooltip, "Click for crafters, reagents and a Wowhead link  ·  Right-click to " ..
				(r.fav and "unstar" or "star"), "gold")
			Theme.TipLine(GameTooltip, SHIFT_TIP, "gold")
			GameTooltip:Show()
		end,
		onClick = recipeClick,
	})
	self.allList:SetPoint("TOPLEFT", 0, top - S.control - SP.m)
	self.allList:SetPoint("BOTTOMRIGHT")

	-- Levelling (v0.4.4): one of your professions, the recipes that still
	-- give skill-ups at your skill, best first. Ranges from Forever's data.
	self.levelMenu = W.Menu(page, {
		width = 220,
		items = function() return Prof.LevelItems() end,
		get = function() return Prof.LevelProfession() or "none" end,
		set = function(v)
			SK.DB.settings.levelProf = tonumber(v)
			Prof:Refresh()
		end,
	})
	self.levelMenu:SetPoint("TOPLEFT", 0, top)
	self.levelMenu.tooltip = "Which of your professions to level"
	self.levelList = W.List(page, {
		columns = LEVEL_COLUMNS, setCell = setLevelCell,
		onEnter = function(row, r)
			GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
			if r.itemID > 0 and GameTooltip.SetItemByID then GameTooltip:SetItemByID(r.itemID)
			else GameTooltip:SetText(CI.SpellName(r.recipeID) or ("Recipe " .. r.recipeID)) end
			local reagents = SK.Reagents.Text(SK.Reagents.Lines(r.recipeID), Theme.Code)
			if reagents then Theme.TipLine(GameTooltip, "Needs: " .. reagents, "dim", true) end
			W.SkillUpTip(GameTooltip, r.recipeID, r.skillLine)
			if r.range.ups > 1 then
				Theme.TipLine(GameTooltip, "Orange gives " .. r.range.ups .. " points per craft", "dim")
			end
			Theme.TipLine(GameTooltip, "Only recipes you've learned are listed: when a trainer or recipe teaches " ..
				"the others isn't in the game's data.", "dim", true)
			Theme.TipLine(GameTooltip, "Click for crafters, reagents and a Wowhead link", "gold")
			Theme.TipLine(GameTooltip, SHIFT_TIP, "gold")
			GameTooltip:Show()
		end,
		onClick = function(r, button)
			if button ~= "RightButton" and Compat.ShiftDown() then return Prof.AddToList(r.recipeID) end
			if button ~= "RightButton" then SK.CraftersTab:ShowRecipe(r.recipeID, r.skillLine) end
		end,
	})
	self.levelList:SetPoint("TOPLEFT", 0, top - S.control - SP.m)
	self.levelList:SetPoint("BOTTOMRIGHT")

	-- Shopping list (v0.4.5): your recipes on the left, reagents on the right.
	self.shopCopy = W.Button(page, "Copy", nil, S.control, function() Prof:CopyShopping() end)
	self.shopCopy:SetPoint("TOPLEFT", 0, top)
	self.shopCopy.tooltip = "The list as plain text (for Discord or a note)."
	self.shopClear = W.Button(page, "Clear list", nil, S.control, function() SK.Shopping.Clear() end, "quiet")
	self.shopClear:SetPoint("LEFT", self.shopCopy, "RIGHT", SP.s, 0)
	self.shopClear.tooltip = "Take every recipe off the list."
	self.shopRaw = W.Chip(page, "Raw materials", function()
		SK.DB.settings.shopRaw = not SK.DB.settings.shopRaw or nil
		SK.Shopping.Dirty()
		Prof:Refresh()
	end)
	self.shopRaw:SetPoint("LEFT", self.shopClear, "RIGHT", SP.s, 0)
	self.shopRaw.tooltip = "Reagents you make yourself (bolts, bars) become crafts on the list, with what they're made from."
	self.shopTSM = W.Button(page, "Copy for TSM", nil, S.control, function() Prof:CopyTSM() end, "quiet")
	self.shopTSM:SetPoint("LEFT", self.shopRaw, "RIGHT", SP.s, 0)
	self.shopTSM.tooltip = "What you still need to buy, as a TSM item list (i:2589,i:2592...) to import into a TSM group."
	self.shopCost = Theme.Text(page, "body", "text")
	self.shopCost:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	self.shopCost:SetPoint("TOP", self.shopCopy, "TOP", 0, 0)
	self.shopCost:SetPoint("BOTTOM", self.shopCopy, "BOTTOM", 0, 0)
	self.shopCost:SetJustifyH("RIGHT")
	self.shopRecipes = W.List(page, {
		columns = SHOP_RECIPE_COLUMNS, setCell = setShopRecipeCell,
		decorate = shopButtons, update = updateShopButtons,
		onEnter = function(row, r)
			GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
			if r.itemID > 0 and GameTooltip.SetItemByID then GameTooltip:SetItemByID(r.itemID)
			else GameTooltip:SetText(CI.SpellName(r.recipeID) or ("Recipe " .. r.recipeID)) end
			local reagents = SK.Reagents.Text(SK.Reagents.Lines(r.recipeID), Theme.Code)
			if reagents then Theme.TipLine(GameTooltip, "Each craft needs: " .. reagents, "dim", true) end
			W.SkillUpTip(GameTooltip, r.recipeID, r.skillLine)
			Theme.TipLine(GameTooltip, "Click for crafters  ·  Right-click to take it off the list", "gold")
			GameTooltip:Show()
		end,
		onClick = function(r, button)
			if button == "RightButton" then SK.Shopping.Set(r.recipeID, 0)
			else SK.CraftersTab:ShowRecipe(r.recipeID, r.skillLine) end
		end,
	})
	self.shopRecipes:SetPoint("TOPLEFT", 0, top - S.control - SP.m)
	self.shopRecipes:SetPoint("BOTTOMLEFT")
	self.shopRecipes:SetWidth(Prof.SHOP_W)
	self.shopReagents = W.List(page, {
		columns = SHOP_REAGENT_COLUMNS, setCell = setShopReagentCell,
		onEnter = function(row, r)
			GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
			if r.itemID and GameTooltip.SetItemByID then GameTooltip:SetItemByID(r.itemID)
			else GameTooltip:SetText("Currency") end
			if r.have ~= nil then
				Theme.TipLine(GameTooltip, "In your bags " .. r.bags .. "  ·  bank " .. r.bank, "dim")
			end
			if r.makeWith then
				Theme.TipLine(GameTooltip, "You can make it: " .. (CI.SpellName(r.makeWith) or "a recipe you know"), "good", true)
			end
			if r.itemID then
				local each, via = SK.Prices.Buy(r.itemID)
				Theme.TipLine(GameTooltip, each and ("Price: " .. money(each) .. " each" .. Theme.Paint("dim",
					Prof.ViaText(via))) or "No price yet", each and "text" or "dim")
			end
			local names = {}
			for _, id in ipairs(r.recipes) do
				names[#names + 1] = CI.NameOf({ recipeID = id, itemID = (SK.RecipeDB.Get(id) or {}).itemID or 0 }) or "..."
			end
			Theme.TipLine(GameTooltip, "For: " .. table.concat(names, ", "), "dim", true)
			GameTooltip:Show()
		end,
	})
	self.shopReagents:SetPoint("TOPLEFT", self.shopRecipes, "TOPRIGHT", SP.l, 0)
	self.shopReagents:SetPoint("BOTTOMRIGHT")

	-- Cheapest route (v0.4.8): one of your professions, from your skill to
	-- your cap, the recipe that costs least per point at each point.
	self.routeProf = W.Menu(page, {
		width = 220,
		items = function() return Prof.LevelItems() end,
		get = function() return Prof.LevelProfession() or "none" end,
		set = function(v)
			SK.DB.settings.levelProf = tonumber(v)
			Prof:Refresh()
		end,
	})
	self.routeProf:SetPoint("TOPLEFT", 0, top)
	self.routeProf.tooltip = "Which of your professions"
	self.routeAdd = W.Button(page, "Add all to shopping list", nil, S.control, function()
		local n = SK.Route.AddToShopping(Prof.routeSteps or {})
		if n > 0 then SK:Print("Added " .. Theme.Count(n, "recipe") .. " to your shopping list (Professions, Shopping list).") end
	end)
	self.routeAdd:SetPoint("LEFT", self.routeProf, "RIGHT", SP.s, 0)
	self.routeAdd.tooltip = "Every craft below, on your shopping list, to see which reagents to buy."
	self.routeLearnChip = W.Chip(page, "Recipes to learn", function()
		SK.DB.settings.routeLearn = SK.DB.settings.routeLearn == false
		Prof:Refresh()
	end)
	self.routeLearnChip:SetPoint("LEFT", self.routeAdd, "RIGHT", SP.s, 0)
	self.routeLearnChip.tooltip = "Also plan with recipes you don't know yet: recipe items with a price (TSM or a " ..
		"vendor you've visited) and recipes a trainer you've opened teaches. Learning costs are in the total."
	self.routeList = W.List(page, {
		columns = ROUTE_COLUMNS, setCell = setRouteCell,
		onEnter = function(row, s)
			if s.stuck then return end
			GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
			if (s.itemID or 0) > 0 and GameTooltip.SetItemByID then GameTooltip:SetItemByID(s.itemID)
			else GameTooltip:SetText(CI.SpellName(s.recipeID) or ("Recipe " .. s.recipeID)) end
			if s.learn then
				local how = s.learn.trainer and "from your trainer" or
					("from " .. (CI.ItemName(s.learn.item) or "its recipe item"))
				Theme.TipLine(GameTooltip, "Learn it first " .. how .. (s.learn.cost > 0 and (", " .. money(s.learn.cost)) or "") ..
					" (in the total)", "good", true)
			end
			if s.net then
				Theme.TipLine(GameTooltip, "Each craft: " .. netMoney(s.net) .. Theme.Paint("dim",
					"  (reagents, minus what you'd get for selling what it makes)"), "text", true)
			end
			Theme.TipLine(GameTooltip, "Yellow and green recipes don't always give a point, so crafts are an " ..
				"average (the original game's chance; not confirmed for Forever).", "dim", true)
			Theme.TipLine(GameTooltip, "Click for crafters and reagents", "gold")
			Theme.TipLine(GameTooltip, SHIFT_TIP, "gold")
			GameTooltip:Show()
		end,
		onClick = function(s, button)
			if s.stuck then return end
			if button ~= "RightButton" and Compat.ShiftDown() then return Prof.AddToList(s.recipeID) end
			if button ~= "RightButton" then SK.CraftersTab:ShowRecipe(s.recipeID, s.skillLine) end
		end,
	})
	self.routeList:SetPoint("TOPLEFT", 0, top - S.control - SP.m)
	self.routeList:SetPoint("BOTTOMRIGHT")

	-- Profit (v0.4.6): one of your professions, learned recipes, best first.
	self.profitProf = W.Menu(page, {
		width = 220,
		items = function() return Prof.LevelItems() end,
		get = function() return Prof.LevelProfession() or "none" end,
		set = function(v)
			SK.DB.settings.levelProf = tonumber(v)
			Prof:Refresh()
		end,
	})
	self.profitProf:SetPoint("TOPLEFT", 0, top)
	self.profitProf.tooltip = "Which of your professions"
	self.priceMenu = W.Menu(page, {
		width = 200,
		items = function() return Prof.PriceItems() end,
		get = function() return SK.DB.settings.priceSource or "auto" end,
		set = function(v)
			SK.DB.settings.priceSource = v
			Prof:Refresh()
		end,
	})
	self.priceMenu:SetPoint("LEFT", self.profitProf, "RIGHT", SP.s, 0)
	self.priceMenu.tooltip = "Where auction prices come from"
	self.profitList = W.List(page, {
		columns = PROFIT_COLUMNS, setCell = setProfitCell,
		onEnter = function(row, r)
			GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
			if r.itemID > 0 and GameTooltip.SetItemByID then GameTooltip:SetItemByID(r.itemID)
			else GameTooltip:SetText(CI.SpellName(r.recipeID) or ("Recipe " .. r.recipeID)) end
			Prof.ProfitTip(GameTooltip, r)
			Theme.TipLine(GameTooltip, "Click for crafters and reagents", "gold")
			Theme.TipLine(GameTooltip, SHIFT_TIP, "gold")
			GameTooltip:Show()
		end,
		onClick = function(r, button)
			if button ~= "RightButton" and Compat.ShiftDown() then return Prof.AddToList(r.recipeID) end
			if button ~= "RightButton" then SK.CraftersTab:ShowRecipe(r.recipeID, r.skillLine) end
		end,
	})
	self.profitList:SetPoint("TOPLEFT", 0, top - S.control - SP.m)
	self.profitList:SetPoint("BOTTOMRIGHT")

	-- One profession: crafters on the left, recipes on the right.
	self.crafters = W.List(page, {
		columns = CRAFTER_COLUMNS, setCell = setCrafterCell,
		decorate = whisperButton, update = updateWhisper,
		onEnter = function(row, c)
			GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
			GameTooltip:AddLine(Theme.ClassText(c.name, c.class))
			if c.altOf then Theme.TipLine(GameTooltip, "alt of " .. c.altOf, "dim") end
			if c.via then Theme.TipLine(GameTooltip, "Online on " .. (c.viaName or "an alt"), "good") end
			if c.max and c.max > 0 then Theme.TipLine(GameTooltip, "Skill " .. c.skill .. " / " .. c.max, "dim") end
			if #c.specs > 0 then Theme.TipLine(GameTooltip, table.concat(c.specs, ", "), "text") end
			if c.hidden then
				Theme.TipLine(GameTooltip, "Keeps their recipes private", "dim")
			elseif c.scanned then
				local stale = Theme.IsStale(c.scanned)
				Theme.TipLine(GameTooltip, "Recipes recorded " .. Theme.Ago(c.scanned) .. " ago" ..
					(stale and " (may be out of date)" or ""), stale and "spark" or "dim")
			elseif not SK.Data.GATHERING[Prof.skillLine] then
				Theme.TipLine(GameTooltip, "Hasn't opened this profession window with the addon yet", "dim", true)
			end
			local picked = Prof.crafter == c.guid
			Theme.TipLine(GameTooltip, (picked and "Click to show everyone's recipes" or "Click to see their recipes") ..
				"  ·  Right-click to " .. (c.fav and "unstar" or "star"), "gold")
			GameTooltip:Show()
		end,
		onClick = function(c, button)
			if button == "RightButton" then
				Fav.ToggleCrafter(c.guid)
			else
				Prof:PickCrafter(Prof.crafter ~= c.guid and c.guid or nil)
			end
		end,
	})
	self.crafters:SetSelected(function(c) return c.guid == Prof.crafter end)
	self.crafters:SetPoint("TOPLEFT", 0, top)
	self.crafters:SetPoint("BOTTOMLEFT")
	self.crafters:SetWidth(Prof.CRAFTERS_W)

	local right = CreateFrame("Frame", nil, page)
	right:SetPoint("TOPLEFT", self.crafters, "TOPRIGHT", SP.l, 0)
	right:SetPoint("BOTTOMRIGHT")
	self.right = right

	-- The picked crafter: name and skill, Character, and back to everyone.
	local picked = CreateFrame("Frame", nil, right)
	picked:SetPoint("TOPLEFT")
	picked:SetPoint("TOPRIGHT")
	picked:SetHeight(S.control)
	self.picked = picked
	self.everyone = W.Button(picked, "Everyone", nil, S.controlSmall, function() Prof:PickCrafter(nil) end, "quiet")
	self.everyone:SetPoint("RIGHT", 0, 0)
	self.everyone.tooltip = "Show the recipes of everyone in the guild again"
	self.charButton = W.Button(picked, "Character", nil, S.controlSmall, function()
		if Prof.crafter then SK.CharacterTab:ShowCharacter(Prof.crafter) end
	end)
	self.charButton:SetPoint("RIGHT", self.everyone, "LEFT", -SP.s, 0)
	self.charButton.tooltip = "Open their gear, talents and professions"
	self.pickedName = Theme.Text(picked, "body", "text")
	self.pickedName:SetPoint("LEFT", 0, 0)
	self.pickedName:SetPoint("RIGHT", self.charButton, "LEFT", -SP.s, 0)
	self.pickedName:SetJustifyH("LEFT")
	self.pickedName:SetWordWrap(false)

	self.filterChips = {}
	prev = nil
	for _, f in ipairs(RECIPE_FILTERS) do
		local c = W.Chip(right, f[2], function()
			Prof.filter = f[1]
			Prof:Refresh()
		end)
		c.value = f[1]
		if prev then c:SetPoint("LEFT", prev, "RIGHT", SP.xs, 0) else c:SetPoint("TOPLEFT", 0, -1) end
		self.filterChips[#self.filterChips + 1] = c
		prev = c
	end
	self.filterChips[2].tooltip = "Recipes only one character in the guild knows."
	self.filterChips[4].tooltip = "Recipes the profession window lists that nobody in the guild has learned."
	self.recipes = W.List(right, {
		columns = RECIPE_COLUMNS, setCell = setRecipeCell,
		onEnter = function(row, r)
			GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
			if r.itemID > 0 and GameTooltip.SetItemByID then GameTooltip:SetItemByID(r.itemID)
			else GameTooltip:SetText(r.name) end
			local reagents = SK.Reagents.Text(SK.Reagents.Lines(r.recipeID), Theme.Code)
			if reagents then Theme.TipLine(GameTooltip, "Needs: " .. reagents, "dim", true) end
			W.SkillUpTip(GameTooltip, r.recipeID, r.skillLine)
			Theme.TipLine(GameTooltip, "Click to see who can make it  ·  Right-click to " ..
				(r.fav and "unstar" or "star"), "gold")
			Theme.TipLine(GameTooltip, SHIFT_TIP, "gold")
			GameTooltip:Show()
		end,
		onClick = recipeClick,
	})
	self.recipes:SetPoint("TOPLEFT", 0, -(S.controlSmall + SP.s + 2)) -- moved down in RefreshOne when a crafter is picked
	self.recipes:SetPoint("BOTTOMRIGHT")

	local function refreshIfShown() if page:IsShown() then Prof:Refresh() end end
	SK:On("NAMES_LOADED", refreshIfShown)
	SK:On("CRAFT_INDEX_UPDATED", refreshIfShown)
	SK:On("FAVOURITES_CHANGED", refreshIfShown)
	SK:On("SHOPPING_CHANGED", refreshIfShown)
	SK:On("PRICES_CHANGED", refreshIfShown)
	local function bagsChanged()
		if page:IsShown() and SK.DB.settings.profView == "shopping" and not Prof.skillLine then Prof:Refresh() end
	end
	SK:RegisterEvent("BAG_UPDATE_DELAYED", bagsChanged)
	SK:RegisterEvent("PLAYERBANKSLOTS_CHANGED", bagsChanged)
end

function Prof:Open(skillLine)
	self.skillLine = skillLine
	self.filter = "all"
	self.crafter = nil
	self:Refresh()
end

-- Show one crafter's recipes on the right (nil = everyone's).
function Prof:PickCrafter(guid)
	self.crafter = guid
	if guid and self.filter == "nobody" then self.filter = "all" end
	self:Refresh()
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
function Prof:Refresh()
	if not self.board then return end
	local ctx = PB.Context()
	self.now, self.ctx = ctx.now, ctx
	local view = SK.DB.settings.profView
	if not VIEW_OK[view] or (view == "profit" and not Prof.ProfitUnlocked()) then view = "board" end
	local one = self.skillLine ~= nil
	for _, c in ipairs(self.viewChips) do
		c:SetShown(not one and (c.value ~= "profit" or Prof.ProfitUnlocked()))
		c:SetActive(c.value == view)
	end
	self.back:SetShown(one)
	self.heading:SetShown(one)
	self.board:SetShown(not one and view == "board")
	self.cooldowns:SetShown(not one and view == "cooldowns")
	self.search:SetShown(not one and view == "recipes")
	self.profMenu:SetShown(not one and view == "recipes")
	self.showMenu:SetShown(not one and view == "recipes")
	self.allList:SetShown(not one and view == "recipes")
	self.levelMenu:SetShown(not one and view == "levelling")
	self.levelList:SetShown(not one and view == "levelling")
	local shop = not one and view == "shopping"
	self.shopCopy:SetShown(shop)
	self.shopClear:SetShown(shop)
	self.shopRaw:SetShown(shop)
	self.shopTSM:SetShown(shop)
	self.shopRecipes:SetShown(shop)
	self.shopReagents:SetShown(shop)
	self.shopCost:SetShown(shop)
	local route = not one and view == "route"
	self.routeProf:SetShown(route)
	self.routeAdd:SetShown(route)
	self.routeLearnChip:SetShown(route)
	self.routeList:SetShown(route)
	local profit = not one and view == "profit"
	self.profitProf:SetShown(profit)
	self.priceMenu:SetShown(profit)
	self.profitList:SetShown(profit)
	self.crafters:SetShown(one)
	self.right:SetShown(one)

	-- Reminder line (shown even when chat reminders are off).
	local nudge = SK.Professions.NudgeText(SK.Professions.CurrentNudges())
	self.nudge:SetText(nudge or "")
	self.nudge:SetShown(nudge ~= nil and not one)
	local shift = nudge and not one and (self.nudge:GetStringHeight() or 0) + SP.s or 0
	local top = -(S.control + SP.m) - shift
	self.board:SetPoint("TOPLEFT", 0, top)
	self.cooldowns:SetPoint("TOPLEFT", 0, top)
	self.search:SetPoint("TOPLEFT", 0, top)
	self.allList:SetPoint("TOPLEFT", 0, top - S.control - SP.m)
	self.levelMenu:SetPoint("TOPLEFT", 0, top)
	self.levelList:SetPoint("TOPLEFT", 0, top - S.control - SP.m)
	self.shopCopy:SetPoint("TOPLEFT", 0, top)
	self.shopRecipes:SetPoint("TOPLEFT", 0, top - S.control - SP.m)
	self.profitProf:SetPoint("TOPLEFT", 0, top)
	self.profitList:SetPoint("TOPLEFT", 0, top - S.control - SP.m)
	self.routeProf:SetPoint("TOPLEFT", 0, top)
	self.routeList:SetPoint("TOPLEFT", 0, top - S.control - SP.m)

	if one then return self:RefreshOne(ctx) end
	if view == "recipes" then return self:RefreshAll(ctx) end
	if view == "levelling" then return self:RefreshLevelling() end
	if view == "shopping" then return self:RefreshShopping() end
	if view == "profit" then return self:RefreshProfit() end
	if view == "route" then return self:RefreshRoute() end
	if view == "cooldowns" then
		local rows = PB.Cooldowns(ctx)
		local ready = 0
		for _, r in ipairs(rows) do if r.ready then ready = ready + 1 end end
		self.cooldowns:SetItems(rows)
		self.cooldowns:SetEmptyText("No profession cooldowns yet. They appear once someone with a cooldown " ..
			"recipe (a transmute, Mooncloth...) opens their profession window with the addon.")
		self.status:SetText(#rows > 0 and (ready .. " ready  ·  " .. Theme.Count(#rows, "cooldown")) or "")
	else
		local rows = PB.Coverage(ctx)
		local missing = 0
		for _, r in ipairs(rows) do if r.chars == 0 then missing = missing + 1 end end
		self.board:SetItems(rows)
		self.status:SetText(missing > 0 and (Theme.Count(missing, "profession") .. " nobody has") or
			"Every profession is covered")
	end
end

---------------------------------------------------------------------------
-- Levelling (v0.4.4)
---------------------------------------------------------------------------
-- Your professions that have recipes in the game's data, for the menu.
function Prof.LevelItems()
	local items = {}
	local own = SK.Profile:Own()
	for skillLine, p in pairs(own and own.profs or {}) do
		if #SK.RecipeDB.List(skillLine) > 0 then
			items[#items + 1] = { value = skillLine, text = (p.name or PB.ProfessionName({}, skillLine)) ..
				"  " .. (p.rank or 0) .. " / " .. (p.max or 0), primary = p.primary }
		end
	end
	table.sort(items, function(a, b)
		if a.primary ~= b.primary then return a.primary == true end
		return a.text < b.text
	end)
	if #items == 0 then items[1] = { value = "none", text = "No professions yet" } end
	return items
end

-- The profession the Levelling view shows: the saved pick if you still have
-- it, else your first primary profession.
function Prof.LevelProfession()
	local own = SK.Profile:Own()
	local profs = own and own.profs or {}
	local pick = SK.DB.settings.levelProf
	if pick and profs[pick] then return pick end
	local items = Prof.LevelItems()
	return type(items[1].value) == "number" and items[1].value or nil
end

-- "12 recipes still give skill-ups: 3 orange · 5 yellow · 4 green". Pure; tested.
function Prof.LevelSummary(rows)
	local n = { orange = 0, yellow = 0, green = 0 }
	for _, r in ipairs(rows) do if r.known then n[r.colour] = n[r.colour] + 1 end end
	local known = n.orange + n.yellow + n.green
	local text = Theme.Count(known, "learned recipe") .. " still give skill-ups"
	if known > 0 then
		text = text .. ": " .. table.concat({ Theme.SkillColour("orange", n.orange .. " orange"),
			Theme.SkillColour("yellow", n.yellow .. " yellow"), Theme.SkillColour("green", n.green .. " green") }, "  ·  ")
	end
	return text, n
end

function Prof:RefreshLevelling()
	self.levelMenu:Refresh()
	local skillLine = Prof.LevelProfession()
	local own = SK.Profile:Own()
	local prof = skillLine and own and own.profs[skillLine]
	if not prof then
		self.levelList:SetItems({})
		self.levelList:SetEmptyText("You haven't learned a profession on this character yet.")
		self.status:SetText("")
		return
	end
	local known = {}
	for id in pairs(own.recipes and own.recipes[skillLine] or {}) do known[id] = true end
	SK.CraftIndex.SetBudget(SK.RecipeDB.REQUESTS_PER_SEARCH)
	local rows = SK.RecipeDB.SkillUps(skillLine, prof.rank or 0, known)
	for _, r in ipairs(rows) do SK.CraftIndex.NameOf({ recipeID = r.recipeID, itemID = r.itemID }) end
	SK.CraftIndex.SetBudget(nil)
	self.levelList:SetItems(rows)
	local scanned = prof.scanned ~= nil
	self.levelList:SetEmptyText(scanned and ("None of your recipes gives skill-ups at " .. (prof.rank or 0) ..
		" any more. Learn new ones from a trainer or recipes.") or ("Open your " .. (prof.name or "profession") ..
		" window once so Short Royalty knows which recipes you've learned."))
	local summary = Prof.LevelSummary(rows)
	-- v0.5.0: recipes a trainer you've visited would teach you now.
	local trainable = SK.Learn.Trainable(skillLine, prof.rank or 0, known)
	if #trainable > 0 then
		summary = summary .. "  ·  " .. Theme.Paint("good", #trainable .. " to learn at your trainer")
	end
	if not scanned then summary = Theme.Paint("spark", "Open your " .. (prof.name or "profession") .. " window once") end
	self.status:SetText(summary)
end

---------------------------------------------------------------------------
-- Shopping list (v0.4.5)
---------------------------------------------------------------------------
-- "3 recipes · 7 reagents · 4 still to get". Pure; tested.
function Prof.ShopSummary(nRecipes, nReagents, nShort, nUnknown)
	if nRecipes == 0 then return "" end
	local text = Theme.Count(nRecipes, "recipe") .. "  ·  " .. Theme.Count(nReagents, "reagent") .. "  ·  " ..
		(nShort > 0 and Theme.Paint("spark", nShort .. " still to get") or Theme.Paint("good", "you have everything"))
	if nUnknown > 0 then text = text .. "  ·  " .. Theme.Paint("dim", nUnknown .. " without reagent data") end
	return text
end

local function shopName(id, isRecipe)
	if isRecipe then return CI.NameOf({ recipeID = id, itemID = (SK.RecipeDB.Get(id) or {}).itemID or 0 }) end
	return CI.ItemName(id)
end

-- "  (vendor)" / "  (auction)" / "  (you make it)". Pure.
function Prof.ViaText(via)
	return via == "vendor" and "  (vendor)" or via == "make" and "  (you make it)" or "  (auction)"
end

function Prof:CopyTSM()
	local text = SK.Shopping.TSMList((SK.Shopping.Rows()))
	SK.DebugWindow:ShowText("Copy for TSM", text ~= "" and text or "Nothing left to buy.")
	return text
end

function Prof:CopyShopping()
	local rows = SK.Shopping.Rows()
	local text = SK.Shopping.Text(SK.Shopping.Entries(), rows, shopName)
	SK.DebugWindow:ShowText("Copy as text", text)
	return text
end

function Prof:RefreshShopping()
	local entries = SK.Shopping.Entries()
	local items = {}
	for _, e in ipairs(entries) do
		local db = SK.RecipeDB.Get(e.id)
		items[#items + 1] = { recipeID = e.id, n = e.n, itemID = db and db.itemID or 0, skillLine = db and db.skillLine }
	end
	local rows, unknown = SK.Shopping.Rows()
	for _, r in ipairs(rows) do
		if r.itemID then r.makeWith = SK.Shopping.YouMake(r.itemID) end
	end
	self.shopRecipes:SetItems(items)
	self.shopRecipes:SetEmptyText("Your shopping list is empty. Shift-click a recipe (All recipes, Levelling or a " ..
		"profession's list) to add it, or press + List on the Crafters tab.")
	self.shopReagents:SetItems(rows)
	self.shopReagents:SetEmptyText(#items > 0 and "No reagent data for these recipes yet. Open the profession's " ..
		"window once." or "The reagents show here, with how many you have in your bags and bank.")
	self.shopClear:SetDisabled(#items == 0)
	self.shopTSM:SetDisabled(#items == 0)
	self.shopRaw:SetActive(SK.DB.settings.shopRaw == true)
	self.shopCopy:SetDisabled(#items == 0)
	local _, nReagents, nShort = SK.Shopping.Summary(entries, rows)
	self.status:SetText(Prof.ShopSummary(#items, nReagents, nShort, #unknown))
	self.shopCost:SetText(Prof.ShopCostText(SK.Shopping.Cost(rows, function(id) return (SK.Prices.Buy(id)) end)))
end

-- "About 1g 20s to buy (2 without a price)". Pure; tested.
function Prof.ShopCostText(total, missing)
	if total == 0 and missing == 0 then return "" end
	local text = total > 0 and ("About " .. money(total) .. " to buy") or ""
	if missing > 0 then
		text = text .. (text ~= "" and "  " or "") .. Theme.Paint("dim", "(" .. missing .. " without a price)")
	end
	return text
end

---------------------------------------------------------------------------
-- Profit (v0.4.6)
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Cheapest route (v0.4.8)
---------------------------------------------------------------------------
-- "Tailoring 120 → 150 · about 5g 20s". Pure; tested.
function Prof.RouteSummary(name, from, to, total, unpriced, source)
	local text = name .. " " .. from .. " to " .. to
	if total ~= 0 or unpriced == 0 then
		text = text .. "  ·  " .. (total < 0 and Theme.Paint("good", "earns about " .. money(-total))
			or ("about " .. money(total)))
	end
	if unpriced > 0 then text = text .. "  ·  " .. Theme.Paint("dim", Theme.Count(unpriced, "step") .. " without a price") end
	if not source then text = text .. "  ·  " .. Theme.Paint("spark", "no TSM: vendor prices only") end
	return text
end

function Prof:RefreshRoute()
	self.routeProf:Refresh()
	local skillLine = Prof.LevelProfession()
	local own = SK.Profile:Own()
	local prof = skillLine and own and own.profs[skillLine]
	Prof.routeSteps = {}
	if not prof then
		self.routeList:SetItems({})
		self.routeList:SetEmptyText("You haven't learned a profession on this character yet.")
		self.status:SetText("")
		self.routeAdd:SetDisabled(true)
		return
	end
	local from, to = prof.rank or 0, prof.max or 0
	local steps, total, unpriced = SK.Route.ForProfession(skillLine)
	if not steps then steps, total, unpriced = {}, 0, 0 end
	self.routeLearnChip:SetActive(SK.DB.settings.routeLearn ~= false)
	SK.CraftIndex.SetBudget(SK.RecipeDB.REQUESTS_PER_SEARCH)
	for _, s in ipairs(steps) do
		s.skillLine = skillLine
		if s.learn and s.learn.item then CI.ItemName(s.learn.item) end
		if s.recipeID then
			local r = SK.RecipeDB.Get(s.recipeID)
			s.itemID = r and r.itemID or 0
			SK.CraftIndex.NameOf({ recipeID = s.recipeID, itemID = s.itemID })
		end
	end
	SK.CraftIndex.SetBudget(nil)
	Prof.routeSteps = steps
	self.routeList:SetItems(steps)
	local name = prof.name or "profession"
	if not prof.scanned then
		self.routeList:SetEmptyText("Open your " .. name .. " window once so Short Royalty knows which recipes you've learned.")
	elseif from >= to then
		self.routeList:SetEmptyText("You're at your cap (" .. to .. "). Learn the next rank from your trainer, " ..
			"then come back for the route.")
	else
		self.routeList:SetEmptyText("None of your recipes gives points at " .. from .. ". Learn new ones from your trainer.")
	end
	local crafted = 0
	for _, s in ipairs(steps) do if not s.stuck then crafted = crafted + 1 end end
	self.routeAdd:SetDisabled(crafted == 0)
	self.status:SetText(#steps > 0 and Prof.RouteSummary(name, from, to, total, unpriced, SK.Prices.Source()) or "")
end

-- Profit is hidden until unlocked with /sr profit (the owner's wish, 11 Nov):
-- once per account, every character.
function Prof.ProfitUnlocked()
	return type(SK.DB.unlocked) == "table" and SK.DB.unlocked.profit == true and SK.Prices.IsOwnerAccount()
end

function Prof.PriceItems()
	local have = Compat.PriceAddons()
	local function label(name, ok) return "Prices: " .. name .. (ok and "" or " (not installed)") end
	return {
		{ value = "auto", text = "Prices: automatic" },
		{ value = "auctionator", text = label("Auctionator", have.auctionator) },
		{ value = "tsm", text = label("TSM", have.tsm) },
	}
end

-- Status line. Pure; tested.
function Prof.ProfitSummary(rows, source)
	local priced, gain = 0, 0
	for _, r in ipairs(rows) do
		if r.profit then
			priced = priced + 1
			if r.profit > 0 then gain = gain + 1 end
		end
	end
	local head = source and ("Prices from " .. SK.Prices.SOURCE_NAMES[source]) or
		Theme.Paint("spark", "No Auctionator or TSM: vendor prices only")
	return head .. "  ·  " .. Theme.Count(priced, "recipe") .. " priced  ·  " ..
		Theme.Paint(gain > 0 and "good" or "dim", gain .. " make a profit")
end

function Prof:RefreshProfit()
	self.profitProf:Refresh()
	self.priceMenu:Refresh()
	local skillLine = Prof.LevelProfession()
	local own = SK.Profile:Own()
	local prof = skillLine and own and own.profs[skillLine]
	if not prof then
		self.profitList:SetItems({})
		self.profitList:SetEmptyText("You haven't learned a profession on this character yet.")
		self.status:SetText("")
		return
	end
	local known = own.recipes and own.recipes[skillLine] or {}
	SK.CraftIndex.SetBudget(SK.RecipeDB.REQUESTS_PER_SEARCH)
	local rows = SK.Prices.Batch(SK.Prices.Rows, skillLine, known)
	for _, r in ipairs(rows) do
		SK.CraftIndex.NameOf({ recipeID = r.recipeID, itemID = r.itemID })
		for _, x in ipairs(SK.Reagents.All(r.recipeID) or {}) do if x.i then CI.ItemName(x.i) end end
	end
	SK.CraftIndex.SetBudget(nil)
	self.profitList:SetItems(rows)
	self.profitList:SetEmptyText(prof.scanned and "No learned recipes in this profession yet." or
		("Open your " .. (prof.name or "profession") .. " window once so Short Royalty knows which recipes you've learned."))
	self.status:SetText(Prof.ProfitSummary(rows, SK.Prices.Source()) .. Prof.MissingText(SK.Prices.MissingTop(rows, 3)))
end

-- "  ·  no price yet: Green Dye (12), Coarse Thread (9)" (v0.5.6), or "".
function Prof.MissingText(top)
	if #top == 0 then return "" end
	local parts = {}
	for i, m in ipairs(top) do parts[i] = (CI.ItemName(m[1]) or "...") .. " (" .. m[2] .. ")" end
	return "  ·  " .. Theme.Paint("spark", "no price yet: " .. table.concat(parts, ", "))
end

Prof.SHOW_ITEMS = {
	{ value = "all", text = "Show: everything" },
	{ value = "learnable", text = "Show: can learn now" },
	{ value = "item", text = "Show: recipe items" },
	{ value = "trainer", text = "Show: trainers" },
	{ value = "points", text = "Show: give you points" },
}

-- Pure (v0.5.3): rows of RecipeDB.Search, kept by `filter`. you(skillLine)
-- -> { skill, known = { [recipeID] } } for your professions (nil if you
-- don't have it); learnAt(recipeID) -> skill a recipe item or a trainer
-- you've seen needs (nil if unknown); colourAt(recipeID, skill).
-- The learning filters sort by that skill.
function Prof.FilterRecipes(rows, filter, you, learnAt, hasItem, colourAt)
	if filter == nil or filter == "all" then return rows end
	local out = {}
	for _, r in ipairs(rows) do
		local me = you(r.skillLine)
		local known = me and me.known[r.recipeID]
		local keep
		if filter == "learnable" then
			local at = learnAt(r.recipeID)
			keep = me and not known and at and at <= me.skill
		elseif filter == "item" then keep = hasItem(r.recipeID)
		elseif filter == "trainer" then keep = not hasItem(r.recipeID)
		elseif filter == "points" then
			local c = me and known and colourAt(r.recipeID, me.skill)
			keep = c ~= nil and c ~= "grey"
		end
		if keep then out[#out + 1] = r end
	end
	if filter ~= "points" then
		table.sort(out, function(a, b)
			local x, y = learnAt(a.recipeID) or 9999, learnAt(b.recipeID) or 9999
			if x ~= y then return x < y end
			return (a.name or "") < (b.name or "")
		end)
	end
	return out
end

local function you(skillLine)
	local own = SK.Profile:Own()
	local p = own and own.profs[skillLine]
	if not p then return nil end
	return { skill = p.rank or 0, known = own.recipes and own.recipes[skillLine] or {} }
end

local function learnAt(recipeID)
	local how = SK.Learn.Info(recipeID)
	if how.itemAt and how.trainerAt then return math.min(how.itemAt, how.trainerAt) end
	return how.itemAt or how.trainerAt
end

local function hasItem(recipeID) return SK.RecipeDB.RecipeItem(recipeID) ~= nil end

function Prof:RefreshAll(ctx)
	self.profMenu:Refresh()
	self.showMenu:Refresh()
	local rows, state, loading = SK.RecipeDB.Search(self.query, self.allProf, ctx.index)
	rows = Prof.FilterRecipes(rows, Prof.allFilter, you, learnAt, hasItem, SK.RecipeDB.ColourAt)
	self.allList:SetItems(rows)
	self.allList:SetLoading(state == "ok" and #rows == 0 and loading > 0)
	if state == "short" then
		self.allList:SetEmptyText("Type at least " .. SK.RecipeDB.MIN_QUERY .. " letters of a recipe, item, group or " ..
			"material (\"mooncloth\", \"camping\", \"thorium bar\"), or pick a profession to see all of its recipes.")
		self.status:SetText(Theme.Count(SK.RecipeDB.Count(), "recipe") .. " in the game")
	else
		self.allList:SetEmptyText(loading > 0 and "Loading names from the game..." or "No recipe matches that.")
		local text = (#rows >= SK.RecipeDB.MAX_RESULTS) and (SK.RecipeDB.MAX_RESULTS .. "+ results, type more")
			or Theme.Count(#rows, "recipe")
		if loading > 0 then text = text .. "  ·  " .. Theme.Paint("spark", "loading " .. loading .. " names...") end
		self.status:SetText(text)
	end
end

function Prof:RefreshOne(ctx)
	local skillLine = self.skillLine
	local profName = PB.ProfessionName(ctx, skillLine)
	self.heading:SetText(profName)
	local crafters = PB.Crafters(ctx, skillLine)
	-- The picked crafter, if they still have this profession.
	local picked
	for _, c in ipairs(crafters) do if c.guid == self.crafter then picked = c end end
	if not picked then self.crafter = nil end
	self.crafters:SetItems(crafters)
	self.crafters:SetEmptyText("Nobody in the guild has this profession yet.")

	self.picked:SetShown(picked ~= nil)
	if picked then
		local skill = picked.skill > 0 and Theme.Paint("dim", "  ·  " .. profName .. " " .. picked.skill) or ""
		self.pickedName:SetText(Theme.ClassText(picked.name, picked.class) .. skill)
	end
	local chipsY = picked and -(S.control + SP.s) or -1
	for i, c in ipairs(self.filterChips) do
		if i == 1 then c:SetPoint("TOPLEFT", 0, chipsY) end
	end
	self.recipes:SetPoint("TOPLEFT", 0, chipsY - (S.controlSmall + SP.s + 1))

	local unknown = not picked and #PB.Unknown(ctx, skillLine) > 0
	if self.filter == "nobody" and not unknown then self.filter = "all" end
	for _, c in ipairs(self.filterChips) do
		c:SetActive(c.value == self.filter)
		if c.value == "nobody" then c:SetShown(unknown) end
		if c.value == "one" then c.label:SetText(picked and "Only they know" or "Only one crafter") end
	end
	local rows, loading = PB.Recipes(ctx, skillLine, self.filter, picked and picked.guid)
	self.recipes:SetItems(rows)
	self.recipes:SetLoading(loading > 0 and #rows == 0)
	local gathering = SK.Data.GATHERING[skillLine]
	local empty = {
		all = gathering and "No recipes yet. In Forever some gathering professions have recipes too " ..
			"(Herbalism: camping items); they appear once someone opens that window." or
			"No recipes yet. They appear after crafters open their profession window once.",
		one = "No recipe has just one crafter.",
		fav = "No starred recipes. Right-click a recipe to star it.",
		nobody = "Everything the profession window lists is known by someone.",
	}
	if picked then
		local first = picked.name:match("^(%S+)") or picked.name
		if picked.hidden then
			empty.all = first .. " keeps their recipes private."
		elseif not picked.scanned then
			empty.all = first .. " hasn't opened their " .. profName .. " window with Short Royalty yet, " ..
				"so we don't know their recipes."
		else
			empty.all = "No " .. profName .. " recipes recorded for " .. first .. "."
		end
		empty.one = "No recipe that only " .. first .. " knows."
		empty.fav = "None of " .. first .. "'s recipes are starred."
	end
	self.recipes:SetEmptyText(empty[self.filter])
	local online = 0
	for _, c in ipairs(crafters) do if c.status ~= "offline" then online = online + 1 end end
	self.status:SetText(Theme.Count(#crafters, "character") .. ", " .. online .. " online  ·  " ..
		(picked and ((picked.name:match("^(%S+)") or picked.name) .. " knows ") or "") .. Theme.Count(#rows, "recipe"))
end

SK.MainFrame:AddTab("professions", "Professions", Prof)
