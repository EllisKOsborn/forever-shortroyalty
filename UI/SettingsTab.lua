-- Settings tab (v0.6.0): two page tabs. General: what you share, how the
-- window looks (accent colour, font, size), and reminders, as rows of
-- switches. Advanced: tools, debug logging and a live status read-out with
-- exactly what guildmates see.
local _, SK = ...

local Settings = SK:NewModule("SettingsTab")
local Theme, W = SK.Theme, SK.Widgets
local S, SP = Theme.SIZES, Theme.SPACE

Settings.COL_W = math.floor((S.contentW - SP.l) / 2)
Settings.VIEWS = { { "general", "General" }, { "advanced", "Advanced" } }

-- Swatch colours for the accent choices (class = the player's own).
function Settings.AccentItems()
	local items = {}
	for _, choice in ipairs(Theme.ACCENT_CHOICES) do
		local c = Theme.AccentBase(choice, SK.Compat.PlayerClassRGB())
		items[#items + 1] = { choice, c[1], c[2], c[3], Theme.ACCENT_NAMES[choice] }
	end
	return items
end

function Settings:SetAccent(choice)
	SK.DB.settings.accent = choice
	Theme.SetAccent(choice, SK.Compat.PlayerClassRGB())
	SK.MainFrame:Refresh()
end

function Settings:Build(page)
	local s = SK.DB.settings
	self.page = page
	self.views = W.SubTabs(page, Settings.VIEWS, function(key)
		s.settingsView = key
		Settings:Refresh()
	end)
	self.views:SetPoint("TOPLEFT", 0, 0)
	self.views:SetPoint("TOPRIGHT", 0, 0)
	local top = -(S.subTabs + SP.l)
	local colB = Settings.COL_W + SP.l

	-------------------------------------------------------------------------
	-- General
	-------------------------------------------------------------------------
	local general = CreateFrame("Frame", nil, page)
	general:SetPoint("TOPLEFT", 0, top)
	general:SetPoint("BOTTOMRIGHT")
	self.general = general

	local sharing = W.SettingsCard(general, Settings.COL_W, "Sharing")
	sharing:SetPoint("TOPLEFT", 0, 0)
	sharing:AddSwitch("Share and receive guild data", "Off: nothing is sent or received.", function() return s.sync end,
		function(v)
			s.sync = v
			SK:Print(v and "Sync turned on." or "Sync turned off. Nothing will be sent or received.")
			SK.MainFrame:Refresh()
		end)
	sharing:AddSwitch("Share my gear and talents", "Gear, item level and talents.", function() return s.share.gear end,
		function(v)
			s.share.gear = v
			SK.Profile:BuildSelf()
			SK:Print(v and "Your gear and talents will be shared." or "Your gear and talents are now private.")
		end)
	sharing:AddSwitch("Share my recipes", "Recipes, skill levels and cooldowns.", function() return s.share.recipes end,
		function(v)
			s.share.recipes = v
			SK.Profile:BuildSelf()
			SK:Print(v and "Your recipes will be shared." or "Your recipes are now private.")
		end)
	sharing:AddSwitch("Share my Short Words results", "Your scores on the leaderboards; never your letters.",
		function() return s.share.words ~= false end, function(v)
			s.share.words = v
			SK.Profile:BuildSelf()
			SK:Print(v and "Your Short Words results will be shared." or "Your Short Words results are now private.")
		end)
	sharing:Finish()
	sharing:SetNote("Notes and officer notes are never shared.")
	self.sharing = sharing

	local profs = W.SettingsCard(general, Settings.COL_W, "Professions and tooltips")
	profs:SetPoint("TOPLEFT", sharing, "BOTTOMLEFT", 0, -SP.l)
	profs:AddSwitch("Guild lines in item tooltips", "Who can make an item, and who wears it.",
		function() return s.craftTooltips end, function(v) s.craftTooltips = v end)
	profs:AddSwitch("Remind me to reopen profession windows", "In chat, at most every few days.",
		function() return s.profNudges end, function(v) s.profNudges = v end,
		"Only after your skill has gone up by " .. SK.Professions.NUDGE_POINTS ..
		" or more since you last opened that profession's window.")
	profs:AddSwitch("Record guild milestones", "For the Overview; kept on this computer.",
		function() return s.feed end, function(v) s.feed = v end)
	profs:Finish()
	self.profs = profs

	local display = W.SettingsCard(general, Settings.COL_W, "Display")
	display:SetPoint("TOPLEFT", colB, 0)
	self.swatches = display:AddControl("Accent colour", "Pink like the crest, gold, or your class.", function(r)
		return W.Swatches(r, Settings.AccentItems(), function() return s.accent or "pink" end,
			function(v) Settings:SetAccent(v) end)
	end)
	self.fontMenu = display:AddControl("Font", "Changes after a reload.", function(r)
		local menu = W.Menu(r, {
			width = 150,
			items = function()
				local out = {}
				for _, k in ipairs(Theme.BODY_CHOICES) do out[#out + 1] = { value = k, text = Theme.BODY_NAMES[k] } end
				return out
			end,
			get = function() return s.font or "inter" end,
			set = function(v)
				s.font = v
				Settings:Refresh()
			end,
		})
		return menu
	end)
	self.scale = display:AddControl("Window size", nil, function(r)
		return W.Slider(r, { width = 110, min = 0.7, max = 1.3, step = 0.1,
			get = function() return s.window.scale or 1 end,
			set = function(v) SK.MainFrame:SetScale(v) end,
			format = function(v) return string.format("%d%%", v * 100 + 0.5) end })
	end)
	display:AddSwitch("Minimap button", nil, function() return not s.minimap.hide end,
		function(v) SK.Minimap:SetShown(v) end)
	display:AddSwitch("Reduce motion", "No window, tab or sync animations.", function() return s.reduceMotion end,
		function(v) s.reduceMotion = v end)
	display:Finish()
	self.display = display
	-- Reload button, shown once the font choice differs from the one in use.
	self.reload = W.Button(general, "Reload now", nil, S.control, function() SK.Compat.ReloadUI() end, "primary")
	self.reload:SetPoint("TOPRIGHT", display, "BOTTOMRIGHT", 0, -SP.s)
	self.reload.tooltip = "Reloads the interface (like /reload) so the new font is used."
	self.reloadText = Theme.Text(general, "small", "dim")
	self.reloadText:SetPoint("RIGHT", self.reload, "LEFT", -SP.s, 0)
	self.reloadText:SetText("The new font shows after a reload.")

	-------------------------------------------------------------------------
	-- Advanced
	-------------------------------------------------------------------------
	local advanced = CreateFrame("Frame", nil, page)
	advanced:SetPoint("TOPLEFT", 0, top)
	advanced:SetPoint("BOTTOMRIGHT")
	self.advanced = advanced
	local tools = W.SettingsCard(advanced, Settings.COL_W, "Tools")
	tools:SetPoint("TOPLEFT", 0, 0)
	local function action(label, desc, text, fn, tip)
		tools:AddControl(label, desc, function(r) return W.Button(r, text, 92, S.controlSmall + 2, fn) end, tip)
	end
	action("Rescan my character", "Gear, talents, professions, reputation.", "Rescan", function()
		SK.Profile:BuildSelf(); SK:Print("Character rescanned.")
	end)
	action("Sync now", "Announce your data, ask for anything missing.", "Sync", function()
		SK.Sync:SendHello(); SK.Sync:SendQuery(); SK:Print("Sync requested.")
	end)
	action("Window position", "Put the window back in the middle.", "Reset", function() SK.MainFrame:ResetPosition() end)
	action("Debug report", "Same as /sr debug, to send to the addon author.", "Open", function() SK.DebugWindow:Open() end)
	tools:AddSwitch("Debug logging in chat", nil, function() return s.debug end, function(v) s.debug = v end)
	tools:Finish()
	self.tools = tools

	self.status = W.Sheet(advanced, Settings.COL_W - SP.m)
	self.status:SetPoint("TOPLEFT", colB, 0)
	self.status:SetPoint("BOTTOM", 0, 0)
	self.status:SetWidth(Settings.COL_W - SP.m)
end

-- Status sections. Pure apart from reading SK state; tested.
function Settings.StatusSections()
	local paused, why = SK.Sync:IsPaused()
	local canSend, sendWhy = SK.Sync:CanSend()
	local st = SK.Sync.stats
	local own = SK.Profile:Own()
	local status = {
		{ label = "Version", value = SK.VERSION },
		{ label = "Guild", value = SK.guildName or "none" },
		{ label = "Sync", value = paused and ("paused (" .. why .. ")") or "running", tone = paused and "dim" or "good" },
		{ label = "Sending", value = canSend and "allowed" or ("not allowed (" .. tostring(sendWhy) .. ")"),
			tone = canSend and "text" or "bad" },
		{ label = "Messages sent / received", value = st.sent .. " / " .. st.received },
		{ label = "Accepted / rejected / queued", value = st.accepted .. " / " .. st.rejected .. " / " .. #SK.Sync.queue },
	}
	if #SK.errors > 0 then
		status[#status + 1] = { label = "Lua errors caught", value = tostring(#SK.errors), tone = "spark" }
	end
	if own then
		status[#status + 1] = { label = "Your data updated", value = SK.Theme.Ago(own.updated) .. " ago" }
		local missing = SK.Professions.Unscanned(own)
		if #missing > 0 then
			status[#status + 1] = { text = "Open these profession windows once: " .. table.concat(missing, ", "), tone = "spark" }
		end
	end
	-- Sharing preview (read-only): exactly what the public copy contains.
	local share = {}
	if own then
		for _, c in ipairs(SK.Profile.SharingSummary(own, SK.DB.settings.share)) do
			share[#share + 1] = { label = c.label, labelTone = "text", value = c.shared and "shared" or "private",
				tone = c.shared and "good" or "dim" }
		end
		local pub = SK.DBM:Guild() and SK.DBM:Guild().profiles[own.guid]
		if pub then share[#share + 1] = { label = "Last shared copy", value = SK.Theme.Ago(pub.updated) .. " ago" } end
	else
		share[#share + 1] = { text = "Nothing yet: your profile is built once the guild roster loads." }
	end
	share[#share + 1] = { text = "Never shared: " .. SK.Profile.NEVER_SHARED }
	if not SK.DB.settings.sync then
		share[#share + 1] = { text = "Sync is off, so nothing is being sent right now.", tone = "spark" }
	end
	share[#share + 1] = { text = "Turning sharing off stops future updates. Copies guildmates already have"
		.. " stay until they're replaced." }
	return {
		{ title = "Status", rows = status },
		{ title = "What guildmates see from you", rows = share },
	}
end

function Settings:Refresh()
	if not self.views then return end
	local s = SK.DB.settings
	local view = s.settingsView == "advanced" and "advanced" or "general"
	self.views:SetActive(view)
	self.general:SetShown(view == "general")
	self.advanced:SetShown(view == "advanced")
	self.sharing:Refresh()
	self.profs:Refresh()
	self.display:Refresh()
	self.tools:Refresh()
	self.swatches:SetColours(Settings.AccentItems())
	local pending = (s.font == "narrow" and "narrow" or "inter") ~= Theme.body
	self.reload:SetShown(pending)
	self.reloadText:SetShown(pending)
	self.sections = Settings.StatusSections()
	self.status:SetSections(self.sections)
end

SK.MainFrame:AddTab("settings", "Settings", Settings, { group = "settings",
	desc = "What you share, how the window looks, and reminders." })
