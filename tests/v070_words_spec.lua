-- v0.7.0 Short Words: scoring, the daily word, free for all, results,
-- leaderboards, what is shared and how it is checked, and the page.
local H = require("tests.helpers.load")

describe("Short Words rules", function()
	local SK, SW
	before_each(function()
		SK = H.load()
		SW = SK.ShortWords
	end)

	it("colours repeated letters only as often as the answer has them", function()
		assert.equal("22222", SW.Score("crane", "crane"))
		assert.equal("00101", SW.Score("speed", "abide")) -- one e in the answer: the second e is grey
		assert.equal("10102", SW.Score("eerie", "there")) -- green first, then yellows left to right
		assert.equal("11000", SW.Score("llama", "hello"))
		assert.equal("00010", SW.Score("fjord", "baker")) -- r is in baker, elsewhere
		assert.equal("00000", SW.Score("fjord", "smite"))
	end)

	it("knows which words may be guessed", function()
		assert.is_true(SW.IsWord("crane"))
		assert.is_true(SW.IsWord("CRANE"))
		assert.is_true(SW.IsWord("aahed"))   -- first word of the list
		assert.is_true(SW.IsWord("zymes"))   -- last word of the list
		assert.is_false(SW.IsWord("zzzzz"))
		assert.is_false(SW.IsWord("cran"))
		assert.is_false(SW.IsWord("cr4ne"))
	end)

	it("every answer is a valid guess, five letters, and the lists are big enough", function()
		local answers, n = SK.Data.WORDS_ANSWERS, #SK.Data.WORDS_ANSWERS / 5
		assert.equal(0, #answers % 5)
		assert.is_true(n > 1500)               -- over four years of daily words
		assert.is_true(#SK.Data.WORDS_VALID / 5 > 8000)
		for i = 1, n do assert.is_true(SW.IsWord(answers:sub(i * 5 - 4, i * 5)), i) end
	end)

	it("gives the whole guild the same word each UTC day", function()
		assert.equal(1, SW.Day(SW.EPOCH))
		assert.equal(1, SW.Day(SW.EPOCH + 86399))
		assert.equal(2, SW.Day(SW.EPOCH + 86400))
		assert.equal(SW.Answer(5), SW.Answer(5))
		assert.are_not.equal(SW.Answer(1), SW.Answer(2))
		assert.equal(SW.Answer(1), SW.Answer(1 + #SK.Data.WORDS_ANSWERS / 5)) -- starts again after the list
		assert.equal(60, SW.UntilNext(SW.EPOCH + 86340))
	end)

	it("never picks today's word for free play", function()
		local calls = 0
		local w = SW.RandomAnswer(SW.Answer(1), function() calls = calls + 1; return calls == 1 and 1 or 2 end)
		assert.equal(SW.Answer(2), w)
	end)

	it("plays a game: bad words don't use a turn, six tries at most", function()
		local g = SW.NewGame("free", "crane", 1, 100)
		assert.same({ false, "short" }, { SW.Guess(g, "cran", 101) })
		assert.same({ false, "notword" }, { SW.Guess(g, "zzzzz", 101) })
		assert.equal(0, #g.rows)
		for _ = 1, 5 do assert.is_true(SW.Guess(g, "fjord", 102)) end
		assert.is_false(g.done)
		assert.is_true(SW.Guess(g, "slate", 103))
		assert.is_true(g.done)
		assert.is_false(g.won)
		assert.equal(103, g.at)
		assert.same({ false, "done" }, { SW.Guess(g, "crane", 104) })
		local k = SW.Keys(g.rows)
		assert.equal(0, k.f)
		assert.equal(2, k.a) -- a in slate is in the right place for crane
	end)

	it("keeps streaks and averages", function()
		local st = SW.NewStats()
		local function daily(day, won, tries)
			local g = { day = day, won = won, rows = {}, at = day }
			for i = 1, tries do g.rows[i] = { w = "crane", p = i == tries and won and "22222" or "00000" } end
			SW.RecordDaily(st, g)
		end
		daily(1, true, 3); daily(2, true, 4); daily(3, false, 6); daily(5, true, 2); daily(6, true, 2)
		daily(6, true, 1) -- the same day again is ignored
		assert.equal(5, st.ds.n)
		assert.equal(4, st.ds.w)
		assert.equal(11, st.ds.g)
		assert.equal(2, st.ds.cs)
		assert.equal(2, st.ds.bs)
		assert.equal(2, SW.Streak(st.ds, 7))
		assert.equal(0, SW.Streak(st.ds, 8))  -- missed a day: no current streak
		assert.equal(6, st.d.day)
		assert.equal("00000,22222", st.d.p)
		local g = { won = true, rows = { {}, {}, {} } }
		SW.RecordFree(st, g, 9)
		SW.RecordFree(st, { won = false, rows = { {}, {}, {}, {}, {}, {} } }, 9)
		assert.same({ day = 9, n = 2, w = 1, g = 3 }, st.ft)
		assert.equal(1, st.f.best)
		assert.equal(0, st.f.run)
		assert.equal("Short Words #6: 2/6 (streak 2)", SW.ShareText({ day = 6, won = true, rows = { {}, {} } }, 2))
		assert.equal("Short Words #6: X/6", SW.ShareText({ day = 6, won = false, rows = {} }, 0))
	end)

	it("ranks the boards: fewest guesses first today, most wins all time", function()
		local function e(name, words) return { guid = name, name = name, status = "offline", words = words } end
		local entries = {
			e("Ann", { d = { day = 4, g = 3, won = true, p = "", at = 50 }, ds = { n = 4, w = 4, g = 14, cs = 4, bs = 4, last = 4 } }),
			e("Bob", { d = { day = 4, g = 3, won = true, p = "", at = 40 }, ds = { n = 9, w = 6, g = 20, cs = 0, bs = 3, last = 3 } }),
			e("Cat", { d = { day = 4, g = 6, won = false, p = "", at = 10 }, ds = { n = 1, w = 0, g = 0, cs = 0, bs = 0, last = 4 } }),
			e("Dan", { d = { day = 3, g = 1, won = true, p = "", at = 5 } }),   -- yesterday's: not on today's board
			e("Eve", { f = { n = 10, w = 9, g = 30, run = 2, best = 6 }, ft = { day = 4, n = 3, w = 3, g = 9 } }),
			e("Fox", { f = { n = 4, w = 4, g = 20, run = 4, best = 4 }, ft = { day = 3, n = 4, w = 4, g = 20 } }),
		}
		local today = SK.ShortWords.Board(entries, "daily", "today", 4)
		assert.same({ "Bob", "Ann", "Cat" }, { today[1].name, today[2].name, today[3].name }) -- same guesses: first to finish
		local all = SW.Board(entries, "daily", "all", 4)
		assert.same({ "Bob", "Ann", "Cat" }, { all[1].name, all[2].name, all[3].name })
		assert.equal(4, all[2].streak)
		assert.equal(0, all[1].streak)
		local free = SW.Board(entries, "free", "today", 4)
		assert.equal(1, #free)                     -- Fox played yesterday
		assert.equal("Eve", free[1].name)
		local freeAll = SW.Board(entries, "free", "all", 4)
		assert.same({ "Eve", "Fox" }, { freeAll[1].name, freeAll[2].name })
		assert.equal(1, freeAll[1].rank)
	end)
end)

describe("Short Words sharing", function()
	local SK, W
	before_each(function()
		SK, W = H.load()
		W.member("Pip", W.player.guid)
		SK.Identity:ReadRoster()
		SK.Profile:BuildSelf()
	end)

	it("a finished daily game goes into your profile at once, with no letters", function()
		local SW = SK.ShortWords
		local g = SW:Daily(W.now)
		local answer = g.word
		assert.is_true(SW:Play(g, answer, W.player.guid, "Pip", W.now))
		local pub = SK.DBM:Guild().profiles[W.player.guid]
		assert.truthy(pub.words)
		assert.equal(1, pub.words.d.g)
		assert.equal("22222", pub.words.d.p)
		local function noLetters(t)
			for _, v in pairs(t) do
				if type(v) == "table" then noLetters(v)
				elseif type(v) == "string" then assert.is_nil(v:find("%a"), "letters in " .. v) end
			end
		end
		noLetters(pub.words)
		assert.truthy(answer)
		assert.is_true((SK.Merge.Validate(pub)))
	end)

	it("an alt sees the daily game already played on this account", function()
		local SW = SK.ShortWords
		local g = SW:Daily(W.now)
		SW:Play(g, "fjord" ~= g.word and "fjord" or "slate", W.player.guid, "Pip", W.now)
		assert.same({ false, "other" }, { SW:Play(SW:Daily(W.now), "crane", "Player-1-ALT", "Alt", W.now) })
	end)

	it("Share my Short Words results off keeps them out of what is sent", function()
		local SW = SK.ShortWords
		local g = SW:Daily(W.now)
		SW:Play(g, g.word, W.player.guid, "Pip", W.now)
		SK.DB.settings.share.words = false
		SK.Profile:BuildSelf()
		assert.is_nil(SK.DBM:Guild().profiles[W.player.guid].words)
		assert.truthy(SK.Profile:Own().words) -- still kept on your own computer
	end)

	it("rejects malformed results from others, accepts good ones", function()
		local V = SK.Merge.FIELDS.words
		assert.is_true(V(nil))
		assert.is_true(V({ d = { day = 3, g = 4, won = true, p = "20110,22222", at = 123 },
			ds = { n = 3, w = 2, g = 7, cs = 1, bs = 2, last = 3 }, f = { n = 1, w = 1, g = 3, run = 1, best = 1 },
			ft = { day = 3, n = 1, w = 1, g = 3 } }))
		assert.is_false(V({ d = { p = "crane" } }))            -- letters are never accepted
		assert.is_false(V({ d = { g = 2.5 } }))
		assert.is_false(V({ ds = { n = -1 } }))
		assert.is_false(V({ ds = { evil = 1 } }))
		assert.is_false(V({ x = {} }))
		assert.is_false(V("words"))
	end)
end)

describe("Short Words page", function()
	local SK, W
	before_each(function()
		SK, W = H.load()
		H.loadUI(SK)
		W.member("Pip", W.player.guid)
		W.member("Bob", "Player-1-B", { online = true })
		SK.Identity:ReadRoster()
		SK.Profile:BuildSelf()
	end)

	it("is in the sidebar under Games, and /sr words opens it", function()
		SK.Commands.Run("words")
		assert.equal("words", SK.MainFrame.current)
		assert.equal("SHORT WORDS", SK.MainFrame.frame.pageTitle:GetText())
	end)

	it("types with the keys, rejects made-up words, and solves the daily word", function()
		SK.MainFrame:Show("words")
		local P = SK.WordsTab
		for l in ("zzzzz"):gmatch(".") do P:Type(l) end
		P:Submit()
		assert.equal("Not in the word list.", P.message:GetText())
		for _ = 1, 5 do P:Type(nil) end
		local word = SK.ShortWords:Daily(W.now).word
		for l in word:gmatch(".") do P:Type(l) end
		assert.equal(word:sub(1, 1):upper(), P.tiles[1][1].letter:GetText())
		P:Submit()
		assert.truthy(P.message:GetText():find("Solved in 1", 1, true))
		assert.is_true(P.share:IsShown())
		P:Share()
		assert.truthy(W.chat[#W.chat][2]:find("Short Words #", 1, true))
		-- you're on today's board
		local list = P.lists.daily_today
		assert.equal(1, #list.items)
		assert.equal(W.player.guid, list.items[1].guid)
	end)

	it("free for all keeps going, and has its own boards", function()
		SK.DB.settings.wordsView = "free"
		SK.MainFrame:Show("words")
		local P = SK.WordsTab
		local first = SK.ShortWords:Free(W.player.guid, W.now).word
		for l in first:gmatch(".") do P:Type(l) end
		P:Submit()
		assert.is_true(P.nextWord:IsShown())
		P:Next()
		assert.is_false(SK.ShortWords:Free(W.player.guid, W.now).done)
		assert.is_true(P.lists.free_today:IsShown())
		SK.DB.settings.wordsBoard = "all"
		P:Refresh()
		assert.is_true(P.lists.free_all:IsShown())
		assert.equal(1, #P.lists.free_all.items)
	end)

	it("shows a guildmate's result from their profile", function()
		local SW = SK.ShortWords
		local guild = SK.DBM:Guild()
		guild.profiles["Player-1-B"] = { guid = "Player-1-B", name = "Bob",
			words = { d = { day = SW.Day(W.now), g = 4, won = true, p = "00100,01100,20220,22222", at = W.now } } }
		SK.MainFrame:Show("words")
		local items = SK.WordsTab.lists.daily_today.items
		assert.equal(1, #items)
		assert.equal("Bob", items[1].name)
		assert.equal(4, #SK.WordsTab.PatternLines(items[1].p))
	end)
end)

describe("v0.7.1 Short Words guild streak", function()
	local SK, W
	before_each(function()
		SK, W = H.load()
	end)

	it("counts days in a row with at least 3 players, and doesn't break today while it's still going", function()
		local SW = SK.ShortWords
		local function e(days) return { wd = days } end
		local entries = { e({ 1, 2, 3, 4, 5 }), e({ 2, 3, 4, 5, 6 }), e({ 3, 4, 5, 6 }), e({ 4, 5 }), e({ 6, 6 }) }
		local counts = SW.GuildCounts(entries)
		assert.equal(2, counts[2])
		assert.equal(3, counts[6]) -- a day listed twice by one player counts once
		assert.same({ 4, 3 }, { SW.GuildStreak(counts, 6, 3) })  -- days 3, 4, 5, 6
		assert.same({ 4, 0 }, { SW.GuildStreak(counts, 7, 3) })  -- day 7 has nobody yet: still 4
		assert.same({ 0, 0 }, { SW.GuildStreak(counts, 8, 3) })  -- day 7 missed: gone
		assert.same({ 5, 3 }, { SW.GuildStreak(counts, 6, 2) })  -- the minimum is a setting
	end)

	it("keeps a local record so the streak can outlast what profiles carry", function()
		local SW = SK.ShortWords
		SK.DB.words.guildDays = { [1] = 3, [2] = 4 }
		local entries = { { wd = { 3 } }, { wd = { 3 } }, { wd = { 3 } } }
		local streak, played, best = SW:GuildStreakNow(entries, 3)
		assert.same({ 3, 3, 3 }, { streak, played, best })
		H.loadUI(SK)
		local text = SK.WordsTab.GuildStreakText(3, 3, 3)
		assert.truthy(text:find("Short Words #3  ·  Guild streak ", 1, true))
		assert.truthy(text:find("3 days", 1, true))
		assert.is_nil(text:find("played today", 1, true)) -- enough players today: no count
	end)

	it("says how many have played today until there are enough", function()
		H.loadUI(SK)
		local text = SK.WordsTab.GuildStreakText(9, 0, 1)
		assert.truthy(text:find("1 of 3 played today", 1, true))
		assert.truthy(SK.ShortWords.ShareText({ day = 9, won = true, rows = { {}, {}, {} } }, 2, 5):find("· guild streak 5", 1, true))
	end)

	it("shares the days played beside the results, and a v0.7.0 player still accepts the profile", function()
		local SW = SK.ShortWords
		W.member("Pip", W.player.guid)
		SK.Identity:ReadRoster()
		SK.Profile:BuildSelf()
		local g = SW:Daily(W.now)
		SW:Play(g, g.word, W.player.guid, "Pip", W.now)
		local pub = SK.DBM:Guild().profiles[W.player.guid]
		assert.same({ SW.Day(W.now) }, pub.wd)
		assert.is_nil(pub.words.days)          -- never inside `words`
		assert.is_true((SK.Merge.Validate(pub)))
		-- v0.7.0's check of `words` only knows d, ds, f, ft: still true for this profile
		for k in pairs(pub.words) do assert.truthy(({ d = 1, ds = 1, f = 1, ft = 1 })[k], k) end
		assert.is_false(SK.Merge.FIELDS.wd({ "x" }))
		assert.is_false(SK.Merge.FIELDS.wd({ [99] = 3 }))
		assert.is_true(SK.Merge.FIELDS.wd({ 1, 2, 3 }))
		SK.DB.settings.share.words = false
		SK.Profile:BuildSelf()
		assert.is_nil(SK.DBM:Guild().profiles[W.player.guid].wd)
	end)

	it("results saved by v0.7.0 (no days list) start the list from today's result", function()
		local SW = SK.ShortWords
		SK.DB.words.chars["G-1"] = { d = { day = 2, g = 3, won = true, p = "22222", at = 1 },
			ds = { n = 1, w = 1, g = 3, cs = 1, bs = 1, last = 2 }, f = { n = 0, w = 0, g = 0, run = 0, best = 0 } }
		assert.same({ 2 }, SW.DaysField("G-1"))
		assert.is_nil(SW.DaysField("nobody"))
	end)
end)
