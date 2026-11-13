local wow = dofile("tests/wowstub.lua")

local UP = wow.load()
local Serializer = UP.Serializer

local EXAMPLE = "UP1:Cat:60-6:Bi8,Cl8,Da3,Gr7,GS9,NA7"

local function decodeError(str)
  local ok, err = Serializer.Decode(str)
  assert.is_false(ok, str)
  return err
end

describe("Serializer.Encode", function()
  it("writes the example string in SkillOrder order", function()
    local build = { family = "Cat", level = 60, loyalty = 6, skills = {
      ["Natural Armor"] = 7, Growl = 7, Bite = 8, Dash = 3, Claw = 8, ["Great Stamina"] = 9, Prowl = 0 } }
    assert.are.equal(EXAMPLE, Serializer.Encode(build))
  end)

  it("drops spaces from the family and allows an empty skill list", function()
    local build = { family = "Bird of Prey", level = 12, loyalty = 2, skills = {} }
    assert.are.equal("UP1:BirdofPrey:12-2:", Serializer.Encode(build))
  end)
end)

describe("Serializer.Decode", function()
  it("reads the example string", function()
    local ok, build = Serializer.Decode(EXAMPLE)
    assert.is_true(ok)
    assert.are.same({ family = "Cat", level = 60, loyalty = 6, skills = {
      Bite = 8, Claw = 8, Dash = 3, Growl = 7, ["Great Stamina"] = 9, ["Natural Armor"] = 7 } }, build)
  end)

  it("round-trips every preset", function()
    local n = 0
    for family, list in pairs(UP.Presets) do
      for _, preset in ipairs(list) do
        local build = UP.Planner.CopyBuild(preset)
        local str = Serializer.Encode(build)
        local ok, back = Serializer.Decode(str)
        assert.is_true(ok, family .. " " .. preset.name .. ": " .. tostring(back))
        assert.are.same(build, back)
        assert.are.equal(str, Serializer.Encode(back))
        n = n + 1
      end
    end
    assert.are.equal(76, n)
  end)

  it("ignores whitespace and the case of the prefix, family and codes", function()
    local ok, build = Serializer.Decode("  up1 : cat :60 - 6:\n bi8, Cl8 ,da3,GR7,gs9,NA7, \t")
    assert.is_true(ok)
    assert.are.equal(EXAMPLE, Serializer.Encode(build))
    ok, build = Serializer.Decode("Up1:birdofprey:60-6:Cl8,Mi1")
    assert.is_true(ok)
    assert.are.equal("Bird of Prey", build.family)
  end)

  it("accepts an empty skill list", function()
    local ok, build = Serializer.Decode("UP1:Wolf:10-1:")
    assert.is_true(ok)
    assert.are.same({}, build.skills)
  end)

  it("explains what is wrong", function()
    assert.are.equal("Not an UltimatePet string.", decodeError("hello"))
    assert.are.equal("Not an UltimatePet string.", decodeError(""))
    assert.are.equal("Not an UltimatePet string.", decodeError(nil))
    assert.are.equal("Unsupported string version: UP2.", decodeError("UP2:Cat:60-6:Bi8"))
    assert.are.equal("Malformed build string.", decodeError("UP1:Cat:60:Bi8"))
    assert.are.equal("Malformed build string.", decodeError("UP1:Cat:60-6"))
    assert.are.equal("Unknown family: Stag.", decodeError("UP1:Stag:60-6:Bi8"))
    assert.are.equal("Level must be 1-60, not 61.", decodeError("UP1:Cat:61-6:Bi8"))
    assert.are.equal("Level must be 1-60, not 0.", decodeError("UP1:Cat:0-6:Bi8"))
    assert.are.equal("Loyalty must be 1-6, not 7.", decodeError("UP1:Cat:60-7:Bi8"))
    assert.are.equal("Unknown skill code: Zz.", decodeError("UP1:Cat:60-6:Bi8,Zz1"))
    assert.are.equal("Bad skill entry: Bite8.", decodeError("UP1:Cat:60-6:Bite8"))
    assert.are.equal("Bite has 8 ranks, not 9.", decodeError("UP1:Cat:60-6:Bi9"))
    assert.are.equal("Bite has 8 ranks, not 0.", decodeError("UP1:Cat:60-6:Bi0"))
    assert.are.equal("Cat can't learn Swipe.", decodeError("UP1:Cat:60-6:Sw1"))
  end)

  it("rejects a skill listed twice", function()
    assert.are.equal("Bite is listed twice.", decodeError("UP1:Cat:60-6:Bi8,Cl8,bi7"))
  end)
end)
