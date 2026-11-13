local wow = dofile("tests/wowstub.lua")

-- Loads only what Waypoints needs, so the spec doesn't depend on the other modules.
local function load()
  wow.reset()
  local ns = {}
  for _, file in ipairs({ "Core.lua", "Data/Beasts.lua", "Waypoints.lua" }) do
    assert(loadfile(file))("UltimatePet", ns)
  end
  return ns
end

-- Optional client APIs this spec installs on the real _G (busted sandboxes plain global writes,
-- which the addon code would not see); cleared between tests.
local OPTIONAL = { "TomTom", "C_Map", "UiMapPoint", "C_SuperTrack" }

-- Real npcs from Data/Beasts.lua.
local CUB = 7430      -- Frostsaber Cub, Winterspring (1452) 49.8, 9.6, L55-56
local LUPOS = 521     -- Lupos, Rare, Duskwood (1431) 25.6, 27.2, L23
local WORG = 9416     -- Scarshield Worg, Blackrock Spire, no coords, L53-54
local SON = 11357     -- Son of Hakkar, Elite, Zul'Gurub (raid), L60

describe("Waypoints", function()
  local UP, W, calls

  local function installMap(opts)
    opts = opts or {}
    _G.C_Map = {
      GetMapInfo = function(map)
        calls.mapInfo = map
        if map == 1452 then return { name = "Winterspring (loc)" } end
        return nil
      end,
      SetUserWaypoint = function(point) calls.pin = point end,
      CanSetUserWaypointOnMap = opts.can ~= nil and function(map)
        calls.canMap = map
        return opts.can
      end or nil,
    }
    _G.UiMapPoint = {
      CreateFromCoordinates = function(map, x, y) return { map = map, x = x, y = y } end,
    }
  end

  before_each(function()
    for _, name in ipairs(OPTIONAL) do _G[name] = nil end
    calls = {}
    UP = load()
    W = UP.Waypoints
  end)

  after_each(function()
    for _, name in ipairs(OPTIONAL) do _G[name] = nil end
  end)

  describe("with TomTom", function()
    before_each(function()
      _G.TomTom = {
        AddWaypoint = function(self, map, x, y, opts)
          calls.tomtom = { self = self, map = map, x = x, y = y, opts = opts }
          return {}
        end,
      }
      installMap()
    end)

    it("detects TomTom", function()
      assert.is_true(W:HasTomTom())
    end)

    it("adds a TomTom waypoint with 0-1 coordinates and prints the localised zone", function()
      local ok, msg = W:Add(CUB, "Bite", 7)
      assert.is_true(ok)
      local t = calls.tomtom
      assert.are.equal(TomTom, t.self)
      assert.are.equal(1452, t.map)
      assert.is_true(math.abs(t.x - 0.498) < 1e-9)
      assert.is_true(math.abs(t.y - 0.096) < 1e-9)
      assert.are.same({
        title = "Tame: Frostsaber Cub (Bite Rank 7)",
        persistent = false, minimap = true, world = true, from = "UltimatePet",
      }, t.opts)
      assert.are.equal("Waypoint set: Tame Frostsaber Cub (Bite Rank 7) - Winterspring (loc) 49.8, 9.6", msg)
      assert.are.same({ "UltimatePet: " .. msg }, wow.takeChat())
      assert.is_nil(calls.pin)
    end)

    it("falls back to the stored zone name when GetMapInfo has none", function()
      local _, msg = W:Add(LUPOS, "Dash", 1)
      assert.are.equal("Waypoint set: Tame Lupos (Dash Rank 1) - Duskwood 25.6, 27.2", msg)
    end)

    it("falls back to the map pin when TomTom errors", function()
      TomTom.AddWaypoint = function() error("boom") end
      local ok, msg = W:Add(CUB, "Bite", 7)
      assert.is_true(ok)
      assert.are.equal("Map pin set: Tame Frostsaber Cub (L55-56) - Winterspring (loc) 49.8, 9.6.", msg)
    end)
  end)

  describe("without TomTom", function()
    it("reports no TomTom", function()
      assert.is_false(W:HasTomTom())
    end)

    it("places the built-in map pin and super-tracks it", function()
      installMap()
      _G.C_SuperTrack = { SetSuperTrackedUserWaypoint = function(v) calls.supertrack = v end }
      local ok, msg = W:Add(CUB, "Bite", 7)
      assert.is_true(ok)
      assert.are.same({ map = 1452, x = 49.8 / 100, y = 9.6 / 100 }, calls.pin)
      assert.is_true(calls.supertrack)
      assert.are.equal("Map pin set: Tame Frostsaber Cub (L55-56) - Winterspring (loc) 49.8, 9.6.", msg)
      assert.are.same({ "UltimatePet: " .. msg }, wow.takeChat())
    end)

    it("places the pin when CanSetUserWaypointOnMap allows it, without C_SuperTrack", function()
      installMap({ can = true })
      local ok, msg = W:Add(LUPOS, "Dash", 1)
      assert.is_true(ok)
      assert.are.equal(1431, calls.canMap)
      assert.are.equal("Map pin set: Tame Lupos (L23) - Duskwood 25.6, 27.2.", msg)
    end)

    it("prints only the coordinates when the map can't take a pin", function()
      installMap({ can = false })
      local ok, msg = W:Add(CUB, "Bite", 7)
      assert.is_false(ok)
      assert.is_nil(calls.pin)
      assert.are.equal("Tame Frostsaber Cub (L55-56) - Winterspring (loc) 49.8, 9.6.", msg)
      assert.are.same({ "UltimatePet: " .. msg }, wow.takeChat())
    end)

    it("prints only the coordinates when SetUserWaypoint errors", function()
      installMap()
      C_Map.SetUserWaypoint = function() error("nope") end
      local ok, msg = W:Add(CUB, "Bite", 7)
      assert.is_false(ok)
      assert.are.equal("Tame Frostsaber Cub (L55-56) - Winterspring (loc) 49.8, 9.6.", msg)
    end)

    it("works with C_Map and UiMapPoint missing entirely", function()
      local ok, msg = W:Add(CUB, "Bite", 7)
      assert.is_false(ok)
      assert.are.equal("Tame Frostsaber Cub (L55-56) - Winterspring 49.8, 9.6.", msg)
      assert.are.equal("Frostsaber Cub  L55-56  Winterspring 49.8, 9.6", W:Describe(CUB))
    end)
  end)

  describe("beasts without coordinates", function()
    it("says which dungeon a beast is in, with or without TomTom", function()
      _G.TomTom = { AddWaypoint = function() calls.tomtom = true end }
      local ok, msg = W:Add(WORG, "Bite", 8)
      assert.is_false(ok)
      assert.is_nil(calls.tomtom)
      assert.are.equal("Scarshield Worg (L53-54) is inside Blackrock Spire.", msg)
      assert.are.same({ "UltimatePet: " .. msg }, wow.takeChat())
    end)

    it("reports no location for a beast with neither coordinates nor instance", function()
      UP.Beasts.npcs[999999] = { name = "Ghost Cat", family = "Cat", min = 10, max = 10, zone = "Nowhere" }
      local ok, msg = W:Add(999999, "Claw", 1)
      assert.is_false(ok)
      assert.are.equal("No location known for Ghost Cat.", msg)
    end)

    it("handles an unknown npc id", function()
      local ok, msg = W:Add(123456789, "Bite", 1)
      assert.is_false(ok)
      assert.are.equal("No beast known with id 123456789.", msg)
      assert.are.equal("Unknown beast 123456789", W:Describe(123456789))
    end)
  end)

  describe("Describe", function()
    it("formats an open-world beast with the localised zone", function()
      installMap()
      assert.are.equal("Frostsaber Cub  L55-56  Winterspring (loc) 49.8, 9.6", W:Describe(CUB))
    end)

    it("uses a single level and a class suffix", function()
      assert.are.equal("Lupos  L23  Duskwood 25.6, 27.2 (Rare)", W:Describe(LUPOS))
    end)

    it("names dungeons and raids", function()
      assert.are.equal("Scarshield Worg  L53-54  Blackrock Spire (dungeon)", W:Describe(WORG))
      assert.are.equal("Son of Hakkar  L60  Zul'Gurub (raid) (Elite)", W:Describe(SON))
    end)

    it("treats a missing max level as a single level", function()
      UP.Beasts.npcs[999998] = { name = "Odd Bat", min = 50, zone = "Felwood", map = 1448, x = 1, y = 2 }
      assert.are.equal("Odd Bat  L50  Felwood 1.0, 2.0", W:Describe(999998))
    end)
  end)
end)
