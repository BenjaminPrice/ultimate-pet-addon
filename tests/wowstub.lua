-- Minimal fake WoW API for loading UltimatePet outside the game (busted specs, tests/smoke.lua).
--
--   local wow = dofile("tests/wowstub.lua")
--   local UP = wow.load()                  -- fresh globals, TOC files run with (addonName, ns)
--   wow.fire("ADDON_LOADED", "UltimatePet")
--   wow.slash("/upet help")
--   wow.chat                               -- every AddMessage line, colour codes stripped
--
-- wow.load() resets the stubbed globals first, so each call is an independent client session.
-- Pass { saved = tbl } to start with existing SavedVariables, { player = "Name", realm = "Realm" }
-- for another character, { petFamily = "Wolf" } for a summoned pet, and { root = "path" } when not
-- running from the repository root.

local wow = {}

local ADDON = "UltimatePet"

-- Every global the stub installs, so reset() can clear the previous session's.
local INSTALLED = {
  "CreateFrame", "UnitName", "UnitCreatureFamily", "GetRealmName", "GetTime", "GetBuildInfo", "GetAddOnMetadata",
  "C_AddOns", "C_Timer", "DEFAULT_CHAT_FRAME", "SlashCmdList", "UltimatePetDB",
  "SLASH_ULTIMATEPET1", "SLASH_ULTIMATEPET2",
}

local function strip(msg)
  return (msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
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
    function f:UnregisterEvent(event) self.events[event] = nil end
    function f:UnregisterAllEvents() self.events = {} end
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
    if unit == "player" then return opts.player or "Tester" end
    return nil
  end
  function UnitCreatureFamily(unit)
    if unit == "pet" then return opts.petFamily end
    return nil
  end
  function GetRealmName() return opts.realm or "Forever" end
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

---Resets the client and runs every file of the TOC with (addonName, ns), as the game does.
---Returns the addon's namespace.
function wow.load(opts)
  opts = opts or {}
  local root = opts.root or "."
  local files, meta = wow.readToc(root .. "/" .. ADDON .. ".toc")
  wow.meta = meta
  wow.reset(opts)
  local ns = {}
  for _, file in ipairs(files) do
    local chunk = assert(loadfile(root .. "/" .. file))
    chunk(ADDON, ns)
  end
  wow.ns = ns
  return ns
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

return wow
