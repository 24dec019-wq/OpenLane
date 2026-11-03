module gpu4x4 (
    input wire clk,
    input wire rst,
    input wire write_en,
    input wire write_matrix,
    input wire [3:0] write_addr,
    input wire signed [7:0] write_data,
    input wire start,
    input wire [3:0] read_addr,
    output reg signed [31:0] result_data,
    output reg busy,
    output reg done
);
    reg signed [7:0] a_mem [0:15];
    reg signed [7:0] b_mem [0:15];
    reg signed [31:0] accum [0:15];
    reg [1:0] k;
    wire signed [15:0] product [0:15];
    integer i;

    genvar row;
    genvar col;
    generate
        for (row = 0; row < 4; row = row + 1) begin: gen_row
            for (col = 0; col < 4; col = col + 1) begin: gen_col
                localparam integer OUT_INDEX = row * 4 + col;
                wire signed [15:0] a_extended;
                wire signed [15:0] b_extended;
                assign a_extended = {{8{a_mem[row * 4 + k][7]}},
                                     a_mem[row * 4 + k]};
                assign b_extended = {{8{b_mem[k * 4 + col][7]}},
                                     b_mem[k * 4 + col]};
                assign product[OUT_INDEX] = a_extended * b_extended;
            end
        end
    endgenerate

    always @* begin
        result_data = accum[read_addr];
    end

    always @(posedge clk) begin
        if (rst) begin
            busy <= 1'b0;
            done <= 1'b0;
            k <= 2'b0;
            for (i = 0; i < 16; i = i + 1)
                accum[i] <= 32'sd0;
        end else begin
            done <= 1'b0;

            if (write_en && !busy) begin
                if (write_matrix)
                    b_mem[write_addr] <= write_data;
                else
                    a_mem[write_addr] <= write_data;
            end

            if (start && !busy) begin
                busy <= 1'b1;
                k <= 2'b0;
                for (i = 0; i < 16; i = i + 1)
                    accum[i] <= 32'sd0;
            end else if (busy) begin
                for (i = 0; i < 16; i = i + 1)
                    accum[i] <= accum[i] + {{16{product[i][15]}}, product[i]};

                if (k == 2'd3) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                end else begin
                    k <= k + 1'b1;
                end
            end
        end
    end
endmodule
