-- Widgets: buttons, tabs, chips, check boxes, a menu, a search box, a
-- virtual (recycling) list with sortable columns, a scrollable text panel,
-- and "blocks" (a section heading with key/value rows). Only core widget
-- types are used (Frame, Button, Slider, EditBox, ScrollFrame,
-- CheckButton) and no Blizzard templates. Every colour, size and font comes
-- from UI/Theme.lua.
local _, SK = ...

local W = {}
SK.Widgets = W
local Theme, Motion = SK.Theme, SK.Motion
local S, SP = Theme.SIZES, Theme.SPACE

-- Small controls keep a comfortable click area: widen the hit box to at
-- least SIZES.minHit without changing how they look.
local function padHit(frame, w, h)
	local dy = math.max(0, (S.minHit - (h or 0)) / 2)
	local dx = math.max(0, (S.minHit - (w or S.minHit)) / 2)
	if (dx > 0 or dy > 0) and frame.SetHitRectInsets then frame:SetHitRectInsets(-dx, -dx, -dy, -dy) end
end
W.padHit = padHit

local function tooltipFor(self)
	local tip = self.disabled and self.disabledTooltip or (not self.disabled and self.tooltip)
	if tip then
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(tip, Theme.RGB("text"))
		GameTooltip:Show()
	end
end

---------------------------------------------------------------------------
-- Button. kind = "ghost" (default: outline), "primary" (accent, one per
-- screen at most) or "quiet" (text only, for "Open roster"-style links and
-- the Whisper links in lists).
---------------------------------------------------------------------------
local BUTTON_LOOK = {
	--             bg rest,   bg hover,    bg press,     border rest,  border hover, label,      label hover
	ghost   = { nil,        "raised",    "pressed",    "lineStrong", "dim",        "text",     "text" },
	primary = { "accent",   "accentLit", "accentDeep", nil,          nil,          "onAccent", "onAccent" },
	quiet   = { nil,        nil,         nil,          nil,          nil,          "dim",      "accent" },
}

function W.Button(parent, text, width, height, onClick, kind)
	kind = kind or "ghost"
	local look = BUTTON_LOOK[kind]
	local b = CreateFrame("Button", nil, parent)
	b.kind, b.disabled, b.active, b.hover = kind, false, false, false
	height = height or S.control
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	if look[4] then Theme.Border(b, look[4]) end
	b.label = Theme.Text(b, kind == "quiet" and "small" or "body", look[6])
	b.label:SetPoint("CENTER")
	b.label:SetJustifyH("CENTER")
	b.label:SetWordWrap(false)
	b.label:SetText(text)
	b:SetSize(width or math.max(S.minHit * 2, (b.label:GetStringWidth() or 0) + SP.l * 2), height)
	padHit(b, width, height)

	function b:Paint(state) -- "rest" | "hover" | "press"
		if self.disabled then
			if look[1] then Theme.Solid(self.bg, "raised") else self.bg:SetColorTexture(0, 0, 0, 0) end
			Theme.SetBorderColor(self, "line")
			self.label:SetTextColor(Theme.RGB("faint"))
			return
		end
		local bg = (state == "press" and look[3]) or (state == "hover" and look[2]) or look[1]
		if bg then Theme.Solid(self.bg, bg) else self.bg:SetColorTexture(0, 0, 0, 0) end
		if look[4] then Theme.SetBorderColor(self, (state ~= "rest" or self.active) and look[5] or look[4]) end
		self.label:SetTextColor(Theme.RGB((state ~= "rest" or self.active) and look[7] or look[6]))
	end
	b:SetScript("OnEnter", function(self)
		self.hover = true
		self:Paint("hover")
		tooltipFor(self)
	end)
	b:SetScript("OnLeave", function(self)
		self.hover = false
		self:Paint("rest")
		GameTooltip:Hide()
	end)
	-- Press feedback is instant: darker fill and the label drops a pixel.
	b:SetScript("OnMouseDown", function(self)
		if self.disabled then return end
		self:Paint("press")
		self.label:SetPoint("CENTER", 0, -1)
	end)
	b:SetScript("OnMouseUp", function(self)
		self.label:SetPoint("CENTER", 0, 0)
		self:Paint(self.hover and "hover" or "rest")
	end)
	if onClick then b:SetScript("OnClick", function(self, ...) if not self.disabled then onClick(self, ...) end end) end
	function b:SetText(t) self.label:SetText(t) end
	function b:SetDisabled(flag)
		self.disabled = flag and true or false
		self:Paint(self.hover and "hover" or "rest")
	end
	b:Paint("rest")
	return b
end

-- Close (X) button: a drawn cross, dim until hovered.
function W.CloseButton(parent, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(S.control, S.control)
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0)
	local x = b:CreateTexture(nil, "ARTWORK")
	x:SetSize(12, 12)
	x:SetPoint("CENTER")
	x:SetTexture(Theme.TEX.close)
	x:SetVertexColor(Theme.RGB("dim"))
	b:SetScript("OnEnter", function()
		Theme.Solid(bg, "raised")
		x:SetVertexColor(Theme.RGB("text"))
		GameTooltip:SetOwner(b, "ANCHOR_TOP")
		GameTooltip:SetText("Close (Esc)", Theme.RGB("text"))
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function()
		bg:SetColorTexture(0, 0, 0, 0)
		x:SetVertexColor(Theme.RGB("dim"))
		GameTooltip:Hide()
	end)
	b:SetScript("OnMouseDown", function() Theme.Solid(bg, "pressed") end)
	b:SetScript("OnMouseUp", function() Theme.Solid(bg, "raised") end)
	b:SetScript("OnClick", onClick)
	return b
end

---------------------------------------------------------------------------
-- Tab: a page's own tabs (Professions: Guild / Recipes / Cooldowns). Plain
-- text, dim until active; the accent underline is owned by W.SubTabs.
---------------------------------------------------------------------------
function W.Tab(parent, text, onClick)
	local t = CreateFrame("Button", nil, parent)
	t.label = Theme.Text(t, "tab", "dim")
	t.label:SetPoint("CENTER")
	t.label:SetText(text)
	t:SetSize((t.label:GetStringWidth() or 0) + SP.m * 2, S.subTabs)
	t:SetScript("OnEnter", function(self) if not self.active then self.label:SetTextColor(Theme.RGB("text")) end end)
	t:SetScript("OnLeave", function(self) if not self.active then self.label:SetTextColor(Theme.RGB("dim")) end end)
	-- Feedback the moment the button goes down, not when it's released.
	t:SetScript("OnMouseDown", function(self) self.label:SetPoint("CENTER", 0, -1) end)
	t:SetScript("OnMouseUp", function(self) self.label:SetPoint("CENTER", 0, 0) end)
	t:SetScript("OnClick", onClick)
	function t:SetActive(flag)
		self.active = flag
		self.label:SetTextColor(Theme.RGB(flag and "text" or "dim"))
	end
	return t
end

---------------------------------------------------------------------------
-- Chip: one of a small set of choices (filters). The picked chip is tinted
-- with the accent.
---------------------------------------------------------------------------
function W.Chip(parent, text, onClick)
	local c = CreateFrame("Button", nil, parent)
	c.active, c.hover = false, false
	c.bg = c:CreateTexture(nil, "BACKGROUND")
	c.bg:SetAllPoints()
	Theme.Border(c, "line")
	c.label = Theme.Text(c, "small", "dim")
	c.label:SetPoint("CENTER")
	c.label:SetText(text)
	c:SetSize((c.label:GetStringWidth() or 0) + SP.m * 2, S.controlSmall + 2)
	padHit(c, nil, S.controlSmall + 2)
	function c:Paint()
		if self.active then
			Theme.Solid(self.bg, "accent", Theme.ALPHA.selected)
			Theme.SetBorderColor(self, "accent")
			self.label:SetTextColor(Theme.RGB("text"))
		else
			self.bg:SetColorTexture(Theme.RGBA("raised", self.hover and 1 or 0))
			Theme.SetBorderColor(self, self.hover and "lineStrong" or "line")
			self.label:SetTextColor(Theme.RGB(self.hover and "text" or "dim"))
		end
	end
	c:SetScript("OnEnter", function(self) self.hover = true; self:Paint(); tooltipFor(self) end)
	c:SetScript("OnLeave", function(self) self.hover = false; self:Paint(); GameTooltip:Hide() end)
	c:SetScript("OnMouseDown", function(self) if not self.active then Theme.Solid(self.bg, "pressed") end end)
	c:SetScript("OnMouseUp", function(self) self:Paint() end)
	c:SetScript("OnClick", onClick)
	function c:SetActive(flag) self.active = flag; self:Paint() end
	c:Paint()
	return c
end

---------------------------------------------------------------------------
-- Check box with label. The whole label is clickable.
---------------------------------------------------------------------------
function W.Check(parent, label, getter, setter)
	local c = CreateFrame("CheckButton", nil, parent)
	c:SetSize(S.check, S.check)
	local box = c:CreateTexture(nil, "BACKGROUND")
	box:SetAllPoints()
	Theme.Solid(box, "surface")
	Theme.Border(c, "lineStrong")
	local tick = c:CreateTexture(nil, "ARTWORK")
	tick:SetPoint("TOPLEFT", 3, -3)
	tick:SetPoint("BOTTOMRIGHT", -3, 3)
	Theme.Solid(tick, "accent")
	c:SetCheckedTexture(tick)
	c.label = Theme.Text(c, "body", "text")
	c.label:SetPoint("LEFT", c, "RIGHT", SP.s, 0)
	c.label:SetWordWrap(false)
	function c:SetLabel(text)
		self.label:SetText(text)
		local w = (self.label:GetStringWidth() or 0) + SP.s
		if self.SetHitRectInsets then self:SetHitRectInsets(0, -w, -4, -4) end
	end
	c:SetLabel(label)
	c:SetScript("OnClick", function(self) setter(self:GetChecked() and true or false) end)
	c:SetScript("OnEnter", function(self) Theme.SetBorderColor(self, "dim"); tooltipFor(self) end)
	c:SetScript("OnLeave", function(self) Theme.SetBorderColor(self, "lineStrong"); GameTooltip:Hide() end)
	function c:Refresh() self:SetChecked(getter() and true or false) end
	c:Refresh()
	return c
end

---------------------------------------------------------------------------
-- Menu: a button that opens a small pop-up list. opts = {
--   width = 150, items = function() return { {value=, text=}, ... } end,
--   get = function() return value end, set = function(value) end,
-- }
---------------------------------------------------------------------------
local openMenu
W.MENU_ROWS = 12 -- rows a menu shows before it scrolls

function W.Menu(parent, opts)
	local width = opts.width or 150
	local b = W.Button(parent, "", width, S.control)
	local arrow = b:CreateTexture(nil, "ARTWORK")
	arrow:SetSize(8, 8)
	arrow:SetPoint("RIGHT", -SP.s, 0)
	arrow:SetTexture(Theme.TEX.arrow)
	arrow:SetTexCoord(0, 1, 1, 0) -- point down
	arrow:SetVertexColor(Theme.RGB("dim"))
	b.label:ClearAllPoints()
	b.label:SetPoint("LEFT", SP.s, 0)
	b.label:SetPoint("RIGHT", -SP.l - SP.xs, 0)
	b.label:SetJustifyH("LEFT")

	local pop = CreateFrame("Frame", nil, b)
	pop:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -SP.xxs)
	pop:SetWidth(width)
	pop:SetFrameStrata("FULLSCREEN_DIALOG")
	pop:EnableMouse(true)
	Theme.Panel(pop, { bg = "surface", border = "lineStrong" })
	pop:Hide()
	pop.entries = {}
	b.pop = pop

	function b:Refresh()
		local current = opts.get()
		for _, it in ipairs(opts.items()) do
			if it.value == current then self:SetText(it.text) return end
		end
		self:SetText("")
	end

	-- Pick a value as if it had been clicked (tests, and code that sets a menu).
	function b:Choose(value)
		opts.set(value)
		self:Refresh()
	end
	function b:Close()
		pop:Hide()
		if openMenu == self then openMenu = nil end
	end

	-- Long lists show MENU_ROWS at a time and scroll with the mouse wheel.
	pop.offset = 0
	local function draw()
		local items = opts.items()
		local current = opts.get()
		local h = S.row
		local shown = math.min(#items, W.MENU_ROWS)
		pop.offset = math.max(0, math.min(pop.offset, #items - shown))
		for i = 1, shown do
			local it = items[pop.offset + i]
			local e = pop.entries[i]
			if not e then
				e = CreateFrame("Button", nil, pop)
				e:SetHeight(h)
				e:SetPoint("TOPLEFT", 1, -1 - (i - 1) * h)
				e:SetPoint("TOPRIGHT", -1, -1 - (i - 1) * h)
				-- Behind the text: the HIGHLIGHT layer draws over it and hid the hovered row.
				e.hl = e:CreateTexture(nil, "BACKGROUND")
				e.hl:SetAllPoints()
				Theme.Solid(e.hl, "raised")
				e.hl:Hide()
				e:SetScript("OnEnter", function(self) self.hl:Show() end)
				e:SetScript("OnLeave", function(self) self.hl:Hide() end)
				e.text = Theme.Text(e, "body", "text")
				e.text:SetPoint("LEFT", SP.s, 0)
				e.text:SetPoint("RIGHT", -SP.s, 0)
				e.text:SetJustifyH("LEFT")
				e.text:SetWordWrap(false)
				e:SetScript("OnClick", function(self)
					b:Close()
					opts.set(self.value)
					b:Refresh()
				end)
				pop.entries[i] = e
			end
			e.value = it.value
			e.text:SetText(it.text)
			e.text:SetTextColor(Theme.RGB(it.value == current and "accent" or "text"))
			e:Show()
		end
		for i = shown + 1, #pop.entries do pop.entries[i]:Hide() end
		pop:SetHeight(shown * h + 2)
		pop.more = #items > shown
	end
	pop:EnableMouseWheel(true)
	pop:SetScript("OnMouseWheel", function(_, delta)
		pop.offset = pop.offset - delta * 3
		draw()
	end)

	function b:Open()
		if openMenu and openMenu ~= self then openMenu:Close() end
		pop.offset = 0
		draw()
		Motion.In(pop, Theme.MOTION.menu, 0.96, "TOP")
		openMenu = self
	end

	b:SetScript("OnClick", function(self)
		if pop:IsShown() then self:Close() else self:Open() end
	end)
	b:SetScript("OnHide", function(self) self:Close() end)
	b:Refresh()
	return b
end

---------------------------------------------------------------------------
-- Skill-up lines for a recipe tooltip (v0.4.4): the range from Forever's data
-- and, if you have the profession, its colour for you now.
---------------------------------------------------------------------------
function W.SkillUpText(recipeID, skillLine)
	local DB = SK.RecipeDB
	local range = DB and DB.Range(recipeID)
	if not range then return nil end
	local text = "Yellow · green · grey at " .. Theme.SkillRange(range)
	local skill = DB.MySkill(skillLine)
	if skill and DB.IKnow(recipeID, skillLine) then
		local colour = DB.ColourAt(recipeID, skill)
		text = text .. Theme.Paint("dim", "  ·  for you (" .. skill .. "): ") .. Theme.SkillColour(colour)
	end
	return text
end

-- Where to learn it (v0.5.0), unless you know it already.
function W.LearnLines(recipeID, skillLine)
	local DB = SK.RecipeDB
	if not SK.Learn or not DB or DB.IKnow(recipeID, skillLine) then return {} end
	local profName = SK.ProfBoard and SK.ProfBoard.ProfessionName({}, skillLine) or nil
	return SK.Learn.Lines(SK.Learn.Info(recipeID), {
		profName = profName,
		itemName = SK.CraftIndex.ItemName,
		money = SK.Money,
	})
end

function W.SkillUpTip(tt, recipeID, skillLine)
	local text = W.SkillUpText(recipeID, skillLine)
	if text then Theme.TipLine(tt, text, "dim", true) end
	for _, line in ipairs(W.LearnLines(recipeID, skillLine)) do Theme.TipLine(tt, line, "text", true) end
end

---------------------------------------------------------------------------
-- Search box (with a clear button once something is typed)
---------------------------------------------------------------------------
function W.SearchBox(parent, width, placeholder, onChange)
	local e = CreateFrame("EditBox", nil, parent)
	e:SetSize(width, S.control)
	e:SetAutoFocus(false)
	e:SetMaxLetters(60)
	e:SetTextInsets(SP.s, S.control, 0, 0)
	Theme.Font(e, "body", "text")
	local bg = e:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	Theme.Solid(bg, "surface")
	Theme.Border(e, "lineStrong")
	local hint = Theme.Text(e, "body", "dim")
	hint:SetPoint("LEFT", SP.s, 0)
	hint:SetPoint("RIGHT", -S.control, 0)
	hint:SetWordWrap(false)
	hint:SetText(placeholder)
	local clear = CreateFrame("Button", nil, e)
	clear:SetSize(S.control, S.control)
	clear:SetPoint("RIGHT")
	local x = clear:CreateTexture(nil, "ARTWORK")
	x:SetSize(10, 10)
	x:SetPoint("CENTER")
	x:SetTexture(Theme.TEX.close)
	x:SetVertexColor(Theme.RGB("dim"))
	clear:SetScript("OnEnter", function() x:SetVertexColor(Theme.RGB("text")) end)
	clear:SetScript("OnLeave", function() x:SetVertexColor(Theme.RGB("dim")) end)
	clear:SetScript("OnClick", function() e:SetText(""); e:ClearFocus() end)
	clear:Hide()
	e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	e:SetScript("OnEditFocusGained", function(self) Theme.SetBorderColor(self, "accent") end)
	e:SetScript("OnEditFocusLost", function(self) Theme.SetBorderColor(self, "lineStrong") end)
	e:SetScript("OnTextChanged", function(self)
		local text = self:GetText() or ""
		hint:SetShown(text == "")
		clear:SetShown(text ~= "")
		onChange(text)
	end)
	return e
end

---------------------------------------------------------------------------
-- Vertical scroll bar (core Slider) shared by List, TextPanel and Sheet.
-- A thin thumb, a wider hit area.
---------------------------------------------------------------------------
local function ScrollBar(parent, onValue)
	local s = CreateFrame("Slider", nil, parent)
	s:SetOrientation("VERTICAL")
	s:SetWidth(SP.m)
	s:SetMinMaxValues(0, 0)
	s:SetValueStep(1)
	if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
	s:SetThumbTexture(Theme.TEX.white)
	local thumb = s:GetThumbTexture()
	thumb:SetSize(S.scrollbar, S.minHit)
	thumb:SetVertexColor(Theme.RGB("lineStrong"))
	s:SetScript("OnEnter", function() thumb:SetVertexColor(Theme.RGB("dim")) end)
	s:SetScript("OnLeave", function() thumb:SetVertexColor(Theme.RGB("lineStrong")) end)
	s:SetScript("OnValueChanged", function(_, v) onValue(math.floor(v + 0.5)) end)
	return s
end

---------------------------------------------------------------------------
-- List: virtual rows + sortable header, with empty and loading states.
-- opts = {
--   columns = { { key=, title=, width=, align="LEFT", sort=function(a,b) } },
--   rowHeight = SIZES.row,
--   setCell = function(fontString, item, column) end,  -- fill a cell
--   onClick = function(item, button) end,
--   onEnter = function(row, item) end,                  -- optional tooltip
--   decorate = function(row) end,                       -- optional: add widgets to a new row
--                                                       -- (put them in row.widgets so empty rows hide them)
--   update = function(row, item) end,                   -- optional: after a row is filled
--   header = false,                                     -- optional: no header row
-- }
---------------------------------------------------------------------------
function W.List(parent, opts)
	local list = CreateFrame("Frame", nil, parent)
	list.opts = opts
	list.items, list.offset, list.customSort = {}, 0, false
	local rowH = opts.rowHeight or S.row
	local headH = opts.header == false and 0 or S.header

	-- header: dim sentence-case labels, one rule under it, a sort arrow on
	-- the active column only.
	local header = CreateFrame("Frame", nil, list)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT", -SP.m, 0)
	header:SetHeight(math.max(headH, 1))
	header:SetShown(headH > 0)
	local rule = Theme.Rule(header, "line")
	rule:SetPoint("BOTTOMLEFT")
	rule:SetPoint("BOTTOMRIGHT")
	list.header = header
	local x = 0
	list.headerButtons = {}
	for i, col in ipairs(opts.columns) do
		local hb = CreateFrame("Button", nil, header)
		hb:SetPoint("LEFT", x, 0)
		hb:SetSize(col.width, headH)
		hb.text = Theme.Text(hb, "small", "dim")
		local right = col.align == "RIGHT"
		hb.text:SetPoint(right and "RIGHT" or "LEFT", right and -SP.s or SP.s, 0)
		hb.text:SetText(col.title)
		hb.arrow = hb:CreateTexture(nil, "ARTWORK")
		hb.arrow:SetSize(8, 8)
		hb.arrow:SetTexture(Theme.TEX.arrow)
		hb.arrow:SetVertexColor(Theme.RGB("text"))
		if right then hb.arrow:SetPoint("RIGHT", hb.text, "LEFT", -SP.xs, 0)
		else hb.arrow:SetPoint("LEFT", hb.text, "RIGHT", SP.xs, 0) end
		hb.arrow:Hide()
		if col.sort then
			hb:SetScript("OnClick", function()
				list.customSort = false
				if list.sortCol == i then list.sortDesc = not list.sortDesc else list.sortCol, list.sortDesc = i, false end
				list:Sort()
			end)
			hb:SetScript("OnEnter", function(self) self.text:SetTextColor(Theme.RGB("text")) end)
			hb:SetScript("OnLeave", function(self)
				self.text:SetTextColor(Theme.RGB(list.sortCol == i and "text" or "dim"))
			end)
		end
		list.headerButtons[i] = hb
		x = x + col.width
	end

	-- scroll bar
	local bar = ScrollBar(list, function(v) list.offset = v; list:Draw() end)
	bar:SetPoint("TOPRIGHT", 0, -headH)
	bar:SetPoint("BOTTOMRIGHT")
	list.bar = bar

	-- empty / error sentence: keeps the header and frame, one line of help.
	list.message = Theme.Text(list, "body", "dim")
	list.message:SetPoint("TOPLEFT", SP.s, -headH - SP.m)
	list.message:SetPoint("RIGHT", -SP.l, 0)
	list.message:SetJustifyV("TOP")
	list.message:Hide()

	list.rows = {}
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(_, delta)
		bar:SetValue(math.max(0, list.offset - delta * 3))
	end)

	function list:RowCount()
		return math.max(1, math.floor((self:GetHeight() - headH) / rowH))
	end

	function list:EnsureRows()
		local need = self:RowCount()
		for i = #self.rows + 1, need do
			local row = CreateFrame("Button", nil, self)
			row:SetHeight(rowH)
			row:SetPoint("TOPLEFT", 0, -headH - (i - 1) * rowH)
			row:SetPoint("TOPRIGHT", -SP.m, -headH - (i - 1) * rowH)
			row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			local ruleRow = Theme.Rule(row, "rule", "BACKGROUND")
			ruleRow:SetPoint("BOTTOMLEFT")
			ruleRow:SetPoint("BOTTOMRIGHT")
			row.sel = row:CreateTexture(nil, "BACKGROUND", nil, 1)
			row.sel:SetAllPoints()
			Theme.Solid(row.sel, "accent", Theme.ALPHA.selected)
			row.sel:Hide()
			row.hl = row:CreateTexture(nil, "BACKGROUND", nil, 2)
			row.hl:SetAllPoints()
			Theme.Solid(row.hl, "raised")
			row.hl:Hide()
			-- loading placeholder: a flat bar at the size of the text
			row.skeleton = row:CreateTexture(nil, "ARTWORK")
			row.skeleton:SetPoint("LEFT", SP.s, 0)
			row.skeleton:SetSize(120 + (i * 37) % 90, 8)
			Theme.Solid(row.skeleton, "raised")
			row.skeleton:Hide()
			row.cells = {}
			row.widgets = {}
			local cx = 0
			for c, col in ipairs(opts.columns) do
				local fs = Theme.Text(row, "body", "text")
				fs:SetWidth(col.width - SP.s * 2)
				fs:SetJustifyH(col.align or "LEFT")
				fs:SetWordWrap(false)
				fs:SetPoint("LEFT", cx + SP.s, 0)
				row.cells[c] = fs
				cx = cx + col.width
			end
			row:SetScript("OnClick", function(self, button)
				if self.item and opts.onClick then opts.onClick(self.item, button) end
			end)
			row:SetScript("OnEnter", function(self)
				if not self.item then return end
				if opts.onClick then Motion.HoverIn(self.hl) end
				W.tipRow = self
				if opts.onEnter then opts.onEnter(self, self.item) end
			end)
			row:SetScript("OnLeave", function(self)
				Motion.HoverOut(self.hl)
				if W.tipRow == self then W.tipRow = nil end
				GameTooltip:Hide()
			end)
			if opts.decorate then opts.decorate(row) end
			self.rows[i] = row
		end
	end

	-- Sort by something that isn't a column (v0.6.0: "oldest data first"
	-- without a Data column). A header click goes back to column sorting.
	function list:SortWith(fn)
		self.customSort, self.sortCol = fn, false
		self:Sort()
	end

	function list:Sort()
		local col = self.sortCol and opts.columns[self.sortCol]
		if self.customSort and not col then
			table.sort(self.items, self.customSort)
		elseif col and col.sort then
			local desc = self.sortDesc
			table.sort(self.items, function(a, b)
				if desc then return col.sort(b, a) end
				return col.sort(a, b)
			end)
		end
		for i, hb in ipairs(self.headerButtons) do
			local on = i == self.sortCol and opts.columns[i].sort ~= nil
			hb.arrow:SetShown(on)
			hb.text:SetTextColor(Theme.RGB(on and "text" or "dim"))
			if on then
				if self.sortDesc then hb.arrow:SetTexCoord(0, 1, 1, 0) else hb.arrow:SetTexCoord(0, 1, 0, 1) end
			end
		end
		self:Draw()
	end

	-- Optional: isSelected(item) -> bool marks rows with a steady tint.
	function list:SetSelected(isSelected)
		self.isSelected = isSelected
		self:Draw()
	end

	-- Text shown when there are no items (nil = nothing).
	function list:SetEmptyText(text)
		self.emptyText = text
		self:Draw()
	end

	-- Loading: placeholder bars instead of rows until data arrives.
	function list:SetLoading(flag)
		self.loading = flag and true or false
		self:Draw()
	end

	function list:SetItems(items)
		self.items = items
		self:Sort()
	end

	function list:Draw()
		self:EnsureRows()
		local visible = self:RowCount()
		local maxOffset = math.max(0, #self.items - visible)
		if self.offset > maxOffset then self.offset = maxOffset end
		bar:SetMinMaxValues(0, maxOffset)
		bar:SetShown(maxOffset > 0)
		local loading = self.loading and #self.items == 0
		for i, row in ipairs(self.rows) do
			local item = (i <= visible) and self.items[self.offset + i] or nil
			row.item = item
			row.skeleton:SetShown(loading and i <= math.min(visible, 6))
			if item then
				for c, col in ipairs(opts.columns) do opts.setCell(row.cells[c], item, col) end
				if opts.update then opts.update(row, item) end
				row.sel:SetShown(self.isSelected ~= nil and self.isSelected(item) and true or false)
				for _, fs in ipairs(row.cells) do fs:Show() end
				row:Show()
			else
				for _, fs in ipairs(row.cells) do fs:Hide() end
				row.sel:Hide()
				row.hl:Hide()
				row:SetShown(loading and i <= 6)
				for _, w in ipairs(row.widgets) do w:Hide() end
			end
		end
		local empty = #self.items == 0 and not loading and self.emptyText
		self.message:SetText(empty or "")
		self.message:SetShown(empty and true or false)
	end

	list:SetScript("OnSizeChanged", function(self) self:Draw() end)
	return list
end

---------------------------------------------------------------------------
-- TextPanel: a scrollable block of rich text (|c colours, |T icons).
---------------------------------------------------------------------------
function W.TextPanel(parent)
	local panel = CreateFrame("ScrollFrame", nil, parent)
	local child = CreateFrame("Frame", nil, panel)
	child:SetSize(10, 10)
	panel:SetScrollChild(child)
	local fs = Theme.Text(child, "body", "text")
	fs:SetPoint("TOPLEFT")
	fs:SetJustifyV("TOP")
	fs:SetSpacing(3)
	panel.fs = fs
	local bar = ScrollBar(panel, function(v) panel:SetVerticalScroll(v) end)
	bar:SetPoint("TOPRIGHT", SP.m, 0)
	bar:SetPoint("BOTTOMRIGHT", SP.m, 0)
	panel:EnableMouseWheel(true)
	panel:SetScript("OnMouseWheel", function(self, delta)
		local _, max = bar:GetMinMaxValues()
		bar:SetValue(math.min(max, math.max(0, self:GetVerticalScroll() - delta * 30)))
	end)
	function panel:SetText(text)
		local w = self:GetWidth()
		child:SetWidth(w)
		fs:SetWidth(w)
		fs:SetText(text)
		local h = fs:GetStringHeight() + SP.s
		child:SetHeight(h)
		local max = math.max(0, h - self:GetHeight())
		bar:SetMinMaxValues(0, max)
		bar:SetShown(max > 0)
		bar:SetValue(0)
	end
	return panel
end

---------------------------------------------------------------------------
-- Block: a section with an uppercase heading, an optional quiet action on
-- the right, a rule, and rows. Rows (all optional fields):
--   { label=, value=, tone=, labelTone=, indent=true, tip= }  key / value
--   { text=, tone= }                                         a sentence (wraps)
--   { sub= }                                                  a small sub-heading
--   { figure=, caption=, tone= }                              the one big number
--   { gap=true }                                              half a row of space
-- Values are right-aligned on one edge; labels are cut with "..." if a
-- value needs the room.
---------------------------------------------------------------------------
local ROW_TONE = { label = "dim", value = "text" }

function W.Block(parent, width, title, action)
	local b = CreateFrame("Frame", nil, parent)
	b:SetWidth(width)
	b.width = width
	b.heading = Theme.Text(b, "label", "dim")
	b.heading:SetPoint("TOPLEFT", 0, 0)
	b.heading:SetText((title or ""):upper())
	b.headH = title and (S.control) or 0
	b.heading:SetShown(title ~= nil)
	if title then
		b.heading:ClearAllPoints()
		b.heading:SetPoint("LEFT", b, "TOPLEFT", 0, -S.control / 2)
		local rule = Theme.Rule(b, "line")
		rule:SetPoint("TOPLEFT", 0, -S.control)
		rule:SetPoint("TOPRIGHT", 0, -S.control)
		b.headH = S.control + SP.s
	end
	if action then
		b.button = W.Button(b, action.text, nil, S.controlSmall, action.onClick, "quiet")
		b.button:SetPoint("RIGHT", b, "TOPRIGHT", 0, -S.control / 2)
		b.button.tooltip = action.tooltip
	end
	b.pool = {}

	local function cell(i)
		local r = b.pool[i]
		if not r then
			r = {
				label = Theme.Text(b, "body", "dim"),
				value = Theme.Text(b, "body", "text"),
				text = Theme.Text(b, "small", "dim"),
				figure = Theme.Text(b, "figure", "accent"),
				-- hover area for rows with a tooltip (row.tip = function(tooltip))
				hit = CreateFrame("Frame", nil, b),
			}
			r.hit:EnableMouse(true)
			r.hit:SetScript("OnEnter", function(self)
				if not self.tip then return end
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				self.tip(GameTooltip)
				GameTooltip:Show()
			end)
			r.hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
			r.hit.tip = nil
			r.label:SetWordWrap(false)
			r.value:SetJustifyH("RIGHT")
			r.value:SetWordWrap(false)
			r.text:SetJustifyV("TOP")
			r.text:SetSpacing(2)
			b.pool[i] = r
		end
		for _, fs in pairs(r) do fs:Hide(); fs:ClearAllPoints() end
		return r
	end

	-- Lay out rows; sets and returns the block's height.
	function b:SetRows(rows)
		self.rows = rows
		local y = self.headH
		for i, row in ipairs(rows) do
			local r = cell(i)
			local top = y
			if row.gap then
				y = y + S.specRow / 2
			elseif row.figure then
				r.figure:SetPoint("TOPLEFT", 0, -y)
				r.figure:SetText(row.figure)
				r.figure:SetTextColor(Theme.RGB(row.tone or "accent"))
				r.figure:Show()
				if row.caption then
					r.label:SetPoint("BOTTOMLEFT", r.figure, "BOTTOMRIGHT", SP.s, 3)
					r.label:SetPoint("RIGHT", self, "RIGHT", 0, 0)
					Theme.Font(r.label, "small", "dim")
					r.label:SetText(row.caption)
					r.label:Show()
				end
				y = y + Theme.SIZE.figure + SP.s
			elseif row.text or row.sub then
				Theme.Font(r.text, row.sub and "small" or "small", row.tone or "dim")
				r.text:SetPoint("TOPLEFT", row.indent and SP.m or 0, -y - (row.sub and SP.xs or 0))
				r.text:SetWidth(self.width - (row.indent and SP.m or 0))
				r.text:SetText(row.sub or row.text)
				r.text:Show()
				local h = r.text:GetStringHeight() or 0
				y = y + math.max(S.specRow, h + SP.xs) + (row.sub and SP.xs or 0)
			else
				local x = row.indent and SP.m or 0
				Theme.Font(r.value, "body", row.tone or ROW_TONE.value)
				r.value:SetPoint("TOPRIGHT", 0, -y)
				r.value:SetText(row.value or Theme.DASH)
				r.value:Show()
				Theme.Font(r.label, "body", row.labelTone or ROW_TONE.label)
				r.label:SetPoint("TOPLEFT", x, -y)
				r.label:SetPoint("RIGHT", r.value, "LEFT", -SP.s, 0)
				r.label:SetText(row.label or "")
				r.label:Show()
				y = y + S.specRow
			end
			r.hit.tip = row.tip
			if row.tip then
				r.hit:SetPoint("TOPLEFT", 0, -top)
				r.hit:SetPoint("TOPRIGHT", 0, -top)
				r.hit:SetHeight(math.max(1, y - top))
				r.hit:Show()
			end
		end
		for i = #rows + 1, #self.pool do cell(i) end
		self:SetHeight(math.max(1, y))
		return y
	end
	return b
end

-- Plain text of block sections, for Copy and tests:
-- { { title=, rows={...} }, ... } -> "TITLE\n  label  value\n..."
function W.SheetText(sections)
	local L = {}
	for _, s in ipairs(sections) do
		if #L > 0 then L[#L + 1] = "" end
		if s.title then L[#L + 1] = s.title:upper() end
		for _, row in ipairs(s.rows or {}) do
			if row.figure then
				L[#L + 1] = "  " .. row.figure .. (row.caption and (" " .. row.caption) or "")
			elseif row.text or row.sub then
				L[#L + 1] = "  " .. (row.sub or row.text)
			elseif not row.gap then
				local value = row.value and Theme.Paint(row.tone, row.value) or "-"
				L[#L + 1] = "  " .. (row.indent and "  " or "") .. (row.label or "") .. "  " .. value
			end
		end
	end
	return table.concat(L, "\n")
end

---------------------------------------------------------------------------
-- Sheet: a scrolling column of Blocks. sheet:SetSections({ {title=, rows=}, ... })
---------------------------------------------------------------------------
function W.Sheet(parent, width)
	local sheet = CreateFrame("ScrollFrame", nil, parent)
	local child = CreateFrame("Frame", nil, sheet)
	child:SetSize(width, 10)
	sheet:SetScrollChild(child)
	sheet.blocks = {}
	local bar = ScrollBar(sheet, function(v) sheet:SetVerticalScroll(v) end)
	bar:SetPoint("TOPRIGHT", SP.m, 0)
	bar:SetPoint("BOTTOMRIGHT", SP.m, 0)
	sheet:EnableMouseWheel(true)
	sheet:SetScript("OnMouseWheel", function(self, delta)
		local _, max = bar:GetMinMaxValues()
		bar:SetValue(math.min(max, math.max(0, self:GetVerticalScroll() - delta * 30)))
	end)
	function sheet:SetSections(sections)
		self.sections = sections
		local y = 0
		for i, s in ipairs(sections) do
			local blk = self.blocks[i]
			if not blk or blk.title ~= s.title then
				if blk then blk:Hide() end
				blk = W.Block(child, width, s.title)
				blk.title = s.title
				self.blocks[i] = blk
			end
			blk:ClearAllPoints()
			blk:SetPoint("TOPLEFT", 0, -y)
			blk:Show()
			y = y + blk:SetRows(s.rows or {}) + SP.xl
		end
		for i = #sections + 1, #self.blocks do self.blocks[i]:Hide() end
		child:SetHeight(math.max(1, y))
		local max = math.max(0, y - self:GetHeight())
		bar:SetMinMaxValues(0, max)
		bar:SetShown(max > 0)
		bar:SetValue(0)
		self:SetVerticalScroll(0)
	end
	return sheet
end

---------------------------------------------------------------------------
-- v0.6.0 widgets: sidebar items, page tabs, switches, a slider, colour
-- swatches, an options menu, cards (a label over a flat panel of rows),
-- the number strip, and setting rows. Same rules as above: core frame
-- types only, every value from UI/Theme.lua.
---------------------------------------------------------------------------

-- Sidebar item: icon + label; the active one gets the raised fill, an
-- accent bar on its left edge and an accent icon.
function W.NavItem(parent, width, icon, text, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width, S.navRow)
	b.active, b.hover = false, false
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	b.mark = b:CreateTexture(nil, "ARTWORK")
	b.mark:SetPoint("TOPLEFT")
	b.mark:SetPoint("BOTTOMLEFT")
	b.mark:SetWidth(S.underline)
	Theme.Solid(b.mark, "accent")
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(16, 16)
	b.icon:SetPoint("LEFT", SP.l, 0)
	b.icon:SetTexture(icon)
	b.label = Theme.Text(b, "tab", "dim")
	b.label:SetPoint("LEFT", b.icon, "RIGHT", SP.s + SP.xxs, 0)
	b.label:SetPoint("RIGHT", -SP.s, 0)
	b.label:SetWordWrap(false)
	b.label:SetText(text)
	function b:Paint()
		if self.active then
			Theme.Solid(self.bg, "raised")
		elseif self.hover then
			Theme.Solid(self.bg, "raised", 0.5)
		else
			self.bg:SetColorTexture(0, 0, 0, 0)
		end
		self.mark:SetShown(self.active)
		Theme.Tint(self.icon, self.active and "accent" or (self.hover and "text" or "dim"))
		self.label:SetTextColor(Theme.RGB((self.active or self.hover) and "text" or "dim"))
	end
	b:SetScript("OnEnter", function(self) self.hover = true; self:Paint(); tooltipFor(self) end)
	b:SetScript("OnLeave", function(self) self.hover = false; self:Paint(); GameTooltip:Hide() end)
	b:SetScript("OnMouseDown", function(self) self.label:SetPoint("LEFT", self.icon, "RIGHT", SP.s + SP.xxs, -1) end)
	b:SetScript("OnMouseUp", function(self) self.label:SetPoint("LEFT", self.icon, "RIGHT", SP.s + SP.xxs, 0) end)
	b:SetScript("OnClick", onClick)
	function b:SetActive(flag) self.active = flag and true or false; self:Paint() end
	b:Paint()
	return b
end

-- Page tabs: a row of W.Tab with one accent underline and a rule under the
-- row. items = { { key, text }, ... }; onPick(key). bar:SetActive(key).
function W.SubTabs(parent, items, onPick)
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetHeight(S.subTabs)
	local rule = Theme.Rule(bar, "line")
	rule:SetPoint("BOTTOMLEFT")
	rule:SetPoint("BOTTOMRIGHT")
	bar.tabs = {}
	local prev
	for _, it in ipairs(items) do
		local t = W.Tab(bar, it[2], function() onPick(it[1]) end)
		t.key = it[1]
		-- The first label lines up with the content edge.
		if prev then t:SetPoint("LEFT", prev, "RIGHT", 0, 0) else t:SetPoint("LEFT", -SP.m, 0) end
		bar.tabs[#bar.tabs + 1] = t
		prev = t
	end
	local u = bar:CreateTexture(nil, "OVERLAY")
	u:SetHeight(S.underline)
	Theme.Solid(u, "accent")
	u:Hide()
	bar.underline = u
	function bar:SetActive(key)
		for _, t in ipairs(self.tabs) do
			local on = t.key == key
			t:SetActive(on)
			if on then
				u:ClearAllPoints()
				u:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", SP.m, 0)
				u:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -SP.m, 0)
				u:Show()
			end
		end
		self.active = key
	end
	return bar
end

-- On/off switch. getter() -> bool, setter(bool).
function W.Switch(parent, getter, setter)
	local w, h = S.switch[1], S.switch[2]
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w, h)
	padHit(b, w, h)
	b.track = b:CreateTexture(nil, "BACKGROUND")
	b.track:SetAllPoints()
	b.track:SetTexture(Theme.TEX.pill)
	b.track:SetTexCoord(0, 1, 0.25, 0.75)
	b.knob = b:CreateTexture(nil, "ARTWORK")
	b.knob:SetSize(h - 4, h - 4)
	b.knob:SetTexture(Theme.TEX.dot)
	b.disabled, b.hover, b.on = false, false, false
	function b:Refresh()
		local on = getter() and true or false
		self.on = on
		self.knob:ClearAllPoints()
		self.knob:SetPoint(on and "RIGHT" or "LEFT", on and -2 or 2, 0)
		if self.disabled then
			Theme.Tint(self.track, "raised")
			Theme.Tint(self.knob, "faint")
		else
			Theme.Tint(self.track, on and "accent" or (self.hover and "lineStrong" or "line"))
			Theme.Tint(self.knob, on and "onAccent" or "dim")
		end
	end
	b:SetScript("OnClick", function(self)
		if self.disabled then return end
		setter(not getter())
		self:Refresh()
	end)
	b:SetScript("OnEnter", function(self) self.hover = true; self:Refresh(); tooltipFor(self) end)
	b:SetScript("OnLeave", function(self) self.hover = false; self:Refresh(); GameTooltip:Hide() end)
	function b:SetDisabled(flag) self.disabled = flag and true or false; self:Refresh() end
	b:Refresh()
	return b
end

-- Horizontal slider with its value on the right. opts = { width, min,
-- max, step, get, set, format = function(v) -> text }. The value is set
-- when the mouse is released (a window resize on every pixel is jumpy).
function W.Slider(parent, opts)
	local f = CreateFrame("Frame", nil, parent)
	local valueW = 44
	f:SetSize(opts.width + SP.s + valueW, S.control)
	local s = CreateFrame("Slider", nil, f)
	s:SetOrientation("HORIZONTAL")
	s:SetPoint("LEFT")
	s:SetSize(opts.width, S.control)
	s:SetMinMaxValues(opts.min, opts.max)
	s:SetValueStep(opts.step)
	if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
	local track = s:CreateTexture(nil, "BACKGROUND")
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	track:SetHeight(3)
	Theme.Solid(track, "lineStrong")
	local fill = s:CreateTexture(nil, "ARTWORK")
	fill:SetPoint("LEFT")
	fill:SetHeight(3)
	Theme.Solid(fill, "accent")
	s:SetThumbTexture(Theme.TEX.dot)
	local thumb = s:GetThumbTexture()
	thumb:SetSize(12, 12)
	Theme.Tint(thumb, "accent")
	f.value = Theme.Text(f, "body", "text")
	f.value:SetPoint("RIGHT")
	f.value:SetWidth(valueW)
	f.value:SetJustifyH("RIGHT")
	local function show(v)
		f.value:SetText(opts.format and opts.format(v) or tostring(v))
		local k = (v - opts.min) / math.max(0.0001, opts.max - opts.min)
		fill:SetWidth(math.max(1, k * opts.width))
	end
	f.pending = false
	s:SetScript("OnValueChanged", function(_, v)
		v = math.floor(v / opts.step + 0.5) * opts.step
		f.pending = v
		show(v)
	end)
	s:SetScript("OnMouseUp", function()
		if f.pending then opts.set(f.pending); f.pending = false end
	end)
	f.slider = s
	function f:Refresh()
		local v = opts.get()
		s:SetValue(v)
		f.pending = false
		show(v)
	end
	-- Set a value as if dragged and released (tests, keyboard).
	function f:Choose(v) s:SetValue(v); opts.set(v); show(v) end
	f:Refresh()
	return f
end

-- Colour swatches: one square per choice, the picked one outlined.
-- items = { { value, r, g, b, tooltip } }; get() -> value; set(value).
function W.Swatches(parent, items, get, set)
	local f = CreateFrame("Frame", nil, parent)
	local size, gap = 16, SP.s
	f:SetSize(#items * (size + gap) - gap + 4, S.control)
	f.buttons = {}
	for i, it in ipairs(items) do
		local b = CreateFrame("Button", nil, f)
		b:SetSize(size, size)
		b:SetPoint("LEFT", 2 + (i - 1) * (size + gap), 0)
		padHit(b, size, size)
		b.fill = b:CreateTexture(nil, "ARTWORK")
		b.fill:SetAllPoints()
		b.ring = CreateFrame("Frame", nil, b)
		b.ring:SetPoint("TOPLEFT", -3, 3)
		b.ring:SetPoint("BOTTOMRIGHT", 3, -3)
		Theme.Border(b.ring, "text")
		b.value, b.tooltip = it[1], it[5]
		b:SetScript("OnClick", function() set(it[1]); f:Refresh() end)
		b:SetScript("OnEnter", tooltipFor)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		f.buttons[i] = b
	end
	function f:SetColours(list)
		for i, it in ipairs(list) do
			local b = self.buttons[i]
			if b then b.fill:SetColorTexture(it[2], it[3], it[4], 1) end
		end
	end
	function f:Refresh()
		local v = get()
		for _, b in ipairs(self.buttons) do b.ring:SetShown(b.value == v) end
	end
	f:SetColours(items)
	f:Refresh()
	return f
end

-- Options menu: a small "···" button that drops a list of actions and
-- on/off items. items() -> { { text=, checked=function or nil, onClick= } }.
function W.OptionsButton(parent, items, tooltip)
	local b = W.Button(parent, "···", S.control + SP.xs, S.control)
	b.tooltip = tooltip
	local pop = CreateFrame("Frame", nil, b)
	pop:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", 0, -SP.xxs)
	pop:SetWidth(200)
	pop:SetFrameStrata("FULLSCREEN_DIALOG")
	pop:EnableMouse(true)
	Theme.Panel(pop, { bg = "surface", border = "lineStrong" })
	pop:Hide()
	pop.entries = {}
	b.pop = pop
	function b:Close() pop:Hide(); if openMenu == self then openMenu = nil end end
	local function draw()
		local list = items()
		for i, it in ipairs(list) do
			local e = pop.entries[i]
			if not e then
				e = CreateFrame("Button", nil, pop)
				e:SetHeight(S.row + SP.xs)
				e:SetPoint("TOPLEFT", 1, -1 - (i - 1) * (S.row + SP.xs))
				e:SetPoint("TOPRIGHT", -1, -1 - (i - 1) * (S.row + SP.xs))
				e.hl = e:CreateTexture(nil, "BACKGROUND")
				e.hl:SetAllPoints()
				Theme.Solid(e.hl, "raised")
				e.hl:Hide()
				e.tick = e:CreateTexture(nil, "ARTWORK")
				e.tick:SetSize(8, 8)
				e.tick:SetPoint("LEFT", SP.s, 0)
				e.tick:SetTexture(Theme.TEX.dot)
				Theme.Tint(e.tick, "accent")
				e.text = Theme.Text(e, "body", "text")
				e.text:SetPoint("LEFT", SP.l + SP.xs, 0)
				e.text:SetPoint("RIGHT", -SP.s, 0)
				e.text:SetWordWrap(false)
				e:SetScript("OnEnter", function(self) self.hl:Show() end)
				e:SetScript("OnLeave", function(self) self.hl:Hide() end)
				e:SetScript("OnClick", function(self)
					b:Close()
					if self.item and self.item.onClick then self.item.onClick() end
				end)
				pop.entries[i] = e
			end
			e.item = it
			e.text:SetText(it.text)
			e.tick:SetShown(it.checked ~= nil and it.checked() and true or false)
			e:Show()
		end
		for i = #list + 1, #pop.entries do pop.entries[i]:Hide() end
		pop:SetHeight(#list * (S.row + SP.xs) + 2)
	end
	function b:Open()
		if openMenu and openMenu ~= self then openMenu:Close() end
		draw()
		Motion.In(pop, Theme.MOTION.menu, 0.96, "TOP")
		openMenu = self
	end
	-- Run an item by its text, as if clicked (tests).
	function b:Run(text)
		for _, it in ipairs(items()) do if it.text == text then it.onClick() return true end end
		return false
	end
	b:SetScript("OnClick", function(self) if pop:IsShown() then self:Close() else self:Open() end end)
	b:SetScript("OnHide", function(self) self:Close() end)
	return b
end

---------------------------------------------------------------------------
-- Card (v0.6.0): a quiet uppercase label, an optional quiet action on its
-- right, and a flat panel of rows under it. Rows (all optional):
--   { label=, value=, tone=, labelTone=, tip=function(tt), onClick= }
--   { text=, tone= }                    a sentence inside the panel (wraps)
--   { bar = { { n, tone }, ... } }      a bar split in proportion
-- Clickable rows get a hover fill and a chevron. card:SetRows returns the
-- card's height. card:SetBody(h) instead keeps an empty panel h tall for
-- other content (card.panel).
---------------------------------------------------------------------------
W.CARD_LABEL_H = 20

function W.Card(parent, width, title, action)
	local c = CreateFrame("Frame", nil, parent)
	c:SetWidth(width)
	c.width = width
	c.label = Theme.Text(c, "label", "dim")
	c.label:SetPoint("TOPLEFT", 0, -SP.xxs)
	c.label:SetText((title or ""):upper())
	c.labelH = title and W.CARD_LABEL_H or 0
	if action then
		c.button = W.Button(c, action.text, nil, S.controlSmall, action.onClick, "quiet")
		c.button:SetPoint("TOPRIGHT", 0, SP.xs)
		c.button.tooltip = action.tooltip
	end
	local panel = CreateFrame("Frame", nil, c)
	panel:SetPoint("TOPLEFT", 0, -c.labelH)
	panel:SetPoint("TOPRIGHT", 0, -c.labelH)
	Theme.Panel(panel, { bg = "surface", border = "line" })
	c.panel = panel
	c.note = Theme.Text(c, "small", "faint")
	c.note:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 0, -SP.xs)
	c.note:SetPoint("RIGHT", 0, 0)
	c.note:SetJustifyV("TOP")
	c.note:SetWordWrap(true)
	c.pool = {}
	c.noteText = false

	local function rowFrame(i)
		local r = c.pool[i]
		if not r then
			r = CreateFrame("Button", nil, panel)
			r.hl = r:CreateTexture(nil, "BACKGROUND")
			r.hl:SetAllPoints()
			Theme.Solid(r.hl, "raised")
			r.hl:Hide()
			r.rule = Theme.Rule(r, "rule")
			r.rule:SetPoint("TOPLEFT")
			r.rule:SetPoint("TOPRIGHT")
			r.labelFS = Theme.Text(r, "body", "text")
			r.labelFS:SetWordWrap(false)
			r.valueFS = Theme.Text(r, "body", "text")
			r.valueFS:SetJustifyH("RIGHT")
			r.valueFS:SetWordWrap(false)
			r.textFS = Theme.Text(r, "small", "dim")
			r.textFS:SetJustifyV("TOP")
			r.textFS:SetWordWrap(true)
			r.textFS:SetSpacing(2)
			r.chev = r:CreateTexture(nil, "ARTWORK")
			r.chev:SetSize(12, 12)
			r.chev:SetTexture(Theme.TEX.chevron)
			Theme.Tint(r.chev, "faint")
			r.segs = {}
			r.row = false
			r:SetScript("OnEnter", function(self)
				if self.row and (self.row.onClick or self.row.tip) then Motion.HoverIn(self.hl) end
				if self.row and self.row.tip then
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					self.row.tip(GameTooltip)
					GameTooltip:Show()
				end
			end)
			r:SetScript("OnLeave", function(self) Motion.HoverOut(self.hl); GameTooltip:Hide() end)
			r:SetScript("OnClick", function(self) if self.row and self.row.onClick then self.row.onClick() end end)
			c.pool[i] = r
		end
		return r
	end

	function c:SetRows(rows)
		self.rows = rows
		local y = 0
		local inner = self.width - 2 * SP.m
		for i, row in ipairs(rows) do
			local r = rowFrame(i)
			r.row = row
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", 0, -y)
			r:SetPoint("TOPRIGHT", 0, -y)
			r.rule:SetShown(i > 1 and not row.bar)
			r.labelFS:Hide(); r.valueFS:Hide(); r.textFS:Hide(); r.chev:Hide()
			for _, t in ipairs(r.segs) do t:Hide() end
			local h
			if row.bar then
				local total = 0
				for _, sgm in ipairs(row.bar) do total = total + math.max(0, sgm[1]) end
				local x = SP.m
				for j, sgm in ipairs(row.bar) do
					local t = r.segs[j]
					if not t then t = r:CreateTexture(nil, "ARTWORK"); r.segs[j] = t end
					local w = total > 0 and math.floor(inner * sgm[1] / total + 0.5) or 0
					t:ClearAllPoints()
					t:SetPoint("LEFT", x, 0)
					t:SetSize(math.max(1, w), SP.s)
					Theme.Solid(t, sgm[2])
					t:SetShown(w > 0)
					x = x + w
				end
				h = SP.l
			elseif row.text then
				Theme.Font(r.textFS, "small", row.tone or "dim")
				r.textFS:SetPoint("TOPLEFT", SP.m, -SP.s)
				r.textFS:SetWidth(inner)
				r.textFS:SetText(row.text)
				r.textFS:Show()
				h = math.max(S.cardRow, (r.textFS:GetStringHeight() or 0) + 2 * SP.s)
			else
				local right = row.onClick and (-SP.m - 12 - SP.xs) or -SP.m
				if row.onClick then r.chev:SetPoint("RIGHT", -SP.m + SP.xxs, 0); r.chev:Show() end
				Theme.Font(r.valueFS, "body", row.tone or "text")
				r.valueFS:SetPoint("RIGHT", right, 0)
				r.valueFS:SetText(row.value or "")
				r.valueFS:Show()
				Theme.Font(r.labelFS, "body", row.labelTone or "text")
				r.labelFS:SetPoint("LEFT", SP.m, 0)
				r.labelFS:SetPoint("RIGHT", r.valueFS, "LEFT", -SP.s, 0)
				r.labelFS:SetText(row.label or "")
				r.labelFS:Show()
				h = S.cardRow
			end
			r:SetHeight(h)
			r:EnableMouse(row.onClick ~= nil or row.tip ~= nil)
			r:Show()
			y = y + h
		end
		for i = #rows + 1, #self.pool do self.pool[i]:Hide(); self.pool[i].row = false end
		panel:SetHeight(math.max(1, y))
		panel:SetShown(#rows > 0)
		return self:Layout(y)
	end

	function c:SetBody(h)
		for _, r in ipairs(self.pool) do r:Hide() end
		panel:SetHeight(h)
		panel:Show()
		return self:Layout(h)
	end

	-- A faint sentence under the panel (nil = none).
	function c:SetNote(text)
		self.noteText = text or false
		self.note:SetText(text or "")
		self.note:SetShown(text ~= nil)
		return self:Layout(panel:GetHeight() or 0)
	end

	function c:Layout(h)
		local total = self.labelH + h
		if self.noteText then total = total + SP.xs + (self.note:GetStringHeight() or 0) end
		self:SetHeight(math.max(1, total))
		return total
	end
	c:SetNote(nil)
	return c
end

-- Plain text of a card's rows (tests, Copy).
function W.CardText(rows)
	local L = {}
	for _, row in ipairs(rows or {}) do
		if row.text then L[#L + 1] = row.text
		elseif row.label then L[#L + 1] = row.label .. "  " .. Theme.Paint(row.tone, row.value or "-") end
	end
	return table.concat(L, "\n")
end

---------------------------------------------------------------------------
-- Number strip (v0.6.0): a flat panel split into equal cells, each a big
-- figure (with an optional dim suffix) over a dim caption. Cells can have
-- a tooltip and a click. strip:SetStats({ { figure=, suffix=, caption=,
-- tone=, tip=function(tt), onClick= }, ... })
---------------------------------------------------------------------------
function W.StatStrip(parent, width, count)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(width, S.statH)
	Theme.Panel(f, { bg = "surface", border = "line" })
	f.cells = {}
	local cw = width / count
	for i = 1, count do
		local c = CreateFrame("Button", nil, f)
		c:SetPoint("TOPLEFT", (i - 1) * cw, 0)
		c:SetSize(cw, S.statH)
		c.hl = c:CreateTexture(nil, "BACKGROUND", nil, 1)
		c.hl:SetPoint("TOPLEFT", 1, -1)
		c.hl:SetPoint("BOTTOMRIGHT", -1, 1)
		Theme.Solid(c.hl, "raised")
		c.hl:Hide()
		if i > 1 then
			local sep = c:CreateTexture(nil, "BORDER")
			sep:SetPoint("TOPLEFT", 0, -SP.s)
			sep:SetPoint("BOTTOMLEFT", 0, SP.s)
			sep:SetWidth(Theme.BORDER.hairline)
			Theme.Solid(sep, "rule")
		end
		c.figure = Theme.Text(c, "figure", "text")
		c.figure:SetPoint("TOPLEFT", SP.l, -SP.s - 1)
		c.suffix = Theme.Text(c, "body", "dim")
		c.suffix:SetPoint("BOTTOMLEFT", c.figure, "BOTTOMRIGHT", SP.xs, 2)
		c.caption = Theme.Text(c, "small", "dim")
		c.caption:SetPoint("BOTTOMLEFT", SP.l, SP.s + 1)
		c.caption:SetPoint("RIGHT", -SP.s, 0)
		c.caption:SetWordWrap(false)
		c.stat = false
		c:SetScript("OnEnter", function(self)
			if not self.stat then return end
			if self.stat.onClick then Motion.HoverIn(self.hl) end
			if self.stat.tip then
				GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
				self.stat.tip(GameTooltip)
				GameTooltip:Show()
			end
		end)
		c:SetScript("OnLeave", function(self) Motion.HoverOut(self.hl); GameTooltip:Hide() end)
		c:SetScript("OnClick", function(self) if self.stat and self.stat.onClick then self.stat.onClick() end end)
		f.cells[i] = c
	end
	function f:SetStats(stats)
		self.stats = stats
		for i, c in ipairs(self.cells) do
			local st = stats[i]
			c.stat = st or false
			c:SetShown(st ~= nil)
			if st then
				c.figure:SetText(st.figure or Theme.DASH)
				c.figure:SetTextColor(Theme.RGB(st.tone or "text"))
				c.suffix:SetText(st.suffix or "")
				c.caption:SetText(st.caption or "")
			end
		end
	end
	return f
end

---------------------------------------------------------------------------
-- Settings card (v0.6.0): a Card whose rows are settings: a name, an
-- optional sentence under it, and a control on the right (a switch, a
-- menu, a slider, swatches, a button). card:AddSwitch / card:AddControl,
-- then card:Finish(). card:Refresh() refreshes every control.
---------------------------------------------------------------------------
function W.SettingsCard(parent, width, title)
	local c = W.Card(parent, width, title)
	c:SetRows({})
	c.items, c.y = {}, 0
	local panel = c.panel
	local function row(label, desc)
		local r = CreateFrame("Frame", nil, panel)
		local h = desc and S.settingRow or S.cardRow + SP.xs
		r:SetPoint("TOPLEFT", 0, -c.y)
		r:SetPoint("TOPRIGHT", 0, -c.y)
		r:SetHeight(h)
		if #c.items > 0 then
			local rule = Theme.Rule(r, "rule")
			rule:SetPoint("TOPLEFT")
			rule:SetPoint("TOPRIGHT")
		end
		r.name = Theme.Text(r, "body", "text")
		r.name:SetWordWrap(false)
		r.name:SetText(label)
		r.desc = false
		if desc then
			r.name:SetPoint("TOPLEFT", SP.m, -SP.s + 1)
			r.desc = Theme.Text(r, "small", "dim")
			r.desc:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -SP.xxs - 1)
			r.desc:SetWordWrap(false)
			r.desc:SetText(desc)
		else
			r.name:SetPoint("LEFT", SP.m, 0)
		end
		c.y = c.y + h
		return r
	end
	-- make(rowFrame) -> control (anchored by the caller or here on the right).
	function c:AddControl(label, desc, make, tip)
		local r = row(label, desc)
		local ctl = make(r)
		ctl:ClearAllPoints()
		ctl:SetPoint("RIGHT", r, "RIGHT", -SP.m, 0)
		r.name:SetPoint("RIGHT", ctl, "LEFT", -SP.m, 0)
		if r.desc then r.desc:SetPoint("RIGHT", ctl, "LEFT", -SP.m, 0) end
		if tip then ctl.tooltip = tip end
		self.items[#self.items + 1] = { row = r, control = ctl, label = label }
		return ctl, r
	end
	function c:AddSwitch(label, desc, get, set, tip)
		return self:AddControl(label, desc, function(r) return W.Switch(r, get, set) end, tip)
	end
	function c:Finish()
		panel:SetHeight(math.max(1, self.y))
		panel:Show()
		return self:Layout(self.y)
	end
	function c:Refresh()
		for _, it in ipairs(self.items) do
			if it.control.Refresh then it.control:Refresh() end
		end
	end
	-- The control of a setting by its name (tests).
	function c:Control(label)
		for _, it in ipairs(self.items) do if it.label == label then return it.control end end
	end
	return c
end

---------------------------------------------------------------------------
-- Recipe tooltips (v0.6.0): short by default (name, who can make it, what
-- it needs, a Shift hint), the full item, skill-up colours, where to learn
-- and the click hints while Shift is held.
--   r = { recipeID, itemID, skillLine, name, count (crafters), online,
--         fav, crafterName, crafterOnline }
--   click = "Click: ..." words for the Shift view.
---------------------------------------------------------------------------
function W.CraftersLine(r)
	local count = r.count or 0
	if count == 0 then return Theme.Paint("spark", "Nobody in the guild knows it yet") end
	if count == 1 and r.crafterName then
		return Theme.Paint("good", "1 crafter: ") .. r.crafterName ..
			(r.crafterOnline and Theme.Paint("dim", " (online)") or "")
	end
	return Theme.Paint("good", Theme.Count(count, "crafter")) ..
		((r.online or 0) > 0 and Theme.Paint("dim", ", " .. r.online .. " online") or "")
end

function W.RecipeTip(tt, r, click)
	local shift = SK.Compat.ShiftDown()
	if shift and (r.itemID or 0) > 0 and tt.SetItemByID then
		tt:SetItemByID(r.itemID)
	else
		local hex = (r.itemID or 0) > 0 and SK.Compat.ItemQualityHex(r.itemID)
		tt:SetText(hex and ("|c" .. hex .. (r.name or "?") .. "|r") or (r.name or "?"))
	end
	if r.count ~= nil then Theme.TipLine(tt, W.CraftersLine(r), "text") end
	local reagents = SK.Reagents.Text(SK.Reagents.Lines(r.recipeID), Theme.Code)
	if reagents then Theme.TipLine(tt, "Needs " .. reagents, "dim", true) end
	if shift then
		W.SkillUpTip(tt, r.recipeID, r.skillLine)
		if click then Theme.TipLine(tt, click .. "  ·  Right-click: " .. (r.fav and "unstar" or "star"), "accent", true) end
	else
		Theme.TipLine(tt, "Shift: the full item, skill-up colours and where to learn", "faint")
	end
end

-- Tooltips that change with Shift redraw while you hold it: a List row's
-- onEnter runs again on MODIFIER_STATE_CHANGED if its tooltip is showing.
W.tipRow = nil
function W.RedrawTip()
	local row = W.tipRow
	if not (row and row.item and row:IsShown() and GameTooltip:IsShown()) then return end
	if GameTooltip.IsOwned and not GameTooltip:IsOwned(row) then return end
	local list = row:GetParent()
	if list and list.opts and list.opts.onEnter then list.opts.onEnter(row, row.item) end
end
SK:RegisterEvent("MODIFIER_STATE_CHANGED", function() W.RedrawTip() end)
