-- UltimatePet: Scanner.lua
-- Reads the game: the Beast Training window (which ranks this hunter knows) and the active pet.
--
-- Public API
--   Scanner:ScanTrainer()           read the open trainer window; returns the number of pet ranks it matched
--   Scanner:ReadPet()               read the active pet now; returns UP.Scanner.pet
--   Scanner:RequestPetRead()        read the active pet after 0.2 s, coalescing bursts of events
--   Scanner:IsUnlocked(skill, rank) true when Beast Training has listed that rank
--   Scanner:HasScanned()            true once Beast Training has been read on this character
--   Scanner:Context()               state for Planner.Status (shape below)
--   Scanner:DebugDump()             list of strings describing the last pet read and trainer scan
--   Scanner:SkillOfSpell(spellId)   skill name, rank for a spell id in Data/Skills.lua; nil otherwise
--
-- Scanner.pet (always a table; exists = false without a pet):
--   { exists, name, family, familyId, level, loyalty (1-6 or nil), loyaltyName, tpTotal, tpUsed,
--     unspent (tpTotal - tpUsed, may be negative on Forever), known = { [skill] = maxRank }, key }
--
-- Scanner:Context() returns a fresh table:
--   { hasPet    = boolean,
--     petLevel  = number (0 without a pet),
--     petFamily = English family name or nil,
--     unspent   = number (0 without a pet; may be negative),
--     loyalty   = number or nil,
--     known     = { [skill] = highest rank in the pet's spellbook },
--     unlocked  = { [skill] = { [rank] = true } } }   -- name-keyed, the per-character DB table itself
--
-- Saved per character (UP.char): unlocked[skill][rank] = true (only grows),
-- scannedAt = time() of the last Beast Training scan.
--
-- Approach learned from TrueshotLodge src/training.lua and Huntsworn Core/Pet.lua (MIT); re-implemented.
local _, UP = ...

local Scanner = UP.Scanner or {}
UP.Scanner = Scanner

local COALESCE_DELAY = 0.2
local MAX_UNMATCHED = 5

local LOYALTY_LEVELS = {
  rebellious = 1, unruly = 2, submissive = 3, dependable = 4, faithful = 5, ["best friend"] = 6,
}

-- Classic creature family ids, used when the client's family name is not one of ours (other languages).
local FAMILY_IDS = {
  [1] = "Wolf", [2] = "Cat", [3] = "Spider", [4] = "Bear", [5] = "Boar", [6] = "Crocolisk",
  [7] = "Carrion Bird", [8] = "Crab", [9] = "Gorilla", [11] = "Raptor", [12] = "Tallstrider",
  [20] = "Scorpid", [21] = "Turtle", [24] = "Bat", [25] = "Hyena", [26] = "Bird of Prey",
  [27] = "Wind Serpent", [45] = "Core Hound", -- 45: CreatureFamily id from later clients, unverified on Forever
  [319] = "Fox", -- from TrueshotLodge data/Families.lua
}
local FAMILY_ALIASES = { Owl = "Bird of Prey" }

local TRAINER_STATUSES = { used = true, available = true, unavailable = true, header = true }

Scanner.pet = { exists = false, known = {} }
Scanner.lastScan = nil
Scanner.lastPetRead = nil

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local lookup, call = UP.lookup, UP.call

-- The first of several dotted paths that exists, called.
local function callFirst(paths, ...)
  for _, path in ipairs(paths) do
    if type(lookup(path)) == "function" then return call(path, ...) end
  end
end

local function trainerCall(name, ...)
  return callFirst({ name, "C_Trainer." .. name }, ...)
end

local function digit(text)
  return type(text) == "string" and tonumber(text:match("%d+")) or nil
end

local function now()
  if type(time) == "function" then return time() end
  return os and os.time and os.time() or 0
end

-- spellId -> { skill, rank } and lowercase English name -> skill, built from Data/Skills.lua once.
local bySpell, byName
local function buildIndex()
  if bySpell then return end
  bySpell, byName = {}, {}
  for skill, def in pairs(UP.Skills or {}) do
    byName[skill:lower()] = skill
    for rank, info in pairs(def.ranks or {}) do
      if type(info) == "table" and info.spellId then
        bySpell[info.spellId] = { skill = skill, rank = rank }
      end
    end
  end
end

function Scanner:SkillOfSpell(spellId)
  buildIndex()
  local entry = spellId and bySpell[tonumber(spellId)]
  if entry then return entry.skill, entry.rank end
end

-- Skill and rank from an English name and rank text ("Rank 3"); the fallback when there is no spell id.
local function skillOfName(name, rankText)
  buildIndex()
  if type(name) ~= "string" then return end
  local base = name:gsub("%s*%(.-%)%s*$", "")
  local skill = byName[base:lower()]
  if not skill then return end
  local ranks = UP.Skills[skill].ranks or {}
  local rank = digit(rankText) or digit(name:match("%((.-)%)"))
  if not rank and not ranks[2] then rank = 1 end -- a single-rank skill needs no rank text
  if rank and ranks[rank] then return skill, rank end
end

local function char()
  return UP.char
end

-- ---------------------------------------------------------------------------
-- Beast Training
-- ---------------------------------------------------------------------------

-- Beast Training opens with no npc (at most a targeted beast); a pet trainer or stable master is an npc.
local function isBeastTraining()
  local exists = call("UnitExists", "npc")
  if not exists then return true end
  if call("UnitCreatureFamily", "npc") then return true end
  return call("UnitCreatureType", "npc") == "Beast"
end

-- Name, rank text and status of trainer entry i, from either the multi-value or the table form.
local function serviceInfo(i)
  local name, second, third = trainerCall("GetTrainerServiceInfo", i)
  if type(name) == "table" then
    local t = name
    name = t.serviceName or t.name
    second = t.serviceSubText or t.subText or t.rank
    third = t.serviceType or t.type or t.status or t.category
  end
  local rankText, status = second, third
  if TRAINER_STATUSES[second] then
    rankText, status = nil, second
  end
  if type(status) ~= "string" then status = nil end
  if type(rankText) ~= "string" then rankText = nil end
  return name, rankText, status
end

local function serviceSpellId(i)
  local link = trainerCall("GetTrainerServiceItemLink", i)
  local id = type(link) == "string" and tonumber(link:match("spell:(%d+)")) or nil
  if id then return id end
  local data = call("C_TooltipInfo.GetTrainerService", i)
  if type(data) == "table" and type(data.id) == "number" then return data.id end
end

local function countUnlocked(unlocked)
  local n = 0
  for _, ranks in pairs(unlocked) do
    for _, v in pairs(ranks) do
      if v then n = n + 1 end
    end
  end
  return n
end

function Scanner:ScanTrainer()
  local db = char()
  local n = tonumber((trainerCall("GetNumTrainerServices"))) or 0
  local beast = isBeastTraining()
  local scan = { at = now(), services = n, beast = beast, matched = 0, learned = 0, unmatched = {}, unmatchedCount = 0 }
  self.lastScan = scan

  local learned = {}
  for i = 1, n do
    local name, rankText, status = serviceInfo(i)
    if name and status ~= "header" then
      local spellId = serviceSpellId(i)
      local skill, rank
      if spellId then skill, rank = self:SkillOfSpell(spellId) end
      -- The link may carry a different spell id than the pet spell; fall back to the name.
      if not skill then skill, rank = skillOfName(name, rankText) end
      if skill then
        scan.matched = scan.matched + 1
        if beast or status == "used" then
          learned[#learned + 1] = { skill, rank }
        end
      else
        scan.unmatchedCount = scan.unmatchedCount + 1
        if #scan.unmatched < MAX_UNMATCHED then
          scan.unmatched[#scan.unmatched + 1] = tostring(name) .. (spellId and (" #" .. spellId) or "")
        end
      end
    end
  end
  scan.learned = #learned

  -- The class trainer or any window without pet abilities: nothing to save.
  if scan.matched == 0 or not db then return 0 end

  db.unlocked = type(db.unlocked) == "table" and db.unlocked or {}
  for _, e in ipairs(learned) do
    local ranks = db.unlocked[e[1]] or {}
    db.unlocked[e[1]] = ranks
    ranks[e[2]] = true
  end
  db.scannedAt = scan.at
  scan.known = countUnlocked(db.unlocked)

  if not self.syncAnnounced then
    self.syncAnnounced = true
    UP:Print("Beast Training synced: " .. scan.known .. " ranks known.")
  end
  UP:Fire("STATE_CHANGED")
  return scan.matched
end

function Scanner:IsUnlocked(skill, rank)
  local db = char()
  local ranks = db and type(db.unlocked) == "table" and db.unlocked[skill]
  return type(ranks) == "table" and ranks[rank] == true
end

function Scanner:HasScanned()
  local db = char()
  return db ~= nil and db.scannedAt ~= nil
end

-- ---------------------------------------------------------------------------
-- Active pet
-- ---------------------------------------------------------------------------

local function familyName(name, id)
  local families = UP.Families or {}
  if name and families[name] then return name end
  if name and FAMILY_ALIASES[name] then return FAMILY_ALIASES[name] end
  if id and FAMILY_IDS[id] then return FAMILY_IDS[id] end
  return name
end

local function loyaltyLevel(text, total, level)
  if type(text) == "number" then return text end
  if type(text) == "string" then
    local lower = text:lower()
    if LOYALTY_LEVELS[lower] then return LOYALTY_LEVELS[lower] end
    for word, value in pairs(LOYALTY_LEVELS) do
      if lower:find(word, 1, true) then return value end
    end
    local d = digit(text)
    if d and d >= 1 and d <= 6 then return d end
  end
  -- The pet's total TP is level * (loyalty - 1).
  if type(total) == "number" and type(level) == "number" and level > 0 and total >= 0 then
    local l = total / level + 1
    if l == math.floor(l) and l >= 1 and l <= 6 then return l end
  end
end

-- A key that stays the same across summons: the stable's petNumber, else name and family.
-- (A pet's GUID changes on every summon, so it isn't used.)
local function petKey(name, family)
  local list = call("C_StableInfo.GetActivePetList")
  if type(list) == "table" then
    for _, info in pairs(list) do
      if type(info) == "table" and info.name == name and info.petNumber then return info.petNumber end
    end
  end
  if name then return tostring(name) .. "|" .. tostring(family) end
  return nil
end

local function readSpellbook()
  local known = {}
  local count = tonumber((call("C_SpellBook.HasPetSpells"))) or 0
  local bank = lookup("Enum.SpellBookSpellBank.Pet") or 1
  local unmatched = 0
  for i = 1, count do
    local info = call("C_SpellBook.GetSpellBookItemInfo", i, bank)
    if type(info) == "table" then
      local id = info.spellID or info.actionID
      local skill, rank = Scanner:SkillOfSpell(id)
      if not skill and info.name then skill, rank = skillOfName(info.name, info.subName) end
      if skill then
        if not known[skill] or rank > known[skill] then known[skill] = rank end
      else
        unmatched = unmatched + 1
      end
    end
  end
  return known, count, unmatched
end

local function samePet(a, b)
  for _, k in ipairs({ "exists", "name", "family", "familyId", "level", "loyalty", "loyaltyName",
                       "tpTotal", "tpUsed", "unspent", "key" }) do
    if a[k] ~= b[k] then return false end
  end
  for k, v in pairs(a.known or {}) do
    if b.known[k] ~= v then return false end
  end
  for k in pairs(b.known or {}) do
    if a.known[k] == nil then return false end
  end
  return true
end

local function buildPet()
  if not call("UnitExists", "pet") then
    return { exists = false, known = {} }
  end
  local pet = { exists = true }
  pet.name = call("UnitName", "pet")
  local famName, famId = call("UnitCreatureFamily", "pet")
  pet.familyId = tonumber(famId)
  pet.family = familyName(famName, pet.familyId)
  pet.familyKnown = pet.family ~= nil and (UP.Families or {})[pet.family] ~= nil
  pet.level = tonumber((call("UnitLevel", "pet")))
  local total, used = callFirst({ "C_PetInfo.GetPetTrainingPoints", "GetPetTrainingPoints" })
  pet.tpTotal, pet.tpUsed = tonumber(total), tonumber(used)
  if pet.tpTotal then pet.unspent = pet.tpTotal - (pet.tpUsed or 0) end
  local loyaltyText = callFirst({ "C_PetInfo.GetPetLoyalty", "GetPetLoyalty" })
  pet.loyaltyName = type(loyaltyText) == "string" and loyaltyText or nil
  pet.loyalty = loyaltyLevel(loyaltyText, pet.tpTotal, pet.level)
  local spellCount, unmatched
  pet.known, spellCount, unmatched = readSpellbook()
  pet.key = petKey(pet.name, pet.family)
  return pet, spellCount, unmatched
end

function Scanner:ReadPet()
  local ok, pet, spellCount, unmatched = pcall(buildPet)
  if not ok or type(pet) ~= "table" then
    self.lastPetRead = { at = call("GetTime"), error = tostring(pet) }
    return self.pet
  end
  self.lastPetRead = { at = call("GetTime"), spells = spellCount or 0, unmatched = unmatched or 0 }
  local changed = not samePet(self.pet, pet)
  self.pet = pet
  if changed then UP:Fire("STATE_CHANGED") end
  return pet
end

function Scanner:RequestPetRead()
  if self.petReadPending then return end
  self.petReadPending = true
  local after = lookup("C_Timer.After")
  local function run()
    self.petReadPending = false
    self:ReadPet()
  end
  if type(after) ~= "function" or not pcall(after, COALESCE_DELAY, run) then
    run()
  end
end

-- ---------------------------------------------------------------------------
-- Planner context and debug output
-- ---------------------------------------------------------------------------

function Scanner:Context()
  local pet = self.pet or {}
  local db = char()
  local known = {}
  for k, v in pairs(pet.known or {}) do known[k] = v end
  return {
    hasPet = pet.exists == true,
    petLevel = pet.level or 0,
    petFamily = pet.family,
    unspent = pet.unspent or 0,
    loyalty = pet.loyalty,
    known = known,
    unlocked = db and type(db.unlocked) == "table" and db.unlocked or {},
  }
end

function Scanner:DebugDump()
  local lines = {}
  local pet = self.pet or {}
  if pet.exists then
    local known = {}
    for skill, rank in pairs(pet.known or {}) do known[#known + 1] = skill .. " " .. rank end
    table.sort(known)
    lines[#lines + 1] = ("pet: %s, %s (id %s%s), level %s, loyalty %s (%s), TP %s/%s used, unspent %s, key %s")
      :format(tostring(pet.name), tostring(pet.family), tostring(pet.familyId),
        pet.familyKnown and "" or ", unknown family", tostring(pet.level), tostring(pet.loyalty),
        tostring(pet.loyaltyName), tostring(pet.tpUsed), tostring(pet.tpTotal), tostring(pet.unspent),
        tostring(pet.key))
    lines[#lines + 1] = "  spellbook: " .. (#known > 0 and table.concat(known, ", ") or "none")
  else
    lines[#lines + 1] = "pet: none"
  end
  local read = self.lastPetRead
  if read then
    lines[#lines + 1] = read.error and ("  last pet read failed: " .. read.error)
      or ("  last pet read: " .. read.spells .. " spellbook entries, " .. read.unmatched .. " not pet skills")
  end

  local scan = self.lastScan
  if scan then
    lines[#lines + 1] = ("trainer scan: %s, %d services, %d pet ranks matched, %d learned, %d unmatched")
      :format(scan.beast and "Beast Training" or "pet trainer", scan.services, scan.matched, scan.learned,
        scan.unmatchedCount)
    if #scan.unmatched > 0 then
      lines[#lines + 1] = "  unmatched: " .. table.concat(scan.unmatched, ", ")
    end
  else
    lines[#lines + 1] = "trainer scan: none this session"
  end
  local db = char()
  lines[#lines + 1] = "saved: " .. (db and type(db.unlocked) == "table" and countUnlocked(db.unlocked) or 0)
    .. " ranks unlocked, last scan " .. tostring(db and db.scannedAt or "never")
  return lines
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

-- Not every client has every event; RegisterEvent errors on an unknown one.
local function on(event, fn)
  return pcall(UP.On, UP, event, fn)
end

local function scanTrainer()
  local ok, err = pcall(Scanner.ScanTrainer, Scanner)
  if not ok then Scanner.lastScan = { error = tostring(err), services = 0, matched = 0, learned = 0,
    unmatched = {}, unmatchedCount = 0 } end
end
on("TRAINER_SHOW", scanTrainer)
on("TRAINER_UPDATE", scanTrainer)

local function request() Scanner:RequestPetRead() end
on("UNIT_PET", function(unit) if unit == "player" then request() end end)
on("UNIT_LEVEL", function(unit) if unit == "pet" then request() end end)
for _, event in ipairs({ "PET_BAR_UPDATE", "PET_UI_UPDATE", "UNIT_PET_TRAINING_POINTS", "PET_TRAINING_POINTS",
                         "SPELLS_CHANGED" }) do
  on(event, request)
end

on("PLAYER_ENTERING_WORLD", function()
  request()
  if Scanner.nagShown then return end
  local _, class = call("UnitClass", "player")
  local db = char()
  if class == "HUNTER" and db and db.scannedAt == nil then
    Scanner.nagShown = true
    UP:Print("Open your Beast Training window once so UltimatePet can see which ranks you know.")
  end
end)
