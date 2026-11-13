-- Build strings: UP1:<FamilyNoSpaces>:<level>-<loyalty>:<Code><rank>,...
-- e.g. UP1:Cat:60-6:Bi8,Cl8,Da3,Gr7,GS9,NA7. Codes come from UP.SkillCodes; skills are written in
-- UP.SkillOrder order.
local _, UP = ...

local Serializer = UP.Serializer or {}
UP.Serializer = Serializer

Serializer.VERSION = 1

-- Family token: the family name without spaces ("Bird of Prey" -> "BirdofPrey").
local function familyToken(family)
  return (family:gsub("%s", ""))
end

function Serializer.Encode(build)
  local parts = {}
  for _, skill in ipairs(UP.SkillOrder) do
    local rank = build.skills and build.skills[skill]
    if type(rank) == "number" and rank > 0 then
      parts[#parts + 1] = UP.SkillCodes[skill] .. rank
    end
  end
  return ("UP%d:%s:%d-%d:%s"):format(Serializer.VERSION, familyToken(build.family),
    build.level, build.loyalty, table.concat(parts, ","))
end

-- Lower-cased lookups: family token -> family, code -> skill. Built on first use.
local lookups
local function getLookups()
  if lookups then return lookups end
  lookups = { family = {}, code = {} }
  for family in pairs(UP.Families) do lookups.family[familyToken(family):lower()] = family end
  for skill, code in pairs(UP.SkillCodes) do lookups.code[code:lower()] = skill end
  return lookups
end

-- Parses one "<Code><rank>" entry into build.skills. Returns an error string on failure.
local function decodeEntry(entry, build)
  local code, rank = entry:match("^(%a%a)(%d+)$")
  if not code then return "Bad skill entry: " .. entry .. "." end
  local skill = getLookups().code[code:lower()]
  if not skill then return "Unknown skill code: " .. code .. "." end
  if build.skills[skill] then return skill .. " is listed twice." end
  rank = tonumber(rank)
  local max = #UP.Skills[skill].ranks
  if rank < 1 or rank > max then return skill .. " has " .. max .. " ranks, not " .. rank .. "." end
  if not UP.Skills[skill].families[build.family] then return build.family .. " can't learn " .. skill .. "." end
  build.skills[skill] = rank
end

-- Decodes a build string. Returns true, build or false, error message. Whitespace anywhere and the
-- case of the prefix, family and codes are ignored.
function Serializer.Decode(str)
  if type(str) ~= "string" then return false, "Not an UltimatePet string." end
  str = str:gsub("%s", "")
  local version = str:match("^[Uu][Pp](%d+):")
  if not version then return false, "Not an UltimatePet string." end
  if tonumber(version) ~= Serializer.VERSION then
    return false, "Unsupported string version: UP" .. version .. "."
  end
  local token, level, loyalty, list = str:match("^%a%a%d+:([^:]*):(%d+)-(%d+):([^:]*)$")
  if not token then return false, "Malformed build string." end
  local family = getLookups().family[token:lower()]
  if not family then return false, "Unknown family: " .. token .. "." end
  level, loyalty = tonumber(level), tonumber(loyalty)
  if level < 1 or level > UP.Planner.MAX_LEVEL then return false, "Level must be 1-60, not " .. level .. "." end
  if loyalty < 1 or loyalty > UP.Planner.MAX_LOYALTY then
    return false, "Loyalty must be 1-6, not " .. loyalty .. "."
  end
  local build = { family = family, level = level, loyalty = loyalty, skills = {} }
  for entry in list:gmatch("[^,]+") do
    local err = decodeEntry(entry, build)
    if err then return false, err end
  end
  return true, build
end
