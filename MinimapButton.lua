-- UltimatePet: MinimapButton.lua
-- A LibDataBroker launcher, shown on the minimap by LibDBIcon (as LibDBIcon10_UltimatePet, which
-- minimap button collectors group with other addons).
local _, UP = ...
-- luacheck: read globals UIParent UISpecialFrames

UP.Minimap = UP.Minimap or {}
local Minimap = UP.Minimap

local NAME = "UltimatePet"
local ICON = "Interface\\Icons\\Ability_Hunter_BeastTraining"

local function lib(name)
  local stub = rawget(_G, "LibStub")
  if not stub then return nil end
  local ok, found = pcall(stub.GetLibrary, stub, name, true)
  if ok then return found end
  return nil
end

local function settings()
  return UP.db and UP.db.global and UP.db.global.minimap
end

local function openPlanner()
  if UP.UI and UP.UI.Toggle then
    UP.UI:Toggle()
  else
    UP:Print("The planner window isn't available.")
  end
end

local function openPetView()
  if UP.PetPanel and UP.PetPanel.Toggle then
    UP.PetPanel:Toggle()
  else
    UP:Print("The pet view isn't available.")
  end
end

Minimap.MENU = {
  { text = "Skill planner", func = openPlanner },
  { text = "Pet view", func = openPetView },
}

local MENU_WIDTH, MENU_ROW, MENU_PAD = 150, 18, 6
local MENU_LINGER = 1.5 -- seconds the menu stays after the mouse leaves it

-- Drawn on the top strata: Blizzard's context menu sits below minimap collectors such as
-- EllesmereUI's, and its clicks go through to the button underneath.
local function buildMenu()
  local f = CreateFrame("Frame", "UltimatePetMinimapMenu", UIParent, "BackdropTemplate")
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetSize(MENU_WIDTH, MENU_PAD * 2 + (#Minimap.MENU + 1) * MENU_ROW)
  f:Hide()
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.02, 0.02, 0.07, 0.96)
  end
  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  title:SetPoint("TOPLEFT", MENU_PAD + 4, -MENU_PAD - 3)
  title:SetText(NAME)
  f.buttons = {}
  for i, item in ipairs(Minimap.MENU) do
    local b = CreateFrame("Button", nil, f)
    b:SetHeight(MENU_ROW)
    b:SetPoint("TOPLEFT", MENU_PAD, -MENU_PAD - i * MENU_ROW)
    b:SetPoint("RIGHT", f, "RIGHT", -MENU_PAD, 0)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(0.27, 0.43, 0.78, 0.45)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", 4, 0)
    fs:SetText(item.text)
    b:SetFontString(fs)
    b.label = fs
    b:RegisterForClicks("AnyUp")
    b:SetScript("OnClick", function()
      f:Hide()
      item.func()
    end)
    f.buttons[i] = b
  end
  f:SetScript("OnUpdate", function(self, elapsed)
    if self:IsMouseOver() then
      self.away = 0
    else
      self.away = (self.away or 0) + (elapsed or 0)
      if self.away > MENU_LINGER then self:Hide() end
    end
  end)
  if pcall(f.RegisterEvent, f, "GLOBAL_MOUSE_DOWN") then
    f:SetScript("OnEvent", function(self)
      if self:IsShown() and not self:IsMouseOver() then self:Hide() end
    end)
  end
  if type(rawget(_G, "UISpecialFrames")) == "table" then table.insert(UISpecialFrames, "UltimatePetMinimapMenu") end
  return f
end

-- A second right-click closes the menu.
function Minimap:OpenMenu(owner)
  local f = self.menu or buildMenu()
  self.menu = f
  if f:IsShown() then
    f:Hide()
    return
  end
  f:ClearAllPoints()
  local getCursor = rawget(_G, "GetCursorPosition")
  local scale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
  if getCursor then
    local x, y = getCursor()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale - 8, y / scale + 8)
  elseif type(owner) == "table" and owner.GetObjectType then
    f:SetPoint("TOPRIGHT", owner, "BOTTOMLEFT", 0, 0)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
  f.away = 0
  f:Show()
  if f.Raise then f:Raise() end
end

function Minimap.OnClick(frame, button)
  if button == "RightButton" then
    Minimap:OpenMenu(frame)
  else
    openPlanner()
  end
  return button
end

function Minimap.OnTooltipShow(tooltip)
  if not (tooltip and tooltip.AddLine) then return end
  tooltip:AddLine("UltimatePet")
  tooltip:AddLine("Left-click: open planner", 1, 1, 1)
  tooltip:AddLine("Right-click: menu", 1, 1, 1)
  local pet = UP.Scanner and UP.Scanner.pet
  if pet and pet.exists then
    local unspent = pet.unspent ~= nil and tostring(pet.unspent) or "?"
    local total = pet.tpTotal ~= nil and tostring(pet.tpTotal) or "?"
    tooltip:AddLine(("%s, level %s, %s / %s TP free"):format(tostring(pet.family or "Pet"),
      tostring(pet.level or "?"), unspent, total), 0.67, 0.83, 0.45)
  end
  if UP.Scanner and UP.Scanner.HasScanned and not UP.Scanner:HasScanned() then
    tooltip:AddLine("Beast Training not synced", 1, 0.54, 0.1)
  end
end

function Minimap:Init()
  if self.registered then return true end
  local ldb, icon = lib("LibDataBroker-1.1"), lib("LibDBIcon-1.0")
  if not (ldb and icon and settings()) then return false end
  self.object = ldb:GetDataObjectByName(NAME) or ldb:NewDataObject(NAME, {
    type = "launcher",
    label = NAME,
    text = NAME,
    icon = ICON,
    OnClick = Minimap.OnClick,
    OnTooltipShow = Minimap.OnTooltipShow,
  })
  local ok = pcall(icon.Register, icon, NAME, self.object, settings())
  self.icon = icon
  self.registered = ok
  return ok
end

function Minimap:Toggle()
  local mm = settings()
  if not mm then return end
  mm.hide = not mm.hide
  if not self.registered then self:Init() end
  if self.icon then
    if mm.hide then pcall(self.icon.Hide, self.icon, NAME) else pcall(self.icon.Show, self.icon, NAME) end
  end
  UP:Print(mm.hide and "Minimap button hidden. Type /upet minimap to show it again."
    or "Minimap button shown.")
end

-- Points LibDBIcon at the current settings table after a full reset replaces it.
function Minimap:Rebind()
  if self.registered and self.icon and settings() then
    pcall(self.icon.Refresh, self.icon, NAME, settings())
  end
end

UP:On("PLAYER_LOGIN", function() Minimap:Init() end)
