-- Reserve+ reminders (v0.9.1). The guild asked for two:
--   * a gentle one at login: you're signed up (or tentative), on this
--     character, for a raid in the next 7 days and haven't made all your
--     reserves. Calm (accent colour), once per login.
--   * an urgent one on raid day: from 00:01 on the day of the raid (each
--     player's own time) until it's over, if you're signed up, or whenever
--     you're in the raid group for tonight's raid, without all your
--     reserves. Orange, shown at login and on joining the raid group, then
--     again every REPEAT seconds. No sound (owner, 16 Nov).
-- Both stop once you've reserved or an officer has locked reserves, never
-- show in combat, and have a Reserve button that opens the Loot page (plus
-- one chat line). Sign-ups and reserves are per character.
--
-- Sharing pauses inside instances, so a reserve made inside the raid only
-- reaches officers after you leave: the earlier reminders are the point.
local _, SK = ...

local Rem = SK:NewModule("ReserveReminder")
local Theme, W, Compat, Motion = SK.Theme, SK.Widgets, SK.Compat, SK.Motion
local R, LN, Board = SK.Reserves, SK.LootNight, SK.RaidBoard
local S, SP, M = Theme.SIZES, Theme.SPACE, Theme.MOTION

Rem.FRAME_NAME = "ShortRoyaltyReserveReminder"
Rem.REPEAT = 1800      -- seconds between raid-day reminders while still not reserved
Rem.CHECK_EVERY = 60   -- seconds between checks
Rem.AHEAD = 7 * 86400  -- the login reminder looks this far ahead
Rem.shownAt = {}       -- [raid id] = when the raid-day box last showed (this session)

-- Which reminder to show, or nil. Pure; tested.
--   raids = { { ev, signed (yes or tentative, this character), mine (my item
--             IDs), limit (reserves allowed), locked } }, soonest first;
--   tonightID = the raid this raid group is for (LootNight.Tonight), or nil.
-- Returns { kind = "day" | "login", ev, title, text }.
function Rem.Pick(raids, now, inRaid, tonightID, inCombat)
	if inCombat then return nil end
	local login
	for _, r in ipairs(raids) do
		local ev, have = r.ev, #(r.mine or {})
		if not r.locked and have < r.limit and not ev.x then
			local name = #Board.Keys(ev) > 0 and Board.EventName(ev) or "the raid"
			local short = have == 0 and "Nothing reserved yet." or string.format("Only %d of %d reserved.", have, r.limit)
			local raidDay = now >= Board.DayStart(ev.at) + 60 and now <= ev.at + LN.AFTER
			if (raidDay and r.signed) or (inRaid and ev.id == tonightID) then
				return { kind = "day", ev = ev, title = "Raid today: " .. name .. ", " .. date("%H:%M", ev.at), text = short }
			end
			if not login and r.signed and ev.at > now and ev.at <= now + Rem.AHEAD then
				local tomorrow = date("%Y-%m-%d", ev.at) == date("%Y-%m-%d", now + 86400)
				login = { kind = "login", ev = ev, title = name .. ", " .. (tomorrow and "tomorrow " or date("%a ", ev.at)) .. date("%H:%M", ev.at),
					text = have == 0 and "Signed up, nothing reserved yet." or string.format("Signed up, %d of %d reserved.", have, r.limit) }
			end
		end
	end
	return login
end

-- The raids to look at, for Pick: upcoming ones, with this character's
-- sign-up and reserves.
function Rem.Raids(now, me)
	local board, store, st = Board:Get(), R:Get(), R:State()
	local out = {}
	if not board or not store or not st then return out end
	-- v0.16.2: not for raids still "to be decided" (nothing to reserve yet).
	for _, ev in ipairs(Board.ReserveRaids(board, now)) do
		local su = Board.SignupOf(board, ev.id, me)
		local lock = store.locks[ev.id]
		out[#out + 1] = { ev = ev, signed = su ~= nil and (su.s == "y" or su.s == "t"), mine = R:MyPicks(ev.id),
			limit = R.EventPicks(st, ev), locked = lock ~= nil and not lock.x }
	end
	return out
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
	f.edge = edge
	local icon = f:CreateTexture(nil, "ARTWORK")
	icon:SetSize(20, 20)
	icon:SetPoint("LEFT", SP.m, 0)
	icon:SetTexture(Theme.TEX.loot)
	f.icon = icon
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
	-- Calm (accent) for the login reminder, orange on raid day.
	local tone = say.kind == "day" and "spark" or "accent"
	Theme.Solid(f.edge, tone)
	Theme.Tint(f.icon, tone)
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
-- reason = "login" (once per login: either reminder), "joined" (joined a
-- raid group: the raid-day one now), "tick" (raid-day one if it's been
-- REPEAT seconds), "update" (reserves changed: hide when done).
function Rem:Check(reason)
	if not SK.DB or not SK.DBM:Guild() then return end
	local now, me = Compat.Now(), Compat.PlayerGUID()
	local tonight = LN.Tonight(Board:Get(), now)
	local say = Rem.Pick(Rem.Raids(now, me), now, Compat.InRaidGroup(), tonight and tonight.id, Compat.InCombat())
	if not say then
		self:HideBox()
		return
	end
	if reason == "update" then
		-- Still short: refresh the words if it's showing.
		if self.box and self.box:IsShown() then self.box.title:SetText(say.title); self.box.text:SetText(say.text) end
		return
	end
	if say.kind == "login" and reason ~= "login" then return end
	if say.kind == "day" and reason == "tick" then
		local last = Rem.shownAt[say.ev.id]
		if last and now - last < Rem.REPEAT then return end
	end
	if self.box and self.box:IsShown() then return end
	self.raidID = say.ev.id
	if say.kind == "day" then Rem.shownAt[say.ev.id] = now end
	self:ShowBox(say)
	SK:Print("%s. %s Type /sr loot to reserve before an officer locks reserves.", say.title, say.text)
end

local wasInRaid = false
local function groupChanged()
	local inRaid = Compat.InRaidGroup()
	local joined = inRaid and not wasInRaid
	wasInRaid = inRaid
	if joined then Rem:Check("joined") end
end

function Rem:OnLogin()
	SK.After(40, function()
		wasInRaid = Compat.InRaidGroup()
		Rem:Check("login")
	end)
	self.ticker = SK.NewTicker(Rem.CHECK_EVERY, function() Rem:Check("tick") end)
end

SK:RegisterEvent("GROUP_ROSTER_UPDATE", function()
	SK:Debounce("reserveremind", 2, groupChanged)
end)
SK:RegisterEvent("PLAYER_REGEN_ENABLED", function()
	SK:Debounce("reserveremind", 3, function() Rem:Check("tick") end)
end)
SK:On("RESERVES_UPDATED", function() if Rem.box and Rem.box:IsShown() then Rem:Check("update") end end)
