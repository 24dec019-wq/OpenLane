`timescale 1ns/1ps

module gpu4x4_90x90_bench_tb;
    localparam integer MATRIX_SIZE = 90;
    localparam integer TILE_SIZE = 4;
    localparam integer TILE_COUNT = (MATRIX_SIZE + TILE_SIZE - 1) / TILE_SIZE;
    localparam integer ELEMENT_COUNT = MATRIX_SIZE * MATRIX_SIZE;

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg write_en = 1'b0;
    reg write_matrix = 1'b0;
    reg [3:0] write_addr = 4'd0;
    reg signed [7:0] write_data = 8'sd0;
    reg start = 1'b0;
    reg [3:0] read_addr = 4'd0;
    wire signed [31:0] result_data;
    wire busy;
    wire done;

    integer a_values [0:ELEMENT_COUNT-1];
    integer b_values [0:ELEMENT_COUNT-1];
    integer c_values [0:ELEMENT_COUNT-1];
    integer row_tile;
    integer col_tile;
    integer inner_tile;
    integer row;
    integer col;
    integer inner;
    integer index;
    integer timeout;
    integer total_cycles = 0;
    integer compute_cycles = 0;
    integer tile_jobs = 0;
    integer active = 0;
    integer expected;
    integer checked = 0;

    gpu4x4 dut (
        .clk(clk),
        .rst(rst),
        .write_en(write_en),
        .write_matrix(write_matrix),
        .write_addr(write_addr),
        .write_data(write_data),
        .start(start),
        .read_addr(read_addr),
        .result_data(result_data),
        .busy(busy),
        .done(done)
    );

    always #10 clk = ~clk;

    always @(posedge clk) begin
        if (active)
            total_cycles = total_cycles + 1;
        if (active && busy)
            compute_cycles = compute_cycles + 1;
    end

    task automatic write_element(
        input reg matrix_select,
        input integer address,
        input integer value
    );
        begin
            write_en = 1'b1;
            write_matrix = matrix_select;
            write_addr = address[3:0];
            write_data = value[7:0];
            @(negedge clk);
        end
    endtask

    task automatic run_tile;
        integer wait_cycles;
        integer output_index;
        integer output_row;
        integer output_col;
        begin
            write_en = 1'b0;
            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            wait_cycles = 0;
            while (!done && wait_cycles < 8) begin
                @(negedge clk);
                wait_cycles = wait_cycles + 1;
            end
            if (!done || busy)
                $fatal(1, "Timed out waiting for 4x4 tile job %0d", tile_jobs);

            for (output_row = 0; output_row < TILE_SIZE;
                 output_row = output_row + 1) begin
                for (output_col = 0; output_col < TILE_SIZE;
                     output_col = output_col + 1) begin
                    output_index = output_row * TILE_SIZE + output_col;
                    read_addr = output_index[3:0];
                    #1;
                    row = row_tile * TILE_SIZE + output_row;
                    col = col_tile * TILE_SIZE + output_col;
                    if (row < MATRIX_SIZE && col < MATRIX_SIZE)
                        c_values[row * MATRIX_SIZE + col] =
                            c_values[row * MATRIX_SIZE + col]
                            + $signed(result_data);
                end
            end
            tile_jobs = tile_jobs + 1;
        end
    endtask

    initial begin
        for (row = 0; row < MATRIX_SIZE; row = row + 1) begin
            for (inner = 0; inner < MATRIX_SIZE; inner = inner + 1) begin
                index = row * MATRIX_SIZE + inner;
                a_values[index] = ((row * 3 + inner * 5) % 256) - 128;
            end
        end
        for (inner = 0; inner < MATRIX_SIZE; inner = inner + 1) begin
            for (col = 0; col < MATRIX_SIZE; col = col + 1) begin
                index = inner * MATRIX_SIZE + col;
                b_values[index] = ((inner * 7 + col * 2) % 256) - 128;
            end
        end
        for (index = 0; index < ELEMENT_COUNT; index = index + 1)
            c_values[index] = 0;

        repeat (2) @(negedge clk);
        rst = 1'b0;
        active = 1;

        for (row_tile = 0; row_tile < TILE_COUNT;
             row_tile = row_tile + 1) begin
            for (col_tile = 0; col_tile < TILE_COUNT;
                 col_tile = col_tile + 1) begin
                for (inner_tile = 0; inner_tile < TILE_COUNT;
                     inner_tile = inner_tile + 1) begin
                    @(negedge clk);
                    for (row = 0; row < TILE_SIZE; row = row + 1) begin
                        for (inner = 0; inner < TILE_SIZE;
                             inner = inner + 1) begin
                            index = (row_tile * TILE_SIZE + row)
                                  * MATRIX_SIZE
                                  + inner_tile * TILE_SIZE + inner;
                            if (row_tile * TILE_SIZE + row < MATRIX_SIZE
                                && inner_tile * TILE_SIZE + inner
                                   < MATRIX_SIZE)
                                write_element(1'b0, row * TILE_SIZE + inner,
                                              a_values[index]);
                            else
                                write_element(1'b0, row * TILE_SIZE + inner, 0);
                        end
                    end

                    for (inner = 0; inner < TILE_SIZE; inner = inner + 1) begin
                        for (col = 0; col < TILE_SIZE; col = col + 1) begin
                            index = (inner_tile * TILE_SIZE + inner)
                                  * MATRIX_SIZE
                                  + col_tile * TILE_SIZE + col;
                            if (inner_tile * TILE_SIZE + inner < MATRIX_SIZE
                                && col_tile * TILE_SIZE + col < MATRIX_SIZE)
                                write_element(1'b1, inner * TILE_SIZE + col,
                                              b_values[index]);
                            else
                                write_element(1'b1, inner * TILE_SIZE + col, 0);
                        end
                    end
                    run_tile();
                end
            end
        end

        active = 0;
        for (row = 0; row < MATRIX_SIZE; row = row + 1) begin
            for (col = 0; col < MATRIX_SIZE; col = col + 1) begin
                expected = 0;
                for (inner = 0; inner < MATRIX_SIZE; inner = inner + 1)
                    expected = expected
                        + a_values[row * MATRIX_SIZE + inner]
                        * b_values[inner * MATRIX_SIZE + col];
                if (c_values[row * MATRIX_SIZE + col] != expected)
                    $fatal(1,
                           "C[%0d,%0d]: expected %0d, got %0d",
                           row, col, expected,
                           c_values[row * MATRIX_SIZE + col]);
                checked = checked + 1;
            end
        end

        $display("MATMUL size=%0dx%0d precision=signed_int8_accum_int32",
                 MATRIX_SIZE, MATRIX_SIZE);
        $display("MATMUL tile_jobs=%0d padded_dimension=%0d",
                 tile_jobs, TILE_COUNT * TILE_SIZE);
        $display("MATMUL useful_macs=%0d padded_tile_macs=%0d",
                 MATRIX_SIZE * MATRIX_SIZE * MATRIX_SIZE,
                 tile_jobs * TILE_SIZE * TILE_SIZE * TILE_SIZE);
        $display("MATMUL rtl_cycles=%0d compute_busy_cycles=%0d",
                 total_cycles, compute_cycles);
        $display("MATMUL checked_outputs=%0d", checked);
        if (tile_jobs != TILE_COUNT * TILE_COUNT * TILE_COUNT)
            $fatal(1, "Unexpected number of 4x4 tile jobs: %0d", tile_jobs);
        if (checked != ELEMENT_COUNT)
            $fatal(1, "Expected %0d outputs, checked %0d",
                   ELEMENT_COUNT, checked);
        $display("PASS: exact 90x90 signed INT8 tiled multiplication");
        $finish;
    end
endmodule
