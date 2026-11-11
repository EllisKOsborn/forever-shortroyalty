-- v0.5.5: who in the guild wears an item (from shared gear).
local H = require("tests.helpers.load")

local A, B, C = "Player-1-0000000B", "Player-1-0000000C", "Player-1-0000000D"
local HELM = 10504 -- Green Lens (any item ID works: names come from the stub)

local function link(id) return "|cff1eff00|Hitem:" .. id .. "::::::::60:::::|h[x]|h|r" end

describe("Gear index", function()
	local SK, W
	before_each(function()
		SK, W = H.load()
		H.addMember(SK, "Fizzwick Spark", A, { online = true })
		H.addMember(SK, "Brambletoe Root", B, { online = false })
		H.addMember(SK, "Aura Light", C)
		local g = SK.DBM:Guild()
		g.profiles[A] = { gear = { [1] = link(HELM), [5] = link(2000) } }
		g.profiles[B] = { gear = { [1] = link(HELM), [11] = link(HELM) } } -- two slots: counted once
		g.profiles[C] = { gear = nil } -- hides gear
		SK.GearIndex.Dirty()
	end)

	it("builds item -> wearers from shared gear, once per person", function()
		local idx = SK.GearIndex.Build(SK.DBM:Guild().profiles)
		assert.equal(2, #idx[HELM])
		assert.same({ A }, idx[2000])
		assert.same({}, SK.GearIndex.Build(nil))
	end)

	it("lists wearers online first, and words it", function()
		local w = SK.GearIndex.Wearers(HELM)
		assert.same({ "Fizzwick Spark", "Brambletoe Root" }, { w[1].name, w[2].name })
		assert.equal("worn by Fizzwick Spark, Brambletoe Root", SK.GearIndex.Text(w, 3))
		assert.equal("worn by Fizzwick Spark (+1)", SK.GearIndex.Text(w, 1))
		assert.is_nil(SK.GearIndex.Text(SK.GearIndex.Wearers(424242), 3))
	end)

	it("follows profile changes", function()
		assert.equal(2, #SK.GearIndex.Wearers(HELM))
		SK.DBM:Guild().profiles[B].gear = {}
		SK:Fire("PROFILE_UPDATED")
		assert.equal(1, #SK.GearIndex.Wearers(HELM))
	end)

	it("adds a Guild line to item tooltips, and /sr who answers by link or name", function()
		H.loadUI(SK)
		local lines = {}
		local tip = { AddLine = function(_, t) lines[#lines + 1] = t end, AddDoubleLine = function() end }
		SK.Tooltip.Add(tip, HELM)
		assert.truthy(table.concat(lines, "\n"):find("worn by Fizzwick Spark, Brambletoe Root", 1, true))
		assert.equal(1, SK.Commands.Who(link(HELM)))
		W.itemNames[HELM], W.itemCached[HELM] = "Green Lens", true
		assert.equal(1, SK.Commands.Who("green le"))
		assert.equal(0, SK.Commands.Who("zz"))
		assert.equal(0, #SK.errors)
	end)
end)
