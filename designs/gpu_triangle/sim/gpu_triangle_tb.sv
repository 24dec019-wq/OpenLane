module gpu_triangle_tb;
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
    integer x;
    integer y;
    integer covered;
    integer checked_count;
    integer case_number;
    integer rendered_triangles;
    integer timeout;
    integer reference_x0;
    integer reference_y0;
    integer reference_x1;
    integer reference_y1;
    integer reference_x2;
    integer reference_y2;

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

    function automatic integer reference_edge(
        input integer ax,
        input integer ay,
        input integer bx,
        input integer by,
        input integer px,
        input integer py
    );
        begin
            reference_edge = ((bx - ax) * (py - ay))
                           - ((by - ay) * (px - ax));
        end
    endfunction

    task automatic render_triangle(input integer change_inputs_while_busy);
        begin
            reference_x0 = x0;
            reference_y0 = y0;
            reference_x1 = x1;
            reference_y1 = y1;
            reference_x2 = x2;
            reference_y2 = y2;

            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            if (change_inputs_while_busy != 0) begin
                x0 = 9'sd0;
                y0 = 9'sd0;
                x1 = 9'sd0;
                y1 = 9'sd0;
                x2 = 9'sd0;
                y2 = 9'sd0;
            end

            timeout = 0;
            while (!done && timeout < 300) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (!done)
                $fatal(1, "Timed out waiting for the triangle rasterizer");
            if (busy)
                $fatal(1, "busy remained asserted when done was asserted");
            $display(
                "CORPUS_CASE %0d %0d %0d %0d %0d %0d %0d %0d",
                rendered_triangles,
                timeout,
                reference_x0,
                reference_y0,
                reference_x1,
                reference_y1,
                reference_x2,
                reference_y2
            );
            rendered_triangles = rendered_triangles + 1;
        end
    endtask

    task automatic check_frame(
        input integer test_number,
        input integer write_image,
        output integer pixel_count
    );
        integer area_ref;
        integer edge0_ref;
        integer edge1_ref;
        integer edge2_ref;
        integer expected;
        integer image_file;
        begin
            area_ref = reference_edge(
                reference_x0, reference_y0, reference_x1, reference_y1,
                reference_x2, reference_y2
            );
            pixel_count = 0;
            image_file = 0;
            if (write_image != 0) begin
                image_file = $fopen("sim/triangle.ppm", "w");
                if (image_file == 0)
                    $fatal(1, "Could not create sim/triangle.ppm");
                $fwrite(image_file, "P3\n16 16\n255\n");
            end

            for (y = 0; y < 16; y = y + 1) begin
                for (x = 0; x < 16; x = x + 1) begin
                    edge0_ref = reference_edge(
                        reference_x1, reference_y1, reference_x2, reference_y2,
                        (x * 16) + 8, (y * 16) + 8
                    );
                    edge1_ref = reference_edge(
                        reference_x2, reference_y2, reference_x0, reference_y0,
                        (x * 16) + 8, (y * 16) + 8
                    );
                    edge2_ref = reference_edge(
                        reference_x0, reference_y0, reference_x1, reference_y1,
                        (x * 16) + 8, (y * 16) + 8
                    );
                    expected = ((area_ref > 0) && (edge0_ref >= 0)
                                && (edge1_ref >= 0) && (edge2_ref >= 0))
                            || ((area_ref < 0) && (edge0_ref <= 0)
                                && (edge1_ref <= 0) && (edge2_ref <= 0));

                    read_addr = {y[3:0], x[3:0]};
                    #1;
                    if (pixel_inside !== (expected != 0))
                        $fatal(1,
                               "Triangle %0d mismatch at (%0d,%0d): expected %0d, got %0b",
                               test_number, x, y, expected, pixel_inside);

                    if (pixel_inside) begin
                        pixel_count = pixel_count + 1;
                        if (write_image != 0)
                            $fwrite(image_file, "255 80 20\n");
                    end else if (write_image != 0) begin
                        $fwrite(image_file, "12 18 32\n");
                    end
                end
            end

            if (write_image != 0)
                $fclose(image_file);
        end
    endtask

    initial begin
        rendered_triangles = 0;
        repeat (2) @(negedge clk);
        rst = 1'b0;

        // Four fractional bits: (2,2), (13,2), and (7.5,13).
        x0 = 9'sd32;
        y0 = 9'sd32;
        x1 = 9'sd208;
        y1 = 9'sd32;
        x2 = 9'sd120;
        y2 = 9'sd208;
        render_triangle(0);
        check_frame(0, 1, covered);
        if (covered != 61)
            $fatal(1, "Unexpected triangle coverage count: %0d", covered);

        // Reverse winding and compare all pixels, not just the coverage count.
        x0 = 9'sd208;
        y0 = 9'sd32;
        x1 = 9'sd32;
        y1 = 9'sd32;
        render_triangle(0);
        check_frame(1, 0, checked_count);
        if (checked_count != covered)
            $fatal(1, "Triangle winding changed coverage: %0d vs %0d",
                   covered, checked_count);

        // Degenerate triangles must produce an empty framebuffer.
        x0 = 9'sd0;
        y0 = 9'sd0;
        x1 = 9'sd16;
        y1 = 9'sd16;
        x2 = 9'sd32;
        y2 = 9'sd32;
        render_triangle(0);
        check_frame(2, 0, checked_count);
        if (checked_count != 0)
            $fatal(1, "Degenerate triangle covered %0d pixels", checked_count);

        // Edges pass through sample centers; equality is expected to be included.
        x0 = 9'sd8;
        y0 = 9'sd8;
        x1 = 9'sd120;
        y1 = 9'sd8;
        x2 = 9'sd8;
        y2 = 9'sd120;
        render_triangle(1);
        check_frame(3, 0, checked_count);

        // Exercise the endpoints of the signed 9-bit input range.
        x0 = -256;
        y0 = -256;
        x1 = 9'sd255;
        y1 = -256;
        x2 = -256;
        y2 = 9'sd255;
        render_triangle(0);
        check_frame(4, 0, checked_count);

        // Non-degenerate triangles wholly outside the viewport on each x side.
        x0 = 9'sd250;
        y0 = 9'sd32;
        x1 = 9'sd255;
        y1 = 9'sd32;
        x2 = 9'sd250;
        y2 = 9'sd208;
        render_triangle(0);
        check_frame(5, 0, checked_count);
        if (checked_count != 0)
            $fatal(1, "Right-offscreen triangle covered %0d pixels", checked_count);

        x0 = -256;
        y0 = 9'sd32;
        x1 = -240;
        y1 = 9'sd32;
        x2 = -256;
        y2 = 9'sd208;
        render_triangle(0);
        check_frame(6, 0, checked_count);
        if (checked_count != 0)
            $fatal(1, "Left-offscreen triangle covered %0d pixels", checked_count);

        // A triangle crossing the viewport boundary must clip conservatively.
        x0 = -16;
        y0 = 9'sd8;
        x1 = 9'sd24;
        y1 = 9'sd8;
        x2 = 9'sd8;
        y2 = 9'sd40;
        render_triangle(0);
        check_frame(7, 0, checked_count);

        // Deterministic coordinate sweep includes off-screen and negative vertices.
        for (case_number = 0; case_number < 128; case_number = case_number + 1) begin
            x0 = ((case_number * 37 + 13) % 512) - 256;
            y0 = ((case_number * 71 + 201) % 512) - 256;
            x1 = ((case_number * 113 + 97) % 512) - 256;
            y1 = ((case_number * 53 + 19) % 512) - 256;
            x2 = ((case_number * 167 + 311) % 512) - 256;
            y2 = ((case_number * 29 + 401) % 512) - 256;
            render_triangle(0);
            check_frame(case_number + 8, 0, checked_count);
        end

        $display("PASS: full-frame oracle checks, winding, degeneracy, edges, and signed coordinates");
        $display("Rendered %0d pixels to sim/triangle.ppm", covered);
        $display("Checked 136 triangles against the integer reference");
        $finish;
    end
endmodule
