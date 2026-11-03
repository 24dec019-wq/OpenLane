# From RTL to GDSII: open-source workflow study

## Scope

This project contains two separate RTL kernels: a 16-by-16 fixed-point
triangle rasterizer and a 4-by-4 signed INT8 matrix tile. They perform
different tasks, so the study does not compare one against the other. The
90-by-90 matrix workload is driven by a testbench that reuses the 4-by-4
tile; it is not a 90-by-90 physical array. Neither design is a complete GPU.

The physical-design study compares three bit-exact rasterizer variants
through synthesis, placement, routing, and extraction. All three use matched
OpenLane/Sky130A settings. Clipping reduces scan cycles for small triangles,
but the saved runs show that it also costs area and worsens the reported
critical-path metric.

## Research claim and source lineage

Under the shared 16-by-16 coverage contract and matched Sky130A flow, exact
edge accumulation does not reduce scan cycles or mapped area. Adding
conservative pixel-center bounding-box traversal reduces scan cycles for
low-occupancy inputs, at the cost of more area and a longer flow
critical-path metric. This is an RTL-to-GDS case study; it does not propose
a new rasterization algorithm or measure a complete GPU.

The edge-function model follows Juan Pineda's parallel polygon
rasterization formulation, [“A Parallel Algorithm for Polygon
Rasterization”](https://doi.org/10.1145/54852.378457) (SIGGRAPH 1988).
Incremental edge values in this RTL are derived exactly from that
determinant. The broader architecture motivation—separating graphics
pipeline work from data-parallel compute—is discussed in Owens et al.,
[“A Survey of General-Purpose Computation on Graphics
Hardware”](https://doi.org/10.1111/j.1467-8659.2007.01012.x), *Computer
Graphics Forum*, 26(1), 80–113 (2007). The report does not reconstruct a commercial GPU. Pixel-center sampling
and inclusive edges are the project's test contract; the
[Direct3D 9 rasterization rules](https://learn.microsoft.com/en-us/windows/win32/direct3d9/rasterization-rules)
are cited as one documented example of API coverage conventions, not as the
implementation source.

## ASIC workload benchmarks

### Triangle coverage

- Signed 9-bit coordinates denote sixteenths of a pixel, range -256 to 255.
- Sample centers are `(16*x + 8, 16*y + 8)` over `x,y` in `[0,15]`.
- Edge function: `E_ab(p)=(b_x-a_x)(p_y-a_y)-(b_y-a_y)(p_x-a_x)`.
- Either winding is supported, edges are inclusive, and zero-area triangles
  are rejected. There is no top-left shared-edge tie-break.
- The same testbench checks all 256 output pixels for 136 triangles
  (34,816 checks per variant; 104,448 across D, I, and IB) against a
  wide-integer reference.
- Each timed case records its ID, six signed input coordinates, and RTL
  completion cycles. `gpu4x4/research_report/tools/summarize_triangle_corpus.py`
  verifies all three logs use identical cases and that measured cycles match
  the exact scan model, then emits means, medians, nearest-rank p95s, and
  bounding-box-occupancy cohorts to
  `gpu4x4/research_report/data/triangle_corpus_summary.csv`.
- Four fixed cases cover full viewport, reference, small, and degenerate
  triangles. Non-degenerate scans take 256 cycles; the degenerate input
  takes zero. The 20 ns OpenLane clock is a constraint, not a measured
  frequency.
- Benchmark D/I/IB cycle counts for the full-frame, reference, small, and
  degenerate inputs are respectively 256/256/256, 256/256/121, 256/256/4,
  and 0/0/0. These are RTL cycles from four fixed cases, not a workload-wide
  throughput distribution.
- Across the 135 nondegenerate cases in the oracle corpus, the clipped
  variant's mean/median/p95 scan counts are 69.97/49/195 cycles, versus
  256/256/256 cycles for D and I. The corpus is a deterministic verification
  sweep containing off-screen inputs, not a production workload sample.
- GTKWave trace export records one triangle render and verifies the input
  vertex snapshot while the engine is busy.
- For nondegenerate off-screen triangles, D/I still scan 256 samples; IB
  can finish with an empty clipped box and no pixel evaluations. Degenerate
  input finishes without a scan in all three implementations.

All runs use OpenLane v1.0.2, SkyWater Sky130A, `sky130_fd_sc_hd`, 35%
target core utilization, and a 20 ns target clock. D/I/IB respectively
map to 7,955/8,822/9,655 cells and 80,943.88/88,885.25/91,964.45
\(\mu m^2\) synthesis cell area. Final DEF die areas are
0.24728/0.27072/0.27981 \(mm^2\), and the flow's critical-path metrics are
9.57/9.93/14.07 ns. The default final \texttt{31-rcx} setup slacks are
6.84/6.59/2.46 ns, but separate min/nom/max MCA reports show negative setup
WNS for every arm: D \(-2.21/-2.51/-2.82\) ns, I
\(-2.20/-2.34/-2.50\) ns, and IB \(-10.04/-10.30/-10.56\) ns. Do not
interpret the positive single-corner reports as all-corner closure; the
constraint/corner discrepancy remains unresolved. All runs report zero
TritonRoute/Magic DRC violations, but have max-fanout and antenna warnings.
Exact run IDs and source/configuration SHA-256 values are in
`gpu4x4/research_report/data/physical_runs.csv`. These are open-PDK flow
results, not silicon measurements. The power values are vectorless estimates.

### 90-by-90 matrix multiplication

`gpu4x4/sim/gpu4x4_90x90_bench_tb.sv` drives the public interface of the
existing 4-by-4 matrix RTL. It computes `C=A*B` with signed INT8 inputs and
signed INT32 accumulation using these deterministic input functions:

```
A[i,k] = ((3*i + 5*k) mod 256) - 128
B[k,j] = ((7*k + 2*j) mod 256) - 128
```

For the 90-by-90 index domain, both generated operand matrices contain all
256 signed INT8 values.

The input dimension 90 is zero-padded to 92. The harness performs 23-by-23
output tiles across 23 K tiles (12,167 tile jobs), checks all 8,100 results
against an integer reference, and records:

| Metric | RTL result |
|---|---:|
| Useful MACs | 729,000 |
| Padded tile MACs | 778,688 |
| Total cycles including serial loads/control | 474,514 |
| Matrix engine busy cycles | 48,668 |
| Output checks | 8,100 passed |

Total cycles include this testbench's serial writes and tile-control
schedule. Busy cycles isolate the four-cycle matrix computation for each
tile; neither metric is a silicon timing result. The 90-by-90 workload has
not itself been run through OpenLane as a whole; the implemented silicon
block is the reusable 4-by-4 tile.

## Implemented rasterizer microarchitectures

All variants must preserve the same ports, one-bit framebuffer, start-time
input snapshot, coordinate format, sample centers, inclusive-edge rule, and
exact signed arithmetic.

| Arm | Architecture | Status |
|---|---|---|
| D | Direct edge evaluation over all 256 pixels | Implemented, simulation-checked, physically measured |
| I | Initialize three edge values and update by exact per-pixel increments; scan full frame | Implemented, simulation-checked, physically measured |
| IB | Incremental stepping with conservative clipping to pixel-center bounds | Implemented, simulation-checked, physically measured |

For edge `a -> b`, the exact recurrence is
`E(x+1,y)=E(x,y)-16*(b_y-a_y)` and
`E(x,y+1)=E(x,y)+16*(b_x-a_x)`. Signed 20-bit sample edge values cover the
conservative difference-of-products bound 515,088; triangle area is bounded
by 522,242. Candidate bounds require explicit signed floor/ceiling behavior.

The full-scan and bounded candidates pass the same 136-triangle, 34,816-pixel
per-variant reference suite as D, plus the same four benchmark workloads.
They have separate OpenLane configs in `gpu_triangle_incremental/` and
`gpu_triangle_incremental_bbox/`, each pointing at its candidate RTL while
matching the direct design's 20 ns clock and 35% utilization target. The
saved results show that I has 9.8% higher synthesis area than D without
reducing the four measured scan-cycle counts. IB reduces reference/small
scan cycles from 256 to 121/4, but has the highest area and critical-path
metric. These conclusions apply only to the current RTL, physical-flow
configuration, and test inputs. To run a fresh physical implementation
inside the same OpenLane v1.0.2 environment:

```sh
./flow.tcl -design gpu_triangle_incremental
./flow.tcl -design gpu_triangle_incremental_bbox
```

### Power in scope

The matched final OpenLane runs include typical-corner vectorless
OpenSTA power estimates. The report package extracts internal, switching,
leakage, and total values from the final STA reports into
`research_report/data/power_estimates.csv`. These estimates have no
workload-derived VCD/SAIF annotation and are not interpreted as candidate
workload power or energy; in particular, they are not used to rank the RTL
arms. The standalone ngspice inverter transient is a library-cell check,
not accelerator power evidence. The 4-by-4 matrix tile is outside this
rasterizer-only estimate table and has no workload power result; a separate
matrix study should normalize energy per useful MAC or per completed
90-by-90 product.

To measure workload energy, capture the same occupancy-stratified inputs for
each arm, annotate activity consistently on the final implementations, and
hold the library, voltage, corner, parasitics, and measurement window fixed.
Report internal, switching, and leakage separately, then integrate power
over each render. The matrix tile needs a separate study, reporting energy
per useful MAC or per completed 90-by-90 product. The ngspice inverter
transient is a cell-level check, not accelerator power evidence; the RTL
kernels have no Xschem transistor-level schematics.

## Reproduction

From the OpenLane repository root:

```sh
./designs/gpu4x4/research_report/tools/reproduce.sh
```

This reruns all three rasterizer correctness suites and benchmarks, the
matrix-tile correctness test and 90-by-90 workload, GTKWave waveform export,
KLayout rendering of all three saved rasterizer GDS files and the matrix
tile GDS, extraction of the saved vectorless power estimates, and LaTeX
compilation. It does not rerun OpenLane and
does not rerun the physical-design flow. The source bibliography and data
artifacts are in `gpu4x4/research_report/`.
