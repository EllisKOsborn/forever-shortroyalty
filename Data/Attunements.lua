-- Raid attunements. RULE: never guess an ID.
--   status = "classic" -> quest ID checked against Wowhead (Classic) on 2026-11-01;
--                         not yet confirmed that Forever uses the same quest.
--                         /sr debug shows whether this client knows the quest.
--   status = "none"    -> Blizzard says the raid needs no attunement.
--   status = "todo"    -> not known yet; shown as "unknown".
-- `quests` = any one of these completes it (e.g. Alliance/Horde variants).
-- `item`   = an item that must be in the player's bags to enter (checked
--            separately from the quest; only the owner can see their bags).
-- `hidden` = not in Forever's first raid wave: kept, but not shown in the UI.
--
-- Source for the first wave (checked 2 Nov 2026): Blizzard, "World of
-- Warcraft: Forever Raid Overview—Locations, Raid Sizes, and Attunement"
-- (news 24303009): only Onyxia's Lair needs attunement, and "the Drakefire
-- Amulet [must be] in your inventory. It does not need to be equipped."
-- Icy Veins' summary agrees that Barrow Deeps and Hyjal Summit have none.
-- Drakefire Amulet = item 16309 (warcraft.wiki.gg and Wowhead Forever).
local _, SK = ...
SK.Data = SK.Data or {}

SK.Data.ATTUNEMENTS = {
	{ key = "barrow", name = "Barrow Deeps", short = "Barrow", size = 10, status = "none", quests = {},
	  note = "No attunement needed (Blizzard raid overview). Opens 9 Dec 2026." },
	{ key = "hyjal", name = "Hyjal Summit", short = "Hyjal", size = 20, status = "none", quests = {},
	  note = "No attunement needed (Blizzard raid overview). Opens 9 Dec 2026." },
	{ key = "ony",  name = "Onyxia's Lair", short = "Onyxia", size = 40, status = "classic", faction = "Alliance",
	  quests = { 6502 }, item = 16309, itemName = "Drakefire Amulet",
	  note = "Drakefire Amulet quest (Alliance) and the amulet in your bags. Opens 9 Dec 2026." },
	{ key = "mc",   name = "Molten Core", status = "classic", hidden = true,
	  quests = { 7848 }, note = "Attunement to the Core. Not in the first Forever raid wave." },
	{ key = "bwl",  name = "Blackwing Lair", status = "classic", hidden = true,
	  quests = { 7761 }, note = "Blackhand's Command. Not in the first Forever raid wave." },
	{ key = "naxx", name = "Naxxramas", status = "todo", hidden = true, quests = {},
	  note = "Not announced for Forever. Verify the attunement quest IDs before adding." },
}

-- When the first raid wave opens: 9 Dec 2026 (Blizzard's raid overview).
-- 00:00 UTC; the exact unlock hour differs by region, so the UI says "about".
SK.Data.RAIDS_OPEN_AT = 1796774400

-- v0.16.8 (owner: "create dungeon groups as well - for UBRS being the main
-- one"): dungeons a group can be made for on the Raids calendar. Any member
-- can make one (raids stay officers-only); they don't count for attendance
-- or the Raider check, and have no soft reserves. Size from Forever's own
-- data: Map 229 "Blackrock Spire" MaxPlayers 10 (wago.tools, build
-- 1.60.1.71091, 25 Nov 2026). The key to enter (Seal of Ascension) isn't
-- checked: status "none" only means "nothing for the addon to check".
SK.Data.DUNGEONS = {
	{ key = "ubrs", name = "Upper Blackrock Spire", short = "UBRS", size = 10, status = "none", dungeon = true, quests = {},
	  note = "Dungeon group (10 players). The addon doesn't check the key." },
}

-- Entries shown in the UI (the first raid wave), in display order.
function SK.Data.ShownAttunements()
	local out = {}
	for _, a in ipairs(SK.Data.ATTUNEMENTS) do
		if not a.hidden then out[#out + 1] = a end
	end
	return out
end
