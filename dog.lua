--- Dog is a program run on mining turtles which is used to find ores and mine
--- them. Unlike quarry programs, this program digs in a straight line down and
--- uses either plethora's block scanner or advanced peripheral's geoscanner to
--- detect where ores are along its path and mine to them.

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
parser.add_argument("max_offset", "The maximum offset from the centerpoint to mine to.", false,  max_offset)

local parsed = parser.parse(table.pack(...))

term.setCursorPos(1, 3)

if parsed.flags.help then
  local _, h = term.getSize()
  textutils.pagedPrint(parser.usage())
  return
end
if parsed.flags.version then
  print(version)
  print()
  print("Latest update notes:", latest_changes)
  return
end
if parsed.flags.fuel then
  do_fuel = true
end
if parsed.flags.level then
  horizontal = true
end

if parsed.options.loglevel then
  log_level = logging.LOG_LEVEL[parsed.options.loglevel:upper()]
  if not log_level then
    error("Invalid log level.", 0)
  end
end
if parsed.options.depth then
  max_depth = tonumber(parsed.options.depth)
  if not max_depth then
    error("Max depth must be a number.", 0)
  end
end
if parsed.options.georange then
  geoscanner_range = tonumber(parsed.options.georange)
  if not geoscanner_range then
    error("Geo range must be a number.", 0)
  end
end
local max_distance = 64
if parsed.options.maxdistance then
  max_distance = tonumber(parsed.options.maxdistance)
  if not max_distance then
    error("Max horizontal distance must be a number.", 0)
  end
end

if parsed.arguments[1] then
  max_offset = tonumber(parsed.arguments[1])
  if not max_offset then
    error("Max offset must be a number.", 0)
  end
end

logging.set_level(log_level)
logging.set_window(log_win)

do
  local setup_context = logging.create_context("Setup")
  setup_context.info("Checking for pickaxe and scanner.")

  local scanner, geoscanner = aid.is_module_equipped("scanner"), aid.is_module_equipped("geoScanner")

  if scanner or geoscanner then
    setup_context.debug("Found scanner.")
    if scanner and geoscanner then
      error("Who ported which mod to which loader, and why?", 0)
    end
  else
    if aid.swap_module("scanner", "left") then
      scanner = "left"
      setup_context.debug("Found scanner.")
    elseif aid.swap_module("geoScanner", "left") then
      geoscanner = "left"
      setup_context.debug("Found geoscanner.")
    else
      error("No scanner or geoscanner found.", 0)
    end
  end

  if aid.is_module_equipped("pickaxe") then
    setup_context.debug("Found pickaxe.")
  else
    if aid.swap_module("pickaxe", "right") then
      setup_context.debug("Found pickaxe.")
    else
      error("No pickaxe found.", 0)
    end
  end

  if scanner then
    setup_context.debug("Using scanner on", scanner, "side.")
    scan = function()
      return peripheral.call(scanner, "scan")
    end
  end

  if geoscanner then
    setup_context.debug("Using geoscanner on", geoscanner, "side.")
    scan = function()
      return peripheral.call(geoscanner, "scan", geoscanner_range)
    end
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
}

if parsed.options.exclude then
  if root_folder:exists(parsed.options.exclude) then
    local exclude = root_folder:unserialize(parsed.options.exclude)
    if type(exclude) == "table" then
      for key, value in pairs(exclude) do
        if type(key) == "string" then
          ORE_DICT[key] = nil
        end
        if type(value) == "string" then
          ORE_DICT[value] = nil
        end
      end
    else
      error("Failed to parse exclude file.", 0)
    end
  else
    error("Exclude file does not exist.", 0)
  end
end
if parsed.options.include then
  if root_folder:exists(parsed.options.include) then
    local include = root_folder:unserialize(parsed.options.include)
    if type(include) == "table" then
      for key, value in pairs(include) do
        if type(key) == "string" then
          ORE_DICT[key] = true
        end
        if type(value) == "string" then
          ORE_DICT[value] = true
        end
      end
    else
      error("Failed to parse include file.", 0)
    end
  else
    error("Include file does not exist.", 0)
  end
end
if parsed.options.only then
  if root_folder:exists(parsed.options.only) then
    local only = root_folder:unserialize(parsed.options.only)
    if type(only) == "table" then
      ORE_DICT = {}
      for key, value in pairs(only) do
        if type(key) == "string" then
          ORE_DICT[key] = true
        end
        if type(value) == "string" then
          ORE_DICT[value] = true
        end
      end
    else
      error("Failed to parse only file.", 0)
    end
  else
    error("Only file does not exist.", 0)
  end
end

local state = {
  state = "digdown",
  state_info = {depth = 0}
}

local function strip_and_offset_scan(data)
  local stripped = {}

  for _, block in ipairs(data) do
    table.insert(stripped, {
      x = block.x + aid.position.x,
      y = block.y + aid.position.y,
      z = block.z + aid.position.z,
      name = block.name
    })
  end

  return stripped
end

local function scan_ores()
  local scanned = scan()
  if type(scanned) == "table" then
    state.state_info.last_scan = strip_and_offset_scan(scanned)
  end
end

local function save_state()
  data_folder:serialize(STATE_FILE, state, true)
end

local function load_state()
  local loaded_state = data_folder:unserialize(STATE_FILE ,{
    state = "digdown",
    state_info = {depth = 0}
  })
  if loaded_state then
    state = loaded_state
  end
end

local ore_context = logging.create_context("Ore")

local function get_closest_ore(initial_facing)
  local closest_ore
  local closest_distance = math.huge
  for i, block in ipairs(state.state_info.last_scan) do
    local distance = math.abs(block.x - aid.position.x) + math.abs(block.y - aid.position.y) + math.abs(block.z - aid.position.z)
    local out_of_range = false
    if horizontal then
      local initial_axis = (initial_facing == 0 or initial_facing == 2) and "z" or "x"
      local opposite_axis = initial_axis == "z" and "x" or "z"
      out_of_range = block.y < -max_offset or block.y > max_offset
        or block[opposite_axis] > max_offset or block[opposite_axis] < -max_offset
        or block[initial_axis] < -max_distance or block[initial_axis] > max_distance
    else
      out_of_range = block.y < -max_depth
        or block.x < -max_offset or block.x > max_offset
        or block.z < -max_offset or block.z > max_offset
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

local function dig_forward(initial_facing)
  dig_context.debug("Digging forward.")

  local forward_axis
  if initial_facing == 0 or initial_facing == 2 then
    forward_axis = "z"
  else
    forward_axis = "x"
  end

  dig_context.debug("Current depth is", math.abs(aid.position[forward_axis]))
  dig_context.debug("Max horizontal distance is", max_distance)

  if math.abs(aid.position[forward_axis]) >= max_distance then
    dig_context.info("Reached max horizontal distance, returning home.")
    state.state = "returning_home"
    return
  end

  local success, block = turtle.inspect()
  if success and FORBIDDEN_BLOCKS[block.name] then
    dig_context.warn("Forbidden block detected in front (" .. block.name .. "), returning home.")
    state.state = "returning_home"
    return
  end

  check_next_ore()
  aid.face(initial_facing)
  turtle.dig()
  aid.go_forward()
  state.state_info.depth = aid.position[forward_axis]
end

local function dig_down()
  dig_context.debug("Digging down.")

  dig_context.debug("Current depth is", aid.position.y)
  dig_context.debug("Max depth is", max_depth)

  if aid.position.y < -max_depth then
    dig_context.info("Reached max depth, returning home.")
    state.state = "returning_home"
    return
  end

  local success, block_data = turtle.inspectDown()
  if success and (block_data.name == "minecraft:bedrock" or FORBIDDEN_BLOCKS[block_data.name]) then
    if block_data.name == "minecraft:bedrock" then
      dig_context.warn("Hit bedrock, returning home.")
    else
      dig_context.warn("Hit forbidden block (" .. block_data.name .. "), returning home.")
    end
    state.state = "returning_home"
    return
  end

  if check_next_ore() then
    return
  end

  turtle.digDown()
  aid.go_down()
  state.state_info.depth = aid.position.y
end

local bedrock_watch = logging.create_context("Bedrock Watch")
local function inspect_for_bedrock(direction)
  if direction == "forward" then
    local success, block = turtle.inspect()
    if success and (block.name == "minecraft:bedrock" or FORBIDDEN_BLOCKS[block.name]) then
      if block.name == "minecraft:bedrock" then
        bedrock_watch.warn("Hit bedrock, returning home.")
      else
        bedrock_watch.warn("Hit forbidden block (" .. block.name .. "), returning home.")
      end
      state.state = "returning_home"
      return true
    end
  elseif direction == "up" then
    local success, block = turtle.inspectUp()
    if success and (block.name == "minecraft:bedrock" or FORBIDDEN_BLOCKS[block.name]) then
      if block.name == "minecraft:bedrock" then
        bedrock_watch.warn("Hit bedrock above, returning home.")
      else
        bedrock_watch.warn("Hit forbidden block (" .. block.name .. ") above, returning home.")
      end
      state.state = "returning_home"
      return true
    end
  elseif direction == "down" then
    local success, block = turtle.inspectDown()
    if success and (block.name == "minecraft:bedrock" or FORBIDDEN_BLOCKS[block.name]) then
      if block.name == "minecraft:bedrock" then
        bedrock_watch.warn("Hit bedrock below, returning home.")
      else
        bedrock_watch.warn("Hit forbidden block (" .. block.name .. ") below, returning home.")
      end
      state.state = "returning_home"
      return true
    end
  end
  return false
end

local seek_context = logging.create_context("Seek")
local function seek(initial_facing)
  local ore = state.state_info.ore
  local x, y, z = ore.x, ore.y, ore.z
  local direction, distance = aid.get_direction_to(vector.new(x, y, z), true)
  seek_context.debug("Seeking to ore.")
  seek_context.debug("Ore is", distance, "blocks away, positioned at", x, y, z)
  seek_context.debug("Turtle is positioned at", aid.position.x, aid.position.y, aid.position.z)

  if distance == 1 then
    if FORBIDDEN_BLOCKS[ore.name] then
      seek_context.warn("Forbidden block adjacent (" .. ore.name .. "), returning home.")
      state.state = "returning_home"
      return
    end
    seek_context.info("Ore is adjacent, mining.")
    if direction == "up" then
      turtle.digUp()
    elseif direction == "down" then
      turtle.digDown()
    else
      aid.face(direction)
      turtle.dig()
    end
    table.remove(state.state_info.last_scan, state.state_info.ore_index)
    seek_context.info("Ore mined, rescanning for more ores.")

    if not check_next_ore() then
      seek_context.info("No more ores found, returning from seek.")
      state.state = "returning_from_seek"
    end

    return
  end

  if direction == "up" then
    if inspect_for_bedrock("up") then return end
    aid.gravel_protected_dig_up()
    aid.go_up()
  elseif direction == "down" then
    if inspect_for_bedrock("down") then return end
    turtle.digDown()
    aid.go_down()
  elseif not direction then
    error("Direction is nil, we're already on top of the detected ore!", 0)
  else
    aid.face(direction)
    if inspect_for_bedrock("forward") then return end
    aid.gravel_protected_dig()
    aid.go_forward()
  end
end

local function goto_safe(x, y, z)
  local direction, distance = aid.get_direction_to(vector.new(x, y, z), false, true)

  if distance == 0 then
    return true, false
  end

  if direction == "up" then
    if inspect_for_bedrock("up") then
      bedrock_watch.warn("Obstacle hit in return path, triggering path retrace. Ticking will stop momentarily.")
      aid.retrace(true)
      return false, true
    end
    aid.gravel_protected_dig_up()
    aid.go_up()
  elseif direction == "down" then
    if inspect_for_bedrock("down") then
      bedrock_watch.warn("Obstacle hit in return path, triggering path retrace. Ticking will stop momentarily.")
      aid.retrace(true)
      return false, true
    end
    turtle.digDown()
    aid.go_down()
  else
    aid.face(direction)
    if inspect_for_bedrock("forward") then
      bedrock_watch.warn("Obstacle hit in return path, triggering path retrace. Ticking will stop momentarily.")
      aid.retrace(true)
      return false, true
    end
    aid.gravel_protected_dig()
    aid.go_forward()
  end

  return false, false
end

local function return_home()
  local finished, bedrock = goto_safe(0, 0, 0)
  if finished then
    return true
  end

  if bedrock then
    bedrock_watch.info("Path retrace complete.")
  end
  return false
end

local r_seek_context = logging.create_context("Return from seek")
local function return_seek(initial_facing)
  local finished, bedrock
  if horizontal then
    local initial_axis = (initial_facing == 0 or initial_facing == 2) and "z" or "x"
    if initial_axis == "z" then
      finished, bedrock = goto_safe(0, 0, state.state_info.depth)
    else
      finished, bedrock = goto_safe(state.state_info.depth, 0, 0)
    end
  else
    finished, bedrock = goto_safe(0, state.state_info.depth, 0)
  end
  if finished then
    state.state = "digdown"
    return true
  end

  if bedrock then
    bedrock_watch.info("Path retrace complete.")
  end
  return false
end

local dump_context = logging.create_context("Dump Inventory")
local function dump_inventory()
  while not aid.find_chest() do
    dump_context.warn("Unable to find chest, waiting 5 seconds.")
    sleep(5)
  end

  for i = 1, 16 do
    if turtle.getItemCount(i) > 0 then
      turtle.select(i)
      if do_fuel and turtle.refuel() then
        dump_context.info("Refueled. Now have", turtle.getFuelLevel(), "fuel.")
      end
      turtle.drop()
    end
  end

  turtle.select(1)
end

local function check_inventory()
  return turtle.getItemCount(15) > 0
end

local function distance_to_home()
  return math.abs(aid.position.y) + math.abs(aid.position.z) + math.abs(aid.position.x)
end

local function check_fuel()
  return turtle.getFuelLevel() < (distance_to_home() + 10)
end

local main_context = logging.create_context("Main")
if horizontal and not parsed.options.maxdistance then
  main_context.warn(("Turtle is set to move horizontally, but no max horizontal distance was specified. The turtle will go %d blocks forward! If this is okay, enter the direction as normal, otherwise terminate now!"):format(max_distance))
end

local _direction
local function ask_direction()
  print("What direction is the turtle facing (north, south, east, west)? You can use the F3 menu to determine this.")
  repeat
    _direction = read()
  until _direction == "north" or _direction == "south" or _direction == "east" or _direction == "west"
end

if aid.is_module_equipped("scanner") then
  main_context.info("Using Plethora scanner, we should be able to determine our own facing.")
  local blocks = scan()

  if type(blocks) == "table" then
    for _, v in ipairs(blocks) do
      if v.x == 0 and v.z == 0 and v.y == 0 then
        if v.state and v.state.facing then
          _direction = v.state.facing
          main_context.info("Found facing in scanner data, facing is", _direction)
          break
        else
          main_context.warn("No facing found in scanner data, unable to determine facing.")
          ask_direction()
          break
        end
      end
    end
  else
    main_context.warn("No scanner data returned, unable to determine facing.")
    ask_direction()
  end
else
  main_context.warn("No scanner found, unable to determine facing.")
  ask_direction()
end

aid.facing = _direction == "north" and 0 or _direction == "east" and 1 or _direction == "south" and 2 or 3

local function BARK_MULTIPLIER()
  local function BARK_FUNCTION(x)
    return 0.05 * x^2 + 1
  end

  if parsed.flags.bark then
    return 16
  else
    return math.max(
      1.0025,
      math.min(
        BARK_FUNCTION(
          math.abs(math.random(-700, 2500) / 1000)
        ),
        1.5
      )
    )
  end
end

local bark_rng = 0.0001
local bark_multiplier = BARK_MULTIPLIER()
local function draw_data()
  data_win.setBackgroundColor(colors.gray)
  data_win.clear()
  data_win.setCursorPos(1, 1)

  data_win.setTextColor(colors.white)
  data_win.write(string.rep('\x8c', tx))
  data_win.setCursorPos(math.ceil(tx / 2) - 3, 1)
  data_win.write(" DATA ")

  data_win.setCursorPos(1, 2)
  data_win.write(("Turtle: X: % 3d Y: % 3d Z: % 3d"):format(aid.position.x, aid.position.y, aid.position.z))

  data_win.setCursorPos(1, 3)
  data_win.write("State: " .. state.state)

  if state.state == "seeking" then
    data_win.setCursorPos(1, 4)
    if state.state_info.ore then
      data_win.write("Seeking: " .. state.state_info.ore.name)
    else
      data_win.write("Seeking: Unknown")
    end

    data_win.setCursorPos(1, 5)
    if state.state_info.ore then
      data_win.write(("  At: X: % 3d Y: % 3d Z: % 3d"):format(
        state.state_info.ore.x,
        state.state_info.ore.y,
        state.state_info.ore.z
      ))
    else
      data_win.write("  At: Unknown")
    end
  elseif state.state == "digdown" then
    data_win.setCursorPos(1, 4)
    data_win.write("Depth: " .. tostring(aid.position.y))
  elseif state.state == "returning_home" then
    data_win.setCursorPos(1, 4)
    data_win.write("Returning Home.")
  elseif state.state == "returning_from_seek" then
    data_win.setCursorPos(1, 4)
    data_win.write("Returning to last known height.")

    data_win.setCursorPos(1, 5)
    data_win.write("  Target depth: " .. tostring(state.state_info.depth))
  elseif state.state == "errored" then
    data_win.setCursorPos(1, 4)
    data_win.write("Errored. On way home.")
  end

  data_win.setCursorPos(1, 6)
  local old_color = data_win.getTextColor()

  local dist = distance_to_home()
  local level = turtle.getFuelLevel()

  if level < dist + 50 then
    data_win.setTextColor(colors.red)
  elseif level < dist + 100 then
    data_win.setTextColor(colors.orange)
  elseif level < dist + 400 then
    data_win.setTextColor(colors.yellow)
  else
    data_win.setTextColor(colors.green)
  end

  data_win.write(("Fuel: %d / %d"):format(level, turtle.getFuelLimit()))

  data_win.setTextColor(old_color)
end

local BARK_CONTEXT = logging.create_context("BARKBARK")
local function BARK()
  local bark_screen = {"###   ##  ###  #  #","#  # #  # #  # # # ","###  #### ###  ##  ","#  # #  # #  # # # ","###  #  # #  # #  #"}
  local bark_count_rng = math.random(0, 100)
  local bark_count = bark_count_rng < 50 and 1 or bark_count_rng < 80 and 2 or bark_count_rng < 95 and 3 or 8
  local bark_win = window.create(term.current(), 1, 1, term.getSize())

  local label = os.getComputerLabel()

  local function _BARK()
    bark_win.setVisible(false)
    local random_bg_color = math.random(0, 15)
    bark_win.setBackgroundColor(2^random_bg_color)
    local random_fg_color
    repeat
      random_fg_color = math.random(0, 15)
    until random_fg_color ~= random_bg_color
    bark_win.setTextColor(2^random_fg_color)
    bark_win.clear()
    local random_x, random_y = math.random(1, tx - 19), math.random(1, ty - 5)

    for i = 1, #bark_screen do
      bark_win.setCursorPos(random_x, random_y + i - 1)
      bark_win.write(bark_screen[i])
    end

    bark_win.setVisible(true)
  end

  if parsed.flags.muzzle then
    BARK_CONTEXT.log(logging.LOG_LEVEL.DEBUG, "WHINE", "WAAAAAAAAAA")
  else
    os.setComputerLabel(("BARK"):rep(bark_count))
    BARK_CONTEXT.log(logging.LOG_LEVEL.INFO, "BARK", ("BARK"):rep(bark_count))
    for _ = 1, bark_count do
      _BARK()
      sleep(math.random(20, 60) / 60)
    end
    os.setComputerLabel(label)
  end

  log_win.redraw()
  data_win.redraw()
end

local function WANT_BARK()
  if math.random(1, 1005) * bark_rng > 1 then
    bark_rng = 0.0001 * (math.random(0, 1) == 0 and 1 or 0.1)
    bark_multiplier = BARK_MULTIPLIER()
    return true
  else
    bark_rng = bark_rng * bark_multiplier
    return false
  end
end

local function main()
  local tick_context = logging.create_context("Tick")
  aid.set_retrace_distance(math.min(16, max_offset * 4))

  main_context.info("Digging down or forward a block so we don't end up destroying the chest.")
  if horizontal then
    turtle.dig()
    aid.go_forward()
  else
    turtle.digDown()
    aid.go_down()
  end
  main_context.info("Start main loop.")

  turtle.select(1)

  local initial_facing = aid.facing

  while true do
    tick_context.debug("Tick. State is:", state.state)

    if WANT_BARK() then
      BARK()
    end

    draw_data()

    if state.state == "digdown" then
      if horizontal then
        dig_forward(initial_facing)
      else
        dig_down()
      end
    elseif state.state == "seeking" then
      seek(initial_facing)
    elseif state.state == "fuel_low" then
      if return_home() then
        dump_inventory()
        tick_context.fatal("Low on fuel.")
        break
      end
    elseif state.state == "inventory_full" then
      if return_home() then
        dump_inventory()
        state.state = "returning_from_seek"
      end
    elseif state.state == "returning_home" then
      if return_home() then
        dump_inventory()
        break
      end
    elseif state.state == "returning_from_seek" then
      return_seek(initial_facing)
    else
      error("Invalid state: " .. tostring(state.state), 0)
    end

    if check_inventory() then
      state.state = "inventory_full"
    end

    if check_fuel() then
      tick_context.warn("Low on fuel! Returning to the surface.")
      state.state = "fuel_low"
    end
  end

  main_context.info("Reached home. Done.")
end

local ok, err = xpcall(main, debug.traceback)

main_context.debug("Cleaning up...")
aid.clear_save()
data_folder:delete(STATE_FILE)

if not ok then
  sleep()
  main_context.fatal(err)
  logging.dump_log(LOG_FILE)
  main_context.info("Dumped log as", LOG_FILE)

  state.state = "errored"

  pcall(function()
    main_context.warn("Threw error! Attempting to return home!")
    local x = 0
    repeat
      pcall(draw_data)
      x = x + 1
      if x > 300 then
        main_context.fatal("Unable to return home, aborting.")
        break
      end
    until return_home()
  end)
end

term.setCursorPos(1, ty)
print()
