import dmac_pkg::*;

module axi_slave_memory #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter ID_WIDTH   = 4
)(
    axi_if.slave axi
);
    logic                      ram_wr_en, ram_rd_en;
    logic [ADDR_WIDTH-1:0]     ram_wr_ad, ram_rd_ad;
    logic [DATA_WIDTH-1:0]     ram_wdata, ram_rdata;
    logic [(DATA_WIDTH/8)-1:0] ram_wstrb;

    ram #(
        .DEPTH(1024), .DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)
    ) internal_sram_inst (
        .clk(axi.clk),
        .wr_en(ram_wr_en), .wr_addr(ram_wr_ad), .wdata(ram_wdata), .wstrb(ram_wstrb),
        .rd_en(ram_rd_en), .rd_addr(ram_rd_ad), .rdata(ram_rdata)
    );

    logic [ID_WIDTH-1:0]   ar_id_q   [0:3];
    logic [ADDR_WIDTH-1:0] ar_addr_q [0:3];
    logic [7:0]            ar_len_q  [0:3]; 
    logic [2:0]            ar_size_q [0:3];
    logic [1:0]            ar_burst_q[0:3]; 
    
    logic [1:0] ar_head, ar_tail;
    logic [2:0] ar_count;
    logic [7:0] r_beat; 
    logic [ADDR_WIDTH-1:0] r_current_addr;

    logic ar_push, ar_pop;
    logic r_is_unsupported;
    logic [ADDR_WIDTH-1:0] r_addr_eff;

    always_comb begin
        r_addr_eff       = (r_beat == 0) ? (ar_addr_q[ar_head] & ~((1 << ar_size_q[ar_head]) - 1)) : r_current_addr;
        axi.rlast        = (r_beat == ar_len_q[ar_head]);
        r_is_unsupported = (ar_burst_q[ar_head] != 2'b01);
        
        axi.arready      = (ar_count < 3'd4);
        ar_push          = axi.arvalid && axi.arready;
        ar_pop           = axi.rvalid  && axi.rready && axi.rlast;

        axi.rid          = ar_id_q[ar_head];
        axi.rresp        = r_is_unsupported ? 2'b10 : 2'b00;
        axi.rdata        = ram_rdata;

        ram_rd_en        = axi.rvalid && axi.rready && !r_is_unsupported; 
        ram_rd_ad        = r_addr_eff;
    end
    
    always_ff @(posedge axi.clk or negedge axi.resetn) begin
        if (!axi.resetn) begin
            ar_head  <= 2'd0; 
            ar_tail  <= 2'd0; 
            ar_count <= 3'd0;
            axi.rvalid <= 1'b0;
            r_beat   <= 8'd0;
            r_current_addr <= {ADDR_WIDTH{1'b0}};
        end else begin
            if (ar_push) begin
                ar_id_q[ar_tail]    <= axi.arid;
                ar_addr_q[ar_tail]  <= axi.araddr;
                ar_len_q[ar_tail]   <= axi.arlen;
                ar_size_q[ar_tail]  <= axi.arsize;
                ar_burst_q[ar_tail] <= axi.arburst;
                ar_tail             <= ar_tail + 1'b1;
            end
            if (ar_pop) begin
                ar_head <= ar_head + 1'b1;
            end
            ar_count <= ar_count + (ar_push) - (ar_pop);

            if (axi.rvalid && axi.rready) begin
                axi.rvalid <= axi.rlast ? 1'b0 : 1'b1; 
                if (axi.rlast) begin
                    r_beat <= 8'd0;
                end else begin
                    r_beat         <= r_beat + 1'b1;
                    r_current_addr <= r_addr_eff + (1 << ar_size_q[ar_head]);
                end
            end else if (!axi.rvalid && ar_count > 0) begin
                axi.rvalid <= 1'b1;
            end
        end
    end

    logic [ID_WIDTH-1:0]   aw_id_q    [0:3];
    logic [ADDR_WIDTH-1:0] aw_addr_q  [0:3];
    logic [2:0]            aw_size_q  [0:3];
    logic [1:0]            aw_burst_q [0:3]; 
    
    logic [1:0] aw_head, aw_tail;
    logic [2:0] aw_count;
    logic       w_first_beat;
    logic [ADDR_WIDTH-1:0] w_current_addr;

    logic aw_push, aw_pop;
    logic w_is_unsupported;
    logic [ADDR_WIDTH-1:0] w_addr_eff;

    always_comb begin
        w_is_unsupported = (aw_burst_q[aw_head] != 2'b01);
        w_addr_eff       = w_first_beat ? (aw_addr_q[aw_head] & ~((1 << aw_size_q[aw_head]) - 1)) : w_current_addr;

        axi.awready      = (aw_count < 3'd4);
        axi.wready       = (aw_count > 0) && !axi.bvalid; 
        aw_push          = axi.awvalid && axi.awready;
        aw_pop           = axi.bvalid  && axi.bready;

        ram_wr_en        = axi.wvalid && axi.wready && (axi.wstrb != 0) && !w_is_unsupported;
        ram_wdata        = axi.wdata;
        ram_wstrb        = axi.wstrb;
        ram_wr_ad        = w_addr_eff;
    end

    always_ff @(posedge axi.clk or negedge axi.resetn) begin
        if (!axi.resetn) begin
            aw_head        <= 2'd0; 
            aw_tail        <= 2'd0; 
            aw_count       <= 3'd0;
            w_first_beat   <= 1'b1;
            w_current_addr <= {ADDR_WIDTH{1'b0}};
            axi.bvalid     <= 1'b0;
            axi.bid        <= {ID_WIDTH{1'b0}};
            axi.bresp      <= 2'b00;
        end else begin
            if (aw_push) begin
                aw_id_q[aw_tail]    <= axi.awid;
                aw_addr_q[aw_tail]  <= axi.awaddr;
                aw_size_q[aw_tail]  <= axi.awsize;
                aw_burst_q[aw_tail] <= axi.awburst;
                aw_tail             <= aw_tail + 1'b1;
            end
            if (aw_pop) begin
                aw_head <= aw_head + 1'b1;
            end
            aw_count <= aw_count + (aw_push) - (aw_pop);

            if (axi.wvalid && axi.wready) begin
                w_first_beat   <= axi.wlast;
                w_current_addr <= w_addr_eff + (1 << aw_size_q[aw_head]);
                
                if (axi.wlast) begin
                    axi.bvalid <= 1'b1;
                    axi.bid    <= aw_id_q[aw_head];
                    axi.bresp  <= w_is_unsupported ? 2'b10 : 2'b00; 
                end
            end else if (axi.bvalid && axi.bready) begin
                axi.bvalid <= 1'b0;
            end
        end
    end
endmodule
