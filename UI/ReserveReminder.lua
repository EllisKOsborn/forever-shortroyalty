-- Reserve+ reminder (v0.9.1). The guild asked: "if you are in a raid group
-- that you didn't do reserves to, you should get a warning" (officers were
-- tired of reminding everyone before the lock). While you're in a raid
-- group for tonight's raid (the Raids page's raid, from 3 h before its
-- start) and you have fewer reserves than that raid allows, a small box at
-- the top of the screen says so, with a Reserve button that opens the Loot
-- page, plus one line in chat. It comes back every REPEAT seconds until you
-- reserve or an officer locks reserves. Never in combat.
--
-- Sharing pauses inside instances, so a reserve made inside the raid only
-- reaches officers after you leave: the box shows as soon as you join the
-- group, usually still in town.
local _, SK = ...

local Rem = SK:NewModule("ReserveReminder")
local Theme, W, Compat, Motion = SK.Theme, SK.Widgets, SK.Compat, SK.Motion
local R, LN, Board = SK.Reserves, SK.LootNight, SK.RaidBoard
local S, SP, M = Theme.SIZES, Theme.SPACE, Theme.MOTION

Rem.FRAME_NAME = "ShortRoyaltyReserveReminder"
Rem.REPEAT = 600     -- seconds between reminders while still not reserved
Rem.CHECK_EVERY = 60 -- seconds between checks while in a raid group
Rem.shownAt = {}     -- [raid id] = when the box last showed (this session)

-- What to say, or nil. Pure; tested.
--   ev: tonight's raid (or nil); mine: my reserves for it (item IDs);
--   limit: reserves allowed there; locked: an officer locked reserves;
--   inRaid: I'm in a raid group; inCombat.
function Rem.Needed(ev, mine, limit, locked, inRaid, inCombat)
	if not ev or not inRaid or inCombat or locked then return nil end
	local have = #(mine or {})
	if have >= limit then return nil end
	local raid = Board.Raid(ev.raid)
	local title = "Reserve for " .. (raid and raid.name or "tonight's raid")
	if have == 0 then return { title = title, text = "Nothing reserved yet." } end
	return { title = title, text = string.format("%d of %d reserved so far.", have, limit) }
end

-- Officers' raid chat line: who's in the raid without a reserve. Pure; tested.
function Rem.RaidChatText(names)
	if #names == 0 then return nil end
	return "Reserves close soon. Not reserved yet: " .. table.concat(names, ", ") .. ". Type /sr loot to reserve."
end

---------------------------------------------------------------------------
-- The box (same look as the Short Words flight box, just under it)
---------------------------------------------------------------------------
function Rem:Build()
	if self.box then return self.box end
	local f = CreateFrame("Frame", Rem.FRAME_NAME, UIParent)
	f:SetSize(S.reminderBox[1], S.reminderBox[2])
	f:SetPoint("TOP", UIParent, "TOP", 0, -(S.flightBoxY + S.flightBox[2] + SP.m))
	f:SetFrameStrata("HIGH")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:Hide()
	Theme.Panel(f, { bg = "void", border = "line" })
	tinsert(UISpecialFrames, Rem.FRAME_NAME) -- Esc hides it
	local edge = f:CreateTexture(nil, "ARTWORK")
	edge:SetPoint("TOPLEFT", 1, -1)
	edge:SetPoint("BOTTOMLEFT", 1, 1)
	edge:SetWidth(SP.xxs)
	Theme.Solid(edge, "spark")
	local icon = f:CreateTexture(nil, "ARTWORK")
	icon:SetSize(20, 20)
	icon:SetPoint("LEFT", SP.m, 0)
	icon:SetTexture(Theme.TEX.loot)
	Theme.Tint(icon, "spark")
	f.close = W.CloseButton(f, function() Rem:HideBox() end)
	f.close:SetPoint("RIGHT", -SP.xs, 0)
	f.go = W.Button(f, "Reserve", nil, S.control, function() Rem:Open() end, "primary")
	f.go:SetPoint("RIGHT", f.close, "LEFT", -SP.xs, 0)
	f.title = Theme.Text(f, "body", "text")
	f.title:SetPoint("TOPLEFT", icon, "TOPRIGHT", SP.s + SP.xxs, 2)
	f.title:SetPoint("RIGHT", f.go, "LEFT", -SP.s, 0)
	f.title:SetWordWrap(false)
	f.text = Theme.Text(f, "small", "dim")
	f.text:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -SP.xxs)
	f.text:SetPoint("RIGHT", f.go, "LEFT", -SP.s, 0)
	f.text:SetWordWrap(false)
	self.box = f
	return f
end

function Rem:ShowBox(say)
	local f = self:Build()
	f:SetScale(SK.DB.settings.window.scale or 1)
	f.title:SetText(say.title)
	f.text:SetText(say.text)
	Motion.In(f, M.open, M.openScale, "TOP")
end

function Rem:HideBox()
	if self.box and self.box:IsShown() then Motion.Out(self.box, M.close) end
end

function Rem:Open()
	self:HideBox()
	if Compat.InCombat() then return end
	if self.raidID then SK.LootTab.raidID = self.raidID end
	SK.LootTab:Show("reserves")
end

---------------------------------------------------------------------------
-- Checking
---------------------------------------------------------------------------
-- force: show even if it showed less than REPEAT seconds ago (joining).
function Rem:Check(force)
	if not SK.DB or not SK.DBM:Guild() then return end
	local now = Compat.Now()
	local ev = LN.Tonight(Board:Get(), now)
	local store, st = R:Get(), R:State()
	local lock = ev and store and store.locks[ev.id]
	local say = ev and st and Rem.Needed(ev, R:MyPicks(ev.id), R.PicksFor(st, ev.raid), lock ~= nil and not lock.x,
		Compat.InRaidGroup(), Compat.InCombat())
	if not say then
		self:HideBox()
		return
	end
	self.raidID = ev.id
	local last = Rem.shownAt[ev.id]
	if not force and last and now - last < Rem.REPEAT then return end
	if self.box and self.box:IsShown() then return end
	Rem.shownAt[ev.id] = now
	self:ShowBox(say)
	SK:Print("%s: %s Type /sr loot to reserve before an officer locks reserves.", say.title, say.text)
end

local wasInRaid = false
local function groupChanged()
	local inRaid = Compat.InRaidGroup()
	local joined = inRaid and not wasInRaid
	wasInRaid = inRaid
	if inRaid then Rem:Check(joined) else Rem:HideBox() end
end

function Rem:OnLogin()
	SK.After(40, function()
		wasInRaid = false
		groupChanged()
	end)
	self.ticker = SK.NewTicker(Rem.CHECK_EVERY, function()
		if Compat.InRaidGroup() then Rem:Check(false) end
	end)
end

SK:RegisterEvent("GROUP_ROSTER_UPDATE", function()
	SK:Debounce("reserveremind", 2, groupChanged)
end)
SK:RegisterEvent("PLAYER_REGEN_ENABLED", function()
	if Compat.InRaidGroup() then SK:Debounce("reserveremind", 3, function() Rem:Check(false) end) end
end)
SK:On("RESERVES_UPDATED", function() if Rem.box and Rem.box:IsShown() then Rem:Check(true) end end)
