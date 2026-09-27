# Morton Grid

## Abstract

Morton Grid is a spatial-indexing experiment written in Luau. It began with a question I had wanted to explore for some time: *"What would happen if Morton ordering were used less as a full hierarchy and more as an ordering for the static side of a spatial index, while a separate structure handled movement?"*

The first versions were closer to an Octree investigation. You may notice the current implementation is no longer an Octree. It now combines two representations according to how objects are expected to behave. Static objects are stored with Morton codes as a spatial ordering over linear arrays. Dynamic objects are stored in a spatial hash grid intended for inexpensive movement. This is mainly because I didn't want to have to create two modules for different purposes; instead, I could easily reuse tables from the current framework, or even the architecture itself.

The difference was already thought by design. An object that does not move does not require a structure designed for frequent relocation, just as an object that moves continuously should not require an ordered spatial representation to be rebuilt every time its position changes.

The result is a fairly specific spatial index, not a general replacement for Octrees. There are workloads where a conventional Octree, including Quenty's implementation, is more appropriate. The proposed framework is mainly an experiment in what can be simplified when static and dynamic objects are allowed to follow different paths.

## Motivation

Early versions centered on Morton codes and the idea of representing a three-dimensional hierarchy without conventional nested indexing. A Morton code, also known as Z-order, interleaves the bits of multiple coordinates into a single integer. The interesting property is not merely the fact that three coordinates transform into a single number, quite the opposite, but rather that the resulting ordering preserves enough spatial locality to make a linear representation useful.

Over time the direction changed. Instead of reproducing an Octree through Morton codes, the static side only uses them to establish an ordering. Objects are kept in parallel arrays containing their Morton code, position, and associated value. Queries use that ordering to restrict the region that needs inspection, after which the actual Euclidean distance is still evaluated. The Morton code is therefore not the query result and does not replace the exact spatial test.

The broader question then became: *"How much of the usual spatial-indexing machinery can be removed if static and dynamic objects are handled separately?"*

## Static Objects

Static objects are accumulated into a Morton-ordered representation. Insertions and removals are not necessarily followed by an immediate reconstruction of the sorted arrays. New elements can remain pending, removed elements can remain as *tombstones*, and the structure is rebuilt when necessary. Maintaining perfect ordering after every modification would make the static representation unnecessarily expensive for data that is expected to change infrequently.

The sorted data is divided into small chunks, and each chunk stores the minimum and maximum positions occupied by its elements. During a radius query, this provides an additional level of rejection before individual distance tests are performed. If it can be determined that the entire chunk is contained within the query sphere, its objects can then be copied directly to the results buffer. The static Morton space is intentionally specialized and thus not arbitrary. Positions are quantized onto the fixed Morton grid used by the implementation, while the original positions remain available for the final distance test. Therefore, the structure must be treated in accordance with this intended spatial scale rather than as an unrestricted coordinate index.

## Dynamic Objects

Moving objects use a different representation. They are stored in a configurable spatial hash grid. Each occupied cell points to an intrusive linked list implemented via arrays; thus, moving an object requires only updating its position and when necessary, unlinking it from one cell and linking it to another.

The grid is not always used for queries. For small dynamic sets, or when traversing grid cells is expected to be more costly than examining the objects directly, the module resorts to a linear scan. This is intentional. A spatial structure entails its own search overhead. Therefore, using it for every query does not necessarily reduce the amount of processing required.

The default cell size can be changed through `Morton.Configure()` before dynamic objects are inserted.

## Implementation

Two objectives guide the implementation: keeping the code concise and explicit, and making common execution paths predictable. The structure does not eliminate allocations entirely; it still employs tables and arrays. Whenever possible, the aim is to reduce the number of allocated tables and keep related data in parallel arrays accessed by index.

This involves a trade-off: some memory is sacrificed to ensure that access patterns are contiguous and highly predictable. This approach tends to favor CPUs, which benefit from data locality and regular loops. In this sense, the implementation is also an exercise in mechanical sympathy.

It was also designed with worst-case access patterns in mind. For small scenes—involving on the order of a few dozen actors, allocation pressure is unlikely to be the deciding factor. Furthermore, the framework was built to be simple and transparent regarding the workloads for which this choice makes sense.

## Radius Queries

Both representations are exposed through a single radius query.
```lua
const Results = {}
const Nearby  = Morton.Radius(vector.zero, 64, Results)
```
The supplied result array is reused and cleared by the query instead of allocating a new table. Static objects are evaluated first and dynamic objects are appended afterward. Objects can be assigned to either representation directly:
```lua
Morton.Static(Object, Position)
Morton.Dynamic(Object, Position)
```
Dynamic objects can then be relocated without reinsertion:
```lua
Morton.Move(Object, NewPosition)
```
An object can also be passed to `Static` or `Dynamic` after already being registered. The module handles the transition between both representations internally. Removal is shared by both:
```lua
Morton.Remove(Object)
```
The module itself owns a single spatial index. It is not implemented as an instantiable Octree or grid object.

## Native Code Generation

The source enables Luau native code generation through `--!native` and uses `--!optimize 2`. A significant amount of the implementation consists of numerical operations, vector operations and tightly repeated loops, which makes native execution relevant to its intended performance profile.

However, this should not be interpreted as a *claim that native code generation always produces a particular speedup*, nor that results obtained on one machine are representative of another. The module should be benchmarked under the same execution conditions in which it will actually be used. Because of this, it was designed both for the `native` environment and, primarily, for the VM.

## Benchmarks

Benchmarks will be kept separately in `Benchmark.md` inside the Benchmark folder. They are intended to describe the behavior observed under specific workloads rather than establish a fixed performance ratio between Morton Grid and another spatial structure.

Object count, spatial distribution, query radius, movement frequency, grid configuration, native code generation and the processor running the test can all materially change the result. The benchmark environment is therefore recorded together with the measurements.

## Scope

Morton Grid came from an experiment rather than an attempt to design a universal spatial framework. Its main assumption is that static and dynamic objects do not necessarily benefit from the same representation. The implementation simply takes advantage of that distinction and combines a *Morton-ordered static index with a spatially hashed dynamic index* behind a small common API.

I should mention again that assumption *will not* fit every project. A conventional Octree may be preferable when hierarchical subdivision itself is useful, when its update characteristics match the workload better or simply when a more general and established structure is desired. Likewise, Roblox's own spatial facilities can be preferable when the objects being queried already exist in a form those systems can index directly.

The framework proposed here is primarily the result of exploring how much of the usual spatial-indexing machinery can be removed when the problem is narrowed enough.
