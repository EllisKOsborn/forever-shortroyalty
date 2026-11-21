-- Roster tab: every guild member, sortable, with class colours, level,
-- spec, professions, item level and when they were last online. Rank,
-- addon version and data age live in the name's tooltip (v0.6.0), with a
-- small orange mark on the name when something is out of date. Alts can be
-- grouped under their main (the ··· menu).
local _, SK = ...

local Roster = SK:NewModule("RosterTab")
local Theme, W = SK.Theme, SK.Widgets
local S, SP = Theme.SIZES, Theme.SPACE

-- "addon" = online with Short Royalty, "online" = online without it, "offline".
-- (Lives in Identity so non-UI code such as Sync and CraftIndex can use it.)
Roster.Status = SK.Identity.Status

local STATUS_RANK = { addon = 3, online = 2, offline = 1 }
-- Round dots: green = online with Short Royalty, white = online without it,
-- dark grey = offline. (Gold and spark stay free for actions and alerts.)
local DOT = {
	addon = Theme.Dot("good"),
	online = Theme.Dot("text"),
	offline = Theme.Dot("faint"),
}
Roster.DOT = DOT

-- Newest addon version anyone in the guild runs (for "needs update").
function Roster.NewestVersion(guild)
	local newest = SK.VERSION ~= "dev" and SK.VERSION or nil
	for _, m in pairs(guild.members) do
		if m.addon and (not newest or SK.Sync.versionNewer(m.addon, newest)) then newest = m.addon end
	end
	return newest
end

local function professionsOf(p)
	local profs, text = {}, {}
	if p and p.profs then
		for skillLine, pr in pairs(p.profs) do
			profs[#profs + 1] = { name = pr.name or SK.Data.ProfessionShort(skillLine), rank = pr.rank or 0,
				short = SK.Data.ProfessionShort(skillLine, pr.name), primary = pr.primary and true or false }
		end
		table.sort(profs, function(a, b)
			if a.primary ~= b.primary then return a.primary end
			return a.name < b.name
		end)
		for _, pr in ipairs(profs) do
			if pr.primary then text[#text + 1] = pr.short .. " " .. pr.rank end
		end
	end
	return profs, table.concat(text, ", ")
end

local function makeRow(guild, guid, m, now, newest)
	local p = SK.Profile:Get(guid, guild)
	local isSelf = SK.DB.account[guid] or false
	local profs, profText = professionsOf(p)
	local spec, mainTree = SK.Talents.Summary(p and p.talents)
	local version = isSelf and SK.VERSION or m.addon
	return {
		guid = guid, name = m.name or (p and p.name) or "?", class = m.class or (p and p.class),
		level = m.level or (p and p.level) or 0, rank = m.rank or "", rankIndex = m.rankIndex or 99,
		online = m.online, lastSeen = m.lastSeen, hasData = p ~= nil, updated = p and p.updated,
		ilvl = p and p.ilvl, spec = spec, mainTree = mainTree, profText = profText, profs = profs,
		status = Roster.Status(m, isSelf, now), addon = version, isSelf = isSelf,
		hasAddon = SK.Identity.HasAddon(guid, m, p),
		altRank = SK.Identity.IsAltRank(m),
		outdated = (version and newest and version ~= "dev" and SK.Sync.versionNewer(newest, version))
			or (not version and m.oldAddon ~= nil) or false,
		oldAddon = not version and m.oldAddon ~= nil or nil,
		note = m.note, officerNote = m.officerNote,
		missingEnchants = p and p.gear and #SK.Data.Enchants.Missing(p.gear, p.class, p.level) or nil,
		hidden = p and p.hidden,
	}
end

local function matches(row, filter)
	local hay = { row.name, row.profText, row.mainTree or "", row.class or "", row.rank, row.note or "" }
	for _, pr in ipairs(row.profs) do hay[#hay + 1] = pr.name end
	for _, alt in ipairs(row.alts or {}) do hay[#hay + 1] = alt.name end
	return table.concat(hay, " "):lower():find(filter, 1, true) ~= nil
end

-- Build display rows from saved members + profiles. Pure; tested.
-- With `group`, alts are folded into their main's row (row.alts).
function Roster.Rows(guild, now, filter, group)
	local rows = {}
	if not guild then return rows end
	filter = filter and filter ~= "" and filter:lower() or nil
	now = now or SK.Compat.Now()
	local newest = Roster.NewestVersion(guild)

	local byGuid = {}
	for guid, m in pairs(guild.members) do
		if not m.leftAt then byGuid[guid] = makeRow(guild, guid, m, now, newest) end
	end

	if group then
		local profiles = {}
		for guid in pairs(byGuid) do
			local p = guild.profiles[guid]
			if p then profiles[guid] = p end
		end
		local groupOf = SK.Alts.Groups(profiles, function(g) return byGuid[g] ~= nil end)
		for guid, row in pairs(byGuid) do
			local g = groupOf[guid]
			if g and #g.members > 1 then
				if g.main == guid then
					row.alts = {}
					for _, other in ipairs(g.members) do
						if other ~= guid then
							local alt = byGuid[other]
							row.alts[#row.alts + 1] = alt
							if STATUS_RANK[alt.status] > STATUS_RANK[row.status] then
								row.status, row.onAlt = alt.status, alt.name
							end
							if alt.online then row.online = true end
						end
					end
				else
					row.hiddenAlt = true
				end
			end
		end
	end

	for _, row in pairs(byGuid) do
		if not row.hiddenAlt and (not filter or matches(row, filter)) then rows[#rows + 1] = row end
	end
	return rows
end

---------------------------------------------------------------------------
-- Raid attunement view (v0.1.2)
---------------------------------------------------------------------------
function Roster.Raid(key)
	for _, a in ipairs(SK.Data.ATTUNEMENTS) do
		if a.key == key then return a end
	end
end

-- Attunement state for one profile and raid (logic in Collect/Attunements).
Roster.AttunementOf = SK.Attunements.StateOf

-- Highest level of any current member (the guild's "max level").
function Roster.MaxLevel(guild)
	local max = 0
	for _, m in pairs(guild and guild.members or {}) do
		if not m.leftAt and (m.level or 0) > max then max = m.level end
	end
	return max
end

-- One row per character (alts are never folded in here, because attunement
-- belongs to a character). Pure; tested.
--   filter: "all" | "yes" | "no" | "unknown"
-- Returns rows, counts { yes, no, unknown } (before `filter`, after search
-- and the max-level rule), maxLevel.
function Roster.AttunementRows(guild, raidKey, filter, maxLevelOnly, search, now)
	local counts = { yes = 0, no = 0, unknown = 0, none = 0 }
	local out = {}
	local raid = Roster.Raid(raidKey)
	if not guild or not raid then return out, counts, 0 end
	now = now or SK.Compat.Now()
	filter = filter or "all"
	local maxLevel = Roster.MaxLevel(guild)

	-- "alt of X" for the tooltip.
	local profiles = {}
	for guid, m in pairs(guild.members) do
		if not m.leftAt and guild.profiles[guid] then profiles[guid] = guild.profiles[guid] end
	end
	local groupOf = SK.Alts.Groups(profiles, function(g) return profiles[g] ~= nil end)

	for _, row in ipairs(Roster.Rows(guild, now, search, false)) do
		if not maxLevelOnly or row.level >= maxLevel then
			row.att, row.attNote = Roster.AttunementOf(SK.Profile:Get(row.guid, guild), raid)
			local g = groupOf[row.guid]
			if g and #g.members > 1 and g.main ~= row.guid then
				local mm = guild.members[g.main]
				row.altOf = (mm and mm.name) or (profiles[g.main] and profiles[g.main].name)
			end
			counts[row.att] = counts[row.att] + 1
			if filter == "all" or filter == row.att then out[#out + 1] = row end
		end
	end
	return out, counts, maxLevel
end

local function byName(a, b) return a.name:lower() < b.name:lower() end
local function byNum(key) return function(a, b)
	local x, y = a[key] or -1, b[key] or -1
	if x == y then return byName(a, b) end
	return x < y
end end

-- Version column: members without the addon first, then newest version first.
function Roster.ByVersion(a, b)
	if a.hasAddon ~= b.hasAddon then return not a.hasAddon end
	if a.altRank ~= b.altRank then return not a.altRank end -- alt rank after the real gaps (v0.4.0)
	local x, y = a.addon or "", b.addon or ""
	if x ~= y then
		if x == "" or y == "" then return y == "" end
		return SK.Sync.versionNewer(x, y) or (not SK.Sync.versionNewer(y, x) and x > y)
	end
	return byName(a, b)
end

-- Widths add up to the content width minus the scroll bar (744 - 12 = 732).
-- The name and professions get the most room; numbers are right-aligned.
local function bySeen(a, b)
	if a.status ~= b.status then return STATUS_RANK[a.status] > STATUS_RANK[b.status] end
	return (a.lastSeen or 0) > (b.lastSeen or 0)
end
local COLUMNS = {
	{ key = "name", title = "Name", width = 196, sort = byName },
	{ key = "level", title = "Lvl", width = 44, align = "RIGHT", sort = byNum("level") },
	{ key = "spec", title = "Spec", width = 120, sort = function(a, b) return (a.mainTree or "~") < (b.mainTree or "~") end },
	{ key = "profs", title = "Professions", width = 226, sort = function(a, b) return a.profText < b.profText end },
	{ key = "ilvl", title = "iLvl", width = 50, align = "RIGHT", sort = byNum("ilvl") },
	{ key = "seen", title = "Seen", width = 96, align = "RIGHT", sort = bySeen },
}
Roster.SEEN_COL = 6

-- "Oldest data first" (missing data first, then oldest; v0.6.0: there's
-- no Data column any more, so it's a sort of its own).
function Roster.ByData(a, b)
	local x, y = a.hasData and (a.updated or 0) or -1, b.hasData and (b.updated or 0) or -1
	if x ~= y then return x < y end
	return byName(a, b)
end

-- Old versions first (oldest first), then the newest, then no addon.
function Roster.ByOldVersion(a, b)
	if a.outdated ~= b.outdated then return a.outdated end
	if a.hasAddon ~= b.hasAddon then return a.hasAddon end
	return Roster.ByVersion(b, a)
end

local ATT_RANK = { yes = 3, no = 2, unknown = 1, none = 0 }

-- While a raid is selected: Attuned takes the place of Professions.
local ATT_COLUMNS = {
	COLUMNS[1], COLUMNS[2], COLUMNS[3],
	{ key = "att", title = "Attuned", width = 226, sort = function(a, b)
		if a.att ~= b.att then return ATT_RANK[a.att] > ATT_RANK[b.att] end
		return byName(a, b)
	end },
	COLUMNS[5], COLUMNS[6],
}

-- The game font has no check-mark glyphs, so the marks are the ready-check
-- atlases from Blizzard's Forever ReadyCheck.lua (READY_CHECK_*_TEXTURE).
local ATT_TEXT = {
	yes = "|A:UI-LFG-ReadyMark:12:12|a " .. Theme.Paint("good", "yes"),
	no = "|A:UI-LFG-DeclineMark:12:12|a " .. Theme.Paint("bad", "no"),
	unknown = "|A:UI-LFG-PendingMark:12:12|a " .. Theme.Paint("dim", "unknown"),
	none = Theme.Paint("dim", "not needed"),
}
Roster.ATT_TEXT = ATT_TEXT

-- Something about this character's data is out of date (orange mark).
function Roster.NeedsLook(r, now)
	if r.oldAddon or r.outdated then return true end
	return r.hasData and not r.isSelf and Theme.IsStale(r.updated, now) or false
end

local function setCell(fs, r, col)
	local k = col.key
	local now = SK.Compat.Now()
	local C = Theme.Code
	if k == "name" then
		local extra = ""
		if r.isSelf then extra = " " .. C("accent") .. "(you)|r" end
		if r.alts and #r.alts > 0 then extra = extra .. " " .. C("dim") .. "+" .. #r.alts .. "|r" end
		if Roster.NeedsLook(r, now) then extra = extra .. " " .. C("spark") .. "!|r" end
		fs:SetText(DOT[r.status] .. " " .. Theme.ClassText(r.name, r.class) .. extra)
	elseif k == "level" then
		fs:SetText(r.level > 0 and r.level or Theme.DASH)
	elseif k == "spec" then
		fs:SetText(r.mainTree and (C("dim") .. r.mainTree .. "|r") or (r.spec and C("dim") .. r.spec .. "|r") or Theme.DASH)
	elseif k == "profs" then
		fs:SetText(r.profText ~= "" and r.profText:gsub(", ", C("faint") .. "  ·  |r") or Theme.DASH)
	elseif k == "ilvl" then
		fs:SetText(r.ilvl and string.format("%.0f", r.ilvl) or Theme.DASH)
	elseif k == "seen" then
		if r.status == "offline" then
			fs:SetText(C("dim") .. Theme.Ago(r.lastSeen, now) .. "|r")
		elseif r.onAlt then
			fs:SetText(C("good") .. "on alt|r")
		else
			fs:SetText(C("good") .. "online|r")
		end
	elseif k == "att" then
		fs:SetText(ATT_TEXT[r.att or "unknown"] .. (r.attNote and (" " .. C("spark") .. "!|r") or ""))
	end
end

local STATUS_TEXT = {
	addon = "Online with Short Royalty",
	online = "Online without Short Royalty (or not heard from yet)",
	offline = "Offline",
}

local function tooltip(row, r)
	local now = SK.Compat.Now()
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	Theme.TipDouble(GameTooltip, Theme.ClassText(r.name, r.class), r.rank ~= "" and r.rank or " ", "text", "dim")
	if r.altOf then Theme.TipLine(GameTooltip, "alt of " .. r.altOf, "dim") end
	if r.att then
		local raid = Roster.Raid(SK.DB.settings.roster.raid)
		Theme.TipDouble(GameTooltip, (raid and raid.name or "Raid") .. " attunement", ATT_TEXT[r.att], "accent")
		if r.attNote then Theme.TipLine(GameTooltip, r.attNote, "spark") end
	end
	Theme.TipLine(GameTooltip, DOT[r.status] .. " " .. STATUS_TEXT[r.status], "text")
	if r.spec then Theme.TipLine(GameTooltip, (r.mainTree or "Talents") .. " " .. r.spec, "text") end
	for _, pr in ipairs(r.profs) do Theme.TipDouble(GameTooltip, pr.name, pr.rank, "text", "text") end
	if r.missingEnchants and r.missingEnchants > 0 then
		Theme.TipLine(GameTooltip, r.missingEnchants .. " item(s) missing an enchant", "spark")
	end
	if r.note and r.note ~= "" then Theme.TipLine(GameTooltip, "Note: " .. r.note, "text", true) end
	if r.officerNote and r.officerNote ~= "" then
		Theme.TipLine(GameTooltip, "Officer note: " .. r.officerNote, "dim", true)
	end
	if r.alts and #r.alts > 0 then
		GameTooltip:AddLine(" ")
		Theme.TipLine(GameTooltip, "Alts", "accent")
		for _, alt in ipairs(r.alts) do
			local right = alt.status == "offline" and Theme.Ago(alt.lastSeen, now) or "online"
			Theme.TipDouble(GameTooltip, DOT[alt.status] .. " " .. Theme.ClassText(alt.name, alt.class) ..
				"  " .. (alt.level > 0 and alt.level or ""), right, "text", "dim")
		end
	end
	GameTooltip:AddLine(" ")
	if r.oldAddon then
		Theme.TipLine(GameTooltip, "Runs an old Short Royalty (v0.3.2 or earlier) that can't share with yours. " ..
			"They need to update.", "spark", true)
	elseif not r.hasData and r.hasAddon then
		Theme.TipLine(GameTooltip, "Has Short Royalty" .. (r.addon and (" " .. r.addon) or "") ..
			", but their data hasn't reached you yet.", "spark", true)
	elseif not r.hasData then
		Theme.TipLine(GameTooltip, "Not seen with Short Royalty yet. They may have it on another character, " ..
			"or be on a trial account (trials can't sync).", "dim", true)
	elseif r.addon then
		if not r.isSelf and Theme.IsStale(r.updated, now) then
			Theme.TipLine(GameTooltip, "Data is " .. Theme.Ago(r.updated, now) .. " old and may be out of date", "spark")
		end
		Theme.TipLine(GameTooltip, "Short Royalty " .. r.addon .. (r.outdated and "  (update available)" or "") ..
			"  ·  data " .. Theme.Ago(r.updated, now) .. (Theme.Ago(r.updated, now) == "now" and "" or " old"),
			r.outdated and "spark" or "dim")
	end
	Theme.TipLine(GameTooltip, "Click to view character", "accent")
	GameTooltip:Show()
end

local FILTERS = {
	{ "all", "All" }, { "yes", "Attuned" }, { "no", "Not attuned" }, { "unknown", "Unknown" },
}

local function raidItems()
	local items = { { value = "none", text = "All raids" } }
	for _, a in ipairs(SK.Data.ShownAttunements()) do
		items[#items + 1] = { value = a.key, text = a.name .. (a.size and (" (" .. a.size .. ")") or "") }
	end
	return items
end

function Roster:Build(page)
	local rs = SK.DB.settings.roster
	self.filter = ""
	-- Toolbar: search, raid picker, options (···), count.
	self.search = W.SearchBox(page, 240, "Search name, profession, note", function(text)
		Roster.filter = text
		Roster:Refresh()
	end)
	self.search:SetPoint("TOPLEFT", 0, 0)
	self.raidMenu = W.Menu(page, {
		width = 170, items = raidItems,
		get = function() return rs.raid or "none" end,
		set = function(v)
			rs.raid = (v ~= "none") and v or nil
			Roster:Refresh()
		end,
	})
	self.raidMenu.tooltip = "Pick a raid to see who is attuned"
	self.raidMenu:SetPoint("LEFT", self.search, "RIGHT", SP.s, 0)
	self.options = W.OptionsButton(page, function()
		return {
			{ text = "Group alts under their main", checked = function() return SK.DB.settings.groupAlts end, onClick = function()
				SK.DB.settings.groupAlts = not SK.DB.settings.groupAlts
				Roster:Refresh()
			end },
			{ text = "Copy the list as text", onClick = function() Roster:CopyText() end },
			{ text = "Taller window", checked = function() return SK.MainFrame.TallH() > 0 end, onClick = function()
				SK.MainFrame:SetTall(SK.MainFrame.TallH() == 0)
			end },
		}
	end, "Group alts, copy the list, taller window")
	self.options:SetPoint("LEFT", self.raidMenu, "RIGHT", SP.s, 0)
	-- v0.10.1: the Officers view (officers and raid leaders with /sr officer).
	self.officerChip = W.Chip(page, "Officers", function()
		rs.officer = not rs.officer
		Roster:Refresh()
	end)
	self.officerChip.tooltip = "The raid roster planner: Raider, Backup or Social, Main or Off per role, level, gear, " ..
		"attunement and officers' notes for every player. Only officers and raid leaders see it."
	self.officerChip:SetPoint("LEFT", self.options, "RIGHT", SP.s, 0)
	self.count = Theme.Text(page, "small", "dim")
	self.count:SetPoint("LEFT", self.officerChip, "RIGHT", SP.m, 0)
	self.count:SetPoint("RIGHT", page, "TOPRIGHT", 0, -S.control / 2)
	self.count:SetJustifyH("RIGHT")
	self.count:SetWordWrap(false)

	-- Second toolbar row, shown only while a raid is selected.
	local bar = CreateFrame("Frame", nil, page)
	bar:SetPoint("TOPLEFT", 0, -(S.control + SP.s))
	bar:SetPoint("TOPRIGHT", 0, -(S.control + SP.s))
	bar:SetHeight(S.control)
	self.attBar = bar
	self.filterTabs = {}
	local prev
	for _, f in ipairs(FILTERS) do
		local t = W.Chip(bar, f[2], function()
			rs.attFilter = f[1]
			Roster:Refresh()
		end)
		t.value = f[1]
		if prev then t:SetPoint("LEFT", prev, "RIGHT", SP.xs, 0) else t:SetPoint("LEFT", 0, 0) end
		self.filterTabs[#self.filterTabs + 1] = t
		prev = t
	end
	self.maxCheck = W.Check(bar, "Max level only", function() return rs.maxLevelOnly end, function(v)
		rs.maxLevelOnly = v
		Roster:Refresh()
	end)
	self.maxCheck:SetPoint("LEFT", prev, "RIGHT", SP.l, 0)
	self.attCount = Theme.Text(bar, "small", "dim")
	self.attCount:SetPoint("LEFT", self.maxCheck.label, "RIGHT", SP.l, 0)
	self.attCount:SetPoint("RIGHT", 0, 0)
	self.attCount:SetJustifyH("RIGHT")
	self.attCount:SetWordWrap(false)

	-- Two lists: the List widget builds its columns once, so instead of
	-- rebuilding it we keep one per column set and show the one in use.
	local function makeList(columns, sortCol)
		local l = W.List(page, {
			columns = columns, setCell = setCell,
			onClick = function(r) SK.CharacterTab:ShowCharacter(r.guid) end,
			onEnter = tooltip,
		})
		l:SetPoint("BOTTOMRIGHT")
		l.sortCol = sortCol
		return l
	end
	self.list = makeList(COLUMNS, Roster.SEEN_COL)        -- online first
	self.list:SetPoint("TOPLEFT", 0, -(S.control + SP.m))
	self.attList = makeList(ATT_COLUMNS, Roster.SEEN_COL) -- online first
	self.attList:SetPoint("TOPLEFT", 0, -(2 * S.control + SP.s + SP.m))
	self.attList:Hide()
	self:BuildOfficers(page)
	SK:On("OFFICERDIR_UPDATED", function() if page:IsShown() then Roster:Refresh() end end)
	SK:On("ATTENDANCE_UPDATED", function() if page:IsShown() and rs.officer then Roster:Refresh() end end)
end

---------------------------------------------------------------------------
-- Officers view: the raid roster planner (v0.13.0; it replaced the v0.10.1
-- roles/notes editor). One row per player with officer-set status and
-- Main / Off per role, level, gear, attunement and officers' notes.
-- Data: Core/OfficerDir.lua (shared between officers by
-- Sync/OfficerSync.lua) and Core/RosterPlan.lua (rows, groups, summary).
---------------------------------------------------------------------------
local RP = SK.RosterPlan
Roster.ATT_DAYS = 30

local function nameOf(guid)
	local guild = SK.DBM:Guild()
	local m = guild and guild.members[guid]
	return m and m.name or nil
end
Roster.PILL_W = 42

local function ageSort(a, b) return (a.age or 1e12) < (b.age or 1e12) end
local function tierRank(role) return function(a, b)
	local ra = ({ m = 1, b = 2 })[a.tiers[role] or ""] or 3
	local rb = ({ m = 1, b = 2 })[b.tiers[role] or ""] or 3
	if ra ~= rb then return ra < rb end
	return a.name:lower() < b.name:lower()
end end

Roster.PLAN_COLUMNS = {
	{ key = "name", title = "Name", width = 100, sort = function(a, b) return a.name:lower() < b.name:lower() end },
	{ key = "spec", title = "Spec", width = 64, sort = function(a, b) return (a.spec or "~") < (b.spec or "~") end },
	{ key = "status", title = "Status", width = 58, click = true, sort = RP.DefaultOrder },
	{ key = "TANK", title = "Tank", width = 48, click = true, sort = tierRank("TANK") },
	{ key = "HEALER", title = "Healer", width = 48, click = true, sort = tierRank("HEALER") },
	{ key = "DPS", title = "DPS", width = 48, click = true, sort = tierRank("DPS") },
	-- v0.13.0: away days in words ("9-15 Dec", "Every Tue"); click for a mini calendar.
	{ key = "away", title = "Away", width = 72, click = true,
		sort = function(a, b) return (a.awayDays[1] and a.awayDays[1].at or 1e12) < (b.awayDays[1] and b.awayDays[1].at or 1e12) end },
	{ key = "level", title = "Level", width = 52, align = "RIGHT", sort = function(a, b) return a.level < b.level end },
	{ key = "ilvl", title = "iLvl", width = 52, align = "RIGHT", sort = function(a, b) return (a.ilvl or 0) < (b.ilvl or 0) end },
	{ key = "att", title = "Ony", width = 40, align = "RIGHT",
		sort = function(a, b) return (a.att == "yes" and 1 or 0) < (b.att == "yes" and 1 or 0) end },
	{ key = "ench", title = "Ench", width = 30, align = "RIGHT", sort = function(a, b) return (a.ench or 99) < (b.ench or 99) end },
	{ key = "seen", title = "Seen", width = 40, align = "RIGHT", sort = ageSort },
	{ key = "note", title = "Note", width = S.contentW - SP.m - 652, click = true },
}

local SIGNED_TEXT = { y = { "good", "Yes" }, t = { "accent", "Maybe" }, n = { "bad", "No" } }

-- One cell's text (the clickable cells draw on their own buttons).
local function setPlanCell(fs, r, col)
	local k = col.key
	if r.section or col.click then return fs:SetText("") end
	if k == "name" then
		local extra = #r.alts > 0 and Theme.Paint("faint", " +" .. #r.alts) or ""
		fs:SetText(Theme.ClassText(r.name, r.class) .. extra)
	elseif k == "spec" then
		fs:SetText(r.spec and Theme.Paint("dim", r.spec) or Theme.DASH)
	elseif k == "level" then
		local lvl = r.level >= RP.MAX_LEVEL and Theme.Paint("good", tostring(r.level)) or tostring(r.level)
		fs:SetText(lvl .. (r.levelGain and Theme.Paint("good", " +" .. r.levelGain) or ""))
	elseif k == "ilvl" then
		fs:SetText(r.ilvl and (string.format("%d", r.ilvl) .. (r.ilvlGain and Theme.Paint("good", " +" .. math.floor(r.ilvlGain + 0.5)) or ""))
			or Theme.DASH)
	elseif k == "att" then
		fs:SetText(r.att == "yes" and Theme.Paint("good", "yes") or (r.att == "no" and Theme.Paint("faint", "no") or Theme.DASH))
	elseif k == "ench" then
		fs:SetText(r.ench == nil and Theme.DASH or (r.ench > 0 and Theme.Paint("spark", tostring(r.ench)) or Theme.Paint("faint", "0")))
	elseif k == "seen" then
		if Roster.signupsFor then
			local t = SIGNED_TEXT[r.signed or ""]
			fs:SetText(t and Theme.Paint(t[1], t[2]) or Theme.DASH)
		else
			local text = RP.AgeText(r.age)
			fs:SetText(not r.age and Theme.Paint("spark", "none") or (r.age > RP.STALE and Theme.Paint("spark", text))
				or (r.age < 3600 and Theme.Paint("good", text)) or text)
		end
	end
end

-- The menu for a status or role cell.
function Roster.CellItems(r, key)
	local OD = SK.OfficerDir
	local function done(ok, why)
		if not ok then SK:Print("Couldn't change it: %s.", tostring(why)) end
		Roster:Refresh()
	end
	if key == "status" then
		return {
			{ text = "Raider", checked = r.status == "r", onClick = function() done(OD:SetStatus(r.guid, "r")) end },
			{ text = "Backup", checked = r.status == "b", onClick = function() done(OD:SetStatus(r.guid, "b")) end },
			{ text = "Social", checked = r.status == "s", onClick = function() done(OD:SetStatus(r.guid, "s")) end },
			{ text = "Not set", checked = r.status == nil, onClick = function() done(OD:SetStatus(r.guid, nil)) end },
		}
	end
	local t = r.tiers[key]
	return {
		{ text = "Main", checked = t == "m", onClick = function() done(OD:SetTier(r.guid, key, "m")) end },
		{ text = "Off", checked = t == "b", onClick = function() done(OD:SetTier(r.guid, key, "b")) end },
		{ text = "No", checked = t == nil, onClick = function() done(OD:SetTier(r.guid, key, nil)) end },
	}
end

local function rowTooltip(row, r)
	if r.section then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	Theme.TipLine(GameTooltip, Theme.ClassText(r.name, r.class) .. Theme.Paint("dim", "  " .. (r.rank ~= "" and r.rank or "")))
	if #r.alts > 0 then Theme.TipLine(GameTooltip, "Alts: " .. table.concat(r.alts, ", "), "dim", true) end
	if r.awayText then Theme.TipLine(GameTooltip, "Away: " .. r.awayText, "bad", true) end
	for _, n in ipairs(r.notes) do
		local who = nameOf(n.by) or "?"
		Theme.TipLine(GameTooltip, Theme.Paint("dim", who .. ": ") .. n.text, "text", true)
	end
	Theme.TipLine(GameTooltip, "Click: their character page.", "accent")
	GameTooltip:Show()
end

-- Clickable cells: a pill for status and roles, the note text for notes.
local function decoratePlanRow(row)
	row.span = Theme.Text(row, "small", "dim")
	row.span:SetPoint("LEFT", SP.s, 0)
	row.span:SetPoint("RIGHT", -SP.s, 0)
	row.span:SetJustifyH("LEFT")
	row.span:SetWordWrap(false)
	row.span:Hide()
	row.band = row:CreateTexture(nil, "BACKGROUND", nil, 0)
	row.band:SetAllPoints()
	Theme.Solid(row.band, "rule")
	row.band:Hide()
	row.hits = {}
	local x = 0
	for _, col in ipairs(Roster.PLAN_COLUMNS) do
		if col.click then
			local b = CreateFrame("Button", nil, row)
			b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			local text = col.key == "note" or col.key == "away"
			local w = text and (col.width - SP.s) or Roster.PILL_W
			b:SetSize(w, S.row - 6)
			b:SetPoint("LEFT", x + (text and SP.xs or math.floor((col.width - w) / 2)), 0)
			b.fill = b:CreateTexture(nil, "BACKGROUND")
			b.fill:SetAllPoints()
			Theme.Solid(b.fill, "accent")
			b.fill:Hide()
			if not text then Theme.Border(b, "accent") end
			b.label = Theme.Text(b, col.key == "note" and "body" or "small", "text")
			b.label:SetPoint("LEFT", text and SP.xs or 0, 0)
			b.label:SetPoint("RIGHT", text and -SP.xs or 0, 0)
			b.label:SetJustifyH(text and "LEFT" or "CENTER")
			b.label:SetWordWrap(false)
			b.key = col.key
			b:SetScript("OnClick", function(self)
				local r = row.item
				if not r or r.section then return end
				if self.key == "note" then return Roster:OpenNotes(r, self) end
				if self.key == "away" then return Roster:OpenAway(r, self) end
				Roster.cellMenu:Open(self, Roster.CellItems(r, self.key))
			end)
			b:SetScript("OnEnter", function(self)
				local r = row.item
				if not r or r.section then return end
				GameTooltip:SetOwner(self, "ANCHOR_TOP")
				if self.key == "note" then
					if #r.notes == 0 then Theme.TipLine(GameTooltip, "No notes yet.", "dim") end
					for _, n in ipairs(r.notes) do
						Theme.TipLine(GameTooltip, Theme.Paint("dim", (nameOf(n.by) or "?") .. ": ") .. n.text, "text", true)
					end
					Theme.TipLine(GameTooltip, "Click to read or add notes.", "accent")
				elseif self.key == "away" then
					if #r.awayDays == 0 then Theme.TipLine(GameTooltip, "Not away in the next four weeks.", "dim") end
					for i, d in ipairs(r.awayDays) do
						if i > 8 then
							Theme.TipLine(GameTooltip, "+" .. (#r.awayDays - 8) .. " more", "faint")
							break
						end
						Theme.TipDouble(GameTooltip, date("%a %d %b", d.at), d.officer and "set by an officer" or "they marked it",
							"text", "dim")
					end
					if r.awayClash then Theme.TipLine(GameTooltip, "Clashes with a raid on the calendar.", "bad") end
					Theme.TipLine(GameTooltip, "Click for the calendar.", "accent")
				elseif self.key == "status" then
					Theme.TipLine(GameTooltip, "Raider, Backup or Social (not their guild rank). Click to change.", "accent", true)
				else
					Theme.TipLine(GameTooltip, SK.Data.ROLE_NAMES[self.key] .. ": Main, Off or no. Click to change.", "accent", true)
				end
				GameTooltip:Show()
			end)
			b:SetScript("OnLeave", function() GameTooltip:Hide() end)
			row.hits[#row.hits + 1] = b
		end
		x = x + col.width
	end
end

local function pill(b, tone, text)
	b.fill:SetShown(tone == "fill")
	Theme.SetBorderColor(b, "accent", (tone == "fill" or tone == "line") and 1 or 0)
	b.label:SetText(tone == "fill" and Theme.Paint("onAccent", text) or text)
end

local function updatePlanRow(row, r)
	local sec = r.section == true
	row.span:SetShown(sec)
	row.band:SetShown(sec)
	if sec then row.span:SetText(r.text .. (r.away and ("  ·  " .. Theme.Paint("bad", r.away)) or "")) end
	for _, b in ipairs(row.hits) do
		b:SetShown(not sec)
		if not sec then
			if b.key == "away" then
				b.label:SetText(r.awayText and Theme.Paint(r.awayClash and "bad" or "dim", r.awayText) or Theme.Paint("faint", "-"))
			elseif b.key == "note" then
				local n = #r.notes
				b.label:SetText(n == 0 and Theme.Paint("faint", "add") or (Theme.Paint("dim", r.note or "") ..
					(n > 1 and Theme.Paint("faint", " (+" .. (n - 1) .. ")") or "")))
			elseif b.key == "status" then
				local tone = r.status == "b" and "accent" or (r.status == "s" and "faint" or "dim")
				if r.status then pill(b, "plain", Theme.Paint(tone, RP.STATUS_NAME[r.status]))
				else pill(b, "plain", Theme.Paint("spark", "Not set")) end
			else
				local t = r.tiers[b.key]
				if t == "m" then pill(b, "fill", "Main")
				elseif t == "b" then pill(b, "line", Theme.Paint("accentLit", "Off"))
				else pill(b, "plain", Theme.Paint("faint", "·")) end
			end
		end
	end
end

function Roster:BuildOfficers(page)
	local ps = SK.DB.settings.planner
	local p = CreateFrame("Frame", nil, page)
	p:SetPoint("TOPLEFT", 0, -(S.control + SP.m))
	p:SetPoint("BOTTOMRIGHT")
	p:Hide()
	self.offPanel = p
	-- Row 1: role chips with counts, then status filters.
	self.roleChips = {}
	local prev
	for _, k in ipairs({ "A", "T", "H", "D", "N" }) do
		local c = W.Chip(p, k, function()
			ps.role = k
			Roster:Refresh()
		end)
		c.value = k
		if prev then c:SetPoint("LEFT", prev, "RIGHT", SP.xs, 0) else c:SetPoint("TOPLEFT", 0, 0) end
		self.roleChips[#self.roleChips + 1] = c
		prev = c
	end
	self.statusChips = {}
	for i, st in ipairs({ { "r", "Raider" }, { "b", "Backup" }, { "s", "Social" } }) do
		local c = W.Chip(p, st[2], function()
			ps.status = ps.status ~= st[1] and st[1] or nil
			Roster:Refresh()
		end)
		c.value = st[1]
		c:SetPoint("LEFT", prev, "RIGHT", i == 1 and SP.l or SP.xs, 0)
		self.statusChips[#self.statusChips + 1] = c
		prev = c
	end
	self.needsChip = W.Chip(p, "Needs a look", function()
		ps.needs = not ps.needs
		Roster:Refresh()
	end)
	self.needsChip.tooltip = "Not level 60, not attuned to Onyxia, missing enchants, no addon, or data a week old."
	self.needsChip:SetPoint("LEFT", prev, "RIGHT", SP.xs, 0)
	-- Row 2: the summary (or a hint) and the sign-ups menu.
	self.signupMenu = W.Menu(p, {
		width = 200,
		items = function()
			local out = { { value = "", text = "Sign-ups: none" } }
			local board = SK.RaidBoard:Get()
			for _, e in ipairs(board and SK.RaidBoard.Upcoming(board, SK.Compat.Now()) or {}) do
				local raid = SK.RaidBoard.Raid(e.raid)
				out[#out + 1] = { value = e.id, text = "Sign-ups: " .. date("%a %d %b", e.at) .. " " .. ((raid and raid.short) or e.raid) }
			end
			return out
		end,
		get = function() return Roster.signupsFor or "" end,
		set = function(v)
			Roster.signupsFor = v ~= "" and v or nil
			Roster:Refresh()
		end,
	})
	self.signupMenu.tooltip = "Pick a raid to see who signed up for it (in the last column)."
	self.signupMenu:SetPoint("TOPRIGHT", 0, -(S.control + SP.s))
	self.planSummary = Theme.Text(p, "small", "dim")
	self.planSummary:SetPoint("TOPLEFT", 0, -(S.control + SP.s + 5))
	self.planSummary:SetPoint("RIGHT", self.signupMenu, "LEFT", -SP.m, 0)
	self.planSummary:SetJustifyH("LEFT")
	self.planSummary:SetWordWrap(false)
	-- The table.
	self.cellMenu = W.PopMenu(p, 120)
	self.offList = W.List(p, {
		columns = Roster.PLAN_COLUMNS, setCell = setPlanCell, decorate = decoratePlanRow, update = updatePlanRow,
		onClick = function(r)
			if r.section then return end
			SK.CharacterTab:ShowCharacter(r.guid)
		end,
		onEnter = rowTooltip,
	})
	self.offList:SetPoint("TOPLEFT", 0, -(2 * S.control + SP.s + SP.m))
	self.offList:SetPoint("BOTTOMRIGHT")
	self:BuildNotes(p)
	self:BuildAway(p)
end

---------------------------------------------------------------------------
-- The away calendar (click an Away cell): a month like Raids → Calendar.
-- Raid days are marked; the player's own away days (from their Calendar)
-- show outlined; officers click days to mark them away (filled red).
---------------------------------------------------------------------------
Roster.CAL_CELL_W, Roster.CAL_CELL_H = 30, 20

function Roster:BuildAway(p)
	local W7, H6 = 7 * (Roster.CAL_CELL_W + 2), 6 * (Roster.CAL_CELL_H + 2)
	local box = CreateFrame("Frame", nil, p)
	box:SetSize(W7 + 2 * SP.m, W.CARD_LABEL_H + S.control + 16 + H6 + 2 * SP.m + 18)
	box:SetFrameStrata("FULLSCREEN_DIALOG")
	box:EnableMouse(true)
	Theme.Panel(box, { bg = "raised", border = "accent" })
	box:Hide()
	self.awayBox = box
	box.title = Theme.Text(box, "body", "text")
	box.title:SetPoint("TOPLEFT", SP.m, -SP.s)
	box.close = W.CloseButton(box, function() Roster:CloseAway() end)
	box.close:SetPoint("TOPRIGHT", -SP.xs, -SP.xs)
	local top = -(SP.s + W.CARD_LABEL_H)
	box.prev = W.Button(box, "<", S.control, S.control, function() Roster:ShiftAway(-1) end)
	box.prev:SetPoint("TOPLEFT", SP.m, top)
	box.next = W.Button(box, ">", S.control, S.control, function() Roster:ShiftAway(1) end)
	box.next:SetPoint("TOPRIGHT", -SP.m, top)
	box.month = Theme.Text(box, "body", "text")
	box.month:SetPoint("TOP", 0, top - 6)
	local y = top - S.control - SP.xs
	for i, d in ipairs({ "M", "T", "W", "T", "F", "S", "S" }) do
		local l = Theme.Text(box, "small", "faint")
		l:SetText(d)
		l:SetPoint("TOP", box, "TOPLEFT", SP.m + (i - 1) * (Roster.CAL_CELL_W + 2) + Roster.CAL_CELL_W / 2, y)
	end
	y = y - 16
	box.cells = {}
	for i = 1, 42 do
		local c = CreateFrame("Button", nil, box)
		c:SetSize(Roster.CAL_CELL_W, Roster.CAL_CELL_H)
		c:SetPoint("TOPLEFT", SP.m + ((i - 1) % 7) * (Roster.CAL_CELL_W + 2), y - math.floor((i - 1) / 7) * (Roster.CAL_CELL_H + 2))
		c.fill = c:CreateTexture(nil, "BACKGROUND")
		c.fill:SetAllPoints()
		Theme.Border(c, "bad")
		c.raid = c:CreateTexture(nil, "ARTWORK")
		c.raid:SetHeight(2)
		c.raid:SetPoint("BOTTOMLEFT", 3, 2)
		c.raid:SetPoint("BOTTOMRIGHT", -3, 2)
		Theme.Solid(c.raid, "accent")
		c.label = Theme.Text(c, "small", "text")
		c.label:SetPoint("CENTER")
		c:SetScript("OnClick", function(self)
			if self.cell and not self.cell.past and Roster.awayFor then
				local ok, why = SK.OfficerDir:ToggleAway(Roster.awayFor.guid, date("%Y-%m-%d", self.cell.at))
				if not ok then SK:Print("Couldn't change it: %s.", tostring(why)) end
				Roster:Refresh()
				Roster:DrawAway()
			end
		end)
		c:SetScript("OnEnter", function(self)
			local cell = self.cell
			if not cell then return end
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			Theme.TipLine(GameTooltip, date("%A %d %B", cell.at), "text")
			for _, rd in ipairs(cell.raids) do Theme.TipLine(GameTooltip, "Raid: " .. rd.text, "accent") end
			if cell.officer then Theme.TipLine(GameTooltip, "Away (set by an officer)", "bad") end
			if cell.away then Theme.TipLine(GameTooltip, "Away (they marked it on their Calendar)", "bad") end
			if not cell.past then
				Theme.TipLine(GameTooltip, cell.officer and "Click: not away" or "Click: mark away", "accent")
			end
			GameTooltip:Show()
		end)
		c:SetScript("OnLeave", function() GameTooltip:Hide() end)
		box.cells[i] = c
	end
	box.key = Theme.Text(box, "small", "dim")
	box.key:SetPoint("BOTTOMLEFT", SP.m, SP.s)
	box.key:SetPoint("BOTTOMRIGHT", -SP.m, SP.s)
	box.key:SetJustifyH("LEFT")
	box.key:SetWordWrap(false)
	box.key:SetText(Theme.Paint("bad", "Red") .. " away  ·  " .. Theme.Paint("bad", "Outline") .. " theirs  ·  " ..
		Theme.Paint("accent", "Line") .. " raid")
end

function Roster:OpenAway(r, anchor)
	local box = self.awayBox
	if box:IsShown() and self.awayFor and self.awayFor.guid == r.guid then return self:CloseAway() end
	self:CloseNotes()
	self.awayFor = r
	local t = date("*t", SK.Compat.Now())
	self.awayMonth = { t.year, t.month }
	box:ClearAllPoints()
	box:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -SP.xxs)
	box.title:SetText(Theme.ClassText(r.name, r.class) .. Theme.Paint("dim", "  away"))
	box:Show()
	self:DrawAway()
end

function Roster:CloseAway()
	if self.awayBox then self.awayBox:Hide() end
	self.awayFor = nil
end

function Roster:ShiftAway(delta)
	if not self.awayMonth then return end
	self.awayMonth = { SK.RaidsTab.ShiftMonth(self.awayMonth[1], self.awayMonth[2], delta) }
	self:DrawAway()
end

function Roster:DrawAway()
	local r, box = self.awayFor, self.awayBox
	if not r or not box:IsShown() then return end
	local guild = SK.DBM:Guild()
	local now = SK.Compat.Now()
	local officer = SK.OfficerDir.AwayOf(SK.OfficerDir:Get(guild), r.guid)
	local grid = SK.RaidsTab.MonthGrid(self.awayMonth[1], self.awayMonth[2], SK.RaidBoard:Get(guild), now,
		SK.Compat.PlayerGUID(), SK.Absences.Of(guild, r.guid))
	box.month:SetText(grid.title)
	for i, c in ipairs(box.cells) do
		local cell = grid.cells[i]
		cell.officer = officer[date("%Y-%m-%d", cell.at)] == true
		c.cell = cell
		local tone = (cell.officer and "onAccent") or (not cell.inMonth or cell.past) and "faint" or "text"
		c.label:SetText(Theme.Paint(tone, tostring(cell.day)))
		Theme.Solid(c.fill, cell.officer and "bad" or (cell.today and "accent" or "surface"),
			(cell.officer and 1) or (cell.today and Theme.ALPHA.selected) or 1)
		Theme.SetBorderColor(c, "bad", (cell.away and not cell.officer) and 1 or 0)
		c.raid:SetShown(#cell.raids > 0)
	end
	local row
	for _, x in ipairs(self.offList.items or {}) do if x.guid == r.guid then row = x end end
	if row then self.awayFor = row end
end

-- The notes box: everyone's notes on one player, and mine to write.
function Roster:BuildNotes(p)
	local box = CreateFrame("Frame", nil, p)
	box:SetSize(330, 170)
	box:SetFrameStrata("FULLSCREEN_DIALOG")
	box:EnableMouse(true)
	Theme.Panel(box, { bg = "raised", border = "accent" })
	box:Hide()
	self.noteBox = box
	box.title = Theme.Text(box, "body", "text")
	box.title:SetPoint("TOPLEFT", SP.m, -SP.s)
	box.close = W.CloseButton(box, function() Roster:CloseNotes() end)
	box.close:SetPoint("TOPRIGHT", -SP.xs, -SP.xs)
	box.list = Theme.Text(box, "small", "text")
	box.list:SetPoint("TOPLEFT", SP.m, -(SP.s + 22))
	box.list:SetPoint("RIGHT", -SP.m, 0)
	box.list:SetJustifyH("LEFT")
	box.list:SetJustifyV("TOP")
	box.list:SetWordWrap(true)
	local field = CreateFrame("Frame", nil, box)
	field:SetPoint("BOTTOMLEFT", SP.m, SP.m + S.control + SP.s)
	field:SetPoint("BOTTOMRIGHT", -SP.m, SP.m + S.control + SP.s)
	field:SetHeight(S.control)
	Theme.Panel(field, { bg = "void", border = "lineStrong" })
	local edit = CreateFrame("EditBox", nil, field)
	edit:SetPoint("TOPLEFT", SP.s, 0)
	edit:SetPoint("BOTTOMRIGHT", -SP.s, 0)
	edit:SetAutoFocus(false)
	edit:SetMaxLetters(SK.OfficerDir.NOTE_MAX)
	Theme.Font(edit, "small", "text")
	edit:SetScript("OnEscapePressed", function() Roster:CloseNotes() end)
	edit:SetScript("OnEnterPressed", function() Roster:SaveMyNote() end)
	box.edit = edit
	box.save = W.Button(box, "Save my note", nil, S.control, function() Roster:SaveMyNote() end, "primary")
	box.save:SetPoint("BOTTOMLEFT", SP.m, SP.m)
	box.remove = W.Button(box, "Remove mine", nil, S.control, function()
		box.edit:SetText("")
		Roster:SaveMyNote()
	end)
	box.remove:SetPoint("LEFT", box.save, "RIGHT", SP.s, 0)
	box.hint = Theme.Text(box, "small", "faint")
	box.hint:SetPoint("LEFT", box.remove, "RIGHT", SP.m, 0)
	box.hint:SetPoint("RIGHT", -SP.m, 0)
	box.hint:SetText("Officers only")
end

function Roster.NotesText(notes)
	if #notes == 0 then return Theme.Paint("dim", "No notes yet. Write the first one below.") end
	local lines = {}
	for i, n in ipairs(notes) do
		if i > 4 then
			lines[#lines + 1] = Theme.Paint("faint", "+" .. (#notes - 4) .. " more (hover the note cell)")
			break
		end
		lines[#lines + 1] = Theme.Paint("dim", (nameOf(n.by) or "?") .. ", " .. Theme.Ago(n.u, SK.Compat.Now()) ..
			(Theme.Ago(n.u, SK.Compat.Now()) == "now" and "" or " ago") .. ": ") .. n.text
	end
	return table.concat(lines, "\n")
end

function Roster:OpenNotes(r, anchor)
	self:CloseAway()
	local box = self.noteBox
	if box:IsShown() and self.notesFor == r.guid then return self:CloseNotes() end
	self.notesFor = r.guid
	box:ClearAllPoints()
	box:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -SP.xxs)
	box.title:SetText(Theme.ClassText(r.name, r.class) .. Theme.Paint("dim", "  notes"))
	box.list:SetText(Roster.NotesText(r.notes))
	local mine
	for _, n in ipairs(r.notes) do if n.mine then mine = n.text end end
	box.edit:SetText(mine or "")
	box.remove:SetShown(mine ~= nil)
	box:Show()
	box.edit:SetFocus()
end

function Roster:CloseNotes()
	self.noteBox:Hide()
	self.noteBox.edit:ClearFocus()
	self.notesFor = nil
end

function Roster:SaveMyNote()
	local guid = self.notesFor
	if not guid then return end
	local ok, why = SK.OfficerDir:SetMyNote(guid, self.noteBox.edit:GetText() or "")
	if not ok then SK:Print("Couldn't save the note: %s.", tostring(why)) end
	self:CloseNotes()
	self:Refresh()
end

function Roster:PlanRows()
	local guild = SK.DBM:Guild()
	local now = SK.Compat.Now()
	local signups
	if self.signupsFor then
		local board = SK.RaidBoard:Get(guild)
		signups = {}
		for guid, su in pairs(board and board.signups[self.signupsFor] or {}) do signups[guid] = su.s end
	end
	local raidDays = {}
	local board = SK.RaidBoard:Get(guild)
	for _, e in pairs(board and board.events or {}) do
		if not e.x and e.at >= now - 86400 then raidDays[date("%Y-%m-%d", e.at)] = true end
	end
	local rows = RP.Build({ guild = guild, dir = SK.OfficerDir:Get(guild) or {}, now = now, me = SK.Compat.PlayerGUID(),
		progress = SK.DB.rosterProgress, signups = signups, raidDays = raidDays,
		profile = function(g) return SK.Profile:Get(g, guild) end,
		isOwn = function(g) return SK.DB.account[g] == true end })
	RP.Record(SK.DB.rosterProgress, rows, now)
	return rows, guild, now
end

function Roster:RefreshOfficers()
	local ps = SK.DB.settings.planner
	local rows, guild = self:PlanRows()
	if self.signupsFor then
		local board = SK.RaidBoard:Get(guild)
		if not (board and board.events[self.signupsFor]) then self.signupsFor = nil end
	end
	local c = RP.Counts(rows)
	local label = { A = "All", T = "Tanks", H = "Healers", D = "DPS", N = "Not sorted" }
	for _, chip in ipairs(self.roleChips) do
		local k = chip.value
		local n = k == "A" and c.all or k == "N" and c.notSorted or (c[k].m .. "+" .. c[k].b)
		chip:SetText(label[k] .. "  " .. Theme.Paint(ps.role == k and "text" or "faint", tostring(n)))
		chip:SetActive(ps.role == k)
	end
	for _, chip in ipairs(self.statusChips) do chip:SetActive(ps.status == chip.value) end
	local needs = 0
	for _, r in ipairs(rows) do if r.needsLook then needs = needs + 1 end end
	self.needsChip:SetText("Needs a look  " .. Theme.Paint(ps.needs and "text" or "faint", tostring(needs)))
	self.needsChip:SetActive(ps.needs == true)
	local items = RP.View(rows, { role = ps.role or "A", status = ps.status, needs = ps.needs, search = self.filter })
	if (ps.role or "A") == "A" then
		self.planSummary:SetText(RP.SummaryText(RP.Summary(rows)))
	else
		self.planSummary:SetText("Click a status, role, away or note cell to change it. Click a name for their character.")
	end
	self.count:SetText(Theme.Count(#rows, "player") .. "  ·  officers only")
	self.signupMenu:Refresh()
	for i, col in ipairs(Roster.PLAN_COLUMNS) do
		local hb = self.offList.headerButtons[i]
		if col.key == "seen" then hb.text:SetText(self.signupsFor and "Signed" or "Seen") end
	end
	self.offList:SetEmptyText(Roster.EmptyText(guild ~= nil, self.filter))
	local list = self.offList
	if not list.wrapped then
		list.wrapped = true
		for _, col in ipairs(Roster.PLAN_COLUMNS) do
			if col.sort then col.sort = RP.GroupSort(col.sort, function() return list.sortDesc end) end
		end
	end
	if not list.sortCol then list:SortWith(RP.GroupSort(RP.DefaultOrder)) end
	list:SetItems(items)
end

-- The selected member's attendance line (Character page, officers). Pure; tested.
function Roster.AttendanceText(r, days)
	if not r or r.raids == 0 then return "Attendance (" .. days .. " days): no recorded raids yet" end
	return string.format("Attendance (%d days): %d%% of %d raids  ·  bench %d", days, r.pct or 0, r.raids, r.bench or 0)
end

-- What an empty roster says. Pure; tested.
function Roster.EmptyText(hasGuild, filter)
	if not hasGuild then return "You're not in a guild, so there's no roster to show." end
	if filter and filter ~= "" then return "Nobody matches \"" .. filter .. "\". Try a name, a profession or part of a note." end
	return "The guild roster hasn't loaded yet. It fills in a few seconds after login."
end

-- From the Overview's "Needs a look": the plain roster, sorted so the
-- people it's about come first.
function Roster:ShowSorted(fn)
	SK.DB.settings.roster.raid = nil
	SK.MainFrame:Select("roster")
	self.list:SortWith(fn)
end
function Roster:ShowOldestFirst() self:ShowSorted(Roster.ByData) end       -- missing and oldest data
function Roster:ShowWithoutAddon() self:ShowSorted(Roster.ByVersion) end   -- not seen with Short Royalty
function Roster:ShowOldVersions() self:ShowSorted(Roster.ByOldVersion) end -- running an old version

-- The list as shown (current filters and sort) as plain text.
function Roster:CopyText()
	local rs = SK.DB.settings.roster
	local raid = rs.raid and Roster.Raid(rs.raid)
	local list = raid and self.attList or self.list
	local title = "Short Royalty roster" .. (raid and (": " .. raid.name) or "")
	if self.filter and self.filter ~= "" then title = title .. " (search: " .. self.filter .. ")" end
	local text = SK.Export.Roster(list.items, { title = title, hideOwnGear = SK.DB.settings.share.gear == false })
	SK.DebugWindow:ShowText("Copy as text", text)
	return text
end

function Roster:Refresh()
	if not self.list then return end
	local guild = SK.DBM:Guild()
	local rs = SK.DB.settings.roster
	-- v0.10.1: the Officers view replaces the lists while it's on.
	local officer = SK.RaidBoard.OfficerView()
	self.officerChip:SetShown(officer)
	self.officerChip:SetActive(officer and rs.officer == true)
	local offOn = officer and rs.officer == true
	self.offPanel:SetShown(offOn)
	self.raidMenu:SetShown(not offOn)
	self.options:ClearAllPoints()
	self.options:SetPoint("LEFT", offOn and self.search or self.raidMenu, "RIGHT", SP.s, 0)
	if offOn then
		self.attBar:Hide()
		self.list:Hide()
		self.attList:Hide()
		return self:RefreshOfficers()
	end
	local raid = rs.raid and Roster.Raid(rs.raid)
	if raid and raid.hidden then raid = nil end -- not in the first raid wave
	if rs.raid and not raid then rs.raid = nil end
	self.raidMenu:Refresh()
	self.attBar:SetShown(raid ~= nil)
	self.list:SetShown(raid == nil)
	self.attList:SetShown(raid ~= nil)

	if raid then
		local noneNeeded = raid.status == "none"
		local rows, counts, maxLevel = Roster.AttunementRows(guild, raid.key, noneNeeded and "all" or rs.attFilter,
			rs.maxLevelOnly, self.filter, SK.Compat.Now())
		for _, t in ipairs(self.filterTabs) do
			t:SetActive(t.value == (rs.attFilter or "all"))
			t:SetShown(not noneNeeded)
		end
		self.maxCheck:Refresh()
		self.maxCheck:SetLabel(maxLevel > 0 and ("Max level only (" .. maxLevel .. ")") or "Max level only")
		if noneNeeded then
			self.attCount:SetText(Theme.Code("good") .. "No attunement needed for this raid.|r")
		elseif raid.status == "todo" then
			self.attCount:SetText(Theme.Paint("spark", "Attunement quests for this raid aren't known yet."))
		else
			self.attCount:SetText(string.format("%d attuned · %d not · %d unknown", counts.yes, counts.no, counts.unknown))
		end
		self.count:SetText(Theme.Count(counts.yes + counts.no + counts.unknown + counts.none, "character"))
		self.attList:SetEmptyText(Roster.EmptyText(guild ~= nil, self.filter))
		self.attList:SetItems(rows)
		return
	end

	local rows = Roster.Rows(guild, SK.Compat.Now(), self.filter, SK.DB.settings.groupAlts)
	local withData, outdated, total = 0, 0, 0
	for _, r in ipairs(rows) do
		for _, x in ipairs({ r, unpack(r.alts or {}) }) do
			total = total + 1
			if x.hasData then withData = withData + 1 end
			if x.outdated then outdated = outdated + 1 end
		end
	end
	local text = Theme.Count(total, "character") .. "  ·  " .. withData .. " with data"
	if outdated > 0 then text = text .. "  ·  " .. Theme.Paint("spark", outdated .. " to update") end
	self.count:SetText(text)
	self.list:SetEmptyText(Roster.EmptyText(guild ~= nil, self.filter))
	self.list:SetItems(rows)
end

SK.MainFrame:AddTab("roster", "Roster", Roster, { group = "guild",
	desc = "Everyone in the guild. Click a name for their gear, talents and professions." })
