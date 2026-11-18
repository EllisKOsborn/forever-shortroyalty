-- v0.9.3: a player's /sr debug (18 Nov) showed 71 failed sends with only
-- "GeneralError" as the reason. Failures are now broken down by channel,
-- message and target, and that unclear code no longer makes the addon ask
-- for a debug report.
local H = require("tests.helpers.load")

describe("v0.9.3 failed sends", function()
	local SK, W
	before_each(function()
		SK, W = H.load()
		H.loadUI(SK) -- Commands.lua (/sr debug)
		W.member("Pip", W.player.guid)
		W.member("Bob", "Player-1-B")
		SK.Identity:ReadRoster()
		SK.Profile:BuildSelf()
		_G.Enum.SendAddonMessageResult.GeneralError = 9
		_G.Enum.SendAddonMessageResult.ChannelThrottle = 8
	end)

	local function sendAll(code, n, dist, target, t)
		SK.Sync.transport = function(_, _, _, _, cb, arg) cb(arg, nil, nil, code) end
		for i = 1, n do
			SK.Sync:Enqueue("k" .. i, dist, target, "NORMAL", { t = t or "RQ", w = {} })
		end
		for _ = 1, math.ceil(n / SK.Sync.SENDS_PER_FLUSH) + 1 do SK.Sync:Flush() end
	end

	it("counts failures by channel, message and reason, and keeps the last few", function()
		sendAll(9, 3, "WHISPER", "Bob", "PR")
		sendAll(9, 2, "GUILD", nil, "HI")
		assert.equal(3, SK.Sync.failures["WHISPER PR GeneralError"])
		assert.equal(2, SK.Sync.failures["GUILD HI GeneralError"])
		assert.equal(5, SK.Sync.stats.sendErrors)
		assert.equal(SK.Sync.FAIL_RECENT, #SK.Sync.recentFails)
		assert.equal("GUILD", SK.Sync.recentFails[1].dist) -- newest first
		local lines = SK.Commands.FailureLines(SK.Sync.failures, SK.Sync.recentFails, W.now)
		assert.truthy(lines[1]:find("WHISPER PR GeneralError x3", 1, true))
		assert.truthy(lines[1]:find("GUILD HI GeneralError x2", 1, true))
		assert.truthy(table.concat(lines, "\n"):find('WHISPER PR to "Bob" (GeneralError)', 1, true))
		assert.truthy(table.concat(lines, "\n"):find("GUILD HI to everyone", 1, true))
	end)

	it("doesn't ask for a debug report over GeneralError, but still does for other failures", function()
		sendAll(9, 12, "GUILD", nil)
		for _, line in ipairs(W.prints) do assert.is_nil(line:find("Please send the /sr debug", 1, true)) end
		sendAll(8, SK.Sync.SEND_FAIL_WARN, "GUILD", nil)
		local asked = 0
		for _, line in ipairs(W.prints) do
			if line:find("Please send the /sr debug", 1, true) then asked = asked + 1 end
		end
		assert.equal(1, asked)
	end)

	it("remembers a limited number of kinds", function()
		for i = 1, SK.Sync.FAIL_KEYS + 10 do
			SK.Sync.NoteFailure(SK.Sync.failures, SK.Sync.recentFails, { dist = "GUILD", msg = { t = "T" .. i } }, "x", W.now)
		end
		local n = 0
		for _ in pairs(SK.Sync.failures) do n = n + 1 end
		assert.equal(SK.Sync.FAIL_KEYS, n)
		assert.same({}, SK.Commands.FailureLines({}, {}, W.now))
	end)
end)
