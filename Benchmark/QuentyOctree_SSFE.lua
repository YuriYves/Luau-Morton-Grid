--!strict
--!native
--!optimize 2

-- Quenty's Nevermore Octree (Standalone Single-File Edition)
-- Decoupled from Nevermore loader and Draw library.

local EPSILON = 1e-6
local SQRT_3_OVER_2 = math.sqrt(3) / 2
local SUB_REGION_POSITION_OFFSET = {
	{ 0.25, 0.25, -0.25 },
	{ -0.25, 0.25, -0.25 },
	{ 0.25, 0.25, 0.25 },
	{ -0.25, 0.25, 0.25 },
	{ 0.25, -0.25, -0.25 },
	{ -0.25, -0.25, -0.25 },
	{ 0.25, -0.25, 0.25 },
	{ -0.25, -0.25, 0.25 },
}

local OctreeRegionUtils = {}

export type OctreeVector3 = { number }

export type OctreeRegion<T> = {
	subRegions: { OctreeRegion<T> },
	lowerBounds: OctreeVector3,
	upperBounds: OctreeVector3,
	position: OctreeVector3,
	size: OctreeVector3,
	parent: OctreeRegion<T>?,
	parentIndex: number,
	depth: number,
	nodes: { [any]: any },
	node_count: number,
}

export type OctreeRegionHashMap<T> = { [number]: { OctreeRegion<T> } }

function OctreeRegionUtils.create<T>(px: number,py: number,pz: number,sx: number,sy: number,sz: number,parent: OctreeRegion<T>?,parentIndex: number?): OctreeRegion<T>
	local hx, hy, hz = sx / 2, sy / 2, sz / 2
	return {
		subRegions = {},
		nodes = {},
		node_count = 0,
		parent = parent,
		parentIndex = parentIndex or 1,
		depth = parent and (parent.depth + 1) or 1,
		lowerBounds = { px - hx, py - hy, pz - hz },
		upperBounds = { px + hx, py + hy, pz + hz },
		position = { px, py, pz },
		size = { sx, sy, sz },
	}
end

function OctreeRegionUtils.getSearchRadiusSquared(radius: number, diameter: number, epsilon: number): number
	local diagonal = SQRT_3_OVER_2 * diameter
	local searchRadius = radius + diagonal
	return searchRadius * searchRadius + epsilon
end

function OctreeRegionUtils.getNeighborsWithinRadius<T>(region: OctreeRegion<T>,radius: number,px: number,py: number,pz: number,objectsFound: { T },nodeDistances2: { number },maxDepth: number)
	local childDiameter = region.size[1] / 2
	local searchRadiusSquared = OctreeRegionUtils.getSearchRadiusSquared(radius, childDiameter, EPSILON)
	local radiusSquared = radius * radius

	for _, childRegion in region.subRegions do
		local cposition = childRegion.position
		local ox, oy, oz = px - cposition[1], py - cposition[2], pz - cposition[3]
		local dist2 = ox * ox + oy * oy + oz * oz

		if dist2 <= searchRadiusSquared then
			if childRegion.depth == maxDepth then
				for node, _ in childRegion.nodes do
					local npx, npy, npz = node:GetRawPosition()
					local nox, noy, noz = px - npx, py - npy, pz - npz
					local ndist2 = nox * nox + noy * noy + noz * noz
					if ndist2 <= radiusSquared then
						local count = #objectsFound + 1
						objectsFound[count] = node:GetObject()
						nodeDistances2[count] = ndist2
					end
				end
			else
				OctreeRegionUtils.getNeighborsWithinRadius(childRegion,radius,px,py,pz,objectsFound,nodeDistances2,maxDepth)
			end
		end
	end
end

function OctreeRegionUtils.createSubRegion<T>(parentRegion: OctreeRegion<T>, parentIndex: number): OctreeRegion<T>
	local size = parentRegion.size
	local position = parentRegion.position
	local multiplier = SUB_REGION_POSITION_OFFSET[parentIndex]
	local px = position[1] + multiplier[1] * size[1]
	local py = position[2] + multiplier[2] * size[2]
	local pz = position[3] + multiplier[3] * size[3]
	local sx, sy, sz = size[1] / 2, size[2] / 2, size[3] / 2
	return OctreeRegionUtils.create(px, py, pz, sx, sy, sz, parentRegion, parentIndex)
end

function OctreeRegionUtils.getSubRegionIndex<T>(region: OctreeRegion<T>, px: number, py: number, pz: number): number
	local index = px > region.position[1] and 1 or 2
	if py <= region.position[2] then
		index += 4
	end
	if pz >= region.position[3] then
		index += 2
	end
	return index
end

function OctreeRegionUtils.getOrCreateSubRegionAtDepth<T>(region: OctreeRegion<T>,px: number,py: number,pz: number,maxDepth: number): OctreeRegion<T>
	local current = region
	for _ = region.depth, maxDepth do
		local index = OctreeRegionUtils.getSubRegionIndex(current, px, py, pz)
		local _next = current.subRegions[index]
		if not _next then
			_next = OctreeRegionUtils.createSubRegion(current, index)
			current.subRegions[index] = _next
		end
		current = _next
	end
	return current
end

function OctreeRegionUtils.addNode<T>(lowestSubregion: OctreeRegion<T>, node: any)
	local current: OctreeRegion<T>? = lowestSubregion
	while current do
		if not current.nodes[node] then
			current.nodes[node] = node
			current.node_count += 1
		end
		current = current.parent
	end
end

function OctreeRegionUtils.removeNode<T>(lowestSubregion: OctreeRegion<T>, node: any)
	local current: OctreeRegion<T>? = lowestSubregion
	while current do
		current.nodes[node] = nil
		current.node_count -= 1
		local parentIndex = current.parentIndex
		if current.node_count <= 0 and parentIndex and current.parent then
			current.parent.subRegions[parentIndex] = nil
		end
		current = current.parent
	end
end

function OctreeRegionUtils.inRegionBounds<T>(region: OctreeRegion<T>, px: number, py: number, pz: number): boolean
	local lower = region.lowerBounds
	local upper = region.upperBounds
	return px >= lower[1] and px <= upper[1] and py >= lower[2] and py <= upper[2] and pz >= lower[3] and pz <= upper[3]
end

function OctreeRegionUtils.getTopLevelRegionHash(cx: number, cy: number, cz: number): number
	return cx * 73856093 + cy * 19351301 + cz * 83492791
end

function OctreeRegionUtils.getTopLevelRegionCellIndex(maxRegionSize: OctreeVector3,px: number,py: number,pz: number): (number, number, number)
	return math.floor(px / maxRegionSize[1] + 0.5),math.floor(py / maxRegionSize[2] + 0.5),math.floor(pz / maxRegionSize[3] + 0.5)
end

function OctreeRegionUtils.getTopLevelRegionPosition(maxRegionSize: OctreeVector3,cx: number,cy: number,cz: number): (number, number, number)
	return maxRegionSize[1] * cx, maxRegionSize[2] * cy, maxRegionSize[3] * cz
end

function OctreeRegionUtils.getOrCreateRegion<T>(regionHashMap: OctreeRegionHashMap<T>,maxRegionSize: OctreeVector3,px: number,py: number,pz: number): OctreeRegion<T>
	local cx, cy, cz = OctreeRegionUtils.getTopLevelRegionCellIndex(maxRegionSize, px, py, pz)
	local hash = OctreeRegionUtils.getTopLevelRegionHash(cx, cy, cz)

	local regionList = regionHashMap[hash]
	if not regionList then
		regionList = {}
		regionHashMap[hash] = regionList
	end

	local rpx, rpy, rpz = OctreeRegionUtils.getTopLevelRegionPosition(maxRegionSize, cx, cy, cz)
	for _, region in regionList do
		local pos = region.position
		if pos[1] == rpx and pos[2] == rpy and pos[3] == rpz then
			return region
		end
	end

	local region = OctreeRegionUtils.create(rpx, rpy, rpz, maxRegionSize[1], maxRegionSize[2], maxRegionSize[3])
	table.insert(regionList, region)
	return region
end

-- OctreeNode

local OctreeNode = {}
OctreeNode.ClassName = "OctreeNode"
OctreeNode.__index = OctreeNode

export type OctreeNode<T> = typeof(setmetatable({} :: {_octree: any,_object: T,_currentLowestRegion: any?,_position: Vector3?,_px: number?,_py: number?,_pz: number?,},{} :: typeof({ __index = OctreeNode })))

function OctreeNode.new<T>(octree: any, object: T): OctreeNode<T>
	local self = setmetatable({} :: any, OctreeNode)
	self._octree = octree
	self._object = object
	self._currentLowestRegion = nil
	self._position = nil
	return self
end

function OctreeNode.GetObject<T>(self: OctreeNode<T>): T
	return self._object
end

function OctreeNode.GetRawPosition<T>(self: OctreeNode<T>): (number, number, number)
	return self._px or 0, self._py or 0, self._pz or 0
end

function OctreeNode.SetPosition<T>(self: OctreeNode<T>, position: Vector3)
	if self._position == position then return end

	local px, py, pz = position.X, position.Y, position.Z
	self._px, self._py, self._pz = px, py, pz
	self._position = position

	if self._currentLowestRegion and OctreeRegionUtils.inRegionBounds(self._currentLowestRegion, px, py, pz) then
		return
	end

	local newLowestRegion = self._octree:GetOrCreateLowestSubRegion(px, py, pz)
	if self._currentLowestRegion then
		OctreeRegionUtils.removeNode(self._currentLowestRegion, self)
	end
	OctreeRegionUtils.addNode(newLowestRegion, self)
	self._currentLowestRegion = newLowestRegion
end

function OctreeNode.Destroy<T>(self: OctreeNode<T>)
	if self._currentLowestRegion then
		OctreeRegionUtils.removeNode(self._currentLowestRegion, self)
		self._currentLowestRegion = nil
	end
end

-- Octree

local Octree = {}
Octree.ClassName = "Octree"
Octree.__index = Octree

export type Octree<T> = typeof(setmetatable({} :: {_maxRegionSize: { number },_maxDepth: number,_regionHashMap: OctreeRegionHashMap<T>,},{} :: typeof({ __index = Octree })))

function Octree.new<T>(): Octree<T>
	local self = setmetatable({} :: any, Octree)
	self._maxRegionSize = { 512, 512, 512 }
	self._maxDepth = 4
	self._regionHashMap = {}
	return self
end

function Octree.CreateNode<T>(self: Octree<T>, position: Vector3, object: T): OctreeNode<T>
	local node = OctreeNode.new(self, object)
	node:SetPosition(position)
	return node
end

function Octree.GetOrCreateLowestSubRegion<T>(self: Octree<T>, px: number, py: number, pz: number): OctreeRegion<T>
	local region = OctreeRegionUtils.getOrCreateRegion(self._regionHashMap, self._maxRegionSize, px, py, pz)
	return OctreeRegionUtils.getOrCreateSubRegionAtDepth(region, px, py, pz, self._maxDepth)
end

function Octree.RadiusSearch<T>(self: Octree<T>, position: Vector3, radius: number): ({ T }, { number })
	local px, py, pz = position.X, position.Y, position.Z
	local objectsFound: { T } = {}
	local nodeDistances2: { number } = {}

	local diameter = self._maxRegionSize[1]
	local searchRadiusSquared = OctreeRegionUtils.getSearchRadiusSquared(radius, diameter, EPSILON)

	for _, regionList in self._regionHashMap do
		for _, region in regionList do
			local rpos = region.position
			local ox, oy, oz = px - rpos[1], py - rpos[2], pz - rpos[3]
			local dist2 = ox * ox + oy * oy + oz * oz

			if dist2 <= searchRadiusSquared then
				OctreeRegionUtils.getNeighborsWithinRadius(
					region,
					radius,
					px,
					py,
					pz,
					objectsFound,
					nodeDistances2,
					self._maxDepth
				)
			end
		end
	end

	return objectsFound, nodeDistances2
end

return Octree