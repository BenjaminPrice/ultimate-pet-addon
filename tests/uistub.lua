-- Fake frame API for the UI spec, layered on tests/wowstub.lua.
--
--   local wow = dofile("tests/wowstub.lua")
--   local ui = dofile("tests/uistub.lua")
--   local UP = wow.load()
--   ui.install()                     -- after wow.load(): richer CreateFrame, UIParent, GameTooltip, ...
--   ui.install({ missing = { BasicFrameTemplateWithInset = true } })  -- that template fails to load
--   ui.menu(dropdownFrame)           -- runs a UIDropDownMenu init function, returns the added buttons
--   ui.pick(dropdownFrame, "Wolf")   -- clicks that menu entry
--   ui.fire(frame, "OnEnter", ...)   -- runs a script handler
--   ui.uninstall()                   -- also clears every named frame from _G
--
-- Every widget is a table with a metatable. Common methods keep state (text, shown, value, checked,
-- points, scripts); any other method whose name starts with a WoW verb (Set, Get, Enable, ...) is a
-- no-op, so the UI never errors on a method the stub doesn't model. Template parentKey fields
-- (TitleText, CloseButton, ...) exist only for the templates in TEMPLATE_PARTS.
-- luacheck: globals CreateFrame UIParent GameTooltip UISpecialFrames C_Spell
-- luacheck: globals UIDropDownMenu_Initialize UIDropDownMenu_CreateInfo UIDropDownMenu_AddButton
-- luacheck: globals UIDropDownMenu_SetText UIDropDownMenu_SetWidth UIDropDownMenu_EnableDropDown
-- luacheck: globals UIDropDownMenu_DisableDropDown CloseDropDownMenus

local ui = {}

local GLOBALS = {
  "UIParent", "GameTooltip", "UISpecialFrames", "C_Spell", "UIDropDownMenu_Initialize",
  "UIDropDownMenu_CreateInfo", "UIDropDownMenu_AddButton", "UIDropDownMenu_SetText", "UIDropDownMenu_SetWidth",
  "UIDropDownMenu_EnableDropDown", "UIDropDownMenu_DisableDropDown", "CloseDropDownMenus",
}

local VERBS = { "Set", "Get", "Enable", "Disable", "Is", "Register", "Unregister", "Clear", "Start", "Stop",
  "Create", "Highlight", "Hook", "Add", "Lock", "Unlock", "Raise", "Lower", "Toggle", "Has", "Can", "Adjust" }

local function noop() end

local methods = {}

local function isMethodName(key)
  if type(key) ~= "string" then return false end
  for _, verb in ipairs(VERBS) do
    if key:sub(1, #verb) == verb and key:sub(#verb + 1, #verb + 1):match("[%u]") then return true end
  end
  return false
end

local meta = {
  __index = function(_, key)
    local m = methods[key]
    if m then return m end
    if isMethodName(key) then return noop end
    return nil
  end,
}

local function new(kind, name, parent, template)
  local obj = setmetatable({
    objectType = kind, name = name, parent = parent, template = template,
    scripts = {}, points = {}, shown = true, enabled = true, text = nil,
  }, meta)
  ui.objects[#ui.objects + 1] = obj
  return obj
end

local function fire(self, script, ...)
  local fn = self.scripts[script]
  if fn then return fn(self, ...) end
end
ui.fire = fire

function methods:GetParent() return self.parent end
function methods:GetObjectType() return self.objectType end
function methods:SetPoint(point, ...) self.points[#self.points + 1] = { point, ... } end
function methods:ClearAllPoints() self.points = {} end
function methods:GetPoint(i)
  local p = self.points[i or 1]
  if not p then return nil end
  -- point, relativeTo, relativePoint, x, y (SetPoint("CENTER") style shorthands are not normalised)
  return p[1], p[2], p[3], p[4], p[5]
end
function methods:SetWidth(w) self.width = w end
function methods:SetHeight(h) self.height = h end
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:GetWidth() return self.width or 0 end
function methods:GetHeight() return self.height or 0 end
function methods:GetFrameLevel() return self.level or 1 end
function methods:SetFrameLevel(l) self.level = l end

function methods:Show()
  local was = self.shown
  self.shown = true
  if not was then fire(self, "OnShow") end
end
function methods:Hide()
  local was = self.shown
  self.shown = false
  if was then fire(self, "OnHide") end
end
function methods:SetShown(on) if on then self:Show() else self:Hide() end end
function methods:IsShown() return self.shown == true end
function methods:IsVisible()
  if not self.shown then return false end
  if self.parent and self.parent.IsVisible then return self.parent:IsVisible() end
  return true
end

function methods:SetScript(script, fn) self.scripts[script] = fn end
function methods:GetScript(script) return self.scripts[script] end
function methods:HookScript(script, fn)
  local old = self.scripts[script]
  self.scripts[script] = function(...)
    if old then old(...) end
    return fn(...)
  end
end
function methods:Click()
  if self.enabled then fire(self, "OnClick", "LeftButton") end
end

function methods:SetText(text)
  self.text = text ~= nil and tostring(text) or nil
  if self.objectType == "EditBox" then fire(self, "OnTextChanged", false) end
end
function methods:GetText()
  if self.objectType == "EditBox" then return self.text or "" end
  return self.text
end
function methods:SetTextColor(r, g, b, a) self.textColor = { r, g, b, a } end
function methods:GetStringHeight() return 12 end
-- Test helper: typing into an edit box (OnTextChanged with userInput = true).
function methods:Type(text)
  self.text = text
  fire(self, "OnTextChanged", true)
end
function methods:SetFocus() self.focus = true fire(self, "OnEditFocusGained") end
function methods:ClearFocus()
  if self.focus then
    self.focus = false
    fire(self, "OnEditFocusLost")
  end
end
function methods:HasFocus() return self.focus == true end
function methods:HighlightText(from, to) self.highlighted = not (from == 0 and to == 0) end

function methods:SetTexture(tex) self.texture = tex end
function methods:GetTexture() return self.texture end
function methods:SetDesaturated(on) self.desaturated = on and true or false end
function methods:IsDesaturated() return self.desaturated == true end

function methods:Enable() self.enabled = true end
function methods:Disable() self.enabled = false end
function methods:IsEnabled() return self.enabled end
function methods:SetChecked(on) self.checked = on and true or false end
function methods:GetChecked() return self.checked == true end
function methods:SetMinMaxValues(min, max) self.min, self.max = min, max end
function methods:SetValue(v)
  if self.min then v = math.max(self.min, math.min(self.max, v)) end
  local changed = v ~= self.value
  self.value = v
  if changed then fire(self, "OnValueChanged", v, false) end
end
function methods:GetValue() return self.value or 0 end
-- Test helper: dragging a slider (OnValueChanged with userInput = true).
function methods:Drag(v)
  self.value = v
  fire(self, "OnValueChanged", v, true)
end

function methods:SetScrollChild(child) self.scrollChild = child end
function methods:SetVerticalScroll(v) self.vscroll = v end
function methods:GetVerticalScroll() return self.vscroll or 0 end
function methods:GetVerticalScrollRange() return 0 end

function methods:CreateFontString(name, layer, font)
  local fs = new("FontString", name, self, font)
  fs.layer = layer
  return fs
end
function methods:CreateTexture(name, layer)
  local t = new("Texture", name, self)
  t.layer = layer
  return t
end

-- parentKey children some Blizzard templates provide.
local TEMPLATE_PARTS = {
  BasicFrameTemplateWithInset = function(f)
    f.TitleText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.CloseButton = new("Button", nil, f, "UIPanelCloseButton")
    f.CloseButton:SetScript("OnClick", function(self) self.parent:Hide() end)
  end,
  OptionsSliderTemplate = function(f)
    f.Text = f:CreateFontString()
    f.Low = f:CreateFontString()
    f.High = f:CreateFontString()
  end,
  UICheckButtonTemplate = function(f)
    f.Text = f:CreateFontString()
  end,
}

function ui.install(opts)
  opts = opts or {}
  ui.objects = {}
  ui.missing = opts.missing or {}
  ui.menus = {}
  ui.wowCreateFrame = CreateFrame

  function CreateFrame(kind, name, parent, template)
    if template and (ui.missing[template] or ui.missing.all) then
      error("CreateFrame: Couldn't find inherited node \"" .. template .. "\"")
    end
    local f = new(kind, name, parent, template)
    if kind == "Frame" or kind == "Button" or kind == "CheckButton" or kind == "Slider"
      or kind == "EditBox" or kind == "ScrollFrame" then
      f.events = {}
    end
    if template and TEMPLATE_PARTS[template] then TEMPLATE_PARTS[template](f) end
    if name then _G[name] = f end
    return f
  end

  UIParent = new("Frame", "UIParent")
  UISpecialFrames = {}
  C_Spell = { GetSpellTexture = function(id) return 100000 + id end }

  GameTooltip = new("GameTooltip", "GameTooltip")
  GameTooltip.lines = {}
  function GameTooltip:SetOwner(owner) self.owner = owner self.lines = {} end
  function GameTooltip:ClearLines() self.lines = {} end
  function GameTooltip:IsOwned(owner) return self.owner == owner and self:IsShown() end
  function GameTooltip:SetText(text) self.lines = { text } end
  function GameTooltip:AddLine(text) self.lines[#self.lines + 1] = text end
  function GameTooltip:AddDoubleLine(left, right) self.lines[#self.lines + 1] = left .. " | " .. right end

  if not ui.missing.UIDropDownMenu then
    function UIDropDownMenu_Initialize(frame, fn) frame.initMenu = fn end
    function UIDropDownMenu_CreateInfo() return {} end
    function UIDropDownMenu_AddButton(info) ui.menus[#ui.menus + 1] = info end
    function UIDropDownMenu_SetText(frame, text) frame.text = text end
    function UIDropDownMenu_SetWidth(frame, width) frame.width = width end
    function UIDropDownMenu_EnableDropDown(frame) frame.enabled = true end
    function UIDropDownMenu_DisableDropDown(frame) frame.enabled = false end
    function CloseDropDownMenus() end
  end
end

function ui.menu(frame)
  ui.menus = {}
  frame.initMenu(frame, 1)
  return ui.menus
end

function ui.pick(frame, text)
  for _, info in ipairs(ui.menu(frame)) do
    if info.text == text then
      assert(not info.disabled, text .. " is disabled")
      info.func()
      return true
    end
  end
  error("no menu entry " .. text)
end

function ui.uninstall()
  for _, name in ipairs(GLOBALS) do _G[name] = nil end
  for _, obj in ipairs(ui.objects or {}) do
    if obj.name and rawget(_G, obj.name) == obj then _G[obj.name] = nil end
  end
  if ui.wowCreateFrame then CreateFrame = ui.wowCreateFrame end
end

function ui.plain(text)
  return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

return ui
