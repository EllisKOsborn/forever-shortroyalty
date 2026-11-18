-- Short Words witnesses (v0.9.1). Addon data is only saved when the game
-- logs out or reloads, so quitting with Alt-F4 after five guesses used to
-- give a fresh daily game (guild report, 18 Nov 2026). Guildmates now
-- remember the colour patterns of today's daily guesses (never the
-- letters) and hand them back after a login.
--
--   WP  GUILD  after each daily guess { d = day, c = "20110,22222" }
--              (`p` is taken: every message carries the protocol there)
--   WQ  GUILD  ~12 s after login { d = day, k = { our account's GUIDs } }
--   WA  GUILD  answer to a WQ { q = asker GUID, d = day, r = { [guid] = p } },
--              after a random 2-6 s; skipped when someone else already
--              answered with as many guesses.
--
-- The daily game waits ("Checking today's guesses…") until the answers are
-- in, at most CHECK_FOR seconds. A witnessed game with more guesses than
-- ours replaces it; the restored rows keep their colours, not their letters.
-- Limits: needs someone with the addon online at both times; nothing is
-- sent while sync is paused (combat, instances) or when "Share my Short
-- Words results" is off.
local _, SK = ...

local WS = SK:NewModule("WordsSync")
SK.WordsSync = WS
local Compat = SK.Compat

WS.ASK_DELAY = 12          -- WQ this long after login
WS.CHECK_FOR = 10          -- wait this long for answers after the WQ
WS.ANSWER_MIN, WS.ANSWER_MAX = 2, 6
WS.MAX_KEYS = 20           -- account characters per WQ

WS.checkingUntil = nil     -- daily play waits until this time (login check)
WS.answered = {}           -- asker guid -> most rows someone answered (suppresses ours)
WS.stats = { sentWP = 0, sentWQ = 0, sentWA = 0, gotWP = 0, gotWA = 0, restored = 0, rejected = 0 }

---------------------------------------------------------------------------
-- Pure helpers (tested)
---------------------------------------------------------------------------
-- A daily pattern so far: 1-6 rows of five 0/1/2, comma-separated; only the
-- last row may be all green. Returns the rows or nil.
function WS.Rows(p)
	if type(p) ~= "string" or #p > 41 then return nil end
	local rows = {}
	for row in (p .. ","):gmatch("([^,]*),") do
		if not row:match("^[012][012][012][012][012]$") then return nil end
		rows[#rows + 1] = row
	end
	if #rows < 1 or #rows > SK.ShortWords.TRIES then return nil end
	for i = 1, #rows - 1 do
		if rows[i] == "22222" then return nil end
	end
	return rows
end

-- Is `d` about today? Yesterday (a guess just before UTC midnight) and
-- tomorrow (a guildmate whose clock is a little ahead) count too.
function WS.RecentDay(d, today)
	return type(d) == "number" and d % 1 == 0 and d >= today - 1 and d <= today + 1
end

-- The game rebuilt from a witnessed pattern: rows with colours and no letters.
function WS.Rebuild(game, p, now)
	local rows = WS.Rows(p)
	if not rows then return false end
	game.rows = {}
	for i, row in ipairs(rows) do game.rows[i] = { w = "", p = row, hidden = true } end
	game.won = rows[#rows] == "22222"
	game.done = game.won or #rows >= SK.ShortWords.TRIES
	if game.done then game.at = game.at or now end
	return true
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
-- What we've seen others play: SK.DB.words.witness[guid] = { d, p, at }
function WS.Witness()
	local db = SK.ShortWords.Store()
	db.witness = db.witness or {}
	return db.witness
end

function WS.Prune(today)
	local w = WS.Witness()
	for guid, e in pairs(w) do
		if type(e) ~= "table" or not WS.RecentDay(e.d, today) then w[guid] = nil end
	end
end

function WS:Checking(now)
	return self.checkingUntil ~= nil and (now or Compat.Now()) < self.checkingUntil
end

local function shareOn()
	local s = SK.DB.settings.share
	return not (s and s.words == false) and SK.Sync:Enabled()
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
-- After a daily guess: tell the guild the colours so far.
function WS:SendProgress(game)
	if not game or game.mode ~= "daily" or #game.rows == 0 or not shareOn() then return false end
	local p = SK.ShortWords.Pattern(game.rows)
	if not WS.Rows(p) then return false end
	self.stats.sentWP = self.stats.sentWP + 1
	-- One key: a newer pattern replaces one still waiting in the queue.
	return SK.Sync:Enqueue("WP", "GUILD", nil, "NORMAL", { t = "WP", d = game.day, c = p }) ~= nil
end

-- After login: ask the guild what they saw us play today.
function WS:SendQuery(now)
	now = now or Compat.Now()
	if not shareOn() or not SK.Sync:CanSend() or SK.Sync:IsPaused() then
		self.checkingUntil = nil -- nobody can answer: don't make the player wait
		return false
	end
	local k = {}
	for guid in pairs(SK.DB.account) do
		if #k < WS.MAX_KEYS then k[#k + 1] = guid end
	end
	table.sort(k)
	if #k == 0 then self.checkingUntil = nil return false end
	self.stats.sentWQ = self.stats.sentWQ + 1
	self.checkingUntil = now + WS.CHECK_FOR
	SK.Sync:Enqueue("WQ", "GUILD", nil, "NORMAL", { t = "WQ", d = SK.ShortWords.Day(now), k = k })
	SK.After(WS.CHECK_FOR + 0.5, function() SK:Fire("WORDS_UPDATED") end)
	SK:Fire("WORDS_UPDATED")
	return true
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
function WS:HandleWP(msg, from, now)
	local today = SK.ShortWords.Day(now)
	local rows = WS.Rows(msg.c)
	if not rows or not WS.RecentDay(msg.d, today) or not SK.Identity:IsMember(from) then
		self.stats.rejected = self.stats.rejected + 1
		return false
	end
	self.stats.gotWP = self.stats.gotWP + 1
	local w = WS.Witness()
	local held = w[from]
	local heldRows = held and held.d == msg.d and WS.Rows(held.p)
	-- Keep the most guesses seen for a day (a game only grows).
	if heldRows and #heldRows >= #rows then return false end
	if held and held.d and held.d > msg.d then return false end
	w[from] = { d = msg.d, p = msg.c, at = now }
	return true
end

function WS:HandleWQ(msg, from)
	if type(msg.k) ~= "table" or type(msg.d) ~= "number" then return end
	local w = WS.Witness()
	local r, most, n = {}, 0, 0
	for _, guid in ipairs(msg.k) do
		n = n + 1
		if n > WS.MAX_KEYS then break end
		local e = type(guid) == "string" and w[guid]
		local rows = e and e.d == msg.d and WS.Rows(e.p)
		if rows then
			r[guid] = e.p
			if #rows > most then most = #rows end
		end
	end
	if most == 0 then return end
	self.answered[from] = nil
	SK.After(WS.ANSWER_MIN + math.random() * (WS.ANSWER_MAX - WS.ANSWER_MIN), function()
		-- Someone else already answered with as many guesses: ours adds nothing.
		if (self.answered[from] or 0) >= most then return end
		self.stats.sentWA = self.stats.sentWA + 1
		SK.Sync:Enqueue("WA:" .. from, "GUILD", nil, "NORMAL", { t = "WA", q = from, d = msg.d, r = r })
	end)
end

-- Answers to anyone's WQ: ours restore the game; others' suppress our answer.
function WS:HandleWA(msg, _, now)
	if type(msg.q) ~= "string" or type(msg.r) ~= "table" or type(msg.d) ~= "number" then return end
	local most, n = 0, 0
	local best
	for guid, p in pairs(msg.r) do
		n = n + 1
		if n > WS.MAX_KEYS then break end
		local rows = type(guid) == "string" and WS.Rows(p)
		if rows then
			if #rows > most then most = #rows end
			if SK.DB.account[guid] and (not best or #rows > #best.rows) then best = { guid = guid, p = p, rows = rows } end
		end
	end
	if most > (self.answered[msg.q] or 0) then self.answered[msg.q] = most end
	if not SK.DB.account[msg.q] then return end
	self.stats.gotWA = self.stats.gotWA + 1
	if best then self:Restore(best.guid, msg.d, best.p, now) end
end

-- A witnessed daily game with more guesses than ours replaces it.
function WS:Restore(guid, day, p, now)
	local SW = SK.ShortWords
	if day ~= SW.Day(now) then return false end
	local rows = WS.Rows(p)
	local game = SW:Daily(now)
	if not rows or #rows <= #game.rows then return false end
	if not WS.Rebuild(game, p, now) then return false end
	local m = SK.Identity:Member(guid)
	game.guid, game.name = guid, (m and m.name) or game.name
	self.stats.restored = self.stats.restored + 1
	if game.done then
		SW.RecordDaily(SW.StatsOf(guid), game)
		SW:Publish(true)
	end
	SK:Print("Short Words: brought back %d guess%s on today's word from the guild.", #rows, #rows == 1 and "" or "es")
	SK:Fire("WORDS_UPDATED")
	return true
end

SK.Sync.handlers.WP = function(_, msg, from, dist)
	if dist == "GUILD" then WS:HandleWP(msg, from, Compat.Now()) end
end
SK.Sync.handlers.WQ = function(_, msg, from, dist)
	if dist == "GUILD" then WS:HandleWQ(msg, from) end
end
SK.Sync.handlers.WA = function(_, msg, from, dist)
	if dist == "GUILD" then WS:HandleWA(msg, from, Compat.Now()) end
end

function WS:OnLogin()
	local now = Compat.Now()
	WS.Prune(SK.ShortWords.Day(now))
	-- Daily play waits for the check (plus the time it takes to ask).
	self.checkingUntil = now + WS.ASK_DELAY + WS.CHECK_FOR
	SK.After(WS.ASK_DELAY, function() self:SendQuery() end)
end
