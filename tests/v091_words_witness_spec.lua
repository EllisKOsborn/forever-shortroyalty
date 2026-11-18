-- v0.9.1 Short Words witnesses: quitting with Alt-F4 (nothing saved) after
-- five guesses used to give a fresh daily game. Guildmates now remember the
-- colours of today's guesses and hand them back after a login.
local H = require("tests.helpers.load")

local BOB = "Player-1-B"

local function setup()
	local SK, W = H.load()
	W.member("Pip", W.player.guid)
	W.member("Bob", BOB)
	SK.Identity:ReadRoster()
	SK.Profile:BuildSelf()
	local sent = H.captureSends(SK)
	return SK, W, sent
end

local function deliver(SK, t, fields, sender, fromGUID)
	SK.Sync:OnCommReceived(SK.PREFIX, H.peerMessage(SK, t, fields, fromGUID, "0.9.1"), "GUILD", sender)
end

local function wrongWords(SW, answer, n)
	local out = {}
	for _, w in ipairs({ "crane", "slate", "fjord", "pious", "dwarf", "nymph", "glyph", "brick" }) do
		if w ~= answer and SW.IsWord(w) and #out < n then out[#out + 1] = w end
	end
	return out
end

local function sentOf(sent, t)
	local out = {}
	for _, s in ipairs(sent) do if s.msg.t == t then out[#out + 1] = s end end
	return out
end

describe("v0.9.1 Short Words: patterns that can be handed back", function()
	it("accepts 1-6 rows of colours, a green row only at the end", function()
		local WS = setup().WordsSync
		assert.equal(1, #WS.Rows("20110"))
		assert.equal(6, #WS.Rows("00000,00000,00000,00000,00000,22222"))
		assert.is_nil(WS.Rows(""))
		assert.is_nil(WS.Rows("22222,00000"))                              -- nothing after a win
		assert.is_nil(WS.Rows("00000,00000,00000,00000,00000,00000,00000")) -- 7 rows
		assert.is_nil(WS.Rows("0011"))
		assert.is_nil(WS.Rows("crane"))                                    -- never letters
		assert.is_nil(WS.Rows(42))
	end)
end)

describe("v0.9.1 Short Words: guesses survive quitting without saving", function()
	local SK, W, sent, SW, WS
	before_each(function()
		SK, W, sent = setup()
		SW, WS = SK.ShortWords, SK.WordsSync
	end)

	it("tells the guild the colours (not the letters) after each daily guess", function()
		local game = SW:Daily(W.now)
		for _, w in ipairs(wrongWords(SW, game.word, 2)) do
			assert.is_true((SW:Play(game, w, W.player.guid, "Pip", W.now)))
		end
		SK.Sync:Flush()
		local wp = sentOf(sent, "WP")
		assert.equal(1, #wp) -- the second guess replaced the first while queued
		assert.equal("GUILD", wp[1].dist)
		assert.equal(SW.Pattern(game.rows), wp[1].msg.c)
		assert.equal(game.day, wp[1].msg.d)
		for _, w in ipairs(wrongWords(SW, game.word, 2)) do assert.is_nil(wp[1].msg.c:find(w, 1, true)) end
	end)

	it("doesn't send anything when 'Share my Short Words results' is off, or for free play", function()
		SK.DB.settings.share.words = false
		local game = SW:Daily(W.now)
		SW:Play(game, wrongWords(SW, game.word, 1)[1], W.player.guid, "Pip", W.now)
		SK.DB.settings.share.words = true
		local free = SW:Free(W.player.guid, W.now)
		SW:Play(free, wrongWords(SW, free.word, 1)[1], W.player.guid, "Pip", W.now)
		SK.Sync:Flush()
		assert.equal(0, #sentOf(sent, "WP"))
	end)

	it("as a witness: remembers a guildmate's colours, the most guesses per day", function()
		local day = SW.Day(W.now)
		deliver(SK, "WP", { d = day, c = "00000,10000" }, "Bob", BOB)
		assert.equal("00000,10000", WS.Witness()[BOB].p)
		deliver(SK, "WP", { d = day, c = "00000" }, "Bob", BOB)          -- fewer: ignored
		assert.equal("00000,10000", WS.Witness()[BOB].p)
		deliver(SK, "WP", { d = day - 5, c = "00000,00000,00000" }, "Bob", BOB) -- old day
		deliver(SK, "WP", { d = day, c = "crane" }, "Bob", BOB)          -- not colours
		assert.equal("00000,10000", WS.Witness()[BOB].p)
		assert.equal(2, WS.stats.rejected)
	end)

	it("as a witness: answers a login question with what it saw", function()
		local day = SW.Day(W.now)
		deliver(SK, "WP", { d = day, c = "00000,10000,11000,21000,22100" }, "Bob", BOB)
		deliver(SK, "WQ", { d = day, k = { BOB, "Player-1-Z" } }, "Bob", BOB)
		W.advance(WS.ANSWER_MAX + 1)
		SK.Sync:Flush()
		local wa = sentOf(sent, "WA")
		assert.equal(1, #wa)
		assert.equal(BOB, wa[1].msg.q)
		assert.same({ [BOB] = "00000,10000,11000,21000,22100" }, wa[1].msg.r)
	end)

	it("as a witness: stays quiet when someone else already answered", function()
		local day = SW.Day(W.now)
		deliver(SK, "WP", { d = day, c = "00000,10000" }, "Bob", BOB)
		deliver(SK, "WQ", { d = day, k = { BOB } }, "Bob", BOB)
		W.member("Cat", "Player-1-C")
		SK.Identity:ReadRoster()
		deliver(SK, "WA", { q = BOB, d = day, r = { [BOB] = "00000,10000" } }, "Cat", "Player-1-C")
		W.advance(WS.ANSWER_MAX + 1)
		SK.Sync:Flush()
		assert.equal(0, #sentOf(sent, "WA"))
	end)

	it("after a quit: five guesses come back, one try is left", function()
		local day = SW.Day(W.now)
		local game = SW:Daily(W.now) -- fresh: the five guesses weren't saved
		assert.equal(0, #game.rows)
		SK.DB.account[W.player.guid] = true
		WS:OnLogin()
		assert.is_true(WS:Checking(W.now))
		local ok, why = SW:Play(game, wrongWords(SW, game.word, 1)[1], W.player.guid, "Pip", W.now)
		assert.is_false(ok)
		assert.equal("checking", why) -- no peeking while the guild answers
		W.advance(WS.ASK_DELAY + 0.1)
		SK.Sync:Flush()
		assert.equal(1, #sentOf(sent, "WQ"))
		local five = "00000,10000,11000,21000,22100"
		deliver(SK, "WA", { q = W.player.guid, d = day, r = { [W.player.guid] = five } }, "Bob", BOB)
		game = SW:Daily(W.now)
		assert.equal(5, #game.rows)
		assert.is_true(game.rows[1].hidden)
		assert.equal("", game.rows[1].w)
		assert.is_false(game.done)
		W.advance(WS.CHECK_FOR + 1)
		assert.is_false(WS:Checking(W.now))
		assert.is_true((SW:Play(game, wrongWords(SW, game.word, 1)[1], W.player.guid, "Pip", W.now)))
		assert.is_true(game.done) -- that was the sixth
		assert.same({}, SW.Keys({ game.rows[1] })) -- no letters on the keyboard from hidden rows
	end)

	it("after a quit on the last guess: the lost game is recorded as lost", function()
		local day = SW.Day(W.now)
		SK.DB.account[W.player.guid] = true
		local six = "00000,10000,11000,21000,22100,22110"
		assert.is_true(WS:Restore(W.player.guid, day, six, W.now))
		local game = SW:Daily(W.now)
		assert.is_true(game.done)
		assert.is_false(game.won)
		assert.equal(1, SW.StatsOf(W.player.guid).ds.n)
		assert.equal(0, SW.StatsOf(W.player.guid).ds.w)
	end)

	it("never replaces a game that has as many guesses or more", function()
		local day = SW.Day(W.now)
		SK.DB.account[W.player.guid] = true
		local game = SW:Daily(W.now)
		for _, w in ipairs(wrongWords(SW, game.word, 2)) do SW.Guess(game, w, W.now) end
		assert.is_false(WS:Restore(W.player.guid, day, "00000,00000", W.now))
		assert.is_false(WS:Restore(W.player.guid, day - 1, "00000,00000,00000", W.now)) -- another day
		assert.is_false(game.rows[1].hidden == true)
	end)

	it("ignores answers about characters that aren't ours", function()
		local day = SW.Day(W.now)
		SK.DB.account[W.player.guid] = true
		deliver(SK, "WA", { q = W.player.guid, d = day, r = { [BOB] = "00000,00000,00000" } }, "Bob", BOB)
		assert.equal(0, #SW:Daily(W.now).rows)
		deliver(SK, "WA", { q = BOB, d = day, r = { [W.player.guid] = "00000,00000,00000" } }, "Bob", BOB)
		assert.equal(0, #SW:Daily(W.now).rows) -- an answer to someone else's question
	end)

	it("doesn't make you wait when nobody can be asked", function()
		SK.DB.settings.share.words = false
		WS:OnLogin()
		W.advance(WS.ASK_DELAY + 0.1)
		assert.is_false(WS:Checking(W.now))
	end)

	it("survives hostile messages", function()
		local day = SW.Day(W.now)
		local big = {}
		for i = 1, 500 do big[i] = "Player-1-" .. i end
		for _, m in ipairs({
			{ "WQ", { d = day, k = big } }, { "WQ", { d = "x", k = {} } }, { "WQ", { d = day, k = "x" } },
			{ "WA", { q = W.player.guid, d = day, r = "x" } }, { "WA", { q = 5, d = day, r = {} } },
			{ "WA", { q = W.player.guid, d = day, r = big } }, { "WP", { d = day } }, { "WP", { d = 1e300, c = "00000" } },
		}) do
			assert.has_no.errors(function() deliver(SK, m[1], m[2], "Bob", BOB) end)
		end
		W.advance(WS.ANSWER_MAX + 1)
		assert.equal(0, #SW:Daily(W.now).rows)
	end)
end)
