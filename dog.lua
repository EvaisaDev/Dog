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
local do_fuel = true
local horizontal = false
local version = "V0.14.3"
local latest_changes = [[Added a few more blocks as ores. If you wish to add some that are missing, PRs are open!]]

local parser = simple_argparse.new_parser("dog", "Dog is a program run on mining turtles which is used to find ores and mine them. Unlike quarry programs, this program digs in a straight line down and uses either plethora's block scanner or advanced peripheral's geoscanner to detect where ores are along its path and mine to them.")
parser.add_option("depth", "The maximum depth to dig to.", max_depth)
parser.add_option("loglevel", "The log level to use.", "INFO")
parser.add_option("georange", "The range to use for the geoscanner, if using Advanced Peripherals.", geoscanner_range)
parser.add_flag("h", "help", "Show this help message and exit.")
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

if parsed.arguments[1] then
  max_offset = tonumber(parsed.arguments[1])
  if not max_offset then
    error("Max offset must be a number.", 0)
  end
end

logging.set_level(log_level)

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
        or block[initial_axis] < -max_depth or block[initial_axis] > max_depth
    else
      out_of_range = block.y < -max_depth
        or block.x < -max_offset or block.x > max_offset
        or block.z < -max_offset or block.z > max_offset
    end
    if not out_of_range and distance < closest_distance then
      closest_ore = i
      closest_distance = distance
    end
  end
  return closest_ore
end

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
  if math.abs(aid.position[initial_facing == 0 or initial_facing == 2 and "z" or "x"]) >= max_depth then
    state.state = "returning_home"
    return
  end
  check_next_ore()
  aid.face(initial_facing)
  turtle.dig()
  aid.go_forward()
  state.state_info.depth = aid.position[initial_facing == 0 or initial_facing == 2 and "z" or "x"]
end

local function dig_down()
  if aid.position.y < -max_depth then
    state.state = "returning_home"
    return
  end
  local success, block_data = turtle.inspectDown()
  if success and block_data.name == "minecraft:bedrock" then
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

local function inspect_for_bedrock(direction)
  if direction == "forward" then
    local success, block = turtle.inspect()
    if success and block.name == "minecraft:bedrock" then
      state.state = "returning_home"
      return true
    end
  elseif direction == "up" then
    local success, block = turtle.inspectUp()
    if success and block.name == "minecraft:bedrock" then
      state.state = "returning_home"
      return true
    end
  elseif direction == "down" then
    local success, block = turtle.inspectDown()
    if success and block.name == "minecraft:bedrock" then
      state.state = "returning_home"
      return true
    end
  end
  return false
end

local function seek(initial_facing)
  local ore = state.state_info.ore
  local x, y, z = ore.x, ore.y, ore.z
  local direction, distance = aid.get_direction_to(vector.new(x, y, z), true)
  if distance == 1 then
    if direction == "up" then
      turtle.digUp()
    elseif direction == "down" then
      turtle.digDown()
    else
      aid.face(direction)
      turtle.dig()
    end
    table.remove(state.state_info.last_scan, state.state_info.ore_index)
    if not check_next_ore() then
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
      aid.retrace(true)
      return false, true
    end
    aid.gravel_protected_dig_up()
    aid.go_up()
  elseif direction == "down" then
    if inspect_for_bedrock("down") then
      aid.retrace(true)
      return false, true
    end
    turtle.digDown()
    aid.go_down()
  else
    aid.face(direction)
    if inspect_for_bedrock("forward") then
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
  end
  return false
end

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
  end
  return false
end

local function dump_inventory()
  while not aid.find_chest() do
    sleep(5)
  end
  for i = 1, 16 do
    if turtle.getItemCount(i) > 0 then
      turtle.select(i)
      if do_fuel and turtle.refuel() then
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

local _direction
local function ask_direction()
  print("What direction is the turtle facing (north, south, east, west)? You can use the F3 menu to determine this.")
  repeat
    _direction = read()
  until _direction == "north" or _direction == "south" or _direction == "east" or _direction == "west"
end

if aid.is_module_equipped("scanner") then
  local blocks = nil
  blocks = scan and scan() or nil
  if type(blocks) == "table" then
    for _, v in ipairs(blocks) do
      if v.x == 0 and v.z == 0 and v.y == 0 then
        if v.state and v.state.facing then
          _direction = v.state.facing
          break
        else
          ask_direction()
          break
        end
      end
    end
  else
    ask_direction()
  end
else
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
    return math.max(1.0025, math.min(BARK_FUNCTION(math.abs(math.random(-700, 2500) / 1000)), 1.5))
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
      data_win.write(("  At: X: % 3d Y: % 3d Z: % 3d"):format(state.state_info.ore.x, state.state_info.ore.y, state.state_info.ore.z))
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
  else
    os.setComputerLabel(("BARK"):rep(bark_count))
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
  aid.set_retrace_distance(math.min(16, max_offset * 4))
  if horizontal then
    turtle.dig()
    aid.go_forward()
  else
    turtle.digDown()
    aid.go_down()
  end
  turtle.select(1)
  local initial_facing = aid.facing
  while true do
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
      state.state = "fuel_low"
    end
  end
end

local ok, err = xpcall(main, debug.traceback)

aid.clear_save()
data_folder:delete(STATE_FILE)

if not ok then
  sleep()
  main_win.fatal(err)
  state.state = "errored"
  pcall(function()
    local x = 0
    repeat
      pcall(draw_data)
      x = x + 1
      if x > 300 then
        break
      end
    until return_home()
  end)
else
  --logging.dump_log(nil)
end

--[[
if not ok then
  sleep() -- in case this was an infinite loop related error.
  main_context.fatal(err)
  logging.dump_log(LOG_FILE)
  main_context.info("Dumped log as", LOG_FILE)

  state.state = "errored"

  -- Attempt to return home to protect the turtle from becoming lost underground.
  pcall(function()
    main_context.warn("Threw error! Attempting to return home!")

    local x = 0
    repeat
      pcall(draw_data)
      x = x + 1
      if x > 300 then -- 300 chosen arbitrarily. This may or may not be a good value.
        main_context.fatal("Unable to return home, aborting.")
        break
      end
    until return_home()
  end)
end
]]

print("Press Enter to close...")
read()
term.setCursorPos(1, ty)
print()
