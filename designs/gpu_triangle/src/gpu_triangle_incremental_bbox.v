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
    reg [3:0] min_x;
    reg [3:0] max_x;
    reg [3:0] min_y;
    reg [3:0] max_y;
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

    integer min_vertex_x;
    integer max_vertex_x;
    integer min_vertex_y;
    integer max_vertex_y;
    integer raw_min_x;
    integer raw_max_x;
    integer raw_min_y;
    integer raw_max_y;
    integer clipped_min_x;
    integer clipped_max_x;
    integer clipped_min_y;
    integer clipped_max_y;
    reg empty_bounds;

    wire signed [9:0] vx0 = $signed({x0[8], x0});
    wire signed [9:0] vy0 = $signed({y0[8], y0});
    wire signed [9:0] vx1 = $signed({x1[8], x1});
    wire signed [9:0] vy1 = $signed({y1[8], y1});
    wire signed [9:0] vx2 = $signed({x2[8], x2});
    wire signed [9:0] vy2 = $signed({y2[8], y2});
    wire signed [19:0] input_area;

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

    function integer floor_div16;
        input integer value;
        begin
            if (value >= 0)
                floor_div16 = value / 16;
            else
                floor_div16 = -(((-value) + 15) / 16);
        end
    endfunction

    function integer ceil_div16;
        input integer value;
        begin
            if (value >= 0)
                ceil_div16 = (value + 15) / 16;
            else
                ceil_div16 = -((-value) / 16);
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
        min_vertex_x = $signed(x0);
        max_vertex_x = $signed(x0);
        min_vertex_y = $signed(y0);
        max_vertex_y = $signed(y0);
        if ($signed(x1) < min_vertex_x) min_vertex_x = $signed(x1);
        if ($signed(x2) < min_vertex_x) min_vertex_x = $signed(x2);
        if ($signed(x1) > max_vertex_x) max_vertex_x = $signed(x1);
        if ($signed(x2) > max_vertex_x) max_vertex_x = $signed(x2);
        if ($signed(y1) < min_vertex_y) min_vertex_y = $signed(y1);
        if ($signed(y2) < min_vertex_y) min_vertex_y = $signed(y2);
        if ($signed(y1) > max_vertex_y) max_vertex_y = $signed(y1);
        if ($signed(y2) > max_vertex_y) max_vertex_y = $signed(y2);

        raw_min_x = ceil_div16(min_vertex_x - 8);
        raw_max_x = floor_div16(max_vertex_x - 8);
        raw_min_y = ceil_div16(min_vertex_y - 8);
        raw_max_y = floor_div16(max_vertex_y - 8);
        empty_bounds = (raw_min_x > raw_max_x)
                     || (raw_min_y > raw_max_y)
                     || (raw_max_x < 0) || (raw_max_y < 0)
                     || (raw_min_x > 15) || (raw_min_y > 15);

        clipped_min_x = raw_min_x;
        clipped_max_x = raw_max_x;
        clipped_min_y = raw_min_y;
        clipped_max_y = raw_max_y;
        if (clipped_min_x < 0) clipped_min_x = 0;
        if (clipped_min_x > 15) clipped_min_x = 15;
        if (clipped_max_x < 0) clipped_max_x = 0;
        if (clipped_max_x > 15) clipped_max_x = 15;
        if (clipped_min_y < 0) clipped_min_y = 0;
        if (clipped_min_y > 15) clipped_min_y = 15;
        if (clipped_max_y < 0) clipped_max_y = 0;
        if (clipped_max_y > 15) clipped_max_y = 15;
    end

    always @* begin
        pixel_inside = framebuffer[read_addr];
    end

    always @(posedge clk) begin
        if (rst) begin
            busy <= 1'b0;
            done <= 1'b0;
            pixel_x <= 4'd0;
            pixel_y <= 4'd0;
            min_x <= 4'd0;
            max_x <= 4'd0;
            min_y <= 4'd0;
            max_y <= 4'd0;
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
                area <= input_area;
                if (input_area == 20'sd0 || empty_bounds) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                end else begin
                    min_x <= clipped_min_x[3:0];
                    max_x <= clipped_max_x[3:0];
                    min_y <= clipped_min_y[3:0];
                    max_y <= clipped_max_y[3:0];
                    pixel_x <= clipped_min_x[3:0];
                    pixel_y <= clipped_min_y[3:0];
                    edge0 <= orient(vx1, vy1, vx2, vy2,
                                    clipped_min_x * 16 + 8,
                                    clipped_min_y * 16 + 8);
                    edge1 <= orient(vx2, vy2, vx0, vy0,
                                    clipped_min_x * 16 + 8,
                                    clipped_min_y * 16 + 8);
                    edge2 <= orient(vx0, vy0, vx1, vy1,
                                    clipped_min_x * 16 + 8,
                                    clipped_min_y * 16 + 8);
                    row_edge0 <= orient(vx1, vy1, vx2, vy2,
                                        clipped_min_x * 16 + 8,
                                        clipped_min_y * 16 + 8);
                    row_edge1 <= orient(vx2, vy2, vx0, vy0,
                                        clipped_min_x * 16 + 8,
                                        clipped_min_y * 16 + 8);
                    row_edge2 <= orient(vx0, vy0, vx1, vy1,
                                        clipped_min_x * 16 + 8,
                                        clipped_min_y * 16 + 8);
                    step_x0 <= x_increment(vy2 - vy1);
                    step_x1 <= x_increment(vy0 - vy2);
                    step_x2 <= x_increment(vy1 - vy0);
                    step_y0 <= y_increment(vx2 - vx1);
                    step_y1 <= y_increment(vx0 - vx2);
                    step_y2 <= y_increment(vx1 - vx0);
                    busy <= 1'b1;
                end
            end else if (busy) begin
                if (((area > 0) && (edge0 >= 0)
                     && (edge1 >= 0) && (edge2 >= 0))
                    || ((area < 0) && (edge0 <= 0)
                        && (edge1 <= 0) && (edge2 <= 0)))
                    framebuffer[{pixel_y, pixel_x}] <= 1'b1;

                if (pixel_x == max_x) begin
                    if (pixel_y == max_y) begin
                        busy <= 1'b0;
                        done <= 1'b1;
                    end else begin
                        pixel_x <= min_x;
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
