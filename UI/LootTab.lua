-- Loot page (v0.9.0 Reserve+). Everyone: Reserves (pick tonight's
-- reserves, see who reserved what), Points (mine, everyone's) and History.
-- Officers and raid leaders with /sr officer: Loot night (rolls, award, end
-- of night) and Rules (reserves per raid, bonus, loot list), plus changing
-- points by hand on the Points tab. Rules live in Core/Reserves.lua and
-- Core/LootNight.lua.
local _, SK = ...

local LT = SK:NewModule("LootTab")
local Theme, W, Compat = SK.Theme, SK.Widgets, SK.Compat
local R, LN, Board = SK.Reserves, SK.LootNight, SK.RaidBoard
local S, SP = Theme.SIZES, Theme.SPACE
local C = Theme.Code

LT.VIEWS = { { "reserves", "Reserves" }, { "points", "Points" }, { "history", "History" },
	{ "night", "Loot night" }, { "rules", "Rules" } }
LT.OFFICER_VIEWS = { night = true, rules = true }
LT.LEFT_W = 330
LT.RIGHT_W = S.contentW - LT.LEFT_W - SP.xl
LT.NIGHT_LEFT_W = 270
LT.NIGHT_RIGHT_W = S.contentW - LT.NIGHT_LEFT_W - SP.xl
LT.FORM_W = 280

local function nameOf(guid)
	local m = SK.Identity:Member(guid)
	return m and m.name or "?", m and m.class
end
local function who(guid)
	local n, cls = nameOf(guid)
	return Theme.ClassText(n, cls)
end
local function itemText(id)
	local name = SK.CraftIndex.ItemName(id) or ("item " .. id)
	local hex = Compat.ItemQualityHex(id)
	return hex and ("|c" .. hex .. name .. "|r") or name
end
LT.ItemText = itemText
local function pts(n)
	if not n or n == 0 then return Theme.DASH end
	return Theme.Paint(n < 0 and "bad" or "accent", tostring(n))
end

---------------------------------------------------------------------------
-- Pure helpers (tested)
---------------------------------------------------------------------------
function LT.View(officer)
	local v = SK.DB.settings.lootView
	if LT.OFFICER_VIEWS[v] and not officer then return "reserves" end
	for _, x in ipairs(LT.VIEWS) do if x[1] == v then return v end end
	return "reserves"
end

-- An item link or a number typed or pasted by an officer -> item ID.
function LT.ParseItem(text)
	if type(text) ~= "string" then return nil end
	local id = tonumber(text:match("item:(%d+)") or text:match("^%s*(%d+)%s*$"))
	return R.IsItem(id) and id or nil
end

-- "Shard of the Scale ×2, Deathbringer" from a list of item IDs.
function LT.PicksText(items, name)
	local counts, order = {}, {}
	for _, i in ipairs(items) do
		if not counts[i] then order[#order + 1] = i end
		counts[i] = (counts[i] or 0) + 1
	end
	local parts = {}
	for _, i in ipairs(order) do
		parts[#parts + 1] = (name or itemText)(i) .. (counts[i] > 1 and (" ×" .. counts[i]) or "")
	end
	return table.concat(parts, ", ")
end

-- History rows, newest first. filter = "all" | "mine" | "hand".
function LT.HistoryRows(store, st, me, filter)
	local rows = {}
	local list = R.Ordered(store)
	for n = #list, 1, -1 do
		local e = list[n]
		local mine = (e.g == me or e.g2 == me) or (e.k == "n" and e.g[me] ~= nil)
		local hand = e.k == "a" or e.k == "m" or e.k == "x"
		if filter == "all" or (filter == "mine" and mine) or (filter == "hand" and hand) then
			rows[#rows + 1] = { e = e, undone = st.undone[e.id] ~= nil }
		end
	end
	return rows
end

-- Everyone's points: { guid, item, points } for every non-zero number.
function LT.AllPoints(st, query, nameFn, itemFn)
	local out = {}
	query = query and query ~= "" and query:lower() or nil
	for g, items in pairs(st.points) do
		for i, p in pairs(items) do
			if p ~= 0 then
				local hit = not query
				if query then
					hit = (nameFn(g) or ""):lower():find(query, 1, true) ~= nil
						or (itemFn(i) or ""):lower():find(query, 1, true) ~= nil
				end
				if hit then out[#out + 1] = { guid = g, item = i, points = p } end
			end
		end
	end
	table.sort(out, function(a, b)
		if a.points ~= b.points then return a.points > b.points end
		if a.guid ~= b.guid then return a.guid < b.guid end
		return a.item < b.item
	end)
	return out
end

---------------------------------------------------------------------------
-- Columns and cells
---------------------------------------------------------------------------
LT.ITEM_COLUMNS = {
	{ key = "item", title = "Item", width = 200 },
	{ key = "mine", title = "Points", width = 64, align = "RIGHT" },
	{ key = "count", title = "Reserved", width = LT.LEFT_W - 264 - SP.m, align = "RIGHT" },
}
LT.WHO_COLUMNS = {
	{ key = "name", title = "Name", width = 120 },
	{ key = "item", title = "Reserve", width = LT.RIGHT_W - 120 - 64 - SP.m },
	{ key = "points", title = "Points", width = 64, align = "RIGHT" },
}
LT.MINE_COLUMNS = {
	{ key = "item", title = "Item", width = 210 },
	{ key = "points", title = "Points", width = 60, align = "RIGHT" },
	{ key = "note", title = "", width = 120 },
}
LT.WHY_COLUMNS = {
	{ key = "date", title = "Date", width = 90 },
	{ key = "what", title = "What", width = S.contentW - 410 - SP.xl - 90 - 60 - SP.m },
	{ key = "d", title = "Points", width = 60, align = "RIGHT" },
}
LT.ALL_COLUMNS = {
	{ key = "name", title = "Name", width = 130 },
	{ key = "item", title = "Item", width = 200 },
	{ key = "points", title = "Points", width = 70, align = "RIGHT" },
}
LT.HISTORY_COLUMNS = {
	{ key = "when", title = "When", width = 92 },
	{ key = "kind", title = "Change", width = 112 },
	{ key = "who", title = "Who", width = 100 },
	{ key = "item", title = "Item", width = 160 },
	{ key = "d", title = "Points", width = 60, align = "RIGHT" },
	{ key = "by", title = "By", width = 70 },
	{ key = "why", title = "Reason", width = S.contentW - 92 - 112 - 100 - 160 - 60 - 70 - SP.m },
}
LT.DROP_COLUMNS = {
	{ key = "item", title = "Dropped", width = 190 },
	{ key = "count", title = "Reserved", width = LT.NIGHT_LEFT_W - 190 - SP.m, align = "RIGHT" },
}
LT.ROLL_COLUMNS = {
	{ key = "name", title = "Name", width = 130 },
	{ key = "res", title = "", width = 96 },
	{ key = "roll", title = "Roll", width = 50, align = "RIGHT" },
	{ key = "bonus", title = "Points", width = 60, align = "RIGHT" },
	{ key = "total", title = "Total", width = LT.NIGHT_RIGHT_W - 130 - 96 - 50 - 60 - SP.m, align = "RIGHT" },
}
LT.END_COLUMNS = {
	{ key = "name", title = "Name", width = 130 },
	{ key = "items", title = "Reserves", width = 230 },
	{ key = "result", title = "Result", width = 80 },
	{ key = "why", title = "Why", width = S.contentW - 130 - 230 - 80 - SP.m },
}

local RESULT = { bonus = { "good", nil }, won = { "accent", "Won it" }, nothing = { "faint", "Nothing" }, out = { "spark", "Left out" } }

local function setCell(fs, r, col)
	local k = col.key
	local v = r[k]
	if k == "name" then fs:SetText(who(r.guid))
	elseif k == "item" and type(v) == "number" then fs:SetText(itemText(v))
	elseif k == "points" or k == "mine" or k == "bonus" then fs:SetText(pts(v))
	else fs:SetText(v ~= nil and tostring(v) or Theme.DASH) end
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
local function frame(page, top)
	local f = CreateFrame("Frame", nil, page)
	f:SetPoint("TOPLEFT", 0, top)
	f:SetPoint("BOTTOMRIGHT")
	return f
end
local function line(parent, role, color)
	local fs = Theme.Text(parent, role or "small", color or "dim")
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(true)
	return fs
end
local function label(parent, text)
	local fs = Theme.Text(parent, "label", "dim")
	fs:SetText(text:upper())
	return fs
end

-- A small "−  value  +" control for the Rules cards.
local function stepper(parent, get, set, step)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(S.controlSmall * 2 + 44 + SP.xs * 2, S.controlSmall)
	local minus = W.Button(f, "−", S.controlSmall, S.controlSmall, function() set(get() - (step or 1)); f:Refresh() end)
	minus:SetPoint("LEFT")
	local value = Theme.Text(f, "body", "accent")
	value:SetPoint("LEFT", minus, "RIGHT", SP.xs, 0)
	value:SetWidth(44)
	value:SetJustifyH("CENTER")
	local plus = W.Button(f, "+", S.controlSmall, S.controlSmall, function() set(get() + (step or 1)); f:Refresh() end)
	plus:SetPoint("LEFT", value, "RIGHT", SP.xs, 0)
	function f:Refresh() value:SetText(tostring(get())) end
	f:Refresh()
	return f
end

function LT:Build(page)
	self.page = page
	local s = SK.DB.settings
	self.views = W.SubTabs(page, LT.VIEWS, function(k)
		s.lootView = k
		LT:Refresh()
	end)
	self.views:SetPoint("TOPLEFT", 0, 0)
	self.views:SetPoint("TOPRIGHT", 0, 0)
	self.bonusLine = Theme.Text(page, "small", "dim")
	self.bonusLine:SetPoint("TOPRIGHT", 0, -SP.s)
	local top = -(S.subTabs + SP.m)

	-------------------------------------------------------------------------
	-- Reserves
	-------------------------------------------------------------------------
	local rv = frame(page, top)
	self.resPage = rv
	self.raidMenu = W.Menu(rv, {
		width = 260,
		items = function()
			local out = {}
			for _, e in ipairs(Board.Upcoming(Board:Get() or Board.New(), Compat.Now())) do
				local raid = Board.Raid(e.raid)
				out[#out + 1] = { value = e.id, text = (raid and raid.name or e.raid) .. ", " .. Board.ShortWhen(e.at, Compat.Now()) }
			end
			return out
		end,
		get = function() return LT.raidID end,
		set = function(v) LT.raidID = v; LT:Refresh() end,
	})
	self.raidMenu:SetPoint("TOPLEFT")
	self.mineLine = line(rv, "body", "text")
	self.mineLine:SetPoint("TOPLEFT", 0, -(S.control + SP.s))
	self.mineLine:SetPoint("RIGHT")
	self.mineLine:SetHeight(18)
	local listTop = -(S.control + SP.s + 18 + SP.m)
	self.itemList = W.List(rv, {
		columns = LT.ITEM_COLUMNS, setCell = setCell,
		onClick = function(r) LT.item = r.item; LT:Refresh() end,
	})
	self.itemList:SetPoint("TOPLEFT", 0, listTop)
	self.itemList:SetPoint("BOTTOMLEFT", 0, S.control + SP.m)
	self.itemList:SetWidth(LT.LEFT_W)
	self.itemList:SetEmptyText("No loot list for this raid yet. Officers add items, and drops are learned.")
	self.reserveBtn = W.Button(rv, "Reserve this", nil, S.control, function() LT:Reserve() end, "primary")
	self.reserveBtn:SetPoint("BOTTOMLEFT")
	self.clearBtn = W.Button(rv, "Clear mine", nil, S.control, function() LT:ClearMine() end)
	self.clearBtn:SetPoint("LEFT", self.reserveBtn, "RIGHT", SP.s, 0)
	self.resNote = line(rv)
	self.resNote:SetPoint("LEFT", self.clearBtn, "RIGHT", SP.m, 0)
	self.resNote:SetPoint("RIGHT")
	self.whoLabel = label(rv, "Who reserved what")
	self.whoLabel:SetPoint("TOPLEFT", LT.LEFT_W + SP.xl, listTop + 16)
	self.whoList = W.List(rv, { columns = LT.WHO_COLUMNS, setCell = setCell })
	self.whoList:SetPoint("TOPLEFT", LT.LEFT_W + SP.xl, listTop)
	self.whoList:SetPoint("BOTTOMRIGHT")
	self.whoList:SetEmptyText("Nobody has reserved yet.")

	-------------------------------------------------------------------------
	-- Points
	-------------------------------------------------------------------------
	local pv = frame(page, top)
	self.ptsPage = pv
	self.ptsChips = {}
	local prev
	for _, m in ipairs({ { "mine", "Mine" }, { "all", "Everyone" } }) do
		local c = W.Chip(pv, m[2], function() s.lootPoints = m[1]; LT:Refresh() end)
		c.value = m[1]
		if prev then c:SetPoint("LEFT", prev, "RIGHT", SP.xs, 0) else c:SetPoint("TOPLEFT") end
		self.ptsChips[#self.ptsChips + 1] = c
		prev = c
	end
	self.ptsSearch = W.SearchBox(pv, 200, "Search name or item", function(text) LT.query = text; LT:Refresh() end)
	self.ptsSearch:SetPoint("LEFT", prev, "RIGHT", SP.l, 0)
	self.ptsNote = line(pv)
	self.ptsNote:SetPoint("LEFT", prev, "RIGHT", SP.l, 0)
	self.ptsNote:SetPoint("RIGHT")
	local pTop = -(S.control + SP.m)
	self.mineList = W.List(pv, {
		columns = LT.MINE_COLUMNS, setCell = setCell,
		onClick = function(r) LT.whyItem = r.item; LT:Refresh() end,
	})
	self.mineList:SetPoint("TOPLEFT", 0, pTop)
	self.mineList:SetPoint("BOTTOMLEFT")
	self.mineList:SetWidth(410)
	self.mineList:SetEmptyText("No points yet. Reserve an item and raid: every night you don't get it, it gains the bonus.")
	self.whyTitle = Theme.Text(pv, "title", "text")
	self.whyTitle:SetPoint("TOPLEFT", 410 + SP.xl, pTop - SP.xxs)
	self.whyList = W.List(pv, { columns = LT.WHY_COLUMNS, setCell = function(fs, r, col)
		if col.key == "d" then fs:SetText(r.d == 0 and Theme.DASH or Theme.Paint(r.d > 0 and "good" or "bad", (r.d > 0 and "+" or "") .. r.d))
		elseif col.key == "date" then fs:SetText(date("%d %b", r.c))
		else fs:SetText((R.KIND_NAME[r.k] or r.k) .. (r.r and (C("dim") .. " · " .. r.r .. "|r") or "")) end
	end })
	self.whyList:SetPoint("TOPLEFT", 410 + SP.xl, pTop - 28)
	self.whyList:SetPoint("BOTTOMRIGHT")
	self.allList = W.List(pv, {
		columns = LT.ALL_COLUMNS, setCell = setCell,
		onClick = function(r) LT.form.g, LT.form.i = r.guid, r.item; LT:Refresh() end,
	})
	self.allList:SetPoint("TOPLEFT", 0, pTop)
	self.allList:SetPoint("BOTTOMLEFT")
	self.allList:SetWidth(S.contentW)
	self.allList:SetEmptyText("Nobody has points yet.")
	self:BuildForm(pv, pTop)

	-------------------------------------------------------------------------
	-- History
	-------------------------------------------------------------------------
	local hv = frame(page, top)
	self.histPage = hv
	self.histChips = {}
	prev = nil
	for _, m in ipairs({ { "all", "All" }, { "mine", "Mine" }, { "hand", "By hand" } }) do
		local c = W.Chip(hv, m[2], function() s.lootHistory = m[1]; LT:Refresh() end)
		c.value = m[1]
		if prev then c:SetPoint("LEFT", prev, "RIGHT", SP.xs, 0) else c:SetPoint("TOPLEFT") end
		self.histChips[#self.histChips + 1] = c
		prev = c
	end
	self.histList = W.List(hv, {
		columns = LT.HISTORY_COLUMNS,
		setCell = function(fs, r, col) LT.HistoryCell(fs, r, col) end,
		onClick = function(r, button)
			if button == "RightButton" and Board.OfficerView() and not r.undone and r.e.k ~= "x" then
				local e, why = R:Undo(r.e.id, "Undone by " .. (nameOf(Compat.PlayerGUID())))
				if not e then SK:Print("Couldn't undo: %s.", tostring(why)) end
				LT:Refresh()
			end
		end,
	})
	self.histList:SetPoint("TOPLEFT", 0, -(S.control + SP.m))
	self.histList:SetPoint("BOTTOMRIGHT", 0, 16 + SP.s)
	self.histList:SetEmptyText("Nothing yet.")
	self.histNote = line(hv)
	self.histNote:SetPoint("BOTTOMLEFT")
	self.histNote:SetPoint("RIGHT")

	-------------------------------------------------------------------------
	-- Loot night (officers)
	-------------------------------------------------------------------------
	local nv = frame(page, top)
	self.nightPage = nv
	self.nightLine = line(nv)
	self.nightLine:SetPoint("TOPLEFT", 0, -SP.xs)
	self.nightLine:SetPoint("RIGHT", -260, 0)
	self.endBtn = W.Button(nv, "End of night", nil, S.control, function() LT.endMode = not LT.endMode; LT:Refresh() end)
	self.endBtn:SetPoint("TOPRIGHT")
	self.lockBtn = W.Button(nv, "Lock reserves", nil, S.control, function() LT:ToggleLock() end)
	self.lockBtn:SetPoint("RIGHT", self.endBtn, "LEFT", -SP.s, 0)
	local nTop = -(S.control + SP.m)
	self.dropList = W.List(nv, {
		columns = LT.DROP_COLUMNS, setCell = setCell,
		onClick = function(r) if LT.night then LN:Select(LT.night.e, r.item) end; LT:Refresh() end,
	})
	self.dropList:SetPoint("TOPLEFT", 0, nTop)
	self.dropList:SetPoint("BOTTOMLEFT", 0, 64 + S.control + SP.m * 2)
	self.dropList:SetWidth(LT.NIGHT_LEFT_W)
	self.dropList:SetEmptyText("Loot shows here when you open a boss's loot window.")
	self.addBox = W.SearchBox(nv, LT.NIGHT_LEFT_W - 70 - SP.s, "Item link or ID", function(text) LT.addText = text end)
	self.addBox:SetPoint("BOTTOMLEFT", 0, 64 + SP.m)
	self.addBtn = W.Button(nv, "Add", 70, S.control, function() LT:AddDrop() end)
	self.addBtn:SetPoint("LEFT", self.addBox, "RIGHT", SP.s, 0)
	self.check = line(nv)
	self.check:SetPoint("BOTTOMLEFT")
	self.check:SetWidth(LT.NIGHT_LEFT_W)
	self.check:SetHeight(64)
	self.check:SetJustifyV("BOTTOM")
	local rx = LT.NIGHT_LEFT_W + SP.xl
	self.curTitle = Theme.Text(nv, "title", "text")
	self.curTitle:SetPoint("TOPLEFT", rx, nTop - SP.xxs)
	self.curSub = line(nv)
	self.curSub:SetPoint("TOPLEFT", rx, nTop - 24)
	self.curSub:SetPoint("RIGHT")
	self.postBtn = W.Button(nv, "Post to raid chat", nil, S.control, function() LT:Post() end, "primary")
	self.postBtn:SetPoint("TOPLEFT", rx, nTop - 46)
	self.awardBtn = W.Button(nv, "Award", nil, S.control, function() LT:Award() end)
	self.awardBtn:SetPoint("LEFT", self.postBtn, "RIGHT", SP.s, 0)
	self.rerollBtn = W.Button(nv, "Re-roll", nil, S.control, function() LT:Reroll() end)
	self.rerollBtn:SetPoint("LEFT", self.awardBtn, "RIGHT", SP.s, 0)
	self.rollList = W.List(nv, {
		columns = LT.ROLL_COLUMNS,
		setCell = function(fs, r, col)
			if col.key == "res" then fs:SetText(r.reserved and Theme.Paint("accent", "Reserved") or Theme.Paint("faint", "No reserve"))
			elseif col.key == "total" then
				local tone = r.first and "good" or (r.reserved and "text" or "faint")
				fs:SetText(Theme.Paint(tone, tostring(r.total)) .. (r.tie and Theme.Paint("spark", " tie") or ""))
			elseif col.key == "roll" then fs:SetText(Theme.Paint(r.reserved and "text" or "faint", tostring(r.roll)))
			else setCell(fs, r, col) end
		end,
		onClick = function(r) LT.winner = r.guid; LT:Refresh() end,
	})
	self.rollList:SetPoint("TOPLEFT", rx, nTop - 46 - S.control - SP.m)
	self.rollList:SetPoint("BOTTOMRIGHT", 0, 16 + SP.s)
	self.rollList:SetEmptyText("Rolls show here. Pick an item on the left, post it, and players /roll.")
	self.rollNote = line(nv)
	self.rollNote:SetPoint("BOTTOMLEFT", rx, 0)
	self.rollNote:SetPoint("RIGHT")
	-- End of night
	self.endList = W.List(nv, {
		columns = LT.END_COLUMNS,
		setCell = function(fs, r, col)
			if col.key == "items" then fs:SetText(LT.PicksText(r.items))
			elseif col.key == "result" then
				local t = RESULT[r.result]
				fs:SetText(Theme.Paint(t[1], t[2] or ("+" .. (R:State().bonus * #(r.bonusItems or {})))))
			elseif col.key == "why" then fs:SetText(Theme.Paint("dim", r.why))
			else setCell(fs, r, col) end
		end,
		onClick = function(r)
			if LT.night and (r.result == "bonus" or r.result == "out") then LN:ToggleOut(LT.night.e, r.guid) end
			LT:Refresh()
		end,
	})
	self.endList:SetPoint("TOPLEFT", 0, nTop - 24)
	self.endList:SetPoint("BOTTOMRIGHT", 0, S.control + SP.m)
	self.endSum = line(nv, "body", "text")
	self.endSum:SetPoint("TOPLEFT", 0, nTop)
	self.endSum:SetPoint("RIGHT")
	self.saveBtn = W.Button(nv, "Save the bonus", nil, S.control, function() LT:SaveNight() end, "primary")
	self.saveBtn:SetPoint("BOTTOMLEFT")
	self.endNote = line(nv)
	self.endNote:SetPoint("LEFT", self.saveBtn, "RIGHT", SP.m, 0)
	self.endNote:SetPoint("RIGHT")

	-------------------------------------------------------------------------
	-- Rules (officers)
	-------------------------------------------------------------------------
	local ru = frame(page, top + -SP.xs)
	self.rulesPage = ru
	local half = math.floor((S.contentW - SP.l) / 2)
	self.picksCard = W.SettingsCard(ru, half, "Reserves per player")
	self.picksCard:SetPoint("TOPLEFT")
	for _, raid in ipairs(SK.Data.ShownAttunements()) do
		self.picksCard:AddControl(string.format("%s (%d)", raid.name, raid.size or 0), nil, function(row)
			return stepper(row, function() return R.PicksFor(R:State(), raid.key) end, function(n)
				n = math.max(1, math.min(R.MAX_PICKS, n))
				if n ~= R.PicksFor(R:State(), raid.key) then LT:Result(R:SetPicks(raid.key, n)) end
			end)
		end)
	end
	self.picksCard:Finish()
	self.picksCard:SetNote("Set it before people reserve. Two reserves may go on the same item: double points, one roll.")
	self.pointsCard = W.SettingsCard(ru, half, "Points")
	self.pointsCard:SetPoint("TOPLEFT", half + SP.l, 0)
	self.pointsCard:AddControl("Bonus per night", "For each reserve someone didn't get.", function(row)
		return stepper(row, function() return R:State() and R:State().bonus or R.DEFAULT_BONUS end, function(n)
			n = math.max(0, math.min(R.MAX_BONUS, n))
			LT:Result(R:SetBonus(n))
		end, 5)
	end)
	self.pointsCard:AddControl("Bench", "Gets the bonus if online when reserves are locked.", function(row)
		local t = Theme.Text(row, "body", "dim"); t:SetText("Yes"); return t
	end)
	self.pointsCard:AddControl("Cap", "None: points keep growing until you win.", function(row)
		local t = Theme.Text(row, "body", "dim"); t:SetText("None"); return t
	end)
	self.pointsCard:Finish()
	self.pointsCard:SetNote("Changes count from now on, never backwards.")
	local lootY = -(W.CARD_LABEL_H + 4 * S.settingRow + SP.xl)
	local ll = label(ru, "Add an item to a raid's loot list")
	ll:SetPoint("TOPLEFT", 0, lootY)
	self.lootRaidMenu = W.Menu(ru, {
		width = 200,
		items = function()
			local out = {}
			for _, raid in ipairs(SK.Data.ShownAttunements()) do out[#out + 1] = { value = raid.key, text = raid.name } end
			return out
		end,
		get = function() return LT.lootRaid or "ony" end,
		set = function(v) LT.lootRaid = v end,
	})
	self.lootRaidMenu:SetPoint("TOPLEFT", 0, lootY - W.CARD_LABEL_H)
	self.lootBox = W.SearchBox(ru, 220, "Item link or ID", function(text) LT.lootText = text end)
	self.lootBox:SetPoint("LEFT", self.lootRaidMenu, "RIGHT", SP.s, 0)
	self.lootAdd = W.Button(ru, "Add", 70, S.control, function() LT:AddLootItem() end)
	self.lootAdd:SetPoint("LEFT", self.lootBox, "RIGHT", SP.s, 0)
	self.rulesNote = line(ru)
	self.rulesNote:SetPoint("BOTTOMLEFT")
	self.rulesNote:SetPoint("RIGHT")
	self.rulesNote:SetText("Every change here goes in the History with your name, and everyone's addon uses it once " ..
		"it reaches them. Shift-click an item (from your bags or AtlasLoot) into the box to paste its link. " ..
		"To take an item off a list, right-click its \"Loot list\" line in the History.")

	SK:On("RESERVES_UPDATED", function() if page:IsShown() then LT:Refresh() end end)
	SK:On("LOOTNIGHT_UPDATED", function() if page:IsShown() then LT:Refresh() end end)
	SK:On("RAIDS_UPDATED", function() if page:IsShown() then LT:Refresh() end end)
	SK:On("NAMES_LOADED", function() if page:IsShown() then LT:Refresh() end end)
	SK:On("ROSTER_UPDATED", function() if page:IsShown() then SK:Debounce("loottab", 1, function() LT:Refresh() end) end end)
end

-- Officers: change points by hand / move them (Points → Everyone).
function LT:BuildForm(pv, pTop)
	self.form = { mode = "add" }
	local fx = S.contentW - LT.FORM_W
	local f = CreateFrame("Frame", nil, pv)
	f:SetPoint("TOPLEFT", fx, pTop)
	f:SetPoint("BOTTOMRIGHT")
	self.formFrame = f
	local l = label(f, "Change points")
	l:SetPoint("TOPLEFT")
	self.formChips = {}
	local prev
	for _, m in ipairs({ { "add", "Add or take" }, { "move", "Move" } }) do
		local c = W.Chip(f, m[2], function() LT.form.mode = m[1]; LT:Refresh() end)
		c.value = m[1]
		if prev then c:SetPoint("LEFT", prev, "RIGHT", SP.xs, 0) else c:SetPoint("TOPLEFT", 0, -W.CARD_LABEL_H) end
		self.formChips[#self.formChips + 1] = c
		prev = c
	end
	local y = W.CARD_LABEL_H + S.controlSmall + SP.m
	local function place(text, widget)
		local t = Theme.Text(f, "small", "dim")
		t:SetPoint("TOPLEFT", 0, -y)
		t:SetText(text)
		widget:SetPoint("TOPLEFT", 0, -(y + 16))
		y = y + 16 + S.control + SP.s
		return widget, t
	end
	local function memberItems()
		local out = {}
		local guild = SK.DBM:Guild()
		for guid, m in pairs(guild and guild.members or {}) do
			if not m.leftAt then out[#out + 1] = { value = guid, text = m.name or "?" } end
		end
		table.sort(out, function(a, b) return a.text:lower() < b.text:lower() end)
		return out
	end
	local function itemsFor(guid)
		local out, seen = {}, {}
		local st = R:State()
		for _, it in ipairs(guid and st and R.ItemsOf(st, guid) or {}) do
			seen[it.item] = true
			out[#out + 1] = { value = it.item, text = (SK.CraftIndex.ItemName(it.item) or ("item " .. it.item)) .. " (" .. it.points .. ")" }
		end
		for _, raid in ipairs(SK.Data.ShownAttunements()) do
			for _, i in ipairs((R.LootList(st, raid.key))) do
				if not seen[i] then
					seen[i] = true
					out[#out + 1] = { value = i, text = SK.CraftIndex.ItemName(i) or ("item " .. i) }
				end
			end
		end
		return out
	end
	local form = self.form
	self.fWho = place("Character", W.Menu(f, { width = LT.FORM_W, items = memberItems,
		get = function() return form.g end, set = function(v) form.g = v; LT:Refresh() end }))
	self.fItem = place("Item", W.Menu(f, { width = LT.FORM_W, items = function() return itemsFor(form.g) end,
		get = function() return form.i end, set = function(v) form.i = v; LT:Refresh() end }))
	self.fWho2, self.fWho2L = place("To character", W.Menu(f, { width = LT.FORM_W, items = memberItems,
		get = function() return form.g2 end, set = function(v) form.g2 = v; LT:Refresh() end }))
	self.fItem2, self.fItem2L = place("To item", W.Menu(f, { width = LT.FORM_W, items = function() return itemsFor(form.g2) end,
		get = function() return form.i2 end, set = function(v) form.i2 = v; LT:Refresh() end }))
	self.fPoints, self.fPointsL = place("Points (minus for a penalty)", W.SearchBox(f, 110, "e.g. -30", function(t) form.d = t end))
	self.fReason = place("Reason (everyone sees it)", W.SearchBox(f, LT.FORM_W, "Why", function(t) form.r = t end))
	self.fSave = W.Button(f, "Save", nil, S.control, function() LT:SaveForm() end, "primary")
	self.fSave:SetPoint("TOPLEFT", 0, -y)
	self.fNote = line(f)
	self.fNote:SetPoint("TOPLEFT", 0, -(y + S.control + SP.s))
	self.fNote:SetWidth(LT.FORM_W)
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
function LT:Result(ok, why)
	if not ok and why then SK:Print("Not saved: %s.", tostring(why)) end
	LT:Refresh()
	return ok
end

function LT:Reserve()
	if not LT.raidID or not LT.item then return end
	local mine = {}
	for _, i in ipairs(R:MyPicks(LT.raidID)) do mine[#mine + 1] = i end
	mine[#mine + 1] = LT.item
	self:Result(R:SetMyPicks(LT.raidID, mine))
end

function LT:ClearMine()
	if LT.raidID then self:Result(R:SetMyPicks(LT.raidID, {})) end
end

function LT:SaveForm()
	local f = self.form
	local why = f.r and f.r ~= "" and f.r or nil
	if f.mode == "move" then
		local d = tonumber(f.d)
		self:Result(R:Move(f.g, f.i, f.g2, f.i2, (d and d > 0) and math.floor(d) or "all", why))
	else
		local d = tonumber(f.d)
		if not d or d == 0 then return self:Result(nil, "type a number of points") end
		self:Result(R:Adjust(f.g, f.i, math.floor(d), why))
	end
end

function LT:ToggleLock()
	if not LT.night then return end
	local lock = R:Get().locks[LT.night.e]
	local inRaid = {}
	for _, m in ipairs(Compat.RaidMembers()) do if m.guid then inRaid[m.guid] = true end end
	self:Result(R:Lock(LT.night.e, lock and not lock.x, function(g) return inRaid[g] == true end, Compat.MemberOnline))
end

function LT:AddDrop()
	local id = LT.ParseItem(LT.addText)
	if not id or not LT.night then return self:Result(nil, "paste an item link or type an item ID") end
	LN:AddItem(LT.night.e, id)
	self.addBox:SetText("")
end

function LT:AddLootItem()
	local id = LT.ParseItem(LT.lootText)
	if not id then return self:Result(nil, "paste an item link or type an item ID") end
	if self:Result(R:AddLoot(LT.lootRaid or "ony", id)) then self.lootBox:SetText("") end
end

-- The current item's reservers with their points, for chat and the screen.
function LT:Reservers(night, itemID)
	local rs, st = R:Get(), R:State()
	local ev = R.Event(night.e)
	local picks = R.PicksOf(rs, night.e, ev and R.PicksFor(st, ev.raid))
	local out = {}
	for _, r in ipairs(R.ReservedBy(picks, itemID)) do
		out[#out + 1] = { guid = r.guid, name = (nameOf(r.guid)), points = R.PointsOf(st, r.guid, itemID) }
	end
	return out, picks
end

function LT:Post()
	local night = LT.night
	if not night or not night.current then return end
	local name = SK.CraftIndex.ItemName(night.current) or ("item " .. night.current)
	Compat.OpenChat("/ra " .. LN.PostText(name, (self:Reservers(night, night.current))))
end

function LT:Award()
	local night = LT.night
	if not night or not night.current or not LT.winner then return end
	local e = self:Result(LN:Award(night.e, night.current, LT.winner))
	if e then
		local name = SK.CraftIndex.ItemName(night.current) or ("item " .. night.current)
		Compat.OpenChat("/ra " .. LN.AwardText(name, (nameOf(LT.winner)), LT.winnerTotal))
		LT.winner = nil
	end
end

function LT:Reroll()
	local night = LT.night
	if night and night.current then night.rolls[night.current] = {} end
	LT.winner = nil
	LT:Refresh()
end

function LT:SaveNight()
	if not LT.night then return end
	local e = self:Result(LN:SaveNight(LT.night.e))
	if e then LT.endMode = false; LT:Refresh() end
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
function LT:Description()
	if Board.OfficerView() then return "Reserves, bonus points and loot nights (officer tools on: /sr officer turns them off)" end
	return "Reserve items for a raid night. Every night you don't get one, it gains bonus points."
end

function LT.HistoryCell(fs, r, col)
	local e, k = r.e, col.key
	local faint = r.undone
	local function t(text, tone) fs:SetText(Theme.Paint(faint and "faint" or (tone or "text"), text)) end
	if k == "when" then return t(date("%d %b %H:%M", e.c), "dim") end
	if k == "kind" then return t(R.KIND_NAME[e.k] or e.k, (e.k == "a" or e.k == "m") and "spark" or nil) end
	if k == "by" then return fs:SetText(faint and Theme.Paint("faint", (nameOf(e.by))) or who(e.by)) end
	if k == "who" then
		if e.k == "n" then return t(Theme.Count(SK.Count(e.g), "person", "people"), "dim") end
		if e.g then return fs:SetText(faint and Theme.Paint("faint", (nameOf(e.g))) or who(e.g)) end
		return fs:SetText(Theme.DASH)
	end
	if k == "item" then
		local i = e.i or (e.k == "x" and nil)
		if e.k == "x" then
			local tgt = R:Get().ledger[e.x]
			return t(tgt and (R.KIND_NAME[tgt.k] or tgt.k) or "?", "dim")
		end
		return fs:SetText(i and (faint and Theme.Paint("faint", SK.CraftIndex.ItemName(i) or tostring(i)) or itemText(i)) or Theme.DASH)
	end
	if k == "d" then
		if e.k == "n" then return t("+" .. e.b .. " each", "good") end
		if e.k == "w" then return t("to 0") end
		if e.k == "a" then return t((e.d > 0 and "+" or "") .. e.d, e.d < 0 and "bad" or "good") end
		if e.k == "m" then return t(e.all and "all" or tostring(e.d)) end
		if e.k == "s" or e.k == "p" then return t(tostring(e.b or e.n)) end
		return fs:SetText(Theme.DASH)
	end
	if k == "why" then
		local text = e.r
		if e.k == "m" then text = "To " .. (nameOf(e.g2)) .. (e.r and (": " .. e.r) or "") end
		if e.k == "p" or e.k == "l" then text = (Board.Raid(e.raid) or {}).name or e.raid end
		return t(text or "", "dim")
	end
end

function LT:RefreshReserves(st, me, now)
	local board = Board:Get() or Board.New()
	local up = Board.Upcoming(board, now)
	local valid = false
	for _, e in ipairs(up) do if e.id == LT.raidID then valid = true end end
	if not valid then
		local tonight = LN.Tonight(board, now)
		LT.raidID = tonight and tonight.id or (up[1] and up[1].id) or nil
	end
	self.raidMenu:Refresh()
	local ev = LT.raidID and board.events[LT.raidID]
	local store = R:Get()
	if not ev or not store then
		self.mineLine:SetText(Theme.Paint("dim", "No raids yet. Reserves open when officers make a raid (Raids page)."))
		self.itemList:SetItems({})
		self.whoList:SetItems({})
		self.reserveBtn:SetDisabled(true)
		self.clearBtn:SetDisabled(true)
		self.resNote:SetText("")
		return
	end
	local limit = R.PicksFor(st, ev.raid)
	local mine = R:MyPicks(ev.id)
	local lock = store.locks[ev.id]
	local locked = lock and not lock.x
	local picks = R.PicksOf(store, ev.id, limit)
	self.mineLine:SetText(string.format("Your %s (%d of %d): %s%s", limit == 1 and "reserve" or "reserves", #mine, limit,
		#mine > 0 and LT.PicksText(mine) or Theme.Paint("spark", "none yet"),
		Theme.Paint("dim", locked and "  ·  locked by an officer" or "  ·  you can change it until an officer locks reserves")))
	local rows = {}
	for _, i in ipairs((R.LootList(st, ev.raid))) do
		local count = 0
		for _, r in ipairs(R.ReservedBy(picks, i)) do count = count + r.count end
		rows[#rows + 1] = { item = i, mine = me and R.PointsOf(st, me, i) or 0, count = count }
	end
	if not LT.item then LT.item = rows[1] and rows[1].item end
	self.itemList:SetItems(rows)
	self.itemList:SetSelected(function(r) return r.item == LT.item end)
	local whoRows = {}
	for g, set in pairs(picks) do
		for i, n in pairs(set) do
			for _ = 1, n do whoRows[#whoRows + 1] = { guid = g, item = i, points = R.PointsOf(st, g, i), name = (nameOf(g)) } end
		end
	end
	table.sort(whoRows, function(a, b)
		if a.item ~= b.item then return a.item < b.item end
		if a.points ~= b.points then return a.points > b.points end
		return a.name < b.name
	end)
	self.whoList:SetItems(whoRows)
	self.whoLabel:SetText(string.format("WHO RESERVED WHAT  ·  %d %s EACH", limit, limit == 1 and "RESERVE" or "RESERVES"))
	local canPick = not locked or Board.CanLead(me)
	self.reserveBtn:SetDisabled(not (canPick and LT.item ~= nil and #mine < limit))
	self.clearBtn:SetDisabled(not (canPick and #mine > 0))
	self.resNote:SetText(#mine >= limit and "To change, clear yours first." or "Pick the same item twice for double points (still one roll).")
end

function LT:RefreshPoints(st, me, officer)
	local s = SK.DB.settings
	local all = s.lootPoints == "all"
	for _, c in ipairs(self.ptsChips) do c:SetActive(c.value == (all and "all" or "mine")) end
	self.ptsSearch:SetShown(all)
	self.ptsNote:SetShown(not all)
	self.mineList:SetShown(not all)
	self.whyTitle:SetShown(not all)
	self.whyList:SetShown(not all)
	self.allList:SetShown(all)
	self.formFrame:SetShown(all and officer)
	if not all then
		local note = "  ·  points belong to this character and stay on each item until you win it"
		self.ptsNote:SetText(me and (who(me) .. Theme.Paint("dim", note)) or "")
		local rows = {}
		local store = R:Get()
		local ev = LN.Tonight(Board:Get(), Compat.Now())
		local tonight = {}
		for _, i in ipairs(ev and R:MyPicks(ev.id) or {}) do tonight[i] = true end
		for _, it in ipairs(me and R.ItemsOf(st, me) or {}) do
			rows[#rows + 1] = { item = it.item, points = it.points, note = tonight[it.item] and Theme.Paint("accent", "Tonight's reserve") or "" }
		end
		if store and not LT.whyItem then LT.whyItem = rows[1] and rows[1].item end
		self.mineList:SetItems(rows)
		self.mineList:SetSelected(function(r) return r.item == LT.whyItem end)
		local lines = me and LT.whyItem and st.lines[me] and st.lines[me][LT.whyItem] or {}
		local why = {}
		for n = #lines, 1, -1 do why[#why + 1] = lines[n] end
		self.whyTitle:SetText(LT.whyItem and (itemText(LT.whyItem) .. "  " .. pts(R.PointsOf(st, me, LT.whyItem))) or "")
		self.whyList:SetItems(why)
		return
	end
	self.allList:SetWidth(officer and (S.contentW - LT.FORM_W - SP.xl) or S.contentW)
	self.allList:SetItems(LT.AllPoints(st, LT.query, function(g) return (nameOf(g)) end, SK.CraftIndex.ItemName))
	self.allList:SetSelected(function(r) return officer and r.guid == self.form.g and r.item == self.form.i end)
	if officer then
		local f = self.form
		local move = f.mode == "move"
		for _, c in ipairs(self.formChips) do c:SetActive(c.value == f.mode) end
		for _, w in ipairs({ self.fWho2, self.fWho2L, self.fItem2, self.fItem2L }) do w:SetShown(move) end
		self.fPointsL:SetText(move and "Points (empty = all of them)" or "Points (minus for a penalty)")
		for _, m in ipairs({ self.fWho, self.fItem, self.fWho2, self.fItem2 }) do m:Refresh() end
		local have = f.g and f.i and R.PointsOf(st, f.g, f.i)
		self.fNote:SetText(have and string.format("%s has %d on %s. It goes in the History with your name, and any officer can undo it.",
			(nameOf(f.g)), have, SK.CraftIndex.ItemName(f.i) or "it") or "Pick a character and an item (or click a row).")
	end
end

function LT:RefreshHistory(st, me)
	local filter = SK.DB.settings.lootHistory or "all"
	for _, c in ipairs(self.histChips) do c:SetActive(c.value == filter) end
	local store = R:Get()
	self.histList:SetItems(store and LT.HistoryRows(store, st, me, filter) or {})
	self.histNote:SetText("Every change, kept by everyone. " .. (Board.OfficerView() and "Right-click a change to undo it."
		or "Only officers and raid leaders can change points."))
end

function LT:RefreshNight(st, now)
	local board = Board:Get()
	local ev = LN.Tonight(board, now)
	local night = ev and LN:Night(ev.id, true)
	LT.night = night
	local store = R:Get()
	local endMode = LT.endMode and night ~= nil
	for _, f in ipairs({ self.dropList, self.addBox, self.addBtn, self.check, self.curTitle, self.curSub, self.postBtn,
		self.awardBtn, self.rerollBtn, self.rollList, self.rollNote }) do f:SetShown(night ~= nil and not endMode) end
	for _, f in ipairs({ self.endList, self.endSum, self.saveBtn, self.endNote }) do f:SetShown(endMode) end
	self.lockBtn:SetShown(night ~= nil)
	self.endBtn:SetShown(night ~= nil)
	if not night then
		self.nightLine:SetText("No raid tonight. A loot night starts with a raid on the Raids page, from 3 hours before its start.")
		return
	end
	local raid = Board.Raid(ev.raid)
	local lock = store.locks[ev.id]
	local locked = lock and not lock.x
	local benchOn, benchOff = 0, 0
	for _, v in pairs(locked and lock.b or {}) do if v == "bench" then benchOn = benchOn + 1 else benchOff = benchOff + 1 end end
	self.nightLine:SetText(string.format("%s %s (%s)  ·  %s%s", Theme.Paint("good", "Tonight"), raid and raid.name or ev.raid,
		Board.ShortWhen(ev.at, now), locked and ("reserves locked " .. date("%H:%M", lock.u) .. "  ·  bench: " .. benchOn .. " online, " ..
		(benchOff > 0 and Theme.Paint("spark", benchOff .. " offline") or "0 offline")) or Theme.Paint("spark", "reserves open"),
		#night.kills > 0 and ("  ·  " .. Theme.Count(#night.kills, "kill")) or ""))
	self.lockBtn:SetText(locked and "Unlock reserves" or "Lock reserves")
	self.lockBtn.tooltip = "Locking also notes who on the bench is online: they get the bonus at the end of the night."
	self.endBtn.active = endMode
	self.endBtn:Paint("rest")
	local limit = R.PicksFor(st, ev.raid)
	local picks = R.PicksOf(store, ev.id, limit)
	if endMode then
		local rows, grants = LN.EndRows(night, picks, lock)
		table.sort(rows, function(a, b) return (nameOf(a.guid)) < (nameOf(b.guid)) end)
		self.endList:SetItems(rows)
		local n, bench, won, off, gone = 0, 0, 0, 0, 0
		for _, r in ipairs(rows) do
			if r.result == "won" then won = won + 1 elseif r.result == "nothing" then
				if r.why == "Not there" then gone = gone + 1 else off = off + 1 end
			end
		end
		for g in pairs(grants) do n = n + 1; if not night.seen[g] then bench = bench + 1 end end
		self.endSum:SetText(night.saved and Theme.Paint("good", "Saved. ") .. "The bonus is in the History."
			or string.format("Check the bonus before saving: %s (%d from the bench)  ·  %d won their reserve  ·  %s  ·  %d not there",
				Theme.Paint("good", n .. " get +" .. st.bonus), bench, won,
				off > 0 and Theme.Paint("spark", off .. " bench offline") or "0 bench offline", gone))
		self.saveBtn:SetDisabled(night.saved ~= nil or n == 0)
		self.endNote:SetText("Click someone to leave them out. Penalties: Points → Everyone → Change points.")
		return
	end
	-- Drops
	local drops, seen = {}, {}
	for _, d in ipairs(night.drops) do
		if not seen[d.i] then
			seen[d.i] = true
			local c = 0
			for _, r in ipairs(R.ReservedBy(picks, d.i)) do c = c + r.count end
			drops[#drops + 1] = { item = d.i, count = c }
		end
	end
	self.dropList:SetItems(drops)
	self.dropList:SetSelected(function(r) return r.item == night.current end)
	-- Raid check
	local inRaid = {}
	for _, m in ipairs(Compat.RaidMembers()) do if m.guid then inRaid[m.guid] = true end end
	local missing, noReserve = R.RaidCheck(picks, inRaid)
	local function names(list)
		local out = {}
		for i, g in ipairs(list) do
			if i > 6 then out[#out + 1] = "+" .. (#list - 6); break end
			out[#out + 1] = (nameOf(g))
		end
		return #out > 0 and table.concat(out, ", ") or "nobody"
	end
	self.check:SetText((C("dim") .. "RAID CHECK|r\n" .. Theme.Paint(#missing > 0 and "spark" or "dim", "Reserved, not in the raid: ") ..
		names(missing) .. "\n" .. Theme.Paint("dim", "In the raid, no reserve: ") .. names(noReserve)))
	-- Current item
	local cur = night.current
	self.postBtn:SetDisabled(cur == nil)
	self.rerollBtn:SetDisabled(cur == nil)
	if not cur then
		self.curTitle:SetText("")
		self.curSub:SetText("")
		self.rollList:SetItems({})
		self.awardBtn:SetDisabled(true)
		self.awardBtn:SetText("Award")
		self.rollNote:SetText("")
		return
	end
	local reservers = self:Reservers(night, cur)
	self.curTitle:SetText(itemText(cur))
	self.curSub:SetText(string.format("Reserved by %d  ·  reservers first, highest roll + points wins; " ..
		"equal: more points, then re-roll", #reservers))
	local rows = R.Rank(cur, night.rolls[cur] or {}, picks, st)
	if rows[1] then rows[1].first = not rows[1].tie end
	if not LT.winner and rows[1] and not rows[1].tie then LT.winner, LT.winnerTotal = rows[1].guid, rows[1].total end
	for _, r in ipairs(rows) do if r.guid == LT.winner then LT.winnerTotal = r.total end end
	self.rollList:SetItems(rows)
	self.rollList:SetSelected(function(r) return r.guid == LT.winner end)
	self.awardBtn:SetDisabled(LT.winner == nil)
	self.awardBtn:SetText(LT.winner and ("Award to " .. (nameOf(LT.winner))) or "Award")
	local waiting = {}
	local rolled = {}
	for _, r in ipairs(rows) do rolled[r.guid] = true end
	for _, r in ipairs(reservers) do if not rolled[r.guid] then waiting[#waiting + 1] = r.name end end
	self.rollNote:SetText(#waiting > 0 and ("Waiting for: " .. table.concat(waiting, ", ")) or
		"Only the first 1-100 roll of each player counts.")
end

function LT:Refresh()
	if not self.page then return end
	local officer = Board.OfficerView()
	for _, t in ipairs(self.views.tabs) do t:SetShown(not LT.OFFICER_VIEWS[t.key] or officer) end
	local view = LT.View(officer)
	self.views:SetActive(view)
	self.resPage:SetShown(view == "reserves")
	self.ptsPage:SetShown(view == "points")
	self.histPage:SetShown(view == "history")
	self.nightPage:SetShown(view == "night")
	self.rulesPage:SetShown(view == "rules")
	local st = R:State() or R.Replay(R.New())
	self.bonusLine:SetText("Bonus: " .. Theme.Paint("accent", "+" .. st.bonus) .. " a night  ·  no cap")
	local me, now = Compat.PlayerGUID(), Compat.Now()
	if view == "reserves" then self:RefreshReserves(st, me, now)
	elseif view == "points" then self:RefreshPoints(st, me, officer)
	elseif view == "history" then self:RefreshHistory(st, me)
	elseif view == "night" then self:RefreshNight(st, now)
	else
		self.picksCard:Refresh()
		self.pointsCard:Refresh()
		self.lootRaidMenu:Refresh()
	end
end

-- Open on a tab (from /sr loot).
function LT:Show(view)
	if view then SK.DB.settings.lootView = view end
	SK.MainFrame:Select("loot")
end

SK.MainFrame:AddTab("loot", "Loot", LT, { group = "guild", icon = Theme.TEX.loot })
