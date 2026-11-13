-- luacheck: read globals UIParent GameTooltip UISpecialFrames
local wow = dofile("tests/wowstub.lua")
local stub = dofile("tests/uistub.lua")
local plain = stub.plain

-- The verified Forever pet: L10 Rebellious Wolf 'Fang', 0 TP total / 4 used, petNumber 7.
local FANG = {
  exists = true, name = "Fang", family = "Wolf", familyId = 1, familyKnown = true, level = 10,
  loyalty = 1, loyaltyName = "Rebellious", tpTotal = 0, tpUsed = 4, unspent = -4,
  known = { Bite = 2, Growl = 2 }, key = 7,
}

local function copy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = copy(v) end
  return out
end

local function chatText()
  return table.concat(wow.takeChat(), "\n")
end

describe("UI", function()
  local UP, UI

  local function setPet(p)
    UP.Scanner.pet = p and copy(p) or { exists = false, known = {} }
    UP:Fire("STATE_CHANGED")
  end

  -- The row frame showing `skill`, searching both columns.
  local function row(skill)
    for _, col in ipairs(UI.w.cols) do
      for _, r in ipairs(col.pool) do
        if r:IsShown() and r.model and r.model.skill == skill then return r, col.index end
      end
    end
    return nil
  end

  local function shownSkills(colIndex)
    local out = {}
    for _, r in ipairs(UI.w.cols[colIndex].pool) do
      if r:IsShown() then out[#out + 1] = r.model.skill end
    end
    return out
  end

  local function load(opts)
    UP = wow.load(opts)
    stub.install(opts and opts.ui)
    wow.fire("ADDON_LOADED", "UltimatePet")
    UI = UP.UI
    wow.takeChat()
  end

  before_each(function() load() end)
  after_each(function() stub.uninstall() end)

  describe("RowModel", function()
    local ctx
    before_each(function()
      ctx = { family = "Cat", petLevel = 60, unspent = 300, known = {}, unlocked = {} }
    end)

    it("shows a rank no beast has unlocked yet as red Not Unlocked, clickable, with a beasts hint", function()
      local m = UI.RowModel("Bite", 8, ctx)
      assert.are.equal("Not Unlocked", m.label)
      assert.are.same(UI.COLORS.LOCKED, m.color)
      assert.is_true(m.clickable)
      assert.are.equal(" \194\187 beasts", m.hint)
      assert.are.equal("Lv 56", m.levelText)
      assert.are.equal("25", m.tpText)
      assert.are.equal(100000 + UP.Skills.Bite.ranks[8].spellId, m.icon)
    end)

    it("labels trainer ranks Trainer, or Trainer - Need Lv N under level", function()
      assert.are.equal("Trainer", UI.RowModel("Growl", 7, ctx).label)
      ctx.petLevel = 50
      local m = UI.RowModel("Growl", 7, ctx)
      assert.are.equal("Trainer - Need Lv 60", m.label)
      assert.are.same(UI.COLORS.NEED, m.color)
      assert.is_true(m.levelBad)
      assert.is_false(m.clickable)
    end)

    it("covers trained, ready, need level and need TP", function()
      ctx.known = { Bite = 8 }
      ctx.petFamily = "Cat"
      assert.are.equal("Trained", UI.RowModel("Bite", 8, ctx).label)
      ctx.unlocked = { Claw = { [8] = true } }
      assert.are.equal("Ready to Train", UI.RowModel("Claw", 8, ctx).label)
      ctx.petLevel = 50
      assert.are.equal("Unlocked - Need Lv 56", UI.RowModel("Claw", 8, ctx).label)
      ctx.petLevel, ctx.unspent = 60, 5
      assert.are.equal("Unlocked - Need 20 more TP", UI.RowModel("Claw", 8, ctx).label)
    end)

    it("shows unknown TP as ? and rank 0 as grey Not taken with a dash", function()
      local swipe = UI.RowModel("Swipe", 1, ctx)
      assert.are.equal("?", swipe.tpText)
      assert.is_true(swipe.tpUnknown)
      local zero = UI.RowModel("Bite", 0, ctx)
      assert.are.equal("Not taken", zero.label)
      assert.are.equal("-", zero.tpText)
      assert.is_true(zero.desaturate)
      assert.is_false(zero.clickable)
      assert.is_false(zero.canLower)
      assert.is_true(zero.canRaise)
    end)

    it("makes no-source ranks clickable without the beasts hint", function()
      local m = UI.RowModel("Lava Breath", 1, { family = "Core Hound", petLevel = 60, unspent = 300 })
      assert.are.equal("No known source", m.label)
      assert.is_true(m.clickable)
      assert.is_nil(m.hint)
    end)

    it("builds the row tooltip", function()
      local lines = UI.TooltipLines("Bite", 8, ctx)
      assert.are.equal("Bite", lines[1].left)
      assert.are.equal("Rank 8", lines[1].right)
      local texts = {}
      for i = 2, #lines do texts[#texts + 1] = lines[i].text end
      assert.are.same({
        "Requires pet level 56", "Training cost: 25 TP",
        "Learned by taming a beast that knows it \194\183 Active", "Not Unlocked",
        "Click to see beasts that teach this rank",
      }, texts)
      local zero = UI.TooltipLines("Great Stamina", 0, ctx)
      assert.are.equal("Not taken. Use + to add it.", zero[#zero].text)
    end)
  end)

  describe("PopoverModel", function()
    it("lists teaching beasts, with instance mobs marked Inside <instance>", function()
      local m = UI.PopoverModel("Bite", 8)
      assert.are.equal("Bite (Rank 8)", m.title)
      assert.are.equal("Pet level 56 \194\183 25 TP \194\183 2 teaching beasts", m.sub)
      assert.are.equal(2, #m.entries)
      local inside = 0
      for _, e in ipairs(m.entries) do
        assert.is_string(e.name)
        assert.is_number(e.id)
        if e.note then
          inside = inside + 1
          assert.truthy(e.note:match("^Inside "))
        end
      end
      assert.is_true(inside > 0)
      assert.truthy(m.footer:match("^How to learn: tame the beast"))
    end)

    it("caps the list at 8 and says how many there are", function()
      local m = UI.PopoverModel("Bite", 1)
      assert.are.equal(8, #m.entries)
      assert.truthy(m.footer:match("^Showing 8 of %d+%."))
      assert.truthy(m.entries[1].detail:match("^Lv %d"))
    end)

    it("says No known taming source for ranks without a source", function()
      local m = UI.PopoverModel("Lava Breath", 1)
      assert.are.equal("No known taming source", m.empty)
      assert.are.equal(0, #m.entries)
      assert.is_nil(m.footer)
    end)
  end)

  describe("window", function()
    it("builds on Toggle, registers for Esc, and toggles closed", function()
      UI:Toggle()
      assert.is_true(UI.frame:IsShown())
      assert.are.equal(UI.frame, _G.UltimatePetFrame)
      assert.are.same({ "UltimatePetFrame" }, UISpecialFrames)
      UI:Toggle()
      assert.is_false(UI.frame:IsShown())
      UI:Toggle()
      assert.is_true(UI.frame:IsShown())
    end)

    it("builds with every template missing (plain fallbacks)", function()
      stub.uninstall()
      load({ ui = { missing = { all = true, UIDropDownMenu = true } } })
      UI:Show()
      assert.is_true(UI.frame:IsShown())
      assert.is_true(UI.w.familyDD.own)
      assert.are.equal("Cat", UI.w.familyDD.frame:GetText())
      assert.are.equal("Not Unlocked", plain(row("Bite").status:GetText()):match("^Not Unlocked"))
    end)

    it("saves its position when dragged", function()
      UI:Show()
      UI.frame:ClearAllPoints()
      UI.frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, -50)
      local drag
      for _, obj in ipairs(stub.objects) do
        if obj.parent == UI.frame and obj.scripts.OnDragStop then drag = obj end
      end
      stub.fire(drag, "OnDragStop")
      assert.are.same({ point = "TOPLEFT", relativePoint = "TOPLEFT", x = 100, y = -50 }, UP.db.global.frame)
    end)

    it("simulates the Cat Raid DPS preset at 60 / Best Friend with nothing unlocked", function()
      UI:Show()
      assert.are.equal("Cat", UP.char.currentBuild.family)
      assert.are.equal("TP: 300 / 300", plain(UI.w.tpText:GetText()))
      assert.are.equal("Active: 4 / 4", plain(UI.w.activeText:GetText()))
      assert.are.equal("Simulating: budget = Level \195\151 (Loyalty - 1) = 60 \195\151 5 = 300 TP.",
        UI.w.petLine:GetText())
      assert.are.equal("Raid DPS", UI.w.familyDD.frame.text == "Cat" and UI.w.presetDD.frame.text)
      local bite = row("Bite")
      assert.are.equal("Not Unlocked \194\187 beasts", plain(bite.status:GetText()))
      assert.are.equal("Trainer", plain(row("Growl").status:GetText()))
      assert.are.equal("8/8", plain(bite.rank:GetText()))
      assert.are.equal("25", bite.tp:GetText())
      assert.are.equal("Not taken", plain(row("Prowl").status:GetText()))
      assert.is_true(row("Prowl").icon:IsDesaturated())
      assert.is_false(UI.w.useCheck:IsEnabled())
      assert.are.equal(60, UI.w.levelSlider:GetValue())
      assert.are.equal(6, UI.w.loyaltySlider:GetValue())
    end)

    it("splits actives and passives into the two columns and follows a family switch", function()
      UI:Show()
      assert.are.same({ "Bite", "Claw", "Dash", "Prowl", "Growl", "Cower" }, shownSkills(1))
      assert.are.same({ "Great Stamina", "Natural Armor", "Arcane Resistance", "Fire Resistance",
        "Frost Resistance", "Nature Resistance", "Shadow Resistance" }, shownSkills(2))
      stub.pick(UI.w.familyDD.frame, "Bird of Prey")
      assert.are.equal("Bird of Prey", UP.char.currentBuild.family)
      assert.are.same({ "Claw", "Dive", "Growl", "Cower", "Mine!" }, shownSkills(1))
      assert.are.equal("Bird of Prey abilities", UI.w.cols[1].heading:GetText())
      assert.is_nil(row("Bite"))
    end)

    it("shows the sync banner until Beast Training is scanned, and hides it for the session on X", function()
      UI:Show()
      assert.is_true(UI.w.banner:IsShown())
      assert.truthy(UI.w.banner.text:GetText():match("^Beast Training not synced%."))
      UI.w.banner.close:Click()
      assert.is_false(UI.w.banner:IsShown())
      UI.bannerDismissed = nil
      UP.char.scannedAt = 1
      UI:Refresh()
      assert.is_false(UI.w.banner:IsShown())
    end)

    it("steps ranks, recolours the TP counter when over budget and marks the preset modified", function()
      UI:Show()
      row("Prowl").plus:Click()
      assert.are.equal(1, UP.char.currentBuild.skills.Prowl)
      assert.are.equal("TP: 315 / 300", plain(UI.w.tpText:GetText()))
      assert.truthy(UI.w.tpText:GetText():find("|cffff3b30", 1, true))
      assert.are.equal("Active: 5 / 4", plain(UI.w.activeText:GetText()))
      assert.are.equal("Raid DPS *", UI.w.presetDD.frame.text)
      row("Prowl").minus:Click()
      assert.is_nil(UP.char.currentBuild.skills.Prowl)
      assert.is_false(row("Prowl").minus:IsEnabled())
    end)

    it("appends +? to the TP counter when a chosen rank has unknown cost", function()
      UI:Show()
      stub.pick(UI.w.familyDD.frame, "Bear")
      row("Swipe").plus:Click()
      assert.truthy(plain(UI.w.tpText:GetText()):match("%+%?$"))
      stub.fire(UI.w.tpCounter, "OnEnter")
      assert.truthy(table.concat(GameTooltip.lines, "\n"):find("unknown TP cost", 1, true))
    end)

    it("changes the simulated budget with the sliders and greys ranks above the level", function()
      UI:Show()
      UI.w.levelSlider:Drag(40)
      assert.are.equal(40, UP.char.currentBuild.level)
      assert.are.equal("TP: 300 / 200", plain(UI.w.tpText:GetText()))
      assert.are.equal("Trainer - Need Lv 60", plain(row("Growl").status:GetText()))
      assert.are.same(UI.COLORS.LOCKED, { unpack(row("Bite").level.textColor, 1, 3) })
      UI.w.loyaltySlider:Drag(3)
      assert.are.equal("TP: 300 / 80", plain(UI.w.tpText:GetText()))
      assert.are.equal("3 \194\183 Submissive", plain(UI.w.loyaltyValue:GetText()))
    end)

    it("shows a row tooltip on hover", function()
      UI:Show()
      stub.fire(row("Bite"), "OnEnter")
      assert.are.equal("Bite | Rank 8", GameTooltip.lines[1])
      assert.are.equal("Click to see beasts that teach this rank", GameTooltip.lines[#GameTooltip.lines])
    end)
  end)

  describe("with the verified Forever pet", function()
    it("refreshes with no pet, then with Fang summoned while simulating", function()
      UI:Show()
      setPet(FANG)
      assert.is_true(UI.w.useCheck:IsEnabled())
      assert.is_false(UI.w.useCheck:GetChecked())
      -- Still the Cat build: the Wolf's known ranks don't count against a Cat.
      assert.are.equal("Not Unlocked \194\187 beasts", plain(row("Bite").status:GetText()))
      stub.pick(UI.w.familyDD.frame, "Wolf")
      -- Budget 300 less the 4 TP of Fang's Bite 2.
      assert.truthy(UI.w.petLine:GetText():find("Statuses compare against your summoned Wolf, Fang.", 1, true))
      assert.are.equal(296, UI.lastState.ctx.unspent)
    end)

    it("tracks the pet when Use current pet is ticked", function()
      UI:Show()
      setPet(FANG)
      UI.w.useCheck:SetChecked(true)
      UI.w.useCheck:Click()
      assert.truthy(chatText():find("Using current pet: Wolf 'Fang' L10, Rebellious, 0 TP.", 1, true))
      assert.are.equal("Wolf", UP.char.currentBuild.family)
      assert.are.equal("Tracking Wolf 'Fang' L10, Rebellious, 0 TP total, 4 used", UI.w.petLine:GetText())
      assert.truthy(plain(UI.w.tpText:GetText()):match("^TP: %d+ / 0$"))
      assert.is_false(UI.w.levelSlider:IsEnabled())
      assert.is_false(UI.w.familyDD.frame.enabled)
      assert.are.equal(10, UI.w.levelSlider:GetValue())
      assert.are.equal(1, UI.w.loyaltySlider:GetValue())
      -- Fang knows Bite 2; Bite 8 needs level 56.
      assert.are.equal("Lv 56", row("Bite").level:GetText())
      UP.UI:StepRank("Bite", -6)
      assert.are.equal("Trained", plain(row("Bite").status:GetText()))
      -- Unticking returns to the sliders.
      UI.w.useCheck:SetChecked(false)
      UI.w.useCheck:Click()
      assert.is_true(UI.w.levelSlider:IsEnabled())
      assert.truthy(UI.w.petLine:GetText():match("^Simulating"))
    end)

    it("falls back to simulation when the pet is dismissed", function()
      UI:Show()
      setPet(FANG)
      UI:SetUseCurrent(true)
      setPet(nil)
      assert.is_false(UI.w.useCheck:GetChecked())
      assert.is_false(UI.w.useCheck:IsEnabled())
      assert.truthy(UI.w.petLine:GetText():match("^Simulating"))
      stub.fire(UI.w.useCheck, "OnEnter")
      assert.are.equal("No pet summoned", GameTooltip.lines[2])
    end)

    it("sets a saved build active for the pet and loads it when the pet is summoned again", function()
      UI:Show()
      setPet(FANG)
      UI:SetActiveForPet()
      assert.truthy(chatText():find("Fang is a Wolf. This build is for a Cat.", 1, true))
      stub.pick(UI.w.familyDD.frame, "Wolf")
      UI.w.saveBox:SetText("Wolf tank")
      UI.w.saveButton:Click()
      UI.w.activeButton:Click()
      assert.truthy(chatText():find('Fang is now tracking "Wolf tank".', 1, true))
      assert.are.equal("Wolf tank", UP.char.petBuild[7])
      -- Switch away, dismiss, then summon Fang with Use current pet on: the build comes back.
      stub.pick(UI.w.presetDD.frame, "PvP")
      UI:SetUseCurrent(true)
      setPet(nil)
      setPet(FANG)
      assert.are.equal("Wolf tank", UP.char.currentBuild.loaded)
      assert.is_true(UP.char.currentBuild.mine)
    end)

    it("refuses to set an unsaved, modified build active", function()
      UI:Show()
      setPet(FANG)
      stub.pick(UI.w.familyDD.frame, "Wolf")
      row("Cower").plus:Click()
      UI:SetActiveForPet()
      assert.truthy(chatText():find("Save the build first, then set it active.", 1, true))
    end)
  end)

  describe("presets and saved builds", function()
    it("lists the family's presets and My builds in the Preset menu", function()
      UI:Show()
      local items = stub.menu(UI.w.presetDD.frame)
      assert.are.equal("Presets for Cat", items[1].text)
      assert.is_true(items[1].isTitle)
      assert.are.equal("Raid DPS", items[2].text)
      assert.is_true(items[2].checked)
      assert.are.equal("My builds", items[#items - 1].text)
      assert.are.equal("(none saved for Cat)", items[#items].text)
      assert.is_true(items[#items].disabled)
    end)

    it("saves, updates, loads and deletes a build", function()
      UI:Show()
      UI.w.saveBox:SetText("Raid kitty")
      UI.w.saveButton:Click()
      assert.truthy(chatText():find('Saved "Raid kitty" to My builds (Cat).', 1, true))
      local saved = UP.char.builds["Raid kitty"]
      assert.are.same({ family = "Cat", level = 60, loyalty = 6,
        skills = { Bite = 8, Claw = 8, Dash = 3, Growl = 7, ["Great Stamina"] = 9, ["Natural Armor"] = 7 } }, saved)
      assert.are.equal("Raid kitty", UI.w.presetDD.frame.text)
      UI.w.saveButton:Click()
      assert.truthy(chatText():find('Updated "Raid kitty".', 1, true))

      local items = stub.menu(UI.w.presetDD.frame)
      assert.are.equal("Raid kitty", items[#items].text)
      assert.is_true(items[#items].checked)

      stub.pick(UI.w.presetDD.frame, "PvP")
      assert.are.equal(3, UP.char.currentBuild.skills.Prowl)
      UI.w.deleteButton:Click()
      local msg = "Load one of your builds from the Preset menu first. Bundled presets can't be deleted."
      assert.truthy(chatText():find(msg, 1, true))
      stub.pick(UI.w.presetDD.frame, "Raid kitty")
      assert.is_nil(UP.char.currentBuild.skills.Prowl)
      UI.w.deleteButton:Click()
      assert.truthy(chatText():find('Deleted "Raid kitty".', 1, true))
      assert.is_nil(UP.char.builds["Raid kitty"])
    end)

    it("asks for a name before saving", function()
      UI:Show()
      UI.w.saveButton:Click()
      assert.truthy(chatText():find("Enter a build name first.", 1, true))
    end)
  end)

  describe("export and import", function()
    it("round-trips the build through the edit boxes", function()
      UI:Show()
      stub.pick(UI.w.familyDD.frame, "Wolf")
      UI.w.levelSlider:Drag(52)
      UI.w.exportButton:Click()
      local str = UI.w.exportBox:GetText()
      assert.are.equal("UP1:Wolf:52-6:Bi8,Da3,Gr7,FH4,GS9,NA7", str)
      assert.is_true(UI.w.exportBox.highlighted)
      assert.truthy(chatText():find("Build string ready. Press Ctrl+C to copy.", 1, true))
      -- Read-only: typing restores the string.
      UI.w.exportBox:Type("junk")
      assert.are.equal(str, UI.w.exportBox:GetText())

      stub.pick(UI.w.familyDD.frame, "Cat")
      UI.w.importBox:SetText(str)
      UI.w.importButton:Click()
      assert.truthy(chatText():find("Imported Wolf build (6 skills).", 1, true))
      local build = UP.char.currentBuild
      assert.are.equal("Wolf", build.family)
      assert.are.equal(52, build.level)
      assert.are.equal("Imported", UI.w.presetDD.frame.text)
      assert.are.equal("", UI.w.importBox:GetText())
      UI.w.exportButton:Click()
      assert.are.equal(str, UI.w.exportBox:GetText())
    end)

    it("prints why an import failed", function()
      UI:Show()
      UI.w.importBox:SetText("hello")
      UI.w.importButton:Click()
      assert.are.equal("UltimatePet: Import failed: Not an UltimatePet string.", wow.takeChat()[1])
      assert.are.equal("Cat", UP.char.currentBuild.family)
    end)
  end)

  describe("popover", function()
    it("opens over the other column for a locked rank and lists its teachers", function()
      UI:Show()
      local bite, colIndex = row("Bite")
      assert.are.equal(1, colIndex)
      bite:Click()
      local p = UI.w.popover
      assert.is_true(p:IsShown())
      assert.are.equal("Bite (Rank 8)", p.title:GetText())
      assert.truthy(p.sub:GetText():match("2 teaching beasts$"))
      assert.is_true(p.entries[1]:IsShown())
      assert.are.equal(UI.w.cols[2], p.points[1][2])
      p.entries[1].button:Click()
      assert.truthy(chatText() ~= "")
      p.close:Click()
      assert.is_false(p:IsShown())
    end)

    it("does nothing for rows that are not locked, and closes when the rank is no longer locked", function()
      UI:Show()
      row("Growl"):Click()
      assert.is_false(UI.w.popover:IsShown())
      row("Bite"):Click()
      assert.is_true(UI.w.popover:IsShown())
      UP.char.unlocked.Bite = { [8] = true }
      UP:Fire("STATE_CHANGED")
      assert.is_false(UI.w.popover:IsShown())
    end)
  end)
end)
