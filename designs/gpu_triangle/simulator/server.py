#!/usr/bin/env python3
"""Local web UI that runs the triangle rasterizer RTL with Icarus Verilog."""

import json
import os
import re
import shlex
import subprocess
import tempfile
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


HERE = Path(__file__).resolve().parent
DESIGN = HERE.parent
MATRIX_DESIGN = DESIGN.parent / "gpu4x4"
TESTBENCH = DESIGN / "sim/gpu_triangle_ui_tb.sv"
BENCH_TESTBENCH = DESIGN / "sim/gpu_triangle_bench_tb.sv"
MATRIX_TESTBENCH = MATRIX_DESIGN / "sim/gpu4x4_90x90_bench_tb.sv"
MATRIX_RTL = MATRIX_DESIGN / "src/gpu4x4.v"
HTML = HERE / "index.html"
COORDINATES = ("x0", "y0", "x1", "y1", "x2", "y2")
VARIANTS = {
    "direct": {
        "label": "D — direct edge evaluation",
        "rtl": DESIGN / "src/gpu_triangle.v",
    },
    "incremental": {
        "label": "I — incremental full-frame scan",
        "rtl": DESIGN / "src/gpu_triangle_incremental.v",
    },
    "incremental_bbox": {
        "label": "IB — incremental clipped scan",
        "rtl": DESIGN / "src/gpu_triangle_incremental_bbox.v",
    },
}
ROW_PATTERN = re.compile(r"^ROW\s+(\d+)\s+([0-9a-fA-F]{4})$")
STATS_PATTERN = re.compile(r"^STATS\s+(\d+)\s+(\d+)$")
BENCH_PATTERN = re.compile(r"^BENCH\s+([a-z_]+)\s+(\d+)\s+(\d+)$")
MATRIX_PATTERNS = {
    "size": re.compile(r"^MATMUL size=(\d+)x(\d+) precision=(\S+)$"),
    "tiles": re.compile(r"^MATMUL tile_jobs=(\d+) padded_dimension=(\d+)$"),
    "macs": re.compile(r"^MATMUL useful_macs=(\d+) padded_tile_macs=(\d+)$"),
    "cycles": re.compile(r"^MATMUL rtl_cycles=(\d+) compute_busy_cycles=(\d+)$"),
    "outputs": re.compile(r"^MATMUL checked_outputs=(\d+)$"),
    "pass": re.compile(r"^PASS: exact 90x90 signed INT8 tiled multiplication$"),
}
BENCH_NAMES = (
    "full_viewport",
    "default_triangle",
    "small_triangle",
    "degenerate",
)


def command_from_env(name, fallback):
    return shlex.split(os.environ.get(name, fallback))


class RTLRunner:
    def __init__(self):
        self.tempdir = tempfile.TemporaryDirectory(prefix="gpu-triangle-ui-")
        self.executables = {}
        self.bench_executables = {}
        self.matrix_executable = Path(self.tempdir.name) / "gpu4x4_90x90_bench"
        compiler = command_from_env("IVERILOG", "iverilog")
        base_compiler = compiler
        base_args = ["-g2012", "-Wall"]
        base = os.environ.get("IVERILOG_BASE")
        if base:
            base_args.extend(["-B", base])
        for variant, config in VARIANTS.items():
            executable = Path(self.tempdir.name) / f"gpu_triangle_{variant}"
            bench_executable = Path(self.tempdir.name) / f"gpu_triangle_bench_{variant}"
            self.compile(
                base_compiler, base_args, "gpu_triangle_ui_tb", TESTBENCH,
                config["rtl"], executable
            )
            self.compile(
                base_compiler, base_args, "gpu_triangle_bench_tb",
                BENCH_TESTBENCH, config["rtl"], bench_executable
            )
            self.executables[variant] = executable
            self.bench_executables[variant] = bench_executable
        self.compile(
            base_compiler,
            base_args,
            "gpu4x4_90x90_bench_tb",
            MATRIX_TESTBENCH,
            MATRIX_RTL,
            self.matrix_executable,
        )
        self.vvp = command_from_env("VVP", "vvp")

    @staticmethod
    def compile(compiler, base_args, top, testbench, rtl, output):
        command = [
            *compiler,
            *base_args,
            "-s",
            top,
            "-o",
            str(output),
            str(testbench),
            str(rtl),
        ]
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
        if result.returncode != 0:
            raise RuntimeError(
                "Could not compile the RTL simulation testbench:\n"
                + result.stdout
                + result.stderr
            )

    def render(self, coordinates, variant="direct"):
        if variant not in self.executables:
            raise ValueError(f"Unknown rasterizer implementation: {variant}")
        args = [str(self.executables[variant])]
        for name in COORDINATES:
            args.append(f"+{name}={coordinates[name]}")
        result = subprocess.run(
            [*self.vvp, *args],
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
        )
        if result.returncode != 0:
            raise RuntimeError(
                "RTL simulation failed:\n" + result.stdout + result.stderr
            )

        rows = [None] * 16
        stats = None
        for line in result.stdout.splitlines():
            row_match = ROW_PATTERN.match(line.strip())
            stats_match = STATS_PATTERN.match(line.strip())
            if row_match:
                row_index = int(row_match.group(1))
                row_bits = int(row_match.group(2), 16)
                if row_index > 15 or rows[row_index] is not None:
                    raise RuntimeError("RTL simulator returned invalid row data")
                rows[row_index] = [
                    bool((row_bits >> column) & 1) for column in range(16)
                ]
            elif stats_match:
                stats = {
                    "scanCycles": int(stats_match.group(1)),
                    "coveredPixels": int(stats_match.group(2)),
                }

        if any(row is None for row in rows) or stats is None:
            raise RuntimeError(
                "RTL simulator output was incomplete:\n" + result.stdout
            )
        return {"rows": rows, **stats, "architecture": variant}

    def benchmark(self):
        started = time.perf_counter()
        variants = {}
        for variant, executable in self.bench_executables.items():
            result = subprocess.run(
                [*self.vvp, str(executable)],
                capture_output=True,
                text=True,
                timeout=30,
                check=False,
            )
            if result.returncode != 0:
                raise RuntimeError(
                    f"{variant} RTL benchmark failed:\n"
                    + result.stdout + result.stderr
                )
            cases = {}
            for line in result.stdout.splitlines():
                match = BENCH_PATTERN.match(line.strip())
                if match:
                    name, cycles, covered = match.groups()
                    if name in cases:
                        raise RuntimeError(
                            f"{variant} benchmark repeated case {name}"
                        )
                    cases[name] = {
                        "scanCycles": int(cycles),
                        "coveredPixels": int(covered),
                        "pixelTests": int(cycles),
                    }
            if tuple(cases) != BENCH_NAMES:
                raise RuntimeError(
                    f"{variant} RTL benchmark returned unexpected cases:\n"
                    + result.stdout
                )
            variants[variant] = {
                "label": VARIANTS[variant]["label"],
                "cases": cases,
            }
        wall_ms = (time.perf_counter() - started) * 1000
        return {
            "clockPeriodNs": 20,
            "targetClockMHz": 50,
            "hostSimulatorWallMs": round(wall_ms, 3),
            "variants": variants,
            "cases": variants["direct"]["cases"],
        }

    def benchmark_matrix(self):
        started = time.perf_counter()
        result = subprocess.run(
            [*self.vvp, str(self.matrix_executable)],
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )
        wall_ms = (time.perf_counter() - started) * 1000
        if result.returncode != 0:
            raise RuntimeError(
                "90-by-90 matrix RTL benchmark failed:\n"
                + result.stdout + result.stderr
            )
        metrics = {}
        passed = False
        for line in result.stdout.splitlines():
            for name, pattern in MATRIX_PATTERNS.items():
                match = pattern.match(line.strip())
                if not match:
                    continue
                if name == "pass":
                    passed = True
                else:
                    if name in metrics:
                        raise RuntimeError(
                            f"Matrix benchmark repeated metric {name}"
                        )
                    metrics[name] = match.groups()
        if set(metrics) != {"size", "tiles", "macs", "cycles", "outputs"} or not passed:
            raise RuntimeError(
                "90-by-90 matrix benchmark output was incomplete:\n"
                + result.stdout
            )
        rows, columns, precision = metrics["size"]
        tile_jobs, padded_dimension = metrics["tiles"]
        useful_macs, padded_macs = metrics["macs"]
        rtl_cycles, compute_cycles = metrics["cycles"]
        output_count, = metrics["outputs"]
        return {
            "rows": int(rows),
            "columns": int(columns),
            "precision": precision,
            "tileJobs": int(tile_jobs),
            "paddedDimension": int(padded_dimension),
            "usefulMacs": int(useful_macs),
            "paddedTileMacs": int(padded_macs),
            "rtlCycles": int(rtl_cycles),
            "computeBusyCycles": int(compute_cycles),
            "checkedOutputs": int(output_count),
            "hostSimulatorWallMs": round(wall_ms, 3),
        }


class SimulatorHandler(BaseHTTPRequestHandler):
    runner = None

    def log_message(self, fmt, *args):
        print(f"{self.address_string()} - {fmt % args}")

    def send_json(self, status, value):
        body = json.dumps(value).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/api/health":
            self.send_json(200, {
                "ok": True,
                "backend": "Icarus Verilog",
                "rasterizerVariants": list(VARIANTS),
            })
            return
        if self.path not in ("/", "/index.html"):
            self.send_error(404)
            return
        body = HTML.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path == "/api/benchmark":
            try:
                output = self.runner.benchmark()
            except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
                self.send_json(500, {"error": str(error)})
                return
            self.send_json(200, output)
            return
        if self.path == "/api/matmul":
            try:
                output = self.runner.benchmark_matrix()
            except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
                self.send_json(500, {"error": str(error)})
                return
            self.send_json(200, output)
            return
        if self.path != "/api/render":
            self.send_error(404)
            return
        try:
            size = int(self.headers.get("Content-Length", "0"))
            if size < 1 or size > 4096:
                self.send_json(400, {"error": "Request must be 1–4096 bytes."})
                return
            request = json.loads(self.rfile.read(size))
            if not isinstance(request, dict):
                raise ValueError("JSON request must be an object.")
            architecture = request.get("architecture", "direct")
            if not isinstance(architecture, str) or architecture not in VARIANTS:
                raise ValueError(
                    f"architecture must be one of: {', '.join(VARIANTS)}"
                )
            coordinates = {}
            for name in COORDINATES:
                value = request.get(name)
                if isinstance(value, bool) or not isinstance(value, int):
                    raise ValueError(f"{name} must be an integer in sixteenths.")
                if value < -256 or value > 255:
                    raise ValueError(f"{name} must be from -256 through 255.")
                coordinates[name] = value
        except (json.JSONDecodeError, ValueError) as error:
            self.send_json(422, {"error": str(error)})
            return

        try:
            output = self.runner.render(coordinates, architecture)
        except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
            self.send_json(500, {"error": str(error)})
            return
        output["coordinates"] = coordinates
        self.send_json(200, output)


def main():
    runner = RTLRunner()
    SimulatorHandler.runner = runner
    address = os.environ.get("HOST", "127.0.0.1")
    port = int(os.environ.get("PORT", "8000"))
    server = ThreadingHTTPServer((address, port), SimulatorHandler)
    print("Triangle RTL mini-simulator")
    print("Backend: Icarus Verilog executing all rasterizer variants")
    print(f"Open http://{address}:{port}/")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping simulator.")
    finally:
        server.server_close()
        runner.tempdir.cleanup()


if __name__ == "__main__":
    main()
