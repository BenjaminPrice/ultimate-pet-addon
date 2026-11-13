-- UltimatePet: PetPanel.lua
-- Panel for the summoned pet: level, loyalty, TP, assigned build and known skills. It sits beside
-- the character sheet while the pet view is open; `/upet pet` opens it as a floating window.
-- Blizzard frames are only hooked (HookScript), never changed.
-- luacheck: read globals UIParent UISpecialFrames GameTooltip InCombatLockdown
local _, UP = ...

local PetPanel = UP.PetPanel or {}
UP.PetPanel = PetPanel

local format = string.format

local FRAME_NAME = "UltimatePetPetPanel"
local WIDTH = 240
-- Frames that are shown only while the character sheet shows the pet: the Classic Pet tab, and
-- the pet view inside the paper doll on the modern-style Forever character sheet.
local PET_VIEWS = { "PetPaperDollFrame", "CharacterStatsPanePetScrollBox" }
-- Offset from CharacterFrame's TOPRIGHT. The Classic character frame art leaves about 32px of
-- transparent space on its right edge; the modern-style Forever frame (with a TitleContainer)
-- ends at its visible edge.
local ATTACH_X, ATTACH_Y = -32, -14
local MODERN_X, MODERN_Y = 4, 0
local PAD = 10
local TITLE_HEIGHT = 22
local LINE_HEIGHT = 15
local ROW_HEIGHT = 20
local HEADER_HEIGHT = 18
local ICON_SIZE = 18
local BUTTON_HEIGHT = 22

local DOT = "  \194\183  "
local BEAST_TRAINING_ID = 5149
local BEAST_TRAINING_ICON = "Interface\\Icons\\Ability_Hunter_BeastTraining"
local TRAIN_SIZE = 14

local function colors()
  return UP.UI.COLORS
end

local function hex(c)
  local function byte(v) return math.floor(v * 255 + 0.5) end
  return format("|cff%02x%02x%02x", byte(c[1]), byte(c[2]), byte(c[3]))
end

-- A copy of the build assigned to this pet (a saved build of its family, else a preset of that
-- name) with a `name` field, or nil.
function PetPanel.ActiveBuild(pet)
  if not (pet and pet.exists and UP.char) then return nil end
  local key = pet.key
  if key == nil then key = tostring(pet.name) .. "|" .. tostring(pet.family) end
  local name = UP.char.petBuild and UP.char.petBuild[key]
  if not name then return nil end
  local saved = UP.char.builds and UP.char.builds[name]
  local source
  if type(saved) == "table" and saved.family == pet.family then
    source = saved
  else
    source = UP.Planner.Preset(pet.family, name)
  end
  if not source then return nil end
  local build = UP.Planner.CopyBuild(source)
  build.name = name
  return build
end

local function petContext(pet)
  return {
    family = pet.family, petFamily = pet.family,
    petLevel = pet.level or 0, unspent = pet.unspent or 0,
    known = pet.known or {},
    unlocked = UP.char and type(UP.char.unlocked) == "table" and UP.char.unlocked or {},
  }
end

-- The highest rank above `known` that the hunter has unlocked and the pet is level enough for:
-- { rank, level, delta (TP to train it, nil when unknown), enough (unspent covers it) } or nil.
function PetPanel.Upgrade(skill, known, ctx)
  local def = UP.Skills[skill]
  local unlocked = ctx.unlocked and ctx.unlocked[skill]
  if not (def and known and type(unlocked) == "table") then return nil end
  local best
  for rank, info in pairs(def.ranks) do
    if rank > known and unlocked[rank] and (info.level or 0) <= (ctx.petLevel or 0)
      and (not best or rank > best) then
      best = rank
    end
  end
  if not best then return nil end
  local from, to = def.ranks[known], def.ranks[best]
  local delta
  if to.tp ~= nil and (from == nil or from.tp ~= nil) then delta = to.tp - (from and from.tp or 0) end
  return { rank = best, level = to.level, delta = delta,
    enough = delta == nil or delta <= (ctx.unspent or 0) }
end

local function skillRow(skill, known, target, hasBuild, ctx)
  local C = colors()
  local row = { skill = skill, name = skill, nameColor = known and C.WHITE or C.GREY }
  row.upgrade = known and PetPanel.Upgrade(skill, known, ctx) or nil
  row.icon = UP.UI.SkillIcon(skill, known or target or 1)
  if not hasBuild then
    row.rankText, row.color = "Rank " .. known, C.WHITE
  elseif target then
    local st = UP.Planner.Status(skill, target, ctx)
    row.rankText = format("%s / %d", known and tostring(known) or "-", target)
    row.color = UP.UI.StatusColor(st and st.code)
    row.code = st and st.code
  else
    row.rankText, row.color = tostring(known), C.GREY
  end
  return row
end

-- Returns { hasPet, lines = { { text, color } }, rows = { row or { header } }, canUse, freeColor }.
function PetPanel.Model(pet, build, ctx)
  local C = colors()
  local m = { hasPet = false, lines = {}, rows = {}, canUse = false }
  if not (pet and pet.exists) then
    m.lines[1] = { text = "No pet summoned.", color = C.GREY }
    return m
  end
  m.hasPet = true
  m.canUse = pet.family ~= nil and UP.Families[pet.family] ~= nil
  ctx = ctx or petContext(pet)

  m.lines[1] = {
    text = format("%s - %s, level %s", pet.name or "Your pet", pet.family or "Unknown family",
      tostring(pet.level or "?")),
    color = C.WHITE,
  }
  local loyalty = pet.loyaltyName or UP.UI.LOYALTY_NAMES[pet.loyalty or 0] or "Loyalty unknown"
  local tp
  if pet.tpTotal == nil then
    tp = "TP unknown"
  else
    local free = pet.unspent or (pet.tpTotal - (pet.tpUsed or 0))
    m.freeColor = free < 0 and C.NEED or C.WHITE
    tp = format("TP %s%d|r / %d free", hex(m.freeColor), free, pet.tpTotal)
  end
  m.lines[2] = { text = loyalty .. DOT .. tp, color = C.GREY }
  if build then
    m.lines[3] = { text = "Build: " .. tostring(build.name), color = C.GOLD }
  else
    m.lines[3] = { text = "Build: none (set one in the planner)", color = C.GREY }
  end

  local known = pet.known or {}
  local targets = build and build.skills or {}
  local actives, passives = {}, {}
  for _, skill in ipairs(UP.SkillOrder) do
    local def = UP.Skills[skill]
    local k = tonumber(known[skill])
    local t = tonumber(targets[skill])
    if k and k <= 0 then k = nil end
    if t and t <= 0 then t = nil end
    if def and (k or t) then
      local list = def.active and actives or passives
      list[#list + 1] = skillRow(skill, k, t, build ~= nil, ctx)
    end
  end
  for _, row in ipairs(actives) do m.rows[#m.rows + 1] = row end
  if #passives > 0 then
    m.rows[#m.rows + 1] = { header = "Passives" }
    for _, row in ipairs(passives) do m.rows[#m.rows + 1] = row end
  end
  if #m.rows == 0 then
    m.rows[1] = { header = "No skills found. Try /upet scan.", color = C.GREY }
  end
  return m
end

-- CreateFrame with the first template that works.
local function create(kind, name, parent, ...)
  for i = 1, select("#", ...) do
    local template = select(i, ...)
    local ok, frame = pcall(CreateFrame, kind, name, parent, template)
    if ok and frame then return frame, template end
  end
  return CreateFrame(kind, name, parent), nil
end

local function setColor(fs, c)
  if c then fs:SetTextColor(c[1], c[2], c[3]) end
end

local function text(parent, font, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
  if justify then fs:SetJustifyH(justify) end
  return fs
end

local function blizzard(name)
  local f = rawget(_G, name)
  if type(f) == "table" then return f end
  return nil
end

local function isVisible(f)
  if not f then return false end
  if type(f.IsVisible) == "function" then return f:IsVisible() and true or false end
  return type(f.IsShown) == "function" and f:IsShown() and true or false
end

local function savePosition(f)
  local point, _, relativePoint, x, y = f:GetPoint()
  if point and UP.db and UP.db.global then
    UP.db.global.petPanel = { point = point, relativePoint = relativePoint, x = x, y = y }
  end
end

local function placeFloating(f)
  local pos = UP.db and UP.db.global and UP.db.global.petPanel
  local planner = UP.UI and UP.UI.frame
  f:ClearAllPoints()
  if type(pos) == "table" and pos.point then
    f:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x or 0, pos.y or 0)
  elseif planner and planner:IsShown() then
    f:SetPoint("TOPLEFT", planner, "TOPRIGHT", 4, 0)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
end

local function placeAttached(f)
  f:ClearAllPoints()
  local character, petFrame = blizzard("CharacterFrame"), blizzard("PetPaperDollFrame")
  if character and character.TitleContainer then
    f:SetPoint("TOPLEFT", character, "TOPRIGHT", MODERN_X, MODERN_Y)
  elseif character then
    f:SetPoint("TOPLEFT", character, "TOPRIGHT", ATTACH_X, ATTACH_Y)
  elseif petFrame then
    f:SetPoint("TOPLEFT", petFrame, "TOPRIGHT", 0, 0)
  else
    placeFloating(f)
  end
end

local function buildFrame()
  local f, template = create("Frame", FRAME_NAME, UIParent, "BackdropTemplate")
  f:SetWidth(WIDTH)
  f:SetHeight(120)
  f:SetFrameStrata("MEDIUM")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:Hide()
  if template and f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.08, 0.07, 0.06, 0.96)
    f:SetBackdropBorderColor(0.43, 0.4, 0.36, 1)
  else
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.07, 0.06, 0.96)
  end

  f.title = text(f, "GameFontNormal", "LEFT")
  f.title:SetPoint("TOPLEFT", PAD, -PAD)
  f.title:SetText("UltimatePet")

  local close = create("Button", nil, f, "UIPanelCloseButton")
  close:SetSize(24, 24)
  close:SetPoint("TOPRIGHT", -2, -2)
  close:SetScript("OnClick", function() PetPanel:Hide() end)
  f.close = close

  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self)
    if PetPanel.mode == "floating" then self:StartMoving() end
  end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if PetPanel.mode == "floating" then savePosition(self) end
  end)
  f:SetScript("OnShow", function() PetPanel:Refresh() end)

  f.lines = {}
  for i = 1, 3 do
    local fs = text(f, "GameFontHighlightSmall", "LEFT")
    fs:SetPoint("TOPLEFT", PAD, -(PAD + TITLE_HEIGHT + (i - 1) * LINE_HEIGHT))
    fs:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
    fs:SetWordWrap(false)
    f.lines[i] = fs
  end
  f.rows = {}

  local b, bTemplate = create("Button", nil, f, "UIPanelButtonTemplate")
  b:SetSize(120, BUTTON_HEIGHT)
  if not bTemplate then
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.45, 0.06, 0.03, 0.95)
    local fs = text(b, "GameFontNormal")
    fs:SetPoint("CENTER")
    b:SetFontString(fs)
  end
  b:SetText("UltimatePet")
  b:SetPoint("BOTTOM", f, "BOTTOM", 0, PAD)
  b:SetScript("OnClick", function() PetPanel:OpenPlanner() end)
  f.button = b

  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, FRAME_NAME) end
  return f
end

function PetPanel.TrainTooltip(skill, up, inCombat)
  local lines = { { format("%s (Rank %d) can be trained.", skill, up.rank), 1, 1, 1 } }
  if up.delta == nil then
    lines[#lines + 1] = { "TP cost unknown.", 0.56, 0.64, 0.74 }
  elseif up.enough then
    lines[#lines + 1] = { format("Costs %d TP.", up.delta), 1, 1, 1 }
  else
    local pet = UP.Scanner and UP.Scanner.pet
    local short = up.delta - ((pet and pet.unspent) or 0)
    lines[#lines + 1] = { format("Costs %d TP. Needs %d more TP.", up.delta, short), 1, 0.54, 0.1 }
  end
  if inCombat then
    lines[#lines + 1] = { "Leave combat to open Beast Training.", 0.6, 0.6, 0.6 }
  else
    lines[#lines + 1] = { "Click to open Beast Training.", 0.24, 1, 0.24 }
  end
  return lines
end

local function inCombat()
  return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

local function showTrainTooltip(owner, rm)
  if not (GameTooltip and rm and rm.upgrade) then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  for i, l in ipairs(PetPanel.TrainTooltip(rm.skill, rm.upgrade, inCombat())) do
    if i == 1 then GameTooltip:SetText(l[1], l[2], l[3], l[4]) else GameTooltip:AddLine(l[1], l[2], l[3], l[4]) end
  end
  GameTooltip:Show()
end

-- Casting Beast Training needs a secure button, and a secure button inside the panel would stop the
-- panel from hiding in combat. So one secure button, parented to UIParent, is placed over the
-- hovered train icon (out of combat only) and hidden again on leave or when combat starts.
local function trainOverlay()
  if PetPanel.overlay ~= nil then return PetPanel.overlay or nil end
  local name = UP.call("C_Spell.GetSpellName", BEAST_TRAINING_ID)
  local ok, b = pcall(CreateFrame, "Button", "UltimatePetTrainButton", UIParent, "SecureActionButtonTemplate")
  if not (ok and b) then
    PetPanel.overlay = false
    return nil
  end
  b:SetAttribute("type", "spell")
  b:SetAttribute("spell", name or "Beast Training")
  if b.RegisterForClicks then b:RegisterForClicks("AnyUp", "AnyDown") end
  b:SetFrameStrata("DIALOG")
  b:SetSize(TRAIN_SIZE, TRAIN_SIZE)
  b:Hide()
  b:SetScript("OnEnter", function(self) showTrainTooltip(self, self.rowModel) end)
  b:SetScript("OnLeave", function(self)
    if GameTooltip then GameTooltip:Hide() end
    if not inCombat() then self:Hide() end
  end)
  PetPanel.overlay = b
  return b
end

-- Positioned in UIParent screen coordinates so the overlay doesn't depend on the panel.
local function placeOverlay(icon, rm)
  if inCombat() then return end
  local b = trainOverlay()
  if not b then return end
  local left, bottom = icon:GetLeft(), icon:GetBottom()
  if not (left and bottom) then return end
  local scale = (icon.GetEffectiveScale and icon:GetEffectiveScale() or 1)
    / (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1)
  b:ClearAllPoints()
  b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * scale, bottom * scale)
  b:SetSize(TRAIN_SIZE * scale, TRAIN_SIZE * scale)
  b.rowModel = rm
  b:Show()
end

UP:On("PLAYER_REGEN_DISABLED", function()
  local b = PetPanel.overlay
  if b then b:Hide() end
end)

local function createRow(f)
  local row = CreateFrame("Frame", nil, f)
  row:SetHeight(ROW_HEIGHT)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(ICON_SIZE, ICON_SIZE)
  row.icon:SetPoint("LEFT", 0, 0)
  row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  row.rank = text(row, "GameFontHighlightSmall", "RIGHT")
  row.rank:SetPoint("RIGHT", 0, 0)
  row.train = CreateFrame("Button", nil, row)
  row.train:SetSize(TRAIN_SIZE, TRAIN_SIZE)
  row.train:SetPoint("RIGHT", row.rank, "LEFT", -4, 0)
  row.train.tex = row.train:CreateTexture(nil, "ARTWORK")
  row.train.tex:SetAllPoints()
  row.train.tex:SetTexture(BEAST_TRAINING_ICON)
  row.train.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  row.train:SetScript("OnEnter", function(self)
    showTrainTooltip(self, row.model)
    placeOverlay(self, row.model)
  end)
  row.train:SetScript("OnLeave", function()
    local b = PetPanel.overlay
    if GameTooltip and not (b and b.IsMouseOver and b:IsMouseOver()) then GameTooltip:Hide() end
  end)
  row.train:Hide()
  row.name = text(row, "GameFontHighlightSmall", "LEFT")
  row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
  row.name:SetPoint("RIGHT", row.train, "LEFT", -4, 0)
  row.name:SetWordWrap(false)
  row.header = text(row, "GameFontNormalSmall", "LEFT")
  row.header:SetPoint("LEFT", 0, 0)
  return row
end

function PetPanel:Create()
  if not self.frame then self.frame = buildFrame() end
  return self.frame
end

function PetPanel:Refresh()
  local f = self.frame
  if not (f and f:IsShown()) then return end
  local pet = UP.Scanner and UP.Scanner.pet or { exists = false, known = {} }
  local m = PetPanel.Model(pet, PetPanel.ActiveBuild(pet))
  self.model = m

  for i, fs in ipairs(f.lines) do
    local line = m.lines[i]
    fs:SetText(line and line.text or "")
    setColor(fs, line and line.color)
    fs:SetShown(line ~= nil)
  end

  local y = -(PAD + TITLE_HEIGHT + #m.lines * LINE_HEIGHT + 4)
  for i, rm in ipairs(m.rows) do
    local row = f.rows[i]
    if not row then
      row = createRow(f)
      f.rows[i] = row
    end
    row.model = rm
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    row:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
    if rm.header then
      row:SetHeight(HEADER_HEIGHT)
      row.header:SetText(rm.header)
      if rm.color then setColor(row.header, rm.color) else row.header:SetTextColor(1, 0.82, 0) end
      row.header:Show()
      row.icon:Hide()
      row.name:Hide()
      row.rank:Hide()
      row.train:Hide()
      y = y - HEADER_HEIGHT
    else
      row:SetHeight(ROW_HEIGHT)
      row.header:Hide()
      row.icon:SetTexture(rm.icon)
      row.icon:Show()
      row.name:SetText(rm.name)
      setColor(row.name, rm.nameColor)
      row.name:Show()
      row.rank:SetText(rm.rankText)
      setColor(row.rank, rm.color)
      row.rank:Show()
      row.train:SetShown(rm.upgrade ~= nil)
      if rm.upgrade then row.train.tex:SetDesaturated(not rm.upgrade.enough) end
      y = y - ROW_HEIGHT
    end
    row:Show()
  end
  for i = #m.rows + 1, #f.rows do
    f.rows[i].model = nil
    f.rows[i]:Hide()
  end
  f:SetHeight(-y + 8 + BUTTON_HEIGHT + PAD)
end

function PetPanel:ShowAttached()
  local f = self:Create()
  self.mode = "attached"
  f:SetFrameStrata("MEDIUM")
  placeAttached(f)
  f.close:Hide()
  if f:IsShown() then self:Refresh() else f:Show() end
end

function PetPanel:ShowFloating()
  local f = self:Create()
  self.mode = "floating"
  -- Same strata as the planner, raised, so the planner never covers it.
  f:SetFrameStrata("HIGH")
  placeFloating(f)
  f.close:Show()
  if f:IsShown() then self:Refresh() else f:Show() end
  if f.Raise then f:Raise() end
end

function PetPanel:Hide()
  if self.frame then self.frame:Hide() end
  self.mode = nil
end

function PetPanel:IsShown()
  return self.frame ~= nil and self.frame:IsShown()
end

local function petViewOpen()
  for _, name in ipairs(PET_VIEWS) do
    if isVisible(blizzard(name)) then return true end
  end
  return false
end

function PetPanel:Toggle()
  self:Hook()
  if petViewOpen() then
    self:ShowAttached()
  elseif self:IsShown() and self.mode == "floating" then
    self:Hide()
  else
    self:ShowFloating()
  end
end

function PetPanel:OpenPlanner()
  local UI = UP.UI
  if UP.char and UI:CanUsePet() and not UI:UsingPet() then UI:SetUseCurrent(true) end
  UI:Show()
end

-- Returns true when at least one pet view is hooked.
function PetPanel:Hook()
  self.hookedViews = self.hookedViews or {}
  for _, name in ipairs(PET_VIEWS) do
    local view = blizzard(name)
    if not self.hookedViews[name] and view and type(view.HookScript) == "function" then
      local ok = pcall(view.HookScript, view, "OnShow", function() PetPanel:ShowAttached() end)
      if ok then
        pcall(view.HookScript, view, "OnHide", function()
          if PetPanel.mode == "attached" and not petViewOpen() then PetPanel:Hide() end
        end)
        self.hookedViews[name] = true
        if isVisible(view) then self:ShowAttached() end
      end
    end
  end
  self.hooked = next(self.hookedViews) ~= nil
  return self.hooked
end

UP:On("PLAYER_LOGIN", function() PetPanel:Hook() end)
UP:On("ADDON_LOADED", function() if UP.char then PetPanel:Hook() end end)

UP:On("STATE_CHANGED", function()
  if PetPanel:IsShown() then PetPanel:Refresh() end
end)
