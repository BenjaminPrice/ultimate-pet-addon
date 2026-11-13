-- UltimatePet: Options.lua
-- The page under Options -> AddOns -> UltimatePet.
local _, UP = ...

local Options = UP.Options or {}
UP.Options = Options

local NAME = "UltimatePet"

local function create(kind, name, parent, template)
  if template then
    local ok, frame = pcall(CreateFrame, kind, name, parent, template)
    if ok and frame then return frame, template end
  end
  return CreateFrame(kind, name, parent), nil
end

local function text(parent, font)
  local fs = parent:CreateFontString(nil, "ARTWORK", font)
  fs:SetJustifyH("LEFT")
  return fs
end

local function checkButton(parent, label)
  local cb, template = create("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetSize(26, 26)
  if not template then
    cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  end
  local templateText = cb.Text or cb.text
  if type(templateText) == "table" and templateText.Hide then templateText:Hide() end
  cb.label = text(cb, "GameFontHighlight")
  cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
  cb.label:SetText(label)
  return cb
end

local function button(parent, label, width)
  local b, template = create("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, 22)
  if not template then
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.45, 0.06, 0.03, 0.95)
    local fs = text(b, "GameFontNormal")
    fs:SetPoint("CENTER")
    b:SetFontString(fs)
  end
  b:SetText(label)
  return b
end

local function alertSettings()
  if UP.Alerts and UP.Alerts.Settings then return UP.Alerts:Settings() end
  local g = UP.db and UP.db.global
  return g and g.alerts or nil
end

local function minimapSettings()
  local g = UP.db and UP.db.global
  return g and type(g.minimap) == "table" and g.minimap or nil
end

-- Shows or hides the minimap button without the chat line /upet minimap prints.
local function setMinimap(show)
  local mm = minimapSettings()
  if not mm then return end
  mm.hide = not show
  local m = UP.Minimap
  if not m then return end
  if not m.registered and m.Init then pcall(m.Init, m) end
  local icon = m.icon
  if icon then
    pcall(show and icon.Show or icon.Hide, icon, NAME)
  end
end

local ALERT_BOXES = {
  { "popup", "Show a popup on screen" },
  { "sound", "Play a sound" },
  { "chat", "Print a chat line" },
}

function Options:Build()
  if self.frame then return self.frame end
  local f = create("Frame", "UltimatePetOptionsPanel")
  f.name = NAME
  f:Hide()

  local title = text(f, "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -16)
  title:SetText(NAME)

  local subtitle = text(f, "GameFontHighlightSmall")
  subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
  subtitle:SetText("Hunter pet build planner")

  local section = text(f, "GameFontNormal")
  section:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -20)
  section:SetText("Learned ability alerts")

  self.checks = {}
  local anchor = section
  for i, def in ipairs(ALERT_BOXES) do
    local key = def[1]
    local cb = checkButton(f, def[2])
    cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", i == 1 and -2 or 0, i == 1 and -6 or -2)
    cb:SetScript("OnClick", function(box)
      local on = box:GetChecked() and true or false
      if UP.Alerts and UP.Alerts.Set then
        UP.Alerts:Set(key, on)
      else
        local s = alertSettings()
        if s then s[key] = on end
      end
    end)
    self.checks[key] = cb
    anchor = cb
  end

  local test = button(f, "Test alert", 120)
  test:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 2, -8)
  test:SetScript("OnClick", function()
    if UP.Alerts and UP.Alerts.Test then UP.Alerts:Test() end
  end)
  self.testButton = test

  local other = text(f, "GameFontNormal")
  other:SetPoint("TOPLEFT", test, "BOTTOMLEFT", 0, -24)
  other:SetText("General")

  local mm = checkButton(f, "Minimap button")
  mm:SetPoint("TOPLEFT", other, "BOTTOMLEFT", -2, -6)
  mm:SetScript("OnClick", function(box)
    setMinimap(box:GetChecked() and true or false)
  end)
  self.minimapCheck = mm

  local open = button(f, "Open planner", 120)
  open:SetPoint("TOPLEFT", mm, "BOTTOMLEFT", 2, -8)
  open:SetScript("OnClick", function()
    if UP.UI and UP.UI.Show then UP.UI:Show() end
  end)
  self.openButton = open

  f:SetScript("OnShow", function() Options:Refresh() end)
  self.frame = f
  return f
end

function Options:Refresh()
  if not self.frame then return end
  local s = alertSettings() or {}
  for key, cb in pairs(self.checks or {}) do
    cb:SetChecked(s[key] ~= false)
  end
  local mm = minimapSettings()
  if self.minimapCheck then self.minimapCheck:SetChecked(not (mm and mm.hide)) end
end

function Options:Register()
  if self.registered then return true end
  local ok, f = pcall(self.Build, self)
  if not ok or not f then return false end
  local settings = UP.lookup("Settings")
  if type(settings) == "table" and type(settings.RegisterCanvasLayoutCategory) == "function" then
    local okCat, category = pcall(settings.RegisterCanvasLayoutCategory, f, NAME)
    if okCat and category then
      if type(settings.RegisterAddOnCategory) == "function" then
        pcall(settings.RegisterAddOnCategory, category)
      end
      self.category = category
      self.registered = true
      return true
    end
  end
  local add = UP.lookup("InterfaceOptions_AddCategory")
  if type(add) == "function" and pcall(add, f) then
    self.registered = true
    return true
  end
  return false
end

function Options:Open()
  self:Register()
  local settings = UP.lookup("Settings")
  if self.category and type(settings) == "table" and type(settings.OpenToCategory) == "function" then
    local category = self.category
    local id = category
    if type(category) == "table" then
      local okId, value = pcall(function() return category:GetID() end)
      id = okId and value or category.ID
    end
    if id ~= nil and pcall(settings.OpenToCategory, id) then return true end
  end
  local open = UP.lookup("InterfaceOptionsFrame_OpenToCategory")
  if self.frame and type(open) == "function" then
    -- Called twice: the first call can land on the wrong page when the list hasn't been built yet.
    pcall(open, self.frame)
    pcall(open, self.frame)
    return true
  end
  UP:Print("The options window isn't available. Use /upet alerts to change alert settings.")
  return false
end

pcall(UP.On, UP, "PLAYER_LOGIN", function()
  if UP.Alerts and UP.Alerts.EnsureDefaults then UP.Alerts.EnsureDefaults() end
  Options:Register()
end)
