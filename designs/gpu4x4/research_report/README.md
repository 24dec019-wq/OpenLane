# From RTL to GDSII: Open-source workflow study

The paper follows two RTL kernels through an OpenLane/Sky130A flow: a
fixed-point triangle rasterizer and a 4-by-4 signed INT8 matrix tile. It
records simulation, synthesis, physical-design, timing, power-estimation,
and GDSII outputs. Default-corner setup slack is positive, but separate
min/nom/max MCA reports show negative setup WNS; the runs do not establish
all-corner timing closure.
The separate `gpu_16bit/` configuration is not included: its saved run
failed lint because the configured RTL source files are missing.

The mathematical rasterizer model is Pineda's published edge-function
formulation ([SIGGRAPH 1988](https://doi.org/10.1145/54852.378457)); the
per-pixel recurrence is derived exactly from that determinant. The
high-level GPU architecture context is Owens et al.'s survey of
graphics-hardware computation ([Computer Graphics Forum, 2007](https://doi.org/10.1111/j.1467-8659.2007.01012.x)).
Neither citation implies a proprietary vendor implementation was copied.

## Rebuild report

From the OpenLane repository root:

```sh
./designs/gpu4x4/research_report/tools/reproduce.sh
```

Required tools: Icarus Verilog (`iverilog`, `vvp`), GTKWave, KLayout,
Python 3, Ghostscript's `ps2pdf`, and a LaTeX/BibTeX distribution. Set `IVERILOG`,
`IVERILOG_BASE`, and `VVP` if Icarus is not in the standard search path.

The script reruns the 136-triangle reference suite and four-case benchmark
for all three rasterizer implementations, the matrix-tile correctness
simulation, and the 90-by-90 tiled matrix benchmark.
Each reference-suite run also records per-case RTL cycles and exact input
coordinates; `tools/summarize_triangle_corpus.py` validates that all three
variants ran the same corpus and that every cycle count matches its exact
scan model. It creates `data/triangle_corpus_summary.csv`, with summaries
stratified by conservative bounding-box occupancy.
`tools/summarize_power_estimates.py` extracts typical-corner power values
from each saved final OpenLane STA report to `data/power_estimates.csv`. These
are vectorless estimates with no workload VCD/SAIF annotation. They do not
show workload power or energy.
It exports the triangle RTL trace using GTKWave, renders the saved final GDS
files for all three variants using KLayout, and compiles the PDF. It does
not rerun OpenLane. The matched physical rasterizer metrics and exact
source/configuration hashes are recorded in `data/physical_runs.csv`; saved
run directories are listed there.

The matrix benchmark drives the existing 4-by-4 tile through its
load/start/read interface. It multiplies signed INT8 90-by-90 matrices,
zero-pads to 92, and checks all 8,100 signed INT32 outputs against an
integer reference. Its total cycle count includes serial testbench writes
and tile control; it is not silicon throughput.

To reproduce the RTL-to-GDS runs, use OpenLane v1.0.2 with the recorded
Sky130A PDK revision and each matched configuration. Each distinct run
directory preserves its netlist, DEF, GDS, SPEF, timing reports, and flow
logs.

## Source evidence

- `report.tex`: workflow study, design contracts, RTL results, matched
  rasterizer comparison, matrix benchmark, physical metrics, and limitations.
- `data/rtl_benchmark.log`: measured Icarus scan cycles and coverage counts
  for the four fixed baseline workloads.
- `data/rtl_benchmark_incremental.log` and
  `data/rtl_benchmark_incremental_bbox.log`: corresponding results for I and
  IB.
- `data/triangle_regression_*.log`: self-checking suite results for each
  rasterizer implementation, including matching case IDs, coordinates, and
  completion-cycle counts.
- `data/triangle_corpus_summary.csv`: reproducible cycle summaries across
  the 136-case corpus, separated by nondegenerate bounding-box occupancy.
- `data/matmul_90x90.log`: measured Icarus cycles, tile counts, operation
  counts, and output-check result for the 90-by-90 workload.
- `data/physical_runs.csv`: run IDs, OpenLane/PDK versions, and source/config
  SHA-256 hashes for the three matched rasterizer physical runs.
- `data/power_estimates.csv`: typical-corner internal, switching, leakage,
  and total estimates from those runs, explicitly marked as having no activity
  annotation. Use the original STA reports in each run directory for full
  tool output.
- `../runs/RUN_2026.11.02_21.13.38/`: saved matrix-tile OpenLane run. The
  report's separate matrix table uses its `metrics.csv` and final signoff
  timing/power reports; these values are not part of the rasterizer CSV.
- `data/triangle_wave.vcd` and `data/triangle_wave.ps`: RTL simulation and
  GTKWave-native trace export; the report embeds a PDF conversion of the PS.
- `data/sim/triangle.ppm`: raw framebuffer output from the self-checking
  testbench.
- `figures/gpu_triangle_floorplan.png`,
  `figures/gpu_triangle_incremental_floorplan.png`,
  `figures/gpu_triangle_incremental_bbox_floorplan.png`, and
  `figures/gpu_triangle_layout_detail.png`: KLayout renders from the saved
  final routed GDS files for D/I/IB, including the detailed D routing view.
- `figures/gpu4x4_floorplan.png`: KLayout render of the saved 4-by-4 matrix
  tile GDS, shown separately from the rasterizer layout.

Area, timing, routing checks, and workload cycles are reported separately.
The power table contains vectorless OpenSTA estimates, not workload
measurements; activity-based power and energy remain unmeasured. The
standalone ngspice inverter simulation does not measure a kernel. The RTL
designs have not been captured as Xschem transistor-level schematics.
