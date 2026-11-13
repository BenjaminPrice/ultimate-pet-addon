local wow = dofile("tests/wowstub.lua")

local function copy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = copy(v) end
  return out
end

local function joined(lines)
  return table.concat(lines, "\n")
end

describe("TOC", function()
  it("targets WoW: Forever and declares the SavedVariables", function()
    local _, meta = wow.readToc("UltimatePet.toc")
    assert.are.equal("16001", meta.Interface)
    assert.are.equal("UltimatePetDB", meta.SavedVariables)
    assert.are.equal("TomTom", meta.OptionalDeps)
  end)

  it("loads Core first and every listed file registers its module", function()
    local files = wow.readToc("UltimatePet.toc")
    assert.are.equal("Core.lua", files[1])
    local UP = wow.load()
    for _, name in ipairs({ "Scanner", "Planner", "Serializer", "Waypoints", "UI",
                            "Families", "Skills", "Beasts", "Presets" }) do
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
      for _, key in ipairs({ "unlocked", "craftCosts", "builds", "petBuild" }) do
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
      assert.are.equal(90, UltimatePetDB.global.minimap.angle)
      assert.is_false(UltimatePetDB.global.minimap.hide)
      assert.is_true(UP.char.unlocked.Bite[3])
      assert.are.equal(123, UP.char.scannedAt)
      assert.is_table(UP.char.craftCosts)
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
      -- A second session loading the saved table changes nothing.
      local snapshot = copy(first)
      UP = wow.load({ saved = first })
      wow.fire("ADDON_LOADED", "UltimatePet")
      assert.are.same(snapshot, UltimatePetDB)
    end)

    it("leaves a newer DB's version alone and warns", function()
      UP = wow.load({ saved = { version = 99 } })
      wow.fire("ADDON_LOADED", "UltimatePet")
      assert.are.equal(99, UltimatePetDB.version)
      assert.matches("newer version", joined(wow.chat))
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

    it("shows help for no or an unknown subcommand", function()
      wow.slash("/upet")
      assert.matches("reset", joined(wow.takeChat()))
      wow.slash("/upet frobnicate")
      assert.matches("unknown command 'frobnicate'", joined(wow.takeChat()))
    end)

    it("reports unimplemented commands", function()
      for _, cmd in ipairs({ "show", "scan", "export", "import abc" }) do
        wow.slash("/upet " .. cmd)
        assert.matches("not implemented yet", joined(wow.takeChat()), nil, true)
      end
    end)

    it("lists APIs in debug, guarded against missing tables", function()
      _G.C_Timer = nil
      _G.GetPetLoyalty = function() end
      wow.slash("/upet debug")
      local out = joined(wow.takeChat())
      assert.matches("GetCraftInfo: missing", out, nil, true)
      assert.matches("C_Timer.After: missing", out, nil, true)
      assert.matches("GetPetLoyalty: function", out, nil, true)
      _G.GetPetLoyalty = nil
      assert.matches("TomTom.AddWaypoint: missing", out, nil, true)
      assert.matches("client 1.60.0", out, nil, true)
    end)

    it("prefixes output", function()
      local raw
      DEFAULT_CHAT_FRAME.AddMessage = function(_, msg) raw = msg end
      UP:Print("hi", 1)
      assert.are.equal("|cffabd473UltimatePet|r: hi 1", raw)
    end)
  end)

  describe("reset", function()
    before_each(function()
      UP = wow.load({ saved = { version = 1, chars = {
        ["Tester-Forever"] = { unlocked = { Bite = { [1] = true } } },
        ["Alt-Forever"] = { unlocked = { Claw = { [1] = true } } },
      } } })
      wow.fire("ADDON_LOADED", "UltimatePet")
      wow.takeChat()
    end)

    it("requires confirm", function()
      wow.slash("/upet reset")
      assert.is_true(UP.char.unlocked.Bite[1])
      assert.matches("reset confirm", joined(wow.takeChat()), nil, true)
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
