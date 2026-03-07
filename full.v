module full_indi #(parameter A_size=5) (
    input w_clk, w_reset, w_inc,
    input [A_size:0] rd_ptr_sync,
    output reg [A_size:0] wr_ptr_g,
    output reg [A_size:0] wr_ptr_bin,
    output reg full
);
    wire [A_size:0] wr_ptr_bin_next;
    wire [A_size:0] wr_ptr_g_next;
    wire full_val;

    assign wr_ptr_bin_next = wr_ptr_bin + (w_inc & ~full);
    assign wr_ptr_g_next   = (wr_ptr_bin_next >> 1) ^ wr_ptr_bin_next;

    assign full_val = (wr_ptr_g_next == {~rd_ptr_sync[A_size:A_size-1], rd_ptr_sync[A_size-2:0]});

    always @(posedge w_clk or posedge w_reset) begin
        if (w_reset) begin
            wr_ptr_bin <= 0;
            wr_ptr_g   <= 0;
            full       <= 0;
        end else begin
            wr_ptr_bin <= wr_ptr_bin_next;
            wr_ptr_g   <= wr_ptr_g_next;
            full       <= full_val;
        end
    end
endmodule