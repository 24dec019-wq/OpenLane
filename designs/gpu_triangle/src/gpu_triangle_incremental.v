`timescale 1ns/1ps

module gpu_triangle (
    input wire clk,
    input wire rst,
    input wire start,
    input wire signed [8:0] x0,
    input wire signed [8:0] y0,
    input wire signed [8:0] x1,
    input wire signed [8:0] y1,
    input wire signed [8:0] x2,
    input wire signed [8:0] y2,
    input wire [7:0] read_addr,
    output reg pixel_inside,
    output reg busy,
    output reg done
);
    reg [255:0] framebuffer;
    reg [3:0] pixel_x;
    reg [3:0] pixel_y;
    reg signed [19:0] area;
    reg signed [19:0] edge0;
    reg signed [19:0] edge1;
    reg signed [19:0] edge2;
    reg signed [19:0] row_edge0;
    reg signed [19:0] row_edge1;
    reg signed [19:0] row_edge2;
    reg signed [19:0] step_x0;
    reg signed [19:0] step_x1;
    reg signed [19:0] step_x2;
    reg signed [19:0] step_y0;
    reg signed [19:0] step_y1;
    reg signed [19:0] step_y2;

    wire signed [9:0] vx0 = $signed({x0[8], x0});
    wire signed [9:0] vy0 = $signed({y0[8], y0});
    wire signed [9:0] vx1 = $signed({x1[8], x1});
    wire signed [9:0] vy1 = $signed({y1[8], y1});
    wire signed [9:0] vx2 = $signed({x2[8], x2});
    wire signed [9:0] vy2 = $signed({y2[8], y2});
    wire signed [19:0] input_area;
    wire signed [9:0] sample_x = {2'b00, pixel_x, 4'b1000};
    wire signed [9:0] sample_y = {2'b00, pixel_y, 4'b1000};

    function signed [19:0] orient;
        input signed [9:0] ax;
        input signed [9:0] ay;
        input signed [9:0] bx;
        input signed [9:0] by;
        input signed [9:0] px;
        input signed [9:0] py;
        reg signed [9:0] dx1;
        reg signed [9:0] dy1;
        reg signed [9:0] dx2;
        reg signed [9:0] dy2;
        begin
            dx1 = bx - ax;
            dy1 = by - ay;
            dx2 = px - ax;
            dy2 = py - ay;
            orient = (dx1 * dy2) - (dy1 * dx2);
        end
    endfunction

    function signed [19:0] x_increment;
        input signed [9:0] delta_y;
        reg signed [19:0] extended_delta;
        begin
            extended_delta = {{10{delta_y[9]}}, delta_y};
            x_increment = -(extended_delta <<< 4);
        end
    endfunction

    function signed [19:0] y_increment;
        input signed [9:0] delta_x;
        reg signed [19:0] extended_delta;
        begin
            extended_delta = {{10{delta_x[9]}}, delta_x};
            y_increment = extended_delta <<< 4;
        end
    endfunction

    assign input_area = orient(vx0, vy0, vx1, vy1, vx2, vy2);

    always @* begin
        pixel_inside = framebuffer[read_addr];
    end

    always @(posedge clk) begin
        if (rst) begin
            busy <= 1'b0;
            done <= 1'b0;
            pixel_x <= 4'd0;
            pixel_y <= 4'd0;
            area <= 20'sd0;
            edge0 <= 20'sd0;
            edge1 <= 20'sd0;
            edge2 <= 20'sd0;
            row_edge0 <= 20'sd0;
            row_edge1 <= 20'sd0;
            row_edge2 <= 20'sd0;
            step_x0 <= 20'sd0;
            step_x1 <= 20'sd0;
            step_x2 <= 20'sd0;
            step_y0 <= 20'sd0;
            step_y1 <= 20'sd0;
            step_y2 <= 20'sd0;
            framebuffer <= 256'b0;
        end else begin
            done <= 1'b0;

            if (start && !busy) begin
                framebuffer <= 256'b0;
                pixel_x <= 4'd0;
                pixel_y <= 4'd0;
                area <= input_area;
                edge0 <= orient(vx1, vy1, vx2, vy2, 10'sd8, 10'sd8);
                edge1 <= orient(vx2, vy2, vx0, vy0, 10'sd8, 10'sd8);
                edge2 <= orient(vx0, vy0, vx1, vy1, 10'sd8, 10'sd8);
                row_edge0 <= orient(vx1, vy1, vx2, vy2, 10'sd8, 10'sd8);
                row_edge1 <= orient(vx2, vy2, vx0, vy0, 10'sd8, 10'sd8);
                row_edge2 <= orient(vx0, vy0, vx1, vy1, 10'sd8, 10'sd8);
                step_x0 <= x_increment(vy2 - vy1);
                step_x1 <= x_increment(vy0 - vy2);
                step_x2 <= x_increment(vy1 - vy0);
                step_y0 <= y_increment(vx2 - vx1);
                step_y1 <= y_increment(vx0 - vx2);
                step_y2 <= y_increment(vx1 - vx0);
                if (input_area == 20'sd0) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                end else begin
                    busy <= 1'b1;
                end
            end else if (busy) begin
                if (((area > 0) && (edge0 >= 0)
                     && (edge1 >= 0) && (edge2 >= 0))
                    || ((area < 0) && (edge0 <= 0)
                        && (edge1 <= 0) && (edge2 <= 0)))
                    framebuffer[{pixel_y, pixel_x}] <= 1'b1;

                if (pixel_x == 4'd15) begin
                    if (pixel_y == 4'd15) begin
                        busy <= 1'b0;
                        done <= 1'b1;
                    end else begin
                        pixel_x <= 4'd0;
                        pixel_y <= pixel_y + 1'b1;
                        edge0 <= row_edge0 + step_y0;
                        edge1 <= row_edge1 + step_y1;
                        edge2 <= row_edge2 + step_y2;
                        row_edge0 <= row_edge0 + step_y0;
                        row_edge1 <= row_edge1 + step_y1;
                        row_edge2 <= row_edge2 + step_y2;
                    end
                end else begin
                    pixel_x <= pixel_x + 1'b1;
                    edge0 <= edge0 + step_x0;
                    edge1 <= edge1 + step_x1;
                    edge2 <= edge2 + step_x2;
                end
            end
        end
    end
endmodule
