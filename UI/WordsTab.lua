-- Short Words page (v0.7.0): the board and keyboard on the left, the
-- leaderboard on the right. Page tabs: Daily (one word a day for the whole
-- guild) and Free for all (keep going). Leaderboards: Today and All time,
-- for the mode you're on. Rules and results live in Core/ShortWords.lua.
--
-- Typing: click the board and an (invisible) edit box takes the keyboard
-- until you press Esc or leave the page, so your movement keys are only
-- borrowed while you choose to type. The on-screen keys work too.
local _, SK = ...

local Words = SK:NewModule("WordsTab")
local Theme, W, Compat = SK.Theme, SK.Widgets, SK.Compat
local SW = SK.ShortWords
local S, SP = Theme.SIZES, Theme.SPACE

Words.VIEWS = { { "daily", "Daily" }, { "free", "Free for all" } }
Words.BOARDS = { { "today", "Today" }, { "all", "All time" } }
Words.LEFT_W = 10 * S.key[1] + 9 * SP.xs                       -- the keyboard's width (296)
Words.RIGHT_W = S.contentW - Words.LEFT_W - SP.xl - SP.xs       -- leaderboard (424)
local TILE, GAP = S.tile, SP.xs + 1
local KEY_ROWS = { "qwertyuiop", "asdfghjkl", "zxcvbnm" }
local TONE = { [0] = "wordMiss", [1] = "wordNear", [2] = "wordHit" }

---------------------------------------------------------------------------
-- Leaderboard columns (424 - 12 = 412) and cells
---------------------------------------------------------------------------
local function avg(v) return v and string.format("%.1f", v) or Theme.DASH end
local function pct(r) return r.n > 0 and (math.floor(r.w / r.n * 100 + 0.5) .. "%") or Theme.DASH end

Words.COLUMNS = {
	daily_today = {
		{ key = "rank", title = "#", width = 32, align = "RIGHT" }, { key = "name", title = "Name", width = 200 },
		{ key = "result", title = "Result", width = 80, align = "RIGHT" }, { key = "when", title = "Finished", width = 100, align = "RIGHT" },
	},
	daily_all = {
		{ key = "rank", title = "#", width = 32, align = "RIGHT" }, { key = "name", title = "Name", width = 140 },
		{ key = "won", title = "Won", width = 50, align = "RIGHT" }, { key = "pct", title = "Win %", width = 56, align = "RIGHT" },
		{ key = "avg", title = "Avg", width = 50, align = "RIGHT" }, { key = "streak", title = "Streak", width = 84, align = "RIGHT" },
	},
	free_today = {
		{ key = "rank", title = "#", width = 32, align = "RIGHT" }, { key = "name", title = "Name", width = 180 },
		{ key = "won", title = "Solved", width = 70, align = "RIGHT" }, { key = "n", title = "Played", width = 64, align = "RIGHT" },
		{ key = "avg", title = "Avg", width = 66, align = "RIGHT" },
	},
	free_all = {
		{ key = "rank", title = "#", width = 32, align = "RIGHT" }, { key = "name", title = "Name", width = 146 },
		{ key = "won", title = "Solved", width = 64, align = "RIGHT" }, { key = "pct", title = "Win %", width = 56, align = "RIGHT" },
		{ key = "avg", title = "Avg", width = 50, align = "RIGHT" }, { key = "best", title = "Best run", width = 64, align = "RIGHT" },
	},
}

local function setCell(fs, r, col)
	local k = col.key
	if k == "rank" then fs:SetText(Theme.Paint(r.rank <= 3 and "accent" or "dim", r.rank))
	elseif k == "name" then fs:SetText((SK.RosterTab.DOT[r.status] or "") .. " " .. Theme.ClassText(r.name, r.class) ..
		(SK.DB.account[r.guid] and Theme.Paint("accent", " (you)") or ""))
	elseif k == "result" then fs:SetText(r.won and (r.g .. "/" .. SW.TRIES) or Theme.Paint("spark", "X/" .. SW.TRIES))
	elseif k == "when" then fs:SetText(Theme.Paint("dim", r.at and (Theme.Ago(r.at) == "now" and "now" or (Theme.Ago(r.at) .. " ago")) or "-"))
	elseif k == "won" then fs:SetText(r.w)
	elseif k == "n" then fs:SetText(Theme.Paint("dim", r.n))
	elseif k == "pct" then fs:SetText(Theme.Paint("dim", pct(r)))
	elseif k == "avg" then fs:SetText(avg(r.avg))
	elseif k == "streak" then
		fs:SetText((r.streak > 0 and r.streak or Theme.DASH) .. Theme.Paint("dim", "  best " .. r.best))
	elseif k == "best" then fs:SetText(r.best)
	end
end

-- Coloured squares for a pattern ("20110,22222"), one row per line.
function Words.PatternLines(p)
	local lines = {}
	for row in (p or ""):gmatch("[012]+") do
		local sq = {}
		for i = 1, #row do sq[i] = Theme.Square(TONE[tonumber(row:sub(i, i))], 12) end
		lines[#lines + 1] = table.concat(sq, " ")
	end
	return lines
end

local function rowTip(row, r)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:AddLine(Theme.ClassText(r.name, r.class))
	local view, board = Words.View()
	if view == "daily" and board == "today" then
		Theme.TipLine(GameTooltip, r.won and ("Solved in " .. r.g) or "Didn't get it", r.won and "good" or "spark")
		for _, line in ipairs(Words.PatternLines(r.p)) do GameTooltip:AddLine(line) end
	elseif view == "daily" then
		Theme.TipDouble(GameTooltip, "Played", r.n, "dim", "text")
		Theme.TipDouble(GameTooltip, "Won", r.w .. " (" .. pct(r) .. ")", "dim", "text")
		Theme.TipDouble(GameTooltip, "Average guesses", avg(r.avg), "dim", "text")
		Theme.TipDouble(GameTooltip, "Streak (best)", r.streak .. " (" .. r.best .. ")", "dim", "text")
	else
		Theme.TipDouble(GameTooltip, "Solved / played", r.w .. " / " .. r.n, "dim", "text")
		Theme.TipDouble(GameTooltip, "Average guesses", avg(r.avg), "dim", "text")
		if r.best then Theme.TipDouble(GameTooltip, "Best run of wins", r.best, "dim", "text") end
	end
	Theme.TipLine(GameTooltip, "Click to view character", "accent")
	GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
local function tile(parent)
	local t = CreateFrame("Frame", nil, parent)
	t:SetSize(TILE, TILE)
	t.bg = t:CreateTexture(nil, "BACKGROUND")
	t.bg:SetAllPoints()
	Theme.Border(t, "line")
	t.letter = Theme.Text(t, "page", "text")
	t.letter:SetPoint("CENTER", 0, 0)
	t.letter:SetJustifyH("CENTER")
	function t:Set(letter, state) -- state: nil (empty), "typed", 0, 1, 2
		self.letter:SetText(letter and letter:upper() or "")
		if state == nil or state == "typed" then
			Theme.Solid(self.bg, "surface")
			Theme.SetBorderColor(self, state == "typed" and "dim" or "line")
		else
			Theme.Solid(self.bg, TONE[state])
			Theme.SetBorderColor(self, TONE[state])
		end
	end
	t:Set(nil)
	return t
end

local function key(parent, label, width, onClick)
	local k = CreateFrame("Button", nil, parent)
	k:SetSize(width, S.key[2])
	k.bg = k:CreateTexture(nil, "BACKGROUND")
	k.bg:SetAllPoints()
	k.label = Theme.Text(k, "small", "text")
	k.label:SetPoint("CENTER")
	k.label:SetText(label)
	k.state = false
	function k:Paint(hover)
		if self.state then Theme.Solid(self.bg, TONE[self.state])
		else Theme.Solid(self.bg, hover and "lineStrong" or "raised") end
	end
	k:SetScript("OnEnter", function(self) self:Paint(true) end)
	k:SetScript("OnLeave", function(self) self:Paint(false) end)
	k:SetScript("OnClick", onClick)
	k:Paint(false)
	return k
end

function Words.View()
	local s = SK.DB.settings
	return s.wordsView == "free" and "free" or "daily", s.wordsBoard == "all" and "all" or "today"
end

function Words:Build(page)
	self.page = page
	local s = SK.DB.settings
	self.views = W.SubTabs(page, Words.VIEWS, function(k)
		s.wordsView = k
		Words:StopTyping()
		Words:Refresh()
	end)
	self.views:SetPoint("TOPLEFT", 0, 0)
	self.views:SetPoint("TOPRIGHT", 0, 0)
	self.status = Theme.Text(page, "small", "dim")
	self.status:SetPoint("RIGHT", self.views, "RIGHT", 0, SP.xxs)
	self.status:SetPoint("LEFT", self.views, "LEFT", 240, 0)
	self.status:SetJustifyH("RIGHT")
	self.status:SetWordWrap(false)
	local top = -(S.subTabs + SP.m)

	-- Board: six rows of five tiles, centred over the keyboard. Clicking it
	-- starts typing.
	local boardW = SW.LEN * TILE + (SW.LEN - 1) * GAP
	local boardH = SW.TRIES * TILE + (SW.TRIES - 1) * GAP
	local board = CreateFrame("Button", nil, page)
	board:SetSize(boardW, boardH)
	board:SetPoint("TOPLEFT", (Words.LEFT_W - boardW) / 2, top)
	board:SetScript("OnClick", function() Words:StartTyping() end)
	self.board = board
	self.tiles = {}
	for r = 1, SW.TRIES do
		self.tiles[r] = {}
		for c = 1, SW.LEN do
			local t = tile(board)
			t:SetPoint("TOPLEFT", (c - 1) * (TILE + GAP), -(r - 1) * (TILE + GAP))
			t:EnableMouse(false)
			self.tiles[r][c] = t
		end
	end

	-- The line under the board: what to do, or how it went.
	self.message = Theme.Text(page, "body", "dim")
	self.message:SetPoint("TOP", board, "BOTTOM", 0, -SP.s)
	self.message:SetWidth(Words.LEFT_W)
	self.message:SetJustifyH("CENTER")
	self.message:SetWordWrap(false)

	-- On-screen keyboard
	local kb = CreateFrame("Frame", nil, page)
	kb:SetSize(Words.LEFT_W, 3 * S.key[2] + 2 * SP.xs)
	kb:SetPoint("TOPLEFT", 0, top - boardH - SP.s - 18 - SP.s)
	self.keys = {}
	for i, letters in ipairs(KEY_ROWS) do
		local row = CreateFrame("Frame", nil, kb)
		row:SetHeight(S.key[2])
		local count = #letters + (i == 3 and 2 or 0)
		local wide = math.floor(S.key[1] * 1.5 + SP.xs / 2)
		local width = #letters * S.key[1] + (count - 1) * SP.xs + (i == 3 and 2 * wide or 0)
		row:SetWidth(width)
		row:SetPoint("TOP", 0, -(i - 1) * (S.key[2] + SP.xs))
		local x = 0
		local function add(k, w)
			k:SetPoint("LEFT", x, 0)
			x = x + w + SP.xs
		end
		if i == 3 then
			self.enterKey = key(row, "Enter", wide, function() Words:Submit() end)
			add(self.enterKey, wide)
		end
		for c = 1, #letters do
			local l = letters:sub(c, c)
			local k = key(row, l:upper(), S.key[1], function() Words:Type(l) end)
			self.keys[l] = k
			add(k, S.key[1])
		end
		if i == 3 then
			self.delKey = key(row, "Del", wide, function() Words:Type(nil) end)
			add(self.delKey, wide)
		end
	end
	self.keyboard = kb

	-- Under the keyboard: Share (daily, when done) or Next word (free).
	self.share = W.Button(page, "Share in guild chat", nil, S.control, function() Words:Share() end)
	self.share:SetPoint("TOP", kb, "BOTTOM", 0, -SP.m)
	self.share.tooltip = "Types your result into guild chat (no letters). Press Enter to send it."
	self.nextWord = W.Button(page, "Next word", nil, S.control, function() Words:Next() end, "primary")
	self.nextWord:SetPoint("TOP", kb, "BOTTOM", 0, -SP.m)

	-- Typing: an invisible edit box holds the current row's letters.
	local input = CreateFrame("EditBox", nil, page)
	input:SetSize(1, 1)
	input:SetPoint("TOPLEFT", board, "TOPLEFT")
	input:SetAutoFocus(false)
	input:SetMaxLetters(SW.LEN)
	input:SetAlpha(0)
	Theme.Font(input, "body", "text")
	input:SetScript("OnTextChanged", function(self)
		local text = (self:GetText() or ""):lower():gsub("[^a-z]", ""):sub(1, SW.LEN)
		if text ~= self:GetText() then self:SetText(text) return end
		Words.typed = text
		Words:DrawBoard()
	end)
	input:SetScript("OnEnterPressed", function() Words:Submit() end)
	input:SetScript("OnEscapePressed", function() Words:StopTyping() end)
	input:SetScript("OnEditFocusGained", function() Words.typing = true; Words:DrawMessage() end)
	input:SetScript("OnEditFocusLost", function() Words.typing = false; Words:DrawMessage() end)
	self.input = input
	self.typed, self.typing, self.note = "", false, false
	page:SetScript("OnHide", function() Words:StopTyping() end)

	-- Leaderboard: Today / All time chips, then one list per board shape.
	local right = CreateFrame("Frame", nil, page)
	right:SetPoint("TOPLEFT", Words.LEFT_W + SP.xl + SP.xs, top)
	right:SetPoint("BOTTOMRIGHT")
	self.right = right
	self.boardChips = {}
	local prev
	for _, b in ipairs(Words.BOARDS) do
		local c = W.Chip(right, b[2], function()
			s.wordsBoard = b[1]
			Words:Refresh()
		end)
		c.value = b[1]
		if prev then c:SetPoint("LEFT", prev, "RIGHT", SP.xs, 0) else c:SetPoint("TOPLEFT", 0, 0) end
		self.boardChips[#self.boardChips + 1] = c
		prev = c
	end
	self.boardCount = Theme.Text(right, "small", "dim")
	self.boardCount:SetPoint("RIGHT", right, "TOPRIGHT", 0, -11)
	self.boardCount:SetJustifyH("RIGHT")
	self.lists = {}
	for name, columns in pairs(Words.COLUMNS) do
		local l = W.List(right, {
			columns = columns, setCell = setCell, onEnter = rowTip,
			onClick = function(r) SK.CharacterTab:ShowCharacter(r.guid) end,
		})
		l:SetPoint("TOPLEFT", 0, -(S.control + SP.s))
		l:SetPoint("BOTTOMRIGHT")
		l:Hide()
		self.lists[name] = l
	end

	SK:On("WORDS_UPDATED", function() if page:IsShown() then Words:Refresh() end end)
	SK:On("PROFILE_UPDATED", function() if page:IsShown() then SK:Debounce("wordsboard", 1, function() Words:Refresh() end) end end)
end

---------------------------------------------------------------------------
-- Playing
---------------------------------------------------------------------------
-- The game shown on the current tab.
function Words:Game()
	local now = Compat.Now()
	if Words.View() == "daily" then return SW:Daily(now) end
	return SW:Free(Compat.PlayerGUID() or "?", now)
end

-- Can this character type into the shown game?
function Words:CanPlay(game)
	game = game or self:Game()
	if game.done then return false end
	return not (game.mode == "daily" and game.guid and game.guid ~= Compat.PlayerGUID())
end

function Words:StartTyping()
	if self.input and self:CanPlay() then self.input:SetFocus() end
end

function Words:StopTyping()
	if self.input then self.input:ClearFocus() end
end

-- Type a letter (nil = delete), from the on-screen keyboard.
function Words:Type(letter)
	if not self:CanPlay() then return end
	local text = self.typed or ""
	if letter then
		if #text < SW.LEN then text = text .. letter end
	else
		text = text:sub(1, -2)
	end
	self.input:SetText(text)
	self.typed = text
	self:DrawBoard()
end

local WHY = {
	short = "Five letters, please.",
	notword = "Not in the word list.",
	other = "Already played today on another character.",
}

function Words:Submit()
	local game = self:Game()
	if not self:CanPlay(game) then return end
	local name = Compat.PlayerFullName()
	local ok, why = SW:Play(game, self.typed or "", Compat.PlayerGUID(), name, Compat.Now())
	if ok then
		self.typed, self.note = "", false
		self.input:SetText("")
		if game.done then self:StopTyping() end
	else
		self.note = WHY[why] or false
	end
	self:Refresh()
end

function Words:Next()
	SW:NextFree(Compat.PlayerGUID() or "?", Compat.Now())
	self.typed, self.note = "", false
	self.input:SetText("")
	self:Refresh()
	self:StartTyping()
end

function Words:Share()
	local game = SW:Daily(Compat.Now())
	if not game.done then return end
	local stats = SW.Store().chars[game.guid or ""]
	local streak = stats and SW.Streak(stats.ds, game.day) or 0
	local guildStreak = SW:GuildStreakNow(SW.Entries(SK.DBM:Guild(), Compat.Now()), game.day)
	if not Compat.OpenChat("/g " .. SW.ShareText(game, streak, guildStreak)) then
		SK:Print("Couldn't open the chat box on this client.")
	end
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
function Words:DrawBoard()
	local game = self:Game()
	local rows = game.rows
	for r = 1, SW.TRIES do
		local row = rows[r]
		for c = 1, SW.LEN do
			local t = self.tiles[r][c]
			if row then
				t:Set(row.w:sub(c, c), tonumber(row.p:sub(c, c)))
			elseif r == #rows + 1 and self:CanPlay(game) then
				local l = (self.typed or ""):sub(c, c)
				t:Set(l ~= "" and l or nil, l ~= "" and "typed" or nil)
			else
				t:Set(nil)
			end
		end
	end
	local keys = SW.Keys(rows)
	for l, k in pairs(self.keys) do
		k.state = keys[l] or false
		k:Paint(false)
	end
end

-- "5h 12m"
local function left(sec)
	local h, m = math.floor(sec / 3600), math.floor(sec % 3600 / 60)
	return h > 0 and (h .. "h " .. m .. "m") or (m .. "m")
end

-- What the line under the board says. Pure apart from SK state; tested.
function Words.MessageFor(game, typing, note, me, now)
	if note then return note, "spark" end
	if game.done then
		local who = (game.mode == "daily" and game.guid and game.guid ~= me) and (" on " .. (game.name or "another character")) or ""
		local nextIn = game.mode == "daily" and ("  ·  next word in " .. left(SW.UntilNext(now))) or ""
		if game.won then return "Solved in " .. #game.rows .. who .. "!" .. nextIn, "good" end
		return "The word was " .. game.word:upper() .. who .. "." .. nextIn, "spark"
	end
	if game.mode == "daily" and game.guid and game.guid ~= me then
		return "Started on " .. (game.name or "another character") .. ": finish it there.", "dim"
	end
	if typing then return "Type a word, Enter to guess, Esc to stop typing.", "dim" end
	return "Click the board to type, or use the keys below.", "dim"
end

function Words:DrawMessage()
	if not self.message then return end
	local text, tone = Words.MessageFor(self:Game(), self.typing, self.note, Compat.PlayerGUID(), Compat.Now())
	self.message:SetText(text)
	self.message:SetTextColor(Theme.RGB(tone))
end

-- "Short Words #12  ·  Guild streak 5 days (2 of 3 today)". Pure; tested.
function Words.GuildStreakText(today, streak, played)
	local text = "Short Words #" .. today .. "  ·  Guild streak " ..
		Theme.Paint(streak > 0 and "accent" or "dim", Theme.Count(streak, "day"))
	if played < SW.GUILD_MIN then
		text = text .. Theme.Paint("dim", "  (" .. played .. " of " .. SW.GUILD_MIN .. " played today)")
	end
	return text
end

function Words:Description()
	return "A five-letter word in six guesses: one word a day for the whole guild, or as many as you like."
end

function Words:Refresh()
	if not self.views then return end
	local view, boardKey = Words.View()
	self.views:SetActive(view)
	local game = self:Game()
	if not self:CanPlay(game) then self:StopTyping() end
	self:DrawBoard()
	self:DrawMessage()
	self.share:SetShown(view == "daily" and game.done)
	self.nextWord:SetShown(view == "free" and game.done)
	local now = Compat.Now()
	local today = SW.Day(now)
	local entries = SW.Entries(SK.DBM:Guild(), now)
	if view == "daily" then
		local streak, played = SW:GuildStreakNow(entries, today)
		self.status:SetText(Words.GuildStreakText(today, streak, played))
	else
		local mine = SW.Store().chars[Compat.PlayerGUID() or ""]
		self.status:SetText(Theme.Count(mine and mine.f.w or 0, "word") .. " solved so far")
	end

	for _, c in ipairs(self.boardChips) do c:SetActive(c.value == boardKey) end
	local listKey = view .. "_" .. boardKey
	for name, l in pairs(self.lists) do l:SetShown(name == listKey) end
	local list = self.lists[listKey]
	local rows = SW.Board(entries, view, boardKey, today)
	list:SetItems(rows)
	list:SetEmptyText(boardKey == "today" and (view == "daily" and "Nobody has played today's word yet. Be the first!" or
		"Nobody has played free for all today yet.") or "No results yet. Scores appear as guildmates play.")
	self.boardCount:SetText(Theme.Count(#rows, "player"))
end

SK.MainFrame:AddTab("words", "Short Words", Words, { group = "games", icon = Theme.TEX.words })
