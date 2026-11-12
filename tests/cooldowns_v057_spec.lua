-- v0.5.7: only recipes with a real cooldown (Forever's SpellCooldowns) count
-- as cooldowns. The game reports the short global cooldown on every recipe
-- just after a craft; older versions then tracked (and shared) every recipe.
local H = require("tests.helpers.load")

local MOONCLOTH, ARCANITE = 18560, 17187         -- real cooldowns in Forever's data
local GREEN_BAG, LINEN_BOOTS = 3758, 12045        -- no cooldown
local ETAY = "Player-1-E"

local function profile(SK, guid, fields)
	local p = { v = 1, guid = guid, name = guid, updated = 1, gear = {} }
	for k, v in pairs(fields or {}) do p[k] = v end
	p.hash = SK.Profile.HashOf(p)
	return p
end

describe("Profession cooldowns (v0.5.7)", function()
	local SK, W
	before_each(function()
		SK, W = H.load()
		W.member("Pip", W.player.guid)
		W.member("Etay", ETAY)
		W.professions = { { name = "Tailoring", rank = 250, max = 300, skillLine = 197 } }
		SK.Identity:ReadRoster()
		SK.Profile:BuildSelf()
	end)

	it("knows which recipes have a cooldown, from Forever's data", function()
		assert.equal(342000, SK.Data.RECIPE_COOLDOWNS[MOONCLOTH])
		assert.is_true(SK.RecipeDB.HasCooldown(MOONCLOTH))
		assert.is_true(SK.RecipeDB.HasCooldown(ARCANITE))
		assert.is_false(SK.RecipeDB.HasCooldown(GREEN_BAG))
	end)

	it("the board leaves out recipes a guildmate's older version shared as cooldowns", function()
		SK.DBM:Guild().profiles[ETAY] = profile(SK, ETAY, { received = W.now,
			profs = { [197] = { name = "Tailoring", rank = 300, scanned = W.now } },
			cds = { [GREEN_BAG] = W.now - 60, [LINEN_BOOTS] = W.now - 60, [MOONCLOTH] = W.now + 3600 } })
		local rows = SK.ProfBoard.Cooldowns(SK.ProfBoard.Context(W.now))
		assert.equal(1, #rows)
		assert.equal(MOONCLOTH, rows[1].recipeID)
	end)

	it("a scan just after a craft (global cooldown on everything) tracks only real cooldowns", function()
		W.tradeskill = { skillLine = 197, name = "Tailoring", recipes = {
			[MOONCLOTH] = { learned = true, itemID = 14342, cd = 1.4 },
			[GREEN_BAG] = { learned = true, itemID = 4241, cd = 1.4 },
		} }
		SK.Professions:Scan()
		W.advance(1)
		local own = SK.Profile:Own()
		assert.is_not_nil(own.cds[MOONCLOTH])
		assert.is_nil(own.cds[GREEN_BAG])
		assert.is_nil(SK.DB.cooldownSpells[W.player.guid][GREEN_BAG])
		assert.is_true(SK.DB.cooldownSpells[W.player.guid][MOONCLOTH])
	end)

	it("cleans up recipes an older version tracked by mistake", function()
		SK.DB.cooldownSpells[W.player.guid] = { [GREEN_BAG] = true, [MOONCLOTH] = true }
		local own = SK.Profile:Own()
		own.cds = { [GREEN_BAG] = W.now - 60, [MOONCLOTH] = W.now - 60 }
		SK.Profile:BuildSelf()
		own = SK.Profile:Own()
		assert.is_nil(own.cds[GREEN_BAG])
		assert.is_not_nil(own.cds[MOONCLOTH])
		assert.is_nil(SK.DB.cooldownSpells[W.player.guid][GREEN_BAG])
		local pub = SK.DBM:Guild().profiles[W.player.guid]
		assert.is_nil(pub.cds and pub.cds[GREEN_BAG])
	end)
end)
