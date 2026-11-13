-- luacheck: globals C_Spell
local wow = dofile("tests/wowstub.lua")
local stub = dofile("tests/uistub.lua")

-- German client names, so English matching can't pass by accident.
local CLIENT_NAMES = { [16827] = "Klaue", [17253] = "Biss" }

describe("Alerts", function()
  local UP, Alerts, sounds, changes

  local function load(opts)
    opts = opts or {}
    UP = wow.load()
    stub.install()
    wow.set("ERR_LEARN_ABILITY_S", opts.format or "You have learned a new ability: %s.")
    wow.set("ERR_LEARN_SPELL_S", "You have learned a new spell: %s.")
    C_Spell.GetSpellName = function(id) return CLIENT_NAMES[id] end
    sounds = {}
    wow.set("PlaySound", function(id, channel) sounds[#sounds + 1] = { id, channel } end)
    wow.set("SOUNDKIT", { LEVELUPSOUND = 888 })
    wow.fire("ADDON_LOADED", "UltimatePet")
    Alerts = UP.Alerts
    changes = 0
    UP:On("STATE_CHANGED", function() changes = changes + 1 end)
    wow.takeChat()
  end

  local function popup() return _G.UltimatePetLearnAlert end

  before_each(function() load() end)
  after_each(function()
    stub.uninstall()
    wow.restore()
  end)

  describe("Pattern", function()
    it("turns %s into a capture and escapes the rest", function()
      local p = Alerts.Pattern("You have learned a new ability: %s.")
      assert.are.equal("^You have learned a new ability: (.+)%.$", p)
      assert.are.equal("Claw (Rank 2)", ("You have learned a new ability: Claw (Rank 2)."):match(p))
    end)

    it("handles positional %1$s", function()
      local p = Alerts.Pattern("Neue Fähigkeit (%1$s) erlernt.")
      assert.are.equal("Klaue (Rang 2)", ("Neue Fähigkeit (Klaue (Rang 2)) erlernt."):match(p))
    end)
  end)

  describe("ParseChat", function()
    it("maps the client's name and takes the digit from the rank text", function()
      local skill, rank, name = Alerts.ParseChat("You have learned a new ability: Klaue (Rang 2).")
      assert.are.equal("Claw", skill)
      assert.are.equal(2, rank)
      assert.are.equal("Klaue", name)
    end)

    it("falls back to the English name when the client name can't be read", function()
      assert.are.equal("Dash", (Alerts.ParseChat("You have learned a new ability: Dash (Rank 1).")))
    end)

    it("keeps the skill but drops an unreadable rank, unless the skill has one rank", function()
      local skill, rank = Alerts.ParseChat("You have learned a new ability: Klaue (Rang X).")
      assert.are.equal("Claw", skill)
      assert.is_nil(rank)
      local s2, r2 = Alerts.ParseChat("You have learned a new ability: Shell Shield.")
      assert.are.equal("Shell Shield", s2)
      assert.are.equal(1, r2)
    end)

    it("ignores other lines and unknown abilities", function()
      assert.is_nil(Alerts.ParseChat("You have learned a new ability: Fireball (Rank 2)."))
      assert.is_nil(Alerts.ParseChat("Fang is now Unruly."))
    end)
  end)

  describe("detection", function()
    it("records Claw 2 from the chat line, fires STATE_CHANGED and notifies", function()
      wow.fire("CHAT_MSG_SYSTEM", "You have learned a new ability: Klaue (Rang 2).")
      assert.is_true(UP.char.unlocked.Claw[2])
      assert.are.equal(1, changes)
      assert.are.same({ "UltimatePet: New pet ability: Klaue (Rank 2)." }, wow.takeChat())
      assert.are.same({ { 888, "Master" } }, sounds)
      assert.is_true(popup():IsShown())
      assert.are.equal("New pet ability", popup().heading:GetText())
      assert.are.equal("Klaue (Rank 2)", popup().title:GetText())
      assert.are.equal(100000 + UP.Skills.Claw.ranks[2].spellId, popup().icon:GetTexture())
    end)

    it("records a rank from the spell id events", function()
      wow.fire("LEARNED_SPELL_IN_TAB", UP.Skills.Bite.ranks[3].spellId, 1, false)
      assert.is_true(UP.char.unlocked.Bite[3])
      wow.fire("LEARNED_SPELL_IN_SKILL_LINE", UP.Skills.Claw.ranks[4].spellId, 1, false)
      assert.is_true(UP.char.unlocked.Claw[4])
      assert.are.equal(2, #wow.takeChat())
    end)

    it("merges the chat line and the event of one learn into one alert", function()
      local timers = {}
      C_Timer.After = function(_, fn) timers[#timers + 1] = fn end
      wow.fire("CHAT_MSG_SYSTEM", "You have learned a new ability: Klaue (Rang X).")
      wow.fire("LEARNED_SPELL_IN_TAB", UP.Skills.Claw.ranks[2].spellId)
      assert.are.equal(1, #timers)
      assert.are.equal(0, #wow.takeChat())
      timers[1]()
      assert.are.same({ "UltimatePet: New pet ability: Klaue (Rank 2)." }, wow.takeChat())
      assert.is_true(UP.char.unlocked.Claw[2])
      assert.are.equal(1, #sounds)
    end)

    it("ignores the same skill and rank for 5 seconds", function()
      wow.fire("CHAT_MSG_SYSTEM", "You have learned a new ability: Klaue (Rang 2).")
      wow.now = 4
      wow.fire("LEARNED_SPELL_IN_TAB", UP.Skills.Claw.ranks[2].spellId)
      assert.are.equal(1, #wow.takeChat())
      wow.now = 5.5
      wow.fire("LEARNED_SPELL_IN_TAB", UP.Skills.Claw.ranks[2].spellId)
      assert.are.equal(1, #wow.takeChat())
    end)

    it("ignores everything while a trainer window is open", function()
      wow.fire("TRAINER_SHOW")
      wow.fire("CHAT_MSG_SYSTEM", "You have learned a new ability: Klaue (Rang 2).")
      assert.is_nil(UP.char.unlocked.Claw)
      assert.are.equal(0, #wow.takeChat())
      wow.fire("TRAINER_CLOSED")
      wow.fire("CHAT_MSG_SYSTEM", "You have learned a new ability: Klaue (Rang 2).")
      assert.is_true(UP.char.unlocked.Claw[2])
    end)

    it("treats a hidden ClassTrainerFrame as a closed trainer", function()
      wow.fire("TRAINER_SHOW")
      wow.set("ClassTrainerFrame", { IsShown = function() return false end })
      wow.fire("CHAT_MSG_SYSTEM", "You have learned a new ability: Klaue (Rang 2).")
      assert.is_true(UP.char.unlocked.Claw[2])
    end)

    it("ignores trainer-taught skills", function()
      wow.fire("CHAT_MSG_SYSTEM", "You have learned a new ability: Growl (Rank 2).")
      wow.fire("LEARNED_SPELL_IN_TAB", UP.Skills["Great Stamina"].ranks[3].spellId)
      wow.fire("CHAT_MSG_SYSTEM", "You have learned a new ability: Great Stamina.")
      assert.is_nil(UP.char.unlocked.Growl)
      assert.is_nil(UP.char.unlocked["Great Stamina"])
      assert.are.equal(0, changes)
      assert.are.equal(0, #wow.takeChat())
    end)

    it("alerts with the name only when the rank can't be read, without recording", function()
      wow.fire("CHAT_MSG_SYSTEM", "You have learned a new ability: Klaue (Rang X).")
      assert.are.same({ "UltimatePet: New pet ability: Klaue." }, wow.takeChat())
      assert.is_nil(UP.char.unlocked.Claw)
    end)

    it("handles a positional format string", function()
      load({ format = "Ihr habt eine neue Fähigkeit erlernt: %1$s." })
      wow.fire("CHAT_MSG_SYSTEM", "Ihr habt eine neue Fähigkeit erlernt: Biss (Rang 3).")
      assert.is_true(UP.char.unlocked.Bite[3])
    end)
  end)

  describe("settings", function()
    it("defaults popup, sound and chat on without overwriting saved values", function()
      assert.are.same({ popup = true, sound = true, chat = true }, UP.db.global.alerts)
      UP = wow.load({ saved = { version = 2, global = { alerts = { sound = false } } } })
      wow.fire("ADDON_LOADED", "UltimatePet")
      assert.are.same({ popup = true, sound = false, chat = true }, UP.db.global.alerts)
    end)

    for _, key in ipairs({ "popup", "sound", "chat" }) do
      it("skips the " .. key .. " when it is off", function()
        UP.db.global.alerts[key] = false
        wow.fire("CHAT_MSG_SYSTEM", "You have learned a new ability: Klaue (Rang 2).")
        local shown = popup() ~= nil and popup():IsShown()
        assert.are.equal(key ~= "popup", shown)
        assert.are.equal(key ~= "sound", #sounds == 1)
        assert.are.equal(key ~= "chat", #wow.takeChat() == 1)
        assert.is_true(UP.char.unlocked.Claw[2])
      end)
    end
  end)

  describe("popup", function()
    it("names the summoned pet's assigned build when it uses the rank", function()
      UP.Scanner.pet = { exists = true, name = "Fang", family = "Cat", key = 7, known = {} }
      UP.char.petBuild[7] = "Raid DPS"
      wow.fire("CHAT_MSG_SYSTEM", "You have learned a new ability: Klaue (Rang 2).")
      assert.are.equal("Part of your build: Raid DPS", popup().build:GetText())
      assert.is_true(popup().build:IsShown())
    end)

    it("names the default planner build (the family's first preset)", function()
      wow.fire("CHAT_MSG_SYSTEM", "You have learned a new ability: Klaue (Rang 2).")
      assert.are.equal("Part of your build: Raid DPS", popup().build:GetText())
    end)

    it("names a saved current build, and shows no build line when nothing uses the rank", function()
      UP.char.currentBuild = { family = "Cat", level = 60, loyalty = 6, skills = { Claw = 8 }, loaded = "Mine" }
      wow.fire("CHAT_MSG_SYSTEM", "You have learned a new ability: Klaue (Rang 2).")
      assert.are.equal("Part of your build: Mine", popup().build:GetText())
      stub.fire(popup(), "OnUpdate", 10)
      UP.char.currentBuild.skills = {}
      wow.fire("LEARNED_SPELL_IN_TAB", UP.Skills.Bite.ranks[2].spellId)
      assert.is_false(popup().build:IsShown())
    end)

    it("fades in, holds, fades out and then shows the next queued alert", function()
      local timers = {}
      C_Timer.After = function(_, fn) timers[#timers + 1] = fn end
      wow.fire("CHAT_MSG_SYSTEM", "You have learned a new ability: Klaue (Rang 2).")
      wow.fire("CHAT_MSG_SYSTEM", "You have learned a new ability: Biss (Rang 3).")
      timers[1]()
      local f = popup()
      assert.are.equal("Klaue (Rank 2)", f.title:GetText())
      stub.fire(f, "OnUpdate", 2)
      assert.is_true(f:IsShown())
      stub.fire(f, "OnUpdate", 3.5)
      assert.are.equal("Biss (Rank 3)", f.title:GetText())
      assert.is_true(f:IsShown())
      stub.fire(f, "OnUpdate", 6)
      assert.is_false(f:IsShown())
    end)
  end)

  describe("Test", function()
    it("shows a Claw 2 sample without recording it", function()
      Alerts:Test()
      assert.is_nil(UP.char.unlocked.Claw)
      assert.are.equal(0, changes)
      assert.are.same({ "UltimatePet: New pet ability: Klaue (Rank 2)." }, wow.takeChat())
      assert.are.equal("Klaue (Rank 2)", popup().title:GetText())
      assert.are.equal(1, #sounds)
    end)

    it("says so when every alert is off", function()
      UP.db.global.alerts = { popup = false, sound = false, chat = false }
      Alerts:Test()
      assert.are.same({ "UltimatePet: All alerts are off. Turn one on with /upet alerts popup on." },
        wow.takeChat())
    end)
  end)

  describe("Slash", function()
    it("prints the state with no arguments", function()
      Alerts.Slash("")
      assert.are.same({ "UltimatePet: Alerts: popup on, sound on, chat on. "
        .. "/upet alerts popup|sound|chat on|off, /upet alerts test" }, wow.takeChat())
    end)

    it("turns each alert on and off", function()
      Alerts.Slash("popup off")
      Alerts.Slash("SOUND off")
      Alerts.Slash("chat  on")
      assert.are.same({ "UltimatePet: Popup alerts off.", "UltimatePet: Sound alerts off.",
        "UltimatePet: Chat alerts on." }, wow.takeChat())
      assert.are.same({ popup = false, sound = false, chat = true }, UP.db.global.alerts)
    end)

    it("runs the test", function()
      Alerts.Slash("test")
      assert.are.same({ "UltimatePet: New pet ability: Klaue (Rank 2)." }, wow.takeChat())
    end)

    it("prints usage for anything else", function()
      Alerts.Slash("popup maybe")
      Alerts.Slash("volume on")
      local usage = "UltimatePet: Usage: /upet alerts popup|sound|chat on|off, /upet alerts test"
      assert.are.same({ usage, usage }, wow.takeChat())
    end)
  end)
end)
