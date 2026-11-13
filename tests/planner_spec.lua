local wow = dofile("tests/wowstub.lua")

local UP = wow.load()
local Planner = UP.Planner

describe("Planner.Budget", function()
  it("is level * (loyalty - 1)", function()
    local cases = {
      { 60, 6, 300 }, { 60, 5, 240 }, { 60, 2, 60 }, { 10, 3, 20 }, { 1, 6, 5 },
      { 60, 1, 0 }, { 10, 1, 0 }, { 0, 6, 0 },
    }
    for _, c in ipairs(cases) do
      assert.are.equal(c[3], Planner.Budget(c[1], c[2]), c[1] .. "/" .. c[2])
    end
  end)

  it("never goes below 0", function()
    assert.are.equal(0, Planner.Budget(60, 0))
    assert.are.equal(0, Planner.Budget(nil, nil))
  end)
end)

describe("Planner.LoyaltyLevel", function()
  it("maps the Forever loyalty names", function()
    local names = { "Rebellious", "Unruly", "Submissive", "Dependable", "Faithful", "Best Friend" }
    for i, name in ipairs(names) do
      assert.are.equal(i, Planner.LoyaltyLevel(name))
    end
    assert.are.equal(6, Planner.LoyaltyLevel("  best friend "))
  end)

  it("takes numbers and a digit in text", function()
    assert.are.equal(3, Planner.LoyaltyLevel(3))
    assert.are.equal(5, Planner.LoyaltyLevel("(Loyalty Level 5) Faithful"))
    assert.are.equal(2, Planner.LoyaltyLevel("Loyalty 2"))
  end)

  it("derives from total TP and pet level when it divides evenly", function()
    assert.are.equal(6, Planner.LoyaltyLevel(nil, 300, 60))
    assert.are.equal(1, Planner.LoyaltyLevel("???", 0, 10))
    assert.are.equal(3, Planner.LoyaltyLevel(nil, 20, 10))
  end)

  it("returns nil when nothing fits", function()
    assert.is_nil(Planner.LoyaltyLevel(nil))
    assert.is_nil(Planner.LoyaltyLevel("Grumpy"))
    assert.is_nil(Planner.LoyaltyLevel(9))
    assert.is_nil(Planner.LoyaltyLevel(nil, 25, 10))
    assert.is_nil(Planner.LoyaltyLevel(nil, 700, 10))
  end)
end)

describe("Planner.Cost and ActiveCount", function()
  it("sums known TP of the example Cat build", function()
    local build = { family = "Cat", level = 60, loyalty = 6, skills = {
      Bite = 8, Claw = 8, Dash = 3, Growl = 7, ["Great Stamina"] = 9, ["Natural Armor"] = 7 } }
    assert.are.same({ 300, 0 }, { Planner.Cost(build) })
    assert.are.equal(4, Planner.ActiveCount(build))
  end)

  it("counts unknown-TP ranks separately and ignores rank 0", function()
    local build = { family = "Bear", level = 60, loyalty = 6, skills = {
      Bite = 8, Swipe = 2, Claw = 0, ["Great Stamina"] = 1 } }
    assert.are.same({ 30, 1 }, { Planner.Cost(build) })
    assert.are.equal(2, Planner.ActiveCount(build))
  end)

  it("handles an empty build", function()
    assert.are.same({ 0, 0 }, { Planner.Cost({ family = "Cat", skills = {} }) })
    assert.are.equal(0, Planner.ActiveCount({ family = "Cat", skills = {} }))
  end)

  it("counts over the 4-active cap without refusing", function()
    local build = { family = "Cat", skills = { Bite = 1, Claw = 1, Dash = 1, Prowl = 1, Growl = 1, Cower = 1 } }
    assert.are.equal(6, Planner.ActiveCount(build))
    assert.is_true(Planner.ActiveCount(build) > Planner.MAX_ACTIVE)
  end)
end)

describe("Planner.Validate", function()
  it("finds no problems in a legal build", function()
    assert.are.same({}, Planner.Validate({ family = "Cat", level = 60, skills = { Bite = 8, Prowl = 3 } }))
  end)

  it("reports family, skill and rank errors and level warnings", function()
    local problems = Planner.Validate({ family = "Cat", level = 20, skills = {
      Bite = 9, Swipe = 1, Dash = 1, Nope = 1 } })
    local msgs = {}
    for _, p in ipairs(problems) do msgs[#msgs + 1] = p.kind .. ": " .. p.msg end
    assert.are.same({
      "error: Bite has 8 ranks, not 9.",
      "warn: Dash 1 needs pet level 30.",
      "error: Cat can't learn Swipe.",
      "error: Unknown skill: Nope.",
    }, msgs)
  end)

  it("reports an unknown family", function()
    assert.are.equal("Unknown family: Stag.", Planner.Validate({ family = "Stag", skills = {} })[1].msg)
  end)
end)

describe("Planner.Status", function()
  -- Wolf at 40 with Bite 4 known, Bite 5 and 7 unlocked, 30 TP unspent.
  local function ctx(over)
    local c = {
      family = "Wolf", petFamily = "Wolf", petLevel = 40, unspent = 30,
      known = { Bite = 4 },
      unlocked = { Bite = { [4] = true, [5] = true, [7] = true }, Charge = { [4] = true } },
    }
    for k, v in pairs(over or {}) do c[k] = v end
    return c
  end

  it("returns nil for rank 0", function()
    assert.is_nil(Planner.Status("Bite", 0, ctx()))
  end)

  it("TRAINED when the pet knows the rank or higher", function()
    assert.are.equal("TRAINED", Planner.Status("Bite", 3, ctx()).code)
    assert.are.equal("TRAINED", Planner.Status("Bite", 4, ctx()).code)
  end)

  it("READY with the TP difference from the known rank", function()
    local s = Planner.Status("Bite", 5, ctx())
    assert.are.equal("READY", s.code)
    assert.are.equal(3, s.delta) -- 13 - 10
    assert.are.equal(32, s.level)
  end)

  it("NEED_LEVEL when unlocked above the pet's level", function()
    local s = Planner.Status("Bite", 7, ctx())
    assert.are.equal("NEED_LEVEL", s.code)
    assert.are.equal(48, s.level)
  end)

  it("NEED_TP with the shortfall", function()
    local s = Planner.Status("Bite", 5, ctx({ unspent = 1 }))
    assert.are.equal("NEED_TP", s.code)
    assert.are.equal(2, s.short)
  end)

  it("NEED_TP when unspent is negative, even for unknown TP", function()
    local s = Planner.Status("Bite", 5, ctx({ unspent = -4 }))
    assert.are.equal("NEED_TP", s.code)
    assert.are.equal(7, s.short)
    local c = ctx({ unspent = -4, family = "Bear", petFamily = "Bear", unlocked = { Swipe = { [1] = true } } })
    local swipe = Planner.Status("Swipe", 1, c)
    assert.are.equal("NEED_TP", swipe.code)
    assert.is_true(swipe.tpUnknown)
  end)

  it("READY with tpUnknown when the cost is unknown", function()
    local c = ctx({ family = "Bear", petFamily = "Bear", unspent = 0, unlocked = { Swipe = { [2] = true } } })
    local s = Planner.Status("Swipe", 2, c)
    assert.are.equal("READY", s.code)
    assert.are.equal(0, s.delta)
    assert.is_true(s.tpUnknown)
  end)

  it("TRAINER and TRAINER_LEVEL for trainer ranks", function()
    assert.are.equal("TRAINER", Planner.Status("Great Stamina", 6, ctx()).code)
    local s = Planner.Status("Great Stamina", 10, ctx())
    assert.are.equal("TRAINER_LEVEL", s.code)
    assert.are.equal(60, s.level)
    assert.are.equal("TRAINER", Planner.Status("Growl", 5, ctx()).code)
  end)

  it("NO_SOURCE for ranks no beast teaches, unless already unlocked", function()
    assert.are.equal("NO_SOURCE", Planner.Status("Lava Breath", 1, ctx({ family = "Core Hound" })).code)
    -- Charge 4 has no known source; one unlocked anyway (e.g. found in game) is trainable.
    local boar = { family = "Boar", petFamily = "Boar", known = {} }
    assert.are.equal("READY", Planner.Status("Charge", 4, ctx(boar)).code)
    boar.unlocked = {}
    assert.are.equal("NO_SOURCE", Planner.Status("Charge", 4, ctx(boar)).code)
  end)

  it("LOCKED when a beast teaches it but it isn't unlocked", function()
    assert.are.equal("LOCKED", Planner.Status("Bite", 6, ctx()).code)
    assert.are.equal("LOCKED", Planner.Status("Bite", 5, ctx({ unlocked = {} })).code)
  end)

  it("ignores the pet's known ranks when its family differs from the build's", function()
    local c = ctx({ family = "Cat" })
    local s = Planner.Status("Bite", 4, c)
    assert.are.equal("READY", s.code)
    assert.are.equal(10, s.delta)
    assert.are.equal("TRAINED", Planner.Status("Bite", 4, ctx({ family = nil })).code)
  end)

  it("treats a missing context as level 0 with no TP", function()
    assert.are.equal("LOCKED", Planner.Status("Bite", 1).code)
    assert.are.equal("TRAINER_LEVEL", Planner.Status("Growl", 1).code)
  end)
end)

describe("Planner.Teachers", function()
  it("returns npc entries with ids in the generated order, 8 by default", function()
    local list = Planner.Teachers("Bite", 1)
    assert.are.equal(8, #list)
    assert.are.equal(UP.Beasts.teach.Bite[1][1], list[1].id)
    assert.are.equal(UP.Beasts.npcs[list[1].id].name, list[1].name)
  end)

  it("honours the limit and handles skills with no teachers", function()
    assert.are.equal(2, #Planner.Teachers("Bite", 1, 2))
    assert.are.same({}, Planner.Teachers("Lava Breath", 1))
    assert.are.same({}, Planner.Teachers("Nope", 1))
  end)
end)

describe("Planner.Preset and CopyBuild", function()
  it("defaults to the family's first preset and copies it as a build", function()
    local preset = Planner.Preset("Cat")
    assert.are.equal("Raid DPS", preset.name)
    local build = Planner.CopyBuild(preset)
    assert.are.same({ "Cat", 60, 6 }, { build.family, build.level, build.loyalty })
    assert.are.same(preset.skills, build.skills)
    build.skills.Bite = 1
    assert.are.equal(8, preset.skills.Bite)
    assert.is_nil(build.note)
  end)

  it("finds by name and returns nil for unknown families", function()
    assert.are.equal("PvP", Planner.Preset("Wolf", "PvP").name)
    assert.is_nil(Planner.Preset("Stag"))
  end)
end)
