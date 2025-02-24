local expect = require "cc.expect".expect
package.path = package.path .. ";lib/?.lua;lib/?/init.lua"
local aid = require("turtle_aid")
local file_helper = require("file_helper")
local root_folder = file_helper:instanced("")
local data_folder = file_helper:instanced("data")
local logging = require("logging")
local simple_argparse = require("simple_argparse")
local LOG_FILE = fs.combine(data_folder.working_directory, ("dog%d.log"):format(math.random(0, 100000)))
local STATE_FILE = "dog.state"
local main_win = term.current()
local max_depth = 512
local log_level = logging.LOG_LEVEL.INFO
local tx, ty = term.getSize()
local log_win = window.create(window.create(main_win, 1, 1, tx, 7), 1, 1, tx, 8)
local data_win = window.create(main_win, 1, 8, tx, ty - 7)
local geoscanner_range = 8
local max_offset = 8
local scan = nil
local do_fuel = false
local horizontal = false
local version = "V0.14.3"
local latest_changes = [[Added a few more blocks as ores. If you wish to add some that are missing, PRs are open!]]
local parser = simple_argparse.new_parser("dog", "Dog is a program run on mining turtles which is used to find ores and mine them. Unlike quarry programs, this program digs in a straight line down and uses either plethora's block scanner or advanced peripheral's geoscanner to detect where ores are along its path and mine to them.")
parser.add_option("depth", "The maximum depth to dig to.", max_depth)
parser.add_option("loglevel", "The log level to use.", "INFO")
parser.add_option("georange", "The range to use for the geoscanner, if using Advanced Peripherals.", geoscanner_range)
parser.add_option("exclude", "A file (lua table) containing ores to exclude from mining.")
parser.add_option("include", "A file (lua table) containing blocks to include in mining.")
parser.add_option("only", "A file (lua table) containing blocks that should be the only ones mined.")
parser.add_option("maxdistance", "The maximum horizontal distance from home to travel.", 64)
parser.add_flag("h", "help", "Show this help message and exit.")
parser.add_flag("f", "fuel", "Attempt to refuel as needed from ores mined.")
parser.add_flag("v", "version", "Show version information and exit.")
parser.add_flag("l", "level", "Travel in a horizontal line at the current level. Useful for mining sand and other surface ores when used in tandem with include or only.")
parser.add_flag("m", "muzzle", "Muzzle the dog. This will prevent the dog from barking, but he will be sad.")
parser.add_flag("b", "bark", "Antagonize the dog by barking at it, this will make the dog bark A LOT.")
parser.add_argument("max_offset", "The maximum offset from the centerpoint to mine to.", false, max_offset)
local parsed = parser.parse(table.pack(...))
term.setCursorPos(1, 3)
if parsed.flags.help then local _, h = term.getSize() textutils.pagedPrint(parser.usage()) return end
if parsed.flags.version then print(version) print() print("Latest update notes:", latest_changes) return end
if parsed.flags.fuel then do_fuel = true end
if parsed.flags.level then horizontal = true end
if parsed.options.loglevel then log_level = logging.LOG_LEVEL[parsed.options.loglevel:upper()] if not log_level then error("Invalid log level.", 0) end end
if parsed.options.depth then max_depth = tonumber(parsed.options.depth) if not max_depth then error("Max depth must be a number.", 0) end end
if parsed.options.georange then geoscanner_range = tonumber(parsed.options.georange) if not geoscanner_range then error("Geo range must be a number.", 0) end end
local max_distance = 64
if parsed.options.maxdistance then max_distance = tonumber(parsed.options.maxdistance) if not max_distance then error("Max horizontal distance must be a number.", 0) end end
if parsed.arguments[1] then max_offset = tonumber(parsed.arguments[1]) if not max_offset then error("Max offset must be a number.", 0) end end
logging.set_level(log_level)
logging.set_window(log_win)
do
  local setup_context = logging.create_context("Setup")
  setup_context.info("Checking for pickaxe and scanner.")
  local scanner, geoscanner = aid.is_module_equipped("scanner"), aid.is_module_equipped("geoScanner")
  if scanner or geoscanner then
    setup_context.debug("Found scanner.")
    if scanner and geoscanner then error("Who ported which mod to which loader, and why?", 0) end
  else
    if aid.swap_module("scanner", "left") then scanner = "left" setup_context.debug("Found scanner.") elseif aid.swap_module("geoScanner", "left") then geoscanner = "left" setup_context.debug("Found geoscanner.") else error("No scanner or geoscanner found.", 0) end
  end
  if aid.is_module_equipped("pickaxe") then
    setup_context.debug("Found pickaxe.")
  else
    if aid.swap_module("pickaxe", "right") then setup_context.debug("Found pickaxe.") else error("No pickaxe found.", 0) end
  end
  if scanner then
    setup_context.debug("Using scanner on", scanner, "side.")
    scan = function() return peripheral.call(scanner, "scan") end
  end
  if geoscanner then
    setup_context.debug("Using geoscanner on", geoscanner, "side.")
    scan = function() return peripheral.call(geoscanner, "scan", geoscanner_range) end
  end
end
local ORE_DICT = {
  ["minecraft:iron_ore"] = true,
  ["minecraft:deepslate_iron_ore"] = true,
  ["minecraft:copper_ore"] = true,
  ["minecraft:deepslate_copper_ore"] = true,
  ["minecraft:gold_ore"] = true,
  ["minecraft:deepslate_gold_ore"] = true,
  ["minecraft:diamond_ore"] = true,
  ["minecraft:deepslate_diamond_ore"] = true,
  ["minecraft:coal_ore"] = true,
  ["minecraft:deepslate_coal_ore"] = true,
  ["minecraft:lapis_ore"] = true,
  ["minecraft:deepslate_lapis_ore"] = true,
  ["minecraft:emerald_ore"] = true,
  ["minecraft:deepslate_emerald_ore"] = true,
  ["minecraft:quartz_ore"] = true,
  ["minecraft:nether_quartz_ore"] = true,
  ["minecraft:redstone_ore"] = true,
  ["minecraft:deepslate_redstone_ore"] = true,
  ["minecraft:nether_gold_ore"] = true,
  ["minecraft:ancient_debris"] = true,
  ["minecraft:glowstone"] = true,
  ["create:zinc_ore"] = true,
  ["create_deepslate_zinc_ore"] = true,
  ["mekanism:tin_ore"] = true,
  ["mekanism:deepslate_tin_ore"] = true,
  ["mekanism:osmium_ore"] = true,
  ["mekanism:deepslate_osmium_ore"] = true,
  ["mekanism:uranium_ore"] = true,
  ["mekanism:deepslate_uranium_ore"] = true,
  ["mekanism:fluorite_ore"] = true,
  ["mekanism:deepslate_fluorite_ore"] = true,
  ["mekanism:lead_ore"] = true,
  ["mekanism:deepslate_lead_ore"] = true,
  ["thermal:apatite_ore"] = true,
  ["thermal:deepslate_apatite_ore"] = true,
  ["thermal:cinnabar_ore"] = true,
  ["thermal:deepslate_cinnabar_ore"] = true,
  ["thermal:niter_ore"] = true,
  ["thermal:deepslate_niter_ore"] = true,
  ["thermal:sulfur_ore"] = true,
  ["thermal:deepslate_sulfur_ore"] = true,
  ["thermal:tin_ore"] = true,
  ["thermal:deepslate_tin_ore"] = true,
  ["thermal:lead_ore"] = true,
  ["thermal:deepslate_lead_ore"] = true,
  ["thermal:silver_ore"] = true,
  ["thermal:deepslate_silver_ore"] = true,
  ["thermal:nickel_ore"] = true,
  ["thermal:deepslate_nickel_ore"] = true,
  ["thermal:ruby_ore"] = true,
  ["thermal:deepslate_ruby_ore"] = true,
  ["thermal:sapphire_ore"] = true,
  ["thermal:deepslate_sapphire_ore"] = true,
  ["rftoolsbase:dimensionalshard_overworld"] = true,
  ["rftoolsbase:dimensionalshard_nether"] = true,
  ["rftoolsbase:dimensionalshard_end"] = true,
  ["deepresonance:resonating_ore_stone"] = true,
  ["deepresonance:resonating_ore_deepslate"] = true,
  ["deepresonance:resonating_ore_nether"] = true,
  ["deepresonance:resonating_ore_end"] = true,
}
local FORBIDDEN_BLOCKS = {
  ["minecraft:chest"] = true,
  ["minecraft:trapped_chest"] = true,
  ["minecraft:ender_chest"] = true,
  ["waystones:magenta_sharestone"] = true,
}
if parsed.options.exclude then
  if root_folder:exists(parsed.options.exclude) then
    local exclude = root_folder:unserialize(parsed.options.exclude)
    if type(exclude) == "table" then
      for key, value in pairs(exclude) do
        if type(key) == "string" then ORE_DICT[key] = nil end
        if type(value) == "string" then ORE_DICT[value] = nil end
      end
    else error("Failed to parse exclude file.", 0) end
  else error("Exclude file does not exist.", 0) end
end
if parsed.options.include then
  if root_folder:exists(parsed.options.include) then
    local include = root_folder:unserialize(parsed.options.include)
    if type(include) == "table" then
      for key, value in pairs(include) do
        if type(key) == "string" then ORE_DICT[key] = true end
        if type(value) == "string" then ORE_DICT[value] = true end
      end
    else error("Failed to parse include file.", 0) end
  else error("Include file does not exist.", 0) end
end
if parsed.options.only then
  if root_folder:exists(parsed.options.only) then
    local only = root_folder:unserialize(parsed.options.only)
    if type(only) == "table" then
      ORE_DICT = {}
      for key, value in pairs(only) do
        if type(key) == "string" then ORE_DICT[key] = true end
        if type(value) == "string" then ORE_DICT[value] = true end
      end
    else error("Failed to parse only file.", 0) end
  else error("Only file does not exist.", 0) end
end
local state = { state = "digdown", state_info = {depth = 0} }
local function strip_and_offset_scan(data)
  local stripped = {}
  for _, block in ipairs(data) do
    table.insert(stripped, { x = block.x + aid.position.x, y = block.y + aid.position.y, z = block.z + aid.position.z, name = block.name })
  end
  return stripped
end
local function scan_ores()
  local scanned = scan()
  if type(scanned) == "table" then state.state_info.last_scan = strip_and_offset_scan(scanned) end
end
local function save_state() data_folder:serialize(STATE_FILE, state, true) end
local function load_state() local loaded_state = data_folder:unserialize(STATE_FILE, { state = "digdown", state_info = {depth = 0} }) if loaded_state then state = loaded_state end end
local ore_context = logging.create_context("Ore")
local function get_closest_ore(initial_facing)
  local closest_ore local closest_distance = math.huge
  for i, block in ipairs(state.state_info.last_scan) do
    local distance = math.abs(block.x - aid.position.x) + math.abs(block.y - aid.position.y) + math.abs(block.z - aid.position.z)
    local out_of_range = false
    if horizontal then
      local initial_axis = (initial_facing == 0 or initial_facing == 2) and "z" or "x"
      local opposite_axis = initial_axis == "z" and "x" or "z"
      out_of_range = block.y < -max_offset or block.y > max_offset or block[opposite_axis] > max_offset or block[opposite_axis] < -max_offset or block[initial_axis] < -max_distance or block[initial_axis] > max_distance
    else
      out_of_range = block.y < -max_depth or block.x < -max_offset or block.x > max_offset or block.z < -max_offset or block.z > max_offset
    end
    if not out_of_range and ORE_DICT[block.name] and distance < closest_distance then
      closest_ore = i
      closest_distance = distance
    end
  end
  return closest_ore
end
local dig_context = logging.create_context("Dig")
local function check_next_ore()
  scan_ores()
  local ore_index = get_closest_ore()
  if ore_index then
    state.state_info.ore_index = ore_index
    state.state_info.ore = state.state_info.last_scan[ore_index]
    state.state = "seeking"
    return true
  end
  return false
end
local function dig_forward
