-- UltimatePet: Alerts.lua
-- Tells the hunter when a Beast Training rank is learned in the wild: a popup, a sound and a chat
-- line, each of which can be turned off.
--
-- Public API
--   Alerts:Report(skill, rank, name)  a learn was seen (rank and name optional); merged and filtered
--   Alerts:Test()                     shows a sample alert (Claw rank 2) without recording anything
--   Alerts:Settings()                 UP.db.global.alerts (defaults filled), or the defaults
--   Alerts:Set(key, on)               sets "popup", "sound" or "chat"
--   Alerts.Slash(rest)                handler for "/upet alerts ..."
--   Alerts.Pattern(format)            a game format string ("... %s.") as a Lua pattern capturing %s
--   Alerts.ParseChat(msg)             skill, rank (or nil), shown name for a learn chat line; nil otherwise
--
-- Detection: CHAT_MSG_SYSTEM against the client's ERR_LEARN_ABILITY_S / ERR_LEARN_SPELL_S, and
-- LEARNED_SPELL_IN_TAB / LEARNED_SPELL_IN_SKILL_LINE by spell id. Reports within MERGE_WINDOW are
-- merged; the same skill and rank is ignored for DUPLICATE_WINDOW. Only ranks whose source is
-- "tame" count, and nothing counts while a trainer window is open.
--
-- Approach credited to Huntsworn's AbilityLearned module (MIT); re-implemented.
local _, UP = ...

local Alerts = UP.Alerts or {}
UP.Alerts = Alerts

local MERGE_WINDOW = 0.3
local DUPLICATE_WINDOW = 5
local FADE_IN, HOLD, FADE_OUT = 0.3, 4, 1
local DEFAULTS = { popup = true, sound = true, chat = true }
local KEYS = { "popup", "sound", "chat" }
local LABELS = { popup = "Popup", sound = "Sound", chat = "Chat" }
local GOLD = { 1, 0.82, 0 }

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function lookup(path)
  local value = _G
  for part in path:gmatch("[^%.]+") do
    if type(value) ~= "table" then return nil end
    value = value[part]
  end
  return value
end

-- Calls a dotted global path under pcall; returns nothing if it is missing or errors.
local function call(path, ...)
  local fn = lookup(path)
  if type(fn) ~= "function" then return end
  local res = { pcall(fn, ...) }
  if not res[1] then return end
  return unpack(res, 2, table.maxn(res))
end

local function now()
  return tonumber((call("GetTime"))) or 0
end

-- A string the addon may read: not a secret value on clients that have them, and not empty.
local function readable(value)
  if type(value) ~= "string" or value == "" then return nil end
  local isSecret = lookup("issecretvalue")
  if type(isSecret) == "function" then
    local ok, secret = pcall(isSecret, value)
    if not ok or secret then return nil end
  end
  return value
end

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------

local function ensureDefaults()
  local global = UP.db and UP.db.global
  if type(global) ~= "table" then return nil end
  if type(global.alerts) ~= "table" then global.alerts = {} end
  for k, v in pairs(DEFAULTS) do
    if global.alerts[k] == nil then global.alerts[k] = v end
  end
  return global.alerts
end
Alerts.EnsureDefaults = ensureDefaults

function Alerts:Settings()
  return ensureDefaults() or DEFAULTS
end

function Alerts:Set(key, on)
  local s = ensureDefaults()
  if s and DEFAULTS[key] ~= nil then s[key] = on and true or false end
end

-- ---------------------------------------------------------------------------
-- Names and chat lines
-- ---------------------------------------------------------------------------

-- A game format string as an anchored Lua pattern that captures each %s. Positional arguments
-- (%1$s) become %s, and every other magic character is escaped.
function Alerts.Pattern(format)
  local marked = format:gsub("%%%d+%$s", "\1"):gsub("%%s", "\1")
  local escaped = marked:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
  return "^" .. escaped:gsub("\1", "(.+)") .. "$"
end

local patterns
local function learnPatterns()
  if patterns then return patterns end
  local list = {}
  for _, name in ipairs({ "ERR_LEARN_ABILITY_S", "ERR_LEARN_SPELL_S" }) do
    local format = rawget(_G, name)
    if type(format) == "string" and format:find("%%%d*%$?s") then
      list[#list + 1] = Alerts.Pattern(format)
    end
  end
  -- Only cache once the client strings exist.
  if #list > 0 then patterns = list end
  return list
end

-- Client spell name of a skill's rank 1, or nil while it can't be read.
local function clientName(def)
  local r1 = def.ranks and def.ranks[1]
  local id = r1 and r1.spellId
  if not id then return nil end
  local name = readable((call("C_Spell.GetSpellName", id)))
  if name then return name end
  local info = call("C_Spell.GetSpellInfo", id)
  if type(info) == "table" then return readable(info.name) end
  return nil
end

-- Client name -> skill and lowercase English name -> skill. Rebuilt until every client name resolved:
-- spell names aren't always readable while the addon loads.
local byName, byEnglish, display, complete = {}, {}, {}, false
local function nameIndex()
  if complete then return end
  complete = true
  for skill, def in pairs(UP.Skills or {}) do
    byEnglish[skill:lower()] = skill
    local name = clientName(def)
    if name then
      byName[name] = skill
      display[skill] = name
    else
      complete = false
    end
  end
end

function Alerts.SkillOfName(name)
  nameIndex()
  if type(name) ~= "string" then return nil end
  return byName[name] or byEnglish[name:lower()]
end

-- The name the client uses for a skill (English if it can't be read).
local function displayName(skill)
  nameIndex()
  return display[skill] or skill
end

-- skill, rank (nil when the rank couldn't be read), shown name for a learn chat line; nil otherwise.
function Alerts.ParseChat(msg)
  msg = readable(msg)
  if not msg then return nil end
  for _, pattern in ipairs(learnPatterns()) do
    local ok, text = pcall(string.match, msg, pattern)
    if ok and text then
      local base, inParens = text:match("^(.-)%s*%((.-)%)%s*$")
      local name = base and base ~= "" and base or text
      local skill = Alerts.SkillOfName(name)
      if skill then
        local def = UP.Skills[skill]
        local rank = inParens and tonumber(inParens:match("%d+"))
        if rank and not def.ranks[rank] then rank = nil end
        if not rank and #def.ranks == 1 then rank = 1 end
        return skill, rank, name
      end
    end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Detection
-- ---------------------------------------------------------------------------

Alerts.trainerOpen = false

function Alerts:TrainerOpen()
  if not self.trainerOpen then return false end
  -- A missed TRAINER_CLOSED: the Blizzard trainer frame exists but is hidden.
  local frame = rawget(_G, "ClassTrainerFrame")
  if type(frame) == "table" and type(frame.IsShown) == "function" then
    local ok, shown = pcall(frame.IsShown, frame)
    if ok and not shown then
      self.trainerOpen = false
      return false
    end
  end
  return true
end

-- True when the rank (or, without a rank, any rank of the skill) is learned from a beast.
local function fromTaming(skill, rank)
  local def = UP.Skills and UP.Skills[skill]
  if not def then return false end
  if rank then
    local r = def.ranks[rank]
    return r ~= nil and r.source == "tame"
  end
  for _, r in pairs(def.ranks) do
    if r.source == "tame" then return true end
  end
  return false
end

local pending, pendingOrder, flushScheduled = {}, {}, false
local lastShown = {}

local function shownKey(skill, rank)
  return skill .. "|" .. tostring(rank or "")
end

local function recent(key)
  local at = lastShown[key]
  return at ~= nil and now() - at < DUPLICATE_WINDOW
end

-- Reports of a learn: merged for MERGE_WINDOW, then recorded and shown.
function Alerts:Report(skill, rank, name)
  if not skill or self:TrainerOpen() then return false end
  if not fromTaming(skill, rank) then return false end
  if rank and recent(shownKey(skill, rank)) then return false end
  if not rank and recent(shownKey(skill)) then return false end
  local entry = pending[skill]
  if entry then
    if rank and (not entry.rank or rank > entry.rank) then entry.rank = rank end
    entry.name = entry.name or name
  else
    pending[skill] = { skill = skill, rank = rank, name = name }
    pendingOrder[#pendingOrder + 1] = skill
  end
  if not flushScheduled then
    flushScheduled = true
    local after = lookup("C_Timer.After")
    if type(after) ~= "function" or not pcall(after, MERGE_WINDOW, function() self:Flush() end) then
      self:Flush()
    end
  end
  return true
end

function Alerts:Flush()
  flushScheduled = false
  local order = pendingOrder
  local entries = pending
  pending, pendingOrder = {}, {}
  for _, skill in ipairs(order) do
    local learn = entries[skill]
    if learn and not (learn.rank and recent(shownKey(skill, learn.rank))) then
      lastShown[shownKey(skill)] = now()
      if learn.rank then
        lastShown[shownKey(skill, learn.rank)] = now()
        local char = UP.char
        if char then
          char.unlocked = type(char.unlocked) == "table" and char.unlocked or {}
          char.unlocked[skill] = char.unlocked[skill] or {}
          char.unlocked[skill][learn.rank] = true
          UP:Fire("STATE_CHANGED")
        end
      end
      self:Notify(learn)
    end
  end
end

-- Forgets merge and duplicate state (tests, /upet reset).
function Alerts:ResetState()
  pending, pendingOrder, flushScheduled, lastShown = {}, {}, false, {}
  byName, byEnglish, display, complete = {}, {}, {}, false
  patterns = nil
  self.trainerOpen = false
  self.queue = {}
  if self.popup then
    self.popup.current = nil
    self.popup:Hide()
  end
end

-- ---------------------------------------------------------------------------
-- Notification
-- ---------------------------------------------------------------------------

-- "Claw (Rank 2)", or "Claw" without a rank.
function Alerts.Title(learn)
  local name = learn.name or displayName(learn.skill)
  if learn.rank then return ("%s (Rank %d)"):format(name, learn.rank) end
  return name
end

local function buildHas(build, skill, rank)
  local skills = type(build) == "table" and type(build.skills) == "table" and build.skills
  local have = skills and tonumber(skills[skill])
  return have ~= nil and have >= (rank or 1)
end

-- The name of the build that uses this rank: the summoned pet's assigned build, else the current
-- planner build (true when that build has no name). nil when neither does.
function Alerts.BuildName(skill, rank)
  local char = UP.char
  if not char then return nil end
  local pet = UP.Scanner and UP.Scanner.pet
  if type(pet) == "table" and pet.exists then
    local key = pet.key
    if key == nil then key = tostring(pet.name) .. "|" .. tostring(pet.family) end
    local assigned = type(char.petBuild) == "table" and char.petBuild[key]
    if assigned then
      local build = type(char.builds) == "table" and char.builds[assigned]
      if type(build) ~= "table" and UP.Planner and pet.family then
        build = UP.Planner.Preset(pet.family, assigned)
      end
      if buildHas(build, skill, rank) then return assigned end
    end
  end
  local current, default = char.currentBuild, false
  if type(current) ~= "table" and UP.CurrentBuild then
    local ok, build = pcall(UP.CurrentBuild, UP)
    current, default = ok and build or nil, true
  end
  if not buildHas(current, skill, rank) then return nil end
  if type(current.loaded) == "string" then return current.loaded end
  -- The planner's default build is the family's first preset.
  local preset = default and UP.Planner and current.family and UP.Planner.Preset(current.family)
  return preset and preset.name or true
end

local function icon(skill, rank)
  local def = UP.Skills[skill]
  if not def then return nil end
  local r = def.ranks[rank or 1] or def.ranks[1]
  local tex = r and r.spellId and call("C_Spell.GetSpellTexture", r.spellId)
  return tex or def.icon
end

local function playSound()
  local kit = lookup("SOUNDKIT")
  local id = type(kit) == "table" and kit.LEVELUPSOUND or 888
  call("PlaySound", id, "Master")
end

function Alerts:Notify(learn)
  local s = self:Settings()
  local title = Alerts.Title(learn)
  if s.popup then
    local ok, err = pcall(self.ShowPopup, self, {
      title = title,
      icon = icon(learn.skill, learn.rank),
      build = Alerts.BuildName(learn.skill, learn.rank),
    })
    if not ok and UP.debug then UP:Print("alert popup failed: " .. tostring(err)) end
  end
  if s.sound then playSound() end
  if s.chat then UP:Print("New pet ability: " .. title .. ".") end
end

-- ---------------------------------------------------------------------------
-- Popup
-- ---------------------------------------------------------------------------

Alerts.queue = {}

local function create(kind, name, parent, template)
  if template then
    local ok, frame = pcall(CreateFrame, kind, name, parent, template)
    if ok and frame then return frame end
  end
  return CreateFrame(kind, name, parent)
end

local function popupFrame()
  if Alerts.popup then return Alerts.popup end
  local parent = rawget(_G, "UIParent")
  local f = create("Frame", "UltimatePetLearnAlert", parent)
  f:SetSize(420, 64)
  f:SetPoint("TOP", parent, "TOP", 0, -190)
  f:SetFrameStrata("HIGH")
  f:EnableMouse(false)
  f:Hide()

  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.45)

  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(40, 40)
  f.icon:SetPoint("LEFT", f, "LEFT", 12, 0)

  f.heading = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.heading:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 10, 2)
  f.heading:SetJustifyH("LEFT")
  f.heading:SetTextColor(1, 1, 1)
  f.heading:SetText("New pet ability")

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  f.title:SetPoint("TOPLEFT", f.heading, "BOTTOMLEFT", 0, -2)
  f.title:SetJustifyH("LEFT")
  f.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])

  f.build = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.build:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -2)
  f.build:SetJustifyH("LEFT")

  f:SetScript("OnUpdate", function(self, elapsed)
    Alerts:Step(self, tonumber(elapsed) or 0)
  end)
  Alerts.popup = f
  return f
end

local function present(f, item)
  f.current = item
  f.t = 0
  f.icon:SetTexture(item.icon)
  f.title:SetText(item.title)
  if item.build then
    f.build:SetText(type(item.build) == "string" and "Part of your build: " .. item.build
      or "Part of your current build")
    f.build:Show()
    f:SetHeight(80)
  else
    f.build:SetText("")
    f.build:Hide()
    f:SetHeight(64)
  end
  f:SetAlpha(0)
  f:Show()
end

-- Advances the fade of the shown alert by `elapsed` seconds; shows the next queued one at the end.
function Alerts:Step(f, elapsed)
  if not f.current then return end
  f.t = (f.t or 0) + elapsed
  local t = f.t
  if t < FADE_IN then
    f:SetAlpha(t / FADE_IN)
  elseif t < FADE_IN + HOLD then
    f:SetAlpha(1)
  elseif t < FADE_IN + HOLD + FADE_OUT then
    f:SetAlpha(1 - (t - FADE_IN - HOLD) / FADE_OUT)
  else
    f.current = nil
    f:SetAlpha(0)
    f:Hide()
    local nextItem = table.remove(self.queue, 1)
    if nextItem then present(f, nextItem) end
  end
end

-- Shows an alert ({ title, icon, build }), or queues it behind the one on screen.
function Alerts:ShowPopup(item)
  local f = popupFrame()
  if f.current then
    self.queue[#self.queue + 1] = item
  else
    present(f, item)
  end
  return f
end

-- ---------------------------------------------------------------------------
-- Test and slash command
-- ---------------------------------------------------------------------------

function Alerts:Test()
  local s = self:Settings()
  if not (s.popup or s.sound or s.chat) then
    UP:Print("All alerts are off. Turn one on with /upet alerts popup on.")
    return
  end
  self:Notify({ skill = "Claw", rank = 2 })
end

local function onOff(v) return v and "on" or "off" end

local USAGE = "/upet alerts popup|sound|chat on|off, /upet alerts test"

function Alerts.Slash(rest, ...)
  if rest == Alerts then rest = ... end -- called as Alerts:Slash(rest)
  local words = {}
  for word in tostring(rest or ""):lower():gmatch("%S+") do words[#words + 1] = word end
  if #words == 0 then
    local s = Alerts:Settings()
    UP:Print(("Alerts: popup %s, sound %s, chat %s. %s"):format(onOff(s.popup), onOff(s.sound),
      onOff(s.chat), USAGE))
    return
  end
  if words[1] == "test" and #words == 1 then
    Alerts:Test()
    return
  end
  local key, value = words[1], words[2]
  if LABELS[key] and (value == "on" or value == "off") and #words == 2 then
    Alerts:Set(key, value == "on")
    UP:Print(("%s alerts %s."):format(LABELS[key], value))
    if UP.Options and UP.Options.Refresh then pcall(UP.Options.Refresh, UP.Options) end
    return
  end
  UP:Print("Usage: " .. USAGE)
end

Alerts.KEYS = KEYS

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local function on(event, fn)
  pcall(UP.On, UP, event, fn)
end

-- Core's ADDON_LOADED handler (registered first) has created UP.db by now.
on("ADDON_LOADED", function(name)
  if name == UP.name then ensureDefaults() end
end)

on("TRAINER_SHOW", function() Alerts.trainerOpen = true end)
on("TRAINER_CLOSED", function() Alerts.trainerOpen = false end)

on("CHAT_MSG_SYSTEM", function(msg)
  local skill, rank, name = Alerts.ParseChat(msg)
  if skill then Alerts:Report(skill, rank, name) end
end)

local function onSpell(spellId)
  if not (UP.Scanner and UP.Scanner.SkillOfSpell) then return end
  local skill, rank = UP.Scanner:SkillOfSpell(spellId)
  if skill then Alerts:Report(skill, rank) end
end
on("LEARNED_SPELL_IN_TAB", onSpell)
on("LEARNED_SPELL_IN_SKILL_LINE", onSpell)
