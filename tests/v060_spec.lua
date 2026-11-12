-- v0.6.0 redesign: sidebar window, one accent colour, Inter, Settings as
-- switch rows, the Roster options menu, Professions page tabs and reminder
-- bar, and short recipe tooltips with the details on Shift.
local H = require("tests.helpers.load")

local function tooltipRecorder()
	local tt = { lines = {} }
	function tt:SetText(t) self.lines = { t } end
	function tt:SetItemByID(id) self.lines = { "ITEM " .. id } end
	function tt:AddLine(t) self.lines[#self.lines + 1] = t end
	function tt:AddDoubleLine(a, b) self.lines[#self.lines + 1] = a .. " | " .. b end
	function tt:Text() return table.concat(self.lines, "\n") end
	return tt
end

describe("v0.6.0 Settings", function()
	local SK, W
	before_each(function()
		SK, W = H.load()
		H.loadUI(SK)
		W.member("Pip", W.player.guid)
		SK.Identity:ReadRoster()
		SK.Profile:BuildSelf()
		SK.MainFrame:Show("settings")
	end)

	it("sharing switches change what is shared", function()
		local sw = SK.SettingsTab.sharing:Control("Share my gear and talents")
		assert.is_true(sw.on)
		sw:GetScript("OnClick")(sw)
		assert.is_false(SK.DB.settings.share.gear)
		assert.is_false(sw.on)
	end)

	it("the accent swatches change the accent colour at once and remember it", function()
		local gold
		for _, b in ipairs(SK.SettingsTab.swatches.buttons) do if b.value == "gold" then gold = b end end
		gold:GetScript("OnClick")(gold)
		assert.equal("gold", SK.DB.settings.accent)
		assert.equal("FFC000", SK.Theme.HEX.accent)
		assert.is_true(gold.ring:IsShown())
		SK.SettingsTab:SetAccent("pink")
		assert.equal("F06BB0", SK.Theme.HEX.accent)
	end)

	it("a new font asks for a reload, and the window size is a slider", function()
		assert.is_false(SK.SettingsTab.reload:IsShown())
		SK.SettingsTab.fontMenu:Choose("narrow")
		assert.equal("narrow", SK.DB.settings.font)
		assert.is_true(SK.SettingsTab.reload:IsShown())
		SK.SettingsTab.fontMenu:Choose("inter")
		assert.is_false(SK.SettingsTab.reload:IsShown())
		SK.SettingsTab.scale:Choose(1.2)
		assert.equal(1.2, SK.DB.settings.window.scale)
		assert.equal("120%", SK.SettingsTab.scale.value:GetText())
	end)

	it("Advanced holds the tools and the status read-out", function()
		assert.is_true(SK.SettingsTab.general:IsShown())
		assert.is_false(SK.SettingsTab.advanced:IsShown())
		local tab = SK.SettingsTab.views.tabs[2]
		tab:GetScript("OnClick")(tab)
		assert.equal("advanced", SK.DB.settings.settingsView)
		assert.is_true(SK.SettingsTab.advanced:IsShown())
		assert.is_false(SK.SettingsTab.general:IsShown())
		assert.equal("Status", SK.SettingsTab.sections[1].title)
		assert.truthy(SK.SettingsTab.tools:Control("Debug logging in chat"))
	end)
end)

describe("v0.6.0 Roster", function()
	local SK, W
	before_each(function()
		SK, W = H.load()
		H.loadUI(SK)
		W.member("Pip", W.player.guid)
		W.member("Bob", "Player-1-B", { online = false })
		SK.Identity:ReadRoster()
		SK.Profile:BuildSelf()
		SK.MainFrame:Show("roster")
	end)

	it("has six columns; rank, version and data age are in the tooltip", function()
		local keys = {}
		for _, c in ipairs(SK.RosterTab.list.opts.columns) do keys[#keys + 1] = c.key end
		assert.same({ "name", "level", "spec", "profs", "ilvl", "seen" }, keys)
		local total = 0
		for _, c in ipairs(SK.RosterTab.list.opts.columns) do total = total + c.width end
		assert.equal(SK.Theme.SIZES.contentW - 12, total)
	end)

	it("the ··· menu groups alts and copies the list", function()
		local before = SK.DB.settings.groupAlts
		assert.is_true(SK.RosterTab.options:Run("Group alts under their main"))
		assert.equal(not before, SK.DB.settings.groupAlts)
		assert.is_true(SK.RosterTab.options:Run("Copy the list as text"))
	end)

	it("marks out-of-date characters with an orange !", function()
		local now = W.now
		assert.is_true(SK.RosterTab.NeedsLook({ outdated = true }, now))
		assert.is_true(SK.RosterTab.NeedsLook({ hasData = true, updated = now - 8 * 86400 }, now))
		assert.is_false(SK.RosterTab.NeedsLook({ hasData = true, updated = now - 60 }, now))
		assert.is_false(SK.RosterTab.NeedsLook({ hasData = true, isSelf = true, updated = now - 9 * 86400 }, now))
	end)

	it("old versions first, from the Overview", function()
		SK.Identity:Member("Player-1-B").addon = "0.0.1"
		SK.RosterTab:ShowOldVersions()
		assert.equal("Bob", SK.RosterTab.list.items[1].name)
	end)
end)

describe("v0.6.0 Professions", function()
	local SK, W
	before_each(function()
		SK, W = H.load()
		H.loadUI(SK)
		W.member("Pip", W.player.guid)
		SK.Identity:ReadRoster()
		SK.Profile:BuildSelf()
	end)

	it("page tabs switch Guild, Recipes and Cooldowns", function()
		SK.MainFrame:Show("professions")
		local P = SK.ProfessionsTab
		assert.equal("board", P.views.active)
		P.views.tabs[2]:GetScript("OnClick")(P.views.tabs[2])
		assert.equal("recipes", SK.DB.settings.profView)
		assert.is_true(P.allList:IsShown())
		assert.is_false(P.board:IsShown())
		P.views.tabs[3]:GetScript("OnClick")(P.views.tabs[3])
		assert.is_true(P.cooldowns:IsShown())
		-- one profession sits under Guild
		P:Open(197)
		assert.equal("board", P.views.active)
		assert.is_true(P.back:IsShown())
	end)
end)

describe("v0.6.0 recipe tooltips", function()
	local SK
	before_each(function()
		SK = H.load()
		H.loadUI(SK)
	end)

	it("are short by default and show the details while Shift is held", function()
		local r = { recipeID = 3914, itemID = 4245, skillLine = 197, name = "Small Silk Pack", count = 2, online = 1 }
		local tt = tooltipRecorder()
		_G.IsShiftKeyDown = function() return false end
		SK.Widgets.RecipeTip(tt, r, "Click: who can make it")
		local text = tt:Text()
		assert.truthy(text:find("2 crafters", 1, true))
		assert.truthy(text:find("1 online", 1, true))
		assert.truthy(text:find("Shift:", 1, true))
		assert.is_nil(text:find("ITEM", 1, true))         -- not the whole item
		assert.is_nil(text:find("Right-click", 1, true))
		assert.is_true(#tt.lines <= 4)
		_G.IsShiftKeyDown = function() return true end
		tt = tooltipRecorder()
		SK.Widgets.RecipeTip(tt, r, "Click: who can make it")
		text = tt:Text()
		assert.truthy(text:find("ITEM 4245", 1, true))     -- the full item
		assert.truthy(text:find("Right-click: star", 1, true))
		assert.is_nil(text:find("Shift:", 1, true))
		_G.IsShiftKeyDown = nil
	end)

	it("name the one crafter when there is only one", function()
		local line = SK.Widgets.CraftersLine({ count = 1, crafterName = "Bramble", crafterOnline = true })
		assert.truthy(line:find("1 crafter: ", 1, true))
		assert.truthy(line:find("Bramble", 1, true))
		assert.truthy(line:find("(online)", 1, true))
		assert.truthy(SK.Widgets.CraftersLine({ count = 0 }):find("Nobody in the guild", 1, true))
	end)
end)

describe("v0.6.0 widgets", function()
	local SK
	before_each(function()
		SK = H.load()
		H.loadUI(SK)
	end)

	it("a switch flips its setting and can be turned off", function()
		local v = false
		local sw = SK.Widgets.Switch(UIParent, function() return v end, function(x) v = x end)
		sw:GetScript("OnClick")(sw)
		assert.is_true(v)
		sw:SetDisabled(true)
		sw:GetScript("OnClick")(sw)
		assert.is_true(v)
	end)

	it("the number strip shows a figure, a suffix and a caption per cell", function()
		local strip = SK.Widgets.StatStrip(UIParent, 400, 2)
		strip:SetStats({ { figure = "41", suffix = "/ 52", caption = "have it" } })
		assert.equal("41", strip.cells[1].figure:GetText())
		assert.equal("/ 52", strip.cells[1].suffix:GetText())
		assert.is_false(strip.cells[2]:IsShown())
	end)

	it("a card lays out rows, a bar and a note", function()
		local c = SK.Widgets.Card(UIParent, 300, "Raids")
		local h = c:SetRows({ { label = "a", value = "1" }, { bar = { { 1, "good" }, { 3, "lineStrong" } } },
			{ text = "a sentence" } })
		assert.is_true(h > SK.Widgets.CARD_LABEL_H)
		assert.equal("RAIDS", c.label:GetText())
		local segs = c.pool[2].segs
		assert.is_true(segs[1]:IsShown() and segs[2]:IsShown())
	end)
end)
