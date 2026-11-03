# Triangle rasterizer demo

This project contains the rasterizer kernel. It writes triangle coverage to a
16x16 one-bit framebuffer using signed fixed-point edge equations. Vertex
coordinates are signed 9-bit values with four fractional bits; samples are
taken at pixel centers. Either winding is accepted, and edges are inclusive.
The direct design scans up to 256 pixels and exposes the framebuffer through
an 8-bit read address. It latches the vertices when `start` is accepted.

The self-checking Icarus Verilog testbench compares every framebuffer pixel
against an integer edge-function reference for 136 triangles. The cases
cover both windings, degenerate triangles, edge inclusion, signed-coordinate
limits, changed inputs during rendering, and a deterministic coordinate
sweep. The testbench also writes `sim/triangle.ppm` as an ASCII PPM image.
Run it from this directory:

```sh
iverilog -g2012 -Wall -s gpu_triangle_tb -o /tmp/gpu_triangle_tb \
  sim/gpu_triangle_tb.sv src/gpu_triangle.v
vvp /tmp/gpu_triangle_tb
```

## RTL microarchitectures

The same module interface and reference testbench are implemented by three
candidate RTL files:

| RTL source | Edge evaluation | Traversal |
|---|---|---|
| `src/gpu_triangle.v` | Direct edge functions per sample | Full 16-by-16 scan |
| `src/gpu_triangle_incremental.v` | Exact edge accumulators | Full 16-by-16 scan |
| `src/gpu_triangle_incremental_bbox.v` | Exact edge accumulators | Conservative pixel-center bounding box |

Compile the self-checking testbench separately with each source file (each
defines the same top-level module name):

```sh
for rtl in src/gpu_triangle.v \
  src/gpu_triangle_incremental.v \
  src/gpu_triangle_incremental_bbox.v; do
  iverilog -g2012 -Wall -s gpu_triangle_tb -o /tmp/gpu_triangle_tb \
    sim/gpu_triangle_tb.sv "$rtl" &&
    vvp /tmp/gpu_triangle_tb || exit 1
done
```

All three variants pass the same 136-triangle reference suite (34,816 pixel
checks each). For the full-frame, reference, small, and degenerate cases,
the direct/incremental/clipped cycle counts are 256/256/256, 256/256/121,
256/256/4, and 0/0/0. The report script also summarizes all 136 cases by
bounding-box occupancy. These are RTL simulation cycles. Each variant has a
matched OpenLane run; see
[`gpu4x4/research_report/README.md`](../gpu4x4/research_report/README.md)
for the metrics and corner-specific timing caveats.

## Interactive RTL mini-simulator

The local browser UI runs the selected `gpu_triangle` RTL through Icarus
Verilog and displays the framebuffer produced by the simulation. It can
also run the four triangle benchmarks across all three variants and the
90-by-90 matrix test using `gpu4x4.v`. The cycle counts come from RTL
simulation, not physical hardware.

With Icarus Verilog installed, start the local server from this design
directory:

```sh
python3 simulator/server.py
```

Open `http://127.0.0.1:8000/`, select a rasterizer variant, drag a vertex or
edit its signed sixteenths-of-a-pixel coordinates, then select
**Run RTL rasterizer**. The browser displays the
16-by-16 framebuffer returned by the Verilog simulation and reports the scan
cycle and coverage counts. Press Ctrl-C in the server terminal to stop it.

Use **Compare three RTL implementations** to run the full-viewport,
reference, small, and degenerate cases on each rasterizer. Use **Run RTL
matrix benchmark** for the tiled 90-by-90 signed INT8 case. Host simulator
runtime is also shown and depends on the machine.

Run the ASIC flow from the OpenLane container with
`./flow.tcl -design gpu_triangle`. The 20 ns clock is a flow constraint, not
a measured operating frequency. This small, single-buffered rasterizer is
not a display controller or a complete graphics processor.
