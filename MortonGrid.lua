--!strict
--!native
--!optimize 2

--	||	Yuri Yves 			||	--

----------------------------------
--	::	Types				::	--
----------------------------------

type IndexArray				= { number }
export type ObjArray		= { any }
type VectorArray			= { vector }
type BoolArray				= { boolean }
type SlotHash				= { [any]: number }

----------------------------------
--	::	Constants			::	--
----------------------------------

const CHUNK_SIZE		= 16
const SIZE, OFFSET		= 1024, 512

const LAST_CELL			= SIZE - 1

const GRID_RADIUS_SCALE	= 1.0000009536743164

const INDEX_SPACE		= 8388608
const INDEX_MASK		= INDEX_SPACE - 1

const DEFAULT_CELL_SIZE,
	EXACT_CELL_LIMIT	= 128, 16777215

const ZERO_VECTOR		= vector.zero
const OFFSET_VECTOR, LAST_VECTOR,
	FAR_AWAY			= vector.create(OFFSET, OFFSET, OFFSET), vector.create(LAST_CELL, LAST_CELL, LAST_CELL), vector.create(1e18, 1e18, 1e18)

----------------------------------
--	::	Morton				::	--
----------------------------------

const Morton					= {}

----------------------------------
--	::	Private Tables		::	--
----------------------------------

local OBJECTS			: ObjArray,	
	POSITIONS			: VectorArray	= {}, {}
local ALTER_OBJECTS		: ObjArray,
	ALTER_POSITIONS		: VectorArray	= {}, {}

const CHUNK_CLEAN		: BoolArray,
	CHUNK_MIN			: VectorArray,
	CHUNK_MAX			: VectorArray	= {}, {}, {}

const MORTON_LUT		: IndexArray	= table.create(SIZE, 0)

const CODES				: IndexArray,
	PENDING_CODE		: IndexArray	= {}, {}

const STATIC_SLOT				: SlotHash 		= {}

const DYNAMIC_SLOT		: SlotHash,
	DYNAMIC_PREV		: IndexArray,
	DYNAMIC_NEXT		: IndexArray,
	DYNAMIC_OBJECT		: ObjArray,
	DYNAMIC_POSITION	: VectorArray,
	DYNAMIC_CELL		: VectorArray 	= {}, {}, {}, {}, {}, {}

const GRID				: {[vector]: number } = {}

----------------------------------
--	::	Private Property	::	--
----------------------------------

local DynamicCount,
	StaticCount,
	PendingCount,
	BufferCount,
	StaticTombs					= 0, 0, 0, 0, 0

local Unsorted						= false

local RebuildThreshold, QueryDebt	= 256, 0

local GridCellSize, GridInverse		= DEFAULT_CELL_SIZE, 1 / DEFAULT_CELL_SIZE
local GridVectorScale, GridPadding 	= true, 1e-20

----------------------------------
--	::	Precomputation		::	--
----------------------------------

for Index: number = 1, SIZE - 1 do MORTON_LUT[Index + 1]  = MORTON_LUT[Index // 2 + 1] * 8 + Index % 2 end

----------------------------------
--	::	Local Functions		::	--
----------------------------------

const function assert<T>(value: T, errorMessage: string?): T if not value then error(errorMessage, 1) end return value end

const function CellOf(Position: vector): vector
	if GridVectorScale then return vector.floor(Position * GridInverse) end
	return vector.create(
		math.floor(Position.x * GridInverse),
		math.floor(Position.y * GridInverse),
		math.floor(Position.z * GridInverse)
	)
end

const function UnlinkDynamic(Index: number): ()
	const Previous: number 	= DYNAMIC_PREV[Index]
	const Next: number 		= DYNAMIC_NEXT[Index]
	if Previous == 0 then
		GRID[DYNAMIC_CELL[Index]] = if Next == 0 then nil else Next
	else
		DYNAMIC_NEXT[Previous] 	= Next
	end
	if Next ~= 0 then DYNAMIC_PREV[Next] = Previous end
end

const function LinkDynamic(Index: number, Cell: vector): ()
	const Head: number 		= GRID[Cell] or 0
	DYNAMIC_CELL[Index] 	= Cell
	DYNAMIC_PREV[Index] 	= 0
	DYNAMIC_NEXT[Index] 	= Head
	if Head ~= 0 then DYNAMIC_PREV[Head] = Index end
	GRID[Cell] 	= Index
end

const function MoveDynamic(Index: number, Position: vector): ()
	const Cell: vector 		= CellOf(Position)
	DYNAMIC_POSITION[Index]	= Position
	if Cell ~= DYNAMIC_CELL[Index] then
		UnlinkDynamic(Index)
		LinkDynamic(Index, Cell)
	end
end

const function RemoveDynamic(Index: number): ()
	UnlinkDynamic(Index)
	
	DYNAMIC_SLOT[DYNAMIC_OBJECT[Index]] = nil
	
	if Index ~= DynamicCount then
		const Object	: any 	 = DYNAMIC_OBJECT[DynamicCount]
		const Cell		: vector = DYNAMIC_CELL[DynamicCount]
		const Previous	: number = DYNAMIC_PREV[DynamicCount]
		const Next		: number = DYNAMIC_NEXT[DynamicCount]
		
		DYNAMIC_OBJECT[Index] 	= Object
		DYNAMIC_POSITION[Index] = DYNAMIC_POSITION[DynamicCount]
		DYNAMIC_CELL[Index] 	= Cell
		DYNAMIC_PREV[Index] 	= Previous
		DYNAMIC_NEXT[Index] 	= Next
		DYNAMIC_SLOT[Object]	= Index
		
		if Previous == 0 then
			GRID[Cell] 	= Index
		else
			DYNAMIC_NEXT[Previous] 	= Index
		end
		
		if Next ~= 0 then
			DYNAMIC_PREV[Next] 	= Index
		end
	end
	
	DYNAMIC_OBJECT[DynamicCount] 	= nil
	DYNAMIC_POSITION[DynamicCount] 	= nil
	DYNAMIC_CELL[DynamicCount]	= nil
	DYNAMIC_PREV[DynamicCount] 	= nil
	DYNAMIC_NEXT[DynamicCount] 	= nil
	DynamicCount -= 1
end

const function BinarySearch(Code: number, Low: number): number
	if Low > StaticCount or CODES[Low] >= Code then return Low end
	local High: number 	= StaticCount
	while Low <= High do
		const Mid: number 	= (Low + High) // 2
		if CODES[Mid] < Code then
			Low = Mid + 1
		else
			High = Mid - 1
		end
	end
	return Low
end

const function Rebuild(): ()
	QueryDebt = 0
	
	const HasPending: boolean	= PendingCount > 0
	const HasTombs: boolean		= StaticTombs > 0
	
	const NeedsSort: boolean 	= Unsorted or HasPending
	
	if HasTombs or HasPending then
		local Live: number 	= 0
		if HasTombs then
			for Index: number = 1, StaticCount do
				if OBJECTS[Index] ~= nil then
					Live 	+= 1
					if Live ~= Index then
						OBJECTS[Live] 	= OBJECTS[Index]
						POSITIONS[Live] = POSITIONS[Index]
						CODES[Live] 	= CODES[Index]
					end
				end
			end
			for Index: number = Live + 1, StaticCount do
				OBJECTS[Index] 		= nil
				POSITIONS[Index] 	= nil
				CODES[Index] 		= nil
			end
		else
			Live = StaticCount
		end
		
		if HasPending then
			table.move(ALTER_OBJECTS, 1, PendingCount, Live + 1, OBJECTS)
			table.move(ALTER_POSITIONS, 1, PendingCount, Live + 1, POSITIONS)
			table.move(PENDING_CODE, 1, PendingCount, Live + 1, CODES)
			
			Live += PendingCount
			table.clear(PENDING_CODE)
			
			PendingCount = 0
		end
		
		StaticTombs, StaticCount = 0, Live
	end
	
	if StaticCount == 0 then
		table.clear(ALTER_OBJECTS)
		table.clear(ALTER_POSITIONS)
		BufferCount, RebuildThreshold, Unsorted = 0, 256, false
		return
	end
	
	if NeedsSort then
		for Index: number = 1, StaticCount do CODES[Index] = CODES[Index] * INDEX_SPACE + Index end
		table.sort(CODES)
		
		const TempObj	: ObjArray 		= ALTER_OBJECTS
		const TempPos	: VectorArray 	= ALTER_POSITIONS
		
		if StaticCount < BufferCount then
			for Index: number = StaticCount + 1, BufferCount do
				TempObj[Index]	= nil
				TempPos[Index]	= nil
			end
		end
		
		BufferCount = StaticCount
		
		for Index: number = 1, StaticCount do
			const Key: number 		= CODES[Index]
			const OrigIdx: number 	= bit32.band(Key, INDEX_MASK)
			const Object: any 		= OBJECTS[OrigIdx]
			TempObj[Index] 			= Object
			TempPos[Index] 			= POSITIONS[OrigIdx]
			CODES[Index] 			= Key // INDEX_SPACE
			STATIC_SLOT[Object] 	= Index
		end

		ALTER_OBJECTS, ALTER_POSITIONS = OBJECTS, POSITIONS
		OBJECTS, POSITIONS 			= TempObj, TempPos
	else
		for Index: number = 1, StaticCount do STATIC_SLOT[OBJECTS[Index]] = Index end
		table.clear(ALTER_OBJECTS)
		table.clear(ALTER_POSITIONS)
		BufferCount = 0
	end

	const ChunkCount: number = (StaticCount + CHUNK_SIZE - 1) // CHUNK_SIZE
	
	for c: number = 1, ChunkCount do
		const First	: number = (c - 1) * CHUNK_SIZE + 1
		local Last	: number = c * CHUNK_SIZE
		
		if Last > StaticCount then Last = StaticCount end
		
		local Lo: vector 	= POSITIONS[First]
		local Hi: vector 	= Lo
		
		for i: number = First + 1, Last do
			const p: vector = POSITIONS[i]
			Lo, Hi 			= vector.min(Lo, p), vector.max(Hi, p)
		end
		
		CHUNK_MIN[c] 	= Lo
		CHUNK_MAX[c] 	= Hi
		CHUNK_CLEAN[c] 	= true
	end
	
	RebuildThreshold, Unsorted 	= StaticCount * 16, false
end

const function QueryDynamic(Position: vector, Radius: number, R2: number, Results: ObjArray, ResultCount: number): number
	const BroadRadius: number 	= Radius * GRID_RADIUS_SCALE + GridPadding
	
	const MinX: number 			= math.floor((Position.x - BroadRadius) * GridInverse)
	const MinY: number 			= math.floor((Position.y - BroadRadius) * GridInverse)
	const MinZ: number 			= math.floor((Position.z - BroadRadius) * GridInverse)
	const MaxX: number 			= math.floor((Position.x + BroadRadius) * GridInverse)
	const MaxY: number 			= math.floor((Position.y + BroadRadius) * GridInverse)
	const MaxZ: number 			= math.floor((Position.z + BroadRadius) * GridInverse)

	const CellCount: number 	= (MaxX - MinX + 1) * (MaxY - MinY + 1) * (MaxZ - MinZ + 1)
	
	if CellCount * 2 >= DynamicCount or DynamicCount <= 16 or math.max(math.abs(MinX), math.abs(MinY), math.abs(MinZ), math.abs(MaxX), math.abs(MaxY), math.abs(MaxZ)) > EXACT_CELL_LIMIT then
		for Index: number = 1, DynamicCount do
			const Diff: vector 	= DYNAMIC_POSITION[Index] - Position
			if vector.dot(Diff, Diff) <= R2 then
				ResultCount += 1
				Results[ResultCount] = DYNAMIC_OBJECT[Index]
			end
		end
		return ResultCount
	end
	
	for X: number = MinX, MaxX do
		for Y: number = MinY, MaxY do
			for Z: number = MinZ, MaxZ do
				local Index: number = GRID[vector.create(X, Y, Z)] or 0
				while Index ~= 0 do
					const Diff: vector = DYNAMIC_POSITION[Index] - Position
					if vector.dot(Diff, Diff) <= R2 then
						ResultCount += 1
						Results[ResultCount] = DYNAMIC_OBJECT[Index]
					end
					Index = DYNAMIC_NEXT[Index]
				end
			end
		end
	end
	
	return ResultCount
end

const function QueryStatic(Position: vector, Radius: number, RadiusSqr: number, Results: ObjArray): number
	if Unsorted then
		Rebuild()
	elseif PendingCount + StaticTombs > 0 then
		QueryDebt += PendingCount + StaticTombs
		if QueryDebt >= RebuildThreshold then Rebuild() end
	end
	
	local ResultCount	: number 	= 0
	
	const RadiusVector	: vector 	= vector.one * Radius
	const MinCell		: vector 	= vector.clamp(vector.floor(Position + OFFSET_VECTOR - RadiusVector), ZERO_VECTOR, LAST_VECTOR)
	const MaxCell		: vector 	= vector.clamp(vector.ceil(Position + OFFSET_VECTOR + RadiusVector), ZERO_VECTOR, LAST_VECTOR)
	
	const StartIdx		: number 	= BinarySearch(MORTON_LUT[MinCell.x + 1] + MORTON_LUT[MinCell.y + 1] * 2 + MORTON_LUT[MinCell.z + 1] * 4, 1)
	const EndIdx		: number	= BinarySearch(MORTON_LUT[MaxCell.x + 1] + MORTON_LUT[MaxCell.y + 1] * 2 + MORTON_LUT[MaxCell.z + 1] * 4 + 1, StartIdx) - 1
	
	if StartIdx > EndIdx and PendingCount == 0 then return 0 end
	
	if PendingCount > 0 then
		for Index: number = 1, PendingCount do
			const Diff: vector 		= ALTER_POSITIONS[Index] - Position
			if vector.dot(Diff, Diff) <= RadiusSqr then
				ResultCount 		+= 1
				Results[ResultCount] = ALTER_OBJECTS[Index]
			end
		end
	end
	
	if StaticCount == 0 or StartIdx > EndIdx then return ResultCount end
	
	local First		: number 	= StartIdx
	
	for c: number = (StartIdx - 1) // CHUNK_SIZE + 1, (EndIdx - 1) // CHUNK_SIZE + 1 do
		local Last	: number 	= c * CHUNK_SIZE
		
		if Last > EndIdx then Last = EndIdx end
		
		const cMin	: vector,
			cMax	: vector 	= CHUNK_MIN[c], CHUNK_MAX[c]
		const Near	: vector 	= vector.clamp(Position, cMin, cMax) - Position
		
		if vector.dot(Near, Near) <= RadiusSqr then
			const Far: vector 	= vector.max(cMax - Position, Position - cMin)
			
			if vector.dot(Far, Far) <= RadiusSqr and CHUNK_CLEAN[c] then
				table.move(OBJECTS, First, Last, ResultCount + 1, Results)
				ResultCount 	+= Last - First + 1
			else
				for Index: number = First, Last do
					const Diff: vector 		= POSITIONS[Index] - Position
					if vector.dot(Diff, Diff) <= RadiusSqr then
						const Object: any = OBJECTS[Index]
						if Object then
							ResultCount += 1
							Results[ResultCount] = Object
						end
					end
				end
			end
		end
		
		First = Last + 1
	end
	
	return ResultCount
end

----------------------------------
--	::	Insertion			::	--
----------------------------------

function Morton.Static(Object: any, Position: vector): ()
	const DynamicSlot: number? = DYNAMIC_SLOT[Object]

	if DynamicSlot then RemoveDynamic(DynamicSlot) end

	const Cell	: vector 	= vector.clamp(vector.floor(Position + OFFSET_VECTOR), ZERO_VECTOR, LAST_VECTOR)
	const Code	: number 	= MORTON_LUT[Cell.x + 1] + MORTON_LUT[Cell.y + 1] * 2 + MORTON_LUT[Cell.z + 1] * 4

	const Slot	: number? 	= STATIC_SLOT[Object]
	
	if Slot then
		if Slot < 0 then
			const I: number		= -Slot
			ALTER_POSITIONS[I] 	= Position
			PENDING_CODE[I] 	= Code
			return
		end

		POSITIONS[Slot] = FAR_AWAY
		OBJECTS[Slot] 	= nil
		CHUNK_CLEAN[(Slot - 1) // CHUNK_SIZE + 1] = false

		StaticTombs += 1
	elseif (Unsorted or StaticCount == 0) and PendingCount == 0 and StaticTombs == 0 then
		StaticCount += 1

		CODES[StaticCount] 		= Code
		OBJECTS[StaticCount] 	= Object
		POSITIONS[StaticCount] 	= Position
		STATIC_SLOT[Object] 	= StaticCount

		Unsorted = true
		
		return
	end

	PendingCount += 1

	ALTER_OBJECTS[PendingCount] 	= Object
	ALTER_POSITIONS[PendingCount]= Position
	
	PENDING_CODE[PendingCount] 	= Code
	STATIC_SLOT[Object] 		= -PendingCount
end

function Morton.Dynamic(Object: any, Position: vector): ()
	const Index		: number? 	= DYNAMIC_SLOT[Object]
	
	if Index then
		MoveDynamic(Index, Position)
		return
	end

	if STATIC_SLOT[Object] then Morton.Remove(Object) end

	DynamicCount += 1

	DYNAMIC_OBJECT[DynamicCount] 	= Object
	DYNAMIC_POSITION[DynamicCount] 	= Position
	DYNAMIC_SLOT[Object] 			= DynamicCount

	LinkDynamic(DynamicCount, CellOf(Position))
end

----------------------------------
--	::	API					::	--
----------------------------------

function Morton.Count(): number
	return StaticCount - StaticTombs + PendingCount + DynamicCount
end

function Morton.Configure(CellSize: number?): number
	if not CellSize then return GridCellSize end
	
	assert(CellSize > 0 and CellSize < math.huge and 1 / CellSize < math.huge, 'Cell size must have a positive finite size and reciprocal')
	assert(DynamicCount == 0, 'Remove dynamic objects before configuring the grid')
	
	GridCellSize 	= CellSize
	GridInverse 	= 1 / CellSize
	GridVectorScale = math.frexp(GridInverse) == 0.5 and GridInverse >= 1.1754943508222875e-38 and GridInverse <= 3.4028234663852886e38
	GridPadding 	= if GridVectorScale then math.max(1e-20, CellSize * 1.401298464324817e-45) else 1e-20
	
	return CellSize
end

function Morton.Move(Object: any, Position: vector): boolean
	const Index: number? = DYNAMIC_SLOT[Object]
	if not Index then return false end
	MoveDynamic(Index, Position)
	return true
end

function Morton.Radius(Position: vector, Radius: number, Results: ObjArray): ObjArray
	table.clear(Results)
	
	const RadiusSqr		: number = Radius * Radius
	local ResultCount	: number = 0
	
	if StaticCount > 0 or PendingCount > 0 then
		ResultCount 	= QueryStatic(Position, Radius, RadiusSqr, Results)
	end
	
	if DynamicCount > 0 then
		QueryDynamic(Position, Radius, RadiusSqr, Results, ResultCount)
	end
	
	return Results
end

function Morton.Clear(): ()
	table.clear(DYNAMIC_OBJECT)
	table.clear(DYNAMIC_POSITION)
	table.clear(DYNAMIC_CELL)
	table.clear(DYNAMIC_NEXT)
	table.clear(DYNAMIC_PREV)
	table.clear(DYNAMIC_SLOT)
	table.clear(GRID)
	
	DynamicCount = 0
	
	table.clear(CODES)
	table.clear(OBJECTS)
	table.clear(POSITIONS)
	table.clear(ALTER_OBJECTS)
	table.clear(ALTER_POSITIONS)
	table.clear(CHUNK_MIN)
	table.clear(CHUNK_MAX)
	table.clear(CHUNK_CLEAN)
	table.clear(PENDING_CODE)
	table.clear(STATIC_SLOT)
	
	StaticCount, StaticTombs, PendingCount, BufferCount = 0, 0, 0, 0
	RebuildThreshold, Unsorted 	= 256, false
	QueryDebt = 0
end

function Morton.Remove(Object: any): ()
	const DynamicSlot: number? = DYNAMIC_SLOT[Object]

	if DynamicSlot then
		RemoveDynamic(DynamicSlot)
		return
	end

	const Slot: number? 		= STATIC_SLOT[Object]
	if not Slot then return end

	if Slot < 0 then
		const I: number		 	= -Slot
		const LastObject: any 	= ALTER_OBJECTS[PendingCount]

		ALTER_OBJECTS[I] 		= LastObject
		ALTER_POSITIONS[I] 		= ALTER_POSITIONS[PendingCount]
		PENDING_CODE[I] 		= PENDING_CODE[PendingCount]
		STATIC_SLOT[LastObject] = -I

		ALTER_OBJECTS[PendingCount] 	= nil
		ALTER_POSITIONS[PendingCount] = nil
		PENDING_CODE[PendingCount] 	= nil

		PendingCount 			-= 1
	elseif Unsorted and StaticTombs == 0 and PendingCount == 0 and Slot > 0 then
		const LastObject: any 	= OBJECTS[StaticCount]

		CODES[Slot] 			= CODES[StaticCount]
		OBJECTS[Slot] 			= LastObject
		POSITIONS[Slot] 		= POSITIONS[StaticCount]
		STATIC_SLOT[LastObject] = Slot
		CODES[StaticCount] 		= nil
		OBJECTS[StaticCount] 	= nil
		POSITIONS[StaticCount] 	= nil

		StaticCount 			-= 1
	else
		POSITIONS[Slot] 		= FAR_AWAY
		OBJECTS[Slot] 			= nil
		CHUNK_CLEAN[(Slot - 1) // CHUNK_SIZE + 1] = false

		StaticTombs 	+= 1
	end

	STATIC_SLOT[Object] = nil
end

----------------------------------
--	::	Return				::	--
----------------------------------

return Morton