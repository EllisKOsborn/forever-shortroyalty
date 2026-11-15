-- Attendance sharing (v0.8.1): every officer and raid leader sees every
-- recorded raid in the addon, whoever recorded it. Only by whisper, only
-- between officer and raid leader ranks (checked by sender and receiver
-- against their own roster); members never get attendance.
--
--   AR  WHISPER  one attendance record { r = record }; sent to the officers
--                online when a recording ends or a Bench tick changes, and
--                in answer to AQ
--   AQ  WHISPER  "the records I hold" { k = { [id] = { s = checks, u = changed } } },
--                once per session to each officer online, ~90 s after login
--
-- Sync's queue, pause rules (not in instances, combat, chat lockdown) and
-- limits apply. Older versions ignore both message types.
local _, SK = ...

local AS = SK:NewModule("AttendanceSync")
local Compat = SK.Compat
local Board, Att = SK.RaidBoard, SK.Attendance

AS.SHARE_DELAY = 5         -- seconds after a change before sending
AS.QUERY_DELAY = 90        -- AQ this long after login
AS.KEEP_DAYS = 90          -- records older than this aren't offered
AS.MAX_ANSWER = 30         -- records sent in answer to one AQ
AS.pending = {}            -- record ids waiting to be sent
AS.stats = { sentAR = 0, sentAQ = 0, gotAR = 0, gotAQ = 0, accepted = 0, rejected = 0 }
AS.lastReject = nil

-- Officers and raid leaders who are online with the addon now, not on our
-- own account. Pure apart from SK.DB.account; tested.
function AS.Targets(guild, now)
	local out = {}
	for guid, m in pairs(guild and guild.members or {}) do
		if not SK.DB.account[guid] and Board.IsLeadRank(m) and SK.Identity.Status(m, false, now) == "addon" then
			out[#out + 1] = guid
		end
	end
	table.sort(out)
	return out
end

local function sendRecord(target, rec)
	local name = SK.Identity:WhisperTarget(target)
	if not name then return false end
	AS.stats.sentAR = AS.stats.sentAR + 1
	SK.Sync:Enqueue("AR:" .. target .. ":" .. rec.id, "WHISPER", name, "BULK", { t = "AR", r = Att.Copy(rec) })
	return true
end

-- Send these records (ids) to every officer online now.
function AS:SendPending()
	-- In an instance or combat: wait, so the list of officers online is fresh.
	if SK.Sync:IsPaused() then
		SK:Debounce("attshare", 30, function() self:SendPending() end)
		return 0
	end
	local ids = self.pending
	self.pending = {}
	if not Board.IsLeadSelf() then return 0 end
	local guild = SK.DBM:Guild()
	local store = Att:Store(guild) or {}
	local n = 0
	for _, target in ipairs(AS.Targets(guild, Compat.Now())) do
		for id in pairs(ids) do
			if store[id] and sendRecord(target, store[id]) then n = n + 1 end
		end
	end
	return n
end

-- A record changed here (ended, Bench ticked): share it in a few seconds.
function AS:Share(id)
	if not id then return end
	self.pending[id] = true
	SK:Debounce("attshare", AS.SHARE_DELAY, function() self:SendPending() end)
end

-- What we hold, for an AQ.
function AS.Summary(store, now)
	local k = {}
	for id, rec in pairs(store or {}) do
		if rec.at >= now - AS.KEEP_DAYS * 86400 then k[id] = { s = rec.snaps, u = rec.u or 0 } end
	end
	return k
end

function AS:SendQuery()
	if not Board.IsLeadSelf() then return 0 end
	local guild = SK.DBM:Guild()
	local now = Compat.Now()
	local k = AS.Summary(Att:Store(guild), now)
	local n = 0
	for _, target in ipairs(AS.Targets(guild, now)) do
		local name = SK.Identity:WhisperTarget(target)
		if name then
			self.stats.sentAQ = self.stats.sentAQ + 1
			SK.Sync:Enqueue("AQ:" .. target, "WHISPER", name, "NORMAL", { t = "AQ", k = k })
			n = n + 1
		end
	end
	return n
end

---------------------------------------------------------------------------
-- Receiving: only from officers and raid leaders, only if we are one.
---------------------------------------------------------------------------
local function allowed(from, dist)
	return dist == "WHISPER" and Board.CanLead(from) and Board.IsLeadSelf()
end

function AS:HandleAR(msg, from, dist)
	if not allowed(from, dist) then return end
	self.stats.gotAR = self.stats.gotAR + 1
	local now = Compat.Now()
	local ok, why = Att.ValidRecord(msg.r, now)
	if not ok then
		self.stats.rejected, self.lastReject = self.stats.rejected + 1, why
		return
	end
	local store = Att:Store()
	if not store then return end
	local have = store[msg.r.id]
	local out, changed = Att.Merge(have, msg.r, Att.current ~= nil and Att.current == have)
	if changed then
		if not have and SK.Count(store) >= Att.MAX_RECORDS then
			local list = Att.Sorted(store)
			if list[#list] and list[#list].at > out.at then return end -- older than everything we keep
			store[list[#list].id] = nil
		end
		store[out.id] = out
		self.stats.accepted = self.stats.accepted + 1
		SK:Fire("ATTENDANCE_UPDATED")
	end
end

function AS:HandleAQ(msg, from, dist)
	if not allowed(from, dist) or type(msg.k) ~= "table" then return end
	self.stats.gotAQ = self.stats.gotAQ + 1
	local now = Compat.Now()
	local list = Att.Sorted(Att:Store() or {}, now - AS.KEEP_DAYS * 86400)
	local n = 0
	for _, rec in ipairs(list) do
		local theirs = msg.k[rec.id]
		local s = type(theirs) == "table" and tonumber(theirs.s) or nil
		local u = type(theirs) == "table" and tonumber(theirs.u) or nil
		if not s or rec.snaps > s or (rec.u or 0) > (u or 0) then
			if sendRecord(from, rec) then n = n + 1 end
			if n >= AS.MAX_ANSWER then break end
		end
	end
end

SK.Sync.handlers.AR = function(_, msg, from, dist) AS:HandleAR(msg, from, dist) end
SK.Sync.handlers.AQ = function(_, msg, from, dist) AS:HandleAQ(msg, from, dist) end

function AS:OnLogin()
	SK.After(AS.QUERY_DELAY + math.random() * 30, function() self:SendQuery() end)
end
