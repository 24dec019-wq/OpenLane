`timescale 1ns/1ps

module gpu_triangle_ui_tb;
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
    integer arg_x0;
    integer arg_y0;
    integer arg_x1;
    integer arg_y1;
    integer arg_x2;
    integer arg_y2;
    integer timeout;
    integer x;
    integer y;
    integer covered;
    reg [15:0] row_bits;

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

    initial begin
        if (!$value$plusargs("x0=%d", arg_x0)
            || !$value$plusargs("y0=%d", arg_y0)
            || !$value$plusargs("x1=%d", arg_x1)
            || !$value$plusargs("y1=%d", arg_y1)
            || !$value$plusargs("x2=%d", arg_x2)
            || !$value$plusargs("y2=%d", arg_y2))
            $fatal(1, "Expected six signed-coordinate plusargs");

        x0 = arg_x0;
        y0 = arg_y0;
        x1 = arg_x1;
        y1 = arg_y1;
        x2 = arg_x2;
        y2 = arg_y2;

        repeat (2) @(negedge clk);
        rst = 1'b0;
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
            $fatal(1, "The RTL rasterizer did not finish within 300 cycles");

        covered = 0;
        for (y = 0; y < 16; y = y + 1) begin
            row_bits = 16'b0;
            for (x = 0; x < 16; x = x + 1) begin
                read_addr = {y[3:0], x[3:0]};
                #1;
                row_bits[x] = pixel_inside;
                if (pixel_inside)
                    covered = covered + 1;
            end
            $display("ROW %0d %04x", y, row_bits);
        end
        $display("STATS %0d %0d", timeout, covered);
        $finish;
    end
endmodule
