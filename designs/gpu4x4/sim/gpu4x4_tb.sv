module gpu4x4_tb;
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

    integer a_values [0:15];
    integer b_values [0:15];
    integer expected [0:15];
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

    always #5 clk = ~clk;

    task automatic write_element(
        input reg matrix_select,
        input integer address,
        input integer value
    );
        begin
            @(negedge clk);
            write_en = 1'b1;
            write_matrix = matrix_select;
            write_addr = address[3:0];
            write_data = value[7:0];
            @(negedge clk);
            write_en = 1'b0;
        end
    endtask

    task automatic run_case(input integer case_number);
        integer r;
        integer c;
        integer q;
        integer timeout;
        begin
            for (r = 0; r < 4; r = r + 1) begin
                for (q = 0; q < 4; q = q + 1) begin
                    if (case_number == 0)
                        a_values[r * 4 + q] = (r * 3) + q - 5;
                    else if (((r + q) % 2) == 0)
                        a_values[r * 4 + q] = -128;
                    else
                        a_values[r * 4 + q] = 127;
                    write_element(1'b0, r * 4 + q, a_values[r * 4 + q]);
                end
            end

            for (q = 0; q < 4; q = q + 1) begin
                for (c = 0; c < 4; c = c + 1) begin
                    if (case_number == 0)
                        b_values[q * 4 + c] = (q * 2) - c + 1;
                    else if (((q + c) % 2) == 0)
                        b_values[q * 4 + c] = 127;
                    else
                        b_values[q * 4 + c] = -128;
                    write_element(1'b1, q * 4 + c, b_values[q * 4 + c]);
                end
            end

            for (r = 0; r < 4; r = r + 1) begin
                for (c = 0; c < 4; c = c + 1) begin
                    expected[r * 4 + c] = 0;
                    for (q = 0; q < 4; q = q + 1)
                        expected[r * 4 + c] =
                            expected[r * 4 + c]
                            + a_values[r * 4 + q] * b_values[q * 4 + c];
                end
            end

            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;

            timeout = 0;
            while (!done && timeout < 8) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (!done)
                $fatal(1, "Timed out waiting for matrix multiplication");
            if (busy)
                $fatal(1, "busy remained asserted when done was asserted");

            for (r = 0; r < 4; r = r + 1) begin
                for (c = 0; c < 4; c = c + 1) begin
                    read_addr = {r[1:0], c[1:0]};
                    #1;
                    if ($signed(result_data) != expected[r * 4 + c])
                        $fatal(1, "case %0d C[%0d,%0d]: expected %0d, got %0d",
                               case_number, r, c, expected[r * 4 + c],
                               $signed(result_data));
                end
            end
            $display("PASS: matrix case %0d", case_number);
        end
    endtask

    initial begin
        repeat (2) @(negedge clk);
        rst = 1'b0;
        run_case(0);
        run_case(1);
        $display("PASS: all 4x4 signed INT8 matrix tests");
        $finish;
    end
endmodule
