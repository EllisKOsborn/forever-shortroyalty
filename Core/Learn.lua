-- Where to learn a recipe (v0.5.0), all from Forever or the player's own game:
--   * recipe items (pattern, plan, formula...) and the skill they need, from
--     Forever's data (Data/Recipes.lua RECIPE_ITEMS);
--   * trainer recipes, skill and cost, remembered whenever you open a
--     trainer (ShortRoyaltyDB.trainer);
--   * the game's own "where from" text for unlearned recipes, read while a
--     profession window is open (ShortRoyaltyDB.recipeSource).
-- Everything stays on this computer. The matching and wording are pure; tested.
local _, SK = ...

local Learn = SK:NewModule("Learn")
local Compat = SK.Compat

Learn.MAX_TEXT = 160

local function store(key)
	if type(SK.DB[key]) ~= "table" then SK.DB[key] = {} end
	return SK.DB[key]
end

-- Game text as one plain line: no colours, icons or links; "|n" -> ", ".
function Learn.Plain(text)
	if type(text) ~= "string" then return nil end
	text = SK.Export.Plain(text:gsub("|n", ", ")):gsub("[\r\n]+", ", "):gsub("%s+", " ")
	text = text:gsub("^[%s,]+", ""):gsub("[%s,]+$", "")
	if text == "" then return nil end
	if #text > Learn.MAX_TEXT then text = text:sub(1, Learn.MAX_TEXT - 3) .. "..." end
	return text
end

---------------------------------------------------------------------------
-- The game's own text, from a profession scan
---------------------------------------------------------------------------
function Learn.StoreSources(sources, reasons)
	local db, n = store("recipeSource"), 0
	for id, t in pairs(sources or {}) do
		local text = Learn.Plain(t)
		if text then
			db[id] = db[id] or {}
			db[id].text = text
			n = n + 1
			Learn.sample = Learn.sample or { id = id, text = text }
		end
	end
	for id, r in pairs(reasons or {}) do
		local reason = Learn.Plain(r)
		if reason then
			db[id] = db[id] or {}
			db[id].reason = reason
			Learn.sampleReason = Learn.sampleReason or { id = id, text = reason }
		end
	end
	Learn.lastSources = n
	if n > 0 then SK:Fire("LEARN_CHANGED") end
	return n
end

---------------------------------------------------------------------------
-- Trainers
---------------------------------------------------------------------------
-- A trainer names the profession ("Tailoring"): our skillLine for it, from
-- the English names or the names your own game uses for your professions.
function Learn.SkillLineByName(name)
	if type(name) ~= "string" then return nil end
	local lower = name:lower()
	for skillLine, p in pairs(SK.Data.PROFESSIONS or {}) do
		if p.key:lower() == lower then return skillLine end
	end
	local own = SK.Profile and SK.Profile:Own()
	for skillLine, p in pairs(own and own.profs or {}) do
		if type(p.name) == "string" and p.name:lower() == lower then return skillLine end
	end
end

-- [lower-case name] = { recipeIDs } for one profession, leaving out recipes
-- that a recipe item teaches (trainers don't). nameOf(recipeID) -> name.
function Learn.NameIndex(skillLine, nameOf)
	local index = {}
	for _, r in ipairs(SK.RecipeDB.List(skillLine)) do
		if not SK.RecipeDB.RecipeItem(r.recipeID) then
			local name = nameOf(r.recipeID)
			if type(name) == "string" then
				local key = name:lower()
				index[key] = index[key] or {}
				table.insert(index[key], r.recipeID)
			end
		end
	end
	return index
end

-- Pure: trainer services -> { [recipeID] = { at, cost } }. indexFor(skillLine)
-- gives a NameIndex. A name that fits more than one recipe is skipped.
function Learn.Match(services, indexFor)
	local out, matched = {}, 0
	for _, s in ipairs(services or {}) do
		local skillLine = Learn.SkillLineByName(s.skill)
		local index = skillLine and indexFor(skillLine)
		local ids = index and type(s.name) == "string" and index[s.name:lower()]
		if ids and #ids == 1 and type(s.rank) == "number" then
			out[ids[1]] = { at = s.rank, cost = s.cost }
			matched = matched + 1
		end
	end
	return out, matched
end

function Learn.ScanTrainer()
	local services = Compat.TrainerServices()
	if not services then return 0 end
	local cache = {}
	local function indexFor(skillLine)
		cache[skillLine] = cache[skillLine] or Learn.NameIndex(skillLine, Compat.SpellName)
		return cache[skillLine]
	end
	local found, matched = Learn.Match(services, indexFor)
	local db, now = store("trainer"), Compat.Now()
	for id, t in pairs(found) do db[id] = { at = t.at, cost = t.cost, seen = now } end
	Learn.lastTrainer = { listed = #services, matched = matched, at = now }
	if matched > 0 then SK:Fire("LEARN_CHANGED") end
	return matched
end

function Learn.TrainerKnown()
	local n = 0
	for _ in pairs(store("trainer")) do n = n + 1 end
	return n
end

-- Recipes a trainer you've visited teaches at or below `skill` that you
-- haven't learned: { recipeID, ... } cheapest first.
function Learn.Trainable(skillLine, skill, known)
	local out = {}
	for id, t in pairs(store("trainer")) do
		local r = SK.RecipeDB.Get(id)
		if r and r.skillLine == skillLine and type(t.at) == "number" and t.at <= (skill or 0) and not known[id] then
			out[#out + 1] = id
		end
	end
	local db = store("trainer")
	table.sort(out, function(a, b) return (db[a].cost or 0) < (db[b].cost or 0) end)
	return out
end

---------------------------------------------------------------------------
-- What we know about one recipe, and how to say it
---------------------------------------------------------------------------
function Learn.Info(recipeID)
	local info = {}
	info.item, info.itemAt = SK.RecipeDB.RecipeItem(recipeID)
	local t = store("trainer")[recipeID]
	if t then info.trainerAt, info.trainerCost = t.at, t.cost end
	local s = store("recipeSource")[recipeID]
	if s then info.text, info.reason = s.text, s.reason end
	return info
end

-- Pure. ctx = { profName, itemName(id), price(itemID) -> copper, via, money(c) }.
-- Returns tooltip lines (plain strings; colours are added by the caller).
function Learn.Lines(info, ctx)
	local lines = {}
	local prof = ctx.profName or "skill"
	if info.item then
		local line = "Learn from " .. (ctx.itemName(info.item) or "a recipe item") ..
			(info.itemAt and info.itemAt > 0 and (" (" .. prof .. " " .. info.itemAt .. ")") or "")
		local each, via = ctx.price(info.item)
		if each then line = line .. ", " .. ctx.money(each) .. (via == "vendor" and " at a vendor" or " at auction") end
		lines[#lines + 1] = line
	end
	if info.trainerAt then
		lines[#lines + 1] = "Trainer: " .. prof .. " " .. info.trainerAt ..
			(info.trainerCost and info.trainerCost > 0 and (", " .. ctx.money(info.trainerCost)) or "")
	end
	if info.text then lines[#lines + 1] = "Source: " .. info.text end
	if not info.item and not info.trainerAt and not info.text then
		lines[#lines + 1] = "No recipe item teaches it: usually a trainer (open one to see the skill and cost)"
	end
	return lines
end

SK:RegisterEvent("TRAINER_SHOW", function() Learn.ScanTrainer() end)
SK:RegisterEvent("TRAINER_UPDATE", function() Learn.ScanTrainer() end)
