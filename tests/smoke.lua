-- Load smoke test with plain Lua 5.1 (no busted): `lua tests/smoke.lua` from the repository root.
-- Loads every TOC file through the WoW stub, fires ADDON_LOADED and runs a few slash commands,
-- echoing the chat output. Exits non-zero on any error.
local wow = dofile("tests/wowstub.lua")

local UP = wow.load()
dofile("tests/uistub.lua").install() -- frame API for /upet show
wow.fire("ADDON_LOADED", "UltimatePet")
assert(type(UltimatePetDB) == "table", "UltimatePetDB not created")
local commands = {
  "/upet help", "/upet debug", "/ultimatepet show", "/upet", "/upet scan", "/upet pet", "/upet minimap",
  "/upet reset", "/upet reset confirm",
}
for _, line in ipairs(commands) do
  print("> " .. line)
  assert(wow.slash(line), "no handler for " .. line)
  for _, msg in ipairs(wow.takeChat()) do print("  " .. msg) end
end
print("OK: UltimatePet " .. UP.version .. " loaded, DB v" .. UltimatePetDB.version)
