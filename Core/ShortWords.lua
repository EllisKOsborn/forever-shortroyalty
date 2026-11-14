-- Short Words (v0.7.0): a five-letter word game with a guild leaderboard.
-- Two modes: Daily (the same word for the whole guild each UTC day) and
-- Free for all (a random word, as many as you like). Six guesses each.
--
-- Saved (local, SK.DB.words):
--   daily = { day, guid, name, rows = { { w, p } }, done, won, at }
--           today's daily game, account-wide: once one character has started
--           it, alts see that game instead of a fresh one (no replays).
--   free  = { [guid] = game }  each character's current free game
--   chars = { [guid] = stats } each character's results (below)
-- Shared with the guild in the profile field `words` (Profile.Public drops
-- it when "Share my Short Words results" is off). Only results and the
-- colour pattern are shared, never the letters:
--   d  = { day, g, won, p, at }       today's daily: g = guesses used,
--                                     p = "20110,22222" (2 right place,
--                                     1 wrong place, 0 not in the word)
--   ds = { n, w, g, cs, bs, last }    daily all time: played, won, guesses
--                                     over the wins, current and best streak,
--                                     last day played
--   f  = { n, w, g, run, best }       free all time (run = wins in a row)
--   ft = { day, n, w, g }             free today
-- Everything here is pure apart from SW:* methods that read SK.DB; tested.
local _, SK = ...

local SW = SK:NewModule("ShortWords")
SK.ShortWords = SW

SW.LEN, SW.TRIES = 5, 6
SW.EPOCH = 1794528000      -- 13 Nov 2026 00:00 UTC = Short Words #1
SW.FREE_PUBLISH = 120      -- free-for-all results reach the guild at most every 2 minutes
SW.GUILD_MIN = 3           -- v0.7.1: players a day needs for the guild streak
SW.HISTORY = 60            -- v0.7.1: daily words played that each profile lists (`wd`)

---------------------------------------------------------------------------
-- Words
---------------------------------------------------------------------------
local function count(list) return math.floor(#list / SW.LEN) end
local function at(list, i) return list:sub((i - 1) * SW.LEN + 1, i * SW.LEN) end

-- Day number: 1 on the first day, a new one every UTC midnight.
function SW.Day(now)
	return math.max(1, math.floor((now - SW.EPOCH) / 86400) + 1)
end

-- Seconds until the next word.
function SW.UntilNext(now)
	return 86400 - ((now - SW.EPOCH) % 86400)
end

function SW.Answer(day)
	local list = SK.Data.WORDS_ANSWERS
	return at(list, (day - 1) % count(list) + 1)
end

-- A random answer, never `exclude` (today's daily). rand(n) -> 1..n.
function SW.RandomAnswer(exclude, rand)
	local list = SK.Data.WORDS_ANSWERS
	local n = count(list)
	for _ = 1, 20 do
		local w = at(list, rand(n))
		if w ~= exclude then return w end
	end
	return at(list, 1) ~= exclude and at(list, 1) or at(list, 2)
end

-- Is it a word you may guess? Binary search in the sorted VALID string.
function SW.IsWord(word)
	if type(word) ~= "string" or not word:match("^%a%a%a%a%a$") then return false end
	word = word:lower()
	local list = SK.Data.WORDS_VALID
	local lo, hi = 1, count(list)
	while lo <= hi do
		local mid = math.floor((lo + hi) / 2)
		local w = at(list, mid)
		if w == word then return true end
		if w < word then lo = mid + 1 else hi = mid - 1 end
	end
	return false
end

-- Colours for a guess: "2" right letter right place, "1" in the word
-- elsewhere, "0" not (or not that many times). Repeated letters count
-- only as often as the answer has them, greens first.
function SW.Score(guess, answer)
	guess, answer = guess:lower(), answer:lower()
	local out, left = {}, {}
	for i = 1, SW.LEN do
		local g, a = guess:sub(i, i), answer:sub(i, i)
		if g == a then out[i] = "2" else out[i] = "0"; left[a] = (left[a] or 0) + 1 end
	end
	for i = 1, SW.LEN do
		local g = guess:sub(i, i)
		if out[i] == "0" and (left[g] or 0) > 0 then
			out[i] = "1"
			left[g] = left[g] - 1
		end
	end
	return table.concat(out)
end

-- Best colour seen per letter (for the keyboard): { a = 2, e = 0, ... }.
function SW.Keys(rows)
	local keys = {}
	for _, r in ipairs(rows or {}) do
		for i = 1, SW.LEN do
			local l, s = r.w:sub(i, i), tonumber(r.p:sub(i, i))
			if not keys[l] or s > keys[l] then keys[l] = s end
		end
	end
	return keys
end

-- "20110,22222"
function SW.Pattern(rows)
	local p = {}
	for i, r in ipairs(rows or {}) do p[i] = r.p end
	return table.concat(p, ",")
end

---------------------------------------------------------------------------
-- A game
---------------------------------------------------------------------------
function SW.NewGame(mode, word, day, now)
	return { mode = mode, word = word, day = day, rows = {}, done = false, won = false, started = now }
end

-- Try a guess. Returns true, or false and why ("done", "short", "notword").
function SW.Guess(game, word, now)
	if game.done then return false, "done" end
	word = (word or ""):lower()
	if #word ~= SW.LEN then return false, "short" end
	if not SW.IsWord(word) and word ~= game.word then return false, "notword" end
	local p = SW.Score(word, game.word)
	game.rows[#game.rows + 1] = { w = word, p = p }
	if p == "22222" then
		game.done, game.won = true, true
	elseif #game.rows >= SW.TRIES then
		game.done = true
	end
	if game.done then game.at = now end
	return true
end

---------------------------------------------------------------------------
-- Results
---------------------------------------------------------------------------
function SW.NewStats()
	return { ds = { n = 0, w = 0, g = 0, cs = 0, bs = 0, last = 0 }, f = { n = 0, w = 0, g = 0, run = 0, best = 0 } }
end

-- Record a finished daily game in a character's stats.
function SW.RecordDaily(stats, game)
	local ds = stats.ds
	if ds.last == game.day then return stats end -- already counted
	local tries = #game.rows
	ds.n = ds.n + 1
	if game.won then
		ds.w = ds.w + 1
		ds.g = ds.g + tries
		ds.cs = (ds.last == game.day - 1 and ds.cs or 0) + 1
		if ds.cs > ds.bs then ds.bs = ds.cs end
	else
		ds.cs = 0
	end
	ds.last = game.day
	stats.d = { day = game.day, g = tries, won = game.won, p = SW.Pattern(game.rows), at = game.at }
	-- v0.7.1: the days played, newest last, for the guild streak (shared as
	-- the profile's `wd`, not inside `words`: v0.7.0 rejects new keys there).
	stats.days = stats.days or {}
	stats.days[#stats.days + 1] = game.day
	while #stats.days > SW.HISTORY do table.remove(stats.days, 1) end
	return stats
end

function SW.RecordFree(stats, game, today)
	local f = stats.f
	local tries = #game.rows
	f.n = f.n + 1
	if game.won then
		f.w, f.g, f.run = f.w + 1, f.g + tries, f.run + 1
		if f.run > f.best then f.best = f.run end
	else
		f.run = 0
	end
	if not stats.ft or stats.ft.day ~= today then stats.ft = { day = today, n = 0, w = 0, g = 0 } end
	local ft = stats.ft
	ft.n = ft.n + 1
	if game.won then ft.w, ft.g = ft.w + 1, ft.g + tries end
	return stats
end

-- Average guesses over the wins ("3.4"), or nil.
function SW.Average(won, guesses)
	if not won or won == 0 then return nil end
	return guesses / won
end

-- The current daily streak still counts if the last game was today or yesterday.
function SW.Streak(ds, today)
	if not ds or (ds.last or 0) < today - 1 then return 0 end
	return ds.cs or 0
end

-- "Short Words #12: 4/6 (streak 3) · guild streak 5" for guild chat.
function SW.ShareText(game, streak, guildStreak)
	local result = game.won and (#game.rows .. "/" .. SW.TRIES) or ("X/" .. SW.TRIES)
	local text = "Short Words #" .. game.day .. ": " .. result
	if streak and streak > 1 then text = text .. " (streak " .. streak .. ")" end
	if guildStreak and guildStreak > 1 then text = text .. " · guild streak " .. guildStreak end
	return text
end

---------------------------------------------------------------------------
-- Guild streak (v0.7.1): days in a row on which at least GUILD_MIN
-- guildmates played the daily word (won or not). Today counts once it has
-- enough players; until then the streak runs to yesterday, so it never
-- breaks while the day is still going.
---------------------------------------------------------------------------
-- Players per day from everyone's `wd` lists. The daily word is
-- account-wide, so each player counts once a day even with alts.
function SW.GuildCounts(entries)
	local counts = {}
	for _, e in ipairs(entries) do
		local seen = {}
		for _, day in ipairs(e.wd or {}) do
			if type(day) == "number" and not seen[day] then
				seen[day] = true
				counts[day] = (counts[day] or 0) + 1
			end
		end
	end
	return counts
end

-- Pure: streak length and today's player count from per-day counts.
function SW.GuildStreak(counts, today, min)
	min = min or SW.GUILD_MIN
	local day = (counts[today] or 0) >= min and today or today - 1
	local streak = 0
	while (counts[day] or 0) >= min do
		streak = streak + 1
		day = day - 1
	end
	return streak, counts[today] or 0
end

-- The guild streak as this computer knows it: today's counts merged into a
-- local record of every day seen (SK.DB.words.guildDays), so the streak can
-- run longer than the HISTORY each profile carries. Returns streak, played
-- today, best streak seen.
function SW:GuildStreakNow(entries, today)
	local db = SW.Store()
	db.guildDays = db.guildDays or {}
	for day, n in pairs(SW.GuildCounts(entries)) do
		if n > (db.guildDays[day] or 0) then db.guildDays[day] = n end
	end
	for day in pairs(db.guildDays) do
		if day < today - 400 then db.guildDays[day] = nil end -- keep about a year
	end
	local streak, played = SW.GuildStreak(db.guildDays, today)
	if streak > (db.guildBest or 0) then db.guildBest = streak end
	return streak, played, db.guildBest or 0
end

---------------------------------------------------------------------------
-- Leaderboards. entries = { { guid, name, class, status, words }, ... }
-- mode "daily" | "free", period "today" | "all". Returns sorted rows with
-- rank and the numbers each board shows.
---------------------------------------------------------------------------
local function byName(a, b) return (a.name or ""):lower() < (b.name or ""):lower() end

function SW.Board(entries, mode, period, today)
	local rows = {}
	for _, e in ipairs(entries) do
		local w = e.words
		local r = { guid = e.guid, name = e.name, class = e.class, status = e.status }
		local keep = false
		if type(w) == "table" then
			if mode == "daily" and period == "today" then
				local d = w.d
				if d and d.day == today then
					keep = true
					r.won, r.g, r.p, r.at = d.won, d.g, d.p, d.at
				end
			elseif mode == "daily" then
				local ds = w.ds
				if ds and (ds.n or 0) > 0 then
					keep = true
					r.n, r.w, r.avg = ds.n, ds.w, SW.Average(ds.w, ds.g)
					r.streak, r.best = SW.Streak(ds, today), ds.bs or 0
				end
			elseif period == "today" then
				local ft = w.ft
				if ft and ft.day == today and (ft.n or 0) > 0 then
					keep = true
					r.n, r.w, r.avg = ft.n, ft.w, SW.Average(ft.w, ft.g)
				end
			else
				local f = w.f
				if f and (f.n or 0) > 0 then
					keep = true
					r.n, r.w, r.avg, r.best = f.n, f.w, SW.Average(f.w, f.g), f.best or 0
				end
			end
		end
		if keep then rows[#rows + 1] = r end
	end
	if mode == "daily" and period == "today" then
		table.sort(rows, function(a, b)
			if a.won ~= b.won then return a.won end
			if a.g ~= b.g then return (a.won and a.g < b.g) or (not a.won and a.g > b.g) end
			if (a.at or 0) ~= (b.at or 0) then return (a.at or 0) < (b.at or 0) end
			return byName(a, b)
		end)
	else
		table.sort(rows, function(a, b)
			if a.w ~= b.w then return a.w > b.w end
			local x, y = a.avg or 99, b.avg or 99
			if x ~= y then return x < y end
			if a.n ~= b.n then return a.n < b.n end
			return byName(a, b)
		end)
	end
	for i, r in ipairs(rows) do r.rank = i end
	return rows
end

---------------------------------------------------------------------------
-- Your games (SK.DB.words)
---------------------------------------------------------------------------
function SW.Store()
	local db = SK.DB.words
	db.chars = db.chars or {}
	db.free = db.free or {}
	return db
end

function SW.StatsOf(guid)
	local db = SW.Store()
	db.chars[guid] = db.chars[guid] or SW.NewStats()
	return db.chars[guid]
end

-- What goes into this character's profile (nil = never played). The days
-- list goes separately (DaysField): v0.7.0 rejects new keys in `words`.
function SW.Field(guid)
	local st = guid and SW.Store().chars[guid]
	if not st then return nil end
	local copy = SK.CopyTable(st)
	copy.days = nil
	return copy
end

-- The profile's `wd`: daily words played (day numbers, newest last).
-- Results from v0.7.0 had no list: today's result seeds it.
function SW.DaysField(guid)
	local st = guid and SW.Store().chars[guid]
	if not st then return nil end
	if not st.days and st.d and st.d.day then st.days = { st.d.day } end
	if not st.days or #st.days == 0 then return nil end
	return SK.CopyTable(st.days)
end

-- Today's daily game (account-wide). A new one each day.
function SW:Daily(now)
	local db = SW.Store()
	local today = SW.Day(now)
	if not db.daily or db.daily.day ~= today then
		db.daily = SW.NewGame("daily", SW.Answer(today), today, now)
	end
	return db.daily
end

-- This character's free game (a new one when there is none).
function SW:Free(guid, now)
	local db = SW.Store()
	if not db.free[guid] then
		local today = SW.Day(now)
		db.free[guid] = SW.NewGame("free", SW.RandomAnswer(SW.Answer(today), math.random), today, now)
	end
	return db.free[guid]
end

function SW:NextFree(guid, now)
	SW.Store().free[guid] = nil
	return self:Free(guid, now)
end

-- Guess on behalf of the logged-in character. Records and publishes a
-- finished game. Returns ok, why.
function SW:Play(game, word, guid, name, now)
	if game.mode == "daily" and game.guid and game.guid ~= guid then return false, "other" end
	local ok, why = SW.Guess(game, word, now)
	if not ok then return false, why end
	if game.mode == "daily" then game.guid, game.name = guid, name end
	if game.done then
		local stats = SW.StatsOf(guid)
		if game.mode == "daily" then
			SW.RecordDaily(stats, game)
			self:Publish(true)
		else
			SW.RecordFree(stats, game, SW.Day(now))
			self:Publish(false)
		end
	end
	SK:Fire("WORDS_UPDATED")
	return true
end

-- Put the results in this character's profile: at once for the daily word,
-- at most every FREE_PUBLISH seconds for free play (each profile change is
-- sent to every guildmate who has the addon).
function SW:Publish(now)
	local function go() if SK.Profile and SK.Profile.SetWords then SK.Profile:SetWords() end end
	if now then go() else SK:Debounce("shortwords", SW.FREE_PUBLISH, go) end
end

-- Leaderboard entries from the guild's profiles (and your own).
function SW.Entries(guild, now)
	local out = {}
	if not guild then return out end
	for guid, m in pairs(guild.members) do
		if not m.leftAt then
			local p = SK.Profile:Get(guid, guild)
			local words, wd = p and p.words, p and p.wd
			if SK.DB.account[guid] then words, wd = SW.Field(guid) or words, SW.DaysField(guid) or wd end
			if words or wd then
				out[#out + 1] = { guid = guid, name = m.name or (p and p.name) or "?", class = m.class or (p and p.class),
					status = SK.Identity.Status(m, SK.DB.account[guid] and m.online, now), words = words,
					wd = type(wd) == "table" and wd or nil }
			end
		end
	end
	return out
end
