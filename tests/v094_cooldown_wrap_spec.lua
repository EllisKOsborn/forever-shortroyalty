-- v0.9.4: transmute cooldowns showed "49d 19h". The client's GetTime() is
-- milliseconds in 32 bits and wraps every 2^32 ms (49 days 17 hours); a
-- cooldown started before the wrap reports its start on the far side.
local H = require("tests.helpers.load")

describe("v0.9.4 cooldowns across the client's timer wrap", function()
	local SK, W
	before_each(function() SK, W = H.load() end)

	it("reads the real time left when the start time comes back from before the wrap", function()
		local wrap = SK.Compat.TIMER_WRAP
		assert.equal(4294967.296, wrap)
		W.now = 5000                                  -- the computer restarted not long ago
		-- Transmute: Arcanite (47 h) started 45 h ago, reported past the wrap
		local duration = 169200
		W.spellCD[17187] = { 5000 - 45 * 3600 + wrap, duration }
		local left = SK.Compat.SpellCooldownRemaining(17187)
		assert.is_true(math.abs(left - 2 * 3600) < 0.01, tostring(left))
		-- an ordinary cooldown is unchanged
		W.spellCD[17566] = { 4000, 82800 }
		assert.equal(81800, SK.Compat.SpellCooldownRemaining(17566))
		-- never more than the cooldown itself
		W.spellCD[17566] = { 9000, 82800 }
		assert.is_true(SK.Compat.SpellCooldownRemaining(17566) <= 82800)
	end)

	it("fixes 49-day times already shared by older versions", function()
		local PB, wrap = SK.ProfBoard, SK.Compat.TIMER_WRAP
		local now = 1800000000
		assert.equal(7200, math.floor(PB.CooldownLeft(now + 7200 + wrap, now) + 0.5))
		assert.equal("2h 0m", PB.TimeLeft(PB.CooldownLeft(now + 7200 + wrap, now)))
		assert.equal(0, PB.CooldownLeft(now + wrap - 60, now))  -- ended a minute ago: ready
		assert.equal(100800, PB.CooldownLeft(now + 100800, now)) -- 1d 4h stays as it is
		assert.equal(0, PB.CooldownLeft(now - 50, now))
	end)
end)

describe("v0.9.4 profession window cooldowns", function()
	it("takes the wrap off the profession window's time left too", function()
		local SK = H.load()
		local wrap = SK.Compat.TIMER_WRAP
		local T = _G.C_TradeSkillUI or {}
		_G.C_TradeSkillUI = T
		local old = T.GetRecipeCooldown
		T.GetRecipeCooldown = function(id) return id == 1 and (3600 + wrap) or 1800 end
		assert.is_true(math.abs(SK.Compat.RecipeCooldown(1) - 3600) < 0.01)
		assert.equal(1800, SK.Compat.RecipeCooldown(2))
		T.GetRecipeCooldown = old
	end)
end)
