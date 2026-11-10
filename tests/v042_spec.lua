-- luacheck: globals C_ChatInfo ChatThrottleLib GetTime GetFramerate securecallfunction xpcall hooksecurefunc IsInGuild GetGuildInfo
-- v0.4.2: fixes from the owner's v0.4.1 /sr debug (10 Nov 2026).
local H = require("tests.helpers.load")

describe("v0.4.2 a momentary 'no guild' from the game", function()
	local SK, W
	before_each(function()
		SK, W = H.load()
		W.member("Pocus Hocus", W.player.guid)
		W.member("Ann", "Player-1-A")
		SK.Identity:ReadRoster()
		SK.Profile:BuildSelf()
	end)

	it("keeps the guild for a while instead of dropping it at once", function()
		local key = SK.guildKey
		assert.truthy(key)
		local realInfo, realIn = _G.GetGuildInfo, _G.IsInGuild
		_G.GetGuildInfo = function() return nil end
		_G.IsInGuild = function() return false end
		SK.Identity:UpdateGuildKey()
		assert.equal(key, SK.guildKey) -- still there
		_G.GetGuildInfo, _G.IsInGuild = realInfo, realIn
		W.advance(SK.Identity.NO_GUILD_AFTER + 2) -- the recheck finds the guild again
		assert.equal(key, SK.guildKey)
		-- really leaving the guild still clears it, after the wait
		_G.GetGuildInfo = function() return nil end
		_G.IsInGuild = function() return false end
		SK.Identity:UpdateGuildKey()
		W.advance(SK.Identity.NO_GUILD_AFTER + 2)
		assert.is_nil(SK.guildKey)
		_G.GetGuildInfo, _G.IsInGuild = realInfo, realIn
	end)

	it("a message arriving with no guild loaded is dropped, not an error", function()
		local msg = H.peerMessage(SK, "SQ", { k = {}, a = {} }, "Player-1-A", "0.4.1")
		SK.guildKey = nil
		assert.is_true((SK.Sync:IsPaused()))
		local ok = pcall(SK.Sync.Handle, SK.Sync, msg:sub(2), "GUILD", "Ann")
		assert.is_true(ok)
		assert.equal("no guild", SK.Sync.lastReject)
		assert.equal(0, #SK.errors)
	end)
end)

describe("v0.4.2 send results", function()
	local SK
	before_each(function() SK = H.load() end)

	it("a whisper to someone who logged off isn't an error", function()
		assert.equal("offline", (SK.Sync.SendOutcome(12, "WHISPER")))
		assert.equal("offline", (SK.Sync.SendOutcome(false, "WHISPER"))) -- no code: likeliest reason
		assert.equal("failed", (SK.Sync.SendOutcome(false, "GUILD")))
		assert.equal("failed", (SK.Sync.SendOutcome(10, "GUILD")))        -- NotInGuild
		assert.equal("ok", (SK.Sync.SendOutcome(0, "WHISPER")))
		assert.equal("lockdown", (SK.Sync.SendOutcome(11, "GUILD")))
	end)

	it("the real ChatThrottleLib hands us Blizzard's result code", function()
		-- Load the vendored library against the stub client.
		local realXpcall = xpcall
		_G.xpcall = function(f, handler, ...) -- Lua 5.1's xpcall takes no arguments
			local args, n = { ... }, select("#", ...)
			return realXpcall(function() return f(unpack(args, 1, n)) end, handler)
		end
		_G.securecallfunction = function(f, ...) return f(...) end
		local realGetTime, clock = _G.GetTime, 1000
		_G.GetTime = function() return clock end
		_G.GetFramerate = function() return 60 end
		_G.hooksecurefunc = _G.hooksecurefunc or function() end
		local sent = {}
		local answer = 0
		_G.C_ChatInfo = _G.C_ChatInfo or {}
		local realSend = C_ChatInfo.SendAddonMessage
		C_ChatInfo.SendAddonMessage = function(prefix, text, dist, target)
			sent[#sent + 1] = { prefix, text, dist, target }
			return answer
		end
		_G.ChatThrottleLib = nil
		assert(loadfile("Libs/AceComm-3.0/ChatThrottleLib.lua"))()
		assert.is_table(ChatThrottleLib)
		clock = 2000 -- well after "login", so the library sends at once instead of queueing

		local got = {}
		local function cb(arg, _, _, result) got[#got + 1] = { arg, result } end
		SK.Sync.transport("\030hello", "GUILD", nil, "NORMAL", cb, "item1")
		answer = 12 -- TargetOffline
		SK.Sync.transport("\030hello", "WHISPER", "Ann Gone", "NORMAL", cb, "item2")
		assert.same({ SK.PREFIX, "\030hello", "GUILD", nil }, sent[1]) -- unchanged on the wire
		assert.equal("Ann Gone", sent[2][4])
		assert.same({ "item1", 0 }, got[1])
		assert.same({ "item2", 12 }, got[2])
		assert.equal("offline", (SK.Sync.SendOutcome(got[2][2], "WHISPER")))

		_G.xpcall, C_ChatInfo.SendAddonMessage, _G.ChatThrottleLib, _G.GetTime = realXpcall, realSend, nil, realGetTime
	end)

	it("counts offline whispers apart from errors and doesn't warn about them", function()
		local W = H.W
		local calls = {}
		_G.ChatThrottleLib = { SendAddonMessage = function(_, _, _, _, dist, _, _, fn, arg)
			calls[#calls + 1] = dist
			fn(arg, false, 12)
		end }
		W.member("Pocus Hocus", W.player.guid)
		SK.Identity:ReadRoster()
		SK.Profile:BuildSelf()
		for i = 1, 8 do SK.Sync:Enqueue("x" .. i, "WHISPER", "Ann Gone", "NORMAL", { t = "RQ", w = {} }) end
		for _ = 1, 4 do SK.Sync:Flush() end
		assert.is_true(#calls >= 8)
		assert.equal(0, SK.Sync.stats.sendErrors or 0)
		assert.is_true(SK.Sync.stats.targetOffline >= 8)
		for _, line in ipairs(W.prints) do assert.is_nil(line:find("Sending to guildmates is failing", 1, true)) end
		_G.ChatThrottleLib = nil
	end)
end)

describe("v0.4.2 profession scans survive an incomplete read", function()
	local SK, W
	local TAILORING = { name = "Tailoring", rank = 85, max = 150, skillLine = 197 }
	local COOKING = { name = "Cooking", rank = 93, max = 150, skillLine = 185 }
	before_each(function()
		SK, W = H.load()
		W.member("Pocus Hocus", W.player.guid)
		W.professions = { TAILORING, COOKING }
		SK.Identity:ReadRoster()
		SK.Profile:BuildSelf()
		local own = SK.Profile:Own()
		own.profs[197].scanned = W.now
		own.recipes[197] = { [3915] = 4344, [2963] = 2996 }
	end)

	it("a profession missing from one read gets its recipes back when it returns", function()
		W.professions = { COOKING } -- the game "forgets" Tailoring for a moment
		SK.Profile:BuildSelf()
		assert.is_nil(SK.Profile:Own().profs[197])
		assert.is_nil(SK.Profile:Own().recipes[197]) -- not shared while it's missing
		W.professions = { TAILORING, COOKING }
		SK.Profile:BuildSelf()
		local own = SK.Profile:Own()
		assert.equal(W.now, own.profs[197].scanned)
		assert.same({ [3915] = 4344, [2963] = 2996 }, own.recipes[197])
		assert.is_nil(SK.DB.scanKeep[W.player.guid]) -- nothing left set aside
		local banner = SK.Professions.Banner(own, SK.DB.settings.share) -- Cooking was never scanned here
		assert.is_nil(banner.text:find("Tailoring", 1, true))
	end)

	it("a profession dropped and started again doesn't get the old recipes", function()
		W.professions = { COOKING }
		SK.Profile:BuildSelf()
		W.professions = { { name = "Tailoring", rank = 1, max = 75, skillLine = 197 }, COOKING }
		SK.Profile:BuildSelf()
		local own = SK.Profile:Own()
		assert.is_nil(own.profs[197].scanned)
		assert.is_nil(own.recipes[197])
	end)
end)
