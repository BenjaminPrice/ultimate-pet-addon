-- Minimal fake WoW API for loading UltimatePet outside the game (busted specs, tests/smoke.lua).
--
--   local wow = dofile("tests/wowstub.lua")
--   local UP = wow.load()                  -- fresh globals, TOC files run with (addonName, ns)
--   wow.fire("ADDON_LOADED", "UltimatePet")
--   wow.slash("/upet help")
--   wow.chat                               -- every AddMessage line, colour codes stripped
--
-- Each wow.load() is an independent client session for character Tester-Forever. Pass
-- { saved = tbl } to start with existing SavedVariables and { petFamily = "Wolf" } for a summoned pet.

local wow = {}

local ADDON = "UltimatePet"

local INSTALLED = {
  "CreateFrame", "UnitName", "UnitCreatureFamily", "GetRealmName", "GetTime", "GetBuildInfo", "GetAddOnMetadata",
  "C_AddOns", "C_Timer", "DEFAULT_CHAT_FRAME", "SlashCmdList", "UltimatePetDB",
  "SLASH_ULTIMATEPET1", "SLASH_ULTIMATEPET2",
}

local function strip(msg)
  return (msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

function wow.copy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = wow.copy(v) end
  return out
end

---Reads a .toc: the files it lists (in order, "/" separators) and its "## Key: value" metadata.
function wow.readToc(path)
  local fh = assert(io.open(path, "r"))
  local text = fh:read("*a")
  fh:close()
  local files, meta = {}, {}
  for raw in text:gmatch("[^\r\n]+") do
    local line = raw:match("^%s*(.-)%s*$")
    local key, value = line:match("^##%s*([^:]+):%s*(.-)$")
    if key then
      meta[key] = value
    elseif line ~= "" and not line:match("^#") then
      files[#files + 1] = (line:gsub("\\", "/"))
    end
  end
  return files, meta
end

function wow.reset(opts)
  opts = opts or {}
  for _, name in ipairs(INSTALLED) do
    _G[name] = nil
  end

  wow.frames = {}
  wow.chat = {}
  wow.now = 0
  wow.meta = wow.meta or {}

  function CreateFrame(frameType, name)
    local f = { type = frameType, name = name, events = {}, scripts = {} }
    function f:RegisterEvent(event) self.events[event] = true end
    function f:IsEventRegistered(event) return self.events[event] == true end
    function f:SetScript(script, fn) self.scripts[script] = fn end
    function f:GetScript(script) return self.scripts[script] end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown == true end
    wow.frames[#wow.frames + 1] = f
    if name then _G[name] = f end
    return f
  end

  function UnitName(unit)
    if unit == "player" then return "Tester" end
    return nil
  end
  function UnitCreatureFamily(unit)
    if unit == "pet" then return opts.petFamily end
    return nil
  end
  function GetRealmName() return "Forever" end
  function GetTime() return wow.now end
  function GetBuildInfo() return "1.60.0", "00000", "Jan 1 2026", 16001 end
  C_AddOns = {
    GetAddOnMetadata = function(addon, field)
      if addon == ADDON then return wow.meta[field] end
    end,
  }
  C_Timer = {
    After = function(_, fn) fn() end,
  }

  DEFAULT_CHAT_FRAME = {
    AddMessage = function(_, msg) wow.chat[#wow.chat + 1] = strip(tostring(msg)) end,
  }
  SlashCmdList = {}
  UltimatePetDB = opts.saved
end

---Runs one addon file with (addonName, ns), as the game does.
function wow.run(file, ns)
  assert(loadfile(file))(ADDON, ns)
end

---Resets the client and runs every file of the TOC. Returns the addon's namespace.
function wow.load(opts)
  local files, meta = wow.readToc(ADDON .. ".toc")
  wow.meta = meta
  wow.reset(opts)
  local ns = {}
  for _, file in ipairs(files) do
    -- XML files only embed third-party libraries (Libs/embeds.xml); specs stub those instead.
    if not file:match("%.xml$") then wow.run(file, ns) end
  end
  return ns
end

---wow.load(), ADDON_LOADED, and the load-time chat discarded.
function wow.start(opts)
  local UP = wow.load(opts)
  wow.fire("ADDON_LOADED", ADDON)
  wow.takeChat()
  return UP
end

---Delivers a game event to every frame that registered it.
function wow.fire(event, ...)
  for _, f in ipairs(wow.frames) do
    local onEvent = f.scripts.OnEvent
    if f.events[event] and onEvent then
      onEvent(f, event, ...)
    end
  end
end

---Runs a slash command line the way the chat box does: SLASH_<KEY>n matched to SlashCmdList.KEY.
---Returns false when no command matched.
function wow.slash(line)
  local cmd, rest = line:match("^(%S+)%s*(.-)$")
  cmd = cmd:lower()
  for key, handler in pairs(SlashCmdList) do
    local i = 1
    while _G["SLASH_" .. key .. i] do
      if _G["SLASH_" .. key .. i]:lower() == cmd then
        handler(rest)
        return true
      end
      i = i + 1
    end
  end
  return false
end

---Clears captured chat and returns what was there.
function wow.takeChat()
  local lines = wow.chat
  wow.chat = {}
  return lines
end

---Sets the scanned pet (nil for none) and fires STATE_CHANGED.
function wow.setPet(UP, pet)
  UP.Scanner.pet = pet and wow.copy(pet) or { exists = false, known = {} }
  UP:Fire("STATE_CHANGED")
end

function wow.chatText()
  return table.concat(wow.takeChat(), "\n")
end

-- Extra globals a spec installs. Written to the real _G (busted sandboxes a spec's own global
-- writes, which addon code would not see) and put back by wow.restore().
local saved = {}

function wow.set(name, value)
  if not saved[name] then saved[name] = { value = rawget(_G, name) } end
  _G[name] = value
end

function wow.restore()
  for name, old in pairs(saved) do _G[name] = old.value end
  saved = {}
end

return wow
