local wow = dofile("tests/wowstub.lua")
local stub = dofile("tests/uistub.lua")

describe("Options", function()
  local UP, Options, rec

  local function load(apis)
    UP = wow.load()
    stub.install()
    rec = { opened = {} }
    if apis.settings then
      wow.set("Settings", {
        RegisterCanvasLayoutCategory = function(frame, name)
          rec.canvas = { frame = frame, name = name }
          return { GetID = function() return 42 end }
        end,
        RegisterAddOnCategory = function(category) rec.addon = category end,
        OpenToCategory = function(id) rec.opened[#rec.opened + 1] = id end,
      })
    end
    if apis.interfaceOptions then
      wow.set("InterfaceOptions_AddCategory", function(frame) rec.added = frame end)
      wow.set("InterfaceOptionsFrame_OpenToCategory", function(frame) rec.opened[#rec.opened + 1] = frame end)
    end
    wow.fire("ADDON_LOADED", "UltimatePet")
    wow.fire("PLAYER_LOGIN")
    Options = UP.Options
    wow.takeChat()
  end

  after_each(function()
    stub.uninstall()
    wow.restore()
  end)

  it("registers a canvas category with Settings on login and opens to it", function()
    load({ settings = true, interfaceOptions = true })
    assert.are.equal("UltimatePet", rec.canvas.name)
    assert.are.equal(Options.frame, rec.canvas.frame)
    assert.are.equal(Options.category, rec.addon)
    assert.is_nil(rec.added)
    Options:Open()
    assert.are.same({ 42 }, rec.opened)
  end)

  it("falls back to InterfaceOptions_AddCategory", function()
    load({ interfaceOptions = true })
    assert.are.equal(Options.frame, rec.added)
    assert.are.equal("UltimatePet", rec.added.name)
    Options:Open()
    assert.are.equal(Options.frame, rec.opened[1])
  end)

  it("does nothing harmful when neither API exists", function()
    load({})
    assert.is_false(Options.registered == true)
    assert.has_no.errors(function() Options:Open() end)
    assert.are.same({ "UltimatePet: The options window isn't available. Use /upet alerts to change alert settings." },
      wow.takeChat())
  end)

  describe("page", function()
    before_each(function() load({ settings = true }) end)

    it("shows the title, subtitle, section and labels", function()
      local texts = {}
      for _, obj in ipairs(stub.objects) do
        if obj.objectType == "FontString" and obj.text then texts[obj.text] = true end
      end
      for _, t in ipairs({ "UltimatePet", "Hunter pet build planner", "Learned ability alerts",
        "Show a popup on screen", "Play a sound", "Print a chat line", "Minimap button" }) do
        assert.is_true(texts[t], t)
      end
      assert.are.equal("Test alert", Options.testButton:GetText())
      assert.are.equal("Open planner", Options.openButton:GetText())
    end)

    it("checks the boxes from the DB on show and writes clicks back", function()
      UP.db.global.alerts.sound = false
      Options.frame:Show()
      assert.is_true(Options.checks.popup:GetChecked())
      assert.is_false(Options.checks.sound:GetChecked())
      for _, key in ipairs({ "popup", "sound", "chat" }) do
        local cb = Options.checks[key]
        local before = UP.db.global.alerts[key]
        cb:SetChecked(not before)
        cb:Click()
        assert.are.equal(not before, UP.db.global.alerts[key])
      end
    end)

    it("binds the minimap checkbox to minimap.hide, inverted", function()
      local calls = {}
      UP.Minimap.registered = true
      UP.Minimap.icon = {
        Show = function(_, name) calls[#calls + 1] = "show " .. name end,
        Hide = function(_, name) calls[#calls + 1] = "hide " .. name end,
      }
      Options.frame:Show()
      assert.is_true(Options.minimapCheck:GetChecked())
      Options.minimapCheck:SetChecked(false)
      Options.minimapCheck:Click()
      assert.is_true(UP.db.global.minimap.hide)
      Options.minimapCheck:SetChecked(true)
      Options.minimapCheck:Click()
      assert.is_false(UP.db.global.minimap.hide)
      assert.are.same({ "hide UltimatePet", "show UltimatePet" }, calls)
    end)

    it("runs a test alert and opens the planner from its buttons", function()
      wow.set("PlaySound", function() end)
      Options.testButton:Click()
      assert.are.same({ "UltimatePet: New pet ability: Claw (Rank 2)." }, wow.takeChat())
      local shown = false
      UP.UI = UP.UI or {}
      local orig = UP.UI.Show
      UP.UI.Show = function() shown = true end
      Options.openButton:Click()
      UP.UI.Show = orig
      assert.is_true(shown)
    end)
  end)
end)
