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

local max_depth = 512
local max_distance = 64
local geoscanner_range = 8
local scan = nil

local parser = simple_argparse.new_parser("dog", "Automated ore-mining program for turtles.")
parser.add_option("depth", "Max depth to dig.", max_depth)
parser.add_option("georange", "Geoscanner range.", geoscanner_range)
parser.add_option("maxdistance", "Max horizontal travel distance.", max_distance)
parser.add_flag("f", "fuel", "Enable automatic refueling.")

local parsed = parser.parse(table.pack(...))

if parsed.options.depth then
  max_depth = tonumber(parsed.options.depth) or error("Max depth must be a number.")
end
if parsed.options.georange then
  geoscanner_range = tonumber(parsed.options.georange) or error("Geoscanner range must be a number.")
end
if parsed.options.maxdistance then
  max_distance = tonumber(parsed.options.maxdistance) or error("Max distance must be a number.")
end

local do_fuel = parsed.flags.fuel

local function scan_ores()
  local scanned = scan()
  if type(scanned) == "table" then
    return scanned
  end
  return {}
end

local function refuel()
  for i = 1, 16 do
    turtle.select(i)
    if turtle.refuel(0) then
      turtle.refuel()
    end
  end
  turtle.select(1)
end

local function check_fuel()
  return turtle.getFuelLevel() < (math.abs(aid.position.y) + 10)
end

local function dump_inventory()
  while not aid.find_chest() do
    sleep(5)
  end
  for i = 1, 16 do
    turtle.select(i)
    turtle.drop()
  end
  turtle.select(1)
end

local function check_inventory()
  return turtle.getItemCount(15) > 0
end

local function return_home()
  aid.navigate_to(0, 0, 0)
  dump_inventory()
  if do_fuel then refuel() end
end

local function mine_ores()
  local ores = scan_ores()
  for _, ore in ipairs(ores) do
    if ORE_DICT[ore.name] then
      aid.navigate_to(ore.x, ore.y, ore.z)
      turtle.dig()
    end
  end
end

local function mine_column(x, z)
  aid.navigate_to(x, 0, z)
  for _ = 1, max_depth do
    if check_inventory() or check_fuel() then
      return_home()
      aid.navigate_to(x, 0, z)
    end
    mine_ores()
    turtle.digDown()
    aid.go_down()
  end
  return_home()
end

local function explore_area()
  for x = 0, max_distance, 4 do
    for z = 0, max_distance, 4 do
      mine_column(x, z)
    end
  end
end

explore_area()
