-- Simple drone program demonstrating the use of waypoints (added in 1.5.9) on
-- the example of a simple sorting system, pulling items from multiple input
-- inventories and placing the items into multiple output inventories, with
-- optional filtering, based on the waypoint labels.

-- The only config option: how far a waypoint may be away from the starting
-- position for it to be used.
local range = 32

local function proxyFor(name, required)
  local address = component and component.list(name)()
  if not address and required then
    error("missing component '" .. name .. "'")
  end
  return address and component.proxy(address) or nil
end

local drone = proxyFor("drone", true)
local nav = proxyFor("navigation", true)
local invctrl = proxyFor("inventory_controller")

-- Colors used to indicate different states of operation.
local colorCharing = 0xFFCC33
local colorSearching = 0x66CC66
local colorDelivering = 0x6699FF

-- Keep track of our own position, relative to our starting position.
local px, py, pz = 0, 0, 0

local function moveTo(x, y, z)
  if type(x) == "table" then
    x, y, z = x[1], x[2], x[3]
  end
  local rx, ry, rz = x - px, y - py, z - pz
  drone.move(rx, ry, rz)
  while drone.getOffset() > 0.5 or drone.getVelocity() > 0.5 do
    computer.pullSignal(0.5)
  end
  px, py, pz = x, y, z
end

local function recharge()
  drone.setLightColor(colorCharing)
  moveTo(0, 0, 0)
  if computer.energy() < computer.maxEnergy() * 0.1 then
    while computer.energy() < computer.maxEnergy() * 0.9 do
      computer.pullSignal(1)
    end
  end
  drone.setLightColor(colorSearching)
end

local function cargoSize()
  local result = 0
  for slot = 1, drone.inventorySize() do
    result = result + drone.count(slot)
  end
  return result
end

local function pullItems()
   -- Only wait up to 5 seconds, avoids dribbling inputs from stalling us.
  local start = computer.uptime()
  repeat until not drone.suck(0) or computer.uptime() - start > 5
end

local function matchCargo(slot, filter)
  if not invctrl or not filter or filter == "" then
    return true
  end
  local stack = invctrl.getStackInInternalSlot(slot)
  return stack and stack.name:match(filter)
end

local function haveCargoFor(filter)
  for slot = 1, drone.inventorySize() do
    if matchCargo(slot, filter) then
      return true
    end
  end
end

local function dropItems(filter)
  for slot = 1, drone.inventorySize() do
    if matchCargo(slot, filter) then
      drone.select(slot)
      drone.drop(0)
    end
  end
end

-- List of known waypoints and their positions relative to the position of the
-- drone when it was started. Waypoints are detected when the program first
-- starts, and when it returns to its home position.
local waypoints

local function updateWaypoints()
  waypoints = nav.findWaypoints(range)
end

local function filterWaypoints(filter)
  local result = {}
  for _, w in ipairs(waypoints) do
    if filter(w) then
      table.insert(result, w)
    end
  end
  return result
end

-- Main program loop; keep returning to recharge, then check all inputs
-- sequentially, distributing what can be picked up from them to all
-- outputs.
while true do
  recharge()
  updateWaypoints()
  -- Get waypoints marking input inventories; defined as those with a high
  -- redstone signal going into them (because there'll usually be more input
  -- than output inventories).
  local inputs = filterWaypoints(function(w) return w.redstone > 0 end)
  local outputs = filterWaypoints(function(w) return w.redstone < 1 end)
  for _, input in ipairs(inputs) do
    moveTo(input.position)
    pullItems()
    drone.setLightColor(colorDelivering)
    for _, output in ipairs(outputs) do
      if cargoSize() == 0 then break end
      if haveCargoFor(output.label) then
        moveTo(output.position)
        dropItems(output.label)
      end
    end
    drone.setLightColor(colorSearching)
  end
end
