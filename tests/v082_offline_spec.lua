-- v0.8.2: "No player named X is currently playing." in the chat (owner,
-- 16 Nov 2026). Our addon whispers (profile replies, requests, attendance)
-- went to players who had just logged off; the game prints that line for
-- every whisper (every numbered piece) that can't be delivered.
local H = require("tests.helpers.load")

describe("v0.8.2 whispers to players who have logged off", function()
	local SK, W, sent
	before_each(function()
		SK, W = H.load()
		W.member("Pocus Hocus", W.player.guid)
		W.member("Andreas Sham", "Player-1-A")
		SK.Identity:ReadRoster()
		SK.Profile:BuildSelf()
		sent = H.captureSends(SK)
		SK.Compat.AddChatFilter("CHAT_MSG_SYSTEM", SK.Sync.SystemFilter)
	end)

	local function queueWhispers(n, name)
		for i = 1, n do
			SK.Sync:Enqueue("x" .. i, "WHISPER", name or "Andreas Sham", "BULK", { t = "RQ", w = {} })
		end
	end

	it("reads the player's name out of the game's own texts", function()
		assert.equal("Andreas Sham", SK.Compat.NotFoundName("No player named 'Andreas Sham' is currently playing."))
		assert.equal("Andreas Sham", SK.Compat.WentOfflineName("Andreas Sham has gone offline."))
		assert.equal("Ann", SK.Compat.WentOfflineName("|Hplayer:Ann|h[Ann]|h has gone offline."))
		assert.is_nil(SK.Compat.NotFoundName("Andreas Sham has gone offline."))
		assert.is_nil(SK.Compat.NotFoundName(nil))
		assert.is_nil(SK.Compat.NotFoundName(42))
	end)

	it("hides the message only when our addon just whispered that player", function()
		queueWhispers(1)
		SK.Sync:Flush()
		assert.equal(1, #sent)
		assert.is_false(W.systemMessage("No player named 'Andreas Sham' is currently playing."))
		assert.equal(1, SK.Sync.stats.hiddenNotFound)
		-- someone we never whispered: the player typed it, so they see it
		assert.is_true(W.systemMessage("No player named 'Someone Else' is currently playing."))
		-- long after our whisper: shown again
		W.advance(SK.Sync.WHISPER_HIDE + 5)
		assert.is_true(W.systemMessage("No player named 'Andreas Sham' is currently playing."))
		-- other system messages are never touched
		assert.is_true(W.systemMessage("Pocus Hocus has earned the achievement [Level 10]!"))
	end)

	it("ignores case and a realm suffix when matching names", function()
		queueWhispers(1, "Andreas Sham-SomeRealm")
		SK.Sync:Flush()
		assert.is_false(W.systemMessage("No player named 'andreas sham' is currently playing."))
	end)

	it("stops whispering them once the game says they're not playing", function()
		queueWhispers(1)
		SK.Sync:Flush()
		W.systemMessage("No player named 'Andreas Sham' is currently playing.")
		queueWhispers(5)
		SK.Sync:Flush()
		SK.Sync:Flush()
		assert.equal(1, #sent) -- nothing more went out
		assert.is_true(SK.Sync.stats.skippedOffline >= 5)
		assert.equal(0, #SK.Sync.queue)
	end)

	it("drops whispers still waiting when they log off", function()
		queueWhispers(6)
		SK.Sync:Enqueue("hi", "GUILD", nil, "NORMAL", { t = "HI", c = {} })
		assert.is_true(W.systemMessage("Andreas Sham has gone offline.")) -- still shown
		assert.equal(1, #SK.Sync.queue) -- only the guild message is left
		SK.Sync:Flush()
		assert.equal(1, #sent)
		assert.equal("GUILD", sent[1].dist)
	end)

	it("whispers them again once they're back", function()
		SK.Sync:MarkGone("Andreas Sham")
		assert.is_true(SK.Sync:IsGone("Andreas Sham"))
		-- any addon message from them (their login HI) clears it
		SK.Sync:OnCommReceived("SomethingElse", "", "GUILD", "Andreas Sham") -- other prefix: ignored
		assert.is_true(SK.Sync:IsGone("Andreas Sham"))
		SK.Sync:OnCommReceived(SK.PREFIX, "x", "GUILD", "Andreas Sham")
		assert.is_false(SK.Sync:IsGone("Andreas Sham"))
		-- or, failing that, after GONE_HOLD
		SK.Sync:MarkGone("Andreas Sham")
		W.advance(SK.Sync.GONE_HOLD + 1)
		assert.is_false(SK.Sync:IsGone("Andreas Sham"))
		queueWhispers(1)
		SK.Sync:Flush()
		assert.equal(1, #sent)
	end)

	it("a whisper the game reports as offline stops the rest of the queue for them", function()
		local calls = 0
		SK.Sync.transport = function(_, _, _, _, cb, arg)
			calls = calls + 1
			cb(arg, nil, nil, 12) -- TargetOffline
		end
		queueWhispers(8)
		for _ = 1, 4 do SK.Sync:Flush() end
		assert.equal(1, calls)
		assert.equal(0, SK.Sync.stats.sendErrors or 0)
	end)

	it("works without the chat filter API (older clients)", function()
		local real = _G.ChatFrameUtil.AddMessageEventFilter
		_G.ChatFrameUtil.AddMessageEventFilter = nil
		assert.is_false(SK.Compat.AddChatFilter("CHAT_MSG_SYSTEM", function() end))
		_G.ChatFrameUtil.AddMessageEventFilter = real
	end)
end)
