-- Minimap button: LibDataBroker launcher + LibDBIcon registration, with stubbed libraries.
local wow = dofile("tests/wowstub.lua")

-- Minimal LibStub with LibDataBroker-1.1 and LibDBIcon-1.0 that record what the addon does.
local function installLibs()
  local rec = { objects = {}, registered = {}, shown = {}, hidden = {} }
  local ldb = {
    NewDataObject = function(_, name, obj) rec.objects[name] = obj; return obj end,
    GetDataObjectByName = function(_, name) return rec.objects[name] end,
  }
  local icon = {
    Register = function(_, name, obj, db) rec.registered[name] = { obj = obj, db = db } end,
    Show = function(_, name) rec.shown[#rec.shown + 1] = name end,
    Hide = function(_, name) rec.hidden[#rec.hidden + 1] = name end,
  }
  local libs = { ["LibDataBroker-1.1"] = ldb, ["LibDBIcon-1.0"] = icon }
  _G.LibStub = setmetatable({
    GetLibrary = function(_, name, silent)
      if not libs[name] and not silent then error("no " .. name) end
      return libs[name]
    end,
  }, { __call = function(self, name, silent) return self:GetLibrary(name, silent) end })
  return rec
end

-- A tooltip that records its lines.
local function tooltip()
  local t = { lines = {} }
  function t:AddLine(text) self.lines[#self.lines + 1] = text end
  return t
end

describe("Minimap button", function()
  local UP, rec

  before_each(function()
    UP = wow.load()
    rec = installLibs()
    wow.fire("ADDON_LOADED", "UltimatePet")
    wow.takeChat()
  end)

  after_each(function() _G.LibStub = nil end)

  it("registers a launcher with LibDBIcon on login using the saved settings", function()
    wow.fire("PLAYER_LOGIN")
    local obj = rec.objects.UltimatePet
    assert.is_table(obj)
    assert.are.equal("launcher", obj.type)
    assert.matches("Ability_Hunter_BeastTraining", obj.icon, nil, true)
    assert.are.equal(UltimatePetDB.global.minimap, rec.registered.UltimatePet.db)
    assert.is_true(UP.Minimap.registered)
  end)

  it("registers only once", function()
    wow.fire("PLAYER_LOGIN")
    local first = rec.registered.UltimatePet
    UP.Minimap:Init()
    assert.are.equal(first, rec.registered.UltimatePet)
  end)

  it("toggles the planner on click", function()
    wow.fire("PLAYER_LOGIN")
    local toggled = 0
    UP.UI = { Toggle = function() toggled = toggled + 1 end }
    rec.objects.UltimatePet.OnClick(nil, "LeftButton")
    assert.are.equal(1, toggled)
  end)

  it("shows a menu with the planner and the pet view on right-click", function()
    wow.fire("PLAYER_LOGIN")
    local built = {}
    local root = {
      CreateTitle = function(_, text) built[#built + 1] = { title = text } end,
      CreateButton = function(_, text, func) built[#built + 1] = { text = text, func = func } end,
    }
    local owner = {}
    _G.MenuUtil = { CreateContextMenu = function(o, gen) assert.are.equal(owner, o); gen(o, root) end }
    local planner, petView = 0, 0
    UP.UI = { Toggle = function() planner = planner + 1 end }
    UP.PetPanel = { Toggle = function() petView = petView + 1 end }
    rec.objects.UltimatePet.OnClick(owner, "RightButton")
    _G.MenuUtil = nil
    assert.are.same({ title = "UltimatePet" }, built[1])
    assert.are.equal("Skill planner", built[2].text)
    assert.are.equal("Pet view", built[3].text)
    assert.are.equal(0, planner)
    built[2].func()
    built[3].func()
    assert.are.equal(1, planner)
    assert.are.equal(1, petView)
  end)

  it("falls back to a dropdown menu without MenuUtil", function()
    local added, toggled = {}, nil
    local createFrame = _G.CreateFrame
    _G.UIParent = {}
    _G.CreateFrame = function() return {} end
    _G.UIDropDownMenu_CreateInfo = function() return {} end
    _G.UIDropDownMenu_AddButton = function(info) added[#added + 1] = info end
    _G.UIDropDownMenu_Initialize = function(frame, init) init(frame, 1) end
    _G.ToggleDropDownMenu = function(_, _, frame, anchor) toggled = { frame = frame, anchor = anchor } end
    UP.Minimap.OnClick({}, "RightButton")
    for _, k in ipairs({ "UIParent", "UIDropDownMenu_CreateInfo", "UIDropDownMenu_AddButton",
      "UIDropDownMenu_Initialize", "ToggleDropDownMenu" }) do _G[k] = nil end
    _G.CreateFrame = createFrame
    assert.is_true(added[1].isTitle)
    assert.are.equal("Skill planner", added[2].text)
    assert.are.equal("Pet view", added[3].text)
    assert.are.equal("cursor", toggled.anchor)
  end)

  it("shows a plain tooltip with the sync hint", function()
    local t = tooltip()
    UP.Minimap.OnTooltipShow(t)
    assert.are.equal("UltimatePet", t.lines[1])
    assert.are.equal("Left-click: open planner", t.lines[2])
    assert.are.equal("Right-click: menu", t.lines[3])
    assert.are.equal("Beast Training not synced", t.lines[#t.lines])
  end)

  it("lists the summoned pet in the tooltip", function()
    UP.Scanner.pet = { exists = true, family = "Wolf", level = 10, tpTotal = 0, unspent = -4 }
    local t = tooltip()
    UP.Minimap.OnTooltipShow(t)
    assert.are.equal("Wolf, level 10, -4 / 0 TP free", t.lines[4])
  end)

  it("hides and shows the button with /upet minimap and saves the choice", function()
    wow.fire("PLAYER_LOGIN")
    wow.slash("/upet minimap")
    assert.is_true(UltimatePetDB.global.minimap.hide)
    assert.are.same({ "UltimatePet" }, rec.hidden)
    assert.matches("Minimap button hidden", table.concat(wow.takeChat(), "\n"), nil, true)
    wow.slash("/upet minimap")
    assert.is_false(UltimatePetDB.global.minimap.hide)
    assert.are.same({ "UltimatePet" }, rec.shown)
  end)

  it("does nothing without the libraries", function()
    _G.LibStub = nil
    assert.is_false(UP.Minimap:Init())
  end)
end)
