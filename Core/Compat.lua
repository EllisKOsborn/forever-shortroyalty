-- Compat: the ONLY place that calls WoW APIs which differ between clients.
-- Every function checks that the API exists first, so a missing or renamed
-- function degrades a feature instead of throwing a Lua error.
--
-- Verified against Blizzard's UI source for WoW Forever 1.60.1 (70532).
-- Items marked "unverified" must be confirmed in game (see /sr debug).
local _, SK = ...

local Compat = {}
SK.Compat = Compat

local function has(ns, fn)
	local t = ns and _G[ns]
	if fn == nil then return type(_G[ns]) == "function" end
	return type(t) == "table" and type(t[fn]) == "function"
end
Compat.has = has

-- Midnight "secret values": never store or compare them.
function Compat.IsSecret(v)
	if issecretvalue then
		local ok, secret = pcall(issecretvalue, v)
		return ok and secret
	end
	return false
end

local function clean(v)
	if v == nil or Compat.IsSecret(v) then return nil end
	return v
end
Compat.clean = clean

---------------------------------------------------------------------------
-- Time, build, account
---------------------------------------------------------------------------
function Compat.Now()
	if GetServerTime then return GetServerTime() end
	return time()
end

function Compat.BuildInfo()
	if not GetBuildInfo then return {} end
	local version, build, date, interface = GetBuildInfo()
	return { version = version, build = build, date = date, interface = interface }
end

-- Trial / starter accounts cannot send addon messages on Forever.
function Compat.IsTrial()
	if IsTrialAccount and IsTrialAccount() then return true end
	if IsVeteranTrialAccount and IsVeteranTrialAccount() then return true end
	if GameLimitedMode_IsActive and GameLimitedMode_IsActive() then return true end
	return false
end

-- Only trial accounts are blocked up front. Blizzard's
-- C_ChatInfo.AreOutgoingAddonChatMessagesRestricted() says "restricted" on
-- normal Forever realms (Blizzard uses it only to gate an esports tool on
-- tournament realms), yet SendAddonMessage to GUILD returned Success and the
-- message arrived (tested in game on 5 Nov 2026, build 70790). So the send's
-- own result code decides; see Sync's onChunkSent.
function Compat.CanSendAddonMessages()
	if Compat.IsTrial() then return false, "trial" end
	return true
end

-- Blizzard's flag, for /sr debug only (never used to block sending).
function Compat.AddonChatFlag()
	if has("C_ChatInfo", "AreOutgoingAddonChatMessagesRestricted") then
		local ok, v = pcall(C_ChatInfo.AreOutgoingAddonChatMessagesRestricted)
		if ok then return v and true or false end
	end
	return nil
end

-- Name of a SendAddonMessageResult code, e.g. 11 -> "AddOnMessageLockdown".
function Compat.SendResultName(code)
	local E = Enum and Enum.SendAddonMessageResult
	if E then
		for name, value in pairs(E) do
			if value == code then return name end
		end
	end
	return tostring(code)
end

-- Highest level a character can reach (60 on Forever; API checked in 1.60.1).
function Compat.MaxPlayerLevel()
	local fn = GetMaxLevelForPlayerExpansion or GetMaxPlayerLevel
	if fn then
		local ok, v = pcall(fn)
		if ok and type(v) == "number" and v > 0 then return v end
	end
	return 60
end

function Compat.InCombat()
	return InCombatLockdown and InCombatLockdown() or false
end

function Compat.InChatLockdown()
	if has("C_ChatInfo", "InChatMessagingLockdown") then
		return C_ChatInfo.InChatMessagingLockdown() and true or false
	end
	return false
end

-- Instance types where we pause sync. Housing ("neighborhood"/"interior")
-- is deliberately not paused.
local PAUSE_INSTANCE = { party = true, raid = true, pvp = true, arena = true, scenario = true }

function Compat.InInstance()
	if not IsInInstance then return false end
	local inInstance, kind = IsInInstance()
	return (inInstance and PAUSE_INSTANCE[kind or ""]) and true or false, kind
end

---------------------------------------------------------------------------
-- Player identity
---------------------------------------------------------------------------
function Compat.PlayerGUID()
	return clean(UnitGUID and UnitGUID("player"))
end

function Compat.PlayerFullName()
	local name, realm
	if UnitFullName then name, realm = UnitFullName("player") end
	if not name and UnitName then name = UnitName("player") end
	return clean(name), clean(realm)
end

function Compat.PlayerBasics()
	local _, classFile, classID = UnitClass("player")
	local _, raceFile = UnitRace("player")
	return {
		class = classFile,
		classID = classID,
		race = raceFile,
		level = UnitLevel("player"),
		faction = UnitFactionGroup and UnitFactionGroup("player") or nil,
	}
end

---------------------------------------------------------------------------
-- Guild
---------------------------------------------------------------------------
function Compat.IsInGuild()
	return IsInGuild and IsInGuild() or false
end

-- Returns guildName, rankName, rankIndex, realm
function Compat.GuildInfo()
	if not GetGuildInfo then return nil end
	return GetGuildInfo("player")
end

function Compat.RequestRoster()
	if has("C_GuildInfo", "GuildRoster") then
		C_GuildInfo.GuildRoster()
	elseif GuildRoster then
		GuildRoster()
	end
end

-- Officer notes are read only where the game allows it, and never synced.
function Compat.CanViewOfficerNote()
	if has("C_GuildInfo", "CanViewOfficerNote") then
		return C_GuildInfo.CanViewOfficerNote() and true or false
	end
	return CanViewOfficerNote and CanViewOfficerNote() and true or false
end

local function hoursAgo(years, months, days, hours)
	return ((years or 0) * 365 + (months or 0) * 30 + (days or 0)) * 24 + (hours or 0)
end

local function readLegacyRoster()
	if not (GetNumGuildMembers and GetGuildRosterInfo) then return nil end
	local total = GetNumGuildMembers()
	if not total or total == 0 then return nil end
	local canOfficer = Compat.CanViewOfficerNote()
	local out = {}
	for i = 1, total do
		local name, rankName, rankIndex, level, _, _, note, officerNote, online, _, classFile,
			_, _, _, _, _, guid = GetGuildRosterInfo(i)
		name, guid = clean(name), clean(guid)
		if name and guid then
			local entry = {
				name = name, guid = guid, rank = clean(rankName), rankIndex = clean(rankIndex),
				level = clean(level), class = clean(classFile), online = clean(online) and true or false,
				note = clean(note), officerNote = canOfficer and clean(officerNote) or nil,
			}
			if not entry.online and GetGuildRosterLastOnline then
				local y, m, d, h = GetGuildRosterLastOnline(i)
				if y or m or d or h then entry.lastOnlineHours = hoursAgo(y, m, d, h) end
			end
			out[#out + 1] = entry
		end
	end
	return out, total
end

local function classFileFromID(classID)
	if classID and has("C_CreatureInfo", "GetClassInfo") then
		local info = C_CreatureInfo.GetClassInfo(classID)
		return info and info.classFile
	end
end

local function readClubRoster()
	if not (has("C_Club", "GetGuildClubId") and has("C_Club", "GetClubMembers") and has("C_Club", "GetMemberInfo")) then
		return nil
	end
	local clubId = C_Club.GetGuildClubId()
	if not clubId then return nil end
	local ids = C_Club.GetClubMembers(clubId)
	if not ids or #ids == 0 then return nil end
	local out = {}
	local canOfficer = Compat.CanViewOfficerNote()
	local OFFLINE = Enum and Enum.ClubMemberPresence and Enum.ClubMemberPresence.Offline or 3
	local UNKNOWN = Enum and Enum.ClubMemberPresence and Enum.ClubMemberPresence.Unknown or 0
	for _, memberId in ipairs(ids) do
		local info = C_Club.GetMemberInfo(clubId, memberId)
		local name, guid = info and clean(info.name), info and clean(info.guid)
		if name and guid then
			local presence = clean(info.presence)
			local entry = {
				name = name, guid = guid, rank = clean(info.guildRank),
				rankIndex = info.guildRankOrder and (info.guildRankOrder - 1) or nil,
				level = clean(info.level), class = classFileFromID(clean(info.classID)),
				online = presence ~= nil and presence ~= OFFLINE and presence ~= UNKNOWN,
				note = clean(info.memberNote),
				officerNote = canOfficer and clean(info.officerNote) or nil,
			}
			if not entry.online and info.lastOnlineYear then
				entry.lastOnlineHours = hoursAgo(info.lastOnlineYear, info.lastOnlineMonth,
					info.lastOnlineDay, info.lastOnlineHour)
			end
			out[#out + 1] = entry
		end
	end
	return out, #ids
end

-- Returns list, complete, source. `complete` means we believe offline
-- members are included (needed before we mark anyone as "left").
function Compat.ReadRoster()
	local list, total = readLegacyRoster()
	if list and #list > 0 then
		local complete = #list >= total
		if GetGuildRosterShowOffline and not GetGuildRosterShowOffline() then
			complete = false
		end
		if complete then return list, true, "legacy" end
	end
	local clubList = readClubRoster()
	if clubList and #clubList > 0 then
		return clubList, true, "club"
	end
	if list and #list > 0 then return list, false, "legacy" end
	return {}, false, "none"
end

---------------------------------------------------------------------------
-- Gear
---------------------------------------------------------------------------
-- 1 Head ... 19 Tabard. 0 (ammo) is skipped.
Compat.GEAR_SLOTS = { 1, 2, 3, 15, 5, 4, 19, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }

function Compat.ReadGear()
	local gear = {}
	if not GetInventoryItemLink then return gear end
	for _, slot in ipairs(Compat.GEAR_SLOTS) do
		local link = clean(GetInventoryItemLink("player", slot))
		if link then gear[slot] = link end
	end
	return gear
end

function Compat.AverageItemLevel()
	if not GetAverageItemLevel then return nil end
	local overall, equipped = GetAverageItemLevel()
	local v = clean(equipped) or clean(overall)
	if v then return math.floor(v * 10 + 0.5) / 10 end
end

---------------------------------------------------------------------------
-- Talents
---------------------------------------------------------------------------
function Compat.TalentAPI()
	if has("C_Traits", "GetConfigInfo") and has("C_Traits", "GetTreeNodes") and has("C_Traits", "GetNodeInfo") then
		return "traits"
	elseif GetNumTalentTabs and GetTalentTabInfo then
		return "classic"
	end
	return "none"
end

function Compat.ActiveTraitConfigID()
	if has("C_SpecializationInfo", "GetCombatConfigIDForSpecGroup") then
		local group = 1
		if has("C_SpecializationInfo", "GetActiveSpecGroup") then
			group = C_SpecializationInfo.GetActiveSpecGroup() or 1
		elseif GetActiveTalentGroup then
			group = GetActiveTalentGroup() or 1
		end
		local id = C_SpecializationInfo.GetCombatConfigIDForSpecGroup(group)
		if id then return id end
	end
	if has("C_ClassTalents", "GetActiveConfigID") then
		return C_ClassTalents.GetActiveConfigID()
	end
end

---------------------------------------------------------------------------
-- Professions
---------------------------------------------------------------------------
-- Returns { [skillLineID] = { name, rank, max, icon, primary } }
function Compat.ReadProfessions()
	local out = {}
	if GetProfessions and GetProfessionInfo then
		-- Forever's ProfessionsBook reads: prof1, prof2, firstAid, fishing, cooking
		-- (Mainline's third value is archaeology). Only the first two are primary.
		local p1, p2, s1, s2, s3, s4 = GetProfessions()
		local slots = { { p1, true }, { p2, true }, { s1, false }, { s2, false }, { s3, false }, { s4, false } }
		for _, s in ipairs(slots) do
			local index = s[1]
			if index then
				local name, icon, rank, maxRank, _, _, skillLine = GetProfessionInfo(index)
				if skillLine and name then
					out[skillLine] = { name = name, rank = rank or 0, max = maxRank or 0, icon = icon, primary = s[2] }
				end
			end
		end
	end
	-- Fill gaps / zero ranks from the skill list (used by Forever's SkillsFrame).
	if has("C_SkillInfo", "GetNumSkillLines") and has("C_SkillInfo", "GetSkillLineInfo") then
		local known = SK.Data and SK.Data.PROFESSIONS or {}
		for i = 1, C_SkillInfo.GetNumSkillLines() do
			local info = C_SkillInfo.GetSkillLineInfo(i)
			if info and not info.isHeader and known[info.skillID] then
				local p = out[info.skillID]
				if not p then
					p = { name = info.name, primary = known[info.skillID].primary }
					out[info.skillID] = p
				end
				if (p.rank or 0) == 0 then
					p.rank, p.max = info.rank, info.maxRank
				end
			end
		end
	end
	return out
end

-- "modern" (C_TradeSkillUI), "classic" (GetTradeSkillInfo) or "none"
function Compat.TradeSkillAPI()
	if has("C_TradeSkillUI", "GetBaseProfessionInfo") and has("C_TradeSkillUI", "GetRecipeInfo")
		and (has("C_TradeSkillUI", "GetAllRecipeIDs") or has("C_TradeSkillUI", "GetFilteredRecipeIDs")) then
		return "modern"
	elseif GetNumTradeSkills and GetTradeSkillInfo then
		return "classic"
	end
	return "none"
end

-- True when the open profession window shows OUR recipes (not a linked,
-- guild or NPC window).
function Compat.IsOwnTradeSkill()
	local T = C_TradeSkillUI
	if not T then return true end
	if T.IsTradeSkillLinked and T.IsTradeSkillLinked() then return false end
	if T.IsTradeSkillGuild and T.IsTradeSkillGuild() then return false end
	if T.IsTradeSkillGuildMember and T.IsTradeSkillGuildMember() then return false end
	if T.IsNPCCrafting and T.IsNPCCrafting() then return false end
	if T.IsRuneforging and T.IsRuneforging() then return false end
	return true
end

-- Returns skillLineID, name, rank, max for the open window (modern API).
function Compat.OpenProfession()
	local info = C_TradeSkillUI.GetBaseProfessionInfo()
	if not info or not info.professionID then return nil end
	local rank, max = info.skillLevel, info.maxSkillLevel
	if (rank or 0) == 0 and has("C_TradeSkillUI", "GetChildProfessionInfo") then
		local child = C_TradeSkillUI.GetChildProfessionInfo()
		if child then rank, max = child.skillLevel, child.maxSkillLevel end
	end
	return info.professionID, info.professionName, rank, max
end

-- Returns list of recipe IDs and whether it is the complete list.
function Compat.RecipeIDs()
	if has("C_TradeSkillUI", "GetAllRecipeIDs") then
		return C_TradeSkillUI.GetAllRecipeIDs() or {}, true
	end
	return C_TradeSkillUI.GetFilteredRecipeIDs() or {}, false
end

function Compat.RecipeInfo(recipeID)
	local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
	if not info then return nil end
	local itemID
	if has("C_TradeSkillUI", "GetRecipeOutputItemData") then
		local ok, out = pcall(C_TradeSkillUI.GetRecipeOutputItemData, recipeID)
		if ok and out then itemID = out.itemID end
	end
	return { learned = info.learned and true or false, name = info.name, itemID = itemID,
		categoryID = info.categoryID, difficulty = clean(info.relativeDifficulty),
		disabledReason = clean(info.disabledReason) }
end

-- C_TradeSkillUI.GetShowLearned / GetShowUnlearned (the window's filter
-- checkboxes; in Forever's TradeSkillUIDocumentation). nil = unknown.
function Compat.RecipeFilters()
	local learned, unlearned
	if has("C_TradeSkillUI", "GetShowLearned") then
		local ok, v = pcall(C_TradeSkillUI.GetShowLearned)
		if ok then learned = v and true or false end
	end
	if has("C_TradeSkillUI", "GetShowUnlearned") then
		local ok, v = pcall(C_TradeSkillUI.GetShowUnlearned)
		if ok then unlearned = v and true or false end
	end
	return learned, unlearned
end

-- Category name and parent for a recipe's categoryID. GetCategoryInfo is
-- not in the generated docs, but Forever's own Blizzard_Professions.lua
-- calls it (categoryInfo.name, .parentCategoryID), so we probe for it.
function Compat.CategoryInfo(categoryID)
	if not categoryID or not has("C_TradeSkillUI", "GetCategoryInfo") then return nil end
	local ok, info = pcall(C_TradeSkillUI.GetCategoryInfo, categoryID)
	if not ok or type(info) ~= "table" then return nil end
	return clean(info.name), clean(info.parentCategoryID)
end

-- Reagents for a recipe: C_TradeSkillUI.GetRecipeSchematic(recipeSpellID,
-- isRecraft[, recipeLevel]) -> CraftingRecipeSchematic (Forever's
-- TradeSkillUIDocumentation / TradeSkillUITypesDocumentation).
-- Returns { output = itemID, min, max, reagents = { {itemID, currencyID, qty, required} } }
-- or nil plus a reason.
function Compat.RecipeSchematic(recipeID)
	if not has("C_TradeSkillUI", "GetRecipeSchematic") then return nil, "no GetRecipeSchematic" end
	local ok, s = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
	if not ok then return nil, "error: " .. tostring(s) end
	if type(s) ~= "table" then return nil, "nothing returned" end
	local out = { output = clean(s.outputItemID), min = clean(s.quantityMin), max = clean(s.quantityMax),
		name = clean(s.name), reagents = {} }
	for _, slot in ipairs(s.reagentSlotSchematics or {}) do
		local first = slot.reagents and slot.reagents[1]
		out.reagents[#out.reagents + 1] = {
			itemID = first and clean(first.itemID), currencyID = first and clean(first.currencyID),
			qty = clean(slot.quantityRequired), required = slot.required and true or false,
		}
	end
	return out
end

---------------------------------------------------------------------------
-- Character model (v0.4.3). Forever's own dressing room (Mainline
-- DressUpFrames.lua) does: ModelScene from "ModelSceneMixinTemplate",
-- TransitionToModelSceneID(596, ...), scene:GetPlayerActor(nil, nil,
-- raceFile, gender) for the camera framing, actor:SetModelByUnit(unit,
-- sheathe, autoDress, hideWeapons, nativeForm, holdBowString, customRaceID),
-- actor:Undress(), actor:TryOn(itemLink). A model can only come from a unit
-- that's present (player, target, group); face, hair and gender can't be set
-- from data (only the barber shop and character select can).
---------------------------------------------------------------------------
Compat.DRESS_UP_SCENE = 596 -- DRESS_UP_FRAME_MODEL_SCENE_ID in DressUpFrames.lua

function Compat.CanShowModels()
	return type(CreateFrame) == "function" and type(ModelSceneMixin) == "table"
end

function Compat.CreateModelScene(parent)
	if not Compat.CanShowModels() then return nil end
	local ok, scene = pcall(CreateFrame, "ModelScene", nil, parent, "ModelSceneMixinTemplate")
	return ok and scene or nil
end

-- raceFile ("NightElf") -> raceID for customRaceID, via C_CreatureInfo.GetRaceInfo.
local raceIDs
function Compat.RaceID(raceFile)
	if not raceFile or not has("C_CreatureInfo", "GetRaceInfo") then return nil end
	if not raceIDs then
		raceIDs = {}
		for id = 1, 100 do
			local ok, info = pcall(C_CreatureInfo.GetRaceInfo, id)
			if ok and type(info) == "table" and info.clientFileString and not raceIDs[info.clientFileString] then
				raceIDs[info.clientFileString] = id
			end
		end
	end
	return raceIDs[raceFile]
end

-- A unit token for this character if they're here (you, target, focus,
-- mouseover, group), else nil.
local UNITS = { "player", "target", "focus", "mouseover" }
for i = 1, 4 do UNITS[#UNITS + 1] = "party" .. i end
for i = 1, 40 do UNITS[#UNITS + 1] = "raid" .. i end
function Compat.UnitForGUID(guid)
	if not guid or not UnitGUID then return nil end
	for _, u in ipairs(UNITS) do
		local ok, g = pcall(UnitGUID, u)
		if ok and clean(g) == guid then return u end
	end
end

local function isObject(v) return type(v) == "table" or type(v) == "userdata" end

-- Shows a character on `scene`. opts = { guid, raceFile, gear = { [slot] = link } }.
-- Returns "real" (their own model: they're here), "dressed" (your character
-- in their gear, as their race when the game allows), or nil + reason.
function Compat.ShowGearModel(scene, opts)
	if not isObject(scene) then return nil, "no model support" end
	opts = opts or {}
	local ok, err = pcall(function()
		if scene.ReleaseAllActors then scene:ReleaseAllActors() end
		scene:TransitionToModelSceneID(Compat.DRESS_UP_SCENE, CAMERA_TRANSITION_TYPE_IMMEDIATE or 1,
			CAMERA_MODIFICATION_TYPE_DISCARD or 1, true)
	end)
	if not ok then return nil, "scene: " .. tostring(err) end
	local unit = Compat.UnitForGUID(opts.guid)
	local mine = unit ~= nil
	local raceFile, gender
	if mine then
		local okR, _, rf = pcall(UnitRace, unit)
		raceFile = okR and clean(rf) or opts.raceFile
		local okS, sx = pcall(UnitSex, unit)
		gender = okS and clean(sx) or nil
	else
		raceFile = opts.raceFile
		gender = UnitSex and clean(UnitSex("player")) or nil -- the body is yours
	end
	local okA, actor = pcall(scene.GetPlayerActor, scene, nil, nil, raceFile, gender)
	if not okA or not isObject(actor) then return nil, "no actor" end
	if mine then
		local okM = pcall(actor.SetModelByUnit, actor, unit, false, true, false, true, false)
		if okM then return "real" end
	end
	local raceID = opts.raceFile and Compat.RaceID(opts.raceFile) or nil
	local okM, err2 = pcall(actor.SetModelByUnit, actor, "player", false, false, false, true, false, raceID)
	if not okM then return nil, "model: " .. tostring(err2) end
	pcall(actor.Undress, actor)
	-- Weapons need their hand named, or both end up in the main hand.
	local HANDS = { [16] = "MAINHANDSLOT", [17] = "SECONDARYHANDSLOT" }
	local slots = {}
	for slot in pairs(opts.gear or {}) do slots[#slots + 1] = slot end
	table.sort(slots)
	for _, slot in ipairs(slots) do
		pcall(actor.TryOn, actor, opts.gear[slot], HANDS[slot])
	end
	return "dressed", raceID and "race" or "own race"
end

-- Does this spell exist on this client? C_Spell.DoesSpellExist is in
-- Forever's SpellDocumentation ("regardless of whether the player has
-- learned it"). nil = can't tell.
function Compat.SpellExists(spellID)
	if has("C_Spell", "DoesSpellExist") then
		local ok, v = pcall(C_Spell.DoesSpellExist, spellID)
		if ok then return v and true or false end
	end
	return nil
end

-- Does the player know this spell? C_SpellBook.IsSpellKnown(spellID[, bank])
-- is in Forever's SpellBookDocumentation (bank defaults to Player). The
-- globals are older fallbacks. Returns known (nil = can't tell), source.
function Compat.IsSpellKnown(spellID)
	if has("C_SpellBook", "IsSpellKnown") then
		local ok, v = pcall(C_SpellBook.IsSpellKnown, spellID)
		if ok then return v and true or false, "C_SpellBook.IsSpellKnown" end
	end
	if has("IsPlayerSpell") then
		local ok, v = pcall(IsPlayerSpell, spellID)
		if ok then return v and true or false, "IsPlayerSpell" end
	end
	if has("IsSpellKnown") then
		local ok, v = pcall(IsSpellKnown, spellID)
		if ok then return v and true or false, "IsSpellKnown" end
	end
	return nil, "none"
end

-- Seconds remaining, or nil.
function Compat.RecipeCooldown(recipeID)
	if not has("C_TradeSkillUI", "GetRecipeCooldown") then return nil end
	local ok, cd = pcall(C_TradeSkillUI.GetRecipeCooldown, recipeID)
	if ok and type(cd) == "number" and cd > 0 then return cd end
end

---------------------------------------------------------------------------
-- Reputation
---------------------------------------------------------------------------
-- Returns { [factionID] = { n = name, r = reaction, v = standing } }
function Compat.ReadReputations(extraIDs)
	local out = {}
	local function add(d)
		if d and d.factionID and d.factionID > 0 and (not d.isHeader or d.isHeaderWithRep) then
			out[d.factionID] = { n = d.name, r = d.reaction, v = d.currentStanding }
		end
	end
	if has("C_Reputation", "GetNumFactions") and has("C_Reputation", "GetFactionDataByIndex") then
		for i = 1, C_Reputation.GetNumFactions() do
			add(C_Reputation.GetFactionDataByIndex(i))
		end
		if extraIDs and has("C_Reputation", "GetFactionDataByID") then
			for _, id in ipairs(extraIDs) do
				if not out[id] then add(C_Reputation.GetFactionDataByID(id)) end
			end
		end
	elseif GetNumFactions and GetFactionInfo then
		for i = 1, GetNumFactions() do
			local name, _, standingID, _, _, barValue, _, _, isHeader, _, hasRep, _, _, factionID = GetFactionInfo(i)
			add({ factionID = factionID, name = name, reaction = standingID, currentStanding = barValue,
				isHeader = isHeader, isHeaderWithRep = hasRep })
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Quests
---------------------------------------------------------------------------
function Compat.IsQuestDone(questID)
	if has("C_QuestLog", "IsQuestFlaggedCompleted") then
		return C_QuestLog.IsQuestFlaggedCompleted(questID) and true or false
	elseif IsQuestFlaggedCompleted then
		return IsQuestFlaggedCompleted(questID) and true or false
	end
	return nil
end

-- How many of an item are in our bags (bank excluded), or nil if the client
-- can't tell. C_Item.GetItemCount(itemInfo, includeBank = false, ...) is in
-- Forever's ItemDocumentation.
function Compat.ItemCountInBags(itemID)
	if has("C_Item", "GetItemCount") then
		local ok, n = pcall(C_Item.GetItemCount, itemID, false)
		if ok then return clean(n) end
		return nil
	end
	if GetItemCount then return clean(GetItemCount(itemID)) end
end

-- bags, everything (bags + bank + reagent bank + account bank), or nil when
-- the game can't tell. Same Forever call, with its includeBank,
-- includeUses (false), includeReagentBank and includeAccountBank flags.
function Compat.ItemCounts(itemID)
	local bags = Compat.ItemCountInBags(itemID)
	if bags == nil then return nil end
	local total
	if has("C_Item", "GetItemCount") then
		local ok, n = pcall(C_Item.GetItemCount, itemID, true, false, true, true)
		if ok then total = clean(n) end
	elseif GetItemCount then
		total = clean(GetItemCount(itemID, true))
	end
	return bags, math.max(total or bags, bags)
end

function Compat.ShiftDown()
	return IsShiftKeyDown ~= nil and IsShiftKeyDown() == true
end

---------------------------------------------------------------------------
-- Prices (v0.4.6). Auction prices come from other addons' public APIs when
-- they're installed: Auctionator (Auctionator.API.v1) and TradeSkillMaster
-- (TSM_API). Neither is required and every call is guarded, so a missing
-- or changed API just means "no price". /sr debug shows whether each works.
---------------------------------------------------------------------------
Compat.PRICE_CALLER = "ShortRoyalty" -- the name Auctionator asks callers to pass

local function copper(v)
	v = clean(v)
	if type(v) == "number" and v == v and v >= 0 and v < 1e12 then return math.floor(v) end
end

local function auctionatorV1()
	local a = type(Auctionator) == "table" and Auctionator
	local api = a and type(a.API) == "table" and a.API
	local v1 = api and type(api.v1) == "table" and api.v1
	return v1 and type(v1.GetAuctionPriceByItemID) == "function" and v1 or nil
end

local function tsmAPI()
	return type(TSM_API) == "table" and type(TSM_API.GetCustomPriceValue) == "function" and TSM_API or nil
end

function Compat.PriceAddons()
	return { auctionator = auctionatorV1() ~= nil, tsm = tsmAPI() ~= nil }
end

-- Copper per item at the auction house, or nil.
function Compat.AuctionatorPrice(itemID)
	local v1 = auctionatorV1()
	if not v1 or type(itemID) ~= "number" then return nil end
	local ok, v = pcall(v1.GetAuctionPriceByItemID, Compat.PRICE_CALLER, itemID)
	return ok and copper(v) or nil
end

-- source is a TSM price source such as "DBMarket"; items are "i:<id>".
function Compat.TSMPrice(itemID, source)
	local api = tsmAPI()
	if not api or type(itemID) ~= "number" then return nil end
	local ok, v = pcall(api.GetCustomPriceValue, source, "i:" .. itemID)
	return ok and copper(v) or nil
end

-- What a vendor pays you for one (C_Item.GetItemInfo's sellPrice), or nil
-- while the item isn't loaded.
function Compat.VendorSellPrice(itemID)
	if not has("C_Item", "GetItemInfo") or type(itemID) ~= "number" then return nil end
	local ok, v = pcall(function() return select(11, C_Item.GetItemInfo(itemID)) end)
	return ok and copper(v) or nil
end

-- Where an unlearned recipe comes from, as the game words it ("Trainer",
-- a vendor's name, "Drop"...). Blizzard's profession window calls this for
-- unlearned recipes; it isn't in the generated docs, so it's probed (v0.5.0).
function Compat.RecipeSourceText(recipeID)
	if not has("C_TradeSkillUI", "GetRecipeSourceText") then return nil end
	local ok, t = pcall(C_TradeSkillUI.GetRecipeSourceText, recipeID)
	t = ok and clean(t) or nil
	if type(t) ~= "string" or t == "" then return nil end
	return t
end

-- The open trainer's list: { { name, kind = "available"|"unavailable"|"used", skill, rank, cost } }.
-- Blizzard's Forever trainer window (Blizzard_TrainerUI, Mainline) uses the
-- same calls. Only what the trainer's filter currently shows is listed.
function Compat.TrainerServices()
	if type(GetNumTrainerServices) ~= "function" or type(GetTrainerServiceInfo) ~= "function" then return nil end
	local okN, n = pcall(GetNumTrainerServices)
	n = okN and clean(n) or 0
	local out = {}
	for i = 1, math.min(n, 500) do
		local ok, name, kind = pcall(GetTrainerServiceInfo, i)
		name, kind = ok and clean(name) or nil, ok and clean(kind) or nil
		if type(name) == "string" and kind ~= "header" then
			local s = { name = name, kind = kind }
			if type(GetTrainerServiceSkillReq) == "function" then
				local okS, skill, rank = pcall(GetTrainerServiceSkillReq, i)
				if okS then s.skill, s.rank = clean(skill), clean(rank) end
			end
			if type(GetTrainerServiceCost) == "function" then
				local okC, cost = pcall(GetTrainerServiceCost, i)
				if okC then s.cost = copper(cost) end
			end
			out[#out + 1] = s
		end
	end
	return out
end

-- The open merchant's items for gold: { { itemID, each } } (copper per item).
-- Blizzard's Forever MerchantFrame (Mainline) uses the same three calls.
function Compat.MerchantItems()
	if type(GetMerchantNumItems) ~= "function" or type(GetMerchantItemID) ~= "function"
		or not has("C_MerchantFrame", "GetItemInfo") then return nil end
	local okN, n = pcall(GetMerchantNumItems)
	n = okN and clean(n) or 0
	local out = {}
	for i = 1, math.min(n, 300) do
		local okI, id = pcall(GetMerchantItemID, i)
		local okF, info = pcall(C_MerchantFrame.GetItemInfo, i)
		id = okI and clean(id) or nil
		if type(id) == "number" and okF and type(info) == "table" and not info.hasExtendedCost and not info.currencyID then
			local price, stack = copper(info.price), clean(info.stackCount)
			if price and price > 0 and type(stack) == "number" and stack > 0 then
				out[#out + 1] = { itemID = id, each = price / stack }
			end
		end
	end
	return out
end

-- Does this quest ID exist in this client's data? (nil = unknown yet)
function Compat.QuestTitle(questID)
	if has("C_QuestLog", "GetTitleForQuestID") then
		return C_QuestLog.GetTitleForQuestID(questID)
	end
end

---------------------------------------------------------------------------
-- Items / spells (for display)
---------------------------------------------------------------------------
-- Enchant ID from an item link ("item:itemID:enchantID:..."), 0 if none.
function Compat.EnchantFromLink(link)
	if type(link) ~= "string" then return nil end
	local e = link:match("item:%-?%d+:(%-?%d*)")
	return tonumber(e) or 0
end

-- equipLoc, classID, subClassID without needing the item cache.
function Compat.ItemEquipInfo(itemID)
	local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
	if not fn or not itemID then return nil end
	local _, _, _, equipLoc, _, classID, subClassID = fn(itemID)
	return equipLoc, classID, subClassID
end

-- Seconds until a (profession) spell is ready: >0 cooling down, 0 ready,
-- nil unknown. Ignores the 1.5 s global cooldown.
function Compat.SpellCooldownRemaining(spellID)
	local start, duration
	if has("C_Spell", "GetSpellCooldown") then
		local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
		if not ok or not info then return nil end
		start, duration = clean(info.startTime), clean(info.duration)
	elseif GetSpellCooldown then
		local ok, a, b = pcall(GetSpellCooldown, spellID)
		if not ok then return nil end
		start, duration = clean(a), clean(b)
	end
	if not start or not duration then return nil end
	if duration <= 1.5 or start == 0 then return 0 end
	return math.max(0, start + duration - GetTime())
end
function Compat.ItemIDFromLink(link)
	if type(link) ~= "string" then return nil end
	local id = link:match("item:(%d+)")
	return id and tonumber(id)
end

function Compat.ItemIcon(itemIDOrLink)
	local id = type(itemIDOrLink) == "number" and itemIDOrLink or Compat.ItemIDFromLink(itemIDOrLink)
	if not id then return nil end
	if has("C_Item", "GetItemIconByID") then return C_Item.GetItemIconByID(id) end
	if GetItemIcon then return GetItemIcon(id) end
end

function Compat.SpellName(spellID)
	if has("C_Spell", "GetSpellName") then return C_Spell.GetSpellName(spellID) end
	if has("C_Spell", "GetSpellInfo") then
		local info = C_Spell.GetSpellInfo(spellID)
		return info and info.name
	end
	if GetSpellInfo then return (GetSpellInfo(spellID)) end
end

-- Item and spell names load asynchronously. These return nil until the
-- data is cached; Request* asks the client to load it, and the client then
-- fires ITEM_DATA_LOAD_RESULT / SPELL_DATA_LOAD_RESULT (itemID|spellID, success).
-- All checked in Blizzard's Forever ItemDocumentation / SpellDocumentation.
function Compat.ItemName(itemID)
	if not itemID or itemID == 0 then return nil end
	if has("C_Item", "GetItemNameByID") then return clean(C_Item.GetItemNameByID(itemID)) end
	if GetItemInfo then return clean((GetItemInfo(itemID))) end
end

function Compat.RequestItem(itemID)
	if itemID and itemID ~= 0 and has("C_Item", "RequestLoadItemDataByID") then
		pcall(C_Item.RequestLoadItemDataByID, itemID)
		return true
	end
	return false
end

function Compat.RequestSpell(spellID)
	if spellID and has("C_Spell", "RequestLoadSpellData") then
		pcall(C_Spell.RequestLoadSpellData, spellID)
		return true
	end
	return false
end

-- "ffRRGGBB" for the item's quality, or nil while the item isn't cached.
function Compat.ItemQualityHex(itemID)
	if not itemID or itemID == 0 or not has("C_Item", "GetItemQualityByID") then return nil end
	local q = clean(C_Item.GetItemQualityByID(itemID))
	if not q then return nil end
	local r, g, b
	if has("C_Item", "GetItemQualityColor") then
		r, g, b = C_Item.GetItemQualityColor(q)
	elseif ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] then
		local c = ITEM_QUALITY_COLORS[q]
		r, g, b = c.r, c.g, c.b
	end
	if not r then return nil end
	return string.format("ff%02x%02x%02x", r * 255, g * 255, b * 255)
end

function Compat.SpellIcon(spellID)
	if has("C_Spell", "GetSpellTexture") then return C_Spell.GetSpellTexture(spellID) end
end

-- Chat links for "Post to guild chat"; nil when not cached yet.
function Compat.ItemLink(itemID)
	if not itemID or itemID == 0 then return nil end
	if has("C_Item", "GetItemInfo") then
		local _, link = C_Item.GetItemInfo(itemID)
		return clean(link)
	end
	if GetItemInfo then return clean(select(2, GetItemInfo(itemID))) end
end

function Compat.SpellLink(spellID)
	if has("C_Spell", "GetSpellLink") then return clean(C_Spell.GetSpellLink(spellID)) end
end

---------------------------------------------------------------------------
-- Chat box (SendChatMessage is restricted on Forever, so we only ever open
-- or pre-fill the chat box; the player presses Enter themselves).
---------------------------------------------------------------------------
-- Opens a whisper to `name`. Forever's 12.x UI has ChatFrameUtil.SendTell
-- (Blizzard_ChatFrameBase/Shared/ChatFrameUtil.lua); ChatFrame_SendTell is
-- the older global.
function Compat.SendTell(name)
	if not name then return false end
	if ChatFrameUtil and ChatFrameUtil.SendTell then
		ChatFrameUtil.SendTell(name)
		return true
	elseif ChatFrame_SendTell then
		ChatFrame_SendTell(name)
		return true
	end
	return false
end

-- Opens one of your own profession windows (v0.3.4, the reminder banner).
-- Blizzard's Forever UI has OpenProfessionUIToSkillLine (Blizzard_Professions
-- bootstrap, always loaded) and C_TradeSkillUI.OpenTradeSkill(skillLineID);
-- neither is restricted. Not in combat. Returns ok, why.
function Compat.CanShowProfession()
	return type(_G.OpenProfessionUIToSkillLine) == "function" or has("C_TradeSkillUI", "OpenTradeSkill")
end

function Compat.ShowProfession(skillLine)
	if type(skillLine) ~= "number" then return false, "unknown" end
	if Compat.InCombat() then return false, "combat" end
	local ok, opened
	if type(_G.OpenProfessionUIToSkillLine) == "function" then
		ok = pcall(_G.OpenProfessionUIToSkillLine, skillLine)
		if ok then return true end
	end
	if has("C_TradeSkillUI", "OpenTradeSkill") then
		ok, opened = pcall(C_TradeSkillUI.OpenTradeSkill, skillLine)
		if ok and opened ~= false then return true end
	end
	return false, "unavailable"
end

-- Opens the chat box with `text` already typed. ChatFrameUtil.OpenChat is
-- in the same Forever file; its edit box parses a leading "/g " into the
-- guild channel (ParseText on the next frame).
function Compat.OpenChat(text)
	if ChatFrameUtil and ChatFrameUtil.OpenChat then
		ChatFrameUtil.OpenChat(text)
		return true
	elseif ChatFrame_OpenChat then
		ChatFrame_OpenChat(text)
		return true
	end
	return false
end

---------------------------------------------------------------------------
-- Item tooltips: TooltipDataProcessor (Blizzard_SharedXMLGame/Tooltip/
-- TooltipDataHandler.lua) with Enum.TooltipDataType.Item (= 0 in
-- TooltipInfoSharedDocumentation). fn(tooltip, itemID).
---------------------------------------------------------------------------
function Compat.HookItemTooltips(fn)
	local kind = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item
	if not (kind and TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall) then return false end
	TooltipDataProcessor.AddTooltipPostCall(kind, function(tooltip, data)
		local id = data and clean(data.id)
		if type(id) == "number" and tooltip and tooltip.AddLine then
			local ok, err = pcall(fn, tooltip, id)
			if not ok and SK.RecordError then SK:RecordError("item tooltip", err) end
		end
	end)
	return true
end

function Compat.ClassColor(classFile)
	local c
	if has("C_ClassColor", "GetClassColor") and classFile then c = C_ClassColor.GetClassColor(classFile) end
	if not c and RAID_CLASS_COLORS and classFile then c = RAID_CLASS_COLORS[classFile] end
	if c then return c.r, c.g, c.b end
	return 0.8, 0.8, 0.8
end

-- Client locale ("enUS" when unknown). Picks the body font in UI/Theme.lua.
function Compat.Locale()
	if has("GetLocale") then
		local ok, l = pcall(GetLocale)
		if ok and type(l) == "string" then return l end
	end
	return "enUS"
end

-- Scale animation from -> to (both uniform). Mainline has SetScaleFrom /
-- SetScaleTo (SimpleAnimScaleAPI, 1.60.1); returns false if missing so the
-- caller can drop the scale part and keep the fade.
function Compat.SetAnimScale(anim, from, to)
	if anim and anim.SetScaleFrom and anim.SetScaleTo then
		anim:SetScaleFrom(from, from)
		anim:SetScaleTo(to, to)
		return true
	end
	return false
end

---------------------------------------------------------------------------
-- Calendar probe for /sr debug.
-- Returns present, numGuildEvents (nil if the call isn't there or fails).
---------------------------------------------------------------------------
function Compat.CalendarStatus()
	if type(C_Calendar) ~= "table" then return false, nil end
	local n
	if has("C_Calendar", "GetNumGuildEvents") then
		local ok, v = pcall(C_Calendar.GetNumGuildEvents)
		if ok then n = clean(v) end
	end
	return true, n
end

---------------------------------------------------------------------------
-- Report for /sr debug: which APIs this client actually has.
---------------------------------------------------------------------------
Compat.PROBES = {
	"C_ChatInfo.SendAddonMessage", "C_ChatInfo.InChatMessagingLockdown",
	"C_ChatInfo.AreOutgoingAddonChatMessagesRestricted",
	"IsTrialAccount", "IsVeteranTrialAccount", "GameLimitedMode_IsActive", "issecretvalue",
	"GetNumGuildMembers", "GetGuildRosterInfo", "GetGuildRosterLastOnline", "C_GuildInfo.GuildRoster",
	"C_Club.GetGuildClubId", "C_Club.GetClubMembers",
	"GetInventoryItemLink", "GetAverageItemLevel",
	"C_Traits.GetConfigInfo", "C_Traits.GetTreeNodes", "C_Traits.GetGroupDisplayInfoByTreeID",
	"C_SpecializationInfo.GetCombatConfigIDForSpecGroup", "C_ClassTalents.GetActiveConfigID",
	"GetNumTalentTabs", "GetTalentTabInfo",
	"GetProfessions", "GetProfessionInfo", "C_SkillInfo.GetSkillLineInfo",
	"C_TradeSkillUI.GetBaseProfessionInfo", "C_TradeSkillUI.GetAllRecipeIDs",
	"C_TradeSkillUI.GetFilteredRecipeIDs", "C_TradeSkillUI.GetRecipeInfo",
	"C_TradeSkillUI.GetRecipeOutputItemData", "C_TradeSkillUI.GetRecipeCooldown",
	"C_TradeSkillUI.IsTradeSkillLinked", "C_TradeSkillUI.IsGuildTradeSkillsEnabled",
	"GetNumTradeSkills", "GetTradeSkillInfo", "GetCraftInfo",
	"C_Reputation.GetFactionDataByIndex", "C_Reputation.GetFactionDataByID", "GetFactionInfo",
	"C_QuestLog.IsQuestFlaggedCompleted", "C_QuestLog.GetTitleForQuestID", "C_Item.GetItemCount",
	"C_Calendar.GetNumDayEvents", "C_Calendar.EventSignUp", "C_Calendar.OpenEvent",
	"C_Calendar.GetNumGuildEvents", "C_Calendar.GetGuildEventInfo", "C_Calendar.EventGetInvite",
	"C_Calendar.AddEvent", "C_PartyInfo.InviteUnit", "C_PartyInfo.ConvertToRaid",
	"C_Item.GetItemIconByID", "C_Item.GetItemInfoInstant", "C_Spell.GetSpellName", "C_Spell.GetSpellCooldown",
	"C_GuildInfo.CanViewOfficerNote",
	-- v0.2 Crafters and tooltips
	"C_Item.GetItemNameByID", "C_Item.RequestLoadItemDataByID", "C_Item.GetItemQualityByID",
	"C_Item.GetItemQualityColor", "C_Item.GetItemInfo", "C_Spell.RequestLoadSpellData",
	"C_Spell.GetSpellTexture", "C_Spell.GetSpellLink",
	"ChatFrameUtil.SendTell", "ChatFrameUtil.OpenChat", "TooltipDataProcessor.AddTooltipPostCall",
	-- v0.2.7 profession probes (for v0.3 Professions)
	"C_TradeSkillUI.GetRecipeSchematic", "C_TradeSkillUI.GetCategoryInfo", "C_TradeSkillUI.GetCategories",
	"C_TradeSkillUI.GetShowLearned", "C_TradeSkillUI.GetShowUnlearned",
	"C_TradeSkillUI.GetProfessionInfoBySkillLineID", "C_SpellBook.IsSpellKnown", "IsPlayerSpell",
	-- v0.3.1 recipe list
	"C_Spell.DoesSpellExist",
	-- v0.4.3 character model
	"ModelSceneMixin.GetPlayerActor", "C_CreatureInfo.GetRaceInfo", "UnitSex",
}

function Compat.ProbeAll()
	local out = {}
	for _, path in ipairs(Compat.PROBES) do
		local ns, fn = path:match("^([^.]+)%.(.+)$")
		out[#out + 1] = { path, ns and has(ns, fn) or has(path) }
	end
	return out
end
