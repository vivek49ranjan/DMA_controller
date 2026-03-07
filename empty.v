module empty_indi #(parameter A_size=5) (
    input r_clk, r_reset, r_inc,
    input [A_size:0] wr_ptr_sync,
    output reg [A_size:0] rd_ptr_g,
    output reg [A_size:0] rd_ptr_bin,
    output reg empty
);
    wire [A_size:0] rd_ptr_bin_next;
    wire [A_size:0] rd_ptr_g_next;
    wire empty_val;

    assign rd_ptr_bin_next = rd_ptr_bin + (r_inc & ~empty);
    assign rd_ptr_g_next   = (rd_ptr_bin_next >> 1) ^ rd_ptr_bin_next;

    assign empty_val = (rd_ptr_g_next == wr_ptr_sync);

    always @(posedge r_clk or posedge r_reset) begin
        if (r_reset) begin
            rd_ptr_bin <= 0;
            rd_ptr_g   <= 0;
            empty      <= 1'b1;
        end else begin
            rd_ptr_bin <= rd_ptr_bin_next;
            rd_ptr_g   <= rd_ptr_g_next;
            empty      <= empty_val;
        end
    end
endmodule