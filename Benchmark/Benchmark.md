# Benchmark

The benchmarks in this document describe the behavior of Morton Grid under a reproducible workload. They are not intended to establish a fixed performance ratio between Morton Grid, Quenty's Octree and a linear scan.
The structures have substantially different architectures and APIs. The benchmark just attempts to compare equivalent operations where possible while preserving the behavior of the original implementations.

## Test Environment

The local run was executed through Roblox Studio on an **Intel(R) Pentium(R) CPU G3250 @ 3.20 GHz**. Native code generation is not available on this machine, so this run represents the Luau VM environment used during development. It was performed twice to observe variance between executions under the same conditions.
A second run was executed on a Roblox server, where the modules were used with `--!native` and `--!optimize 2` enabled. The same deterministic dataset and random seed were used in every execution.
The benchmark contains 40,000 static objects arranged in a regular three-dimensional grid. It performs 3,000 radius queries with a radius of 100 studs. The generated grid uses dimensions of `40x25x40`, with spacing of 10, 15 and 25 studs along the X, Y and Z axes respectively.
The random seed used for query generation is `0x4D4F5254` (1297044052). The dynamic benchmark uses 64 moving objects over 100 frames, producing 6,400 position updates.

## Methodology

> [!NOTE]
> The Quenty implementation used in these tests is a standalone single-file edition of the Nevermore Octree.
> The parts required for the Octree itself were preserved, while dependencies such as the Nevermore loader and drawing utilities were removed so that the structure could be benchmarked independently.
> This should therefore be understood primarily as a comparison with Quenty's Octree approach rather than as a benchmark of the complete Nevermore ecosystem.
> Integrating the original package into a larger project may introduce different execution and memory characteristics.

Morton Grid and Quenty's Octree are first populated with the same set of positions. Population and first-query costs are measured separately because Morton Grid deliberately postpones construction of its sorted static representation.
Calling `Morton.Static()` does not necessarily sort or rebuild the structure immediately. The first radius query therefore includes the initial deferred reconstruction.
Quenty's Octree constructs its hierarchy incrementally while nodes are inserted, so its first query does not contain an equivalent deferred construction cost.

For steady-state queries, both structures receive the same 3,000 query positions and the same radius. A linear scan over all 40,000 objects is also measured as a baseline.
Morton Grid receives a reusable result buffer. Quenty's `RadiusSearch`, according to its normal interface, creates its result tables internally and additionally computes squared distances for returned nodes.
For this reason, the benchmark measures the observable behavior of both implementations rather than attempting to isolate only the spatial traversal algorithm.

The result of each Morton query is independently compared against a brute-force radius test performed outside the timed region. The dynamic benchmark is isolated from the static benchmark.
Both Morton Grid and Quenty's Octree begin with fresh structures containing the same 64 moving objects, and both receive an identical precomputed trajectory.

## Studio / Luau VM

Two tests/runs were recorded in Studio. They are reported separately because the difference between them is part of what the benchmark is documenting.

| Metric | Morton Grid | Quenty Octree | Brute Force |
|---|---:|---:|---:|
| Static Objects | 40,000 | 40,000 | 40,000 |
| Search Iterations | 3,000 | 3,000 | 3,000 |
| Search Radius | 100 | 100 | 100 |
| Population Time | 0.031597 s | 0.171191 s | N/A |
| Population per Object | 0.7899 µs | 4.2798 µs | N/A |
| First Query | 0.017350 s | 0.000721 s | N/A |
| Population and First query | 0.048947 s | 0.171912 s | N/A |
| Query Time | 0.295200 s | 1.769696 s | 2.657622 s |
| Average Query | 98.4000 µs | 589.8986 µs | 885.8740 µs |
| Relative to Brute Force | 9.00x | 1.50x | 1.00x |
| Relative to Quenty | 5.99x | 1.00x | N/A |
| Average Results per Query | 646.45 | 646.45 | 646.45 |
| Total Results | 1,939,358 | 1,939,357 | 1,939,358 |
| Observed Heap Delta | 0 KB | 24,044 KB | N/A |
| Movement Time, 6,400 Updates | 0.000827 s | 0.002091 s | N/A |
| Average Movement | 0.1292 µs | 0.3267 µs | N/A |
| Relative Movement Time | 2.53x | 1.00x | N/A |

A second Studio run produced similar proportions but different absolute numbers.

| Metric | Morton Grid | Quenty Octree | Brute Force |
|---|---:|---:|---:|
| Population Time | 0.025925 s | 0.158313 s | N/A |
| Population per Object | 0.6481 µs | 3.9578 µs | N/A |
| First Query | 0.018818 s | 0.000537 s | N/A |
| Query Time | 0.298582 s | 1.807650 s | 2.686107 s |
| Average Query | 99.5275 µs | 602.5499 µs | 895.3689 µs |
| Relative to Brute Force | 9.00x | 1.49x | 1.00x |
| Relative to Quenty | 6.05x | 1.00x | N/A |
| Observed Heap Delta | 0 KB | 14,868 KB | N/A |
| Movement Time, 6,400 Updates | 0.000814 s | 0.002134 s | N/A |
| Average Movement | 0.1272 µs | 0.3335 µs | N/A |
| Relative Movement Time | 2.62x | 1.00x | N/A |

Morton Grid matched the brute-force reference for all 3,000 validated queries in both runs. Quenty's aggregate result count was just one result lower than the brute-force reference in both runs.
The benchmark did not independently validate each Quenty result, so the exact cause of this one-result difference was not investigated. I believe it may originate from a boundary case or some detail of the tested implementation.
Since the discrepancy is very small relative to the complete result set and the benchmark is primarily concerned with execution cost, it's reported as observed, rather than treated as a big problem.

## Server / Native Execution

| Metric | Morton Grid | Quenty Octree | Brute Force |
|---|---:|---:|---:|
| Static Objects | 40,000 | 40,000 | 40,000 |
| Search Iterations | 3,000 | 3,000 | 3,000 |
| Search Radius | 100 | 100 | 100 |
| Population Time | 0.013936 s | 0.130254 s | N/A |
| Population per Object | 0.3484 µs | 3.2563 µs | N/A |
| First Query | 0.015452 s | 0.000618 s | N/A |
| Population and First query | 0.029388 s | 0.130872 s | N/A |
| Query Time | 0.136035 s | 1.312458 s | 0.860017 s |
| Average Query | 45.3451 µs | 437.4861 µs | 286.6724 µs |
| Relative to Brute Force | 6.32x | 0.66x | 1.00x |
| Relative to Quenty | 9.65x | 1.00x | N/A |
| Average Results per Query | 646.45 | 646.45 | 646.45 |
| Total Results | 1,939,358 | 1,939,357 | 1,939,358 |
| Observed Heap Delta | 0 KB | 10,223 KB | N/A |
| Movement Time, 6,400 Updates | 0.000350 s | 0.001122 s | N/A |
| Average Movement | 0.0547 µs | 0.1753 µs | N/A |
| Relative Movement Time | 3.20x | 1.00x | N/A |

Again, Morton Grid matched the brute-force reference for every validated query. The same one-result difference in Quenty's aggregate count appeared in this run.

## Observations

The server execution produced a larger difference between the two implementations than the Studio execution. Morton Grid completed the query workload in approximately one tenth of Quenty's time on the server, while the Studio runs produced a difference of approximately six times.

Looking at the same structure across environments, Morton Grid became roughly 2.17x faster in the query loop on the server compared to Studio, Quenty's Octree improved by roughly 1.35x, and the brute-force loop improved by roughly 3.09x. This is consistent with the idea that the execution environment alters the relative weight of numerical loops, and it is reported here as an observation of this benchmark rather than as a general conclusion about native code generation.

Morton's first query showed much less variation between Studio and the server, shifting from 17.35 ms to 15.45 ms. This is expected given the module's architecture. The first query simply incurs the cost of deferred reconstruction, which includes sorting static arrays and rebuilding chunk boundaries. Therefore, in these measurements, this workload did not exhibit the same magnitude of improvement observed during the steady-state query cycle.

One result is worth stating plainly rather than omitting. On the server, brute force was faster than Quenty's Octree, `286.7 µs` against `437.5 µs` per query. In Studio, the opposite happened, and Quenty was significantly faster than brute force, `589.9 µs` against `885.9 µs`. Using a spatial structure does not automatically beat a linear loop when the loop is simple and sufficiently optimized.

It also makes Morton Grid's `9.65x` relative to Quenty more informative. Morton was still `6.32x` above brute force in the same server run, so the result is not only Quenty being slow in that environment.

The movement test shows a smaller difference than the static-query benchmark. Both structures can avoid rebuilding their complete spatial representation for every small movement. Morton Grid updates its spatial hash membership only when an object crosses a grid-cell boundary, while Quenty can retain a node in its current lowest region while the position remains inside that region.

The benchmark records the difference in `gcinfo()` before and after the steady-state query loop. This value is only an observed heap delta, not a measurement of total allocations, peak memory usage or garbage-collection work during the benchmark.

Morton Grid reported a zero-kilobyte heap delta in the recorded runs. Its radius-query API reuses a result table supplied by the caller rather than constructing a new result table for each query. I should mention that the observed zero delta should still not be interpreted as proof that no temporary allocation occurred, since `gcinfo()` only describes the observed heap state.

## Limitations

The dataset, query positions and the dynamic trajectories are deterministic and the same random seed is used in every recorded environment so that differences between runs are not caused by a different query distribution.
A thing to note is that this benchmark is not intended to be truly definitive. A spatial index can behave *very* differently depending on object distribution, execution environment or processor architecture.
The current workload was simply chosen to provide a reasonably large and reproducible case while attempting to preserve the normal behavior of both implementations.

There are also unavoidable differences between the two APIs. Morton Grid accepts a reusable result buffer, while Quenty's `RadiusSearch` constructs result arrays internally and also computes squared distances for the returned nodes.
The benchmark intentionally preserves these behaviors rather than modifying either implementation specifically for the test.

Alternative benchmark design proposals are very welcome. If another workload reveals behavior not adequately represented by this test, reproducing it and comparing the results would be more useful than treating the measurements presented in this document as absolute. The benchmark code was included to allow its assumptions to be examined, modified and perhaps challenged.
The results should, therefore, be expected to vary across processors, Roblox versions, object distributions and execution environments.
