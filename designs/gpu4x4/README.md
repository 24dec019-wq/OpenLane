# GPU-style ASIC kernels

This directory contains two small RTL designs:

- `gpu4x4`: a 4x4 signed INT8 matrix-multiply tile, with 16 parallel
  multiply-accumulate lanes.
- `../gpu_triangle`: a fixed-point edge-function triangle rasterizer that
  writes a 16x16 coverage framebuffer and produces a PPM image in simulation.

Both have OpenLane configurations for Sky130 HD. They are research kernels,
not a complete GPU. The 20 ns clock is a flow constraint, not a measured
operating frequency.

See [gpu_triangle](../gpu_triangle/README.md) for the rasterizer,
[RESEARCH.md](RESEARCH.md) for the model and results, and
[research_report](research_report/README.md) for the RTL-to-GDSII workflow
study and its source data.

## Project structure and status

- `src/` contains the matrix tile RTL; `sim/` contains arithmetic/control
  tests, the tiled 90-by-90 workload, and the standalone inverter ngspice
  deck.
- `../gpu_triangle/src/` contains direct, incremental, and clipped
  rasterizer RTL; `../gpu_triangle/sim/` contains their shared oracle
  regression, cycle benchmarks, and waveform testbench.
- `../gpu_triangle_incremental/` and `../gpu_triangle_incremental_bbox/`
  contain the matched OpenLane configurations and saved physical runs for
  the two rasterizer variants; the direct baseline run is under
  `../gpu_triangle/`.
- `research_report/` contains the LaTeX report, citations, reproducible
  scripts, simulation/physical summaries, and GTKWave/KLayout figures.

Completed work includes shared RTL correctness tests, a deterministic
90-by-90 matrix simulation, matched rasterizer RTL-to-GDS runs, and figures
rendered from the saved layouts. OpenLane's rasterizer power figures are
vectorless estimates: no workload VCD/SAIF was annotated, so activity-based
power and energy remain unmeasured. The matrix tile also has a typical-corner
vectorless estimate, but no activity-based workload power or energy result.
The ngspice test covers a standard-cell inverter, not either accelerator;
the designs have not been captured as Xschem transistor-level schematics.

## Matrix compute tile

The tile computes `C = A x B` for two 4x4 signed INT8 matrices. Its 16
multiply-accumulate lanes produce signed 32-bit results over four cycles.

Matrices are loaded through the `write_en`, `write_matrix`, `write_addr`, and
`write_data` interface. `write_matrix=0` selects A and `write_matrix=1`
selects B. Pulse `start` after loading both matrices, wait for the one-cycle
`done` pulse, then select each result with `read_addr`. Writes are ignored
while the engine is busy. The initial physical-design clock target is 20 ns
(50 MHz) for the Sky130 HD library; it is a constraint, not a measured
frequency guarantee.

### 90-by-90 RTL benchmark

`sim/gpu4x4_90x90_bench_tb.sv` composes the 4-by-4 tile to calculate a
90-by-90 signed INT8 matrix product with signed 32-bit accumulation. It uses
deterministic input formulas, zero-pads to 92, submits 12,167 tile jobs, and
checks all 8,100 outputs against an integer reference. Run it from this
directory with:

```sh
iverilog -g2012 -Wall -s gpu4x4_90x90_bench_tb \
  -o /tmp/gpu4x4_90x90_bench \
  sim/gpu4x4_90x90_bench_tb.sv src/gpu4x4.v
vvp /tmp/gpu4x4_90x90_bench
```

The total cycle count includes serial testbench writes and control overhead;
`compute_busy_cycles` counts only cycles when the matrix RTL is busy. Both
are simulation counts, not measured silicon performance.

## Run

From the OpenLane checkout, run `./flow.tcl -design gpu4x4` in the OpenLane
container to synthesize and harden the design for the configured Sky130 PDK.

Run the functional self-check with Icarus Verilog:

```sh
iverilog -g2012 -Wall -s gpu4x4_tb -o /tmp/gpu4x4_tb \
  sim/gpu4x4_tb.sv src/gpu4x4.v
vvp /tmp/gpu4x4_tb
```

Run the Sky130 transistor-level inverter transient check with ngspice from the
`sim` directory:

```sh
ngspice -b gpu4x4_cell.spice
```

The Icarus Verilog testbench checks the matrix engine's arithmetic and control
behavior. The ngspice deck simulates a loaded Sky130 HD inverter cell and
measures its rising and falling propagation delays; it is a library-cell
electrical check, not a transistor-level simulation of the complete matrix
engine.
