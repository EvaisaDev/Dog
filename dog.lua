local expect = require "cc.expect".expect
package.path = package.path .. ";lib/?.lua;lib/?/init.lua"

local aid = require("turtle_aid")
local file_helper = require("file_helper")
local logging = require("logging")

local LOG_FILE = fs.combine("data", ("dog%d.log"):format(math.random(0, 100000)))
local STATE_FILE = "dog.state"

local max_depth = 512
local geoscanner_range = 8
local max_offset = 8
local max_distance = 64
local scan = nil
local do_fuel = true
local start_x, start_z = 0, 0

local function init_logger()
    logging.set_level(logging.LOG_LEVEL.INFO)
end

local function initialize()
    local setup_context = logging.create_context("Setup")
    setup_context.info("Checking for pickaxe and scanner.")

    local scanner, geoscanner = aid.is_module_equipped("scanner"), aid.is_module_equipped("geoScanner")

    if scanner or geoscanner then
        setup_context.debug("Found scanner.")
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
    ["minecraft:redstone_ore"] = true,
    ["minecraft:deepslate_redstone_ore"] = true,
    ["minecraft:nether_gold_ore"] = true,
    ["minecraft:ancient_debris"] = true
}

local FORBIDDEN_BLOCKS = {
    ["minecraft:chest"] = true,
    ["minecraft:trapped_chest"] = true,
    ["minecraft:ender_chest"] = true
}

local state = {
    state = "digdown",
    state_info = { depth = 0, x = 0, z = 0 }
}

local function save_state()
    file_helper:instanced("data"):serialize(STATE_FILE, state, true)
end

local function load_state()
    local loaded_state = file_helper:instanced("data"):unserialize(STATE_FILE, { state = "digdown", state_info = { depth = 0, x = 0, z = 0 } })
    if loaded_state then
        state = loaded_state
    end
end

local function scan_ores()
    local scanned = scan()
    if type(scanned) == "table" then
        state.state_info.last_scan = scanned
    end
end

local function get_closest_ore()
    local closest_ore
    local closest_distance = math.huge

    for i, block in ipairs(state.state_info.last_scan or {}) do
        local distance = math.abs(block.x - aid.position.x) + math.abs(block.y - aid.position.y) + math.abs(block.z - aid.position.z)
        if ORE_DICT[block.name] and distance < closest_distance then
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

local function dig_down()
    if aid.position.y < -max_depth then
        state.state = "returning_home"
        return
    end

    if check_next_ore() then return end

    turtle.digDown()
    aid.go_down()
    state.state_info.depth = aid.position.y
end

local function return_home()
    while aid.position.y < 0 do
        turtle.digUp()
        aid.go_up()
    end
    return true
end

local function dump_inventory()
    while not aid.find_chest() do
        sleep(5)
    end

    for i = 1, 16 do
        if turtle.getItemCount(i) > 0 then
            turtle.select(i)
            if do_fuel and turtle.refuel() then
                logging.create_context("Fuel").info("Refueled to", turtle.getFuelLevel())
            end
            turtle.drop()
        end
    end

    turtle.select(1)
end

local function move_to_next_column()
    state.state_info.x = state.state_info.x + 1
    if state.state_info.x >= max_distance then
        state.state_info.x = 0
        state.state_info.z = state.state_info.z + 1
        if state.state_info.z >= max_distance then
            logging.create_context("Main").info("Finished mining the 64x64 area.")
            return false
        end
    end
    aid.go_to(state.state_info.x, 0, state.state_info.z)
    return true
end

local function main()
    aid.set_retrace_distance(math.min(16, max_offset * 4))

    if aid.position.y == 0 then
        if state.state_info.x == 0 and state.state_info.z == 0 then
            aid.go_forward()
        end
    end

    turtle.select(1)

    while true do
        if state.state == "digdown" then
            dig_down()
        elseif state.state == "seeking" then
            local ore = state.state_info.ore
            aid.go_to(ore.x, ore.y, ore.z)
            turtle.dig()
            table.remove(state.state_info.last_scan, state.state_info.ore_index)
            if not check_next_ore() then
                state.state = "returning_from_seek"
            end
        elseif state.state == "returning_home" then
            if return_home() then
                dump_inventory()
                if not move_to_next_column() then break end
                state.state = "digdown"
            end
        elseif state.state == "returning_from_seek" then
            aid.go_to(state.state_info.x, 0, state.state_info.z)
            state.state = "digdown"
        end

        if turtle.getItemCount(16) > 0 then
            state.state = "returning_home"
        end

        if turtle.getFuelLevel() < max_depth then
            state.state = "returning_home"
        end
    end

    logging.create_context("Main").info("Mining complete.")
end

init_logger()
initialize()
load_state()
main()
