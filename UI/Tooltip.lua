-- "Crafted by" on every item tooltip: guild members who can make the item,
-- online first, at most three names. Index lookups only (no scanning), so
-- it stays cheap. Turned off in Settings with "Show guild crafters in item
-- tooltips".
local _, SK = ...

local Tip = SK:NewModule("Tooltip")
Tip.hooked = false

-- v0.9.0 Reserve+: who reserved this item for tonight's raid, with points.
function Tip.ReserveText(itemID)
	local R, LN = SK.Reserves, SK.LootNight
	local ev = LN.Tonight(SK.RaidBoard:Get(), SK.Compat.Now())
	local store, st = ev and R:Get(), R:State()
	if not store or not st then return nil end
	local picks = R.PicksOf(store, ev.id, R.PicksFor(st, ev.raid))
	return LN.TooltipText(st, picks, itemID, function(g)
		local m = SK.Identity:Member(g)
		return m and SK.Theme.ClassText((m.name or "?"):match("^(%S+)") or "?", m.class) or "?"
	end, 5)
end

function Tip.Add(tooltip, itemID)
	if not SK.DB or tooltip.IsEmbedded then return end
	if not SK.DB.settings.craftTooltips then return end
	if SK.DBM:Guild() then
		local text = Tip.ReserveText(itemID)
		if text then SK.Theme.TipLine(tooltip, SK.Theme.Code("accent") .. "Reserve+:|r " .. text, "text", true) end
	end
	local guild = SK.DBM:Guild()
	if not guild then return end
	local text = SK.CraftIndex.TooltipText(SK.CraftIndex:Get(true), itemID, guild, SK.Compat.Now(), 3)
	if text then
		SK.Theme.TipLine(tooltip, SK.Theme.Code("accent") .. "Short Royalty:|r " .. text, "text", true)
	end
	-- v0.5.5: guildmates wearing it.
	local worn = SK.GearIndex and SK.GearIndex.Text(SK.GearIndex.Wearers(itemID), 3)
	if worn then
		SK.Theme.TipLine(tooltip, SK.Theme.Code("accent") .. "Guild:|r " .. worn, "text", true)
	end
end

function Tip:OnLogin()
	self.hooked = SK.Compat.HookItemTooltips(Tip.Add)
	if not self.hooked then SK:Debug("item tooltip hook not available on this client") end
end
