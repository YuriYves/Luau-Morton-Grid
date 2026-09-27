--!strict
--!native
--!optimize 2

------------------------------------------
--	::	Benchmark					::	--
------------------------------------------

const Players 			= game:GetService("Players")
const ReplicatedStorage = game:GetService("ReplicatedStorage")
const RunService 		= game:GetService("RunService")

const Morton 			= require(ReplicatedStorage:WaitForChild("MortonGrid")) :: any
const QuentyOctree 		= require(ReplicatedStorage:WaitForChild("QuentyOctree")) :: any

------------------------------------------
--	::	Configuration				::	--
------------------------------------------

const Iterations 		= 3_000
const Radius 			= 100
const RadiusSqr 		= Radius * Radius

const DynamicMovers 	= 64
const DynamicFrames 	= 100

const WarmupObjects 	= 50
const WarmupQueries 	= 100
const WarmupMoves 		= 100

const RandomSeed 		= 0x4D4F5254

const GridX 			= 40
const GridY 			= 25
const GridZ 			= 40
const ObjectCount 		= GridX * GridY * GridZ

const SpacingX 			= 10
const SpacingY 			= 15
const SpacingZ 			= 25

------------------------------------------
--	::	Local Functions				::	--
------------------------------------------

const function assert<T>(value: T, errorMessage: string?): T if not value then error(errorMessage, 1) end; return value end

------------------------------------------
--	::	Startup						::	--
------------------------------------------

if #Players:GetPlayers() == 0 then
	local Waiting: boolean = true

	Players.PlayerAdded:Connect(function()
		Waiting = false
	end)

	while Waiting do
		task.wait(0.1)
	end
end

print("[Benchmark] Waiting 10 seconds for engine stabilization...")

task.wait(10)

------------------------------------------
--	::	Dataset Generation			::	--
------------------------------------------

const Objects: { Instance } = {}

local Folder: Folder 	= Instance.new('Folder')
Folder.Name 			= 'Benchmark'
Folder.Parent 			= workspace

print(string.format("[Benchmark] Generating %d spheres...", ObjectCount))

for X: number = 1, GridX do
	for Y: number = 1, GridY do
		for Z: number = 1, GridZ do
			const Part 		= Instance.new("Part")
			Part.Shape 		= Enum.PartType.Ball
			Part.Size 		= Vector3.new(2, 2, 2)
			Part.Anchored 	= true
			Part.CanCollide = false
			Part.CanTouch 	= false
			Part.CanQuery 	= false
			Part.Position 	= Vector3.new((X - 1 - (GridX - 1) / 2) * SpacingX, (Y - 1) * SpacingY, (Z - 1 - (GridZ - 1) / 2) * SpacingZ)
			Part.Parent 	= Folder
			table.insert(Objects, Part)
		end
	end
end

task.wait(3)

print(string.format("[Benchmark] Inserting the positions..."))

const Positions: { vector } 			= table.create(ObjectCount) :: any
const Vector3Positions: { Vector3 } 	= table.create(ObjectCount) :: any

for Index: number = 1, ObjectCount do
	const Position: Vector3 	= (Objects[Index] :: BasePart).Position
	Positions[Index] 			= vector.create(Position.X, Position.Y, Position.Z)
	Vector3Positions[Index] 	= Position
end

task.wait(3)

------------------------------------------
--	::	Deterministic Queries		::	--
------------------------------------------

const RNG = Random.new(RandomSeed)

const Queries		: { vector } 	= table.create(Iterations) :: any
const Vector3Queries: { Vector3 } 	= table.create(Iterations) :: any

for Index: number = 1, Iterations do
	const Query: vector 	= vector.create(RNG:NextNumber(-250, 250), RNG:NextNumber(0, 50), RNG:NextNumber(-250, 250))
	Queries[Index] 			= Query
	Vector3Queries[Index] 	= Vector3.new(Query.x, Query.y, Query.z)
end

------------------------------------------
--	::	Reusable Buffers			::	--
------------------------------------------

const MortonResults	: { any } 				= table.create(256)
const BruteResults	: { any } 				= table.create(256)
const ValidationSet	: { [any]: boolean } 	= {}

------------------------------------------
--	::	Helpers						::	--
------------------------------------------

const function BruteRadius(Query: vector, Results: { any }): number
	table.clear(Results)
	local ResultCount: number = 0

	for Index: number = 1, ObjectCount do
		const Difference: vector = Positions[Index] - Query
		if vector.dot(Difference, Difference) <= RadiusSqr then
			ResultCount += 1
			Results[ResultCount] = Objects[Index]
		end
	end

	return ResultCount
end

const function ValidateResults(QueryIndex: number, MortonResult: { any }, ExpectedResult: { any }): ()
	if #MortonResult ~= #ExpectedResult then
		error(string.format("Correctness failure at query %d: Morton returned %d objects, brute force returned %d", QueryIndex, #MortonResult, #ExpectedResult))
	end
	table.clear(ValidationSet)

	for Index: number = 1, #ExpectedResult do
		ValidationSet[ExpectedResult[Index]] = true
	end

	for Index: number = 1, #MortonResult do
		const Object = MortonResult[Index]
		if not ValidationSet[Object] then
			error(string.format("Correctness failure at query %d: Morton returned an unexpected object", QueryIndex))
		end
	end
end

------------------------------------------
--	::	Warmup						::	--
------------------------------------------

print("[Benchmark] Running warmup...")

do
	const Count: number = math.min(ObjectCount, WarmupObjects)

	for Index: number = 1, Count do
		Morton.Static(Objects[Index], Positions[Index])
	end

	for Index: number = 1, math.min(Iterations, WarmupQueries) do
		Morton.Radius(Queries[Index], Radius, MortonResults)
	end

	Morton.Clear()

	local Tree = QuentyOctree.new()

	for Index: number = 1, Count do
		Tree:CreateNode(Vector3Positions[Index], Objects[Index])
	end

	for Index: number = 1, math.min(Iterations, WarmupQueries) do
		Tree:RadiusSearch(Vector3Queries[Index], Radius)
	end

	for Index: number = 1, math.min(Iterations, WarmupQueries) do
		BruteRadius(Queries[Index], BruteResults)
	end

	local WarmObjects		: { any } 		= table.create(WarmupObjects) :: any
	local WarmPositions		: { vector } 	= table.create(WarmupObjects) :: any
	local WarmQuentyNodes	: { any } 		= table.create(WarmupObjects) :: any

	local WarmTree 			= QuentyOctree.new()

	for Index: number = 1, WarmupObjects do
		local Object 				= {}
		local Position 				= vector.create(Index, 0, Index)
		WarmObjects[Index] 			= Object
		WarmPositions[Index] 		= Position
		Morton.Dynamic(Object, Position)
		WarmQuentyNodes[Index] 		= WarmTree:CreateNode(Vector3.new(Position.x, Position.y, Position.z), Object)
	end

	for Step: number = 1, WarmupMoves do
		const Index: number 		= (Step - 1) % WarmupObjects + 1
		const Position: vector 		= WarmPositions[Index] + vector.create(1, 0, 1)
		WarmPositions[Index] 		= Position
		Morton.Move(WarmObjects[Index], Position)
		WarmQuentyNodes[Index]:SetPosition(Vector3.new(Position.x, Position.y, Position.z))
	end

	Morton.Clear()
end

task.wait(0.5)

------------------------------------------
--	::	Static Population			::	--
------------------------------------------

print("[Benchmark] Measuring static population...")

const MortonPopulateStart: number 	= os.clock()
for Index: number = 1, ObjectCount do
	Morton.Static(Objects[Index], Positions[Index])
end
const MortonPopulateTime: number 	= os.clock() - MortonPopulateStart

const QuentyTree 					= QuentyOctree.new()
const QuentyNodes: { any } 			= table.create(ObjectCount) :: any

const QuentyPopulateStart: number 	= os.clock()
for Index: number = 1, ObjectCount do
	QuentyNodes[Index] = QuentyTree:CreateNode(Vector3Positions[Index], Objects[Index])
end
const QuentyPopulateTime: number 	= os.clock() - QuentyPopulateStart

------------------------------------------
--	::	First Query					::	--
------------------------------------------

print("[Benchmark] Measuring first query...")

const MortonFirstQueryStart: number = os.clock()
Morton.Radius(Queries[1], Radius, MortonResults)
const MortonFirstQueryTime: number 	= os.clock() - MortonFirstQueryStart

const QuentyFirstQueryStart: number = os.clock()
QuentyTree:RadiusSearch(Vector3Queries[1], Radius)
const QuentyFirstQueryTime: number 	= os.clock() - QuentyFirstQueryStart

------------------------------------------
--	::	Validation					::	--
------------------------------------------

print(string.format("[Benchmark] Validating %d Morton queries against brute force...", Iterations))

for Index: number = 1, Iterations do
	Morton.Radius(Queries[Index], Radius, MortonResults)
	BruteRadius(Queries[Index], BruteResults)
	ValidateResults(Index, MortonResults, BruteResults)
end

print(string.format("[Benchmark] Correctness validation passed: %d/%d queries", Iterations, Iterations))

------------------------------------------
--	::	Steady-State Static Queries	::	--
------------------------------------------

print(string.format("[Benchmark] Measuring %d static radius queries...", Iterations))

------------------------------------------
--	::	Morton						::	--
------------------------------------------

local MortonHits: number 			= 0
const MortonHeapBefore: number 		= gcinfo()
const MortonQueryStart: number 		= os.clock()

for Index: number = 1, Iterations do
	Morton.Radius(Queries[Index], Radius, MortonResults)
	MortonHits += #MortonResults
end

const MortonSearchTime: number 		= os.clock() - MortonQueryStart
const MortonHeapDelta: number 		= gcinfo() - MortonHeapBefore

------------------------------------------
--	::	Quenty						::	--
------------------------------------------

local QuentyHits: number 			= 0
const QuentyHeapBefore: number 		= gcinfo()
const QuentyQueryStart: number 		= os.clock()

for Index: number = 1, Iterations do
	local Results = QuentyTree:RadiusSearch(Vector3Queries[Index], Radius)
	QuentyHits += #Results
end

const QuentySearchTime: number 		= os.clock() - QuentyQueryStart
const QuentyHeapDelta: number 		= gcinfo() - QuentyHeapBefore

------------------------------------------
--	::	Brute Force					::	--
------------------------------------------

local BruteHits: number 			= 0
const BruteQueryStart: number 		= os.clock()

for Index: number = 1, Iterations do
	const Query: vector = Queries[Index]
	local Hits: number 	= 0

	for PositionIndex: number = 1, ObjectCount do
		const Difference: vector = Positions[PositionIndex] - Query
		if vector.dot(Difference, Difference) <= RadiusSqr then
			Hits += 1
		end
	end

	BruteHits += Hits
end

const BruteSearchTime: number 		= os.clock() - BruteQueryStart

------------------------------------------
--	::	Prepare Dynamic Benchmark	::	--
------------------------------------------

print(string.format("[Benchmark] Preparing dynamic benchmark (%d movers, %d frames)...", DynamicMovers, DynamicFrames))

Morton.Clear()

const DynamicQuentyTree 					= QuentyOctree.new()
const DynamicObjects: { any } 				= table.create(DynamicMovers) :: any
const DynamicInitial: { vector } 			= table.create(DynamicMovers) :: any
const DynamicInitialVector3: { Vector3 } 	= table.create(DynamicMovers) :: any
const DynamicQuentyNodes: { any } 			= table.create(DynamicMovers) :: any
const DynamicStepCount: number 				= DynamicMovers * DynamicFrames
const DynamicTrajectory: { vector } 		= table.create(DynamicStepCount) :: any
const DynamicTrajectoryVector3: { Vector3 } = table.create(DynamicStepCount) :: any

const DynamicRNG 							= Random.new(RandomSeed + 1)

for Mover: number = 1, DynamicMovers do
	const Object 							= { id = "mover_" .. Mover }
	const Position: vector 					= vector.create(
		DynamicRNG:NextNumber(-150, 150),
		DynamicRNG:NextNumber(5, 30),
		DynamicRNG:NextNumber(-150, 150)
	)

	DynamicObjects[Mover] 					= Object
	DynamicInitial[Mover] 					= Position
	DynamicInitialVector3[Mover] 			= Vector3.new(Position.x, Position.y, Position.z)

	local Current: vector 					= Position

	for Frame: number = 1, DynamicFrames do
		Current += vector.create(math.sin(Frame * 0.1 + Mover), 0, math.cos(Frame * 0.1 + Mover))
		const Index: number 				= (Frame - 1) * DynamicMovers + Mover
		DynamicTrajectory[Index] 			= Current
		DynamicTrajectoryVector3[Index] 	= Vector3.new(Current.x, Current.y, Current.z)
	end
end

for Mover: number = 1, DynamicMovers do
	Morton.Dynamic(DynamicObjects[Mover], DynamicInitial[Mover])
	DynamicQuentyNodes[Mover] = DynamicQuentyTree:CreateNode(DynamicInitialVector3[Mover], DynamicObjects[Mover])
end

------------------------------------------
--	::	Dynamic Movement			::	--
------------------------------------------

print(string.format("[Benchmark] Measuring movement (%d updates)...", DynamicStepCount))

------------------------------------------
--	::	Morton						::	--
------------------------------------------

const MortonMoveStart: number 		= os.clock()

for Frame: number = 1, DynamicFrames do
	const Base: number = (Frame - 1) * DynamicMovers
	for Mover: number = 1, DynamicMovers do
		Morton.Move(DynamicObjects[Mover], DynamicTrajectory[Base + Mover])
	end
end

const MortonMoveTime: number 		= os.clock() - MortonMoveStart

------------------------------------------
--	::	Quenty						::	--
------------------------------------------

const QuentyMoveStart: number 		= os.clock()

for Frame: number = 1, DynamicFrames do
	const Base: number = (Frame - 1) * DynamicMovers
	for Mover: number = 1, DynamicMovers do
		DynamicQuentyNodes[Mover]:SetPosition(DynamicTrajectoryVector3[Base + Mover])
	end
end

const QuentyMoveTime: number 		= os.clock() - QuentyMoveStart

------------------------------------------
--	::	Report						::	--
------------------------------------------

const Separator: string 			= string.rep("=", 106)
const SubSeparator: string 			= string.rep("-", 106)

const Environment: string 			= if RunService:IsStudio() then "Roblox Studio" else "Roblox Server"

print("\n" .. Separator)
print("MORTON GRID BENCHMARK")
print(Separator)
print(string.format("Environment: %s | Random seed: 0x%X", Environment, RandomSeed))
print(SubSeparator)
print(string.format("%-30s %-22s %-22s %-22s", "METRIC", "MORTON GRID", "QUENTY OCTREE", "BRUTE FORCE"))
print(Separator)
print(string.format("%-30s %-22d %-22d %-22d", "Static objects", ObjectCount, ObjectCount, ObjectCount))
print(string.format("%-30s %-22d %-22d %-22d", "Search iterations", Iterations, Iterations, Iterations))
print(string.format("%-30s %-22.1f %-22.1f %-22.1f", "Search radius", Radius, Radius, Radius))
print(SubSeparator)
print(string.format("%-30s %-22.6f %-22.6f %-22s", "Population time (s)", MortonPopulateTime, QuentyPopulateTime, "N/A"))
print(string.format("%-30s %-22.4f %-22.4f %-22s", "Population / object (us)", (MortonPopulateTime / ObjectCount) * 1e6, (QuentyPopulateTime / ObjectCount) * 1e6, "N/A"))
print(SubSeparator)
print(string.format("%-30s %-22.6f %-22.6f %-22s", "First query (s)", MortonFirstQueryTime, QuentyFirstQueryTime, "N/A"))
print(string.format("%-30s %-22.6f %-22.6f %-22s", "Populate + first query (s)", MortonPopulateTime + MortonFirstQueryTime, QuentyPopulateTime + QuentyFirstQueryTime, "N/A"))
print(SubSeparator)
print(string.format("%-30s %-22.6f %-22.6f %-22.6f", "Search total (s)", MortonSearchTime, QuentySearchTime, BruteSearchTime))
print(string.format("%-30s %-22.4f %-22.4f %-22.4f", "Average query (us)", (MortonSearchTime / Iterations) * 1e6, (QuentySearchTime / Iterations) * 1e6, (BruteSearchTime / Iterations) * 1e6))
print(string.format("%-30s %-22.2fx %-22.2fx %-22.2fx", "Relative to brute force", BruteSearchTime / MortonSearchTime, BruteSearchTime / QuentySearchTime, 1.0))
print(string.format("%-30s %-22.2fx %-22s %-22s", "Relative to Quenty", QuentySearchTime / MortonSearchTime, "1.00x", "N/A"))
print(SubSeparator)
print(string.format("%-30s %-22.2f %-22.2f %-22.2f", "Average results / query", MortonHits / Iterations, QuentyHits / Iterations, BruteHits / Iterations))
print(string.format("%-30s %-22d %-22d %-22d", "Total results", MortonHits, QuentyHits, BruteHits))
print(string.format("%-30s %-22s %-22s %-22s", "Correctness validation", string.format("PASS (%d/%d)", Iterations, Iterations), "Not independently checked", "Reference"))
print(SubSeparator)
print(string.format("%-30s %-22d %-22d %-22s", "Heap delta via gcinfo (KB)", MortonHeapDelta, QuentyHeapDelta, "N/A"))
print(SubSeparator)
print(string.format("%-30s %-22d %-22d %-22s", "Dynamic movers", DynamicMovers, DynamicMovers, "N/A"))
print(string.format("%-30s %-22d %-22d %-22s", "Movement updates", DynamicStepCount, DynamicStepCount, "N/A"))
print(string.format("%-30s %-22.6f %-22.6f %-22s", "Movement total (s)", MortonMoveTime, QuentyMoveTime, "N/A"))
print(string.format("%-30s %-22.4f %-22.4f %-22s", "Average move (us)", (MortonMoveTime / DynamicStepCount) * 1e6, (QuentyMoveTime / DynamicStepCount) * 1e6, "N/A"))
print(string.format("%-30s %-22.2fx %-22s %-22s", "Relative movement time", QuentyMoveTime / MortonMoveTime, "1.00x", "N/A"))
print(Separator .. "\n")