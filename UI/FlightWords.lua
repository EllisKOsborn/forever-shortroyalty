-- Short Words on flights (v0.7.2). When you take a flight path, a small box
-- near the top of the screen offers a game: today's word if you haven't
-- played it, otherwise free for all. Play opens the window on Short Words
-- (you still click the board to type, so the keyboard is never taken).
-- Landing hides the box, and closes the window if the box opened it (games
-- are saved as you go). Settings → General → "Short Words on flights".
--
-- Flights: PLAYER_CONTROL_LOST / PLAYER_CONTROL_GAINED (Forever's
-- LossOfControlDocumentation) and UnitOnTaxi("player") (Compat.OnTaxi).
-- Control is also lost to stuns and fears, so UnitOnTaxi decides; a check
-- every few seconds while flying catches a landing the event missed.
local _, SK = ...

local Flight = SK:NewModule("FlightWords")
local Theme, W, Compat, Motion = SK.Theme, SK.Widgets, SK.Compat, SK.Motion
local SW = SK.ShortWords
local S, SP, M = Theme.SIZES, Theme.SPACE, Theme.MOTION

Flight.FRAME_NAME = "ShortRoyaltyFlightWords"
Flight.START_DELAY = 0.5 -- UnitOnTaxi can trail the event by a moment
Flight.CHECK_EVERY = 3   -- seconds between "still flying?" checks
Flight.TITLE = "Flying? Play Short Words"

-- What the box offers, or nil for no box. Pure; tested.
--   enabled: the setting; onWords: the window is already showing Short Words;
--   daily: today's daily game; me: this character's GUID.
function Flight.Offer(enabled, inCombat, onWords, daily, me)
	if not enabled or inCombat or onWords then return nil end
	if daily and not daily.done and not (daily.guid and daily.guid ~= me) then
		return { view = "daily", text = "Today's word is waiting." }
	end
	return { view = "free", text = "Play free for all until you land." }
end

local function windowShown()
	local f = SK.MainFrame.frame
	return f ~= nil and f:IsShown() and not Motion.IsLeaving(f)
end

local function onWords()
	return windowShown() and SK.MainFrame.current == "words"
end

---------------------------------------------------------------------------
-- The box
---------------------------------------------------------------------------
function Flight:Build()
	if self.box then return self.box end
	local f = CreateFrame("Frame", Flight.FRAME_NAME, UIParent)
	f:SetSize(S.flightBox[1], S.flightBox[2])
	f:SetPoint("TOP", UIParent, "TOP", 0, -S.flightBoxY)
	f:SetFrameStrata("HIGH")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:Hide()
	Theme.Panel(f, { bg = "void", border = "line" })
	tinsert(UISpecialFrames, Flight.FRAME_NAME) -- Esc hides it
	local edge = f:CreateTexture(nil, "ARTWORK")
	edge:SetPoint("TOPLEFT", 1, -1)
	edge:SetPoint("BOTTOMLEFT", 1, 1)
	edge:SetWidth(SP.xxs)
	Theme.Solid(edge, "accent")
	local icon = f:CreateTexture(nil, "ARTWORK")
	icon:SetSize(20, 20)
	icon:SetPoint("LEFT", SP.m, 0)
	icon:SetTexture(Theme.TEX.words)
	Theme.Tint(icon, "accent")

	f.close = W.CloseButton(f, function() Flight:HideBox() end)
	f.close:SetPoint("RIGHT", -SP.xs, 0)
	f.play = W.Button(f, "Play", nil, S.control, function() Flight:Play() end, "primary")
	f.play:SetPoint("RIGHT", f.close, "LEFT", -SP.xs, 0)

	f.title = Theme.Text(f, "body", "text")
	f.title:SetPoint("TOPLEFT", icon, "TOPRIGHT", SP.s + SP.xxs, 2)
	f.title:SetPoint("RIGHT", f.play, "LEFT", -SP.s, 0)
	f.title:SetWordWrap(false)
	f.title:SetText(Flight.TITLE)
	f.text = Theme.Text(f, "small", "dim")
	f.text:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -SP.xxs)
	f.text:SetPoint("RIGHT", f.play, "LEFT", -SP.s, 0)
	f.text:SetWordWrap(false)
	self.box = f
	return f
end

function Flight:ShowBox(offer)
	local f = self:Build()
	self.offer = offer
	f:SetScale(SK.DB.settings.window.scale or 1)
	f.text:SetText(offer.text)
	Motion.In(f, M.open, M.openScale, "TOP")
end

function Flight:HideBox()
	self.offer = false
	if self.box then Motion.Out(self.box, M.close) end
end

---------------------------------------------------------------------------
-- Flying
---------------------------------------------------------------------------
Flight.flying, Flight.opened, Flight.offer, Flight.ticker, Flight.box = false, false, false, false, false

function Flight:TookOff()
	if self.flying or not Compat.OnTaxi() then return end
	self.flying, self.opened = true, false
	local offer = Flight.Offer(SK.DB.settings.flightWords ~= false, Compat.InCombat(), onWords(),
		SW:Daily(Compat.Now()), Compat.PlayerGUID())
	if offer then self:ShowBox(offer) end
	self.ticker = SK.NewTicker(Flight.CHECK_EVERY, function()
		if not Compat.OnTaxi() then Flight:Landed() end
	end)
end

function Flight:Landed()
	if not self.flying then return end
	self.flying = false
	if self.ticker then self.ticker:Cancel() end
	self.ticker = false
	self:HideBox()
	if self.opened then
		self.opened = false
		if onWords() and not Compat.InCombat() then SK.MainFrame:Close() end
	end
end

-- Play: open the window on the mode the box offered. Only a window the box
-- opened closes again on landing.
function Flight:Play()
	local offer = self.offer
	self:HideBox()
	if Compat.InCombat() then return end
	local wasShown = windowShown()
	if offer then SK.DB.settings.wordsView = offer.view end
	SK.MainFrame:Open("words")
	self.opened = self.flying and not wasShown
end

function Flight:OnLogin()
	-- A /reload in mid-air.
	SK.After(3, function() Flight:TookOff() end)
end

SK:RegisterEvent("PLAYER_CONTROL_LOST", function()
	SK.After(Flight.START_DELAY, function() Flight:TookOff() end)
end)
SK:RegisterEvent("PLAYER_CONTROL_GAINED", function()
	SK.After(Flight.START_DELAY, function()
		if not Compat.OnTaxi() then Flight:Landed() end
	end)
end)
