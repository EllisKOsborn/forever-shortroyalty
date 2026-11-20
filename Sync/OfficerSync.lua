-- Officer roster sharing (v0.10.1): roles, notes and alt links from
-- Core/OfficerDir.lua, only between officer and raid leader ranks, only by
-- whisper (like attendance, Sync/AttendanceSync.lua).
--
--   OR  WHISPER  changed entries { d = { [key] = { v, u, by } } }, to every
--                officer online with the addon, a few seconds after a change
--   OQ  WHISPER  "what I hold" { k = { [key] = u } }, once per session to each
--                officer online, ~2 minutes after login; answered with an OR
--                of the entries the asker lacks or holds older
--
-- Sender and receiver must be lead ranks (checked against their own roster).
-- Older versions ignore both message types.
local _, SK = ...

local OS = SK:NewModule("OfficerSync")
local Compat = SK.Compat
local Board, OD = SK.RaidBoard, SK.OfficerDir

OS.SHARE_DELAY = 5
OS.QUERY_DELAY = 110
OS.MAX_ITEMS = 120          -- entries per OR
OS.MAX_ASK = 2000           -- keys read from one OQ
OS.pending = {}
OS.stats = { sentOR = 0, sentOQ = 0, gotOR = 0, gotOQ = 0, accepted = 0, rejected = 0 }
OS.lastReject = nil

local function targets()
	return SK.AttendanceSync.Targets(SK.DBM:Guild(), Compat.Now())
end

-- Send entries (keys) to one officer, in messages of MAX_ITEMS.
local function sendTo(target, dir, keys)
	local name = SK.Identity:WhisperTarget(target)
	if not name then return 0 end
	local msg, n, sent = { t = "OR", d = {} }, 0, 0
	local function flush()
		if n == 0 then return end
		sent = sent + 1
		OS.stats.sentOR = OS.stats.sentOR + 1
		SK.Sync:Enqueue("OR:" .. target .. ":" .. sent .. ":" .. math.random(1e6), "WHISPER", name, "BULK", msg)
		msg, n = { t = "OR", d = {} }, 0
	end
	for _, key in ipairs(keys) do
		local e = dir[key]
		if e then
			msg.d[key] = { v = e.v, u = e.u, by = e.by }
			n = n + 1
			if n >= OS.MAX_ITEMS then flush() end
		end
	end
	flush()
	return sent
end

function OS:Share(key)
	self.pending[key] = true
	SK:Debounce("officersync", OS.SHARE_DELAY, function() self:SendPending() end)
end

function OS:SendPending()
	if SK.Sync:IsPaused() then
		SK:Debounce("officersync", 30, function() self:SendPending() end)
		return 0
	end
	local keys = {}
	for k in pairs(self.pending) do keys[#keys + 1] = k end
	table.sort(keys)
	self.pending = {}
	if not Board.IsLeadSelf() then return 0 end
	local dir, n = OD:Get(), 0
	for _, target in ipairs(targets()) do n = n + sendTo(target, dir, keys) end
	return n
end

function OS:SendQuery()
	if not Board.IsLeadSelf() then return 0 end
	local dir = OD:Get() or {}
	local k = {}
	for key, e in pairs(dir) do k[key] = e.u end
	local n = 0
	for _, target in ipairs(targets()) do
		local name = SK.Identity:WhisperTarget(target)
		if name then
			self.stats.sentOQ = self.stats.sentOQ + 1
			SK.Sync:Enqueue("OQ:" .. target, "WHISPER", name, "NORMAL", { t = "OQ", k = k })
			n = n + 1
		end
	end
	return n
end

local function allowed(from, dist)
	return dist == "WHISPER" and Board.CanLead(from) and Board.IsLeadSelf()
end

function OS:HandleOR(msg, from, dist)
	if not allowed(from, dist) or type(msg.d) ~= "table" then return end
	self.stats.gotOR = self.stats.gotOR + 1
	local dir = OD:Get()
	if not dir then return end
	local now, guild, n, changed = Compat.Now(), SK.DBM:Guild(), 0, false
	local isLead = function(g) return Board.CanLead(g, guild) end
	local isMember = function(g) return SK.Identity:IsMember(g) end
	for key, e in pairs(msg.d) do
		n = n + 1
		if n > OS.MAX_ITEMS then break end
		local ok, why = OD.Merge(dir, key, e, now, isLead, isMember)
		if ok then
			changed = true
			self.stats.accepted = self.stats.accepted + 1
		elseif why ~= "not newer" then
			self.stats.rejected, self.lastReject = self.stats.rejected + 1, why
		end
	end
	if changed then SK:Fire("OFFICERDIR_UPDATED") end
end

function OS:HandleOQ(msg, from, dist)
	if not allowed(from, dist) or type(msg.k) ~= "table" then return end
	self.stats.gotOQ = self.stats.gotOQ + 1
	local dir = OD:Get() or {}
	local theirs, n = {}, 0
	for key, u in pairs(msg.k) do
		n = n + 1
		if n > OS.MAX_ASK then break end
		if type(key) == "string" and type(u) == "number" then theirs[key] = u end
	end
	local keys = {}
	for key, e in pairs(dir) do
		if not theirs[key] or e.u > theirs[key] then keys[#keys + 1] = key end
	end
	table.sort(keys)
	sendTo(from, dir, keys)
end

SK.Sync.handlers.OR = function(_, msg, from, dist) OS:HandleOR(msg, from, dist) end
SK.Sync.handlers.OQ = function(_, msg, from, dist) OS:HandleOQ(msg, from, dist) end

function OS:OnLogin()
	SK.After(OS.QUERY_DELAY + math.random() * 30, function() self:SendQuery() end)
end
