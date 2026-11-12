-- Professions tab (v0.3, page tabs since v0.6.0): Guild (the coverage
-- board, then one profession at a time: crafters and recipes), Recipes
-- (every recipe in the game) and Cooldowns. Numbers come from
-- Core/ProfBoard.lua; clicking a recipe opens it in Find a crafter.
-- In one profession, clicking a crafter shows that crafter's recipes on the
-- right (v0.3.4), with a Character button to open their character sheet.
local _, SK = ...

local Prof = SK:NewModule("ProfessionsTab")
local Theme, W, Compat = SK.Theme, SK.Widgets, SK.Compat
local PB, CI, Fav = SK.ProfBoard, SK.CraftIndex, SK.Favourites
local S, SP = Theme.SIZES, Theme.SPACE

Prof.CRAFTERS_W = 380
Prof.RECIPES_W = S.contentW - Prof.CRAFTERS_W - SP.l

-- Levelling, Route, Shopping list and Profit were removed in v0.5.6 (owner,
-- 12 Nov: "not working as intended"); git history has them (v0.4.4-v0.5.5).
local VIEWS = { { "board", "Guild" }, { "recipes", "Recipes" }, { "cooldowns", "Cooldowns" } }
Prof.VIEWS = VIEWS
local VIEW_OK = { board = true, recipes = true, cooldowns = true }
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
	end, "quiet")
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
-- Board: 744 - 12 = 732. Specialisations are in the row's tooltip.
local BOARD_COLUMNS = {
	{ key = "name", title = "Profession", width = 232 },
	{ key = "chars", title = "Crafters", width = 100, align = "RIGHT" },
	{ key = "atMax", title = "At " .. SK.Data.SKILL_CAP, width = 100, align = "RIGHT" },
	{ key = "online", title = "Online", width = 100, align = "RIGHT" },
	{ key = "top", title = "Top skill", width = 100, align = "RIGHT" },
	{ key = "scan", title = "Updated", width = 100, align = "RIGHT" },
}

-- Crafters: 380 - 12 = 368. Specialisations are in the tooltip.
local CRAFTER_COLUMNS = {
	{ key = "name", title = "Character", width = 176 },
	{ key = "skill", title = "Skill", width = 50, align = "RIGHT" },
	{ key = "scan", title = "Recipes", width = 76, align = "RIGHT" },
	{ key = "btn", title = "", width = 66 },
}

-- Recipes: 348 - 12 = 336.
local RECIPE_COLUMNS = {
	{ key = "name", title = "Recipe", width = 256 },
	{ key = "count", title = "Crafters", width = 80, align = "RIGHT" },
}

-- Recipes (every recipe in the game): 732.
local ALL_COLUMNS = {
	{ key = "name", title = "Recipe", width = 290 },
	{ key = "prof", title = "Profession", width = 120 },
	{ key = "group", title = "Group", width = 222 },
	{ key = "count", title = "Crafters", width = 100, align = "RIGHT" },
}

-- Cooldowns: 732.
local COOLDOWN_COLUMNS = {
	{ key = "name", title = "Cooldown", width = 246 },
	{ key = "who", title = "Crafter", width = 180 },
	{ key = "left", title = "Ready in", width = 100, align = "RIGHT" },
	{ key = "asof", title = "As of", width = 120, align = "RIGHT" },
	{ key = "btn", title = "", width = 86 },
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
		local star = c.fav and (Theme.Star("accent") .. " ") or ""
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

local function setRecipeCell(fs, r, col)
	if col.key == "name" then
		local hex = r.itemID > 0 and Compat.ItemQualityHex(r.itemID)
		local name = hex and ("|c" .. hex .. r.name .. "|r") or r.name
		fs:SetText((r.fav and (Theme.Star("accent") .. " ") or "") .. recipeIcon(r) .. name)
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

local function recipeClick(r, button)
	if button == "RightButton" then Fav.ToggleRecipe(r.recipeID)
	else SK.CraftersTab:ShowRecipe(r.recipeID, r.skillLine) end
end

-- The short recipe tooltip (W.RecipeTip): one crafter is named.
local function recipeTip(row, r)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	local tip = { recipeID = r.recipeID, itemID = r.itemID, skillLine = r.skillLine, name = r.name, count = r.count,
		fav = r.fav }
	if r.count == 1 then
		local index = Prof.ctx and Prof.ctx.index
		local entry = index and index.recipes and index.recipes[r.recipeID]
		local c = entry and entry.crafters and entry.crafters[1] -- a GUID
		local guild = SK.DBM:Guild()
		local m = c and guild and guild.members[c]
		if m then tip.crafterName, tip.crafterOnline = Theme.ClassText(m.name, m.class), m.online end
	end
	W.RecipeTip(GameTooltip, tip, "Click: crafters, reagents, Wowhead")
	GameTooltip:Show()
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

	-- Page tabs: Guild / Recipes / Cooldowns, with the count on the right.
	self.views = W.SubTabs(page, VIEWS, function(key)
		settings.profView = key
		Prof.skillLine = nil
		Prof:Refresh()
	end)
	self.views:SetPoint("TOPLEFT", 0, 0)
	self.views:SetPoint("TOPRIGHT", 0, 0)
	self.viewChips = self.views.tabs
	self.status = Theme.Text(page, "small", "dim")
	self.status:SetPoint("RIGHT", self.views, "RIGHT", 0, SP.xxs)
	self.status:SetPoint("LEFT", self.views, "LEFT", 300, 0)
	self.status:SetJustifyH("RIGHT")
	self.status:SetWordWrap(false)

	local top = -(S.subTabs + SP.m)
	-- One profession: a back link and its name.
	self.back = W.Button(page, "All professions", nil, S.control, function()
		Prof.skillLine = nil
		Prof:Refresh()
	end, "quiet")
	self.back:SetPoint("TOPLEFT", -SP.s, top)
	self.heading = Theme.Text(page, "title", "text")
	self.heading:SetPoint("LEFT", self.back, "RIGHT", SP.xs, 0)

	-- The reminder ("your Tailoring went up"): a slim bar with an Open button.
	local nudgeBar = CreateFrame("Frame", nil, page)
	nudgeBar:SetPoint("TOPLEFT", 0, top)
	nudgeBar:SetPoint("TOPRIGHT", 0, top)
	nudgeBar:SetHeight(S.control + SP.s)
	nudgeBar.bg = nudgeBar:CreateTexture(nil, "BACKGROUND")
	nudgeBar.bg:SetAllPoints()
	Theme.Solid(nudgeBar.bg, "spark", Theme.ALPHA.alert)
	nudgeBar.edge = nudgeBar:CreateTexture(nil, "ARTWORK")
	nudgeBar.edge:SetPoint("TOPLEFT")
	nudgeBar.edge:SetPoint("BOTTOMLEFT")
	nudgeBar.edge:SetWidth(SP.xxs)
	Theme.Solid(nudgeBar.edge, "spark")
	nudgeBar.open = W.Button(nudgeBar, "Open", nil, S.controlSmall, function(b)
		if b.skillLine then SK.MainFrame:OpenNextProfession(b.skillLine, b.profName) end
	end)
	nudgeBar.open:SetPoint("RIGHT", -SP.s, 0)
	nudgeBar.open.tooltip = "Opens your profession window so guildmates see your new recipes."
	self.nudgeBar = nudgeBar
	self.nudge = Theme.Text(nudgeBar, "small", "text")
	self.nudge:SetPoint("LEFT", SP.m, 0)
	self.nudge:SetPoint("RIGHT", nudgeBar.open, "LEFT", -SP.m, 0)
	self.nudge:SetWordWrap(false)

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
				local specs = PB.SpecText(r.specs)
				if specs ~= "" then Theme.TipLine(GameTooltip, specs, "text", true) end
			end
			Theme.TipLine(GameTooltip, "Click to see crafters and recipes", "accent")
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
		onEnter = recipeTip,
		onClick = recipeClick,
	})
	self.allList:SetPoint("TOPLEFT", 0, top - S.control - SP.m)
	self.allList:SetPoint("BOTTOMRIGHT")

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
				"  ·  Right-click to " .. (c.fav and "unstar" or "star"), "accent")
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
	self.crafters:SetPoint("TOPLEFT", 0, top - S.control - SP.s)
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
	local prev
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
		onEnter = recipeTip,
		onClick = recipeClick,
	})
	self.recipes:SetPoint("TOPLEFT", 0, -(S.controlSmall + SP.s + 2)) -- moved down in RefreshOne when a crafter is picked
	self.recipes:SetPoint("BOTTOMRIGHT")

	local function refreshIfShown() if page:IsShown() then Prof:Refresh() end end
	SK:On("NAMES_LOADED", refreshIfShown)
	SK:On("CRAFT_INDEX_UPDATED", refreshIfShown)
	SK:On("FAVOURITES_CHANGED", refreshIfShown)
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
	if not VIEW_OK[view] then view = "board" end
	local one = self.skillLine ~= nil
	if one then view = "board" end
	self.views:SetActive(view)
	self.back:SetShown(one)
	self.heading:SetShown(one)
	self.board:SetShown(not one and view == "board")
	self.cooldowns:SetShown(not one and view == "cooldowns")
	self.search:SetShown(not one and view == "recipes")
	self.profMenu:SetShown(not one and view == "recipes")
	self.showMenu:SetShown(not one and view == "recipes")
	self.allList:SetShown(not one and view == "recipes")
	self.crafters:SetShown(one)
	self.right:SetShown(one)

	-- Reminder bar (shown even when chat reminders are off).
	local nudges = SK.Professions.CurrentNudges()
	local nudge = SK.Professions.NudgeText(nudges)
	self.nudge:SetText(nudge or "")
	local showNudge = nudge ~= nil and not one
	self.nudgeBar:SetShown(showNudge)
	if showNudge then
		local first = nudges[1]
		local open = self.nudgeBar.open
		open.skillLine, open.profName = first.skillLine, first.name
		open:SetText("Open " .. first.name)
		open:SetWidth(math.max(S.minHit * 2, (open.label:GetStringWidth() or 0) + SP.l * 2))
		open:SetShown(SK.Compat.CanShowProfession())
		open:SetDisabled(SK.Compat.InCombat())
		open.disabledTooltip = "Not in combat"
	end
	local shift = showNudge and (S.control + SP.s + SP.m) or 0
	local top = -(S.subTabs + SP.m) - shift
	self.board:SetPoint("TOPLEFT", 0, top)
	self.cooldowns:SetPoint("TOPLEFT", 0, top)
	self.search:SetPoint("TOPLEFT", 0, top)
	self.allList:SetPoint("TOPLEFT", 0, top - S.control - SP.m)

	if one then return self:RefreshOne(ctx) end
	if view == "recipes" then return self:RefreshAll(ctx) end
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
		self.status:SetText(Prof.BoardStatus(SK.Overview.Recipes(ctx.index), missing))
	end
end

-- The Guild view's line on the right (v0.6.0: the Overview's Recipes card
-- moved here). Pure; tested.
function Prof.BoardStatus(recipes, missing)
	local parts = {}
	if recipes.total > 0 then
		parts[#parts + 1] = Theme.Count(recipes.total, "recipe") .. " known"
		if recipes.single > 0 then parts[#parts + 1] = Theme.Paint("spark", recipes.single .. " by only one character") end
	else
		parts[#parts + 1] = "Recipes appear after crafters open their profession window once"
	end
	parts[#parts + 1] = missing > 0 and (Theme.Count(missing, "profession") .. " nobody has") or "every profession covered"
	return table.concat(parts, "  ·  ")
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
	self.filterChips[1]:SetPoint("TOPLEFT", 0, chipsY)
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

SK.MainFrame:AddTab("professions", "Professions", Prof, { group = "crafting",
	desc = "Who crafts what in the guild, every recipe in the game, and cooldowns." })
