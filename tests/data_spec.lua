-- Checks the generated data (Data/Families.lua, Data/Skills.lua, Data/Beasts.lua) after a full
-- addon load. Regenerate with `python3 -I tools/gen_data.py`; decisions are in tools/DATA_NOTES.md.
local wow = dofile("tests/wowstub.lua")

local UP = wow.load()
local Families, Skills, Beasts = UP.Families, UP.Skills, UP.Beasts

local FAMILIES = {
  "Bat", "Bear", "Bird of Prey", "Boar", "Carrion Bird", "Cat", "Core Hound", "Crab", "Crocolisk",
  "Fox", "Gorilla", "Hyena", "Raptor", "Scorpid", "Spider", "Tallstrider", "Turtle", "Wind Serpent",
  "Wolf",
}
local SOURCES = { tame = true, trainer = true, none = true }

local function count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

local function contains(list, value)
  for _, v in ipairs(list) do
    if v == value then return true end
  end
  return false
end

local function teachers(skill, rank)
  return (Beasts.teach[skill] or {})[rank] or {}
end

describe("Families", function()
  it("has the 19 Forever families in alphabetical FamilyOrder", function()
    assert.are.same(FAMILIES, UP.FamilyOrder)
    assert.are.equal(19, count(Families))
  end)

  it("lists at least 3 abilities per family, all of them known skills that name the family", function()
    for _, name in ipairs(FAMILIES) do
      local fam = Families[name]
      assert.is_table(fam, name)
      assert.is_string(fam.petopiaId, name)
      assert.is_true(#fam.abilities >= 3, name)
      for _, skill in ipairs(fam.abilities) do
        assert.is_table(Skills[skill], name .. ": " .. skill)
        assert.is_true(Skills[skill].families[name], name .. ": " .. skill)
      end
    end
  end)

  it("matches every skill's family set", function()
    for skill, s in pairs(Skills) do
      for fam in pairs(s.families) do
        assert.is_true(contains(Families[fam].abilities, skill), skill .. " / " .. fam)
      end
    end
  end)

  it("gives Core Hound Bite, Cower, Growl, Lava Breath and the passives", function()
    local abilities = Families["Core Hound"].abilities
    for _, skill in ipairs({ "Bite", "Cower", "Growl", "Lava Breath", "Great Stamina", "Natural Armor",
                             "Fire Resistance" }) do
      assert.is_true(contains(abilities, skill), skill)
    end
    assert.is_false(contains(abilities, "Claw"))
  end)
end)

describe("Skills", function()
  it("has 32 skills, 7 of them passive", function()
    local passives = 0
    for _, s in pairs(Skills) do
      if not s.active then passives = passives + 1 end
    end
    assert.are.equal(32, count(Skills))
    assert.are.equal(7, passives)
  end)

  it("gives every rank a level, a source, and a numeric or unknown TP cost", function()
    for name, s in pairs(Skills) do
      assert.is_string(s.key, name)
      assert.is_boolean(s.active, name)
      assert.is_boolean(s.unique, name)
      assert.is_string(s.icon, name)
      assert.is_truthy(s.icon:match("^Interface\\Icons\\"), name)
      assert.are.equal(s.unique, count(s.families) == 1, name)
      assert.is_true(#s.ranks >= 1, name)
      assert.are.equal(#s.ranks, count(s.ranks), name)
      local prev = 0
      for r, rank in ipairs(s.ranks) do
        local id = name .. " " .. r
        assert.is_number(rank.level, id)
        assert.is_true(rank.level >= prev and rank.level <= 60, id)
        prev = rank.level
        assert.is_true(rank.tp == nil or type(rank.tp) == "number", id)
        assert.is_true(SOURCES[rank.source] == true, id)
        if name ~= "Lava Breath" then -- no source has Lava Breath spell ids
          assert.is_number(rank.spellId, id)
        end
      end
    end
  end)

  it("lists every skill once in SkillOrder, actives first", function()
    assert.are.equal(count(Skills), #UP.SkillOrder)
    local seen, passive = {}, false
    for _, name in ipairs(UP.SkillOrder) do
      assert.is_table(Skills[name], name)
      assert.is_nil(seen[name], name)
      seen[name] = true
      if passive then assert.is_false(Skills[name].active, name) end
      if not Skills[name].active then passive = true end
    end
  end)

  it("has a unique two-letter export code for every skill", function()
    local used = {}
    for name in pairs(Skills) do
      local code = UP.SkillCodes[name]
      assert.is_string(code, name)
      assert.is_truthy(code:match("^%a%a$"), name)
      assert.is_nil(used[code], code)
      used[code] = name
    end
    assert.are.equal(count(Skills), count(UP.SkillCodes))
    assert.are.equal("Bi", UP.SkillCodes.Bite)
    assert.are.equal("LB", UP.SkillCodes["Lava Breath"])
    assert.are.equal("FT", UP.SkillCodes["Frost Resistance"])
  end)

  it("keeps Growl free and trainer-taught at ranks 2-7", function()
    for r = 2, 7 do
      assert.are.equal("trainer", Skills.Growl.ranks[r].source)
      assert.are.equal(0, Skills.Growl.ranks[r].tp)
    end
  end)

  it("stores placeholder TP costs on Forever abilities as unknown", function()
    for r = 1, 5 do
      assert.is_nil(Skills.Dismember.ranks[r].tp)
      assert.is_nil(Skills["Sonic Blast"].ranks[r].tp)
    end
    assert.is_nil(Skills["Trickster's Dance"].ranks[1].tp)
    assert.is_nil(Skills.Thunderstomp.ranks[4].tp)
    assert.are.equal(25, Skills.Thunderstomp.ranks[3].tp)
    assert.are.equal(25, Skills.Bite.ranks[8].tp)
  end)
end)

describe("Beasts", function()
  it("resolves every teacher to an npc of a family that can learn the skill", function()
    for skill, ranks in pairs(Beasts.teach) do
      assert.is_table(Skills[skill], skill)
      for r, ids in pairs(ranks) do
        assert.is_table(Skills[skill].ranks[r], skill .. " " .. r)
        assert.is_true(#ids > 0, skill .. " " .. r)
        assert.are.equal("tame", Skills[skill].ranks[r].source, skill .. " " .. r)
        for _, id in ipairs(ids) do
          local npc = Beasts.npcs[id]
          assert.is_table(npc, skill .. " " .. r .. ": npc " .. id)
          assert.is_true(Skills[skill].families[npc.family], skill .. " " .. r .. ": npc " .. id)
        end
      end
    end
  end)

  it("keeps coordinates in 0-100 and only with a map", function()
    local withCoords = 0
    for id, npc in pairs(Beasts.npcs) do
      assert.is_string(npc.name, id)
      assert.is_table(Families[npc.family], id)
      if npc.map then
        withCoords = withCoords + 1
        assert.is_number(npc.x, id)
        assert.is_number(npc.y, id)
        assert.is_true(npc.x >= 0 and npc.x <= 100 and npc.y >= 0 and npc.y <= 100, id)
      else
        assert.is_nil(npc.x, id)
        assert.is_nil(npc.y, id)
      end
      if npc.instance then
        assert.are.equal(1, select(2, npc.zone:gsub("%((%a+)%)$", "")), id)
      end
    end
    assert.is_true(withCoords > 300)
  end)

  it("sorts open-world beasts before instance ones, then normal before rare/elite", function()
    local function tier(npc)
      return (npc.instance and 2 or 0) + (npc.class and 1 or 0)
    end
    for skill, ranks in pairs(Beasts.teach) do
      for r, ids in pairs(ranks) do
        for i = 2, #ids do
          local a, b = Beasts.npcs[ids[i - 1]], Beasts.npcs[ids[i]]
          assert.is_true(tier(a) <= tier(b), skill .. " " .. r)
        end
      end
    end
  end)

  it("has no teachers for Lava Breath", function()
    assert.is_nil(Beasts.teach["Lava Breath"])
    for _, rank in ipairs(Skills["Lava Breath"].ranks) do
      assert.are.equal("none", rank.source)
    end
  end)

  it("takes Sonic Blast (missing from Petopia) from TrueshotLodge", function()
    local s = Skills["Sonic Blast"]
    assert.are.same({ Bat = true }, s.families)
    assert.are.equal(5, #s.ranks)
    assert.are.equal(1264478, s.ranks[1].spellId)
    assert.are.equal("tame", s.ranks[1].source)
    assert.are.equal("none", s.ranks[5].source)
    assert.is_true(contains(teachers("Sonic Blast", 1), 277882))
  end)

  it("keeps Lava Breath (missing from TrueshotLodge) from Petopia", function()
    local s = Skills["Lava Breath"]
    assert.are.same({ ["Core Hound"] = true }, s.families)
    assert.are.equal(2, #s.ranks)
    assert.are.equal(48, s.ranks[1].level)
    assert.is_nil(s.ranks[1].spellId)
    assert.is_nil(s.ranks[1].tp)
  end)

  it("merges teacher lists: Petopia-only and TrueshotLodge-only links both kept", function()
    assert.is_true(contains(teachers("Bite", 1), 250873)) -- Juvenile Vuldren, Petopia only
    assert.is_true(contains(teachers("Bite", 1), 255887)) -- Slydris, TrueshotLodge only
    -- Petopia lists no source for Demoralizing Screech 2; TrueshotLodge has teachers.
    assert.are.equal("tame", Skills["Demoralizing Screech"].ranks[2].source)
    assert.is_true(contains(teachers("Demoralizing Screech", 2), 4158))
  end)

  it("drops a teacher whose family cannot learn the skill", function()
    assert.is_false(contains(teachers("Claw", 5), 4343)) -- Drywallow Snapper is a Crocolisk
    assert.is_true(contains(teachers("Bite", 5), 4343))
  end)

  it("leaves dungeon mobs without coordinates instead of inventing them", function()
    local kresh = Beasts.npcs[3653]
    assert.are.equal("Wailing Caverns", kresh.instance)
    assert.is_nil(kresh.map)
  end)
end)
