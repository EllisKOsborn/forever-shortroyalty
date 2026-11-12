-- Overview tab (v0.6.0): the guild at a glance. A strip of four numbers,
-- then "Needs a look" (what's missing or out of date, each row opens the
-- Roster), Raids, and Milestones (or Getting started while it's not done).
-- Names and details live in tooltips. Numbers come from Core/Overview.lua
-- and Core/Feed.lua.
local _, SK = ...

local Ov = SK:NewModule("OverviewTab")
local Theme, W, Compat = SK.Theme, SK.Widgets, SK.Compat
local S, SP = Theme.SIZES, Theme.SPACE

Ov.COL_W = math.floor((S.contentW - SP.l) / 2)
Ov.FEED_ROWS = 8      -- milestones shown

local function n(v) return tostring(v or 0) end

Ov.TIP_NAMES = 60 -- names in the hover list (two per line); the Roster has the rest

-- Hover list of everyone without the addon: two names per line, online first.
function Ov.WithoutTip(tt, without)
	Theme.TipLine(tt, "Not seen with Short Royalty yet (" .. #without .. ")")
	local function name(w)
		if not w then return "" end
		return (w.online and (SK.RosterTab.DOT.online .. " ") or "") .. Theme.ClassText(w.name, w.class)
	end
	local shown = math.min(#without, Ov.TIP_NAMES)
	for i = 1, shown, 2 do
		Theme.TipDouble(tt, name(without[i]), i + 1 <= shown and name(without[i + 1]) or "")
	end
	if #without > shown then Theme.TipLine(tt, "and " .. (#without - shown) .. " more: Not seen yet lists everyone", "dim") end
	Theme.TipLine(tt, "Characters that haven't logged in with Short Royalty yet (the Alt rank isn't counted). " ..
		"Online first (white dot).", "dim", true)
	Theme.TipLine(tt, "Click to see them in the Roster", "accent")
end

---------------------------------------------------------------------------
-- Rows (pure; tested). See W.Card / W.StatStrip for the formats.
---------------------------------------------------------------------------
function Ov.LevelsTip(tt, o)
	Theme.TipLine(tt, "Members")
	Theme.TipDouble(tt, "Players (alts counted once)", n(o.players), "dim", "text")
	for i, b in ipairs(SK.Overview.LEVEL_BANDS) do Theme.TipDouble(tt, "Level " .. b[3], n(o.levels[i]), "dim", "text") end
	if (o.altRank or 0) > 0 then
		Theme.TipLine(tt, "Not counting the " .. Theme.Count(o.altRank, "character") .. " in the Alt rank.", "faint", true)
	end
end

-- The number strip: members, online, have Short Royalty, raids.
function Ov.Stats(o)
	local stats = {
		{ figure = n(o.members), caption = "members", tip = function(tt) Ov.LevelsTip(tt, o) end },
		{ figure = n(o.online), caption = "online now", tip = function(tt)
			Theme.TipLine(tt, "Online now")
			Theme.TipLine(tt, n(o.withAddon) .. " of them with Short Royalty", "dim")
		end },
		{ figure = n(o.hasAddon), suffix = "/ " .. n(o.members), caption = "have Short Royalty",
			tip = #o.without > 0 and function(tt) Ov.WithoutTip(tt, o.without) end or nil,
			onClick = #o.without > 0 and function() SK.RosterTab:ShowWithoutAddon() end or nil },
	}
	if o.raidDays and o.raidDays > 0 then
		stats[4] = { figure = n(o.raidDays), tone = "accent",
			caption = (o.raidDays == 1 and "day" or "days") .. " until raids, 9 Dec" }
	elseif o.raidDays then
		stats[4] = { figure = "Open", tone = "accent", caption = "raids are open" }
	else
		stats[4] = { figure = Theme.DASH, caption = "raids" }
	end
	return stats
end

-- "Needs a look": only what's actually missing; each row opens the Roster.
function Ov.NeedsRows(o)
	local rows = {}
	local function add(count, one, many, onClick, tip)
		if count > 0 then
			rows[#rows + 1] = { label = count == 1 and one or many, value = n(count), tone = "spark", onClick = onClick, tip = tip }
		end
	end
	local oldest = function() SK.RosterTab:ShowOldestFirst() end
	add(#o.without, "Not seen with the addon yet", "Not seen with the addon yet",
		function() SK.RosterTab:ShowWithoutAddon() end, function(tt) Ov.WithoutTip(tt, o.without) end)
	add(o.outdated, "Running an old version", "Running an old version", function() SK.RosterTab:ShowOldVersions() end,
		function(tt)
			Theme.TipLine(tt, "Running an old Short Royalty")
			Theme.TipLine(tt, "Newest seen: " .. tostring(o.newest or "?") .. ". Click to see who, oldest first.", "dim", true)
		end)
	add(o.addonNoData, "Has the addon, no data here yet", "Have the addon, no data here yet", oldest)
	add(o.unscanned, "Profession window not opened", "Profession windows not opened", oldest, function(tt)
		Theme.TipLine(tt, "Profession windows not opened")
		Theme.TipLine(tt, "They have a crafting profession but haven't opened its window with Short Royalty, " ..
			"so their recipes aren't known yet.", "dim", true)
	end)
	add(o.stale, "Profile older than a week", "Profiles older than a week", oldest)
	if o.selfOutdated then
		rows[#rows + 1] = { text = string.format("Short Royalty %s is out (you have %s).", tostring(o.newest), SK.VERSION),
			tone = "spark" }
	end
	if #rows == 0 then rows[1] = { text = "All good: everyone's data is current.", tone = "good" } end
	return rows
end

-- Raids: one row per raid that needs an attunement (with a bar), one row
-- for the raids that don't.
function Ov.RaidRows(o)
	local rows, open = {}, {}
	local function toRoster(key) return function()
		SK.DB.settings.roster.raid = key
		SK.DB.settings.roster.attFilter = "all"
		SK.MainFrame:Select("roster")
	end end
	for _, r in ipairs(o.raids) do
		local name = string.format("%s (%s)", r.name, n(r.size))
		if r.status == "none" then
			open[#open + 1] = r
		else
			rows[#rows + 1] = { label = name, value = n(r.yes) .. " attuned", tone = r.yes > 0 and "good" or "dim",
				onClick = toRoster(r.key), tip = function(tt)
					Theme.TipLine(tt, name)
					Theme.TipDouble(tt, "Attuned", n(r.yes), "dim", "good")
					Theme.TipDouble(tt, "Not attuned", n(r.no), "dim", "bad")
					Theme.TipDouble(tt, "Unknown (gear or talents hidden, or no data)", n(r.unknown), "dim", "text")
					Theme.TipLine(tt, "Characters at level " .. n(o.maxLevel) .. ". Click for the list.", "faint")
				end }
			rows[#rows + 1] = { bar = { { r.yes, "good" }, { r.no, "lineStrong" }, { r.unknown, "raised" } } }
			rows[#rows + 1] = { text = string.format("%d attuned  ·  %d not yet  ·  %d unknown", r.yes, r.no, r.unknown) ..
				(r.noItem > 0 and Theme.Paint("spark", string.format("  ·  %d without the amulet in their bags", r.noItem)) or "") }
		end
	end
	if #open > 0 then
		local names = {}
		for _, r in ipairs(open) do names[#names + 1] = r.name end
		rows[#rows + 1] = { label = table.concat(names, ", "), value = n(open[1].eligible) .. " ready", tone = "dim",
			onClick = toRoster(open[1].key), tip = function(tt)
				Theme.TipLine(tt, table.concat(names, ", "))
				Theme.TipLine(tt, "No attunement needed: " .. n(open[1].eligible) .. " characters at level " ..
					n(o.maxLevel) .. ".", "dim", true)
			end }
	end
	if #rows == 0 then rows[1] = { text = "No raids to show yet." } end
	return rows
end

-- Plain text (tests, Copy).
function Ov.NeedsText(o) return W.CardText(Ov.NeedsRows(o)) end
function Ov.RaidText(o) return W.CardText(Ov.RaidRows(o)) end

-- Page sentence under the title.
function Ov.DescriptionText(guildName, o, hasGuild)
	if not hasGuild then return "No guild  ·  join a guild to see guildmates here" end
	return table.concat({ guildName or "Your guild", Theme.Count(o.members, "member"),
		Theme.Count(o.players, "player"), o.online .. " online" }, "  ·  ")
end

function Ov:Description()
	return self.data and Ov.DescriptionText(SK.guildName, self.data, SK.DBM:Guild() ~= nil) or ""
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
local function setFeedCell(fs, e, col)
	if col.key == "when" then
		fs:SetText(Theme.Paint("dim", Theme.Ago(e.at)))
	elseif col.key == "what" then
		local first = (e.name or "?"):match("^(%S+)") or e.name
		fs:SetText(Theme.ClassText(first, e.class) .. " " .. e.text)
	else
		fs:SetText("")
	end
end

function Ov:Build(page)
	self.page = page
	self.stats = W.StatStrip(page, S.contentW, 4)
	self.stats:SetPoint("TOPLEFT", 0, 0)
	local top = -(S.statH + SP.l)

	self.needs = W.Card(page, Ov.COL_W, "Needs a look")
	self.needs:SetPoint("TOPLEFT", 0, top)
	self.raids = W.Card(page, Ov.COL_W, "Raids", { text = "Attunement list", tooltip = "Roster with Onyxia's Lair attunement",
		onClick = function()
			SK.DB.settings.roster.raid = "ony"
			SK.DB.settings.roster.attFilter = "all"
			SK.MainFrame:Select("roster")
		end })
	self.raids:SetPoint("TOPLEFT", self.needs, "BOTTOMLEFT", 0, -SP.l)

	-- Milestones: a list with a quiet Grats link per row.
	local feed = W.Card(page, Ov.COL_W, "Milestones")
	feed:SetPoint("TOPLEFT", Ov.COL_W + SP.l, top)
	feed:SetBody(Ov.FEED_ROWS * S.cardRow)
	self.feed = feed
	local gratsW = 48
	local inner = Ov.COL_W - 2 * SP.s
	feed.list = W.List(feed.panel, {
		header = false, rowHeight = S.cardRow,
		columns = { { key = "when", title = "", width = 34 }, { key = "what", title = "", width = inner - 34 - gratsW - SP.m },
			{ key = "btn", title = "", width = gratsW } },
		setCell = setFeedCell,
		decorate = function(row)
			row.grats = W.Button(row, "Grats", gratsW - SP.xs, S.controlSmall, function(b)
				if b.entry then Compat.OpenChat("/g " .. SK.Feed.GratsText(b.entry)) end
			end, "quiet")
			row.grats:SetPoint("RIGHT", -SP.xxs, 0)
			row.widgets[#row.widgets + 1] = row.grats
			row.grats.tooltip = "Types a congratulation into guild chat. Press Enter to send it."
		end,
		update = function(row, e)
			row.grats.entry = e
			row.grats:SetShown(e.grats ~= nil and not SK.DB.account[e.guid])
		end,
		onEnter = function(row, e)
			GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
			GameTooltip:AddLine(Theme.ClassText(e.name, e.class) .. " " .. e.text, Theme.RGB("text"))
			GameTooltip:AddLine(Theme.Ago(e.at) .. " ago (seen by your addon)", Theme.RGB("dim"))
			GameTooltip:AddLine("Click to view character", Theme.RGB("accent"))
			GameTooltip:Show()
		end,
		onClick = function(e) SK.CharacterTab:ShowCharacter(e.guid) end,
	})
	feed.list:SetPoint("TOPLEFT", SP.xs, 0)
	feed.list:SetPoint("BOTTOMRIGHT", -SP.xs, 0)
	feed.list:SetEmptyText("Level-ups, profession milestones, attunements and new recipes show here as your addon sees them.")
	feed.empty = feed.list.message

	-- Getting started (v0.3.1): takes the milestones' place until it's done
	-- or hidden (a new player has no milestones yet anyway).
	self.start = W.Card(page, Ov.COL_W, "Getting started", { text = "Hide", onClick = function() SK.Onboarding.Hide() end,
		tooltip = "Hide this list (it also goes away by itself once everything's done)" })
	self.start:SetPoint("TOPLEFT", Ov.COL_W + SP.l, top)

	SK:On("ONBOARDING_CHANGED", function()
		if page:IsShown() then Ov:Refresh() end
	end)
	SK:On("FEED_UPDATED", function()
		if page:IsShown() then SK:Debounce("overviewfeed", 0.5, function() Ov:Refresh() end) end
	end)
end

function Ov:Refresh()
	if not self.needs then return end
	local guild = SK.DBM:Guild()
	local o = SK.Overview.Build(guild, Compat.Now())
	self.data = o
	self.stats:SetStats(Ov.Stats(o))
	self.needs:SetRows(Ov.NeedsRows(o))
	self.raids:SetRows(Ov.RaidRows(o))
	self.feed.list:SetItems(SK.Feed.Entries(guild, SK.Feed.MAX))

	local steps, allDone = SK.Onboarding.Steps(SK.Profile:Own(), SK.DB.settings.seen, nil,
		o.hasAddon, o.members)
	local showStart = SK.Onboarding.Visible(allDone)
	self.start:SetShown(showStart)
	self.feed:SetShown(not showStart)
	if showStart then self.start:SetRows(Ov.StartRows(steps)) end
	if SK.MainFrame.current == "overview" then SK.MainFrame:UpdateHeader() end
end

-- Getting started rows (pure; tested).
function Ov.StartRows(steps)
	local rows = {}
	for _, s in ipairs(steps) do
		rows[#rows + 1] = { label = s.text, labelTone = s.done and "dim" or "text",
			value = s.done and "done" or (s.optional and "optional" or "to do"),
			tone = s.done and "good" or (s.optional and "dim" or "spark") }
		if s.detail and not s.done then rows[#rows + 1] = { text = s.detail, tone = "dim" } end
	end
	return rows
end

SK.MainFrame:AddTab("overview", "Overview", Ov, { group = "guild" })
