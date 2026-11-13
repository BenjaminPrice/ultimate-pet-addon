-- luacheck config: run `luacheck .` from the repository root.
std = "lua51"
max_line_length = 120
codes = true
self = false -- UP:Method() style throughout, self often unused
exclude_files = { ".ai/**", "Libs/**", ".serena/**", "**/refs/**", "tools/sources/**", ".lua/**", ".luarocks/**", ".install/**" }

-- The only globals the addon defines.
globals = {
  "UltimatePetDB",
  "SLASH_ULTIMATEPET1",
  "SLASH_ULTIMATEPET2",
  SlashCmdList = { fields = { "ULTIMATEPET" } },
}

-- WoW API the addon reads directly. Optional APIs are reached through UP.lookup.
read_globals = {
  "C_AddOns",
  "CreateFrame",
  "DEFAULT_CHAT_FRAME",
  "GetAddOnMetadata",
  "GetBuildInfo",
  "GetRealmName",
  "UnitName", "UnitExists", "UnitCreatureFamily",
  "time",
}

-- The WoW stub installs the fake client's globals; the specs poke at them.
files["tests/"] = {
  std = "+busted",
  globals = {
    "CreateFrame", "UnitName", "UnitCreatureFamily", "GetRealmName", "GetTime", "GetBuildInfo", "GetAddOnMetadata",
    "C_AddOns", "C_Timer", "DEFAULT_CHAT_FRAME", "SlashCmdList", "UltimatePetDB",
    "SLASH_ULTIMATEPET1", "SLASH_ULTIMATEPET2",
  },
}

-- Optional map / waypoint APIs the Waypoints spec installs and clears.
files["tests/waypoints_spec.lua"] = {
  std = "+busted",
  globals = { "TomTom", "C_Map", "UiMapPoint", "C_SuperTrack" },
}
