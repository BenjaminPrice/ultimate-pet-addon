local wow = dofile("tests/wowstub.lua")

-- Game APIs the scanner reads that tests/wowstub.lua does not provide. Installed per test through
-- set() and restored afterwards, so other specs see the stub's plain client.
local saved = {}
local function set(name, value)
  if not saved[name] then saved[name] = { value = rawget(_G, name) } end
  _G[name] = value
end
local function restore()
  for name, old in pairs(saved) do _G[name] = old.value end
  saved = {}
end

local function spell(UP, skill, rank)
  return UP.Skills[skill].ranks[rank].spellId
end

local function link(id)
  return "|cff71d5ff|Hspell:" .. id .. "|h[x]|h|r"
end

-- A fake trainer window. services: { name, status, link, tooltipId, level, costs, rank }.
-- opts.table: GetTrainerServiceInfo returns a table; opts.cTrainer: only C_Trainer.* exists.
local function trainer(services, opts)
  opts = opts or {}
  local api = {
    GetNumTrainerServices = function() return #services end,
    GetTrainerServiceInfo = function(i)
      local s = services[i]
      if opts.table then return { name = s.name, type = s.status, subText = s.rank } end
      if s.rank then return s.name, s.rank, s.status end
      return s.name, s.status
    end,
    GetTrainerServiceItemLink = function(i) return services[i].link end,
    GetTrainerServiceCost = function(i)
      local c = services[i].costs or { 0 }
      return unpack(c, 1, c.n or #c)
    end,
    GetTrainerServiceLevelReq = function(i) return services[i].level end,
  }
  if opts.cTrainer then
    set("C_Trainer", api)
  else
    for name, fn in pairs(api) do set(name, fn) end
    set("C_Trainer", {})
  end
  set("C_TooltipInfo", {
    GetTrainerService = function(i)
      local id = services[i].tooltipId
      return id and { id = id } or nil
    end,
  })
end

-- No npc unit: Beast Training. kind = "beast" (npc with a family) or "trainer" (humanoid npc).
local function npc(kind)
  set("UnitExists", function(unit)
    if unit == "npc" then return kind ~= nil end
    if unit == "pet" then return _G.__petExists == true end
    return unit == "player"
  end)
  set("UnitCreatureFamily", function(unit)
    if unit == "npc" and kind == "beast" then return "Cat", 2 end
    if unit == "pet" and _G.__petFamily then return unpack(_G.__petFamily) end
  end)
  set("UnitCreatureType", function(unit)
    if unit == "npc" then return kind == "beast" and "Beast" or "Humanoid" end
  end)
end

-- The verified Forever pet: L10 Rebellious Wolf, TP 0 total / 4 used, petNumber 7.
local function forPet(book, overrides)
  overrides = overrides or {}
  set("__petExists", true)
  set("__petFamily", overrides.family or { "Wolf", 1 })
  if not rawget(_G, "UnitExists") then npc(nil) end -- wowstub installs UnitCreatureFamily but not UnitExists
  local baseName = UnitName
  set("UnitName", function(unit)
    if unit == "pet" then return "Fang" end
    return baseName(unit)
  end)
  set("UnitLevel", function(unit) if unit == "pet" then return overrides.level or 10 end end)
  set("UnitGUID", function(unit) if unit == "pet" then return "Pet-0-1-2-3-4-0000ABCD" end end)
  set("C_PetInfo", {
    GetPetTrainingPoints = function() return overrides.total or 0, overrides.used or 4 end,
    GetPetLoyalty = function()
      if overrides.loyalty == false then return nil end
      return overrides.loyalty or "Rebellious"
    end,
  })
  set("C_StableInfo", {
    GetActivePetList = function() return { { name = "Other", petNumber = 3 }, { name = "Fang", petNumber = 7 } } end,
  })
  set("Enum", { SpellBookSpellBank = { Player = 0, Pet = 1 } })
  set("C_SpellBook", {
    HasPetSpells = function() return #book, "PET" end,
    GetSpellBookItemInfo = function(i, bank)
      assert(bank == 1, "pet bank")
      return book[i]
    end,
  })
end

describe("Scanner", function()
  local UP, changes

  before_each(function()
    UP = wow.load()
    wow.fire("ADDON_LOADED", "UltimatePet")
    wow.takeChat()
    changes = 0
    UP:On("STATE_CHANGED", function() changes = changes + 1 end)
    set("time", function() return 1234 end)
  end)

  after_each(restore)

  describe("Beast Training", function()
    local function window(U)
      return {
        { name = "Pet Abilities", status = "header" },
        { name = "Bite", status = "used", link = link(spell(U, "Bite", 2)), level = 8, costs = { 0, 4, n = 2 } },
        { name = "Bite", status = "available", link = link(spell(U, "Bite", 3)), level = 16, costs = { 0, 7 } },
        { name = "Great Stamina", status = "unavailable", link = link(spell(U, "Great Stamina", 4)), level = 24 },
        -- no link: the spell id comes from the tooltip
        { name = "Dash", status = "used", tooltipId = spell(U, "Dash", 1), level = 30 },
        -- a hunter class skill, not a pet ability
        { name = "Arcane Shot", status = "used", link = link(14281), level = 6 },
      }
    end

    it("records every listed pet rank, its costs and the scan time", function()
      npc(nil)
      trainer(window(UP))
      wow.fire("TRAINER_SHOW")
      local unlocked = UP.char.unlocked
      assert.is_true(unlocked.Bite[2])
      assert.is_true(unlocked.Bite[3])
      assert.is_true(unlocked["Great Stamina"][4])
      assert.is_true(unlocked.Dash[1])
      assert.is_nil(unlocked["Arcane Shot"])
      assert.are.equal(1234, UP.char.scannedAt)
      assert.are.same({ level = 8, costs = { 0, 4, n = 2 } }, UP.char.craftCosts.Bite[2])
      assert.are.equal(30, UP.char.craftCosts.Dash[1].level)
      assert.are.equal(1, changes)
      assert.is_true(UP.Scanner:HasScanned())
      assert.is_true(UP.Scanner:IsUnlocked("Bite", 3))
      assert.is_false(UP.Scanner:IsUnlocked("Bite", 4))
      assert.is_false(UP.Scanner:IsUnlocked("Nope", 1))
    end)

    it("prints the sync line once per session", function()
      npc(nil)
      trainer(window(UP))
      wow.fire("TRAINER_SHOW")
      wow.fire("TRAINER_UPDATE")
      assert.are.same({ "UltimatePet: Beast Training synced: 4 ranks known." }, wow.takeChat())
      assert.are.equal(2, changes)
    end)

    it("treats an npc with a creature family as Beast Training", function()
      npc("beast")
      trainer(window(UP))
      wow.fire("TRAINER_SHOW")
      assert.is_true(UP.Scanner:IsUnlocked("Bite", 3))
    end)

    it("counts only 'used' entries at a real pet trainer", function()
      npc("trainer")
      trainer(window(UP))
      wow.fire("TRAINER_SHOW")
      assert.is_true(UP.Scanner:IsUnlocked("Bite", 2))
      assert.is_true(UP.Scanner:IsUnlocked("Dash", 1))
      assert.is_false(UP.Scanner:IsUnlocked("Bite", 3))
      assert.is_false(UP.Scanner:IsUnlocked("Great Stamina", 4))
      -- costs are still recorded for ranks not yet learned
      assert.are.equal(16, UP.char.craftCosts.Bite[3].level)
    end)

    it("only ever grows the unlocked set", function()
      npc(nil)
      trainer(window(UP))
      wow.fire("TRAINER_SHOW")
      trainer({ { name = "Growl", status = "used", link = link(spell(UP, "Growl", 1)) } })
      wow.fire("TRAINER_UPDATE")
      assert.is_true(UP.Scanner:IsUnlocked("Bite", 3))
      assert.is_true(UP.Scanner:IsUnlocked("Growl", 1))
    end)

    it("reads a table-returning GetTrainerServiceInfo through C_Trainer", function()
      npc(nil)
      trainer({
        { name = "Header", status = "header" },
        { name = "Claw", status = "used", link = link(spell(UP, "Claw", 5)) },
      }, { table = true, cTrainer = true })
      assert.is_nil(rawget(_G, "GetNumTrainerServices"))
      wow.fire("TRAINER_SHOW")
      assert.is_true(UP.Scanner:IsUnlocked("Claw", 5))
    end)

    it("falls back to the English name and rank text without a spell id", function()
      npc(nil)
      trainer({
        { name = "Growl", rank = "Rank 2", status = "used" },
        { name = "Bite", status = "used" }, -- multi-rank skill without a rank: skipped
        { name = "Shell Shield", status = "used" }, -- single rank
      })
      wow.fire("TRAINER_SHOW")
      assert.is_true(UP.Scanner:IsUnlocked("Growl", 2))
      assert.is_nil(UP.char.unlocked.Bite)
      assert.is_true(UP.Scanner:IsUnlocked("Shell Shield", 1))
    end)

    it("saves nothing from a trainer with no pet abilities", function()
      npc("trainer")
      trainer({ { name = "Arcane Shot", status = "used", link = link(14281) } })
      wow.fire("TRAINER_SHOW")
      assert.is_nil(UP.char.scannedAt)
      assert.are.same({}, UP.char.unlocked)
      assert.are.equal(0, changes)
      assert.are.same({}, wow.takeChat())
      local dump = table.concat(UP.Scanner:DebugDump(), "\n")
      assert.matches("0 pet ranks matched", dump, 1, true)
      assert.matches("Arcane Shot #14281", dump, 1, true)
    end)
  end)

  describe("active pet", function()
    local function book(U)
      return {
        { name = "Attack", actionID = 0 }, -- a command, not a spell
        { name = "Bite", spellID = spell(U, "Bite", 1) },
        { name = "Bite", spellID = spell(U, "Bite", 2) },
        { name = "Growl", actionID = spell(U, "Growl", 1) },
        { name = "Great Stamina", spellID = spell(U, "Great Stamina", 1) },
        { name = "Great Stamina", spellID = spell(U, "Great Stamina", 2) },
        { name = "Natural Armor", spellID = spell(U, "Natural Armor", 1) },
      }
    end

    it("reads the verified Forever values", function()
      forPet(book(UP))
      local pet = UP.Scanner:ReadPet()
      assert.is_true(pet.exists)
      assert.are.equal("Fang", pet.name)
      assert.are.equal("Wolf", pet.family)
      assert.are.equal(1, pet.familyId)
      assert.are.equal(10, pet.level)
      assert.are.equal(0, pet.tpTotal)
      assert.are.equal(4, pet.tpUsed)
      assert.are.equal(-4, pet.unspent)
      assert.are.equal(1, pet.loyalty)
      assert.are.equal("Rebellious", pet.loyaltyName)
      assert.are.equal(7, pet.key)
      assert.are.same({ Bite = 2, Growl = 1, ["Great Stamina"] = 2, ["Natural Armor"] = 1 }, pet.known)
      assert.are.equal(1, changes)
    end)

    it("derives loyalty from the text or the training points", function()
      forPet({}, { loyalty = "Loyalty Level 4" })
      assert.are.equal(4, UP.Scanner:ReadPet().loyalty)
      forPet({}, { loyalty = "BEST FRIEND" })
      assert.are.equal(6, UP.Scanner:ReadPet().loyalty)
      forPet({}, { loyalty = false, total = 20, used = 0 })
      assert.are.equal(3, UP.Scanner:ReadPet().loyalty)
      forPet({}, { loyalty = "???", total = 7, used = 0 })
      assert.is_nil(UP.Scanner:ReadPet().loyalty)
    end)

    it("maps a family it doesn't know by id, and keeps an unknown one", function()
      forPet({ { name = "Claw", spellID = spell(UP, "Claw", 3) } }, { family = { "Loup", 1 } })
      local pet = UP.Scanner:ReadPet()
      assert.are.equal("Wolf", pet.family)
      -- a skill outside the family is still what the pet has
      assert.are.same({ Claw = 3 }, pet.known)

      forPet({}, { family = { "Wyvern", 99 } })
      pet = UP.Scanner:ReadPet()
      assert.are.equal("Wyvern", pet.family)
      assert.is_false(pet.familyKnown)
      assert.matches("unknown family", UP.Scanner:DebugDump()[1], 1, true)
    end)

    it("uses the GUID when the stable list has no entry", function()
      forPet({})
      set("C_StableInfo", nil)
      assert.are.equal("Pet-0-1-2-3-4-0000ABCD", UP.Scanner:ReadPet().key)
    end)

    it("reports no pet and fires only when the state changes", function()
      forPet(book(UP))
      UP.Scanner:ReadPet()
      UP.Scanner:ReadPet()
      assert.are.equal(1, changes)
      set("__petExists", false)
      local pet = UP.Scanner:ReadPet()
      assert.is_false(pet.exists)
      assert.are.equal(2, changes)
      assert.are.equal("pet: none", UP.Scanner:DebugDump()[1])
    end)

    it("coalesces bursts of pet events into one read", function()
      local queue = {}
      set("C_Timer", { After = function(delay, fn) queue[#queue + 1] = { delay, fn } end })
      forPet(book(UP))
      wow.fire("UNIT_PET", "player")
      wow.fire("PET_BAR_UPDATE")
      wow.fire("UNIT_LEVEL", "pet")
      wow.fire("SPELLS_CHANGED")
      wow.fire("UNIT_PET_TRAINING_POINTS", "player")
      assert.are.equal(1, #queue)
      assert.are.equal(0.2, queue[1][1])
      assert.is_false(UP.Scanner.pet.exists)
      queue[1][2]()
      assert.is_true(UP.Scanner.pet.exists)
      assert.are.equal(1, changes)
      wow.fire("PET_UI_UPDATE")
      assert.are.equal(2, #queue)
    end)

    it("ignores UNIT_PET and UNIT_LEVEL for other units", function()
      local queue = {}
      set("C_Timer", { After = function(_, fn) queue[#queue + 1] = fn end })
      wow.fire("UNIT_PET", "party1")
      wow.fire("UNIT_LEVEL", "player")
      assert.are.equal(0, #queue)
    end)

    it("reads at once without C_Timer", function()
      set("C_Timer", nil)
      forPet(book(UP))
      wow.fire("PET_BAR_UPDATE")
      assert.is_true(UP.Scanner.pet.exists)
    end)
  end)

  describe("Context", function()
    it("has the planner's shape", function()
      npc(nil)
      trainer({ { name = "Bite", status = "used", link = link(spell(UP, "Bite", 4)) } })
      wow.fire("TRAINER_SHOW")
      forPet({ { spellID = spell(UP, "Bite", 3) } })
      UP.Scanner:ReadPet()
      local ctx = UP.Scanner:Context()
      assert.are.same({
        hasPet = true, petLevel = 10, petFamily = "Wolf", unspent = -4, loyalty = 1,
        known = { Bite = 3 }, unlocked = { Bite = { [4] = true } },
      }, ctx)
      ctx.known.Bite = 99
      assert.are.equal(3, UP.Scanner.pet.known.Bite)
    end)

    it("has safe defaults without a pet or a DB", function()
      local fresh = wow.load()
      local ctx = fresh.Scanner:Context()
      assert.are.same({ hasPet = false, petLevel = 0, unspent = 0, known = {}, unlocked = {} }, ctx)
      assert.is_false(fresh.Scanner:HasScanned())
      assert.is_false(fresh.Scanner:IsUnlocked("Bite", 1))
    end)
  end)

  describe("first-run nag", function()
    local function hunter(class)
      set("UnitClass", function(unit) if unit == "player" then return "Hunter", class end end)
    end

    it("asks a hunter who has never scanned, once per session", function()
      hunter("HUNTER")
      wow.fire("PLAYER_ENTERING_WORLD")
      wow.fire("PLAYER_ENTERING_WORLD")
      assert.are.same({
        "UltimatePet: Open your Beast Training window once so UltimatePet can see which ranks you know.",
      }, wow.takeChat())
    end)

    it("stays quiet for other classes and after a scan", function()
      hunter("MAGE")
      wow.fire("PLAYER_ENTERING_WORLD")
      hunter("HUNTER")
      UP.char.scannedAt = 1
      wow.fire("PLAYER_ENTERING_WORLD")
      assert.are.same({}, wow.takeChat())
    end)
  end)

  describe("without the game APIs", function()
    it("never errors", function()
      for _, event in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE", "UNIT_PET", "PET_BAR_UPDATE", "UNIT_LEVEL",
                               "PLAYER_ENTERING_WORLD", "PET_UI_UPDATE", "UNIT_PET_TRAINING_POINTS",
                               "PET_TRAINING_POINTS", "SPELLS_CHANGED" }) do
        wow.fire(event, "player")
        wow.fire(event, "pet")
      end
      assert.is_table(UP.Scanner:ReadPet())
      assert.are.equal(0, UP.Scanner:ScanTrainer())
      assert.is_table(UP.Scanner:Context())
      assert.is_table(UP.Scanner:DebugDump())
    end)

    it("survives APIs that throw", function()
      local boom = function() error("boom") end
      set("GetNumTrainerServices", function() return 2 end)
      set("GetTrainerServiceInfo", boom)
      set("UnitExists", function() return true end)
      set("UnitCreatureFamily", boom)
      set("C_PetInfo", { GetPetTrainingPoints = boom, GetPetLoyalty = boom })
      set("C_SpellBook", { HasPetSpells = boom })
      wow.fire("TRAINER_SHOW")
      local pet = UP.Scanner:ReadPet()
      assert.is_true(pet.exists)
      assert.is_nil(pet.unspent)
      assert.are.same({}, pet.known)
      assert.is_table(UP.Scanner:DebugDump())
    end)

    it("registers every event it listens to", function()
      local f = UP.frame
      for _, event in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE", "UNIT_PET", "PET_BAR_UPDATE", "UNIT_LEVEL",
                               "PLAYER_ENTERING_WORLD", "PET_UI_UPDATE", "UNIT_PET_TRAINING_POINTS",
                               "SPELLS_CHANGED" }) do
        assert.is_true(f:IsEventRegistered(event), event)
      end
    end)
  end)
end)
