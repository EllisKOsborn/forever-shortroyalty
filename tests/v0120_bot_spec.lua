-- v0.12.0: the code for Short Royalty's own Discord bot (raid ··· menu,
-- "Post with the Discord bot"), read by discord-bot/src/code.js, and the
-- bot's "Copy for the addon" list read by the existing import.
local H = require("tests.helpers.load")

local CAT, DAN, EVE = "Player-1-C", "Player-1-D", "Player-1-E"

describe("v0.12.0 Discord bot code", function()
	local SK, W, B, e
	before_each(function()
		SK, W = H.load()
		W.member("Pip Hocus", W.player.guid, { rank = "Officer", rankIndex = 1 })
		W.member("Cat Fern", CAT, { rank = "Member", rankIndex = 4, class = "PRIEST" })
		W.member("Dan Moss", DAN, { rank = "Member", rankIndex = 4, class = "MAGE" })
		W.member("Eve Moss", EVE, { rank = "Member", rankIndex = 4, class = "ROGUE" })
		SK.Identity:ReadRoster()
		SK.Profile:BuildSelf()
		B = SK.RaidBoard
		e = B:Create("ony", W.now + 3600)
		B:Get().signups[e.id] = { [CAT] = { s = "y", r = "HEALER", u = W.now - 5 }, [DAN] = { s = "n", r = "DPS", u = W.now - 9 },
			[EVE] = { s = "t", u = W.now - 2 } }
		assert.is_true(B:SetPlace(e.id, CAT, "i"))
	end)

	local function lines(text)
		local out = {}
		for l in text:gmatch("[^\n]+") do out[#out + 1] = l end
		return out
	end

	it("gives the bot's header and one line per sign-up, split by semicolons", function()
		local rows = B.LineUp(B:Get(), e, B.Ctx())
		local L = lines(B.BotCode(e, rows, B:Get().signups[e.id], W.now))
		assert.truthy(L[1]:find("/raid-post", 1, true))
		assert.equal(string.format("SR1;%s;ony;Onyxia's Lair;40;%d;%d", e.id, e.at, W.now), L[2])
		local by = {}
		for i = 3, #L do
			local n, s, r, p, u = L[i]:match("^([^;]+);([ytn]);(%u*);([ib]?);(%d+)$")
			assert.truthy(n, L[i])
			by[n] = { s = s, r = r, p = p, u = tonumber(u) }
		end
		assert.same({ s = "y", r = "HEALER", p = "i", u = W.now - 5 }, by["Cat Fern"])
		assert.same({ s = "n", r = "DPS", p = "", u = W.now - 9 }, by["Dan Moss"])
		assert.equal("t", by["Eve Moss"].s)
		assert.is_nil(L[#L]:find("|", 1, true))
	end)

	it("strips separators and colour codes from names", function()
		local code = B.BotCode(e, { { guid = CAT, name = "Cat;Fern|r", status = "y" } }, {}, W.now)
		assert.equal("CatFernr;y;;;0", lines(code)[3])
	end)

	it("reads the bot's Copy for the addon list", function()
		local members = {}
		for guid, m in pairs(SK.DBM:Guild().members) do members[guid] = { name = m.name } end
		local r = B.ParseImport("Onyxia's Lair sign-ups from Discord\nCat Fern signed up healer\n" ..
			"Dan Moss cant come dps\nEve Moss tentative", members)
		assert.equal(3, #r.entries)
		local by = {}
		for _, x in ipairs(r.entries) do by[x.guid] = x end
		assert.same({ guid = CAT, s = "y", r = "HEALER" }, by[CAT])
		assert.same({ guid = DAN, s = "n", r = "DPS" }, by[DAN])
		assert.equal("t", by[EVE].s)
		assert.equal(1, #r.unmatched) -- the title line
	end)

	it("officers get Post with the Discord bot in the raid's menu", function()
		H.loadUI(SK)
		SK.DB.officer[W.player.guid] = true
		SK.MainFrame:Open("raids")
		local RT = SK.RaidsTab
		RT.selected = e.id
		local names = {}
		for _, it in ipairs(RT:DetailOptions()) do names[it.text] = it end
		assert.truthy(names["Post with the Discord bot"])
		names["Post with the Discord bot"].onClick()
		assert.truthy(SK.DebugWindow.text:find("SR1;" .. e.id, 1, true))
		assert.equal(0, #SK.errors)
	end)
end)
