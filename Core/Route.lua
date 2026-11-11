-- Cheapest levelling route (levelling tools step 4): from your skill to a
-- target, the recipe that costs least per skill point at each point, from
-- the recipes you've learned. Ranges are Forever's (RecipeDB.Range); costs
-- count what you'd get for selling what you make (Prices). Open to everyone.
-- The planning is pure; tested.
local _, SK = ...

local Route = SK:NewModule("Route")

-- Chance that one craft gives a point at `skill`. Orange always does; from
-- yellow it falls to nothing at grey: (grey - skill) / (grey - yellow).
-- That's the original game's rule; Forever's isn't published, so it's an
-- estimate (the colours themselves are checked against the game).
function Route.Chance(range, skill)
	if skill < range.yellow then return 1 end
	if skill >= range.grey then return 0 end
	return (range.grey - skill) / (range.grey - range.yellow)
end

-- Points one craft gives on average at `skill` (orange can give several).
function Route.Gain(range, skill)
	if skill < range.yellow then return math.max(1, range.ups or 1) end
	return Route.Chance(range, skill)
end

-- recipes = { { recipeID, range, net = copper per craft after selling what
-- it makes (nil = no price), and for one you haven't learned (v0.5.2)
-- learnAt = skill needed, learnCost = copper, learn = { item | trainer } } }.
-- Returns steps { recipeID, from, to, crafts, net, cost, learn } (cost nil
-- when unpriced; learn = { cost, item | trainer } on the first step that
-- needs it), the total (crafts and learning) and how many steps had no price.
-- If the recipes run out before `to`, a last step { stuck, from }.
-- Each point uses the recipe with the lowest cost per point there; a recipe
-- still to learn adds its learning cost spread over the points it can give
-- from here (so a pattern isn't judged on its first point alone). A recipe
-- without a price is only used when no priced one gives points.
function Route.Plan(recipes, from, to)
	local steps, skill, guard, paid = {}, from, 0, {}
	while skill < to and guard < 2000 do
		guard = guard + 1
		local best, bestPer, bestGain
		for _, r in ipairs(recipes) do
			local usable = skill >= (r.learnAt or 0)
			local gain = usable and r.range and Route.Gain(r.range, skill) or 0
			if gain > 0 then
				local per = r.net and r.net / gain or nil
				if per and (r.learnCost or 0) > 0 and not paid[r.recipeID] then
					local span = math.max(1, math.min(r.range.grey, to) - skill)
					per = per + r.learnCost / span
				end
				local better
				if not best then better = true
				elseif per and not bestPer then better = true
				elseif per and bestPer then better = per < bestPer or (per == bestPer and gain > bestGain)
				elseif not per and not bestPer then better = gain > bestGain end
				if better then best, bestPer, bestGain = r, per, gain end
			end
		end
		if not best then
			steps[#steps + 1] = { stuck = true, from = skill }
			break
		end
		local orange = skill < best.range.yellow
		local points = orange and math.min(math.max(1, best.range.ups or 1), to - skill) or 1
		local crafts = orange and 1 or 1 / bestGain
		local last = steps[#steps]
		if last and not last.stuck and last.recipeID == best.recipeID then
			last.to, last.exact = skill + points, last.exact + crafts
		else
			steps[#steps + 1] = { recipeID = best.recipeID, from = skill, to = skill + points, exact = crafts,
				net = best.net }
			if best.learnAt and not paid[best.recipeID] then
				steps[#steps].learn = { cost = best.learnCost or 0, item = best.learn and best.learn.item,
					trainer = best.learn and best.learn.trainer }
			end
		end
		paid[best.recipeID] = true
		skill = skill + points
	end
	local total, unpriced = 0, 0
	for _, s in ipairs(steps) do
		if not s.stuck then
			s.crafts = math.ceil(s.exact - 1e-9)
			s.exact = nil
			if s.net then
				s.cost = s.crafts * s.net
				total = total + s.cost
			else
				unpriced = unpriced + 1
			end
			if s.learn then total = total + s.learn.cost end
		end
	end
	return steps, total, unpriced
end

-- How to learn a recipe you don't know (v0.5.2), cheapest way first:
-- { learnAt, learnCost, learn = { item | trainer } } or nil. A recipe item
-- counts only with a price (TSM, or a vendor you've visited): without one we
-- don't know you can get it. Trainer recipes count once you've seen them.
function Route.HowToLearn(recipeID)
	local best
	local item, itemAt = SK.RecipeDB.RecipeItem(recipeID)
	if item then
		local price = SK.Prices.Buy(item)
		if price then best = { learnAt = itemAt or 0, learnCost = price, learn = { item = item } } end
	end
	local t = type(SK.DB.trainer) == "table" and SK.DB.trainer[recipeID]
	if t and type(t.at) == "number" and (not best or (t.cost or 0) < best.learnCost) then
		best = { learnAt = t.at, learnCost = t.cost or 0, learn = { trainer = true } }
	end
	return best
end

-- Your recipes in one profession, with their range and net cost; with
-- `toLearn`, also the ones you could learn (v0.5.2).
function Route.Recipes(skillLine, known, toLearn)
	local out = {}
	for _, r in ipairs(SK.RecipeDB.List(skillLine)) do
		local range = SK.RecipeDB.Range(r.recipeID)
		local how = range and not known[r.recipeID] and toLearn and Route.HowToLearn(r.recipeID)
		if range and (known[r.recipeID] or how) then
			local c = SK.Prices.Recipe(r.recipeID)
			local e = { recipeID = r.recipeID, itemID = r.itemID, range = range,
				net = c.cost and (c.cost - (c.value or 0)) or nil }
			if how then e.learnAt, e.learnCost, e.learn = how.learnAt, how.learnCost, how.learn end
			out[#out + 1] = e
		end
	end
	return out
end

-- The whole plan for one of your professions, from your skill to its cap:
-- steps, total, unpriced, from, to (or nil when there's nothing to plan).
function Route.ForProfession(skillLine)
	local own = SK.Profile and SK.Profile:Own()
	local prof = own and skillLine and own.profs[skillLine]
	if not prof or not prof.scanned then return nil end
	local from, to = prof.rank or 0, prof.max or 0
	if from >= to then return {}, 0, 0, from, to end
	local known = {}
	for id in pairs(own.recipes and own.recipes[skillLine] or {}) do known[id] = true end
	local toLearn = SK.DB.settings.routeLearn ~= false
	local steps, total, unpriced = SK.Prices.Batch(function()
		return Route.Plan(Route.Recipes(skillLine, known, toLearn), from, to)
	end)
	return steps, total, unpriced, from, to
end

-- Every crafted step onto the shopping list.
function Route.AddToShopping(steps)
	local n = 0
	for _, s in ipairs(steps) do
		if not s.stuck and s.crafts and s.crafts > 0 then
			SK.Shopping.Add(s.recipeID, s.crafts)
			n = n + 1
		end
	end
	return n
end
