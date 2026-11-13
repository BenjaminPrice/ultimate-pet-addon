-- UltimatePet: minimap button and broker launcher.
-- A LibDataBroker launcher shown on the minimap by LibDBIcon. The button is named
-- LibDBIcon10_UltimatePet, which minimap button collectors (EllesmereUIMinimap and others) group
-- with other addons; broker displays (Titan Panel, ElvUI datatexts, ...) can show the launcher.
local _, UP = ...

UP.Minimap = UP.Minimap or {}
local Minimap = UP.Minimap

local NAME = "UltimatePet"
local ICON = "Interface\\Icons\\Ability_Hunter_BeastTraining"

-- Returns the library, or nil when LibStub or the library is not loaded.
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

-- Opens or closes the planner.
function Minimap.OnClick(_, button)
  if UP.UI and UP.UI.Toggle then
    UP.UI:Toggle()
  else
    UP:Print("The planner window isn't available.")
  end
  return button
end

-- Fills the tooltip shown by LibDBIcon and broker displays.
function Minimap.OnTooltipShow(tooltip)
  if not (tooltip and tooltip.AddLine) then return end
  tooltip:AddLine("UltimatePet")
  tooltip:AddLine("Left-click: open planner", 1, 1, 1)
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

-- Registers the launcher and the minimap button. Safe to call more than once.
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

-- Shows or hides the minimap button and remembers the choice.
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

-- Points LibDBIcon at the current settings table (after a full reset replaces it).
function Minimap:Rebind()
  if self.registered and self.icon and settings() then
    pcall(self.icon.Refresh, self.icon, NAME, settings())
  end
end

-- LibDBIcon needs the saved settings, so register after the DB is ready.
UP:On("PLAYER_LOGIN", function() Minimap:Init() end)
