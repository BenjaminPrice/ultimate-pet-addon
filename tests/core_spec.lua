local wow = dofile("tests/wowstub.lua")

describe("TOC", function()
  it("targets WoW: Forever and declares the SavedVariables", function()
    local _, meta = wow.readToc("UltimatePet.toc")
    assert.are.equal("16001", meta.Interface)
    assert.are.equal("UltimatePetDB", meta.SavedVariables)
    assert.are.equal("TomTom", meta.OptionalDeps)
  end)

  it("loads the embedded libraries, then Core, and every listed file registers its module", function()
    local files = wow.readToc("UltimatePet.toc")
    assert.are.equal("Libs/embeds.xml", files[1])
    assert.are.equal("Core.lua", files[2])
    local UP = wow.load()
    for _, name in ipairs({ "Scanner", "Planner", "Serializer", "Waypoints", "UI", "PetPanel", "Minimap",
                            "Alerts", "Options", "Families", "Skills", "Beasts", "Presets" }) do
      assert.is_table(UP[name], name)
    end
  end)
end)

describe("Core", function()
  local UP

  before_each(function()
    UP = wow.load()
  end)

  describe("ADDON_LOADED", function()
    it("creates the DB with defaults for this character", function()
      assert.is_nil(UltimatePetDB)
      wow.fire("ADDON_LOADED", "UltimatePet")
      assert.is_table(UltimatePetDB)
      assert.are.equal(UP.DB_VERSION, UltimatePetDB.version)
      assert.is_table(UltimatePetDB.global.minimap)
      assert.is_table(UltimatePetDB.global.frame)
      local char = UltimatePetDB.chars["Tester-Forever"]
      assert.is_table(char)
      for _, key in ipairs({ "unlocked", "builds", "petBuild" }) do
        assert.is_table(char[key], key)
      end
      assert.is_nil(char.scannedAt)
      assert.are.equal(char, UP.char)
      assert.is_true(UP.loaded)
    end)

    it("ignores other addons' ADDON_LOADED", function()
      wow.fire("ADDON_LOADED", "TomTom")
      assert.is_nil(UltimatePetDB)
      assert.is_nil(UP.loaded)
    end)

    it("fires STATE_CHANGED once loaded", function()
      local fired = 0
      UP:On("STATE_CHANGED", function() fired = fired + 1 end)
      wow.fire("ADDON_LOADED", "UltimatePet")
      assert.are.equal(1, fired)
    end)

    it("keeps existing data and other characters", function()
      UP = wow.load({ saved = {
        version = 1,
        global = { minimap = { angle = 90 } },
        chars = {
          ["Tester-Forever"] = { unlocked = { Bite = { [3] = true } }, scannedAt = 123 },
          ["Alt-Forever"] = { builds = { x = {} } },
        },
      } })
      wow.fire("ADDON_LOADED", "UltimatePet")
      assert.are.equal(90, UltimatePetDB.global.minimap.minimapPos)
      assert.is_nil(UltimatePetDB.global.minimap.angle)
      assert.is_false(UltimatePetDB.global.minimap.hide)
      assert.is_true(UP.char.unlocked.Bite[3])
      assert.are.equal(123, UP.char.scannedAt)
      assert.is_table(UltimatePetDB.chars["Alt-Forever"].builds.x)
    end)
  end)

  describe("migration", function()
    it("upgrades an unversioned DB and repairs bad shapes", function()
      UP = wow.load({ saved = { global = "junk", chars = 5 } })
      wow.fire("ADDON_LOADED", "UltimatePet")
      assert.are.equal(UP.DB_VERSION, UltimatePetDB.version)
      assert.is_table(UltimatePetDB.global.minimap)
      assert.is_table(UltimatePetDB.chars["Tester-Forever"].unlocked)
    end)

    it("is idempotent", function()
      wow.fire("ADDON_LOADED", "UltimatePet")
      UP.char.unlocked.Claw = { [2] = true }
      local first = UltimatePetDB
      UP:InitDB()
      UP:InitDB()
      assert.are.equal(first, UltimatePetDB)
      assert.is_true(UltimatePetDB.chars["Tester-Forever"].unlocked.Claw[2])
      local snapshot = wow.copy(first)
      UP = wow.load({ saved = first })
      wow.fire("ADDON_LOADED", "UltimatePet")
      assert.are.same(snapshot, UltimatePetDB)
    end)

    it("drops the unused craftCosts table when migrating to version 3", function()
      UP = wow.load({ saved = { version = 2, chars = { ["Tester-Forever"] = { craftCosts = { Bite = {} } } } } })
      wow.fire("ADDON_LOADED", "UltimatePet")
      assert.is_nil(UP.char.craftCosts)
      assert.are.equal(3, UltimatePetDB.version)
    end)

    it("leaves a newer DB's version alone and warns", function()
      UP = wow.load({ saved = { version = 99 } })
      wow.fire("ADDON_LOADED", "UltimatePet")
      assert.are.equal(99, UltimatePetDB.version)
      assert.matches("newer version", wow.chatText())
    end)
  end)

  describe("SpellText", function()
    local loaded, requested
    before_each(function()
      loaded, requested = {}, {}
      wow.set("C_Spell", {
        GetSpellDescription = function(id) return loaded[id] or "" end,
        RequestLoadSpellData = function(id) requested[#requested + 1] = id end,
      })
    end)
    after_each(function() wow.restore() end)

    it("returns the client's text for a loaded spell", function()
      loaded[17253] = "Bite the enemy, causing 7 to 9 damage."
      assert.are.equal("Bite the enemy, causing 7 to 9 damage.", UP.SpellText(17253))
      assert.is_nil(UP.SpellText(nil))
    end)

    it("requests an unloaded spell once and calls back when it arrives", function()
      local calls = 0
      assert.is_nil(UP.SpellText(17255, function() calls = calls + 10 end))
      assert.is_nil(UP.SpellText(17255, function() calls = calls + 1 end))
      assert.are.same({ 17255 }, requested)
      wow.fire("SPELL_DATA_LOAD_RESULT", 17255, true)
      assert.are.equal(1, calls)
      wow.fire("SPELL_DATA_LOAD_RESULT", 17255, true)
      assert.are.equal(1, calls)
    end)

    it("skips the callback when the load fails", function()
      local called = false
      UP.SpellText(17256, function() called = true end)
      wow.fire("SPELL_DATA_LOAD_RESULT", 17256, false)
      assert.is_false(called)
    end)
  end)

  describe("events", function()
    it("registers game events on the frame but not internal messages", function()
      UP:On("UNIT_PET", function() end)
      UP:On("STATE_CHANGED", function() end)
      assert.is_true(UP.frame:IsEventRegistered("UNIT_PET"))
      assert.is_false(UP.frame:IsEventRegistered("STATE_CHANGED"))
    end)

    it("passes event arguments to every handler", function()
      local got = {}
      UP:On("UNIT_PET", function(unit) got[#got + 1] = "a:" .. unit end)
      UP:On("UNIT_PET", function(unit) got[#got + 1] = "b:" .. unit end)
      wow.fire("UNIT_PET", "player")
      assert.are.same({ "a:player", "b:player" }, got)
    end)

    it("refuses to fire unknown messages", function()
      assert.has_error(function() UP:Fire("NOPE") end)
    end)
  end)

  describe("slash commands", function()
    before_each(function()
      wow.fire("ADDON_LOADED", "UltimatePet")
      wow.takeChat()
    end)

    it("registers /ultimatepet and /upet", function()
      assert.is_true(wow.slash("/ultimatepet help"))
      assert.is_true(wow.slash("/UPET help"))
    end)

    it("routes subcommands, case-insensitively, with arguments", function()
      local got
      UP.commands.import = function(rest) got = rest end
      wow.slash("/upet IMPORT UP1:Cat:60-6:Bi8")
      assert.are.equal("UP1:Cat:60-6:Bi8", got)
    end)

    it("opens the planner for no subcommand and shows help for an unknown one", function()
      local toggled = 0
      UP.UI = { Toggle = function() toggled = toggled + 1 end }
      wow.slash("/upet")
      wow.slash("/upet show")
      assert.are.equal(2, toggled)
      wow.slash("/upet help")
      assert.matches("reset", wow.chatText())
      wow.slash("/upet frobnicate")
      assert.matches("unknown command 'frobnicate'", wow.chatText())
    end)

    it("reports no pet for scan", function()
      wow.slash("/upet scan")
      assert.matches("No pet summoned.", wow.chatText(), nil, true)
    end)

    it("prints the version, client and scanner state in debug", function()
      wow.slash("/upet debug")
      local out = wow.chatText()
      assert.matches("client 1.60.0", out, nil, true)
      assert.matches("pet: none", out, nil, true)
    end)

    it("prefixes output", function()
      local raw
      DEFAULT_CHAT_FRAME.AddMessage = function(_, msg) raw = msg end
      UP:Print("hi", 1)
      assert.are.equal("|cffabd473UltimatePet|r: hi 1", raw)
    end)
  end)

  describe("export and import", function()
    before_each(function()
      wow.fire("ADDON_LOADED", "UltimatePet")
      wow.takeChat()
    end)

    it("exports the Cat Raid DPS preset when nothing is loaded and no pet is out", function()
      wow.slash("/upet export")
      assert.are.same({ "UltimatePet: UP1:Cat:60-6:Bi8,Cl8,Da3,Gr7,GS9,NA7" }, wow.takeChat())
      assert.is_nil(UP.char.currentBuild)
    end)

    it("defaults to the summoned pet's family", function()
      UP = wow.start({ petFamily = "Wolf" })
      wow.slash("/upet export")
      assert.matches("^UltimatePet: UP1:Wolf:60%-6:", wow.takeChat()[1])
    end)

    it("imports a build, stores it per character and exports it back", function()
      local fired = 0
      UP:On("STATE_CHANGED", function() fired = fired + 1 end)
      wow.slash("/upet import up1:Cat:60-6: Bi8,Cl8,Da3,Gr7,GS9,NA7")
      assert.are.same({ "UltimatePet: Imported Cat build (6 skills)." }, wow.takeChat())
      assert.are.equal(1, fired)
      assert.are.equal("Cat", UltimatePetDB.chars["Tester-Forever"].currentBuild.family)
      wow.slash("/upet import UP1:BirdofPrey:20-3:Cl3")
      assert.are.same({ "UltimatePet: Imported Bird of Prey build (1 skill)." }, wow.takeChat())
      wow.slash("/upet export")
      assert.are.same({ "UltimatePet: UP1:BirdofPrey:20-3:Cl3" }, wow.takeChat())
    end)

    it("keeps the current build when an import fails", function()
      wow.slash("/upet import UP1:Cat:60-6:Sw1")
      assert.are.same({ "UltimatePet: Import failed: Cat can't learn Swipe." }, wow.takeChat())
      assert.is_nil(UP.char.currentBuild)
      wow.slash("/upet import")
      assert.matches("usage", wow.takeChat()[1])
    end)

    it("survives a reload", function()
      wow.slash("/upet import UP1:Wolf:60-6:Bi8")
      UP = wow.start({ saved = UltimatePetDB })
      wow.slash("/upet export")
      assert.are.same({ "UltimatePet: UP1:Wolf:60-6:Bi8" }, wow.takeChat())
    end)
  end)

  describe("reset", function()
    before_each(function()
      UP = wow.start({ saved = { version = 1, chars = {
        ["Tester-Forever"] = { unlocked = { Bite = { [1] = true } } },
        ["Alt-Forever"] = { unlocked = { Claw = { [1] = true } } },
      } } })
    end)

    it("requires confirm", function()
      wow.slash("/upet reset")
      assert.is_true(UP.char.unlocked.Bite[1])
      assert.matches("reset confirm", wow.chatText(), nil, true)
    end)

    it("wipes only this character with confirm", function()
      local fired = 0
      UP:On("STATE_CHANGED", function() fired = fired + 1 end)
      wow.slash("/upet reset confirm")
      assert.is_nil(UltimatePetDB.chars["Tester-Forever"].unlocked.Bite)
      assert.is_table(UP.char.builds)
      assert.is_true(UltimatePetDB.chars["Alt-Forever"].unlocked.Claw[1])
      assert.are.equal(1, fired)
    end)

    it("wipes everything with 'all confirm' only", function()
      wow.slash("/upet reset all")
      assert.is_table(UltimatePetDB.chars["Alt-Forever"])
      wow.slash("/upet reset all confirm")
      assert.is_nil(UltimatePetDB.chars["Alt-Forever"])
      assert.is_table(UltimatePetDB.chars["Tester-Forever"].unlocked)
      assert.are.equal(UP.DB_VERSION, UltimatePetDB.version)
    end)
  end)
end)
