--[[
  Very basic raytracer, passing results (i.e. hit "pixels") to a callback.

  Usage:
  local rt = require("raytracer").new()
  table.insert(rt.model, {0,0,0,16,16,16})
  --rt.camera.position = {-20,20,0}
  --rt.camera.target = {8,8,8}
  --rt.camera.fov = 100
  rt:render(width, height, function(hitX, hitY, box, normal)
    -- do stuff with the hit information, e.g. set pixel at hitX/hitY to boxes color
  end)

  Shapes must at least have their min/max coordinates given as the first six
  integer indexed entries of the table, as {minX,minY,minZ,maxX,maxY,maxZ}.
  The returned normal is a sequence with the x/y/z components of the normal.

  The camera can be configured as shown in the example above, i.e. it has a
  position, target and field of view (which is in degrees).

  MIT Licensed, Copyright Sangar 2015
]]
local M = {}

-- vector math stuffs

local function vadd(v1, v2)
  return {v1[1]+v2[1], v1[2]+v2[2], v1[3]+v2[3]}
end
local function vsub(v1, v2)
  return {v1[1]-v2[1], v1[2]-v2[2], v1[3]-v2[3]}
end
local function vmul(v1, v2)
  return {v1[1]*v2[1], v1[2]*v2[2], v1[3]*v2[3]}
end
local function vcross(v1, v2)
  return {v1[2]*v2[3]-v1[3]*v2[2], v1[3]*v2[1]-v1[1]*v2[3], v1[1]*v2[2]-v1[2]*v2[1]}
end
local function vmuls(v, s)
  return vmul(v, {s, s, s})
end
local function vdot(v1, v2)
  return v1[1]*v2[1] + v1[2]*v2[2] + v1[3]*v2[3]
end
local function vnorm(v)
  return vdot(v, v)
end
local function vlen(v)
  return math.sqrt(vnorm(v))
end
local function vnormalize(v)
  return vmuls(v, 1/vlen(v))
end

-- collision stuffs

-- http://tog.acm.org/resources/GraphicsGems/gems/RayBox.c
-- adjusted version also returning the surface normal
local function collideRayBox(box, origin, dir)
  local inside = true
  local quadrant = {0,0,0}
  local minB = {box[1],box[2],box[3]}
  local maxB = {box[4],box[5],box[6]}
  local maxT = {0,0,0}
  local candidatePlane = {0,0,0}
  local sign = 0

  -- Find candidate planes; this loop can be avoided if
  -- rays cast all from the eye(assume perpsective view)
  for i=1,3 do
    if origin[i] < minB[i] then
      quadrant[i] = true
      candidatePlane[i] = minB[i]
      inside = false
      sign = -1
    elseif origin[i] > maxB[i] then
      quadrant[i] = true
      candidatePlane[i] = maxB[i]
      inside = false
      sign = 1
    else
      quadrant[i] = false
    end
  end

  -- Ray origin inside bounding box
  if inside then
    return nil
  end

  -- Calculate T distances to candidate planes
  for i=1,3 do
    if quadrant[i] and dir[i] ~= 0 then
      maxT[i] = (candidatePlane[i] - origin[i]) / dir[i]
    else
      maxT[i] = -1
    end
  end

  -- Get largest of the maxT's for final choice of intersection
  local whichPlane = 1
  for i=2,3 do
    if maxT[whichPlane] < maxT[i] then
      whichPlane = i
    end
  end

  -- Check final candidate actually inside box
  if maxT[whichPlane] < 0 then return nil end
  local coord,normal = {0,0,0},{0,0,0}
  for i=1,3 do
    if whichPlane ~= i then
      coord[i] = origin[i] + maxT[whichPlane] * dir[i]
      if coord[i] < minB[i] or coord[i] > maxB[i] then
        return nil
      end
    else
      coord[i] = candidatePlane[i]
      normal[i] = sign
    end
  end

  return coord, normal -- ray hits box
end

local function trace(model, origin, dir)
  local bestBox, bestNormal, bestDist = nil, nil, math.huge
  for _, box in ipairs(model) do
    local hit, normal = collideRayBox(box, origin, dir)
    if hit then
      local dist = vlen(vsub(hit, origin))
      if dist < bestDist then
        bestBox = box
        bestNormal = normal
        bestDist = dist
      end
    end
  end
  return bestBox, bestNormal
end

-- public api

function M.new()
  return setmetatable({model={},camera={position={-1,1,-1},target={0,0,0},fov=90}}, {__index=M})
end

function M:render(w, h, f)
  if #self.model < 1 then return end
  -- overall model bounds, for quick empty space skipping
  local bounds = {self.model[1][1],self.model[1][2],self.model[1][3],self.model[1][4],self.model[1][5],self.model[1][6]}
  for _, shape in ipairs(self.model) do
    bounds[1] = math.min(bounds[1], shape[1])
    bounds[2] = math.min(bounds[2], shape[2])
    bounds[3] = math.min(bounds[3], shape[3])
    bounds[4] = math.max(bounds[4], shape[4])
    bounds[5] = math.max(bounds[5], shape[5])
    bounds[6] = math.max(bounds[6], shape[6])
  end
  bounds = {bounds}
  -- setup framework for ray generation
  local origin = self.camera.position
  local forward = vnormalize(vsub(self.camera.target, origin))
  local plane = vadd(origin, forward)
  local side = vcross(forward, {0,1,0})
  local up = vcross(forward, side)
  local lside = math.tan(self.camera.fov/2/180*math.pi)
  -- generate ray for each pixel, left-to-right, top-to-bottom
  local blanks = 0
  for sy = 1, h do
    local ry = (sy/h - 0.5)*lside
    local py = vadd(plane, vmuls(up, ry))
    for sx = 1, w do
      local rx = (sx/w - 0.5)*lside
      local px = vadd(py, vmuls(side, rx))
      local dir = vnormalize(vsub(px, origin))
      if trace(bounds, origin, dir) then
        local box, normal = trace(self.model, origin, dir)
        if box then
          blanks = 0
          if f(sx, sy, box, normal) == false then
            return
          end
        else
          blanks = blanks + 1
        end
      else
        blanks = blanks + 1
      end
      if blanks > 50 then
        blanks = 0
        os.sleep(0) -- avoid too long without yielding
      end
    end
  end
end

return M
