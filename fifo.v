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
    
    reg [A_size:0] wr_ptr_sync, rd_ptr_sync;  
    
    reg [A_size:0] wr_ptr_sync_q1, rd_ptr_sync_q1; 

    
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

    always @(posedge w_clk or posedge w_reset) begin
        if (w_reset) begin
            rd_ptr_sync_q1 <= 0;
            rd_ptr_sync    <= 0;
        end else begin
            rd_ptr_sync_q1 <= rd_ptr_g;
            rd_ptr_sync    <= rd_ptr_sync_q1;
        end
    end

    always @(posedge r_clk or posedge r_reset) begin
        if (r_reset) begin
            wr_ptr_sync_q1 <= 0;
            wr_ptr_sync    <= 0;
        end else begin
            wr_ptr_sync_q1 <= wr_ptr_g;
            wr_ptr_sync    <= wr_ptr_sync_q1;
        end
    end

endmodule
