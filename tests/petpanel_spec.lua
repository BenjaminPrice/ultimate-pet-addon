local wow = dofile("tests/wowstub.lua")
local stub = dofile("tests/uistub.lua")
local plain = stub.plain

-- The verified Forever pet: L10 Rebellious Wolf 'Fang', 0 TP total / 4 used, petNumber 7.
local FANG = {
  exists = true, name = "Fang", family = "Wolf", familyId = 1, familyKnown = true, level = 10,
  loyalty = 1, loyaltyName = "Rebellious", tpTotal = 0, tpUsed = 4, unspent = -4,
  known = { Bite = 2, Growl = 1, ["Great Stamina"] = 1, ["Natural Armor"] = 1 }, key = 7,
}

local BLIZZARD = { "PetPaperDollFrame", "CharacterFrame", "UltimatePetPetPanel" }

local function copy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = copy(v) end
  return out
end

local function hex(c)
  local function byte(v) return math.floor(v * 255 + 0.5) end
  return ("|cff%02x%02x%02x"):format(byte(c[1]), byte(c[2]), byte(c[3]))
end

describe("PetPanel", function()
  local UP, PetPanel, C

  local function setPet(p)
    UP.Scanner.pet = p and copy(p) or { exists = false, known = {} }
    UP:Fire("STATE_CHANGED")
  end

  -- A stand-in Blizzard frame, hidden, that records HookScript calls.
  local function blizzardFrame(name)
    local f = CreateFrame("Frame", name, rawget(_G, "UIParent"))
    f:Hide()
    f.hooks = {}
    local hook = f.HookScript
    function f:HookScript(script, fn)
      self.hooks[#self.hooks + 1] = script
      return hook(self, script, fn)
    end
    return f
  end

  local function texts(m)
    local out = {}
    for _, line in ipairs(m.lines) do out[#out + 1] = plain(line.text) end
    return out
  end

  local function rows(m)
    local out = {}
    for _, r in ipairs(m.rows) do
      out[#out + 1] = r.header and ("# " .. r.header) or (r.name .. " = " .. r.rankText)
    end
    return out
  end

  local function rowFor(m, skill)
    for _, r in ipairs(m.rows) do
      if r.skill == skill then return r end
    end
  end

  before_each(function()
    UP = wow.load()
    stub.install()
    wow.fire("ADDON_LOADED", "UltimatePet")
    PetPanel, C = UP.PetPanel, UP.UI.COLORS
    wow.takeChat()
  end)

  after_each(function()
    stub.uninstall()
    for _, name in ipairs(BLIZZARD) do rawset(_G, name, nil) end
  end)

  describe("Model", function()
    it("says no pet is summoned", function()
      local m = PetPanel.Model({ exists = false, known = {} })
      assert.is_false(m.hasPet)
      assert.are.same({ "No pet summoned." }, texts(m))
      assert.are.same({}, m.rows)
      assert.is_false(m.canUse)
    end)

    it("shows the Forever pet with negative free TP in orange and its known ranks", function()
      local m = PetPanel.Model(FANG, nil)
      assert.is_true(m.hasPet)
      assert.is_true(m.canUse)
      assert.are.same({
        "Fang - Wolf, level 10",
        "Rebellious  \194\183  TP -4 / 0 free",
        "Build: none (set one in the planner)",
      }, texts(m))
      assert.are.same(C.NEED, m.freeColor)
      assert.truthy(m.lines[2].text:find(hex(C.NEED) .. "-4|r", 1, true))
      assert.are.same({
        "Bite = Rank 2", "Growl = Rank 1", "# Passives", "Great Stamina = Rank 1", "Natural Armor = Rank 1",
      }, rows(m))
      local bite = rowFor(m, "Bite")
      assert.are.same(C.WHITE, bite.color)
      assert.are.equal(100000 + UP.Skills.Bite.ranks[2].spellId, bite.icon)
    end)

    it("shows unknown TP and a loyalty level without a name", function()
      local p = copy(FANG)
      p.tpTotal, p.unspent, p.loyaltyName, p.loyalty = nil, nil, nil, 3
      assert.are.equal("Submissive  \194\183  TP unknown", texts(PetPanel.Model(p))[2])
    end)

    it("compares known ranks with an assigned preset's targets", function()
      UP.char.petBuild[7] = "Raid DPS"
      local build = PetPanel.ActiveBuild(FANG)
      assert.are.equal("Raid DPS", build.name)
      local m = PetPanel.Model(FANG, build)
      assert.are.equal("Build: Raid DPS", texts(m)[3])
      assert.are.same({
        "Bite = 2 / 8", "Dash = - / 3", "Growl = 1 / 7", "Furious Howl = - / 4",
        "# Passives", "Great Stamina = 1 / 9", "Natural Armor = 1 / 7",
      }, rows(m))
      local ctx = { family = "Wolf", petFamily = "Wolf", petLevel = 10, unspent = -4, known = FANG.known,
        unlocked = UP.char.unlocked }
      for _, skill in ipairs({ "Bite", "Dash", "Growl", "Furious Howl", "Great Stamina", "Natural Armor" }) do
        local r = rowFor(m, skill)
        local st = UP.Planner.Status(skill, build.skills[skill], ctx)
        assert.are.same(UP.UI.StatusColor(st.code), r.color, skill)
      end
      assert.are.same(C.LOCKED, rowFor(m, "Bite").color)
      assert.are.same(C.GREY, rowFor(m, "Dash").nameColor)
    end)

    it("uses a saved build: trained targets green, untracked known ranks grey", function()
      UP.char.builds.Mine = { family = "Wolf", level = 60, loyalty = 6, skills = { Bite = 2, Dash = 1 } }
      UP.char.petBuild[7] = "Mine"
      local m = PetPanel.Model(FANG, PetPanel.ActiveBuild(FANG))
      assert.are.equal("Build: Mine", texts(m)[3])
      assert.are.same(C.TRAINED, rowFor(m, "Bite").color)
      assert.are.equal("2 / 2", rowFor(m, "Bite").rankText)
      assert.are.equal("- / 1", rowFor(m, "Dash").rankText)
      assert.are.equal("1", rowFor(m, "Growl").rankText)
      assert.are.same(C.GREY, rowFor(m, "Growl").color)
    end)

    it("ignores an assignment naming nothing this family has", function()
      UP.char.builds.Kitty = { family = "Cat", skills = { Bite = 1 } }
      UP.char.petBuild[7] = "Kitty"
      assert.is_nil(PetPanel.ActiveBuild(FANG))
      UP.char.petBuild[7] = "Nope"
      assert.is_nil(PetPanel.ActiveBuild(FANG))
    end)
  end)

  describe("attached to the Pet tab", function()
    it("hooks PetPaperDollFrame on login and shows and hides with it, beside CharacterFrame", function()
      local character = blizzardFrame("CharacterFrame")
      local petTab = blizzardFrame("PetPaperDollFrame")
      setPet(FANG)
      wow.fire("PLAYER_LOGIN")
      assert.are.same({ "OnShow", "OnHide" }, petTab.hooks)
      assert.is_false(PetPanel:IsShown())

      petTab:Show()
      local f = rawget(_G, "UltimatePetPetPanel")
      assert.is_true(f:IsShown())
      assert.are.equal("attached", PetPanel.mode)
      assert.are.same({ "TOPLEFT", character, "TOPRIGHT", -32, -14 }, f.points[1])
      assert.are.equal("Fang - Wolf, level 10", plain(f.lines[1].text))
      assert.is_false(f.close:IsShown())

      -- Refreshes on STATE_CHANGED while shown.
      local p = copy(FANG)
      p.level = 11
      setPet(p)
      assert.are.equal("Fang - Wolf, level 11", plain(f.lines[1].text))

      -- /upet pet while the tab is open only refreshes.
      wow.slash("/upet pet")
      assert.is_true(f:IsShown())
      assert.are.equal("attached", PetPanel.mode)

      petTab:Hide()
      assert.is_false(f:IsShown())

      -- Hooks only once.
      wow.fire("PLAYER_LOGIN")
      assert.are.equal(2, #petTab.hooks)
    end)

    it("anchors to PetPaperDollFrame without CharacterFrame", function()
      local petTab = blizzardFrame("PetPaperDollFrame")
      wow.fire("PLAYER_LOGIN")
      petTab:Show()
      local f = rawget(_G, "UltimatePetPetPanel")
      assert.are.equal(petTab, f.points[1][2])
      assert.are.equal("No pet summoned.", plain(f.lines[1].text))
    end)

    it("doesn't error without PetPaperDollFrame or CharacterFrame", function()
      assert.has_no.errors(function() wow.fire("PLAYER_LOGIN") end)
      assert.is_false(PetPanel:Hook())
      assert.has_no.errors(function() wow.slash("/upet pet") end)
      assert.is_true(PetPanel:IsShown())
      assert.are.equal("floating", PetPanel.mode)
    end)
  end)

  describe("floating", function()
    it("toggles with /upet pet, closes with Escape and remembers its position", function()
      setPet(FANG)
      wow.slash("/upet pet")
      local f = rawget(_G, "UltimatePetPetPanel")
      assert.is_true(f:IsShown())
      assert.are.equal("floating", PetPanel.mode)
      assert.is_true(f.close:IsShown())
      assert.are.equal("CENTER", f.points[1][1])
      local found = false
      for _, name in ipairs(rawget(_G, "UISpecialFrames")) do
        if name == "UltimatePetPetPanel" then found = true end
      end
      assert.is_true(found)

      f:ClearAllPoints()
      f:SetPoint("TOPLEFT", rawget(_G, "UIParent"), "TOPLEFT", 50, -60)
      stub.fire(f, "OnDragStop")
      assert.are.same({ point = "TOPLEFT", relativePoint = "TOPLEFT", x = 50, y = -60 }, UP.db.global.petPanel)

      wow.slash("/upet pet")
      assert.is_false(f:IsShown())
      wow.slash("/upet pet")
      assert.are.same({ "TOPLEFT", rawget(_G, "UIParent"), "TOPLEFT", 50, -60 }, f.points[1])
    end)

    it("sizes to its rows", function()
      setPet(FANG)
      wow.slash("/upet pet")
      local f = rawget(_G, "UltimatePetPetPanel")
      local shown = 0
      for _, r in ipairs(f.rows) do if r:IsShown() then shown = shown + 1 end end
      assert.are.equal(5, shown)
      local tall = f:GetHeight()
      setPet(nil)
      shown = 0
      for _, r in ipairs(f.rows) do if r:IsShown() then shown = shown + 1 end end
      assert.are.equal(0, shown)
      assert.is_true(f:GetHeight() < tall)
    end)
  end)

  describe("button", function()
    it("opens the planner using the current pet", function()
      setPet(FANG)
      wow.slash("/upet pet")
      rawget(_G, "UltimatePetPetPanel").button:Click()
      assert.is_true(UP.char.useCurrentPet)
      assert.is_true(UP.UI.frame:IsShown())
    end)

    it("opens the planner without a pet", function()
      wow.slash("/upet pet")
      rawget(_G, "UltimatePetPetPanel").button:Click()
      assert.is_falsy(UP.char.useCurrentPet)
      assert.is_true(UP.UI.frame:IsShown())
    end)
  end)
end)
