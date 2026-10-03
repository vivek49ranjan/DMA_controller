import dmac_pkg::*;

module axi_io_slave #(
    parameter ROM_DEPTH  = 1024,
    parameter INIT_FILE  = "default_io.mem",
    parameter BASE_ADDR  = 32'h4000_0000 
)(
    axi_if.slave axi
);

    logic [DATA_WIDTH-1:0] internal_rom [0:ROM_DEPTH-1];
    
    initial begin
        $readmemh(INIT_FILE, internal_rom);
    end

    logic [ID_WIDTH-1:0]   ar_id_queue    [0:3];
    logic [ADDR_WIDTH-1:0] ar_addr_queue  [0:3];
    logic [7:0]            ar_len_queue   [0:3]; 
    logic [2:0]            ar_size_queue  [0:3];
    logic [1:0]            ar_burst_queue [0:3];
    
    logic [1:0]            ar_head, ar_tail;
    logic [2:0]            ar_count;
    logic [7:0]            r_beat_count; 
    logic [ADDR_WIDTH-1:0] r_current_addr;

    logic                  ar_push, ar_pop;
    logic                  r_is_unsupported;
    logic [ADDR_WIDTH-1:0] r_addr_eff;
     
    logic [ID_WIDTH-1:0]   aw_id_queue    [0:3];
    logic [ADDR_WIDTH-1:0] aw_addr_queue  [0:3]; 
    logic [7:0]            aw_len_queue   [0:3]; 
    logic [2:0]            aw_size_queue  [0:3]; 
    logic [1:0]            aw_burst_queue [0:3];
    
    logic [1:0]            aw_head, aw_tail;
    logic [2:0]            aw_count;
    logic [7:0]            w_beat_count;         
    logic [ADDR_WIDTH-1:0] w_current_addr;       

    logic                  aw_push, aw_pop;
    logic                  w_is_unsupported;

    always_comb begin
        r_addr_eff       = (r_beat_count == 0) ? (ar_addr_queue[ar_head] & ~((1 << ar_size_queue[ar_head]) - 1)) : r_current_addr;
        
        axi.rlast        = (r_beat_count == ar_len_queue[ar_head]);
        r_is_unsupported = (ar_burst_queue[ar_head] != 2'b01) || (ar_size_queue[ar_head] > 3'd2);
        w_is_unsupported = (aw_burst_queue[aw_head] != 2'b01) || (aw_size_queue[aw_head] > 3'd2);

        axi.arready      = (ar_count < 3'd4);
        axi.rvalid       = (ar_count > 0); 
        axi.rid          = ar_id_queue[ar_head];
        axi.rresp        = r_is_unsupported ? 2'b10 : 2'b00;        
        axi.rdata        = internal_rom[(r_addr_eff - BASE_ADDR) >> 2]; 
          
        ar_push          = axi.arvalid && axi.arready;
        ar_pop           = axi.rvalid  && axi.rready  && axi.rlast;

        axi.awready      = (aw_count < 3'd4);
        axi.wready       = (aw_count > 0) && !axi.bvalid;
        aw_push          = axi.awvalid && axi.awready;
        aw_pop           = axi.bvalid  && axi.bready;
    end

    always_ff @(posedge axi.clk or negedge axi.resetn) begin
        if (!axi.resetn) begin
            ar_head        <= 2'd0; 
            ar_tail        <= 2'd0; 
            ar_count       <= 3'd0;
            r_beat_count   <= 8'd0;
            r_current_addr <= {ADDR_WIDTH{1'b0}};
        end else begin
            if (ar_push) begin
                ar_id_queue[ar_tail]    <= axi.arid;
                ar_addr_queue[ar_tail]  <= axi.araddr;
                ar_len_queue[ar_tail]   <= axi.arlen;
                ar_size_queue[ar_tail]  <= axi.arsize;
                ar_burst_queue[ar_tail] <= axi.arburst;
                ar_tail                 <= ar_tail + 1'b1;
            end
            if (ar_pop) begin
                ar_head <= ar_head + 1'b1;
            end
            ar_count <= ar_count + (ar_push) - (ar_pop);

            if (axi.rvalid && axi.rready) begin
                if (axi.rlast) begin
                    r_beat_count <= 8'd0;
                end else begin
                    r_beat_count   <= r_beat_count + 1'b1;
                    r_current_addr <= r_addr_eff + (1 << ar_size_queue[ar_head]);
                end
            end
        end
    end

    logic [ADDR_WIDTH-1:0] w_addr_eff;
    assign w_addr_eff = (w_beat_count == 0) ? (aw_addr_queue[aw_head] & ~((1 << aw_size_queue[aw_head]) - 1)) : w_current_addr;

    always_ff @(posedge axi.clk or negedge axi.resetn) begin
        if (!axi.resetn) begin
            aw_head        <= 2'd0; 
            aw_tail        <= 2'd0; 
            aw_count       <= 3'd0;
            w_beat_count   <= 8'd0;
            w_current_addr <= {ADDR_WIDTH{1'b0}};
                
            axi.bvalid     <= 1'b0; 
            axi.bid        <= {ID_WIDTH{1'b0}}; 
            axi.bresp      <= 2'b00;
        end else begin
            if (aw_push) begin
                aw_id_queue[aw_tail]    <= axi.awid;
                aw_addr_queue[aw_tail]  <= axi.awaddr; 
                aw_len_queue[aw_tail]   <= axi.awlen;  
                aw_size_queue[aw_tail]  <= axi.awsize;  
                aw_burst_queue[aw_tail] <= axi.awburst;
                aw_tail                 <= aw_tail + 1'b1;
            end
            
            if (aw_pop) begin
                aw_head <= aw_head + 1'b1;
            end
            aw_count <= aw_count + (aw_push) - (aw_pop);

            if (axi.wvalid && axi.wready) begin
                if (!w_is_unsupported) begin
                    for (int lane = 0; lane < (DATA_WIDTH/8); lane++) begin
                        if (axi.wstrb[lane]) begin
                            internal_rom[(w_addr_eff - BASE_ADDR) >> 2][(lane*8) +: 8] <= axi.wdata[(lane*8) +: 8];
                        end
                    end
                end

                if (axi.wlast) begin
                    w_beat_count <= 8'd0;
                    axi.bvalid   <= 1'b1; 
                    axi.bid      <= aw_id_queue[aw_head]; 
                    axi.bresp    <= w_is_unsupported ? 2'b10 : 2'b00; 
                end else begin
                    w_beat_count   <= w_beat_count + 1'b1;
                    w_current_addr <= w_addr_eff + (1 << aw_size_queue[aw_head]);
                end
            end
            
            else if (axi.bvalid && axi.bready) begin
                axi.bvalid <= 1'b0;
            end
        end
    end
endmodule
