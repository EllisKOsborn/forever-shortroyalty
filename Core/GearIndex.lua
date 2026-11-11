-- Who in the guild wears an item (v0.5.5), from the gear guildmates already
-- share (players who hide their gear send none, so they're never listed).
-- Rebuilt only when profiles or the roster change. The index is pure; tested.
local _, SK = ...

local GI = SK:NewModule("GearIndex")

-- Pure: { [itemID] = { guid, ... } } from profiles { [guid] = { gear = { [slot] = link } } }.
function GI.Build(profiles)
	local out = {}
	for guid, p in pairs(profiles or {}) do
		local seen = {}
		for _, link in pairs(type(p) == "table" and type(p.gear) == "table" and p.gear or {}) do
			local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
			if id and not seen[id] then
				seen[id] = true
				out[id] = out[id] or {}
				table.insert(out[id], guid)
			end
		end
	end
	return out
end

local index
function GI.Dirty() index = nil end

local function get()
	if not index then
		local guild = SK.DBM:Guild()
		index = GI.Build(guild and guild.profiles)
	end
	return index
end

-- { { guid, name, class, online } } for an item, online first, then by name.
function GI.Wearers(itemID)
	local guild = SK.DBM:Guild()
	local out = {}
	for _, guid in ipairs(get()[itemID] or {}) do
		local m = guild and guild.members[guid]
		if m then out[#out + 1] = { guid = guid, name = m.name or "?", class = m.class, online = m.online == true } end
	end
	table.sort(out, function(a, b)
		if a.online ~= b.online then return a.online end
		return a.name < b.name
	end)
	return out
end

-- Pure: "worn by Fizzwick, Brambletoe (+2)".
function GI.Text(wearers, max)
	if #wearers == 0 then return nil end
	local names = {}
	for i = 1, math.min(max or 3, #wearers) do names[i] = wearers[i].name end
	local more = #wearers - #names
	return "worn by " .. table.concat(names, ", ") .. (more > 0 and (" (+" .. more .. ")") or "")
end

-- Items guildmates wear whose name contains `query` (names this game has
-- loaded): { { itemID, name } }, at most `max`.
function GI.Search(query, max)
	local q = type(query) == "string" and query:lower() or ""
	local out = {}
	if #q < 3 then return out end
	for id in pairs(get()) do
		local name = SK.CraftIndex.ItemName(id)
		if name and name:lower():find(q, 1, true) then out[#out + 1] = { itemID = id, name = name } end
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	while #out > (max or 10) do table.remove(out) end
	return out
end

for _, msg in ipairs({ "PROFILE_UPDATED", "SELF_UPDATED", "ROSTER_UPDATED" }) do SK:On(msg, GI.Dirty) end
