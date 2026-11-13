-- UltimatePet: Core.lua
-- Namespace, event dispatcher, SavedVariables defaults and migrations, slash commands.
local addonName, UP = ...

UP.name = addonName

local function metadata(field)
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  return get and get(addonName, field) or nil
end

UP.version = metadata("Version") or "dev"

-- ---------------------------------------------------------------------------
-- Output
-- ---------------------------------------------------------------------------

local PREFIX = "|cffabd473UltimatePet|r: "

function UP:Print(...)
  local parts = {}
  for i = 1, select("#", ...) do
    parts[#parts + 1] = tostring((select(i, ...)))
  end
  local msg = PREFIX .. table.concat(parts, " ")
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(msg)
  else
    print(msg)
  end
end

-- ---------------------------------------------------------------------------
-- Events and internal messages
-- ---------------------------------------------------------------------------
-- UP:On(name, fn) subscribes fn(...) to a game event or an internal message. Game events are
-- registered on the shared frame; names in UP.MESSAGES are internal and only reach handlers through
-- UP:Fire(name, ...). Handlers receive the event's arguments, not the event name.

UP.MESSAGES = {
  STATE_CHANGED = true, -- scanned data, the active pet or the DB changed; the UI refreshes
}

local handlers = {}
local frame = CreateFrame("Frame")
UP.frame = frame

local function dispatch(name, ...)
  local list = handlers[name]
  if not list then return end
  for i = 1, #list do
    list[i](...)
  end
end

frame:SetScript("OnEvent", function(_, event, ...)
  dispatch(event, ...)
end)

function UP:On(name, fn)
  assert(type(name) == "string" and type(fn) == "function", "UP:On(name, fn)")
  local list = handlers[name]
  if not list then
    list = {}
    handlers[name] = list
    if not UP.MESSAGES[name] then
      frame:RegisterEvent(name)
    end
  end
  list[#list + 1] = fn
end

function UP:Fire(name, ...)
  assert(UP.MESSAGES[name], "unknown internal message: " .. tostring(name))
  dispatch(name, ...)
end

-- ---------------------------------------------------------------------------
-- SavedVariables
-- ---------------------------------------------------------------------------

UP.DB_VERSION = 1

local GLOBAL_DEFAULTS = {
  minimap = { angle = 225, hide = false },
  frame = {},
}

local CHAR_DEFAULTS = {
  unlocked = {},   -- [skill][rank] = true, from the Beast Training window
  craftCosts = {}, -- [skill][rank] = { tp =, level = }, live overrides of bundled data
  builds = {},     -- [name] = build table
  petBuild = {},   -- [petName .. "|" .. family] = build name
  -- scannedAt: time of the last Beast Training scan; nil until the first one
}

-- Fills missing keys of t from defaults, recursing into tables; never overwrites a value.
local function applyDefaults(t, defaults)
  for k, v in pairs(defaults) do
    if type(v) == "table" then
      if type(t[k]) ~= "table" then t[k] = {} end
      applyDefaults(t[k], v)
    elseif t[k] == nil then
      t[k] = v
    end
  end
  return t
end

-- migrations[n] upgrades a DB at version n - 1 to version n. Version 0 is a fresh or unversioned
-- DB; the defaults fill in its shape, so migration 1 only has to drop anything that is not a table.
UP.migrations = {
  [1] = function(db)
    if type(db.global) ~= "table" then db.global = nil end
    if type(db.chars) ~= "table" then db.chars = nil end
  end,
}

function UP:CharKey()
  local name = UnitName and UnitName("player") or "Unknown"
  local realm = GetRealmName and GetRealmName() or "Unknown"
  return (name or "Unknown") .. "-" .. (realm or "Unknown")
end

function UP:InitDB()
  local db = type(UltimatePetDB) == "table" and UltimatePetDB or {}
  local from = tonumber(db.version) or 0
  if from > UP.DB_VERSION then
    UP:Print("saved data is from a newer version (" .. from .. "); some settings may be ignored.")
  end
  for v = from + 1, UP.DB_VERSION do
    UP.migrations[v](db)
    db.version = v
  end
  db.version = db.version or UP.DB_VERSION
  db.global = applyDefaults(type(db.global) == "table" and db.global or {}, GLOBAL_DEFAULTS)
  db.chars = type(db.chars) == "table" and db.chars or {}

  local key = UP:CharKey()
  db.chars[key] = applyDefaults(type(db.chars[key]) == "table" and db.chars[key] or {}, CHAR_DEFAULTS)

  UltimatePetDB = db
  UP.db, UP.char, UP.charKey = db, db.chars[key], key
  return db
end

-- Wipes the current character's data, or every character's and the global settings with `all`.
function UP:ResetDB(all)
  if all then
    UltimatePetDB = nil
  elseif UltimatePetDB and UltimatePetDB.chars then
    UltimatePetDB.chars[UP:CharKey()] = nil
  end
  UP:InitDB()
  UP:Fire("STATE_CHANGED")
end

UP:On("ADDON_LOADED", function(name)
  if name ~= addonName then return end
  UP:InitDB()
  UP.loaded = true
  UP:Fire("STATE_CHANGED")
end)

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------

-- APIs the scanner, waypoints and UI rely on; `/upet debug` reports which exist on this client.
UP.DEBUG_APIS = {
  -- Beast Training is the class trainer window on Forever
  "GetNumTrainerServices", "GetTrainerServiceInfo", "GetTrainerServiceItemLink", "GetTrainerServiceCost",
  "GetTrainerServiceLevelReq", "C_Trainer", "C_TooltipInfo.GetTrainerService",
  -- Classic craft API (missing on Forever 1.60)
  "GetCraftInfo", "GetNumCrafts",
  -- Pet state
  "C_PetInfo.GetPetTrainingPoints", "C_PetInfo.GetPetLoyalty", "GetPetTrainingPoints", "GetPetLoyalty",
  "UnitCreatureFamily", "C_StableInfo.GetActivePetList",
  -- Pet spellbook and icons
  "C_SpellBook.HasPetSpells", "C_SpellBook.GetSpellBookItemInfo", "C_SpellBook.GetSpellBookItemName",
  "Enum.SpellBookSpellBank", "C_Spell.GetSpellTexture", "C_Spell.GetSpellSubtext", "GetSpellTexture",
  -- Maps, UI, waypoints
  "C_Map.GetMapInfo", "C_Map.SetUserWaypoint", "UiMapPoint.CreateFromCoordinates",
  "C_Timer.After", "UIDropDownMenu_Initialize",
  "TomTom.AddWaypoint",
}

-- Calls a dotted global path and returns its results as one string, or nil if it's missing or errors.
local function probe(path, ...)
  local fn = UP.lookup(path)
  if type(fn) ~= "function" then return nil end
  local res = { pcall(fn, ...) }
  if not res[1] then return "error: " .. tostring(res[2]) end
  local out = {}
  for i = 2, table.maxn(res) do out[#out + 1] = tostring(res[i]) end
  return table.concat(out, ", ")
end

-- Looks up a dotted global path ("C_Map.GetMapInfo") without erroring on missing tables.
local function lookup(path)
  local value = _G
  for part in path:gmatch("[^%.]+") do
    if type(value) ~= "table" then return nil end
    value = value[part]
  end
  return value
end
UP.lookup = lookup

local function notImplemented(cmd)
  UP:Print("'" .. cmd .. "' is not implemented yet.")
end

local HELP = {
  "show - open the planner",
  "scan - rescan the active pet",
  "debug - list the game APIs this client provides",
  "export - print the current build string",
  "import <string> - load a build string",
  "reset [all] confirm - wipe this character's data (or everything with 'all')",
  "help - this list",
}

UP.commands = {
  help = function()
    UP:Print("v" .. UP.version .. " - /upet or /ultimatepet:")
    for _, line in ipairs(HELP) do
      UP:Print("  " .. line)
    end
  end,
  show = function() notImplemented("show") end,
  scan = function() notImplemented("scan") end,
  export = function() notImplemented("export") end,
  import = function(rest)
    if rest == "" then
      UP:Print("usage: /upet import <string>")
      return
    end
    notImplemented("import")
  end,
  reset = function(rest)
    local all = rest:match("^all") ~= nil
    if rest:match("confirm$") then
      UP:ResetDB(all)
      UP:Print(all and "all saved data reset." or "data for " .. UP:CharKey() .. " reset.")
    else
      UP:Print("this wipes " .. (all and "ALL saved data" or "data for " .. UP:CharKey())
        .. ". Type /upet reset " .. (all and "all " or "") .. "confirm to proceed.")
    end
  end,
  debug = function()
    local build = GetBuildInfo and table.concat({ GetBuildInfo() }, " ") or "?"
    UP:Print("v" .. UP.version .. ", client " .. build .. ", DB v"
      .. tostring(UP.db and UP.db.version) .. ", " .. UP:CharKey())
    for _, path in ipairs(UP.DEBUG_APIS) do
      local value = lookup(path)
      local state = value == nil and "|cffff4040missing|r" or ("|cff40ff40" .. type(value) .. "|r")
      UP:Print("  " .. path .. ": " .. state)
    end
    if UnitExists and UnitExists("pet") then
      local bank = UP.lookup("Enum.SpellBookSpellBank.Pet")
      UP:Print("pet: family " .. tostring(probe("UnitCreatureFamily", "pet"))
        .. ", level " .. tostring(probe("UnitLevel", "pet")))
      UP:Print("  training points: " .. tostring(probe("C_PetInfo.GetPetTrainingPoints")))
      UP:Print("  loyalty: " .. tostring(probe("C_PetInfo.GetPetLoyalty")))
      UP:Print("  pet spells: " .. tostring(probe("C_SpellBook.HasPetSpells")) .. " (bank " .. tostring(bank) .. ")")
    else
      UP:Print("no pet summoned; summon one and run /upet debug again for pet values.")
    end
  end,
}

function UP:HandleSlash(input)
  local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()
  if cmd == "" then cmd = "help" end
  local fn = UP.commands[cmd]
  if fn then
    fn(rest)
  else
    UP:Print("unknown command '" .. cmd .. "'. Try /upet help.")
  end
end

SLASH_ULTIMATEPET1 = "/ultimatepet"
SLASH_ULTIMATEPET2 = "/upet"
SlashCmdList.ULTIMATEPET = function(input)
  UP:HandleSlash(input)
end
