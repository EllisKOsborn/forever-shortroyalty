-- A small Short Royalty panel beside Blizzard's profession window (v0.5.3):
-- your next route step, and for the recipe you pick there its colour,
-- where to learn it, who in the guild makes it (and, with Profit unlocked,
-- its cost and profit). Our own frame, positioned next to theirs: nothing
-- of Blizzard's is changed. /sr panel turns it on and off.
local _, SK = ...

local Panel = SK:NewModule("ProfPanel")
local Theme, W, Compat = SK.Theme, SK.Widgets, SK.Compat
local S, SP = Theme.SIZES, Theme.SPACE

Panel.WIDTH = 280

-- Pure: the panel's lines for a step and a recipe. Returns a list of
-- { text, role } where role is a Theme colour.
function Panel.Lines(o)
	local out = {}
	local function add(text, role) out[#out + 1] = { text, role or "text" } end
	add("Next on your route", "dim")
	if o.atCap then
		add("You're at your cap: learn the next rank from your trainer.", "text")
	elseif o.step and o.step.stuck then
		add("Nothing you know gives points at " .. o.step.from .. ": visit your trainer.", "spark")
	elseif o.step then
		add(o.step.from .. " - " .. o.step.to .. ": " .. o.step.crafts .. "x " .. (o.stepName or "...") ..
			(o.step.learn and " (learn it first)" or ""), "text")
		if o.total then add("All the way: about " .. o.total, "dim") end
	else
		add("Open this window once so Short Royalty knows your recipes.", "dim")
	end
	if o.recipeName then
		add(" ", "dim")
		add(o.recipeName, "gold")
		if o.skillUp then add(o.skillUp, "dim") end
		for _, l in ipairs(o.learn or {}) do add(l, "text") end
		if o.crafters then add(o.crafters, "text") end
		if o.profit then add(o.profit, "text") end
	end
	return out
end

function Panel:Build()
	if self.frame then return self.frame end
	local f = CreateFrame("Frame", "ShortRoyaltyProfPanel", UIParent)
	f:SetWidth(Panel.WIDTH)
	f:SetHeight(200)
	f:SetFrameStrata("HIGH")
	f:Hide()
	Theme.Panel(f, { bg = "void", border = "line" })
	local title = Theme.Text(f, "heading", "text")
	title:SetPoint("TOPLEFT", SP.m, -SP.m)
	title:SetText("Short Royalty")
	f.title = title
	local body = Theme.Text(f, "small", "text")
	body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -SP.s)
	body:SetPoint("RIGHT", -SP.m, 0)
	body:SetJustifyH("LEFT")
	body:SetJustifyV("TOP")
	body:SetWordWrap(true)
	f.body = body
	f.route = W.Button(f, "Route", nil, S.controlSmall, function()
		SK.DB.settings.profView = "route"
		SK.MainFrame:Show("professions")
		if SK.ProfessionsTab then SK.ProfessionsTab:Refresh() end
	end)
	f.route:SetPoint("BOTTOMLEFT", SP.m, SP.m)
	f.route.tooltip = "Open the whole route in Short Royalty"
	f.add = W.Button(f, "+ List", nil, S.controlSmall, function()
		if Panel.recipeID then SK.Shopping.Add(Panel.recipeID, Compat.ShiftDown() and 5 or 1) end
	end)
	f.add:SetPoint("LEFT", f.route, "RIGHT", SP.s, 0)
	f.add.tooltip = "Add one craft of the selected recipe to your shopping list (Shift: 5)"
	f.hide = W.Button(f, "Hide", nil, S.controlSmall, function()
		SK.DB.settings.profPanel = false
		f:Hide()
		SK:Print("Panel hidden. Type /sr panel to show it beside your profession window again.")
	end, "quiet")
	f.hide:SetPoint("BOTTOMRIGHT", -SP.m, SP.m)
	self.frame = f
	return f
end

function Panel.Enabled() return SK.DB.settings.profPanel ~= false end

local function stepName(step)
	if not step or not step.recipeID then return nil end
	local r = SK.RecipeDB.Get(step.recipeID)
	return SK.CraftIndex.NameOf({ recipeID = step.recipeID, itemID = r and r.itemID or 0 })
end

function Panel:Refresh()
	local f = self.frame
	if not f or not f:IsShown() then return end
	local skillLine = Compat.OpenProfession()
	if not skillLine then skillLine = SK.Professions.lastScan and SK.Professions.lastScan.skillLine end
	local o = {}
	local steps, total, _, from, to = SK.Route.ForProfession(skillLine)
	if steps then
		o.atCap = from >= to
		o.step = steps[1]
		o.stepName = stepName(o.step)
		o.total = total and total ~= 0 and SK.Prices.Money(total) or nil
	end
	local id = Panel.recipeID
	if id then
		local r = SK.RecipeDB.Get(id)
		o.recipeName = SK.CraftIndex.NameOf({ recipeID = id, itemID = r and r.itemID or 0 }) or ("Recipe " .. id)
		o.skillUp = W.SkillUpText(id, skillLine)
		o.learn = W.LearnLines(id, skillLine)
		local guild = SK.DBM:Guild()
		if guild then
			local list = SK.CraftIndex.Crafters(SK.CraftIndex:Get(true), id, guild, Compat.Now())
			if #list > 0 then
				local names = {}
				for i = 1, math.min(3, #list) do names[i] = list[i].name end
				o.crafters = "Guild: " .. Theme.Count(#list, "crafter") .. " (" .. table.concat(names, ", ") ..
					(#list > 3 and ", ..." or "") .. "), " .. SK.CraftIndex.OnlineCount(list) .. " online"
			else
				o.crafters = "Guild: nobody else makes it yet"
			end
		end
		if SK.ProfessionsTab and SK.ProfessionsTab.ProfitUnlocked() then
			local c = SK.Prices.Batch(SK.Prices.Recipe, id)
			if c.cost and c.value then
				o.profit = "Cost " .. SK.Prices.Money(c.cost) .. ", sells " .. SK.Prices.Money(c.value) ..
					", profit " .. SK.Prices.Money(c.profit)
			end
		end
	end
	local parts = {}
	for _, l in ipairs(Panel.Lines(o)) do parts[#parts + 1] = Theme.Paint(l[2], l[1]) end
	f.body:SetText(table.concat(parts, "\n"))
	f.add:SetDisabled(id == nil)
	local h = (f.body:GetStringHeight() or 120) + S.controlSmall + 4 * SP.m + 20
	f:SetHeight(math.max(140, math.min(h, 420)))
end

-- Beside Blizzard's profession window, your own professions only.
function Panel:Attach()
	if not Panel.Enabled() or not Compat.IsOwnTradeSkill() then return self:Detach() end
	local pf = Compat.ProfessionsFrame()
	if not pf then return end
	local f = self:Build()
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", pf, "TOPRIGHT", SP.xs, 0)
	f:Show()
	self:Refresh()
end

function Panel:Detach()
	if self.frame then self.frame:Hide() end
end

function Panel:OnInit()
	SK:RegisterEvent("TRADE_SKILL_SHOW", function() SK.After(0.2, function() Panel:Attach() end) end)
	SK:RegisterEvent("TRADE_SKILL_CLOSE", function() Panel:Detach() end)
	Compat.OnRecipeSelected(Panel, function(recipeID)
		Panel.recipeID = recipeID
		Panel:Refresh()
	end)
	local function refresh() Panel:Refresh() end
	for _, msg in ipairs({ "SELF_UPDATED", "SHOPPING_CHANGED", "PRICES_CHANGED", "LEARN_CHANGED", "NAMES_LOADED",
		"CRAFT_INDEX_UPDATED" }) do
		SK:On(msg, refresh)
	end
end

-- /sr panel
function Panel.Toggle()
	SK.DB.settings.profPanel = not Panel.Enabled()
	if Panel.Enabled() then
		SK:Print("Panel on: it shows beside your profession window.")
		if Compat.ProfessionsFrame() and Compat.ProfessionsFrame():IsShown() then Panel:Attach() end
	else
		Panel:Detach()
		SK:Print("Panel off. Type /sr panel to bring it back.")
	end
end
