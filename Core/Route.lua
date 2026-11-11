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
-- it makes (nil = no price) } }. Returns steps
--   { recipeID, from, to, crafts, net, cost } (cost nil when unpriced)
-- and, if the learned recipes run out before `to`, a last step { stuck, from }.
-- Each point uses the recipe with the lowest cost per point there; a recipe
-- without a price is only used when no priced one gives points.
function Route.Plan(recipes, from, to)
	local steps, skill, guard = {}, from, 0
	while skill < to and guard < 2000 do
		guard = guard + 1
		local best, bestPer, bestGain
		for _, r in ipairs(recipes) do
			local gain = r.range and Route.Gain(r.range, skill) or 0
			if gain > 0 then
				local per = r.net and r.net / gain or nil
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
		end
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
		end
	end
	return steps, total, unpriced
end

-- Your learned recipes in one profession, with their range and net cost.
function Route.Recipes(skillLine, known)
	local out = {}
	for _, r in ipairs(SK.RecipeDB.List(skillLine)) do
		local range = known[r.recipeID] and SK.RecipeDB.Range(r.recipeID)
		if range then
			local c = SK.Prices.Recipe(r.recipeID)
			out[#out + 1] = { recipeID = r.recipeID, itemID = r.itemID, range = range,
				net = c.cost and (c.cost - (c.value or 0)) or nil }
		end
	end
	return out
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
