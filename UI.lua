-- UltimatePet: UI.lua
-- The planner window (layout: .ai/ui-mock-approved.html). Created on first Show, refreshed on STATE_CHANGED.
-- luacheck: read globals UIParent GameTooltip UISpecialFrames C_Spell
-- luacheck: read globals UIDropDownMenu_Initialize UIDropDownMenu_CreateInfo UIDropDownMenu_AddButton
-- luacheck: read globals UIDropDownMenu_SetText UIDropDownMenu_SetWidth UIDropDownMenu_EnableDropDown
-- luacheck: read globals UIDropDownMenu_DisableDropDown CloseDropDownMenus
local _, UP = ...

local UI = UP.UI or {}
UP.UI = UI

local format = string.format

local FRAME_NAME = "UltimatePetFrame"
local WIDTH, HEIGHT = 720, 570
local ROW_HEIGHT = 36
local COLUMN_TOP = -114          -- below the pet line
local COLUMN_TOP_BANNER = -142   -- below the sync banner
local COLUMN_BOTTOM = 72         -- above the bottom bar
local POPOVER_WIDTH = 300

local LOYALTY_NAMES = { "Rebellious", "Unruly", "Submissive", "Dependable", "Faithful", "Best Friend" }
UI.LOYALTY_NAMES = LOYALTY_NAMES

local COLORS = {
  TRAINED = { 0.24, 1, 0.24 },
  READY = { 1, 0.93, 0.27 },
  NEED = { 1, 0.54, 0.1 },
  LOCKED = { 1, 0.23, 0.19 },
  TRAINER = { 0.71, 0.71, 0.71 },
  NO_SOURCE = { 0.56, 0.64, 0.74 },
  ZERO = { 0.42, 0.42, 0.42 },
  DIM = { 0.33, 0.33, 0.33 },
  GREY = { 0.62, 0.62, 0.62 },
  WHITE = { 1, 1, 1 },
  GOLD = { 1, 0.82, 0 },
  HUNTER = { 0.67, 0.83, 0.45 },
  ERROR = { 1, 0.3, 0.3 },
}
UI.COLORS = COLORS

local CODE_COLOR = {
  TRAINED = "TRAINED", READY = "READY", NEED_LEVEL = "NEED", NEED_TP = "NEED", TRAINER_LEVEL = "NEED",
  LOCKED = "LOCKED", TRAINER = "TRAINER", NO_SOURCE = "NO_SOURCE",
}

local HOW_TO_LEARN = "How to learn: tame the beast and use the ability at least once. "
  .. "You must be at least the beast's level to tame it."
local BANNER_TEXT = "Beast Training not synced. Open your Beast Training window once so UltimatePet "
  .. "can see which ranks you know."

local function hex(c)
  local function byte(v) return math.floor(v * 255 + 0.5) end
  return format("|cff%02x%02x%02x", byte(c[1]), byte(c[2]), byte(c[3]))
end

local function colorize(text, c)
  return hex(c) .. text .. "|r"
end

local function trim(s)
  return (tostring(s or ""):match("^%s*(.-)%s*$"))
end

local function printError(msg)
  UP:Print(colorize(msg, COLORS.ERROR))
end

local function spellTexture(spellId)
  return spellId and UP.call("C_Spell.GetSpellTexture", spellId) or nil
end

local function countSkills(build)
  local n = 0
  for _, rank in pairs(build.skills or {}) do
    if type(rank) == "number" and rank > 0 then n = n + 1 end
  end
  return n
end

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

-- ---------------------------------------------------------------------------
-- Build state
-- ---------------------------------------------------------------------------
-- UP.char.currentBuild is the working build. Besides the build fields it carries UI bookkeeping:
--   loaded   name shown in the Preset menu (preset name, saved build name or "Imported")
--   mine     true when `loaded` names one of UP.char.builds
--   modified true after a rank, level or loyalty change since loading

local function pet()
  return UP.Scanner and UP.Scanner.pet or { exists = false, known = {} }
end

local function petName(p)
  return p.name or "Your pet"
end

-- The key a pet's assigned build is stored under in UP.char.petBuild.
local function petKey(p)
  if p.key ~= nil then return p.key end
  return tostring(p.name) .. "|" .. tostring(p.family)
end

local function presetBuild(family, name, keep)
  local preset = UP.Planner.Preset(family, name) or UP.Planner.Preset(family)
  local build = preset and UP.Planner.CopyBuild(preset) or { family = family, level = 60, loyalty = 6, skills = {} }
  build.family = family
  build.loaded = preset and preset.name or nil
  if keep then build.level, build.loyalty = keep.level, keep.loyalty end
  return build
end

local function currentBuild()
  local char = UP.char
  local build = char.currentBuild
  if type(build) ~= "table" or not UP.Families[build.family or ""] then
    build = UP:CurrentBuild()
    if type(build) ~= "table" or not UP.Families[build.family or ""] then
      build = presetBuild("Cat")
    elseif build.loaded == nil then
      local preset = UP.Planner.Preset(build.family)
      build.loaded = preset and preset.name or nil
    end
    char.currentBuild = build
  end
  build.skills = type(build.skills) == "table" and build.skills or {}
  build.level = tonumber(build.level) or 60
  build.loyalty = tonumber(build.loyalty) or 6
  return build
end

-- SetCurrentBuild fires STATE_CHANGED, which refreshes the window.
local function commit(build)
  UP:SetCurrentBuild(build or currentBuild())
end

local function savedBuild(name)
  local build = UP.Planner.CopyBuild(UP.char.builds[name])
  build.loaded, build.mine = name, true
  return build
end

-- A saved build (or else a preset) of `family` by name, as a fresh current build.
local function resolveBuild(name, family)
  local saved = UP.char.builds[name]
  if type(saved) == "table" and saved.family == family then return savedBuild(name) end
  if UP.Planner.Preset(family, name) then return presetBuild(family, name) end
end

function UI:OpenPetView()
  if UP.PetPanel and UP.PetPanel.Toggle then
    UP.PetPanel:Toggle()
  else
    UP:Print("The pet view isn't available.")
  end
end

-- True when the "Use current pet" setting is on and a pet of a known family is out.
function UI:UsingPet()
  local p = pet()
  return UP.char ~= nil and UP.char.useCurrentPet == true and p.exists == true
    and p.family ~= nil and UP.Families[p.family] ~= nil
end

function UI:CanUsePet()
  local p = pet()
  return p.exists == true and p.family ~= nil and UP.Families[p.family] ~= nil
end

-- When tracking the summoned pet, switch to its assigned build (or its family) once per new pet.
function UI:SyncPet()
  if not UP.char then return end
  if not self:UsingPet() then
    self.petKey = nil
    return
  end
  local p = pet()
  local key = petKey(p)
  if key == self.petKey then return end
  self.petKey = key
  local assigned = UP.char.petBuild[key]
  local build = assigned and resolveBuild(assigned, p.family)
  if build then
    UP.char.currentBuild = build
  elseif currentBuild().family ~= p.family then
    UP.char.currentBuild = presetBuild(p.family, nil, currentBuild())
  end
end

-- The build plus everything derived from it. In simulation the Planner context uses the slider
-- level and a budget of level * (loyalty - 1), less the TP of ranks the pet already knows when it is
-- of the same family. With "Use current pet" the pet's real level, unspent TP and total are used.
function UI.State()
  local build = currentBuild()
  local p = pet()
  local live = UI:UsingPet()
  local ctx = UP.Scanner:Context()
  ctx.family = build.family
  ctx.petName = p.name
  local s = { build = build, pet = p, live = live, ctx = ctx }
  if live then
    s.level = p.level or build.level
    s.loyalty = p.loyalty or build.loyalty
    s.budget = p.tpTotal or UP.Planner.Budget(s.level, s.loyalty)
  else
    s.level, s.loyalty = build.level, build.loyalty
    s.budget = UP.Planner.Budget(s.level, s.loyalty)
    local spent = 0
    if p.exists and p.family == build.family then
      spent = UP.Planner.Cost({ skills = ctx.known })
    end
    ctx.petLevel = s.level
    ctx.unspent = s.budget - spent
  end
  s.cost, s.unknown = UP.Planner.Cost(build)
  s.active = UP.Planner.ActiveCount(build)
  return s
end

-- ---------------------------------------------------------------------------
-- View models (pure; tested without frames)
-- ---------------------------------------------------------------------------

function UI.StatusLabel(st)
  local code = st.code
  if code == "TRAINED" then return "Trained" end
  if code == "READY" then return "Ready to Train" end
  if code == "NEED_LEVEL" then return "Unlocked - Need Lv " .. st.level end
  if code == "NEED_TP" then return "Unlocked - Need " .. st.short .. " more TP" end
  if code == "TRAINER" then return "Trainer" end
  if code == "TRAINER_LEVEL" then return "Trainer - Need Lv " .. st.level end
  if code == "NO_SOURCE" then return "No known source" end
  return "Not Unlocked"
end

-- Actives and passives the family can learn, in UP.SkillOrder order.
function UI.SkillLists(family)
  local actives, passives = {}, {}
  for _, skill in ipairs(UP.SkillOrder) do
    local def = UP.Skills[skill]
    if def and def.families[family] then
      local list = def.active and actives or passives
      list[#list + 1] = skill
    end
  end
  return actives, passives
end

function UI.StatusColor(code)
  return COLORS[CODE_COLOR[code or ""]] or COLORS.GREY
end

function UI.SkillIcon(skill, rank)
  local def = UP.Skills[skill]
  if not def then return nil end
  local r = def.ranks[math.max(1, math.min(tonumber(rank) or 1, #def.ranks))]
  return spellTexture(r and r.spellId) or def.icon
end

-- What a row shows for `skill` at the chosen `rank` (0 = not taken) under the Planner ctx.
function UI.RowModel(skill, rank, ctx)
  local def = UP.Skills[skill]
  local max = #def.ranks
  rank = math.max(0, math.min(tonumber(rank) or 0, max))
  local shown = def.ranks[math.max(1, rank)]
  local petLevel = ctx and ctx.petLevel or 0
  local m = {
    skill = skill, rank = rank, max = max, name = skill, active = def.active,
    icon = spellTexture(shown.spellId) or def.icon,
    desaturate = rank == 0,
    canLower = rank > 0, canRaise = rank < max,
    clickable = false, levelBad = false,
  }
  if rank == 0 then
    m.levelText, m.tpText, m.tpColor = "", "-", COLORS.DIM
    m.label, m.color = "Not taken", COLORS.ZERO
    return m
  end
  m.levelText = "Lv " .. shown.level
  m.levelBad = petLevel < shown.level
  if shown.tp == nil then
    m.tpText, m.tpColor, m.tpUnknown = "?", COLORS.NO_SOURCE, true
  else
    m.tpText, m.tpColor = tostring(shown.tp), COLORS.WHITE
  end
  local st = UP.Planner.Status(skill, rank, ctx)
  m.status, m.code = st, st.code
  m.label = UI.StatusLabel(st)
  m.color = UI.StatusColor(st.code)
  m.clickable = st.code == "LOCKED" or st.code == "NO_SOURCE"
  -- U+00BB: the mock's U+25B8 arrow isn't in the game fonts.
  if st.code == "LOCKED" then m.hint = " \194\187 beasts" end
  return m
end

-- Row tooltip: a list of { text, color } and { left, right, color, rightColor } lines.
function UI.TooltipLines(skill, rank, ctx)
  local def = UP.Skills[skill]
  local m = UI.RowModel(skill, rank, ctx)
  local shownRank = math.max(1, m.rank)
  local r = def.ranks[shownRank]
  local lines = {}
  local function add(text, color) lines[#lines + 1] = { text = text, color = color or COLORS.WHITE } end
  lines[1] = { left = skill, right = "Rank " .. shownRank, color = COLORS.WHITE, rightColor = COLORS.GREY }
  add("Requires pet level " .. r.level, (ctx.petLevel or 0) < r.level and COLORS.LOCKED or COLORS.WHITE)
  add("Training cost: " .. (r.tp and (r.tp .. " TP") or "unknown"))
  local source = r.source == "trainer" and "Taught by a pet trainer"
    or r.source == "none" and "No known taming source"
    or "Learned by taming a beast that knows it"
  add(source .. (def.active and " \194\183 Active" or " \194\183 Passive"), COLORS.GREY)
  if m.rank == 0 then
    add("Not taken. Use + to add it.", COLORS.GREY)
  else
    add(m.label, m.color)
  end
  local sameFamily = ctx.family == nil or ctx.family == ctx.petFamily
  local known = sameFamily and ctx.known and ctx.known[skill]
  if known and known > 0 then
    add(format("%s knows Rank %d", ctx.petName or "Your pet", known), COLORS.GREY)
  end
  if m.code == "LOCKED" then add("Click to see beasts that teach this rank", COLORS.TRAINED) end
  return lines
end

local function zoneName(info)
  local mapInfo = info.map and UP.call("C_Map.GetMapInfo", info.map)
  if type(mapInfo) == "table" and type(mapInfo.name) == "string" and mapInfo.name ~= "" then
    return mapInfo.name
  end
  return info.zone or "Unknown zone"
end

local function levelRange(info)
  if info.min and info.max and info.max ~= info.min then return format("Lv %d-%d", info.min, info.max) end
  local l = info.min or info.max
  return l and ("Lv " .. l) or "Lv ?"
end

-- One beast entry: { id, name, detail, note }. note is set for dungeon and raid mobs.
function UI.BeastEntry(info)
  local parts = { levelRange(info) .. (info.family and (" " .. info.family) or "") }
  local note
  if info.instance then
    note = "Inside " .. info.instance
  elseif info.map and info.x and info.y then
    parts[#parts + 1] = format("%s %.1f, %.1f", zoneName(info), info.x, info.y)
  else
    parts[#parts + 1] = (info.zone or "Unknown zone") .. ", location unknown"
  end
  local detail = table.concat(parts, " \194\183 ")
  if info.class then detail = detail .. " (" .. info.class .. ")" end
  return { id = info.id, name = info.name or ("npc " .. tostring(info.id)), detail = detail, note = note }
end

function UI.PopoverModel(skill, rank)
  local r = UP.Skills[skill].ranks[rank]
  local all = (UP.Beasts.teach[skill] or {})[rank] or {}
  local m = { skill = skill, rank = rank, title = format("%s (Rank %d)", skill, rank), entries = {} }
  for _, info in ipairs(UP.Planner.Teachers(skill, rank)) do
    m.entries[#m.entries + 1] = UI.BeastEntry(info)
  end
  local count = #all
  m.sub = format("Pet level %d \194\183 %s \194\183 %d teaching beast%s", r.level,
    r.tp and (r.tp .. " TP") or "TP unknown", count, count == 1 and "" or "s")
  if #m.entries == 0 then
    m.empty = r.source == "none" and "No known taming source" or "No beasts known to teach this rank."
  else
    m.footer = HOW_TO_LEARN
    if count > #m.entries then m.footer = format("Showing %d of %d. ", #m.entries, count) .. m.footer end
  end
  return m
end

-- Dropdown items: { text, checked, title, disabled, func, tooltip }.
function UI.FamilyMenuItems()
  local items = {}
  local family = currentBuild().family
  for _, f in ipairs(UP.FamilyOrder) do
    items[#items + 1] = { text = f, checked = f == family, func = function() UI:SelectFamily(f) end }
  end
  return items
end

function UI.PresetMenuItems()
  local build = currentBuild()
  local family = build.family
  local items = { { text = "Presets for " .. family, title = true } }
  for _, preset in ipairs(UP.Presets[family] or {}) do
    items[#items + 1] = {
      text = preset.name, checked = not build.mine and build.loaded == preset.name,
      tooltip = preset.note, func = function() UI:LoadPreset(preset.name) end,
    }
  end
  items[#items + 1] = { text = "My builds", title = true }
  local any = false
  for _, name in ipairs(sortedKeys(UP.char.builds)) do
    local saved = UP.char.builds[name]
    if type(saved) == "table" and saved.family == family then
      any = true
      items[#items + 1] = {
        text = name, checked = build.mine and build.loaded == name,
        func = function() UI:LoadMyBuild(name) end,
      }
    end
  end
  if not any then items[#items + 1] = { text = "(none saved for " .. family .. ")", disabled = true } end
  return items
end

function UI.PresetLabel(build)
  return (build.loaded or "Custom") .. (build.modified and " *" or "")
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------

function UI:SelectFamily(family)
  if not UP.Families[family] or self:UsingPet() then return end
  self.pop = nil
  commit(presetBuild(family, nil, currentBuild()))
end

function UI:LoadPreset(name)
  local build = currentBuild()
  if not UP.Planner.Preset(build.family, name) then return end
  commit(presetBuild(build.family, name, build))
end

function UI:LoadMyBuild(name)
  if type(UP.char.builds[name]) ~= "table" then return end
  commit(savedBuild(name))
end

function UI:StepRank(skill, delta)
  local build = currentBuild()
  local def = UP.Skills[skill]
  if not def then return end
  local rank = math.max(0, math.min(#def.ranks, (build.skills[skill] or 0) + delta))
  build.skills[skill] = rank > 0 and rank or nil
  build.modified = true
  commit(build)
end

function UI:SetLevel(value)
  local build = currentBuild()
  value = math.floor((tonumber(value) or 1) + 0.5)
  if value == build.level then return end
  build.level, build.modified = value, true
  commit(build)
end

function UI:SetLoyalty(value)
  local build = currentBuild()
  value = math.floor((tonumber(value) or 1) + 0.5)
  if value == build.loyalty then return end
  build.loyalty, build.modified = value, true
  commit(build)
end

function UI:SetUseCurrent(on)
  if on and not self:CanUsePet() then on = false end
  UP.char.useCurrentPet = on and true or false
  self.petKey = nil
  if on then
    local p = pet()
    UP:Print(format("Using current pet: %s '%s' L%d, %s, %d TP.", p.family, petName(p), p.level or 0,
      p.loyaltyName or ("Loyalty " .. tostring(p.loyalty or "?")), p.tpTotal or 0))
    self:SyncPet()
  end
  commit()
end

function UI:SaveBuild(name)
  name = trim(name)
  if name == "" then
    printError("Enter a build name first.")
    return false
  end
  local s = UI.State()
  local existed = UP.char.builds[name] ~= nil
  UP.char.builds[name] = {
    family = s.build.family, level = s.level, loyalty = s.loyalty,
    skills = UP.Planner.CopyBuild(s.build).skills,
  }
  s.build.loaded, s.build.mine, s.build.modified = name, true, false
  if existed then
    UP:Print(format('Updated "%s".', name))
  else
    UP:Print(format('Saved "%s" to My builds (%s).', name, s.build.family))
  end
  commit(s.build)
  return true
end

function UI:DeleteBuild()
  local build = currentBuild()
  local name = build.loaded
  if not (build.mine and name and UP.char.builds[name]) then
    printError("Load one of your builds from the Preset menu first. Bundled presets can't be deleted.")
    return false
  end
  UP.char.builds[name] = nil
  for key, assigned in pairs(UP.char.petBuild) do
    if assigned == name then UP.char.petBuild[key] = nil end
  end
  build.loaded, build.mine, build.modified = nil, nil, true
  UP:Print(format('Deleted "%s".', name))
  commit(build)
  return true
end

function UI:SetActiveForPet()
  local p = pet()
  local build = currentBuild()
  if not p.exists then
    printError("No pet summoned.")
    return false
  end
  if p.family ~= build.family then
    printError(format("%s is a %s. This build is for a %s.", petName(p), tostring(p.family), build.family))
    return false
  end
  local name = build.loaded
  local valid = name and not build.modified and (build.mine and UP.char.builds[name]
    or not build.mine and UP.Planner.Preset(build.family, name))
  if not valid then
    printError("Save the build first, then set it active.")
    return false
  end
  local key = petKey(p)
  UP.char.petBuild[key] = name
  if self:UsingPet() then self.petKey = key end
  UP:Print(format('%s is now tracking "%s".', petName(p), name))
  commit(build)
  return true
end

-- Encodes the shown level and loyalty, which are the pet's own when tracking it.
function UI:ExportString()
  local s = UI.State()
  return UP.Serializer.Encode({
    family = s.build.family, skills = s.build.skills,
    level = math.max(1, math.min(UP.Planner.MAX_LEVEL, s.level or 60)),
    loyalty = math.max(1, math.min(UP.Planner.MAX_LOYALTY, s.loyalty or 6)),
  })
end

function UI:Export()
  local str = self:ExportString()
  local box = self.w and self.w.exportBox
  if box then
    box.locked = str
    box:SetText(str)
    box:SetFocus()
    box:HighlightText()
  end
  UP:Print("Build string ready. Press Ctrl+C to copy.")
  return str
end

function UI:Import(text)
  local ok, result = UP.Serializer.Decode(trim(text))
  if not ok then
    printError("Import failed: " .. result)
    return false
  end
  local p = pet()
  if self:UsingPet() and p.family ~= result.family then
    printError(format("Import failed: %s is a %s. Untick Use current pet to plan a %s.", petName(p),
      p.family, result.family))
    return false
  end
  result.loaded = "Imported"
  self.pop = nil
  local box = self.w and self.w.importBox
  if box then
    box:SetText("")
    box:ClearFocus()
  end
  local n = countSkills(result)
  UP:Print(format("Imported %s build (%d skill%s).", result.family, n, n == 1 and "" or "s"))
  commit(result)
  return true
end

function UI:DismissBanner()
  self.bannerDismissed = true
  self:Refresh()
end

function UI:OpenPopover(skill, column)
  self.pop = { skill = skill, column = column }
  self:Refresh()
end

function UI:ClosePopover()
  self.pop = nil
  if self.w and self.w.popover then self.w.popover:Hide() end
end

function UI:Waypoint(npcId)
  if not self.pop then return end
  local rank = currentBuild().skills[self.pop.skill]
  UP.Waypoints:Add(npcId, self.pop.skill, rank)
end

-- ---------------------------------------------------------------------------
-- Widget builders: each template is guarded, with a plain fallback
-- ---------------------------------------------------------------------------

-- CreateFrame with the first template that works. Returns the frame and the template used (or nil).
local function create(kind, name, parent, ...)
  for i = 1, select("#", ...) do
    local template = select(i, ...)
    local ok, frame = pcall(CreateFrame, kind, name, parent, template)
    if ok and frame then return frame, template end
  end
  return CreateFrame(kind, name, parent), nil
end

local TOOLTIP_BACKDROP = {
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 16,
  insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local function backdrop(frame, bg, border, def)
  if not frame.SetBackdrop then return end
  frame:SetBackdrop(def or TOOLTIP_BACKDROP)
  if bg and frame.SetBackdropColor then frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1) end
  if border and frame.SetBackdropBorderColor then
    frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
  end
end

local function panel(parent)
  local f = create("Frame", nil, parent, "BackdropTemplate")
  backdrop(f, { 0, 0, 0, 0.5 }, { 0.3, 0.28, 0.25, 1 })
  return f
end

local function text(parent, font, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
  if justify then fs:SetJustifyH(justify) end
  return fs
end

local function setColor(fs, c)
  fs:SetTextColor(c[1], c[2], c[3])
end

-- Enable/Disable exist on every clickable widget type; SetEnabled doesn't on older sliders.
local function setEnabled(frame, on)
  if on then frame:Enable() else frame:Disable() end
end

local function button(parent, label, width, height)
  local b, template = create("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, height or 22)
  if not template then
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.45, 0.06, 0.03, 0.95)
    local fs = text(b, "GameFontNormal")
    fs:SetPoint("CENTER")
    b:SetFontString(fs)
    b:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight", "ADD")
  end
  b:SetText(label)
  return b
end

local function closeButton(parent)
  local b, template = create("Button", nil, parent, "UIPanelCloseButton")
  if not template then
    b:SetSize(20, 20)
    local fs = text(b, "GameFontNormalLarge")
    fs:SetPoint("CENTER")
    b:SetFontString(fs)
    b:SetText("\195\151")
  end
  return b
end

local function tooltipFor(frame, fn)
  frame:SetScript("OnEnter", function(self)
    local lines = fn(self)
    if not lines or #lines == 0 then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    for i, line in ipairs(lines) do
      if i == 1 then
        GameTooltip:SetText(line, 1, 1, 1)
      else
        GameTooltip:AddLine(line, nil, nil, nil, true)
      end
    end
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function editBox(parent, width, placeholder)
  local e, template = create("EditBox", nil, parent, "InputBoxTemplate", "BackdropTemplate")
  e:SetSize(width, 20)
  e:SetAutoFocus(false)
  if template ~= "InputBoxTemplate" then
    e:SetFontObject("ChatFontNormal")
    e:SetTextInsets(6, 6, 0, 0)
    backdrop(e, { 0, 0, 0, 0.8 }, { 0.36, 0.33, 0.29, 1 })
  end
  local hint = text(e, "GameFontDisableSmall", "LEFT")
  hint:SetPoint("LEFT", template == "InputBoxTemplate" and 0 or 6, 0)
  hint:SetText(placeholder or "")
  local function update()
    hint:SetShown(e:GetText() == "" and not e:HasFocus())
  end
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEditFocusGained", update)
  e:SetScript("OnEditFocusLost", function(self)
    self:HighlightText(0, 0)
    update()
  end)
  e:SetScript("OnTextChanged", function(self, userInput)
    -- Read-only boxes (export) restore their text when typed into.
    if userInput and self.locked and self:GetText() ~= self.locked then
      self:SetText(self.locked)
      self:HighlightText()
    end
    update()
  end)
  update()
  return e
end

local function checkButton(parent, label)
  local cb, template = create("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetSize(24, 24)
  if not template then
    cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    cb:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
  end
  local templateText = cb.Text or cb.text
  if type(templateText) == "table" and templateText.Hide then templateText:Hide() end
  cb.label = text(parent, "GameFontHighlight", "LEFT")
  cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  cb.label:SetText(label)
  return cb
end

local function slider(parent, min, max, width)
  local s, template = create("Slider", nil, parent, "OptionsSliderTemplate", "UISliderTemplateWithLabels",
    "BackdropTemplate")
  for _, key in ipairs({ "Text", "Low", "High" }) do
    local child = s[key]
    if type(child) == "table" and child.Hide then child:Hide() end
  end
  if template == "BackdropTemplate" or not template then
    s:SetOrientation("HORIZONTAL")
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    backdrop(s, nil, nil, {
      bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
      edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
      tile = true, tileSize = 8, edgeSize = 8,
      insets = { left = 3, right = 3, top = 6, bottom = 6 },
    })
  end
  s:SetSize(width, 17)
  s:SetMinMaxValues(min, max)
  s:SetValueStep(1)
  if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  return s
end

-- Dropdowns use UIDropDownMenu when the client has it, else a small menu of our own.
-- Returned as { frame, own, setText(text), setEnabled(on) }.

local ownMenu

local function showOwnMenu(anchor, items)
  if not ownMenu then
    ownMenu = create("Frame", nil, UI.frame, "BackdropTemplate")
    backdrop(ownMenu, { 0.02, 0.02, 0.07, 0.96 }, { 0.6, 0.6, 0.6, 1 })
    ownMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    ownMenu:EnableMouse(true)
    ownMenu.buttons = {}
  end
  if ownMenu:IsShown() and ownMenu.anchor == anchor then
    ownMenu:Hide()
    return
  end
  ownMenu.anchor = anchor
  for i, item in ipairs(items) do
    local b = ownMenu.buttons[i]
    if not b then
      b = CreateFrame("Button", nil, ownMenu)
      b:SetHeight(16)
      b:SetPoint("TOPLEFT", 8, -6 - (i - 1) * 16)
      b:SetPoint("RIGHT", -8, 0)
      local hl = b:CreateTexture(nil, "HIGHLIGHT")
      hl:SetAllPoints()
      hl:SetColorTexture(0.27, 0.43, 0.78, 0.45)
      b.fs = text(b, "GameFontHighlightSmall", "LEFT")
      b.fs:SetPoint("LEFT", 14, 0)
      b.check = b:CreateTexture(nil, "OVERLAY")
      b.check:SetSize(14, 14)
      b.check:SetPoint("LEFT", -2, 0)
      b.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
      ownMenu.buttons[i] = b
    end
    b.fs:SetText(item.text)
    setColor(b.fs, item.title and COLORS.GOLD or item.disabled and COLORS.GREY or COLORS.WHITE)
    b.check:SetShown(item.checked == true)
    setEnabled(b, not item.title and not item.disabled)
    b:SetScript("OnClick", function()
      ownMenu:Hide()
      if item.func then item.func() end
    end)
    b:Show()
  end
  for i = #items + 1, #ownMenu.buttons do ownMenu.buttons[i]:Hide() end
  ownMenu:SetSize(190, #items * 16 + 12)
  ownMenu:ClearAllPoints()
  ownMenu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  ownMenu:Show()
end

local function dropdown(parent, name, width, itemsFn)
  local hasApi = type(UIDropDownMenu_Initialize) == "function" and type(UIDropDownMenu_AddButton) == "function"
  if hasApi then
    local ok, dd = pcall(CreateFrame, "Frame", name, parent, "UIDropDownMenuTemplate")
    if ok and dd then
      if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(dd, width) end
      UIDropDownMenu_Initialize(dd, function(_, level)
        if not UP.char then return end
        for _, item in ipairs(itemsFn()) do
          local info = type(UIDropDownMenu_CreateInfo) == "function" and UIDropDownMenu_CreateInfo() or {}
          info.text = item.text
          info.isTitle = item.title
          info.disabled = item.disabled or item.title
          info.notCheckable = item.title or item.disabled
          info.checked = item.checked
          info.func = item.func and function() item.func() end
          if item.tooltip then
            info.tooltipTitle, info.tooltipText, info.tooltipOnButton = item.text, item.tooltip, true
          end
          UIDropDownMenu_AddButton(info, level)
        end
      end)
      return {
        frame = dd,
        setText = function(t) if UIDropDownMenu_SetText then UIDropDownMenu_SetText(dd, t) end end,
        setEnabled = function(on)
          local fn = on and UIDropDownMenu_EnableDropDown or UIDropDownMenu_DisableDropDown
          if fn then fn(dd) end
        end,
      }
    end
  end
  local b = button(parent, "", width + 24, 22)
  b:SetScript("OnClick", function(self) showOwnMenu(self, itemsFn()) end)
  return {
    frame = b,
    own = true,
    setText = function(t) b:SetText(t) end,
    setEnabled = function(on) setEnabled(b, on) end,
  }
end

-- ---------------------------------------------------------------------------
-- Window sections
-- ---------------------------------------------------------------------------

local function savePosition(f)
  local point, _, relativePoint, x, y = f:GetPoint()
  if point and UP.db then
    UP.db.global.frame = { point = point, relativePoint = relativePoint, x = x, y = y }
  end
end

local function restorePosition(f)
  local pos = UP.db and UP.db.global and UP.db.global.frame
  f:ClearAllPoints()
  if type(pos) == "table" and pos.point then
    f:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x or 0, pos.y or 0)
  else
    f:SetPoint("CENTER")
  end
end

local function buildWindow()
  local f, template = create("Frame", FRAME_NAME, UIParent, "BasicFrameTemplateWithInset", "BackdropTemplate")
  f:SetSize(WIDTH, HEIGHT)
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:Hide()

  if template ~= "BasicFrameTemplateWithInset" then
    backdrop(f, { 0.08, 0.07, 0.06, 0.96 }, { 0.43, 0.4, 0.36, 1 }, {
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 24,
      insets = { left = 6, right = 6, top = 6, bottom = 6 },
    })
  end
  local title = f.TitleText or (f.TitleContainer and f.TitleContainer.TitleText)
  if type(title) ~= "table" or not title.SetText then
    title = text(f, "GameFontNormal")
    title:SetPoint("TOP", 0, -6)
  end
  title:SetText("UltimatePet")
  if type(f.CloseButton) ~= "table" then
    local close = closeButton(f)
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() UI:Hide() end)
  end

  local drag = CreateFrame("Frame", nil, f)
  drag:SetPoint("TOPLEFT", 0, 0)
  drag:SetPoint("TOPRIGHT", -28, 0)
  drag:SetHeight(24)
  drag:EnableMouse(true)
  drag:RegisterForDrag("LeftButton")
  drag:SetScript("OnDragStart", function() f:StartMoving() end)
  drag:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    savePosition(f)
  end)

  f:SetScript("OnShow", function() UI:Refresh() end)
  f:SetScript("OnHide", function()
    if UP.PetPanel and UP.PetPanel.docked then UP.PetPanel:Hide() end
    UI:ClosePopover()
    GameTooltip:Hide()
    if ownMenu then ownMenu:Hide() end
    if type(CloseDropDownMenus) == "function" then CloseDropDownMenus() end
  end)

  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, FRAME_NAME) end
  restorePosition(f)
  return f
end

local function buildTopBar(f, w)
  local family = text(f, "GameFontNormalSmall")
  family:SetPoint("TOPLEFT", 16, -38)
  family:SetText("Family")
  w.familyDD = dropdown(f, FRAME_NAME .. "FamilyDropDown", 110, UI.FamilyMenuItems)
  w.familyDD.frame:SetPoint("TOPLEFT", 40, w.familyDD.own and -32 or -30)

  local preset = text(f, "GameFontNormalSmall")
  preset:SetPoint("TOPLEFT", 222, -38)
  preset:SetText("Preset")
  w.presetDD = dropdown(f, FRAME_NAME .. "PresetDropDown", 160, UI.PresetMenuItems)
  w.presetDD.frame:SetPoint("TOPLEFT", 248, w.presetDD.own and -32 or -30)

  w.useCheck = checkButton(f, "Use current pet")
  -- Disabled buttons only fire OnEnter with motion scripts on; the tooltip explains why it's off.
  if w.useCheck.SetMotionScriptsWhileDisabled then w.useCheck:SetMotionScriptsWhileDisabled(true) end
  w.useCheck:SetPoint("TOPLEFT", 498, -32)
  w.useCheck:SetScript("OnClick", function(self) UI:SetUseCurrent(self:GetChecked() and true or false) end)
  tooltipFor(w.useCheck, function()
    if UI:CanUsePet() then
      return { "Use current pet", "Use the summoned pet's family, level, loyalty and real TP total." }
    end
    local p = pet()
    if p.exists and p.family then return { "Use current pet", "Unknown pet family: " .. p.family } end
    return { "Use current pet", "No pet summoned" }
  end)

  local level = text(f, "GameFontNormalSmall")
  level:SetPoint("TOPLEFT", 16, -72)
  level:SetText("Level")
  w.levelSlider = slider(f, 1, UP.Planner.MAX_LEVEL, 130)
  w.levelSlider:SetPoint("LEFT", level, "RIGHT", 8, 0)
  w.levelValue = text(f, "GameFontHighlightSmall", "LEFT")
  w.levelValue:SetPoint("LEFT", w.levelSlider, "RIGHT", 8, 0)
  w.levelSlider:SetScript("OnValueChanged", function(_, value)
    if not UI.updating then UI:SetLevel(value) end
  end)

  local loyalty = text(f, "GameFontNormalSmall")
  loyalty:SetPoint("TOPLEFT", 236, -72)
  loyalty:SetText("Loyalty")
  w.loyaltySlider = slider(f, 1, UP.Planner.MAX_LOYALTY, 80)
  w.loyaltySlider:SetPoint("LEFT", loyalty, "RIGHT", 8, 0)
  w.loyaltyValue = text(f, "GameFontHighlightSmall", "LEFT")
  w.loyaltyValue:SetPoint("LEFT", w.loyaltySlider, "RIGHT", 8, 0)
  w.loyaltySlider:SetScript("OnValueChanged", function(_, value)
    if not UI.updating then UI:SetLoyalty(value) end
  end)

  -- Counters are buttons so the TP one can explain "+?" on hover.
  w.activeCounter = CreateFrame("Button", nil, f)
  w.activeCounter:SetSize(84, 20)
  w.activeCounter:SetPoint("TOPRIGHT", -16, -66)
  w.activeText = text(w.activeCounter, "GameFontHighlight", "RIGHT")
  w.activeText:SetPoint("RIGHT")

  w.tpCounter = CreateFrame("Button", nil, f)
  w.tpCounter:SetSize(120, 20)
  w.tpCounter:SetPoint("RIGHT", w.activeCounter, "LEFT", -10, 0)
  w.tpText = text(w.tpCounter, "GameFontHighlight", "RIGHT")
  w.tpText:SetPoint("RIGHT")
  tooltipFor(w.tpCounter, function()
    local unknown = UI.lastState and UI.lastState.unknown or 0
    if unknown == 0 then return nil end
    return {
      "Unknown TP cost",
      format("%d chosen rank%s %s an unknown TP cost and %s not counted.", unknown, unknown == 1 and "" or "s",
        unknown == 1 and "has" or "have", unknown == 1 and "is" or "are"),
      colorize("Open Beast Training to sync real costs.", COLORS.TRAINED),
    }
  end)

  w.petLine = text(f, "GameFontHighlightSmall", "LEFT")
  w.petLine:SetPoint("TOPLEFT", 16, -96)
  w.petLine:SetPoint("RIGHT", f, "RIGHT", -16, 0)
  w.petLine:SetWordWrap(false)
end

local function buildBanner(f, w)
  local b = create("Frame", nil, f, "BackdropTemplate")
  backdrop(b, { 0.47, 0.35, 0.04, 0.45 }, { 0.42, 0.33, 0.09, 1 })
  b:SetPoint("TOPLEFT", 12, -112)
  b:SetPoint("TOPRIGHT", -12, -112)
  b:SetHeight(26)
  local msg = text(b, "GameFontHighlightSmall", "LEFT")
  msg:SetPoint("LEFT", 10, 0)
  msg:SetPoint("RIGHT", -28, 0)
  msg:SetText(BANNER_TEXT)
  msg:SetTextColor(1, 0.91, 0.65)
  local x = closeButton(b)
  x:SetSize(22, 22)
  x:SetPoint("RIGHT", -2, 0)
  x:SetScript("OnClick", function() UI:DismissBanner() end)
  b.text, b.close = msg, x
  w.banner = b
end

local function scrollArea(col)
  local scroll, template = create("ScrollFrame", nil, col, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 4, -24)
  scroll:SetPoint("BOTTOMRIGHT", template and -26 or -6, 4)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(1, 1)
  scroll:SetScrollChild(child)
  if not template then
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
      local range = self:GetVerticalScrollRange() or 0
      local value = math.max(0, math.min(range, (self:GetVerticalScroll() or 0) - delta * ROW_HEIGHT))
      self:SetVerticalScroll(value)
    end)
  end
  return scroll, child
end

local function createRow(col)
  local row = CreateFrame("Button", nil, col.child)
  row:SetHeight(ROW_HEIGHT)
  local hl = row:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.06)

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(28, 28)
  row.icon:SetPoint("LEFT", 4, 0)
  row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  row.tp = text(row, "GameFontHighlight", "RIGHT")
  row.tp:SetWidth(30)
  row.tp:SetPoint("RIGHT", -4, 0)
  row.plus = button(row, "+", 20, 18)
  row.plus:SetPoint("RIGHT", row.tp, "LEFT", -6, 0)
  row.rank = text(row, "GameFontHighlight", "CENTER")
  row.rank:SetWidth(38)
  row.rank:SetPoint("RIGHT", row.plus, "LEFT", -2, 0)
  row.minus = button(row, "-", 20, 18)
  row.minus:SetPoint("RIGHT", row.rank, "LEFT", -2, 0)

  row.name = text(row, "GameFontHighlight", "LEFT")
  row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -1)
  row.level = text(row, "GameFontHighlightSmall", "LEFT")
  row.level:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
  row.status = text(row, "GameFontHighlightSmall", "LEFT")
  row.status:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 1)
  row.status:SetPoint("RIGHT", row.minus, "LEFT", -4, 0)
  row.status:SetWordWrap(false)

  row:SetScript("OnClick", function(self)
    if self.model and self.model.clickable then UI:OpenPopover(self.model.skill, col.index) end
  end)
  row:SetScript("OnEnter", function(self)
    if not self.model then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    for _, line in ipairs(UI.TooltipLines(self.model.skill, self.model.rank, UI.lastState.ctx)) do
      if line.left then
        local c, rc = line.color, line.rightColor
        GameTooltip:AddDoubleLine(line.left, line.right, c[1], c[2], c[3], rc[1], rc[2], rc[3])
      else
        GameTooltip:AddLine(line.text, line.color[1], line.color[2], line.color[3], true)
      end
    end
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  row.minus:SetScript("OnClick", function() if row.model then UI:StepRank(row.model.skill, -1) end end)
  row.plus:SetScript("OnClick", function() if row.model then UI:StepRank(row.model.skill, 1) end end)
  return row
end

local function buildColumns(f, w)
  w.cols = {}
  local colWidth = (WIDTH - 24 - 8) / 2
  for i, heading in ipairs({ "abilities", "Passives & resistances" }) do
    local col = panel(f)
    col.index = i
    col:SetWidth(colWidth)
    col.heading = text(col, "GameFontNormal", "LEFT")
    col.heading:SetPoint("TOPLEFT", 10, -7)
    col.heading:SetText(heading)
    local right = text(col, "GameFontDisableSmall", "RIGHT")
    right:SetPoint("TOPRIGHT", -32, -8)
    right:SetText("RANK          TP")
    col.scroll, col.child = scrollArea(col)
    col.child:SetWidth(colWidth - 32)
    col.pool = {}
    w.cols[i] = col
  end
  w.cols[1]:SetPoint("TOPLEFT", 12, COLUMN_TOP)
  w.cols[1]:SetPoint("BOTTOMLEFT", 12, COLUMN_BOTTOM)
  w.cols[2]:SetPoint("TOPRIGHT", -12, COLUMN_TOP)
  w.cols[2]:SetPoint("BOTTOMRIGHT", -12, COLUMN_BOTTOM)
end

local function buildBottomBar(f, w)
  w.saveBox = editBox(f, 130, "Build name")
  w.saveBox:SetPoint("BOTTOMLEFT", 20, 42)
  w.saveBox:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    UI:SaveBuild(self:GetText())
  end)
  local save = button(f, "Save build", 90)
  save:SetPoint("LEFT", w.saveBox, "RIGHT", 8, 0)
  save:SetScript("OnClick", function() UI:SaveBuild(w.saveBox:GetText()) end)
  local delete = button(f, "Delete", 70)
  delete:SetPoint("LEFT", save, "RIGHT", 4, 0)
  delete:SetScript("OnClick", function() UI:DeleteBuild() end)
  local active = button(f, "Set active for current pet", 180)
  active:SetPoint("LEFT", delete, "RIGHT", 16, 0)
  active:SetScript("OnClick", function() UI:SetActiveForPet() end)
  local petView = button(f, "Pet view", 80)
  petView:SetPoint("BOTTOMRIGHT", -20, 42)
  petView:SetScript("OnClick", function() UI:OpenPetView() end)
  w.petViewButton = petView

  local export = button(f, "Export", 70)
  export:SetPoint("BOTTOMLEFT", 14, 12)
  export:SetScript("OnClick", function() UI:Export() end)
  w.exportBox = editBox(f, 250, "Click Export to create a share string")
  w.exportBox:SetPoint("LEFT", export, "RIGHT", 10, 0)
  w.exportBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  w.exportBox:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
  w.importBox = editBox(f, 220, "Paste UP1:... string")
  w.importBox:SetPoint("LEFT", w.exportBox, "RIGHT", 16, 0)
  w.importBox:SetScript("OnEnterPressed", function(self) UI:Import(self:GetText()) end)
  local import = button(f, "Import", 70)
  import:SetPoint("LEFT", w.importBox, "RIGHT", 6, 0)
  import:SetScript("OnClick", function() UI:Import(w.importBox:GetText()) end)
  w.saveButton, w.deleteButton, w.activeButton, w.exportButton, w.importButton = save, delete, active, export, import
end

local function buildPopover(f, w)
  local p = create("Frame", nil, f, "BackdropTemplate")
  backdrop(p, { 0.01, 0.02, 0.07, 0.95 }, { 0.6, 0.6, 0.6, 1 })
  p:SetWidth(POPOVER_WIDTH)
  p:SetFrameLevel((f:GetFrameLevel() or 1) + 20)
  p:EnableMouse(true)
  p:Hide()
  p.title = text(p, "GameFontHighlight", "LEFT")
  p.title:SetPoint("TOPLEFT", 10, -10)
  p.sub = text(p, "GameFontDisableSmall", "LEFT")
  p.sub:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -3)
  local x = closeButton(p)
  x:SetSize(22, 22)
  x:SetPoint("TOPRIGHT", -2, -2)
  x:SetScript("OnClick", function() UI:ClosePopover() end)
  p.close = x
  p.empty = text(p, "GameFontDisableSmall", "LEFT")
  p.footer = text(p, "GameFontDisableSmall", "LEFT")
  p.footer:SetWidth(POPOVER_WIDTH - 20)
  p.footer:SetJustifyV("TOP")
  p.entries = {}
  w.popover = p
end

local function popoverEntry(p, i)
  local e = p.entries[i]
  if e then return e end
  e = CreateFrame("Frame", nil, p)
  e:SetSize(POPOVER_WIDTH - 16, 34)
  local bg = e:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(1, 1, 1, 0.04)
  e.name = text(e, "GameFontHighlightSmall", "LEFT")
  e.name:SetPoint("TOPLEFT", 6, -4)
  setColor(e.name, COLORS.TRAINED)
  e.detail = text(e, "GameFontHighlightSmall", "LEFT")
  e.detail:SetPoint("TOPLEFT", e.name, "BOTTOMLEFT", 0, -2)
  e.detail:SetPoint("RIGHT", e, "RIGHT", -84, 0)
  e.detail:SetWordWrap(false)
  e.detail:SetTextColor(0.81, 0.81, 0.81)
  e.note = text(e, "GameFontHighlightSmall", "LEFT")
  e.note:SetPoint("TOPLEFT", e.detail, "BOTTOMLEFT", 0, -2)
  setColor(e.note, COLORS.NEED)
  e.button = button(e, "Waypoint", 76, 20)
  e.button:SetPoint("RIGHT", -4, 0)
  e.button:SetScript("OnClick", function() if e.npcId then UI:Waypoint(e.npcId) end end)
  p.entries[i] = e
  return e
end

-- ---------------------------------------------------------------------------
-- Refresh
-- ---------------------------------------------------------------------------

local function counterText(label, value, over)
  return colorize(label, COLORS.GOLD) .. " " .. (over and colorize(value, COLORS.LOCKED) or value)
end

local function refreshTopBar(w, s)
  local build = s.build
  w.familyDD.setText(build.family)
  w.familyDD.setEnabled(not s.live)
  w.presetDD.setText(UI.PresetLabel(build))

  local canUse = UI:CanUsePet()
  w.useCheck:SetChecked(s.live)
  setEnabled(w.useCheck, canUse)
  setColor(w.useCheck.label, canUse and COLORS.WHITE or COLORS.GREY)

  UI.updating = true
  pcall(w.levelSlider.SetValue, w.levelSlider, s.level or 1)
  pcall(w.loyaltySlider.SetValue, w.loyaltySlider, s.loyalty or 1)
  UI.updating = false
  setEnabled(w.levelSlider, not s.live)
  setEnabled(w.loyaltySlider, not s.live)
  local lockedNote = s.live and colorize(" (pet)", COLORS.GREY) or ""
  w.levelValue:SetText(colorize(tostring(s.level or "?"), COLORS.GOLD) .. lockedNote)
  w.loyaltyValue:SetText(colorize(tostring(s.loyalty or "?"), COLORS.GOLD) .. " \194\183 "
    .. (LOYALTY_NAMES[s.loyalty or 0] or "?"))

  local tp = counterText("TP:", format("%d / %d", s.cost, s.budget), s.cost > s.budget)
  if s.unknown > 0 then tp = tp .. colorize(" +?", COLORS.NO_SOURCE) end
  w.tpText:SetText(tp)
  w.activeText:SetText(counterText("Active:", format("%d / %d", s.active, UP.Planner.MAX_ACTIVE),
    s.active > UP.Planner.MAX_ACTIVE))

  local p = s.pet
  if s.live then
    w.petLine:SetText(format("Tracking %s '%s' L%d, %s, %d TP total, %d used", p.family, petName(p), p.level or 0,
      p.loyaltyName or ("Loyalty " .. tostring(p.loyalty or "?")), p.tpTotal or 0, p.tpUsed or 0))
    setColor(w.petLine, COLORS.HUNTER)
  else
    local line = format("Simulating: budget = Level \195\151 (Loyalty - 1) = %d \195\151 %d = %d TP.", s.level,
      s.loyalty - 1, s.budget)
    if p.exists and p.family == build.family then
      line = line .. format(" Statuses compare against your summoned %s, %s.", p.family, petName(p))
    end
    w.petLine:SetText(line)
    setColor(w.petLine, COLORS.GREY)
  end
end

local function refreshBanner(w)
  local show = not UP.Scanner:HasScanned() and not UI.bannerDismissed
  w.banner:SetShown(show)
  local top = show and COLUMN_TOP_BANNER or COLUMN_TOP
  w.cols[1]:SetPoint("TOPLEFT", 12, top)
  w.cols[2]:SetPoint("TOPRIGHT", -12, top)
end

local function setRow(row, m)
  row.model = m
  row.icon:SetTexture(m.icon)
  row.icon:SetDesaturated(m.desaturate)
  if m.desaturate then row.icon:SetVertexColor(0.6, 0.6, 0.6) else row.icon:SetVertexColor(1, 1, 1) end
  row.name:SetText(m.name)
  setColor(row.name, m.rank == 0 and COLORS.GREY or COLORS.WHITE)
  row.level:SetText(m.levelText)
  setColor(row.level, m.levelBad and COLORS.LOCKED or COLORS.GREY)
  row.status:SetText(m.label .. (m.hint and colorize(m.hint, COLORS.GREY) or ""))
  setColor(row.status, m.color)
  local rankColor = m.levelBad and COLORS.GREY or COLORS.WHITE
  row.rank:SetText(colorize(tostring(m.rank), rankColor) .. colorize("/" .. m.max, COLORS.GREY))
  row.tp:SetText(m.tpText)
  setColor(row.tp, m.tpColor)
  setEnabled(row.minus, m.canLower)
  setEnabled(row.plus, m.canRaise)
end

local function refreshColumn(col, skills, s)
  for i, skill in ipairs(skills) do
    local row = col.pool[i]
    if not row then
      row = createRow(col)
      row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
      row:SetPoint("RIGHT", col.child, "RIGHT", 0, 0)
      col.pool[i] = row
    end
    setRow(row, UI.RowModel(skill, s.build.skills[skill] or 0, s.ctx))
    row:Show()
  end
  for i = #skills + 1, #col.pool do
    col.pool[i].model = nil
    col.pool[i]:Hide()
  end
  col.child:SetHeight(math.max(1, #skills * ROW_HEIGHT))
end

local function refreshPopover(w, s, actives, passives)
  local pop = UI.pop
  local p = w.popover
  if pop then
    local inFamily = false
    for _, list in ipairs({ actives, passives }) do
      for _, skill in ipairs(list) do if skill == pop.skill then inFamily = true end end
    end
    local rank = s.build.skills[pop.skill] or 0
    local m = inFamily and rank > 0 and UI.RowModel(pop.skill, rank, s.ctx)
    if not (m and m.clickable) then pop = nil end
  end
  UI.pop = pop
  if not pop then
    p:Hide()
    return
  end
  local rank = s.build.skills[pop.skill]
  local m = UI.PopoverModel(pop.skill, rank)
  p.title:SetText(m.title)
  p.sub:SetText(m.sub)
  local y = -46
  for i, entry in ipairs(m.entries) do
    local e = popoverEntry(p, i)
    e.npcId = entry.id
    e.name:SetText(entry.name)
    e.detail:SetText(entry.detail)
    e.note:SetText(entry.note or "")
    e.note:SetShown(entry.note ~= nil)
    local h = entry.note and 46 or 34
    e:SetHeight(h)
    e:ClearAllPoints()
    e:SetPoint("TOPLEFT", 8, y)
    e:Show()
    y = y - h - 4
  end
  for i = #m.entries + 1, #p.entries do p.entries[i]:Hide() end
  p.empty:SetShown(m.empty ~= nil)
  if m.empty then
    p.empty:SetText(m.empty)
    p.empty:ClearAllPoints()
    p.empty:SetPoint("TOPLEFT", 10, y)
    y = y - 18
  end
  p.footer:SetShown(m.footer ~= nil)
  if m.footer then
    p.footer:SetText(m.footer)
    p.footer:ClearAllPoints()
    p.footer:SetPoint("TOPLEFT", 10, y - 2)
    local h = p.footer.GetStringHeight and tonumber(p.footer:GetStringHeight()) or 0
    y = y - math.max(36, h + 8)
  end
  p:SetHeight(-y + 6)
  p:ClearAllPoints()
  local other = w.cols[pop.column == 1 and 2 or 1]
  if pop.column == 1 then
    p:SetPoint("TOPLEFT", other, "TOPLEFT", 12, -4)
  else
    p:SetPoint("TOPRIGHT", other, "TOPRIGHT", -12, -4)
  end
  p:Show()
end

function UI:Refresh()
  if not (self.frame and self.frame:IsShown()) or not UP.char then return end
  self:SyncPet()
  local w = self.w
  local s = UI.State()
  self.lastState = s
  refreshTopBar(w, s)
  refreshBanner(w)
  local actives, passives = UI.SkillLists(s.build.family)
  w.cols[1].heading:SetText(s.build.family .. " abilities")
  refreshColumn(w.cols[1], actives, s)
  refreshColumn(w.cols[2], passives, s)
  refreshPopover(w, s, actives, passives)
end

-- ---------------------------------------------------------------------------
-- Show / hide
-- ---------------------------------------------------------------------------

function UI:Create()
  if self.frame then return self.frame end
  local f = buildWindow()
  self.frame = f
  local w = {}
  self.w = w
  buildTopBar(f, w)
  buildBanner(f, w)
  buildColumns(f, w)
  buildBottomBar(f, w)
  buildPopover(f, w)
  return f
end

function UI:Show()
  if not UP.char then
    UP:Print("Still loading; try again in a moment.")
    return
  end
  self:Create():Show()
end

function UI:Hide()
  if self.frame then self.frame:Hide() end
end

function UI:Toggle()
  if self.frame and self.frame:IsShown() then
    self:Hide()
  else
    self:Show()
  end
end

UP:On("STATE_CHANGED", function()
  if UI.frame and UI.frame:IsShown() then
    UI:Refresh()
  else
    UI:SyncPet()
  end
end)
