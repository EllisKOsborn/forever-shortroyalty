-- Reserve+ sync (v0.9.0): sharing the points history, tonight's reserves and
-- officers' locks (Core/Reserves.lua) over the guild addon channel, on top
-- of Sync's queue, pause rules (combat, instances, chat lockdown) and limits.
--
--   LE  GUILD  points history entries { l = { entry, ... } }. Only officers
--              and raid leaders send them, and an LE is only accepted from
--              a sender with one of those ranks on OUR roster: an entry's
--              `by` field is just text in the message, so the sender is
--              what's trusted. Members get the history from any officer.
--   LP  GUILD  reserves and locks { q = { pick, ... }, k = { lock, ... } }
--              ("p", "s" and "v" are taken by every message: protocol,
--              sender, version).
--              A reserve is accepted from that player, or from an officer
--              (who may pass on anyone's); a lock only from an officer.
--   LQ  GUILD  "what I hold", once per session after login:
--              { w = { [week] = fingerprint } for the history,
--                r = { [raid id] = fingerprint } for reserves and locks }.
--              Officers answer with the history weeks and raids that differ;
--              members answer with their own reserve only. Anyone who sees
--              that they lack something sends their own LQ (max every 5 min).
--
-- `heard` stops the same entry or reserve going out twice. Older versions
-- ignore all three message types.
local _, SK = ...

local RV = SK:NewModule("ReserveSync")
local Compat = SK.Compat
local R = SK.Reserves
local Board = SK.RaidBoard

RV.DIGEST_DELAY = 100      -- LQ this long after login (after SQ and RD)
RV.ANSWER_MIN, RV.ANSWER_MAX = 2, 8
RV.CHANGE_DELAY = 3
RV.MAX_ENTRIES = 25        -- history entries per LE
RV.MAX_PICKS = 60          -- reserves per LP
RV.MAX_LOCKS = 10          -- locks per LP
RV.MAX_WEEKS = 520         -- weeks per LQ (10 years)
RV.MAX_RAIDS = 60          -- raids per LQ
RV.DIGEST_AGAIN = 300
RV.WEEK = 7 * 86400

RV.heard = {}              -- "E:"..id / "P:"..raid.."|"..guid / "K:"..raid -> true or u
RV.pending = { e = {}, p = {}, k = {} }
RV.stats = { sentLE = 0, sentLP = 0, sentLQ = 0, gotLE = 0, gotLP = 0, gotLQ = 0, accepted = 0, rejected = 0 }
RV.lastReject = nil
RV.digestAt = nil

---------------------------------------------------------------------------
-- Fingerprints (pure)
---------------------------------------------------------------------------
function RV.Week(c) return math.floor(c / RV.WEEK) end

-- { [week] = fingerprint of the ids made that week }.
function RV.LedgerDigest(store)
	local weeks = {}
	for id, e in pairs(store.ledger) do
		local w = RV.Week(e.c)
		weeks[w] = weeks[w] or {}
		table.insert(weeks[w], id)
	end
	local out = {}
	for w, ids in pairs(weeks) do
		table.sort(ids)
		out[w] = Board.Hash(table.concat(ids, ","))
	end
	return out
end

-- { [raid id] = fingerprint of its reserves and lock }.
function RV.NightDigest(store)
	local out = {}
	local ids = {}
	for id in pairs(store.picks or {}) do ids[id] = true end
	for id in pairs(store.locks or {}) do ids[id] = true end
	for id in pairs(ids) do
		local parts = {}
		local guids = {}
		for g in pairs(store.picks[id] or {}) do guids[#guids + 1] = g end
		table.sort(guids)
		for _, g in ipairs(guids) do parts[#parts + 1] = g .. "=" .. string.format("%d", store.picks[id][g].u) end
		local l = store.locks and store.locks[id]
		if l then parts[#parts + 1] = "L" .. string.format("%d", l.u) end
		out[id] = Board.Hash(table.concat(parts, ","))
	end
	return out
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
local function isLead(g) return Board.CanLead(g) end
local function meLead() return isLead(Compat.PlayerGUID()) end

local function schedule(self, delay)
	if delay == "answer" then
		SK.After(RV.ANSWER_MIN + math.random() * (RV.ANSWER_MAX - RV.ANSWER_MIN), function() self:SendPending() end)
	else
		SK:Debounce("reservesync", RV.CHANGE_DELAY, function() self:SendPending() end)
	end
end

-- History entries (officers only send them).
function RV:Queue(ids, delay)
	for _, id in ipairs(ids or {}) do self.pending.e[id] = true end
	schedule(self, delay)
end

function RV:QueuePick(raidID, guid, delay)
	self.pending.p[raidID .. "|" .. guid] = true
	schedule(self, delay)
end

function RV:QueueLock(raidID, delay)
	self.pending.k[raidID] = true
	schedule(self, delay)
end

local function newKey() return tostring(Compat.Now()) .. ":" .. math.random(1e6) end

function RV:SendPending()
	local store = R:Get()
	if not store then return 0 end
	local pend = self.pending
	self.pending = { e = {}, p = {}, k = {} }
	local sent = 0
	-- History: only from officers (nobody would accept it from anyone else).
	if meLead() then
		local ids = {}
		for id in pairs(pend.e) do
			if store.ledger[id] and not self.heard["E:" .. id] then ids[#ids + 1] = id end
		end
		table.sort(ids)
		local batch = {}
		local function flush()
			if #batch == 0 then return end
			sent = sent + 1
			self.stats.sentLE = self.stats.sentLE + 1
			SK.Sync:Enqueue("LE:" .. newKey(), "GUILD", nil, "NORMAL", { t = "LE", l = batch })
			batch = {}
		end
		for _, id in ipairs(ids) do
			batch[#batch + 1] = store.ledger[id]
			self.heard["E:" .. id] = true
			if #batch >= RV.MAX_ENTRIES then flush() end
		end
		flush()
	end
	-- Reserves and locks.
	local msg = { t = "LP", q = {}, k = {} }
	local function flushLP()
		if #msg.q == 0 and #msg.k == 0 then return end
		sent = sent + 1
		self.stats.sentLP = self.stats.sentLP + 1
		SK.Sync:Enqueue("LP:" .. newKey(), "GUILD", nil, "NORMAL", msg)
		msg = { t = "LP", q = {}, k = {} }
	end
	local lead, me = meLead(), Compat.PlayerGUID()
	local keys = {}
	for k in pairs(pend.p) do keys[#keys + 1] = k end
	table.sort(keys)
	for _, k in ipairs(keys) do
		local raidID, g = k:match("^(.+)|(.+)$")
		local p = raidID and store.picks[raidID] and store.picks[raidID][g]
		-- Members only pass on their own reserves (nobody accepts others').
		if p and (lead or g == me) and (self.heard["P:" .. k] or -1) < p.u then
			msg.q[#msg.q + 1] = { e = raidID, g = g, i = p.i, u = p.u }
			self.heard["P:" .. k] = p.u
			if #msg.q >= RV.MAX_PICKS then flushLP() end
		end
	end
	if lead then
		for raidID in pairs(pend.k) do
			local l = store.locks[raidID]
			if l and (self.heard["K:" .. raidID] or -1) < l.u then
				msg.k[#msg.k + 1] = { e = l.e, by = l.by, u = l.u, x = l.x, b = l.b, s = l.s }
				self.heard["K:" .. raidID] = l.u
				if #msg.k >= RV.MAX_LOCKS then flushLP() end
			end
		end
	end
	flushLP()
	return sent
end

function RV:SendDigest()
	local store = R:Get()
	if not store then return end
	R.PruneNights(store, R.RaidExists)
	local w, r, n = {}, {}, 0
	for week, h in pairs(RV.LedgerDigest(store)) do
		n = n + 1
		if n > RV.MAX_WEEKS then break end
		w[week] = h
	end
	n = 0
	for id, h in pairs(RV.NightDigest(store)) do
		n = n + 1
		if n > RV.MAX_RAIDS then break end
		r[id] = h
	end
	self.digestAt = Compat.Now()
	self.stats.sentLQ = self.stats.sentLQ + 1
	SK.Sync:Enqueue("LQ", "GUILD", nil, "NORMAL", { t = "LQ", w = w, r = r })
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local function count(self, ok, why, quiet)
	if ok then
		self.stats.accepted = self.stats.accepted + 1
	elseif not quiet[why or ""] then
		self.stats.rejected = self.stats.rejected + 1
		self.lastReject = why
	end
end
local QUIET = { ["already have it"] = true, ["not newer"] = true }

function RV:HandleLE(msg, from)
	local store = R:Get()
	if not store or type(msg.l) ~= "table" then return end
	self.stats.gotLE = self.stats.gotLE + 1
	if not isLead(from) then
		self.stats.rejected = self.stats.rejected + 1
		self.lastReject = "points from someone who isn't an officer"
		return
	end
	local now, changed = Compat.Now(), false
	for n, e in ipairs(msg.l) do
		if n > RV.MAX_ENTRIES then break end
		local ok, why = R.Merge(store, e, now, isLead)
		count(self, ok, why, QUIET)
		if ok then changed = true end
		if type(e) == "table" and type(e.id) == "string" and (ok or why == "already have it") then self.heard["E:" .. e.id] = true end
	end
	if changed then SK:Debounce("reservesui", 1, function() SK:Fire("RESERVES_UPDATED") end) end
end

function RV:HandleLP(msg, from)
	local store = R:Get()
	if not store then return end
	self.stats.gotLP = self.stats.gotLP + 1
	local now, changed = Compat.Now(), false
	local lead = isLead(from)
	local ctx = {
		now = now, officer = lead, raidExists = R.RaidExists,
		canWrite = function(g) return g == from or lead end,
	}
	for n, p in ipairs(type(msg.q) == "table" and msg.q or {}) do
		if n > RV.MAX_PICKS then break end
		local ok, why = R.MergePick(store, p, ctx)
		count(self, ok, why, QUIET)
		if ok then changed = true end
		if ok and type(p) == "table" then self.heard["P:" .. p.e .. "|" .. p.g] = p.u end
	end
	if lead then
		for n, l in ipairs(type(msg.k) == "table" and msg.k or {}) do
			if n > RV.MAX_LOCKS then break end
			local ok, why = R.MergeLock(store, l, now, isLead, R.RaidExists)
			count(self, ok, why, QUIET)
			if ok then changed = true; self.heard["K:" .. l.e] = l.u end
		end
	elseif type(msg.k) == "table" and #msg.k > 0 then
		self.stats.rejected = self.stats.rejected + 1
		self.lastReject = "a lock from someone who isn't an officer"
	end
	if changed then SK:Debounce("reservesui", 1, function() SK:Fire("RESERVES_UPDATED") end) end
end

function RV:HandleLQ(msg, from)
	local store = R:Get()
	if not store or type(msg.w) ~= "table" or type(msg.r) ~= "table" then return end
	self.stats.gotLQ = self.stats.gotLQ + 1
	local lead, me = meLead(), Compat.PlayerGUID()
	local lacking = false
	-- History weeks.
	local mine = RV.LedgerDigest(store)
	local n = 0
	for w, h in pairs(msg.w) do
		n = n + 1
		if n > RV.MAX_WEEKS then break end
		if type(w) == "number" and type(h) == "string" and mine[w] ~= h then lacking = true end
	end
	if lead then
		local ids = {}
		for id, e in pairs(store.ledger) do
			local w = RV.Week(e.c)
			if msg.w[w] ~= mine[w] then
				self.heard["E:" .. id] = nil
				ids[#ids + 1] = id
			end
		end
		if #ids > 0 then self:Queue(ids, "answer") end
	end
	-- Reserves and locks.
	local nights = RV.NightDigest(store)
	for id, h in pairs(nights) do
		if msg.r[id] ~= h then
			if lead then
				for g in pairs(store.picks[id] or {}) do
					self.heard["P:" .. id .. "|" .. g] = nil
					self:QueuePick(id, g, "answer")
				end
				if store.locks[id] then
					self.heard["K:" .. id] = nil
					self:QueueLock(id, "answer")
				end
			elseif me and store.picks[id] and store.picks[id][me] then
				self.heard["P:" .. id .. "|" .. me] = nil
				self:QueuePick(id, me, "answer")
			end
		end
	end
	n = 0
	for id, h in pairs(msg.r) do
		n = n + 1
		if n > RV.MAX_RAIDS then break end
		if type(id) == "string" and #id <= 80 and type(h) == "string" and nights[id] ~= h then lacking = true end
	end
	if lacking and not lead and isLead(from) and (not self.digestAt or Compat.Now() - self.digestAt >= RV.DIGEST_AGAIN) then
		-- An officer holds something we don't: ask the channel once.
		self.digestAt = Compat.Now()
		SK.After(RV.ANSWER_MIN + math.random() * (RV.ANSWER_MAX - RV.ANSWER_MIN), function() self:SendDigest() end)
	end
end

SK.Sync.handlers.LE = function(_, msg, from, dist)
	if dist == "GUILD" then RV:HandleLE(msg, from) end
end
SK.Sync.handlers.LP = function(_, msg, from, dist)
	if dist == "GUILD" then RV:HandleLP(msg, from) end
end
SK.Sync.handlers.LQ = function(_, msg, from, dist)
	if dist == "GUILD" then RV:HandleLQ(msg, from) end
end

function RV:OnLogin()
	SK.After(RV.DIGEST_DELAY + math.random() * 20, function() self:SendDigest() end)
end
