-- UltimatePet: Waypoints.lua
-- Points the player at a teaching beast: a TomTom waypoint when TomTom is loaded, else the
-- built-in map pin, else the coordinates in chat. Every game API is optional and pcall-guarded.
local _, UP = ...

local Waypoints = UP.Waypoints or {}
UP.Waypoints = Waypoints

local format = string.format

-- Looks up a dotted global path ("C_Map.GetMapInfo") without erroring on missing tables.
local function lookup(path)
  local value = _G
  for part in path:gmatch("[^%.]+") do
    if type(value) ~= "table" then return nil end
    value = value[part]
  end
  return value
end

-- Calls the function at a dotted global path. Returns ok, results...; ok is false when the
-- function is missing or raised an error.
local function call(path, ...)
  local fn = lookup(path)
  if type(fn) ~= "function" then return false end
  return pcall(fn, ...)
end

local function npc(npcId)
  local beasts = UP.Beasts and UP.Beasts.npcs
  return beasts and beasts[npcId]
end

local function hasCoords(info)
  return type(info.map) == "number" and type(info.x) == "number" and type(info.y) == "number"
end

---"L57-59", or "L50" when the range is a single level.
local function levels(info)
  local min, max = info.min, info.max
  if not min then return max and ("L" .. max) or "" end
  if not max or max == min then return "L" .. min end
  return format("L%d-%d", min, max)
end

---Localised zone name for the npc's map, falling back to the stored English name.
local function zoneName(info)
  if info.map then
    local ok, mapInfo = call("C_Map.GetMapInfo", info.map)
    if ok and type(mapInfo) == "table" and type(mapInfo.name) == "string" and mapInfo.name ~= "" then
      return mapInfo.name
    end
  end
  return info.zone or "Unknown zone"
end

local function location(info)
  return format("%s %.1f, %.1f", zoneName(info), info.x, info.y)
end

function Waypoints:HasTomTom()
  return type(lookup("TomTom.AddWaypoint")) == "function"
end

-- TomTom:AddWaypoint(map, x, y, opts). Returns true when the call didn't error.
local function addTomTom(info, title)
  local tomtom = lookup("TomTom")
  local ok = pcall(tomtom.AddWaypoint, tomtom, info.map, info.x / 100, info.y / 100, {
    title = title,
    persistent = false,
    minimap = true,
    world = true,
    from = "UltimatePet",
  })
  return ok
end

-- Built-in map pin plus super-tracking where available. Returns true when the pin was placed.
local function addMapPin(info)
  if type(lookup("C_Map.SetUserWaypoint")) ~= "function" then return false end
  if type(lookup("C_Map.CanSetUserWaypointOnMap")) == "function" then
    local ok, can = call("C_Map.CanSetUserWaypointOnMap", info.map)
    if not ok or not can then return false end
  end
  local ok, point = call("UiMapPoint.CreateFromCoordinates", info.map, info.x / 100, info.y / 100)
  if not ok or point == nil then return false end
  if not call("C_Map.SetUserWaypoint", point) then return false end
  call("C_SuperTrack.SetSuperTrackedUserWaypoint", true)
  return true
end

---Sets a waypoint to a teaching beast and reports it in chat.
---Returns ok (a waypoint or pin was placed) and the message printed.
function Waypoints:Add(npcId, skill, rank)
  local info = npc(npcId)
  local msg
  if not info then
    msg = format("No beast known with id %s.", tostring(npcId))
    UP:Print(msg)
    return false, msg
  end

  local name = info.name or ("npc " .. tostring(npcId))
  if not hasCoords(info) then
    if info.instance then
      msg = format("%s (%s) is inside %s.", name, levels(info), info.instance)
    else
      msg = format("No location known for %s.", name)
    end
    UP:Print(msg)
    return false, msg
  end

  local what
  if skill then
    what = format("%s (%s Rank %s)", name, tostring(skill), tostring(rank or "?"))
  else
    what = format("%s (%s)", name, levels(info))
  end

  if self:HasTomTom() and addTomTom(info, "Tame: " .. what) then
    msg = format("Waypoint set: Tame %s - %s", what, location(info))
    UP:Print(msg)
    return true, msg
  end

  local where = format("Tame %s (%s) - %s.", name, levels(info), location(info))
  if addMapPin(info) then
    msg = "Map pin set: " .. where
    UP:Print(msg)
    return true, msg
  end
  UP:Print(where)
  return false, where
end

---One plain line for UI lists: "Name  L57-59  Winterspring 63.2, 58.1 (Rare)".
function Waypoints:Describe(npcId)
  local info = npc(npcId)
  if not info then return format("Unknown beast %s", tostring(npcId)) end
  local where
  if hasCoords(info) then
    where = location(info)
  elseif info.instance then
    -- The generator stores instance zones as "Zul'Gurub (Raid)" / "Uldaman (Dungeon)".
    local kind = type(info.zone) == "string" and info.zone:match("%((%a+)%)$")
    where = format("%s (%s)", info.instance, kind and kind:lower() or "dungeon")
  else
    where = info.zone or "location unknown"
  end
  local line = format("%s  %s  %s", info.name or tostring(npcId), levels(info), where)
  if info.class then
    line = line .. " (" .. info.class .. ")"
  end
  return line
end
