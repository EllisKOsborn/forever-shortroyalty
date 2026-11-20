-- Boss assignments (v0.11.0; idea from OXM, our own build): per raid,
-- officers add a block per boss (a short name they type) with lines of a
-- task from a fixed list and up to five players. Everyone sees them, and
-- each player's own jobs show on the Raids tab.
--
-- board.assign[id][key] = { name, o = order, lines = { { t = task, g = { guid... } } },
--                           u = changed, by = officer, x = true when deleted }
-- Shared in RB as `as` (whole block, newest wins); older versions ignore it.
-- The block name is the only typed text: plain, at most NAME_MAX letters,
-- no "|" or control characters, and only from officers or raid leaders.
--
-- Pure parts (tested): CleanName, ValidBlock, MergeBlock, Blocks, JobsOf.
local _, SK = ...

local RA = SK:NewModule("RaidAssign")
local Compat = SK.Compat

RA.NAME_MAX = 30
RA.MAX_BLOCKS = 12
RA.MAX_LINES = 12
RA.MAX_PLAYERS = 5
RA.TASKS = {
	{ "mt", "Main tank" }, { "ot", "Off tank" }, { "th", "Tank healer" }, { "rh", "Raid healer" },
	{ "int", "Interrupt" }, { "disp", "Dispel" }, { "dec", "Decurse" }, { "kite", "Kite" },
	{ "cd", "Cooldowns" }, { "soak", "Soak" }, { "mark", "Marks" }, { "pull", "Pull" },
}
RA.TASK_NAME = {}
for _, t in ipairs(RA.TASKS) do RA.TASK_NAME[t[1]] = t[2] end

local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
local function str(v, max) return type(v) == "string" and #v > 0 and #v <= max end

function RA.CleanName(text)
	text = tostring(text or ""):gsub("|", ""):gsub("[%c]", " "):gsub("%s+", " ")
	text = text:gsub("^%s+", ""):gsub("%s+$", "")
	if #text > RA.NAME_MAX then text = text:sub(1, RA.NAME_MAX) end
	return text
end

function RA.ValidBlock(b, now)
	if type(b) ~= "table" then return false, "not a table" end
	if not str(b.e, 80) or not str(b.k, 80) or not str(b.by, 64) then return false, "bad id" end
	if not finite(b.u) or b.u > now + SK.RaidBoard.MAX_FUTURE then return false, "bad time" end
	if b.x ~= nil and b.x ~= true then return false, "bad delete" end
	if not str(b.name, RA.NAME_MAX) or b.name:find("[|%c]") then return false, "bad name" end
	if not finite(b.o) then return false, "bad order" end
	if type(b.lines) ~= "table" or #b.lines > RA.MAX_LINES then return false, "bad lines" end
	local n = 0
	for _ in pairs(b.lines) do n = n + 1 end
	if n ~= #b.lines then return false, "bad lines" end
	for _, l in ipairs(b.lines) do
		if type(l) ~= "table" or not RA.TASK_NAME[l.t] or type(l.g) ~= "table" or #l.g > RA.MAX_PLAYERS then
			return false, "bad line"
		end
		for _, g in ipairs(l.g) do if not str(g, 64) then return false, "bad player" end end
	end
	return true
end

local function copyLines(lines)
	local out = {}
	for i, l in ipairs(lines or {}) do
		local g = {}
		for j, x in ipairs(l.g or {}) do g[j] = x end
		out[i] = { t = l.t, g = g }
	end
	return out
end
RA.CopyLines = copyLines

function RA.MergeBlock(board, b, now, isLead)
	local ok, why = RA.ValidBlock(b, now)
	if not ok then return false, why end
	if not isLead(b.by) then return false, "not an officer or raid leader" end
	if not board.events[b.e] then return false, "unknown raid" end
	board.assign = board.assign or {}
	local list = board.assign[b.e] or {}
	board.assign[b.e] = list
	local have = list[b.k]
	if have and have.u >= b.u then return false, "not newer" end
	if not have and SK.Count(list) >= RA.MAX_BLOCKS * 2 then return false, "too many" end
	list[b.k] = { name = b.name, o = b.o, lines = copyLines(b.lines), u = b.u, by = b.by, x = b.x }
	return true
end

-- The raid's blocks in order (deleted left out): { { key, name, lines } }.
function RA.Blocks(board, id)
	local out = {}
	for k, b in pairs(board.assign and board.assign[id] or {}) do
		if not b.x then out[#out + 1] = { key = k, name = b.name, o = b.o, lines = b.lines } end
	end
	table.sort(out, function(a, b) if a.o ~= b.o then return a.o < b.o end return a.key < b.key end)
	return out
end

-- One player's jobs: { "Interrupt on Onyxia", ... }.
function RA.JobsOf(board, id, guid)
	local out = {}
	for _, b in ipairs(RA.Blocks(board, id)) do
		for _, l in ipairs(b.lines) do
			for _, g in ipairs(l.g) do
				if g == guid then out[#out + 1] = RA.TASK_NAME[l.t] .. " on " .. b.name end
			end
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Officers' changes
---------------------------------------------------------------------------
local function save(id, key, block)
	local B = SK.RaidBoard
	local board, officer, now = B:Get(), Compat.PlayerGUID(), Compat.Now()
	if not board or not board.events[id] then return false, "unknown raid" end
	if not B.CanLead(officer) then return false, "only officers and raid leaders can change assignments" end
	board.assign = board.assign or {}
	local list = board.assign[id] or {}
	board.assign[id] = list
	local have = list[key]
	block.u, block.by = math.max(now, have and have.u + 1 or 0), officer
	list[key] = block
	SK:Fire("RAIDS_UPDATED")
	if SK.RaidSync then SK.RaidSync:Queue({ "A:" .. id .. "|" .. key }) end
	return true
end

local function current(id, key)
	local board = SK.RaidBoard:Get()
	local b = board and board.assign and board.assign[id] and board.assign[id][key]
	if not b or b.x then return nil end
	return { name = b.name, o = b.o, lines = copyLines(b.lines) }
end

-- Returns the new block's key.
function RA:AddBlock(id, name)
	name = RA.CleanName(name)
	if name == "" then return nil, "type a boss name" end
	local board = SK.RaidBoard:Get()
	local blocks = board and RA.Blocks(board, id) or {}
	if #blocks >= RA.MAX_BLOCKS then return nil, "that's the most bosses a raid can have here" end
	local key = (Compat.PlayerGUID() or "x"):sub(-8) .. ":" .. string.format("%d", Compat.Now()) .. ":" .. (#blocks + 1)
	local ok, why = save(id, key, { name = name, o = (#blocks > 0 and blocks[#blocks].o or 0) + 1, lines = {} })
	if not ok then return nil, why end
	return key
end

function RA:DeleteBlock(id, key)
	local b = current(id, key)
	if not b then return false, "unknown boss" end
	b.x = true
	return save(id, key, b)
end

function RA:AddLine(id, key, task)
	local b = current(id, key)
	if not b then return false, "unknown boss" end
	if not RA.TASK_NAME[task] then return false, "pick a task" end
	if #b.lines >= RA.MAX_LINES then return false, "that's the most lines a boss can have" end
	b.lines[#b.lines + 1] = { t = task, g = {} }
	return save(id, key, b)
end

function RA:RemoveLine(id, key, line)
	local b = current(id, key)
	if not b or not b.lines[line] then return false, "unknown line" end
	table.remove(b.lines, line)
	return save(id, key, b)
end

-- Add the player to the line, or take them off if they're on it.
function RA:TogglePlayer(id, key, line, guid)
	local b = current(id, key)
	local l = b and b.lines[line]
	if not l then return false, "unknown line" end
	for i, g in ipairs(l.g) do
		if g == guid then
			table.remove(l.g, i)
			return save(id, key, b)
		end
	end
	if #l.g >= RA.MAX_PLAYERS then return false, "that line is full (" .. RA.MAX_PLAYERS .. " players)" end
	l.g[#l.g + 1] = guid
	return save(id, key, b)
end

-- Copy the blocks of the last earlier raid of the same kind (empty lines
-- keep their tasks; players stay only if they're In this raid).
function RA:CopyLast(id)
	local B = SK.RaidBoard
	local board = B:Get()
	local ev = board and board.events[id]
	if not ev then return 0, "unknown raid" end
	local best
	for oid, e in pairs(board.events) do
		if oid ~= id and e.raid == ev.raid and e.at < ev.at and #RA.Blocks(board, oid) > 0
			and (not best or e.at > best.at) then best = e end
	end
	if not best then return 0, "no earlier " .. ((B.Raid(ev.raid) or {}).name or "raid") .. " with assignments" end
	local n = 0
	for _, b in ipairs(RA.Blocks(board, best.id)) do
		local key = self:AddBlock(id, b.name)
		if key then
			local copy = current(id, key)
			for _, l in ipairs(b.lines) do
				local g = {}
				for _, x in ipairs(l.g) do if B.PlaceOf(board, id, x) == "i" then g[#g + 1] = x end end
				copy.lines[#copy.lines + 1] = { t = l.t, g = g }
			end
			save(id, key, copy)
			n = n + 1
		end
	end
	return n
end
