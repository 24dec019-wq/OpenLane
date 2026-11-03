`timescale 1ns/1ps

module gpu_triangle_bench_tb;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg start = 1'b0;
    reg signed [8:0] x0 = 9'sd0;
    reg signed [8:0] y0 = 9'sd0;
    reg signed [8:0] x1 = 9'sd0;
    reg signed [8:0] y1 = 9'sd0;
    reg signed [8:0] x2 = 9'sd0;
    reg signed [8:0] y2 = 9'sd0;
    reg [7:0] read_addr = 8'd0;
    wire pixel_inside;
    wire busy;
    wire done;
    integer scan_cycles;
    integer timeout;
    integer x;
    integer y;
    integer covered;

    gpu_triangle dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .x0(x0),
        .y0(y0),
        .x1(x1),
        .y1(y1),
        .x2(x2),
        .y2(y2),
        .read_addr(read_addr),
        .pixel_inside(pixel_inside),
        .busy(busy),
        .done(done)
    );

    always #10 clk = ~clk;

    task automatic benchmark_case(
        input [127:0] name,
        input integer ax,
        input integer ay,
        input integer bx,
        input integer by,
        input integer cx,
        input integer cy
    );
        begin
            x0 = ax;
            y0 = ay;
            x1 = bx;
            y1 = by;
            x2 = cx;
            y2 = cy;
            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;

            timeout = 0;
            while (!done && timeout < 300) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (!done || busy)
                $fatal(1, "Benchmark case did not complete");

            scan_cycles = timeout;
            covered = 0;
            for (y = 0; y < 16; y = y + 1) begin
                for (x = 0; x < 16; x = x + 1) begin
                    read_addr = {y[3:0], x[3:0]};
                    #1;
                    if (pixel_inside)
                        covered = covered + 1;
                end
            end
            $display("BENCH %0s %0d %0d", name, scan_cycles, covered);
            @(negedge clk);
        end
    endtask

    initial begin
        repeat (2) @(negedge clk);
        rst = 1'b0;

        benchmark_case(
            "full_viewport",
            9'sd255, 9'sd255,
            -9'sd256, 9'sd255,
            9'sd255, -9'sd256
        );
        benchmark_case(
            "default_triangle",
            9'sd32, 9'sd32,
            9'sd208, 9'sd32,
            9'sd120, 9'sd208
        );
        benchmark_case(
            "small_triangle",
            9'sd8, 9'sd8,
            9'sd24, 9'sd8,
            9'sd8, 9'sd24
        );
        benchmark_case(
            "degenerate",
            9'sd0, 9'sd0,
            9'sd16, 9'sd16,
            9'sd32, 9'sd32
        );
        $display("BENCH_DONE");
        $finish;
    end
endmodule
