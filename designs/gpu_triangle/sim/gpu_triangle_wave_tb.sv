`timescale 1ns/1ps

module gpu_triangle_wave_tb;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg start = 1'b0;
    reg signed [8:0] x0 = 9'sd32;
    reg signed [8:0] y0 = 9'sd32;
    reg signed [8:0] x1 = 9'sd208;
    reg signed [8:0] y1 = 9'sd32;
    reg signed [8:0] x2 = 9'sd120;
    reg signed [8:0] y2 = 9'sd208;
    reg [7:0] read_addr = 8'd0;
    wire pixel_inside;
    wire busy;
    wire done;
    integer timeout;

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

    always #5 clk = ~clk;

    initial begin
        $dumpfile("triangle_wave.vcd");
        $dumpvars(0, gpu_triangle_wave_tb);
        repeat (2) @(negedge clk);
        rst = 1'b0;
        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        x0 = 9'sd0;
        y0 = 9'sd0;
        x1 = 9'sd0;
        y1 = 9'sd0;
        x2 = 9'sd0;
        y2 = 9'sd0;

        timeout = 0;
        while (!done && timeout < 300) begin
            @(negedge clk);
            timeout = timeout + 1;
        end
        if (!done)
            $fatal(1, "Timed out waiting for the rasterizer waveform");
        $display("PASS: captured a triangle render; input pins changed while busy");
        $finish;
    end
endmodule
