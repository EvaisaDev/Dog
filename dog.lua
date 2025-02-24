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
local geoscanner_range = 8
local max_distance = 64
local scan = nil
local do_fuel = false
local mining_x, mining_z = 0, 0

local parser = simple_argparse.new_parser("dog", "Mining turtle program that detects and mines ores efficiently.")
parser.add_option("depth", "Max depth to mine.", max_depth)
parser.add_option("georange", "Geoscanner range.", geoscanner_range)
parser.add_flag("f", "fuel", "Enable auto-refueling.")
parser.add_option("maxdistance", "Maximum horizontal distance from home.", max_distance)

local parsed = parser.parse(table.pack(...))
if parsed.flags.fuel then do_fuel = true end
if parsed.options.depth then max_depth = tonumber(parsed.options.depth) end
if parsed.options.georange then geoscanner_range = tonumber(parsed.options.georange) end
if parsed.options.maxdistance then max_distance = tonumber(parsed.options.maxdistance) end

logging.set_level(logging.LOG_LEVEL.INFO)

local function move_to(x, y, z)
    while aid.position.x ~= x do
        if aid.position.x < x then aid.face(1); aid.go_forward()
        else aid.face(3); aid.go_forward() end
    end
    while aid.position.z ~= z do
        if aid.position.z < z then aid.face(0); aid.go_forward()
        else aid.face(2); aid.go_forward() end
    end
    while aid.position.y < y do aid.gravel_protected_dig_up(); aid.go_up() end
    while aid.position.y > y do turtle.digDown(); aid.go_down() end
end

local function dump_inventory()
    move_to(0, 0, 0)
    while not aid.find_chest() do sleep(5) end
    for i = 1, 16 do
        turtle.select(i)
        if do_fuel then turtle.refuel() end
        turtle.drop()
    end
    turtle.select(1)
end

local function check_fuel()
    return turtle.getFuelLevel() < (math.abs(aid.position.y) + math.abs(aid.position.z) + math.abs(aid.position.x) + 10)
end

local function check_inventory()
    return turtle.getItemCount(15) > 0
end

local function scan_ores()
    local scanned = scan()
    if type(scanned) == "table" then
        state.state_info.last_scan = scanned
    end
end

local function dig_down()
    if aid.position.y < -max_depth then return true end
    if turtle.detectDown() then
        local success, block = turtle.inspectDown()
        if success and block.name == "minecraft:bedrock" then return true end
    end
    scan_ores()
    turtle.digDown()
    aid.go_down()
    return false
end

local function seek_and_mine()
    scan_ores()
    for _, ore in ipairs(state.state_info.last_scan) do
        if ORE_DICT[ore.name] then
            move_to(ore.x, ore.y, ore.z)
            turtle.dig()
            return true
        end
    end
    return false
end

local function mine_column()
    move_to(mining_x, 0, mining_z)
    while not dig_down() do
        if seek_and_mine() then mine_column() end
    end
    move_to(0, 0, 0)
end

local function explore_area()
    for x = 0, max_distance, 2 do
        for z = 0, max_distance, 2 do
            mining_x, mining_z = x, z
            mine_column()
            if check_fuel() or check_inventory() then dump_inventory() end
        end
    end
end

local function main()
    explore_area()
    print("Mining complete. Returning home.")
    move_to(0, 0, 0)
end

local ok, err = pcall(main)
if not ok then
    logging.error("Error: " .. err)
    move_to(0, 0, 0)
end
