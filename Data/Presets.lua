-- UltimatePet: Data/Presets.lua
-- Suggested level 60 builds per family (Best Friend, 300 TP). Hand-authored, not generated.
-- These are community-style suggestions, not authoritative. tests/presets_spec.lua checks that each
-- one fits 300 known TP, uses at most 4 actives and only skills and ranks the family can learn.
-- Ranks with no known source are avoided (the highest taught rank is used instead), except Lava
-- Breath, which has no source at all.
local _, UP = ...

local UNKNOWN = " Includes abilities with unknown TP cost."

-- One preset: level 60, Best Friend.
local function preset(name, role, skills, note)
  return { name = name, role = role, level = 60, loyalty = 6, skills = skills, note = note }
end

local RAID, LEVEL, PVP = "Raid DPS", "Leveling / Solo Tank", "PvP"
local FIRE, NATURE = "Fire Resistance", "Nature Resistance"

UP.Presets = {
  ["Bat"] = {
    preset(RAID, "raid", { Bite = 8, Dive = 3, Growl = 7, ["Great Stamina"] = 9, ["Natural Armor"] = 8 },
      "Max Bite, Dive for gap closing, rest into Stamina and Armor."),
    preset(LEVEL, "leveling", { Bite = 8, Dive = 1, Growl = 7, ["Great Stamina"] = 10, ["Natural Armor"] = 7 },
      "Max Bite and Growl, Stamina first, Dive 1 for speed."),
    preset(PVP, "pvp", { Bite = 8, Dive = 3, ["Sonic Blast"] = 3, ["Great Stamina"] = 9, ["Natural Armor"] = 8 },
      "Bite, Dive and Sonic Blast. No Growl." .. UNKNOWN),
    preset(FIRE, "resist", { Bite = 8, Dive = 3, Growl = 7, ["Fire Resistance"] = 4, ["Great Stamina"] = 9,
      ["Natural Armor"] = 3 }, "Fire Resistance 4 for fire raids, rest into Stamina."),
  },
  ["Bear"] = {
    preset(RAID, "raid", { Bite = 8, Claw = 8, Dash = 3, Growl = 7, ["Great Stamina"] = 9, ["Natural Armor"] = 7 },
      "Max Bite and Claw, Dash for gap closing, rest into Stamina and Armor."),
    preset(LEVEL, "leveling", { Bite = 8, Claw = 8, Swipe = 2, Growl = 7, ["Great Stamina"] = 10,
      ["Natural Armor"] = 6 }, "Bite, Claw and Swipe for threat on groups, max Stamina." .. UNKNOWN),
    preset(PVP, "pvp", { Bite = 8, Claw = 8, Dash = 3, ["Great Stamina"] = 9, ["Natural Armor"] = 7 },
      "Max Bite and Claw, Dash to stay on target. No Growl."),
    preset(FIRE, "resist", { Bite = 8, Claw = 8, Growl = 7, ["Fire Resistance"] = 4, ["Great Stamina"] = 9,
      ["Natural Armor"] = 3 }, "Fire Resistance 4 for fire raids, rest into Stamina."),
  },
  ["Bird of Prey"] = {
    preset(RAID, "raid", { Claw = 8, Dive = 3, Growl = 7, ["Great Stamina"] = 9, ["Natural Armor"] = 8 },
      "Max Claw, Dive for gap closing, rest into Stamina and Armor."),
    preset(LEVEL, "leveling", { Claw = 8, Dive = 1, Growl = 7, ["Great Stamina"] = 10, ["Natural Armor"] = 7 },
      "Max Claw and Growl, Stamina first, Dive 1 for speed."),
    preset(PVP, "pvp", { Claw = 8, Dive = 3, ["Mine!"] = 1, ["Great Stamina"] = 9, ["Natural Armor"] = 8 },
      "Claw, Dive and Mine! to disarm. No Growl." .. UNKNOWN),
    preset(FIRE, "resist", { Claw = 8, Dive = 3, Growl = 7, ["Fire Resistance"] = 4, ["Great Stamina"] = 9,
      ["Natural Armor"] = 3 }, "Fire Resistance 4 for fire raids, rest into Stamina."),
  },
  ["Boar"] = {
    preset(RAID, "raid", { Bite = 8, Charge = 6, Dash = 3, Growl = 7, ["Great Stamina"] = 9, ["Natural Armor"] = 7 },
      "Max Bite and Charge, Dash for gap closing, rest into Stamina and Armor."),
    preset(LEVEL, "leveling", { Bite = 8, Charge = 6, Dash = 1, Growl = 7, ["Great Stamina"] = 10,
      ["Natural Armor"] = 6 }, "Charge in, max Bite and Growl, Stamina first."),
    preset(PVP, "pvp", { Bite = 8, Charge = 6, Dash = 3, ["Great Stamina"] = 9, ["Natural Armor"] = 7 },
      "Charge to root, Dash to catch runners. No Growl."),
    preset(FIRE, "resist", { Bite = 8, Charge = 6, Growl = 7, ["Fire Resistance"] = 4, ["Great Stamina"] = 9,
      ["Natural Armor"] = 3 }, "Fire Resistance 4 for fire raids, rest into Stamina."),
  },
  ["Carrion Bird"] = {
    preset(RAID, "raid", { Bite = 8, Claw = 8, Dive = 3, Growl = 7, ["Great Stamina"] = 9, ["Natural Armor"] = 7 },
      "Max Bite and Claw, Dive for gap closing, rest into Stamina and Armor."),
    preset(LEVEL, "leveling", { Bite = 8, Claw = 8, ["Demoralizing Screech"] = 3, Growl = 7,
      ["Great Stamina"] = 9, ["Natural Armor"] = 7 }, "Bite, Claw and Demoralizing Screech to cut enemy damage."),
    preset(PVP, "pvp", { Bite = 8, Claw = 8, Dive = 3, ["Demoralizing Screech"] = 3, ["Great Stamina"] = 9,
      ["Natural Armor"] = 6 }, "Max Bite and Claw, Dive and Demoralizing Screech. No Growl."),
    preset(FIRE, "resist", { Bite = 8, Claw = 8, Growl = 7, ["Fire Resistance"] = 4, ["Great Stamina"] = 9,
      ["Natural Armor"] = 3 }, "Fire Resistance 4 for fire raids, rest into Stamina."),
  },
  ["Cat"] = {
    preset(RAID, "raid", { Bite = 8, Claw = 8, Dash = 3, Growl = 7, ["Great Stamina"] = 9, ["Natural Armor"] = 7 },
      "Max Bite and Claw, Dash for gap closing, rest into Stamina and Armor."),
    preset(LEVEL, "leveling", { Bite = 8, Claw = 8, Dash = 1, Growl = 7, ["Great Stamina"] = 10,
      ["Natural Armor"] = 6 }, "Max Bite, Claw and Growl, Stamina first, Dash 1 for speed."),
    preset(PVP, "pvp", { Bite = 8, Claw = 8, Dash = 3, Prowl = 3, ["Great Stamina"] = 9, ["Natural Armor"] = 6 },
      "Prowl to open, max Bite and Claw, Dash to stay on target. No Growl."),
    preset(FIRE, "resist", { Bite = 8, Claw = 8, Growl = 7, ["Fire Resistance"] = 4, ["Great Stamina"] = 9,
      ["Natural Armor"] = 3 }, "Fire Resistance 4 for fire raids, rest into Stamina."),
  },
  ["Core Hound"] = {
    preset(RAID, "raid", { Bite = 8, ["Lava Breath"] = 2, Growl = 7, ["Great Stamina"] = 9, ["Natural Armor"] = 9 },
      "Max Bite and Lava Breath, rest into Stamina and Armor. Lava Breath has no known source yet." .. UNKNOWN),
    preset(LEVEL, "leveling", { Bite = 8, Growl = 7, ["Great Stamina"] = 10, ["Natural Armor"] = 7 },
      "Max Bite and Growl, Stamina first."),
    preset(PVP, "pvp", { Bite = 8, ["Lava Breath"] = 2, ["Great Stamina"] = 9, ["Natural Armor"] = 9 },
      "Bite and Lava Breath. No Growl. Lava Breath has no known source yet." .. UNKNOWN),
    preset(FIRE, "resist", { Bite = 8, Growl = 7, ["Fire Resistance"] = 4, ["Great Stamina"] = 10 },
      "Fire Resistance 4 for fire raids, max Stamina."),
  },
  ["Crab"] = {
    preset(RAID, "raid", { Claw = 8, Dash = 3, Growl = 7, ["Great Stamina"] = 9, ["Natural Armor"] = 8 },
      "Max Claw, Dash for gap closing, rest into Stamina and Armor."),
    preset(LEVEL, "leveling", { Claw = 8, Pinch = 2, Dash = 1, Growl = 7, ["Great Stamina"] = 10,
      ["Natural Armor"] = 7 }, "Claw and Pinch, max Growl, Stamina first." .. UNKNOWN),
    preset(PVP, "pvp", { Claw = 8, Dash = 3, Pinch = 2, ["Great Stamina"] = 9, ["Natural Armor"] = 8 },
      "Claw and Pinch, Dash to stay on target. No Growl." .. UNKNOWN),
    preset(FIRE, "resist", { Claw = 8, Dash = 3, Growl = 7, ["Fire Resistance"] = 4, ["Great Stamina"] = 9,
      ["Natural Armor"] = 3 }, "Fire Resistance 4 for fire raids, rest into Stamina."),
  },
  ["Crocolisk"] = {
    preset(RAID, "raid", { Bite = 8, Dismember = 3, Dash = 3, Growl = 7, ["Great Stamina"] = 9,
      ["Natural Armor"] = 8 }, "Max Bite, Dismember, Dash for gap closing, rest into Stamina." .. UNKNOWN),
    preset(LEVEL, "leveling", { Bite = 8, Dash = 1, Growl = 7, ["Great Stamina"] = 10, ["Natural Armor"] = 7 },
      "Max Bite and Growl, Stamina first, Dash 1 for speed."),
    preset(PVP, "pvp", { Bite = 8, Dash = 3, Dismember = 3, ["Great Stamina"] = 9, ["Natural Armor"] = 8 },
      "Bite and Dismember, Dash to stay on target. No Growl." .. UNKNOWN),
    preset(NATURE, "resist", { Bite = 8, Dash = 3, Growl = 7, ["Nature Resistance"] = 4, ["Great Stamina"] = 9,
      ["Natural Armor"] = 3 }, "Nature Resistance 4 for nature fights (AQ, Hakkar), rest into Stamina."),
  },
  ["Fox"] = {
    preset(RAID, "raid", { Bite = 8, Dash = 3, Growl = 7, ["Great Stamina"] = 9, ["Natural Armor"] = 8 },
      "Max Bite, Dash for gap closing, rest into Stamina and Armor."),
    preset(LEVEL, "leveling", { Bite = 8, Dash = 1, Growl = 7, ["Great Stamina"] = 10, ["Natural Armor"] = 7 },
      "Max Bite and Growl, Stamina first, Dash 1 for speed."),
    preset(PVP, "pvp", { Bite = 8, Dash = 3, ["Trickster's Dance"] = 1, ["Great Stamina"] = 9,
      ["Natural Armor"] = 8 }, "Bite, Dash and Trickster's Dance. No Growl." .. UNKNOWN),
    preset(FIRE, "resist", { Bite = 8, Dash = 3, Growl = 7, ["Fire Resistance"] = 4, ["Great Stamina"] = 9,
      ["Natural Armor"] = 3 }, "Fire Resistance 4 for fire raids, rest into Stamina."),
  },
  ["Gorilla"] = {
    preset(RAID, "raid", { Bite = 8, Dash = 3, Growl = 7, ["Great Stamina"] = 9, ["Natural Armor"] = 8 },
      "Max Bite, Dash for gap closing, rest into Stamina and Armor. No Thunderstomp, it hits groups."),
    preset(LEVEL, "leveling", { Bite = 8, Thunderstomp = 3, Dash = 1, Growl = 7, ["Great Stamina"] = 10,
      ["Natural Armor"] = 6 }, "Thunderstomp for threat on groups, max Bite and Growl, Stamina first."),
    preset(PVP, "pvp", { Bite = 8, Dash = 3, Thunderstomp = 3, ["Great Stamina"] = 9, ["Natural Armor"] = 7 },
      "Bite, Thunderstomp, Dash to stay on target. No Growl."),
    preset(FIRE, "resist", { Bite = 8, Dash = 3, Growl = 7, ["Fire Resistance"] = 4, ["Great Stamina"] = 9,
      ["Natural Armor"] = 3 }, "Fire Resistance 4 for fire raids, rest into Stamina."),
  },
  ["Hyena"] = {
    preset(RAID, "raid", { Bite = 8, Dash = 3, Growl = 7, ["Great Stamina"] = 9, ["Natural Armor"] = 8 },
      "Max Bite, Dash for gap closing, rest into Stamina and Armor."),
    preset(LEVEL, "leveling", { Bite = 8, Dash = 1, Growl = 7, ["Great Stamina"] = 10, ["Natural Armor"] = 7 },
      "Max Bite and Growl, Stamina first, Dash 1 for speed."),
    preset(PVP, "pvp", { Bite = 8, Dash = 3, ["Tendon Rip"] = 2, ["Great Stamina"] = 9, ["Natural Armor"] = 8 },
      "Bite, Dash and Tendon Rip to slow. No Growl." .. UNKNOWN),
    preset(FIRE, "resist", { Bite = 8, Dash = 3, Growl = 7, ["Fire Resistance"] = 4, ["Great Stamina"] = 9,
      ["Natural Armor"] = 3 }, "Fire Resistance 4 for fire raids, rest into Stamina."),
  },
  ["Raptor"] = {
    preset(RAID, "raid", { Bite = 8, Claw = 8, ["Savage Rend"] = 3, Growl = 7, ["Great Stamina"] = 9,
      ["Natural Armor"] = 8 }, "Max Bite and Claw, Savage Rend, rest into Stamina and Armor." .. UNKNOWN),
    preset(LEVEL, "leveling", { Bite = 8, Claw = 8, Dash = 1, Growl = 7, ["Great Stamina"] = 10,
      ["Natural Armor"] = 6 }, "Max Bite, Claw and Growl, Stamina first, Dash 1 for speed."),
    preset(PVP, "pvp", { Bite = 8, Claw = 8, Dash = 3, ["Savage Rend"] = 3, ["Great Stamina"] = 9,
      ["Natural Armor"] = 7 }, "Max Bite and Claw, Savage Rend, Dash to stay on target. No Growl." .. UNKNOWN),
    preset(FIRE, "resist", { Bite = 8, Claw = 8, Growl = 7, ["Fire Resistance"] = 4, ["Great Stamina"] = 9,
      ["Natural Armor"] = 3 }, "Fire Resistance 4 for fire raids, rest into Stamina."),
  },
  ["Scorpid"] = {
    preset(RAID, "raid", { Claw = 8, ["Scorpid Poison"] = 4, Dash = 3, Growl = 7, ["Great Stamina"] = 9,
      ["Natural Armor"] = 7 }, "Max Claw and Scorpid Poison, Dash for gap closing, rest into Stamina."),
    preset(LEVEL, "leveling", { Claw = 8, ["Scorpid Poison"] = 4, Dash = 1, Growl = 7, ["Great Stamina"] = 10,
      ["Natural Armor"] = 6 }, "Max Claw, Scorpid Poison and Growl, Stamina first."),
    preset(PVP, "pvp", { Claw = 8, ["Scorpid Poison"] = 4, Dash = 3, ["Great Stamina"] = 9, ["Natural Armor"] = 7 },
      "Max Claw and Scorpid Poison, Dash to stay on target. No Growl."),
    preset(NATURE, "resist", { Claw = 8, ["Scorpid Poison"] = 4, Growl = 7, ["Nature Resistance"] = 4,
      ["Great Stamina"] = 9, ["Natural Armor"] = 3 },
      "Nature Resistance 4 for nature fights (AQ, Hakkar), rest into Stamina."),
  },
  ["Spider"] = {
    preset(RAID, "raid", { Bite = 8, Dash = 3, Growl = 7, ["Great Stamina"] = 9, ["Natural Armor"] = 8 },
      "Max Bite, Dash for gap closing, rest into Stamina and Armor."),
    preset(LEVEL, "leveling", { Bite = 8, Dash = 1, Growl = 7, ["Great Stamina"] = 10, ["Natural Armor"] = 7 },
      "Max Bite and Growl, Stamina first, Dash 1 for speed."),
    preset(PVP, "pvp", { Bite = 8, Dash = 3, Web = 2, ["Great Stamina"] = 9, ["Natural Armor"] = 8 },
      "Bite, Dash and Web to root. No Growl." .. UNKNOWN),
    preset(NATURE, "resist", { Bite = 8, Dash = 3, Growl = 7, ["Nature Resistance"] = 4, ["Great Stamina"] = 9,
      ["Natural Armor"] = 3 }, "Nature Resistance 4 for nature fights (AQ, Hakkar), rest into Stamina."),
  },
  ["Tallstrider"] = {
    preset(RAID, "raid", { Bite = 8, Dash = 3, Growl = 7, ["Great Stamina"] = 9, ["Natural Armor"] = 8 },
      "Max Bite, Dash for gap closing, rest into Stamina and Armor."),
    preset(LEVEL, "leveling", { Bite = 8, Dash = 1, Growl = 7, ["Great Stamina"] = 10, ["Natural Armor"] = 7 },
      "Max Bite and Growl, Stamina first, Dash 1 for speed."),
    preset(PVP, "pvp", { Bite = 8, Dash = 3, ["Dust Cloud"] = 2, ["Great Stamina"] = 9, ["Natural Armor"] = 8 },
      "Bite, Dash and Dust Cloud. No Growl." .. UNKNOWN),
    preset(FIRE, "resist", { Bite = 8, Dash = 3, Growl = 7, ["Fire Resistance"] = 4, ["Great Stamina"] = 9,
      ["Natural Armor"] = 3 }, "Fire Resistance 4 for fire raids, rest into Stamina."),
  },
  ["Turtle"] = {
    preset(RAID, "raid", { Bite = 8, Dash = 3, Growl = 7, ["Great Stamina"] = 9, ["Natural Armor"] = 8 },
      "Max Bite, Dash for gap closing, rest into Stamina and Armor."),
    preset(LEVEL, "leveling", { Bite = 8, ["Shell Shield"] = 1, Growl = 7, ["Great Stamina"] = 10,
      ["Natural Armor"] = 7 }, "Max Bite and Growl, Shell Shield for emergencies, Stamina first."),
    preset(PVP, "pvp", { Bite = 8, Dash = 3, ["Shell Shield"] = 1, ["Great Stamina"] = 9, ["Natural Armor"] = 7 },
      "Bite, Dash and Shell Shield. No Growl."),
    preset(FIRE, "resist", { Bite = 8, ["Shell Shield"] = 1, Growl = 7, ["Fire Resistance"] = 4,
      ["Great Stamina"] = 9, ["Natural Armor"] = 4 }, "Fire Resistance 4 for fire raids, rest into Stamina."),
  },
  ["Wind Serpent"] = {
    preset(RAID, "raid", { Bite = 8, Dive = 3, Growl = 7, ["Lightning Breath"] = 6, ["Great Stamina"] = 9,
      ["Natural Armor"] = 7 }, "Max Bite and Lightning Breath, Dive for gap closing, rest into Stamina."),
    preset(LEVEL, "leveling", { Bite = 8, Dive = 1, Growl = 7, ["Lightning Breath"] = 6, ["Great Stamina"] = 10,
      ["Natural Armor"] = 6 }, "Max Bite, Lightning Breath and Growl, Stamina first."),
    preset(PVP, "pvp", { Bite = 8, Dive = 3, ["Lightning Breath"] = 6, ["Great Stamina"] = 9,
      ["Natural Armor"] = 7 }, "Max Bite and Lightning Breath, Dive to stay on target. No Growl."),
    preset(FIRE, "resist", { Bite = 8, Growl = 7, ["Lightning Breath"] = 6, ["Fire Resistance"] = 4,
      ["Great Stamina"] = 9, ["Natural Armor"] = 3 }, "Fire Resistance 4 for fire raids, rest into Stamina."),
  },
  ["Wolf"] = {
    preset(RAID, "raid", { Bite = 8, Dash = 3, Growl = 7, ["Furious Howl"] = 4, ["Great Stamina"] = 9,
      ["Natural Armor"] = 7 }, "Max Bite and Furious Howl, Dash for gap closing, rest into Stamina."),
    preset(LEVEL, "leveling", { Bite = 8, Dash = 1, Growl = 7, ["Furious Howl"] = 4, ["Great Stamina"] = 10,
      ["Natural Armor"] = 6 }, "Max Bite, Furious Howl and Growl, Stamina first."),
    preset(PVP, "pvp", { Bite = 8, Dash = 3, ["Furious Howl"] = 4, ["Great Stamina"] = 9, ["Natural Armor"] = 7 },
      "Max Bite and Furious Howl, Dash to stay on target. No Growl."),
    preset(FIRE, "resist", { Bite = 8, Growl = 7, ["Furious Howl"] = 4, ["Fire Resistance"] = 4,
      ["Great Stamina"] = 9, ["Natural Armor"] = 3 }, "Fire Resistance 4 for fire raids, rest into Stamina."),
  },
}

-- Each preset carries its family so it can be used directly as a build.
for family, list in pairs(UP.Presets) do
  for _, p in ipairs(list) do p.family = family end
end
