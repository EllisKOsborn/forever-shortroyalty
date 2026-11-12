-- v0.3.5: pointing at "Don't have it yet" (or its names) on the Overview
-- lists everyone without Short Royalty in a tooltip.
local H = require("tests.helpers.load")

local function fakeTooltip()
	local tt = { lines = {} }
	function tt:AddLine(text) self.lines[#self.lines + 1] = text end
	function tt:AddDoubleLine(l, r) self.lines[#self.lines + 1] = l .. " | " .. r end
	return tt
end

describe("v0.3.5 full list of who doesn't have the addon", function()
	local SK
	before_each(function()
		SK = H.load()
		H.loadUI(SK)
	end)

	local function people(n)
		local t = {}
		for i = 1, n do t[i] = { name = string.format("N%02d Surname", i), online = i == 1 } end
		return t
	end

	it("puts every name in the tooltip, two per line", function()
		local tt = fakeTooltip()
		SK.OverviewTab.WithoutTip(tt, people(14))
		local all = table.concat(tt.lines, "\n")
		assert.truthy(all:find("Not seen with Short Royalty yet (14)", 1, true))
		for i = 1, 14 do assert.truthy(all:find(string.format("N%02d Surname", i), 1, true), i) end
		assert.truthy(tt.lines[2]:find("N01 Surname", 1, true) and tt.lines[2]:find("N02 Surname", 1, true)) -- two per line
		assert.truthy(tt.lines[2]:find(SK.RosterTab.DOT.online, 1, true)) -- N01 is online
	end)

	it("stops at 60 names and points to the Roster for the rest", function()
		local tt = fakeTooltip()
		SK.OverviewTab.WithoutTip(tt, people(65))
		local all = table.concat(tt.lines, "\n")
		assert.truthy(all:find("N60 Surname", 1, true))
		assert.is_nil(all:find("N61 Surname", 1, true))
		assert.truthy(all:find("and 5 more", 1, true))
	end)

	it("the number and the Needs a look row both carry the full list", function()
		local o = { members = 14, players = 14, online = 1, withAddon = 0, hasAddon = 0, without = people(14), levels = {},
			raids = {}, outdated = 0, addonNoData = 0, unscanned = 0, stale = 0 }
		local stats = SK.OverviewTab.Stats(o)
		assert.equal("function", type(stats[3].tip))
		assert.equal("function", type(SK.OverviewTab.NeedsRows(o)[1].tip))
		assert.is_nil(stats[2].onClick)
	end)

	it("a Card row with a tip shows it on hover, and a clickable row has a chevron", function()
		local c = SK.Widgets.Card(UIParent, 200, "Test")
		local shown, clicked
		c:SetRows({ { label = "x", value = "1" }, { label = "y", value = "2", tip = function() shown = true end,
			onClick = function() clicked = true end } })
		local r = c.pool[2]
		r:GetScript("OnEnter")(r)
		r:GetScript("OnClick")(r)
		assert.is_true(shown)
		assert.is_true(clicked)
		assert.is_true(r.chev:IsShown())
		assert.is_false(c.pool[1].chev:IsShown())
	end)

	it("a Block row with a tip shows it on hover", function()
		local b = SK.Widgets.Block(UIParent, 200, "Test")
		local shown
		b:SetRows({ { label = "x", value = "1" }, { text = "names", tip = function() shown = true end } })
		local hit = b.pool[2].hit
		assert.is_true(hit:IsShown())
		assert.is_false(b.pool[1].hit:IsShown())
		hit:GetScript("OnEnter")(hit)
		assert.is_true(shown)
	end)
end)
