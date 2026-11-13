-- Build logic with no frames or game API calls.
-- A build is { family = "Cat", level = 60, loyalty = 6, skills = { ["Bite"] = 8, ... } }.
-- Skill names are the keys of UP.Skills; a rank of 0 (or no entry) means the skill isn't taken.
local _, UP = ...

local Planner = UP.Planner or {}
UP.Planner = Planner

-- Pets can only use this many active abilities at once. Shown, not enforced.
Planner.MAX_ACTIVE = 4
Planner.MAX_LEVEL = 60
Planner.MAX_LOYALTY = 6
Planner.DEFAULT_TEACHERS = 8

-- Loyalty names as C_PetInfo.GetPetLoyalty() returns them on Forever, lower-cased.
Planner.LOYALTY_NAMES = {
  ["rebellious"] = 1, ["unruly"] = 2, ["submissive"] = 3,
  ["dependable"] = 4, ["faithful"] = 5, ["best friend"] = 6,
}

-- Total TP for a pet level and loyalty level: level * (loyalty - 1), never below 0.
function Planner.Budget(level, loyalty)
  return math.max(0, (tonumber(level) or 0) * ((tonumber(loyalty) or 1) - 1))
end

-- Returns loyalty as 1-6 from a number, a name ("Faithful"), text with a digit, or nil.
-- When the value can't be read, derives it from total TP and pet level if that divides evenly.
function Planner.LoyaltyLevel(value, total, petLevel)
  local n = tonumber(value)
  if n and n >= 1 and n <= Planner.MAX_LOYALTY and n == math.floor(n) then return n end
  if type(value) == "string" then
    local name = value:lower():match("^%s*(.-)%s*$")
    if Planner.LOYALTY_NAMES[name] then return Planner.LOYALTY_NAMES[name] end
    local digit = tonumber(value:match("%d+"))
    if digit and digit >= 1 and digit <= Planner.MAX_LOYALTY then return digit end
  end
  total, petLevel = tonumber(total), tonumber(petLevel)
  if total and petLevel and petLevel > 0 and total >= 0 and total % petLevel == 0 then
    local derived = total / petLevel + 1
    if derived <= Planner.MAX_LOYALTY then return derived end
  end
  return nil
end

local function rankData(skill, rank)
  local s = UP.Skills[skill]
  return s and s.ranks[rank] or nil
end

local function eachTaken(build, fn)
  for skill, rank in pairs(build and build.skills or {}) do
    if type(rank) == "number" and rank > 0 then fn(skill, rank) end
  end
end

-- Known TP of the build's chosen ranks, and how many chosen ranks have unknown TP.
function Planner.Cost(build)
  local known, unknown = 0, 0
  eachTaken(build, function(skill, rank)
    local r = rankData(skill, rank)
    if r and r.tp then
      known = known + r.tp
    elseif r then
      unknown = unknown + 1
    end
  end)
  return known, unknown
end

function Planner.ActiveCount(build)
  local n = 0
  eachTaken(build, function(skill)
    local s = UP.Skills[skill]
    if s and s.active then n = n + 1 end
  end)
  return n
end

-- Problems with a build, as a list of { kind = "error" | "warn", msg = "..." } in SkillOrder order.
-- Errors: unknown family or skill, skill the family can't learn, rank out of range.
-- Warnings: a rank above the build's pet level.
function Planner.Validate(build)
  local problems = {}
  local function add(kind, msg) problems[#problems + 1] = { kind = kind, msg = msg } end
  local family = build and build.family
  if not UP.Families[family or ""] then add("error", "Unknown family: " .. tostring(family) .. ".") end
  local names = {}
  for skill in pairs(build and build.skills or {}) do names[#names + 1] = skill end
  table.sort(names, function(a, b) return Planner.SkillIndex(a) < Planner.SkillIndex(b) end)
  for _, skill in ipairs(names) do
    local rank, s = build.skills[skill], UP.Skills[skill]
    if not s then
      add("error", "Unknown skill: " .. tostring(skill) .. ".")
    elseif type(rank) ~= "number" or rank < 0 or rank ~= math.floor(rank) or rank > #s.ranks then
      add("error", skill .. " has " .. #s.ranks .. " ranks, not " .. tostring(rank) .. ".")
    elseif rank > 0 then
      if UP.Families[family or ""] and not s.families[family] then
        add("error", family .. " can't learn " .. skill .. ".")
      end
      if build.level and s.ranks[rank].level > build.level then
        add("warn", skill .. " " .. rank .. " needs pet level " .. s.ranks[rank].level .. ".")
      end
    end
  end
  return problems
end

-- Unknown skills sort last.
function Planner.SkillIndex(skill)
  if not Planner.skillIndex then
    Planner.skillIndex = {}
    for i, name in ipairs(UP.SkillOrder) do Planner.skillIndex[name] = i end
  end
  return Planner.skillIndex[skill] or math.huge
end

-- TP needed to go from knownRank to rank: tp[rank] - tp[knownRank]. Second return is true when
-- either cost is unknown, in which case the delta is 0.
function Planner.Delta(skill, rank, knownRank)
  local target = rankData(skill, rank)
  local from = (knownRank or 0) > 0 and rankData(skill, knownRank) or nil
  if not target or target.tp == nil or (from and from.tp == nil) then return 0, true end
  return target.tp - (from and from.tp or 0), false
end

-- Status of one rank of a skill for the summoned pet. ctx fields (all optional):
--   family    the build's family; the pet's known ranks only count when it equals petFamily
--             (nil = don't check)
--   petFamily, petLevel (default 0), unspent TP (default 0; may be negative)
--   known     { [skill] = highest rank the pet knows }
--   unlocked  { [skill] = { [rank] = true } }, the Beast Training set (same shape as UP.char.unlocked)
-- Returns nil for rank 0, else { code, rank, level, delta, tpUnknown, short }. code is one of
-- TRAINED, READY, NEED_LEVEL, NEED_TP, TRAINER, TRAINER_LEVEL, NO_SOURCE, LOCKED.
function Planner.Status(skill, rank, ctx)
  if not rank or rank <= 0 then return nil end
  local r = rankData(skill, rank)
  if not r then return nil end
  ctx = ctx or {}
  local petLevel, unspent = ctx.petLevel or 0, ctx.unspent or 0
  local sameFamily = ctx.family == nil or ctx.family == ctx.petFamily
  local knownRank = sameFamily and ctx.known and ctx.known[skill] or 0
  local delta, tpUnknown = Planner.Delta(skill, rank, knownRank)
  local out = { rank = rank, level = r.level, delta = delta, tpUnknown = tpUnknown or nil }
  local levelOk = petLevel >= r.level
  local unlocked = ctx.unlocked and ctx.unlocked[skill] and ctx.unlocked[skill][rank]

  if knownRank >= rank then
    out.code = "TRAINED"
  elseif r.source == "trainer" then
    out.code = levelOk and "TRAINER" or "TRAINER_LEVEL"
  elseif r.source == "none" and not unlocked then
    out.code = "NO_SOURCE"
  elseif unlocked and levelOk and delta <= unspent then
    out.code = "READY"
  elseif unlocked and not levelOk then
    out.code = "NEED_LEVEL"
  elseif unlocked then
    out.code, out.short = "NEED_TP", delta - unspent
  else
    out.code = "LOCKED"
  end
  return out
end

-- Up to `limit` (default 8) beasts that teach skill/rank, best first, as copies of the
-- UP.Beasts.npcs entries with an `id` field added.
function Planner.Teachers(skill, rank, limit)
  limit = limit or Planner.DEFAULT_TEACHERS
  local ids = (UP.Beasts.teach[skill] or {})[rank] or {}
  local out = {}
  for _, id in ipairs(ids) do
    if #out >= limit then break end
    local npc = UP.Beasts.npcs[id]
    if npc then
      local entry = { id = id }
      for k, v in pairs(npc) do entry[k] = v end
      out[#out + 1] = entry
    end
  end
  return out
end

-- Copies only the build fields, so a preset becomes a plain build.
function Planner.CopyBuild(build)
  local skills = {}
  for skill, rank in pairs(build.skills or {}) do skills[skill] = rank end
  return { family = build.family, level = build.level, loyalty = build.loyalty, skills = skills }
end

-- The preset named `name` for a family (default: its first preset, Raid DPS), or nil.
function Planner.Preset(family, name)
  for _, preset in ipairs(UP.Presets[family] or {}) do
    if name == nil or preset.name == name then return preset end
  end
  return nil
end
