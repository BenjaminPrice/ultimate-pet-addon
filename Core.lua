local addonName, UP = ...

UP.name = addonName

local function metadata(field)
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  return get and get(addonName, field) or nil
end

UP.version = metadata("Version") or "dev"

-- Resolves a dotted global path ("C_Map.GetMapInfo"), returning nil when any part is missing.
function UP.lookup(path)
  local value = _G
  for part in path:gmatch("[^%.]+") do
    if type(value) ~= "table" then return nil end
    value = value[part]
  end
  return value
end

-- Calls the function at a dotted global path; returns nothing when it is missing or errors.
function UP.call(path, ...)
  local fn = UP.lookup(path)
  if type(fn) ~= "function" then return end
  local res = { pcall(fn, ...) }
  if not res[1] then return end
  return unpack(res, 2, table.maxn(res))
end


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

-- UP:On(name, fn) subscribes to a game event or, for names in UP.MESSAGES, an internal message
-- sent with UP:Fire. Handlers receive the arguments without the event name.
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


UP.DB_VERSION = 3

local GLOBAL_DEFAULTS = {
  minimap = { hide = false }, -- owned by LibDBIcon (hide, minimapPos, lock)
  frame = {},
  petPanel = {}, -- floating pet panel position
  alerts = { popup = true, sound = true, chat = true }, -- learned-ability alerts
  tpCosts = {}, -- [skill][rank] = TP, costs missing from the data and worked out from a summoned pet
}

local CHAR_DEFAULTS = {
  unlocked = {},   -- [skill][rank] = true, from the Beast Training window
  builds = {},     -- [name] = build table
  petBuild = {},   -- [petName .. "|" .. family] = build name
  -- scannedAt: time of the last Beast Training scan; nil until the first one
  -- currentBuild: the build last loaded (import or planner); nil = CurrentBuild()'s default
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
  -- LibDBIcon stores the button position as minimapPos.
  [2] = function(db)
    local mm = type(db.global) == "table" and db.global.minimap
    if type(mm) == "table" and mm.angle ~= nil then
      if mm.minimapPos == nil then mm.minimapPos = mm.angle end
      mm.angle = nil
    end
  end,
  [3] = function(db)
    for _, char in pairs(type(db.chars) == "table" and db.chars or {}) do
      if type(char) == "table" then char.craftCosts = nil end
    end
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

-- The build last loaded for this character. Defaults to a copy of the Raid DPS preset for the
-- summoned pet's family, or Cat when no pet is out.
function UP:CurrentBuild()
  local char = UP.char
  if char and type(char.currentBuild) == "table" then return char.currentBuild end
  local family = UnitCreatureFamily and UnitCreatureFamily("pet")
  if not (family and UP.Presets[family]) then family = "Cat" end
  return UP.Planner.CopyBuild(UP.Planner.Preset(family))
end

function UP:SetCurrentBuild(build)
  UP.char.currentBuild = build
  UP:Fire("STATE_CHANGED")
end

UP:On("ADDON_LOADED", function(name)
  if name ~= addonName then return end
  UP:InitDB()
  UP.loaded = true
  UP:Fire("STATE_CHANGED")
end)


local function notImplemented(cmd)
  UP:Print("'" .. cmd .. "' is not implemented yet.")
end

local HELP = {
  "show - open the planner (also /upet on its own)",
  "scan - read the active pet again",
  "pet - show the current pet panel",
  "alerts [popup|sound|chat on|off | test] - learned-ability alert settings",
  "options - open the options page",
  "minimap - show or hide the minimap button",
  "debug - print the version and scanner state for bug reports",
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
  show = function()
    if UP.UI and UP.UI.Toggle then UP.UI:Toggle() else notImplemented("show") end
  end,
  scan = function()
    if not (UP.Scanner and UP.Scanner.ReadPet) then return notImplemented("scan") end
    local pet = UP.Scanner:ReadPet()
    if not (pet and pet.exists) then
      UP:Print("No pet summoned.")
    else
      UP:Print(("%s: %s, level %s, %s TP total, %s used."):format(tostring(pet.name), tostring(pet.family),
        tostring(pet.level), tostring(pet.tpTotal), tostring(pet.tpUsed)))
    end
  end,
  pet = function()
    if UP.PetPanel and UP.PetPanel.Toggle then UP.PetPanel:Toggle() else notImplemented("pet") end
  end,
  alerts = function(rest)
    if UP.Alerts and UP.Alerts.Slash then UP.Alerts.Slash(rest) else notImplemented("alerts") end
  end,
  options = function()
    if UP.Options and UP.Options.Open then UP.Options:Open() else notImplemented("options") end
  end,
  minimap = function()
    if UP.Minimap and UP.Minimap.Toggle then UP.Minimap:Toggle() else notImplemented("minimap") end
  end,
  export = function()
    UP:Print(UP.Serializer.Encode(UP:CurrentBuild()))
  end,
  import = function(rest)
    if rest == "" then
      UP:Print("usage: /upet import <string>")
      return
    end
    if UP.UI and UP.UI.Import then
      UP.UI:Import(rest)
      return
    end
    local ok, result = UP.Serializer.Decode(rest)
    if not ok then
      UP:Print("Import failed: " .. result)
      return
    end
    UP:SetCurrentBuild(result)
    local n = 0
    for _ in pairs(result.skills) do n = n + 1 end
    UP:Print(("Imported %s build (%d skill%s)."):format(result.family, n, n == 1 and "" or "s"))
  end,
  reset = function(rest)
    local all = rest:match("^all") ~= nil
    if rest:match("confirm$") then
      UP:ResetDB(all)
      if all and UP.Minimap and UP.Minimap.Rebind then UP.Minimap:Rebind() end
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
    if UP.Scanner and UP.Scanner.DebugDump then
      for _, line in ipairs(UP.Scanner:DebugDump()) do UP:Print("  " .. line) end
    end
  end,
}

function UP:HandleSlash(input)
  local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()
  if cmd == "" then cmd = "show" end
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
