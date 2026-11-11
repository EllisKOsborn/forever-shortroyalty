-- v0.4.3: a character model on the Character tab (their gear on your
-- character, or their real look when they're your target / in your group).
local H = require("tests.helpers.load")

local BOB = "Player-1-B"
local SWORD = "|cff0070dd|Hitem:1:::::|h[Sword]|h|r"
local SHIELD = "|cff0070dd|Hitem:2:::::|h[Shield]|h|r"
local HELM = "|cff0070dd|Hitem:3:::::|h[Helm]|h|r"

-- A fake ModelScene + actor that records what was done to it.
local function fakeScene()
	local log = { tryOn = {} }
	local actor = {}
	function actor:SetModelByUnit(unit, _, autoDress, _, _, _, raceID)
		log.unit, log.autoDress, log.raceID = unit, autoDress, raceID
	end
	function actor:Undress() log.undressed = true end
	function actor:TryOn(link, hand) log.tryOn[#log.tryOn + 1] = { link, hand } end
	local scene = { log = log }
	function scene:ReleaseAllActors() end
	function scene:TransitionToModelSceneID(id) log.sceneID = id end
	function scene:GetPlayerActor(_, _, raceFile, gender) log.raceFile, log.gender = raceFile, gender; return actor end
	return scene
end

describe("v0.4.3 character model", function()
	local SK, W
	before_each(function()
		SK, W = H.load()
		W.member("Pip", W.player.guid)
		W.member("Bob", BOB)
		SK.Identity:ReadRoster()
		_G.UnitSex = function() return 3 end
		_G.C_CreatureInfo = { GetRaceInfo = function(id)
			return ({ [1] = { clientFileString = "Human" }, [4] = { clientFileString = "NightElf" },
				[3] = { clientFileString = "Dwarf" } })[id]
		end }
	end)
	after_each(function()
		_G.UnitSex = nil
		_G.ModelSceneMixin = nil
		_G.C_CreatureInfo = nil
	end)

	it("puts their gear on your character, as their race, weapons in the right hands", function()
		local scene = fakeScene()
		local mode, detail = SK.Compat.ShowGearModel(scene, { guid = BOB, raceFile = "Dwarf",
			gear = { [1] = HELM, [16] = SWORD, [17] = SHIELD } })
		assert.equal("dressed", mode)
		assert.equal("race", detail)
		local log = scene.log
		assert.equal(SK.Compat.DRESS_UP_SCENE, log.sceneID)
		assert.equal("player", log.unit)
		assert.is_false(log.autoDress)
		assert.equal(3, log.raceID)
		assert.is_true(log.undressed)
		assert.same({ { HELM, nil }, { SWORD, "MAINHANDSLOT" }, { SHIELD, "SECONDARYHANDSLOT" } }, log.tryOn)
	end)

	it("shows their real look when they're your target", function()
		local real = _G.UnitGUID
		_G.UnitGUID = function(u) if u == "target" then return BOB end return real(u) end
		local scene = fakeScene()
		assert.equal("real", (SK.Compat.ShowGearModel(scene, { guid = BOB, raceFile = "Dwarf", gear = { [1] = HELM } })))
		assert.equal("target", scene.log.unit)
		assert.is_true(scene.log.autoDress)
		assert.equal(0, #scene.log.tryOn)
		_G.UnitGUID = real
	end)

	it("degrades without model support or a race the game doesn't know", function()
		assert.is_nil((SK.Compat.ShowGearModel(nil, {})))
		assert.is_nil(SK.Compat.CreateModelScene({}))
		local mode, detail = SK.Compat.ShowGearModel(fakeScene(), { guid = BOB, raceFile = "Murloc", gear = {} })
		assert.equal("dressed", mode)
		assert.equal("own race", detail)
		local broken = fakeScene()
		broken.GetPlayerActor = function() return 0 end -- what the stub returns
		assert.is_nil((SK.Compat.ShowGearModel(broken, { guid = BOB })))
	end)
end)

describe("v0.4.3 Character tab model", function()
	local SK, W, scene
	before_each(function()
		SK, W = H.load()
		_G.ModelSceneMixin = {}
		_G.UnitSex = function() return 2 end
		scene = nil
		local realCreate = _G.CreateFrame
		_G.CreateFrame = function(kind, ...)
			if kind == "ModelScene" then
				local f = realCreate(kind, ...)
				local fake = fakeScene()
				for k, v in pairs(fake) do f[k] = v end
				scene = f
				return f
			end
			return realCreate(kind, ...)
		end
		H.loadUI(SK)
		W.member("Pip", W.player.guid)
		W.member("Bob", BOB)
		SK.Identity:ReadRoster()
		W.gear[1] = HELM
		SK.Profile:BuildSelf()
		local p = { v = 1, guid = BOB, name = "Bob", class = "WARRIOR", race = "Dwarf", updated = 1, ilvl = 51.5,
			gear = { [1] = HELM, [16] = SWORD } }
		p.hash = SK.Profile.HashOf(p)
		SK.DBM:Guild().profiles[BOB] = p
	end)
	after_each(function()
		_G.ModelSceneMixin = nil
		_G.UnitSex = nil
	end)

	it("shows the model, notes what it is, and doesn't redress for nothing", function()
		SK.CharacterTab:ShowCharacter(BOB)
		local tab = SK.CharacterTab
		assert.truthy(scene)
		assert.is_true(tab.model:IsShown())
		assert.is_false(tab.ilvl:IsShown())
		assert.equal("player", scene.log.unit)
		assert.equal(2, #scene.log.tryOn)
		assert.truthy(tab.modelNote:GetText():find("Item level 51.5", 1, true))
		assert.truthy(tab.modelNote:GetText():find("Their gear", 1, true))
		scene.log.tryOn = {}
		tab:Refresh()
		assert.equal(0, #scene.log.tryOn) -- same gear: not rebuilt
		assert.equal(0, #SK.errors)
	end)

	it("the Model chip switches back to the item level and spec", function()
		SK.CharacterTab:ShowCharacter(BOB)
		local tab = SK.CharacterTab
		tab.modelChip:GetScript("OnClick")(tab.modelChip)
		assert.is_false(SK.DB.settings.charModel)
		assert.is_false(tab.model:IsShown())
		assert.is_true(tab.ilvl:IsShown())
	end)

	it("no model when the player hides their gear", function()
		local p = SK.DBM:Guild().profiles[BOB]
		p.gear, p.hidden = nil, { gear = true }
		p.hash = SK.Profile.HashOf(p)
		SK.CharacterTab:ShowCharacter(BOB)
		assert.is_false(SK.CharacterTab.model:IsShown())
	end)

	it("says what you're looking at", function()
		local N = SK.CharacterTab.ModelNote
		assert.equal("Their own look", N("real"))
		assert.equal("Their gear and race", N("dressed", "race"))
		assert.equal("Item level 51.5\nTheir gear on you", N("dressed", "own race", 51.5))
		assert.equal("No model here", N(nil))
	end)

	it("your own character is your real look", function()
		SK.CharacterTab:ShowCharacter(nil)
		assert.equal("player", scene.log.unit)
		assert.is_true(scene.log.autoDress)
		assert.truthy(SK.CharacterTab.modelNote:GetText():find("Their own look", 1, true))
	end)
end)
