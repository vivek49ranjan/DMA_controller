module fifo_mem #(parameter D_size=8, parameter DEPTH=32, parameter A_size=5) (
    input wr_clk,
    input [A_size-1:0] wr_ptr, rd_ptr,
    input [D_size-1:0] write_data,
    input w_inc, full,
    output [D_size-1:0] read_data
);
    reg [D_size-1:0] memory [0:DEPTH-1];

    always @(posedge wr_clk) begin
        if (w_inc && !full)
            memory[wr_ptr] <= write_data;
    end

    assign read_data = memory[rd_ptr];
endmodule