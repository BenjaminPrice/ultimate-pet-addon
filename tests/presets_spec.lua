-- Checks every hand-authored preset in Data/Presets.lua against the generated data.
local wow = dofile("tests/wowstub.lua")

local UP = wow.load()
local Planner = UP.Planner

local ROLES = { "Raid DPS", "Leveling / Solo Tank", "PvP" }
local RESIST = { ["Fire Resistance"] = true, ["Nature Resistance"] = true }

local function each(fn)
  for _, family in ipairs(UP.FamilyOrder) do
    for _, preset in ipairs(UP.Presets[family]) do fn(family, preset, family .. " / " .. preset.name) end
  end
end

describe("Presets", function()
  it("has 4 uniquely named presets for each of the 19 families, in role order", function()
    local families = 0
    for family, list in pairs(UP.Presets) do
      families = families + 1
      assert.is_table(UP.Families[family], family)
      assert.are.equal(4, #list, family)
      local seen = {}
      for i, preset in ipairs(list) do
        assert.is_nil(seen[preset.name], family .. " " .. preset.name)
        seen[preset.name] = true
        if i <= 3 then
          assert.are.equal(ROLES[i], preset.name, family)
        else
          assert.is_true(RESIST[preset.name], family .. " " .. preset.name)
          assert.are.equal("resist", preset.role)
        end
      end
    end
    assert.are.equal(19, families)
  end)

  it("are level 60 Best Friend builds of their own family", function()
    each(function(family, preset, label)
      assert.are.equal(family, preset.family, label)
      assert.are.equal(60, preset.level, label)
      assert.are.equal(6, preset.loyalty, label)
      assert.is_string(preset.role, label)
    end)
  end)

  it("fit 300 known TP and 4 actives", function()
    each(function(_, preset, label)
      local known = Planner.Cost(preset)
      assert.is_true(known <= Planner.Budget(60, 6), label .. ": " .. known .. " TP")
      assert.is_true(Planner.ActiveCount(preset) <= Planner.MAX_ACTIVE, label)
    end)
  end)

  it("only use skills and ranks the family can learn by 60", function()
    each(function(_, preset, label)
      assert.are.same({}, Planner.Validate(preset), label)
      for skill, rank in pairs(preset.skills) do
        assert.is_true(rank >= 1, label .. ": " .. skill)
      end
    end)
  end)

  it("say so in the note when they include abilities with unknown TP", function()
    each(function(_, preset, label)
      assert.is_string(preset.note, label)
      assert.is_true(#preset.note > 0, label)
      local _, unknown = Planner.Cost(preset)
      local flagged = preset.note:find("Includes abilities with unknown TP cost.", 1, true) ~= nil
      assert.are.equal(unknown > 0, flagged, label)
    end)
  end)

  it("avoid ranks with no known source, except Lava Breath", function()
    each(function(_, preset, label)
      for skill, rank in pairs(preset.skills) do
        if skill ~= "Lava Breath" then
          assert.are_not.equal("none", UP.Skills[skill].ranks[rank].source, label .. ": " .. skill)
        end
      end
    end)
  end)

  it("max Growl whenever they take it", function()
    each(function(_, preset, label)
      local growl = preset.skills.Growl
      assert.is_true(growl == nil or growl == 7, label)
    end)
  end)
end)
