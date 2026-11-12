-- The main window (v0.6.0): a sidebar on the left (crest, the sections,
-- sync status at the bottom) and the page on the right (its title, one
-- sentence saying what it's for, the reminder bar when there is one, and
-- the page itself). Built lazily the first time it is opened.
local _, SK = ...

local Main = SK:NewModule("MainFrame")
local Theme, W, Motion = SK.Theme, SK.Widgets, SK.Motion
local S, SP, M = Theme.SIZES, Theme.SPACE, Theme.MOTION

Main.tabs = {}        -- ordered { key, title, module, group, desc, icon }
Main.FRAME_NAME = "ShortRoyaltyMainFrame"

-- Sidebar sections, in order. The settings group has no label.
Main.GROUPS = { { key = "guild", title = "Guild" }, { key = "crafting", title = "Crafting" }, { key = "settings" } }

-- Tab modules call this at load time. module:Build(page) once,
-- module:Refresh() whenever data changes while the tab is visible.
-- opts = { group = "guild" | "crafting" | "settings", desc = "one sentence",
--          icon = Theme.TEX.x, nav = "sidebar label" (defaults to title) }.
-- A module may have Description() for a sentence that changes (Overview).
function Main:AddTab(key, title, module, opts)
	opts = opts or {}
	self.tabs[#self.tabs + 1] = { key = key, title = title, module = module, group = opts.group or "guild",
		desc = opts.desc, icon = opts.icon or Theme.TEX[key], nav = opts.nav or title }
end

local function savePosition(f)
	local point, _, relPoint, x, y = f:GetPoint(1)
	local w = SK.DB.settings.window
	w.point, w.relPoint, w.x, w.y = point, relPoint, x, y
end

-- The chosen window size, shrunk if it wouldn't fit on screen (big UI
-- scale on a small display). Pure; tested.
-- extraH: the reminder bar's height while it shows.
function Main.FitScale(chosen, screenW, screenH, extraH)
	local ww, wh = S.window[1], S.window[2] + (extraH or 0)
	local fit = 1e9
	if screenW and screenW > 0 then fit = math.min(fit, screenW * 0.96 / ww) end
	if screenH and screenH > 0 then fit = math.min(fit, screenH * 0.94 / wh) end
	return math.max(0.5, math.min(chosen or 1, fit))
end

function Main:ApplyScale()
	if not self.frame then return end
	local chosen = SK.DB.settings.window.scale or 1
	self.frame:SetScale(Main.FitScale(chosen, UIParent:GetWidth(), UIParent:GetHeight(), self.bannerH))
end

-- Accent and body font from Settings (v0.6.0). The font must be set before
-- any text is created, so this runs when saved settings load.
function Main.ApplyLook()
	local s = SK.DB and SK.DB.settings
	if not s then return end
	Theme.body = (s.font == "narrow") and "narrow" or "inter"
	Theme.SetAccent(s.accent or "pink", SK.Compat.PlayerClassRGB())
end

function Main:OnInit() Main.ApplyLook() end
-- The class colour is only known once the player is in the world.
function Main:OnLogin() Theme.SetAccent(SK.DB.settings.accent or "pink", SK.Compat.PlayerClassRGB()) end

local function dragHandle(frame, f)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function() f:StartMoving() end)
	frame:SetScript("OnDragStop", function() f:StopMovingOrSizing(); savePosition(f) end)
end

function Main:Build()
	if self.frame then return self.frame end
	local s = SK.DB.settings.window
	local f = CreateFrame("Frame", self.FRAME_NAME, UIParent)
	f:SetSize(S.window[1], S.window[2])
	f:SetPoint(s.point or "CENTER", UIParent, s.relPoint or s.point or "CENTER", s.x or 0, s.y or 0)
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:Hide()
	Theme.Panel(f, { bg = "void", border = "line" })
	tinsert(UISpecialFrames, self.FRAME_NAME) -- Esc closes it (instantly)
	self.frame = f
	self:ApplyScale()

	-------------------------------------------------------------------------
	-- Sidebar
	-------------------------------------------------------------------------
	local side = CreateFrame("Frame", nil, f)
	side:SetPoint("TOPLEFT", 1, -1)
	side:SetPoint("BOTTOMLEFT", 1, 1)
	side:SetWidth(S.sidebar - 1)
	side.bg = side:CreateTexture(nil, "BACKGROUND")
	side.bg:SetAllPoints()
	Theme.Solid(side.bg, "side")
	local edge = side:CreateTexture(nil, "BORDER")
	edge:SetPoint("TOPRIGHT")
	edge:SetPoint("BOTTOMRIGHT")
	edge:SetWidth(Theme.BORDER.hairline)
	Theme.Solid(edge, "line")
	f.side = side

	-- Crest and name (a drag handle).
	local brand = CreateFrame("Frame", nil, side)
	brand:SetPoint("TOPLEFT")
	brand:SetPoint("TOPRIGHT")
	brand:SetHeight(S.pageHead)
	dragHandle(brand, f)
	f.titleBar = brand
	local crest = brand:CreateTexture(nil, "ARTWORK")
	crest:SetSize(S.crest, S.crest)
	crest:SetPoint("TOPLEFT", SP.l - 1, -SP.l)
	crest:SetTexture(Theme.TEX.crest)
	f.crest = crest
	local title = Theme.Text(brand, "brand", "text")
	title:SetPoint("LEFT", crest, "RIGHT", SP.s + SP.xxs, 0)
	title:SetText("SHORT\nROYALTY")
	title:SetSpacing(1)
	f.title = title

	-- Sections
	f.navButtons = {}
	local y = S.pageHead + SP.xs
	for _, g in ipairs(Main.GROUPS) do
		if g.title then
			local label = Theme.Text(side, "label", "faint")
			label:SetPoint("TOPLEFT", SP.l, -y - SP.s)
			label:SetText(g.title:upper())
			y = y + SP.l + SP.s + SP.xs
		else
			y = y + SP.m
		end
		for i, tab in ipairs(self.tabs) do
			if tab.group == g.key then
				local b = W.NavItem(side, S.sidebar - 1, tab.icon, tab.nav, function() Main:Select(tab.key) end)
				b:SetPoint("TOPLEFT", 0, -y)
				b.key = tab.key
				f.navButtons[i] = b
				y = y + S.navRow
			end
		end
	end

	-- Sync status at the bottom: a dot, what sync is doing, and the guild.
	local status = CreateFrame("Frame", nil, side)
	status:SetPoint("BOTTOMLEFT", 0, 0)
	status:SetPoint("BOTTOMRIGHT", 0, 0)
	status:SetHeight(S.pageHead - SP.xs)
	status:EnableMouse(true)
	local rule = Theme.Rule(status, "rule")
	rule:SetPoint("TOPLEFT")
	rule:SetPoint("TOPRIGHT")
	local dot = status:CreateTexture(nil, "ARTWORK")
	dot:SetSize(8, 8)
	dot:SetPoint("TOPLEFT", SP.l, -SP.m - 3)
	dot:SetTexture(Theme.TEX.dot)
	f.dot = dot
	local ring = status:CreateTexture(nil, "OVERLAY")
	ring:SetSize(16, 16)
	ring:SetPoint("CENTER", dot, "CENTER")
	ring:SetTexture(Theme.TEX.ring)
	Theme.Tint(ring, "good")
	ring:SetAlpha(0)
	f.ring = ring
	f.status = Theme.Text(status, "small", "dim")
	f.status:SetPoint("LEFT", dot, "RIGHT", SP.s - 1, 0)
	f.status:SetPoint("RIGHT", -SP.s, 0)
	f.status:SetWordWrap(false)
	f.guildLine = Theme.Text(status, "small", "faint")
	f.guildLine:SetPoint("TOPLEFT", SP.l, -(SP.m + SP.l + SP.xs))
	f.guildLine:SetPoint("RIGHT", -SP.s, 0)
	f.guildLine:SetWordWrap(false)
	status:SetScript("OnEnter", function() Main:StatusTooltip(status) end)
	status:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f.statusFrame = status

	-------------------------------------------------------------------------
	-- Page header: title, one sentence, close (a drag handle too)
	-------------------------------------------------------------------------
	local head = CreateFrame("Frame", nil, f)
	head:SetPoint("TOPLEFT", S.sidebar, 0)
	head:SetPoint("TOPRIGHT", -1, -1)
	head:SetHeight(S.pageHead)
	dragHandle(head, f)
	f.head = head
	f.pageTitle = Theme.Text(head, "page", "text")
	f.pageTitle:SetPoint("TOPLEFT", SP.l, -SP.l + 1)
	f.desc = Theme.Text(head, "small", "dim")
	f.desc:SetPoint("TOPLEFT", f.pageTitle, "BOTTOMLEFT", 0, -SP.xs)
	f.desc:SetPoint("RIGHT", -(S.control + SP.l + SP.s), 0)
	f.desc:SetWordWrap(false)
	local close = W.CloseButton(head, function() Main:Close() end)
	close:SetPoint("TOPRIGHT", -SP.m, -SP.m)
	f.close = close

	-- Reminder bar (v0.3.4): orange, under the page header, on every page,
	-- while your profession windows haven't been opened. The window grows
	-- by its height so no page's layout moves.
	local banner = CreateFrame("Frame", nil, f)
	banner:SetPoint("TOPLEFT", S.sidebar + SP.l, -(S.pageHead + SP.xs))
	banner:SetPoint("TOPRIGHT", -SP.l, -(S.pageHead + SP.xs))
	banner:SetHeight(S.banner)
	banner.bg = banner:CreateTexture(nil, "BACKGROUND")
	banner.bg:SetAllPoints()
	Theme.Solid(banner.bg, "spark", Theme.ALPHA.alert)
	banner.edge = banner:CreateTexture(nil, "ARTWORK")
	banner.edge:SetPoint("TOPLEFT")
	banner.edge:SetPoint("BOTTOMLEFT")
	banner.edge:SetWidth(SP.xxs)
	Theme.Solid(banner.edge, "spark")
	banner.button = W.Button(banner, "Open", nil, S.control, function(b) Main:OpenNextProfession(b.skillLine, b.profName) end, "primary")
	banner.button:SetPoint("RIGHT", -SP.s, 0)
	banner.text = Theme.Text(banner, "body", "text")
	banner.text:SetPoint("LEFT", SP.m, 0)
	banner.text:SetPoint("RIGHT", banner.button, "LEFT", -SP.m, 0)
	banner.text:SetJustifyH("LEFT")
	banner.text:SetWordWrap(true)
	banner:Hide()
	f.banner = banner
	self.bannerH = 0

	-- Content area
	local content = CreateFrame("Frame", nil, f)
	content:SetPoint("TOPLEFT", S.sidebar + SP.l, -(S.pageHead + SP.xs))
	content:SetPoint("BOTTOMRIGHT", -SP.l, SP.l)
	f.content = content
	for _, tab in ipairs(self.tabs) do
		local page = CreateFrame("Frame", nil, content)
		page:SetAllPoints()
		page:Hide()
		tab.page = page
	end

	f:SetScript("OnShow", function() Main:Refresh() end)
	f:SetScript("OnHide", function() f:SetAlpha(1) end)

	local function changed() if f:IsShown() then SK:Debounce("ui", 0.5, function() Main:Refresh() end) end end
	SK:On("ROSTER_UPDATED", changed)
	SK:On("SELF_UPDATED", changed)
	SK:On("PROFILE_UPDATED", function()
		changed()
		Motion.Pulse(ring, SK.Compat.Now())
	end)
	-- The bar's Open button is off in combat.
	SK:RegisterEvent("PLAYER_REGEN_DISABLED", function() if f:IsShown() then Main:UpdateBanner() end end)
	SK:RegisterEvent("PLAYER_REGEN_ENABLED", function() if f:IsShown() then Main:UpdateBanner() end end)
	SK:RegisterEvent("UI_SCALE_CHANGED", function() Main:ApplyScale() end)
	SK:RegisterEvent("DISPLAY_SIZE_CHANGED", function() Main:ApplyScale() end)
	return f
end

function Main:Tab(key)
	for _, tab in ipairs(self.tabs) do if tab.key == key then return tab end end
end

-- The page's title and sentence.
function Main:UpdateHeader()
	local tab = self.current and self:Tab(self.current)
	if not tab or not self.frame then return end
	self.frame.pageTitle:SetText(tab.title:upper())
	local desc = tab.module.Description and tab.module:Description() or tab.desc or ""
	self.frame.desc:SetText(desc)
end

function Main:Select(key)
	self:Build()
	for i, tab in ipairs(self.tabs) do
		local active = tab.key == key
		if active and not tab.built then
			tab.module:Build(tab.page)
			tab.built = true
		end
		tab.page:SetShown(active)
		if self.frame.navButtons[i] then self.frame.navButtons[i]:SetActive(active) end
	end
	self.current = key
	SK.DB.settings.window.tab = key
	SK.Onboarding.Seen(key)
	self:Refresh()
end

-- Show, hide or update the reminder bar; grow or shrink the window to fit.
function Main:UpdateBanner()
	local f = self.frame
	if not f then return end
	local info = SK.Professions.Banner(SK.Profile:Own(), SK.DB.settings.share)
	local b = f.banner
	b:SetShown(info ~= nil)
	local extra = info and (S.banner + SP.m) or 0
	if info then
		b.text:SetText(info.text)
		b.button:SetText("Open " .. info.next.name)
		b.button:SetWidth(math.max(S.minHit * 2, (b.button.label:GetStringWidth() or 0) + SP.l * 2))
		b.button.skillLine, b.button.profName = info.next.skillLine, info.next.name
		local can = SK.Compat.CanShowProfession()
		b.button:SetShown(can)
		b.button:SetDisabled(SK.Compat.InCombat())
		b.button.disabledTooltip = "Not in combat"
		b.button.tooltip = "Opens your " .. info.next.name .. " window. The addon records your recipes " ..
			"as soon as it opens; this bar goes away when all are done."
		b.text:SetPoint("RIGHT", can and b.button or b, can and "LEFT" or "RIGHT", -SP.m, 0)
	end
	if extra ~= self.bannerH then
		self.bannerH = extra
		f:SetHeight(S.window[2] + extra)
		f.content:SetPoint("TOPLEFT", S.sidebar + SP.l, -(S.pageHead + SP.xs + extra))
		self:ApplyScale()
	end
end

function Main:OpenNextProfession(skillLine, name)
	local ok, why = SK.Compat.ShowProfession(skillLine)
	if ok then return true end
	if why == "combat" then
		SK:Print("You can open %s after combat.", name or "it")
	else
		SK:Print("Couldn't open %s from here. Open it from your spellbook or professions book instead.", name or "it")
	end
	return false
end

-- Words for the sync status at the bottom of the sidebar. Pure; tested.
function Main.StatusText(paused, why, errors)
	local text = paused and ("Sync paused: " .. why) or "Synced"
	if errors and errors > 0 then
		text = text .. "  ·  " .. Theme.Paint("spark", errors .. (errors == 1 and " error" or " errors"))
	end
	return text
end

-- "Update: 0.9.0 is out" when a guildmate runs a newer version than
-- ours (shown instead of the guild line). Pure; tested.
function Main.UpdateText(newest, mine)
	if not newest or mine == "dev" or not SK.Sync.versionNewer(newest, mine) then return nil end
	return Theme.Paint("spark", "Update: " .. newest .. " is out")
end

-- "Short Royalty · 10 online" (or "No guild"). Pure; tested.
function Main.GuildLine(guildName, guild)
	if not guildName then return "No guild" end
	local online = 0
	for _, m in pairs(guild and guild.members or {}) do
		if not m.leftAt and m.online then online = online + 1 end
	end
	return guildName .. "  ·  " .. online .. " online"
end

function Main:StatusTooltip(owner)
	local paused, why = SK.Sync:IsPaused()
	GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMRIGHT")
	GameTooltip:AddLine(paused and ("Sync paused: " .. why) or "Sync on", Theme.RGB(paused and "dim" or "good"))
	GameTooltip:AddLine(paused and "Your guildmates' data stays as it was. It starts again on its own."
		or "Changes reach guildmates in about a minute. The dot flashes when new data arrives.", Theme.RGB("text"))
	local guild = SK.DBM:Guild()
	local newest = guild and SK.RosterTab.NewestVersion(guild)
	if Main.UpdateText(newest, SK.VERSION) then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Short Royalty " .. newest .. " is out (you have " .. SK.VERSION .. "). " ..
			"Update it from CurseForge or GitHub.", Theme.RGB("spark"))
	end
	if #SK.errors > 0 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(#SK.errors .. " Lua error(s) caught. Type /sr debug and send the text to the addon author.",
			Theme.RGB("spark"))
	end
	GameTooltip:Show()
end

function Main:Refresh()
	if not self.frame or not self.frame:IsShown() then return end
	if not self.current then
		-- v0.2.2: open on the new Overview once, then remember the last tab again.
		if not SK.DB.settings.overviewShown then
			SK.DB.settings.overviewShown = true
			return self:Select("overview")
		end
		return self:Select(SK.DB.settings.window.tab or "overview")
	end
	for _, tab in ipairs(self.tabs) do
		if tab.key == self.current and tab.built and tab.module.Refresh then tab.module:Refresh() end
	end
	self:UpdateBanner()
	self:UpdateHeader()
	local paused, why = SK.Sync:IsPaused()
	local f = self.frame
	f.status:SetText(Main.StatusText(paused, why, #SK.errors))
	local guild = SK.DBM:Guild()
	local newer = Main.UpdateText(guild and SK.RosterTab.NewestVersion(guild), SK.VERSION)
	f.guildLine:SetText(newer or Main.GuildLine(SK.guildName, guild))
	Theme.Tint(f.dot, paused and "faint" or "good")
end

-- instant = true when opened from the keyboard (/sk): no animation.
function Main:Open(key, instant)
	local f = self:Build()
	if not f:IsShown() or Motion.IsLeaving(f) then
		Motion.In(f, M.open, M.openScale, "CENTER", instant)
	end
	if key then self:Select(key) end
end

function Main:Close(instant)
	if not self.frame then return end
	Motion.Out(self.frame, M.close, instant)
end

function Main:Toggle(instant)
	local f = self:Build()
	if f:IsShown() then self:Close(instant) else self:Open(nil, instant) end
end

function Main:Show(key)
	self:Open(key)
end

function Main:SetScale(scale)
	SK.DB.settings.window.scale = scale
	self:ApplyScale()
end

function Main:ResetPosition()
	local w = SK.DB.settings.window
	w.point, w.relPoint, w.x, w.y = "CENTER", "CENTER", 0, 0
	if self.frame then
		self.frame:ClearAllPoints()
		self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	end
end
