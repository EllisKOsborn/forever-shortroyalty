-- Raid loot lists for Reserve+ (v0.9.0). RULE: never guess an ID.
--
-- Onyxia's Lair: the ORIGINAL game's (1.12) drops. Each ID was checked on
-- warcraft.wiki.gg ("Onyxia's Lair loot (Classic)" and each item's page,
-- its wowhead classic/item= link) on 16 Nov 2026, and matches a second,
-- independent list. status = "classic": Forever may change it. Forever's
-- own item data (wago.tools build 1.60.1.70938) does NOT contain these
-- items yet, apart from the Onyxia Hide Backpack, Mature Black Dragon Sinew
-- and Head of Onyxia: raid loot is usually held back until the raid opens
-- (9 Dec 2026). The addon also learns every item that drops (officers'
-- Loot night) and officers can add items by hand (Rules tab), so the list
-- fixes itself after the first kill.
--
-- Barrow Deeps and Hyjal Summit: new raids, not in the game files and no
-- published loot yet (checked 16 Nov). Lists come from drops and officers.
--
-- Head of Onyxia: 18423 is the Alliance one (the guild is Alliance only;
-- the Horde one is 18422).
local _, SK = ...
SK.Data = SK.Data or {}

SK.Data.LOOT = {
	ony = {
		status = "classic",
		items = {
			17068, -- Deathbringer
			17075, -- Vis'kag the Bloodletter
			17064, -- Shard of the Scale
			17078, -- Sapphiron Drape
			18813, -- Ring of Binding
			18205, -- Eskhandar's Collar
			17067, -- Ancient Cornerstone Grimoire
			17966, -- Onyxia Hide Backpack
			18705, -- Mature Black Dragon Sinew
			18423, -- Head of Onyxia (Alliance)
			16914, -- Netherwind Crown
			16921, -- Halo of Transcendence
			16963, -- Helm of Wrath
			16955, -- Judgment Crown
			16900, -- Stormrage Cover
			16929, -- Nemesis Skullcap
			16939, -- Dragonstalker's Helm
			16908, -- Bloodfang Hood
		},
	},
	barrow = { status = "todo", items = {} },
	hyjal = { status = "todo", items = {} },
}
