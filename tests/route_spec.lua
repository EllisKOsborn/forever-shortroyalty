-- v0.4.8: cheapest levelling route (levelling tools step 4). Open to everyone.
local H = require("tests.helpers.load")

-- Forever's numbers: Bolt of Linen Cloth (2963) yellow 25 / green 37 / grey 50;
-- Gray Woolen Shirt (2406) 90 / 100 / 110; Woolen Cape (2402) 80 / 97 / 115.
local LINEN_BOLT, SHIRT, CAPE = 2963, 2406, 2402

local function range(yellow, grey, ups)
	return { orange = 1, yellow = yellow, green = math.floor((yellow + grey) / 2), grey = grey, ups = ups or 1 }
end

describe("Route planning", function()
	local SK
	before_each(function() SK = H.load() end)

	it("chance of a point: always while orange, then down to nothing at grey", function()
		local R, r = SK.Route, range(90, 110)
		assert.equal(1, R.Chance(r, 89))
		assert.equal(1, R.Chance(r, 90))     -- (110 - 90) / (110 - 90)
		assert.equal(0.5, R.Chance(r, 100))
		assert.equal(0, R.Chance(r, 110))
		assert.equal(3, R.Gain(range(90, 110, 3), 80)) -- orange: all its skill-ups
		assert.equal(0.5, R.Gain(range(90, 110, 3), 100))
	end)

	it("picks the cheapest per point at each skill, and averages crafts for yellow and green", function()
		local recipes = {
			{ recipeID = 1, range = range(100, 110), net = 50 }, -- orange until 100, then fades
			{ recipeID = 2, range = range(95, 120), net = 80 },  -- dearer, but lasts longer
		}
		local steps, total, unpriced = SK.Route.Plan(recipes, 98, 104)
		-- 98, 99: recipe 1 orange (50/point). 100 on: recipe 1 = 50 / ((110-s)/10),
		-- recipe 2 = 80 / ((120-s)/25): at 100 that's 50 vs 80 -> 1; at 102, 62.5 vs 111 -> 1.
		assert.equal(1, #steps)
		assert.same({ 1, 98, 104 }, { steps[1].recipeID, steps[1].from, steps[1].to })
		-- crafts: 1 + 1 + 10/10 + 10/9 + 10/8 + 10/7 = 6.79 -> 7
		assert.equal(7, steps[1].crafts)
		assert.equal(350, steps[1].cost)
		assert.equal(350, total)
		assert.equal(0, unpriced)
	end)

	it("switches recipe when another becomes cheaper per point", function()
		local recipes = {
			{ recipeID = 1, range = range(100, 104), net = 10 },
			{ recipeID = 2, range = range(120, 140), net = 30 },
		}
		local steps = SK.Route.Plan(recipes, 98, 103)
		-- 98, 99 orange r1 (10/pt); 100: r1 = 10/1 = 10 vs r2 30 -> r1; 101: 10/0.75 = 13.3 -> r1;
		-- 102: 10/0.5 = 20 -> r1; still < 30.
		assert.equal(1, #steps)
		steps = SK.Route.Plan(recipes, 98, 104)
		-- 103: r1 = 10/0.25 = 40 > 30 -> r2
		assert.equal(2, #steps)
		assert.same({ 2, 103, 104, 1, 30 }, { steps[2].recipeID, steps[2].from, steps[2].to, steps[2].crafts, steps[2].cost })
	end)

	it("counts selling what you make: a recipe that earns money is the cheapest", function()
		local recipes = {
			{ recipeID = 1, range = range(200, 220), net = 40 },
			{ recipeID = 2, range = range(200, 220), net = -15 }, -- sells for more than it costs
		}
		local steps, total = SK.Route.Plan(recipes, 150, 152)
		assert.equal(2, steps[1].recipeID)
		assert.equal(-30, total)
	end)

	it("orange recipes with several skill-ups move several points per craft", function()
		local steps = SK.Route.Plan({ { recipeID = 1, range = range(200, 220, 3), net = 9 } }, 100, 107)
		assert.same({ 3, 27 }, { steps[1].crafts, steps[1].cost }) -- 100 -> 103 -> 106 -> 107
	end)

	it("says when you run out of recipes, and uses unpriced recipes only when nothing priced works", function()
		local steps, total, unpriced = SK.Route.Plan({
			{ recipeID = 1, range = range(100, 102), net = 5 },
			{ recipeID = 2, range = range(100, 105), net = nil },
		}, 99, 110)
		assert.same({ 1, 99 }, { steps[1].recipeID, steps[1].from })
		local last = steps[#steps]
		assert.is_true(last.stuck)
		assert.equal(105, last.from)
		assert.is_true(unpriced >= 1) -- recipe 2 took over once recipe 1 went grey
		assert.is_true(total > 0)
		assert.same({}, (SK.Route.Plan({}, 10, 10)))
	end)

	it("real Forever recipes: Tailoring 85 to 110 with the shirt and the cape", function()
		local R = SK.RecipeDB
		local recipes = {
			{ recipeID = LINEN_BOLT, range = R.Range(LINEN_BOLT), net = 10 }, -- grey from 50: never used
			{ recipeID = SHIRT, range = R.Range(SHIRT), net = 100 },
			{ recipeID = CAPE, range = R.Range(CAPE), net = 60 },
		}
		local steps = SK.Route.Plan(recipes, 85, 110)
		for _, s in ipairs(steps) do assert.is_true(s.recipeID ~= LINEN_BOLT) end
		assert.equal(CAPE, steps[1].recipeID) -- cape is cheaper while it's orange
		assert.equal(110, steps[#steps].to)
	end)
end)

describe("Professions → Route", function()
	local SK, W
	before_each(function()
		SK, W = H.load()
		H.loadUI(SK)
		W.member("Pocus Hocus", W.player.guid)
		W.professions = { { name = "Tailoring", rank = 85, max = 110, skillLine = 197 } }
		SK.Identity:ReadRoster()
		SK.Profile:BuildSelf()
		local own = SK.Profile:Own()
		own.profs[197].scanned = W.now
		own.profs[197].primary = true
		own.recipes[197] = { [SHIRT] = 2587, [CAPE] = 2584 }
		_G.TSM_API = { GetCustomPriceValue = function() return 100 end } -- every item 1s
	end)
	after_each(function() _G.TSM_API = nil end)

	it("is there for everyone (no unlock), shows steps and a total, and fills the shopping list", function()
		assert.is_false(SK.ProfessionsTab.ProfitUnlocked())
		SK.DB.settings.profView = "route"
		SK.MainFrame:Show("professions")
		local tab = SK.ProfessionsTab
		assert.is_true(tab.routeList:IsShown())
		local steps = tab.routeList.items
		assert.is_true(#steps >= 1)
		assert.equal(85, steps[1].from)
		assert.equal(110, steps[#steps].to)
		assert.truthy(tab.status:GetText():find("Tailoring 85 to 110", 1, true))
		tab.routeAdd:GetScript("OnClick")(tab.routeAdd)
		assert.is_true(#SK.Shopping.Entries() >= 1)
		assert.equal(0, #SK.errors)
	end)

	it("at your cap it says to train the next rank", function()
		SK.Profile:Own().profs[197].rank = 110
		SK.DB.settings.profView = "route"
		SK.MainFrame:Show("professions")
		assert.truthy(SK.ProfessionsTab.routeList.emptyText:find("at your cap", 1, true))
		assert.equal(0, #SK.errors)
	end)

	it("summary line", function()
		local S = SK.ProfessionsTab.RouteSummary
		assert.truthy(S("Tailoring", 120, 150, 52000, 0, "tsm"):find("about 5g 20s", 1, true))
		assert.truthy(S("Tailoring", 120, 150, -300, 0, "tsm"):find("earns about 3s", 1, true))
		assert.truthy(S("Tailoring", 120, 150, 0, 2, nil):find("no TSM", 1, true))
	end)
end)
