module fifo #(parameter D_size=8, parameter A_size=5) (
    input r_clk, w_clk,
    input w_reset, r_reset,
    input w_inc, r_inc,
    input [D_size-1:0] write_data,
    output [D_size-1:0] read_data,
    output full,
    output empty
);

    wire [A_size:0] wr_ptr_g, rd_ptr_g;   
    wire [A_size:0] wr_ptr_bin, rd_ptr_bin;
    wire [A_size:0] wr_ptr_sync, rd_ptr_sync; 

    fifo_mem #(D_size, (1<<A_size), A_size) memory_bank (
        .wr_clk(w_clk),
        .wr_ptr(wr_ptr_bin[A_size-1:0]), 
        .rd_ptr(rd_ptr_bin[A_size-1:0]),
        .write_data(write_data),
        .read_data(read_data),
        .w_inc(w_inc),
        .full(full)
    );

    full_indi #(A_size) write_ctrl (
        .w_clk(w_clk),
        .w_reset(w_reset),
        .w_inc(w_inc),
        .rd_ptr_sync(rd_ptr_sync),
        .wr_ptr_g(wr_ptr_g),
        .wr_ptr_bin(wr_ptr_bin),
        .full(full)
    );

    empty_indi #(A_size) read_ctrl (
        .r_clk(r_clk),
        .r_reset(r_reset),
        .r_inc(r_inc),
        .wr_ptr_sync(wr_ptr_sync),
        .rd_ptr_g(rd_ptr_g),
        .rd_ptr_bin(rd_ptr_bin),
        .empty(empty)
    );

    synchronizer #(A_size) sync_r2w (
        .clk(w_clk), .reset(w_reset),
        .d_in(rd_ptr_g), .d_out(rd_ptr_sync)
    );

    synchronizer #(A_size) sync_w2r (
        .clk(r_clk), .reset(r_reset),
        .d_in(wr_ptr_g), .d_out(wr_ptr_sync)
    );

endmodule