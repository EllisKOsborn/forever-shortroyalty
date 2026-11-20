-- Raid sync (v0.8.0): sharing the raid board (Core/RaidBoard.lua) over the
-- guild addon channel, on top of Sync's queue, pause rules and limits.
--
--   RB  GUILD  raids and sign-ups { e = {event...}, su = {signup...},
--              pk = {In/Bench choice...} (v0.10.0; older versions ignore pk) }
--              sent a few seconds after a change, and in answer to RD
--   RD  GUILD  "the raids I hold" { d = { [id] = fingerprint } }, once per
--              session after login. Anyone holding a raid that differs
--              answers with an RB after a random 2-8 s delay; anyone missing
--              one of the listed raids sends its own RD the same way.
--
-- Nobody sends what someone else has just sent: `heard` remembers the
-- newest copy of each raid and sign-up seen on the channel this session.
-- Older versions ignore both message types.
local _, SK = ...

local RS = SK:NewModule("RaidSync")
local Compat = SK.Compat
local Board = SK.RaidBoard

RS.DIGEST_DELAY = 75       -- RD this long after login (after Sync's SQ)
RS.ANSWER_MIN, RS.ANSWER_MAX = 2, 8
RS.CHANGE_DELAY = 3        -- RB this long after our own change
RS.MAX_ITEMS = 120         -- raids + sign-ups per RB
RS.MAX_DIGEST = 60         -- raids per RD
RS.DIGEST_AGAIN = 300      -- an RD in answer to someone else's, at most every 5 minutes

RS.heard = {}              -- item key -> newest `u` seen on the channel
RS.pending = {}            -- item keys waiting to be sent
RS.stats = { sentRB = 0, sentRD = 0, gotRB = 0, gotRD = 0, accepted = 0, rejected = 0 }
RS.lastReject = nil
RS.digestAt = nil

local function eventKey(id) return "E:" .. id end
local function signupKey(id, guid) return "S:" .. id .. "|" .. guid end

-- The stored item for a key, as it goes on the wire, or nil.
local function wireItem(board, key)
	local id = key:match("^E:(.+)$")
	if id then
		local e = board.events[id]
		return e and "e", e and { id = e.id, by = e.by, c = e.c, raid = e.raid, at = e.at, u = e.u, x = e.x, eb = e.eb }
	end
	local pid, pguid = key:match("^P:(.+)|(.+)$")
	if pid then
		local p = board.places and board.places[pid] and board.places[pid][pguid]
		return p and "pk", p and { e = pid, g = pguid, v = p.v, u = p.u, by = p.by }
	end
	local sid, guid = key:match("^S:(.+)|(.+)$")
	local su = sid and board.signups[sid] and board.signups[sid][guid]
	return su and "su", su and { e = sid, g = guid, s = su.s, r = su.r, u = su.u, b = su.b }
end

-- Every key of one raid (the raid first, then its sign-ups).
local function raidKeys(board, id)
	local keys = { eventKey(id) }
	for guid in pairs(board.signups[id] or {}) do keys[#keys + 1] = signupKey(id, guid) end
	for guid in pairs(board.places and board.places[id] or {}) do keys[#keys + 1] = "P:" .. id .. "|" .. guid end
	return keys
end
RS.raidKeys = raidKeys

-- Mark keys to send. delay = nil: our own change (a few seconds);
-- "answer": a random 2-8 s so only one of many answers goes out.
function RS:Queue(keys, delay)
	for _, k in ipairs(keys or {}) do self.pending[k] = true end
	if delay == "answer" then
		SK.After(RS.ANSWER_MIN + math.random() * (RS.ANSWER_MAX - RS.ANSWER_MIN), function() self:SendPending() end)
	else
		SK:Debounce("raidsync", RS.CHANGE_DELAY, function() self:SendPending() end)
	end
end

-- Send what's pending and newer than anything heard. Returns messages queued.
function RS:SendPending()
	local board = Board:Get()
	if not board then return 0 end
	local keys = {}
	for k in pairs(self.pending) do keys[#keys + 1] = k end
	table.sort(keys) -- raids ("E:") before sign-ups ("S:")
	self.pending = {}
	local msg, count, sentMsgs = { t = "RB", e = {}, su = {}, pk = {} }, 0, 0
	local function flush()
		if count == 0 then return end
		sentMsgs = sentMsgs + 1
		self.stats.sentRB = self.stats.sentRB + 1
		SK.Sync:Enqueue("RB:" .. tostring(Compat.Now()) .. ":" .. sentMsgs .. ":" .. math.random(1e6), "GUILD", nil, "NORMAL", msg)
		msg, count = { t = "RB", e = {}, su = {}, pk = {} }, 0
	end
	for _, k in ipairs(keys) do
		local kind, item = wireItem(board, k)
		if item and (self.heard[k] or -1) < item.u then
			table.insert(msg[kind], item)
			self.heard[k] = item.u
			count = count + 1
			if count >= RS.MAX_ITEMS then flush() end
		end
	end
	flush()
	return sentMsgs
end

function RS:SendDigest()
	local board = Board:Get()
	if not board then return end
	Board.Prune(board, Compat.Now())
	local d, n = {}, 0
	for id, h in pairs(Board.Digest(board)) do
		n = n + 1
		if n > RS.MAX_DIGEST then break end
		d[id] = h
	end
	self.digestAt = Compat.Now()
	self.stats.sentRD = self.stats.sentRD + 1
	SK.Sync:Enqueue("RD", "GUILD", nil, "NORMAL", { t = "RD", d = d })
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
function RS:HandleRB(msg, from)
	local board = Board:Get()
	if not board then return end
	self.stats.gotRB = self.stats.gotRB + 1
	local now = Compat.Now()
	local guild = SK.DBM:Guild()
	local isLead = function(g) return Board.CanLead(g, guild) end
	local isMember = function(g) return SK.Identity:IsMember(g) end
	local changed, ours = false, {}
	local function note(key, u, mine)
		if type(u) == "number" and (self.heard[key] or -1) < u then self.heard[key] = u end
		-- We hold something newer than what was just sent: answer with it.
		if mine and type(u) == "number" and mine.u > u then ours[#ours + 1] = key end
	end
	local n = 0
	for _, e in ipairs(type(msg.e) == "table" and msg.e or {}) do
		n = n + 1
		if n > RS.MAX_ITEMS then break end
		local ok, why = Board.MergeEvent(board, e, now, isLead)
		if ok then changed = true; self.stats.accepted = self.stats.accepted + 1
		elseif why ~= "not newer" then self.stats.rejected = self.stats.rejected + 1; self.lastReject = why end
		if type(e) == "table" and type(e.id) == "string" and (ok or why == "not newer") then
			note(eventKey(e.id), e.u, board.events[e.id])
		end
	end
	for _, s in ipairs(type(msg.su) == "table" and msg.su or {}) do
		n = n + 1
		if n > RS.MAX_ITEMS then break end
		local ok, why = Board.MergeSignup(board, s, now, isMember, isLead)
		if ok then changed = true; self.stats.accepted = self.stats.accepted + 1
		elseif why ~= "not newer" then self.stats.rejected = self.stats.rejected + 1; self.lastReject = why end
		if type(s) == "table" and type(s.e) == "string" and type(s.g) == "string" and (ok or why == "not newer") then
			note(signupKey(s.e, s.g), s.u, board.signups[s.e] and board.signups[s.e][s.g])
		end
	end
	for _, p in ipairs(type(msg.pk) == "table" and msg.pk or {}) do
		n = n + 1
		if n > RS.MAX_ITEMS then break end
		local ok, why = Board.MergePlace(board, p, now, isMember, isLead)
		if ok then changed = true; self.stats.accepted = self.stats.accepted + 1
		elseif why ~= "not newer" then self.stats.rejected = self.stats.rejected + 1; self.lastReject = why end
		if type(p) == "table" and type(p.e) == "string" and type(p.g) == "string" and (ok or why == "not newer") then
			note("P:" .. p.e .. "|" .. p.g, p.u, board.places[p.e] and board.places[p.e][p.g])
		end
	end
	if #ours > 0 then self:Queue(ours, "answer") end
	if changed then
		SK:Debounce("raidsui", 1, function() SK:Fire("RAIDS_UPDATED") end)
	end
	SK:Debug("raids from %s: %s", tostring(from), changed and "changed" or "nothing new")
end

function RS:HandleRD(msg, from)
	local board = Board:Get()
	if not board or type(msg.d) ~= "table" then return end
	self.stats.gotRD = self.stats.gotRD + 1
	local mine = Board.Digest(board)
	local send, lacking, n = {}, {}, 0
	for id, h in pairs(mine) do
		-- They differ, or lack it (a cancelled raid they never had can stay that way).
		if msg.d[id] ~= h and (msg.d[id] ~= nil or not board.events[id].x) then
			for _, k in ipairs(raidKeys(board, id)) do send[#send + 1] = k end
		end
	end
	for id, h in pairs(msg.d) do
		n = n + 1
		if n > RS.MAX_DIGEST then break end
		if type(id) == "string" and #id <= 80 and type(h) == "string" and not mine[id] then lacking[#lacking + 1] = id end
	end
	-- The asker hears our copies; heard makes sure they go out only once.
	for _, k in ipairs(send) do self.heard[k] = nil end
	if #send > 0 then self:Queue(send, "answer") end
	if #lacking > 0 and (not self.digestAt or Compat.Now() - self.digestAt >= RS.DIGEST_AGAIN) then
		self.digestAt = Compat.Now()
		SK.After(RS.ANSWER_MIN + math.random() * (RS.ANSWER_MAX - RS.ANSWER_MIN), function()
			for _, id in ipairs(lacking) do
				if not board.events[id] then return self:SendDigest() end
			end
		end)
	end
	SK:Debug("raid digest from %s: %d to send, %d missing here", tostring(from), #send, #lacking)
end

SK.Sync.handlers.RB = function(_, msg, from, dist)
	if dist == "GUILD" then RS:HandleRB(msg, from) end
end
SK.Sync.handlers.RD = function(_, msg, from, dist)
	if dist == "GUILD" then RS:HandleRD(msg, from) end
end

function RS:OnLogin()
	SK.After(RS.DIGEST_DELAY + math.random() * 15, function() self:SendDigest() end)
end
