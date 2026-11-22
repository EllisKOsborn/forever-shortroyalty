-- v0.15.0: the window width setting (Normal / Wide / Extra wide). Pages lay
-- out from Theme.SIZES.contentW; the flexible columns get the extra room.
local H = require("tests.helpers.load")

describe("v0.15.0 window width", function()
	local SK, W, Theme
	before_each(function()
		SK, W = H.load()
		H.loadUI(SK)
		Theme = SK.Theme
		W.member("Pip", W.player.guid, { rank = "Officer", rankIndex = 1 })
		W.member("Bob", "Player-1-B")
		SK.Identity:ReadRoster()
		SK.Profile:BuildSelf()
	end)
	after_each(function() if Theme then Theme.SetWidth("normal") end end)

	local function col(columns, key)
		for _, c in ipairs(columns) do if c.key == key then return c.width end end
	end

	it("normal keeps the v0.6.0 layout", function()
		Theme.SetWidth("normal")
		assert.equal(960, Theme.SIZES.window[1])
		assert.equal(744, Theme.SIZES.contentW)
		assert.equal(124, col(SK.RosterTab.PLAN_COLUMNS, "name"))
	end)

	it("wide and extra wide give names, notes and lists the room", function()
		local note = col(SK.RosterTab.PLAN_COLUMNS, "note")
		Theme.SetWidth("wider")
		assert.equal(1440, Theme.SIZES.window[1])
		assert.equal(744 + 480, Theme.SIZES.contentW)
		assert.equal(124 + 168, col(SK.RosterTab.PLAN_COLUMNS, "name"))
		assert.equal(note + 480 - 168 - 72, col(SK.RosterTab.PLAN_COLUMNS, "note"))
		-- Every list still adds up to its space.
		local sum = 0
		for _, c in ipairs(SK.RosterTab.PLAN_COLUMNS) do sum = sum + c.width end
		assert.equal(Theme.SIZES.contentW - Theme.SPACE.m, sum)
		assert.equal(270 + 160, SK.RaidsTab.LEFT_W)
		assert.equal(Theme.SIZES.contentW - SK.RaidsTab.LEFT_W - Theme.SPACE.xl, SK.RaidsTab.RIGHT_W)
		Theme.SetWidth("wide")
		assert.equal(124 + 84, col(SK.RosterTab.PLAN_COLUMNS, "name"))
		Theme.SetWidth("bogus")
		assert.equal("normal", Theme.width)
	end)

	it("the setting applies at start-up and every page builds at Extra wide", function()
		SK.DB.settings.window.width = "wider"
		SK.MainFrame.ApplyLook()
		assert.equal(1440, Theme.SIZES.window[1])
		SK.DB.officer[W.player.guid] = true
		SK.MainFrame:Open("overview")
		for _, tab in ipairs(SK.MainFrame.tabs) do
			SK.MainFrame:Select(tab.key)
			assert.is_true(tab.built)
		end
		assert.equal(0, #SK.errors)
	end)

	it("Settings offers the widths and asks for a reload when it changes", function()
		SK.MainFrame:Open("settings")
		local S = SK.SettingsTab
		assert.is_false(S.reload:IsShown())
		S.widthMenu:Choose("wide")
		assert.equal("wide", SK.DB.settings.window.width)
		assert.is_true(S.reload:IsShown())
	end)
end)
