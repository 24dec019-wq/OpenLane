#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../../../" && pwd)
report_dir="$repo_root/designs/gpu4x4/research_report"
triangle_dir="$repo_root/designs/gpu_triangle"
matrix_dir="$repo_root/designs/gpu4x4"
triangle_tb="$triangle_dir/sim/gpu_triangle_tb.sv"
benchmark_tb="$triangle_dir/sim/gpu_triangle_bench_tb.sv"
wave_tb="$triangle_dir/sim/gpu_triangle_wave_tb.sv"
matrix_tb="$matrix_dir/sim/gpu4x4_tb.sv"
matrix_benchmark_tb="$matrix_dir/sim/gpu4x4_90x90_bench_tb.sv"
matrix_rtl="$matrix_dir/src/gpu4x4.v"
data_dir="$report_dir/data"
figures_dir="$report_dir/figures"
triangle_run="$triangle_dir/runs/RUN_2026.11.02_21.37.32"
incremental_run="$repo_root/designs/gpu_triangle_incremental/runs/RUN_2026.11.02_23.06.43"
incremental_bbox_run="$repo_root/designs/gpu_triangle_incremental_bbox/runs/RUN_2026.11.02_23.16.24"
matrix_run="$matrix_dir/runs/RUN_2026.11.02_21.13.38"
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/gpu-rasterizer-report.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM

mkdir -p "$data_dir/sim" "$figures_dir"
iverilog=${IVERILOG:-iverilog}
vvp=${VVP:-vvp}

compile_testbench() {
  top=$1
  testbench=$2
  output=$3
  rtl=$4
  if [ -n "${IVERILOG_BASE:-}" ]; then
    "$iverilog" -B "$IVERILOG_BASE" -g2012 -Wall -s "$top" \
      -o "$output" "$testbench" "$rtl"
  else
    "$iverilog" -g2012 -Wall -s "$top" \
      -o "$output" "$testbench" "$rtl"
  fi
}

for arm in direct incremental incremental_bbox; do
  case "$arm" in
    direct) arm_rtl="$triangle_dir/src/gpu_triangle.v" ;;
    incremental) arm_rtl="$triangle_dir/src/gpu_triangle_incremental.v" ;;
    incremental_bbox)
      arm_rtl="$triangle_dir/src/gpu_triangle_incremental_bbox.v"
      ;;
  esac
  compile_testbench gpu_triangle_tb "$triangle_tb" \
    "$build_dir/${arm}_tb" "$arm_rtl"
  compile_testbench gpu_triangle_bench_tb "$benchmark_tb" \
    "$build_dir/${arm}_bench" "$arm_rtl"
  if [ "$arm" = direct ]; then
    run_dir="$data_dir"
    bench_log="$data_dir/rtl_benchmark.log"
  else
    run_dir="$build_dir/$arm"
    mkdir -p "$run_dir/sim"
    bench_log="$data_dir/rtl_benchmark_${arm}.log"
  fi
  (cd "$run_dir" && "$vvp" "$build_dir/${arm}_tb") \
    > "$data_dir/triangle_regression_${arm}.log"
  (cd "$run_dir" && "$vvp" "$build_dir/${arm}_bench") > "$bench_log"
  cat "$data_dir/triangle_regression_${arm}.log"
  cat "$bench_log"
done

python3 "$report_dir/tools/summarize_triangle_corpus.py" \
  "$data_dir" "$data_dir/triangle_corpus_summary.csv"
python3 "$report_dir/tools/summarize_power_estimates.py"

if [ -n "${IVERILOG_BASE:-}" ]; then
  "$iverilog" -B "$IVERILOG_BASE" -g2012 -Wall -s gpu4x4_tb \
    -o "$build_dir/gpu4x4_tb" "$matrix_tb" "$matrix_rtl"
  "$iverilog" -B "$IVERILOG_BASE" -g2012 -Wall \
    -s gpu4x4_90x90_bench_tb -o "$build_dir/gpu4x4_90x90_bench" \
    "$matrix_benchmark_tb" "$matrix_rtl"
else
  "$iverilog" -g2012 -Wall -s gpu4x4_tb -o "$build_dir/gpu4x4_tb" \
    "$matrix_tb" "$matrix_rtl"
  "$iverilog" -g2012 -Wall -s gpu4x4_90x90_bench_tb \
    -o "$build_dir/gpu4x4_90x90_bench" "$matrix_benchmark_tb" "$matrix_rtl"
fi
"$vvp" "$build_dir/gpu4x4_tb"
"$vvp" "$build_dir/gpu4x4_90x90_bench" \
  > "$data_dir/matmul_90x90.log"
cat "$data_dir/matmul_90x90.log"

compile_testbench gpu_triangle_wave_tb "$wave_tb" \
  "$build_dir/gpu_triangle_wave_tb" "$triangle_dir/src/gpu_triangle.v"
(cd "$data_dir" && "$vvp" "$build_dir/gpu_triangle_wave_tb")
(cd "$data_dir" && gtkwave -T "$report_dir/tools/gtkwave_report.tcl" \
  triangle_wave.vcd)
ps2pdf "$data_dir/triangle_wave.ps" "$data_dir/triangle_wave.pdf"

GPU_LAYOUT_GDS="$triangle_run/results/final/gds/gpu_triangle.gds" \
GPU_LAYOUT_PNG="$figures_dir/gpu_triangle_floorplan.png" \
GPU_LAYOUT_LYP="$triangle_run/results/signoff/gpu_triangle.lyp" \
GPU_VISIBLE_METALS=1 \
  klayout -b -r "$report_dir/tools/render_layout.rb"
GPU_LAYOUT_GDS="$triangle_run/results/final/gds/gpu_triangle.gds" \
GPU_LAYOUT_PNG="$figures_dir/gpu_triangle_layout_detail.png" \
GPU_LAYOUT_LYP="$triangle_run/results/signoff/gpu_triangle.lyp" \
GPU_VISIBLE_METALS=345 \
GPU_LAYOUT_BOX=230,230,255,255 \
  klayout -b -r "$report_dir/tools/render_layout.rb"
GPU_LAYOUT_GDS="$incremental_run/results/final/gds/gpu_triangle.gds" \
GPU_LAYOUT_PNG="$figures_dir/gpu_triangle_incremental_floorplan.png" \
GPU_LAYOUT_LYP="$incremental_run/results/signoff/gpu_triangle.lyp" \
GPU_VISIBLE_METALS=1 \
  klayout -b -r "$report_dir/tools/render_layout.rb"
GPU_LAYOUT_GDS="$incremental_bbox_run/results/final/gds/gpu_triangle.gds" \
GPU_LAYOUT_PNG="$figures_dir/gpu_triangle_incremental_bbox_floorplan.png" \
GPU_LAYOUT_LYP="$incremental_bbox_run/results/signoff/gpu_triangle.lyp" \
GPU_VISIBLE_METALS=1 \
  klayout -b -r "$report_dir/tools/render_layout.rb"
GPU_LAYOUT_GDS="$matrix_run/results/final/gds/gpu4x4.gds" \
GPU_LAYOUT_PNG="$figures_dir/gpu4x4_floorplan.png" \
GPU_LAYOUT_LYP="$matrix_run/results/signoff/gpu4x4.lyp" \
GPU_VISIBLE_METALS=1 \
  klayout -b -r "$report_dir/tools/render_layout.rb"

cd "$report_dir"
pdflatex -halt-on-error -interaction=nonstopmode report.tex
bibtex report
pdflatex -halt-on-error -interaction=nonstopmode report.tex
pdflatex -halt-on-error -interaction=nonstopmode report.tex

printf '\nReport created: %s/report.pdf\n' "$report_dir"
