--[[
  Branch mining program for OpenComputers robots.

  This program is designed to dig out branches, in a fashion that allows
  players to easily navigate the dug out tunnels. The primary concern was
  not the performance of the mining, only a good detection rate, and nice
  tunnels. Suggested upgrades for this are the geolyzer and inventory
  controller upgrade, and depending on your world gen (ravines?) a hover
  upgrade might be necessary. The rest is up to you (chunkloading, more
  inventory, battery upgrades).

  By Sangar, 2015

  This program is licensed under the MIT license.
  http://opensource.org/licenses/mit-license.php
]]

local component = require("component")
local computer = require("computer")
local robot = require("robot")
local shell = require("shell")
local sides = require("sides")

--[[ Config ]]-----------------------------------------------------------------

-- Every how many blocks to dig a side shaft. The default makes for a
-- two wide wall between tunnels, making sure we don't miss anything.
local shaftInterval = 3

-- Max recursion level for mining ore veins. We abort early because we
-- assume we'll encounter the same vein again from an adjacent tunnel.
local maxVeinRecursion = 8

-- Every how many blocks to place a torch when placing torches.
local torchInverval = 11

--[[ State ]]------------------------------------------------------------------

-- Slots we don't want to drop. Filled in during initialization, based
-- on items already in the inventory. Useful for stuff like /dev/null.
local keepSlot = {}

-- Slots that we keep torches in, updated when stocking up on torches.
local torchSlots = {}

--[[ Utility ]]----------------------------------------------------------------

-- Check if a block with the specified info should be mined.
local function shouldMine(info)
  return info and info.name and (info.name:match(".*ore.*") or info.name:match(".*Ore.*"))
end

-- Number of stacks of torches to keep; default is 1 per inventory upgrade.
local function torchStacks()
  return math.max(1, math.ceil(robot.inventorySize() / 16))
end

-- Look for the first empty slot in our inventory.
local function findEmptySlot()
  for slot = 1, robot.inventorySize() do
    if robot.count(slot) == 0 then
      return slot
    end
  end
end

-- Find the first torch slot that still contains torches.
local function findTorchSlot()
  for _, slot in ipairs(torchSlots) do
    if robot.count(slot) > 0 then
      return slot
    end
  end
end

--[[ Torching ]]---------------------------------------------------------------

-- We can automatically place torches while moving; this keeps track of the
-- state, so we can place every n blocks.
local placingTorches, torchState = false, 0

-- Start automatically placing torches in the configured interval.
local function beginPlacingTorches()
  placingTorches = true
  torchState = 0
end

-- Stop automatically placing torches.
local function stopPlacingTorches()
  placingTorches = false
end

-- Place a single torch above the robot, if there are any torches left.
local function placeTorch()
  local slot = findTorchSlot()
  if slot then
    robot.select(slot)
    robot.placeUp()
    robot.select(1)
  end
  return true
end

-- Called whenever we're moving, used for automatic torch placement.
local function onMove()
  if placingTorches then
    if torchState < 1 then
      torchState = torchInverval
      placeTorch()
    else
      torchState = torchState - 1
    end
  end
end

--[[ Navigation ]]-------------------------------------------------------------

-- Quick look-up table for inverting directions.
local oppositeSides = {
  [sides.north] = sides.south,
  [sides.south] = sides.north,
  [sides.east] = sides.west,
  [sides.west] = sides.east,
  [sides.up] = sides.down,
  [sides.down] = sides.up
}

-- For pushTurn() readability.
local left = false
local right = not left

-- Keeps track of our moves to allow "undoing" them for returning to the
-- docking station. Format is a list of moves, represented as tables
-- containing the type of move and distance to move, e.g.
--   {move=sides.back, count=10},
--   {turn=true, count=2}
-- means we first moved back 10 blocks, then turned around.
local moves = {}

-- Undo a *single* move, i.e. reduce the count of the latest move type.
local function undoMove(move)
  if move.move then
    local side = oppositeSides[move.move]
    local result = component.robot.move(side)
    if not result then
      -- Obstructed, try to clear the way.
      if side == sides.back then
        -- Moving backwards, turn around.
        component.robot.turn(left)
        component.robot.turn(left)
        repeat
          robot.swing()
        until robot.forward()
        component.robot.turn(left)
        component.robot.turn(left)
      else
        repeat
          component.robot.swing(side)
        until component.robot.move(side)
      end
    end
  else
    local direction = not move.turn
    component.robot.turn(direction)
  end
  move.count = move.count - 1
  onMove()
end

-- Make a turn in the specified direction.
local function pushTurn(direction)
  component.robot.turn(direction)
  if moves[#moves] and moves[#moves].turn == direction then
    moves[#moves].count = moves[#moves].count + 1
  else
    moves[#moves + 1] = {turn=direction, count=1}
  end
  return true -- Allows for `return pushMove() and pushTurn() and pushMove()`.
end

-- Try to make a move towards the specified side.
local function pushMove(side)
  local result, reason = component.robot.move(side)
  if result then
    if moves[#moves] and moves[#moves].move == side then
      moves[#moves].count = moves[#moves].count + 1
    else
      moves[#moves + 1] = {move=side, count=1}
    end
    onMove()
  end
  return result, reason
end

-- Undo the most recent move *type*. I.e. will undo all moves of the most
-- recent type (say we moved forwards twice, this will go back twice).
local function popMove()
  -- Deep copy the move for returning it.
  local move = moves[#moves] and {move=moves[#moves].move,
                                  turn=moves[#moves].turn,
                                  count=moves[#moves].count}
  while moves[#moves] and moves[#moves].count > 0 do
    undoMove(moves[#moves])
  end
  moves[#moves] = nil
  return move
end

-- Get the current top and count values, to be used as a position snapshot
-- that can be restored later on by calling setTop().
local function getTop()
  if moves[#moves] then
    return #moves, moves[#moves].count
  else
    return 0, 0
  end
end

-- Undo some moves based on a stored top and count received from getTop().
local function setTop(top, count, unsafe)
  assert(top >= 0 and top <= #moves)
  assert(count >= 0 and top < #moves or count <= moves[#moves].count)
  while #moves > top do
    if unsafe then
      moves[#moves] = nil
    else
      popMove()
    end
  end
  local move = moves[#moves]
  if move then
    while move.count > count do
      if unsafe then
        move.count = move.count - 1
      else
        undoMove(move)
      end
    end
    if move.count < 1 then
      moves[#moves] = nil
    end
  end
end

-- Repeat the specified set of moves.
local function pushMoves(moves)
  for _, move in ipairs(moves) do
    if move.move then
      for _ = 1, move.count do
        repeat until pushMove(move.move)
      end
    else
      for _ = 1, move.count do
        pushTurn(move.turn)
      end
    end
  end
end

-- Undo *all* moves made since program start, return the list of moves.
local function popMoves()
  local result = {}
  local move = popMove()
  while move do
    table.insert(result, 1, move)
    move = popMove()
  end
  return result
end

--[[ Maintenance ]]------------------------------------------------------------

-- Go back to the docking bay for general maintenance if necessary.
local function gotoMaintenance(force)
  if not force and
     robot.durability() and
     computer.energy() / computer.maxEnergy() > 0.1 and
     findTorchSlot()
  then
    return -- No need yet.
  end

  io.write("Going back for maintenance!\n")
  local moves = popMoves()

  -- Drop inventory.
  io.write("Dropping what I found.\n")
  for slot = 1, robot.inventorySize() do
    while not keepSlot[slot] and robot.count(slot) > 0 do
      robot.select(slot)
      robot.dropDown()
    end
  end
  robot.select(1)

  -- Make sure we have a working tool.
  if not robot.durability() then
    io.write("Tool is broken, getting a new one.\n")
    if component.isAvailable("inventory_controller") then
      robot.select(findEmptySlot()) -- Select an empty slot for working.
      repeat
        component.inventory_controller.equip() -- Drop whatever's in the tool slot.
        while robot.count() > 0 do
          robot.dropDown()
        end
        robot.suckUp(1) -- Pull something from above and equip it.
        component.inventory_controller.equip()
      until robot.durability()
      robot.select(1)
    else
      -- Can't re-equip autonomously, wait for player to give us a tool.
      io.write("HALP! I need a new tool.\n")
      repeat
        event.pull(10, "inventory_changed")
      until robot.durability()
    end
  end

  -- Stock up on torches. First, clean up our list and look for empty slots.
  io.write("Getting my fill of torches.\n")
  local oldTorchSlots = torchSlots
  torchSlots = {}
  for _, slot in ipairs(oldTorchSlots) do
    keepSlot[slot] = nil
    if robot.count(slot) > 0 then
      torchSlots[#torchSlots + 1] = slot
    end
  end
  while #torchSlots < torchStacks() do
    local slot = findEmptySlot()
    if not slot then
      break -- This should never happen...
    end
    torchSlots[#torchSlots + 1] = slot
  end
  -- Then fill the slots with torches.
  robot.turnLeft()
  for _, slot in ipairs(torchSlots) do
    keepSlot[slot] = true
    if robot.space(slot) > 0 then
      robot.select(slot)
      repeat
        local before = robot.space()
        robot.suck(robot.space())
        if robot.space() == before then
          os.sleep(5) -- Don't busy idle.
        end
      until robot.space() < 1
      robot.select(1)
    end
  end
  robot.turnRight()

  -- Recharge our batteries. Do this last so we can charge some during the
  -- other operations.
  io.write("Waiting until my batteries are full.\n")
  while computer.energy() / computer.maxEnergy() < 0.95 do
    os.sleep(10)
  end

  if moves and #moves > 0 then
    io.write("Returning to where I left off.\n")
    pushMoves(moves)
  end
end

--[[ Mining ]]-----------------------------------------------------------------

-- Dig out a block on the specified side, without tool if possible.
local function dig(side)
  repeat
    local something, what = component.robot.detect(side)
    if not something or what == "replaceable" or what == "liquid" then
      return true -- We can just move into whatever is there.
    end

    local emptySlot = findEmptySlot()
    gotoMaintenance(not emptySlot) -- Go back to base if necessary.

    local brokeSomething

    local info = component.isAvailable("geolyzer") and
                 component.geolyzer.analyze(side)
    if info and info.name == "OpenComputers:robot" then
      brokeSomething = true -- Wait for other robot to go away.
      os.sleep(0.5)
    elseif component.isAvailable("inventory_controller") then
      robot.select(emptySlot or 1)
      component.inventory_controller.equip() -- Save some tool durability.
      brokeSomething = component.robot.swing(side)
      component.inventory_controller.equip()
    end
    if not brokeSomething then
      robot.select(1)
      brokeSomething = component.robot.swing(side)
    end
  until not brokeSomething
end

-- Move towards the specified direction, digging out blocks as necessary.
local function move(side)
  local result, reason, retry
  repeat
    retry = false
    if side ~= sides.back then
      retry = dig(side)
    end
    result, reason = pushMove(side)
  until result or not retry
  return result, reason
end

-- Turn to face the specified, relative orientation.
local function turnTowards(side)
  if side == sides.left then
    pushTurn(left)
  elseif side == sides.right then
    pushTurn(right)
  elseif side == sides.back then
    pushTurn(left)
    pushTurn(left)
  end
end

--[[ Moving ]]-----------------------------------------------------------------

-- Dig out any interesting ores adjacent to the current position, recursively.
-- POST: back to the starting position and facing.
local function digVein(maxDepth)
  if maxDepth < 1 then return end
  for _, side in ipairs(sides) do
    side = sides[side]
    if shouldMine(component.geolyzer.analyze(side)) then
      local top, count = getTop()
      turnTowards(side)
      if side == sides.up or side == sides.down then
        move(side)
      else
        move(sides.forward)
      end
      digVein(maxDepth - 1)
      setTop(top, count)
    end
  end
end

-- Dig out any interesting ores adjacent to the current position, recursively.
-- Also checks blocks adjacent to above block in exhaustive mode.
-- POST: back at the starting position and facing.
local function digVeins(exhaustive)
  if component.isAvailable("geolyzer") then
    digVein(maxVeinRecursion)
    if exhaustive and move(sides.up) then
      digVein(maxVeinRecursion)
      popMove()
    end
  end
end

-- Dig a 1x2 tunnel of the specified length. Checks for ores.
-- Also checks upper row for ores in exhaustive mode.
-- PRE: bottom front of tunnel to dig.
-- POST: at the end of the tunnel.
local function dig1x2(length, exhaustive)
  while length > 0 and move(sides.forward) do
    dig(sides.up)
    digVeins(exhaustive)
    length = length - 1
  end
  return length < 1
end

-- Dig a 1x3 tunnel of the specified length.
-- PRE: center front of tunnel to dig.
-- POST: at the end of the tunnel.
local function dig1x3(length)
  while length > 0 and move(sides.forward) do
    dig(sides.up)
    dig(sides.down)
    length = length - 1
  end
  return length < 1
end

-- Dig out a main shaft.
-- PRE: bottom front of main shaft.
-- POST: bottom front of main shaft.
local function digMainShaft(length)
  io.write("Digging main shaft.\n")

  if not move(sides.up) then
    return false
  end

  local top, count = getTop()

  if not (dig1x3(length) and
          pushTurn(left) and
          dig1x3(1) and
          pushTurn(left) and
          dig1x3(length - 1) and
          placeTorch() and
          pushTurn(left) and
          dig1x3(1))
  then
    return false
  end

   -- Create snapshot for shortcut below.
  local midTop, midCount = getTop()

  if not (dig1x3(1) and
          pushTurn(left) and
          dig1x3(length - 1) and
          placeTorch())
  then
    return false
  end

  -- Shortcut: manually move back to start, do an unsafe setTop.
  -- Otherwise we'd have to retrace all three rows.
  setTop(midTop, midCount)
  if pushTurn(left) and move(sides.back) then
    setTop(top, count, true)
    return true
  end

  return false
end

-- Dig all shafts in one cardinal direction (the one we're facing).
-- PRE: bottom front of a main shaft.
-- POST: bottom front of a main shaft.
local function digShafts(length)
  local top, count = getTop() -- Remember start of main shaft.
  local ok = digMainShaft(length)
  setTop(top, count)
  if not ok then
    io.write("Failed digging main shaft, skipping.\n")
    return
  end

  io.write("Beginning work on side shafts.\n")
  for i = shaftInterval, length, shaftInterval do
    io.write("Working on shafts #" .. (i / shaftInterval) .. ".\n")

    if not dig1x2(shaftInterval) then -- Move to height of shaft.
      break
    end
    local sideTop, sideCount = getTop() -- Remember position.

    pushTurn(left) -- Dig left shaft.
    dig1x2(i + 2, true)
    beginPlacingTorches()
    setTop(sideTop, sideCount)
    stopPlacingTorches()

    pushTurn(right) -- Dig right shaft.
    dig1x2(i + 2, true)
    beginPlacingTorches()
    setTop(sideTop, sideCount)
    stopPlacingTorches()
  end

  setTop(top, count) -- Go back to start of main shaft.
end

-- Moves to the next main shaft, clockwise.
-- PRE: bottom front of nth main shaft.
-- POST: bottom front of (n+1)th main shaft.
local function gotoNextMainShaft()
  return pushTurn(right) and
         dig1x2(2) and
         pushTurn(right) and
         dig1x2(2) and
         pushTurn(left)
end

--[[ Main ]]-------------------------------------------------------------------

local function main(radius, levels, full)
  -- We dig tunnels every three blocks, to have a spacing of
  -- two blocks between them (so we don't really have to follow
  -- veins but can just break the blocks in the wall that are
  -- interesting to us). So adjust the length accordingly.
  radius = radius - radius % shaftInterval

  -- Flag slots that contain something as do-not-drop and check
  -- that we have some free inventory space at all.
  local freeSlots = robot.inventorySize()
  for slot = 1, robot.inventorySize() do
    if robot.count(slot) > 0 then
      keepSlot[slot] = true
      freeSlots = freeSlots - 1
    end
  end
  if freeSlots < 2 + torchStacks() then -- Place for mined blocks + torches.
    io.write("Sorry, but I need more empty inventory space to work.\n")
    os.exit()
  end
  gotoMaintenance(true)

  if not move(sides.forward) then
    io.write("Exit from docking bay obstructed, aborting.\n")
    os.exit()
  end

  for level = 1, levels do
    if level > 1 then
      for _ = 1, 4 do
        if not move(sides.down) then
          io.write("Access to level " .. level .. " obstructed, aborting.\n")
          popMoves()
          gotoMaintenance(true)
          os.exit()
        end
      end
    end

    local top, count = getTop()

    for shaft = 1, full and 4 or 1 do
      if shaft > 1 and not gotoNextMainShaft() then
        break
      end
      digShafts(radius)
    end

    setTop(top, count)
  end

  io.write("All done! Going home to clean up.\n")
  popMoves()
  gotoMaintenance(true)
end

local args, options = shell.parse(...)
if options.h or options.help then
  io.write("Usage: miner [radius [levels [full]]]\n")
  io.write("  radius: the radius in blocks of the area to\n")
  io.write("          mine. Adjusted to be a multiple of\n")
  io.write("          three. Default: 9.\n")
  io.write("  levels: the number of vertical levels to mine.\n")
  io.write("          Default: 1.\n")
  io.write("  full:   whether to mine a full level (all four\n")
  io.write("          cardinal directions). Default: false.\n")
  os.exit()
end

local radius = tonumber(args[1]) or 9
local levels = tonumber(args[2]) or 1
local full = args[3] and args[3] == "true" or args[3] == "yes"

io.write("Will mine " .. levels .. " levels in a radius of " .. radius .. ".\n")
if full then
  io.write("Will mine all four cardinal directions.\n")
end
if not component.isAvailable("geolyzer") then
  io.write("Installing a geolyzer upgrade is strongly recommended.\n")
end
if not component.isAvailable("inventory_controller") then
  io.write("Installing an inventory controller upgrade is strongly recommended.\n")
end

io.write("I'll drop mined out stuff below me.\n")
io.write("I'll be looking for torches on my left.\n")
if component.isAvailable("inventory_controller") then
  io.write("I'll try to get new tools from above me.\n")
else
  io.write("You'll need to manually provide me with new tools if they break.\n")
end

io.write("Shall we begin? [Y/n] ")
local result = io.read()
if result and result == "" or result:lower() == "y" then
  main(radius, levels, full)
end
