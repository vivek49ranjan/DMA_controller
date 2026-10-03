import dmac_pkg::*;

module axi_master #(
    parameter ADDR_WIDTH   = 32,
    parameter DATA_WIDTH   = 32,
    parameter ID_WIDTH     = 4,
    parameter Q_DEPTH_BITS = 2
)(
    axi_if.master                 axi,
    input  dma_cmd_t              cmd,
    input  logic                  cmd_valid,
    
    output logic                  read_cmd_ready,
    output logic                  write_cmd_ready,
    output logic                  read_cmd_done,
    output logic [Q_DEPTH_BITS:0] read_done_id,
    output logic                  write_cmd_done,
    output logic [Q_DEPTH_BITS:0] write_done_id,
    output logic                  cmd_error,
    output logic [1:0]            cmd_error_type,

    input  logic [DATA_WIDTH-1:0] tx_data,
    input  logic                  tx_valid,
    output logic                  tx_ready,
    
    output logic [DATA_WIDTH-1:0] rx_data,
    output logic                  rx_valid,
    input  logic                  rx_ready
);
    
    logic [2:0] outstanding_reads;
    logic       read_pipeline_full;
    logic       ar_fire, r_fire, r_last_fire;
    
    assign read_pipeline_full = (outstanding_reads == 3'd4);
    assign ar_fire            = axi.arvalid && axi.arready;
    assign r_fire             = axi.rvalid && axi.rready;
    assign r_last_fire        = r_fire && axi.rlast;

    always_comb begin
        read_cmd_ready = !read_pipeline_full && !axi.arvalid;
    end

    always_ff @(posedge axi.clk or negedge axi.resetn) begin
        if (!axi.resetn) begin
            axi.arvalid       <= 1'b0;
            outstanding_reads <= 3'd0;
            axi.araddr        <= {ADDR_WIDTH{1'b0}};
            axi.arlen         <= 8'd0;
            axi.arsize        <= 3'd0;
            axi.arid          <= {ID_WIDTH{1'b0}};
            axi.arburst       <= 2'b01;
        end else begin
            if (cmd_valid && !cmd.rnw && read_cmd_ready) begin
                axi.arvalid <= 1'b1;
                axi.araddr  <= cmd.addr;
                axi.arlen   <= cmd.len - 1'b1; 
                axi.arsize  <= cmd.size;
                axi.arid    <= cmd.id;
                axi.arburst <= 2'b01;
            end else if (ar_fire) begin
                axi.arvalid <= 1'b0;
            end

            case ({ar_fire, r_last_fire})
                2'b10: outstanding_reads <= outstanding_reads + 1'b1; 
                2'b01: outstanding_reads <= outstanding_reads - 1'b1; 
                default: ; 
            endcase
        end
    end

    logic latch_rresp_err;
    logic [1:0] latch_rresp_type;

    always_ff @(posedge axi.clk or negedge axi.resetn) begin
        if (!axi.resetn) begin
            latch_rresp_err  <= 1'b0;
            latch_rresp_type <= 2'b00;
        end else begin
            if (r_fire && axi.rresp != 2'b00) begin
                latch_rresp_err  <= 1'b1;
                latch_rresp_type <= axi.rresp;
            end
            if (r_last_fire) begin
                latch_rresp_err  <= 1'b0; 
            end
        end
    end

    always_comb begin
        axi.rready    = rx_ready;
        rx_valid      = axi.rvalid;
        rx_data       = axi.rdata;
        read_cmd_done = 1'b0;
        read_done_id  = axi.rid[Q_DEPTH_BITS:0]; 

        if (r_last_fire) begin
            read_cmd_done = 1'b1;
        end
    end

    localparam MAX_W_OUT = 4; 
    
    logic [2:0]              outstanding_writes;
    logic [1:0]              aw_head, w_tail, b_tail;  
    logic [7:0]              awlen_buffer  [0:MAX_W_OUT-1]; 
    logic [ADDR_WIDTH-1:0]   awaddr_buffer [0:MAX_W_OUT-1]; 
    logic [2:0]              awsize_buffer [0:MAX_W_OUT-1]; 
    logic [MAX_W_OUT-1:0]    add_valid; 

    logic write_pipeline_full;
    logic aw_fire, b_fire;
    
    assign write_pipeline_full = (outstanding_writes == 3'd4);
    assign aw_fire             = axi.awvalid && axi.awready;
    assign b_fire              = axi.bvalid  && axi.bready;

    always_comb begin
        write_cmd_ready = !write_pipeline_full && !axi.awvalid;
    end

    always_ff @(posedge axi.clk or negedge axi.resetn) begin
        if (!axi.resetn) begin
            axi.awvalid        <= 1'b0;
            outstanding_writes <= 3'd0;
            axi.awaddr         <= {ADDR_WIDTH{1'b0}};
            axi.awlen          <= 8'd0;
            axi.awsize         <= 3'd0;
            axi.awid           <= {ID_WIDTH{1'b0}};
            axi.awburst        <= 2'b01;
            
            aw_head            <= 2'd0;
            b_tail             <= 2'd0; 
            add_valid          <= {MAX_W_OUT{1'b0}}; 
        end else begin
            if (cmd_valid && cmd.rnw && write_cmd_ready) begin
                axi.awvalid <= 1'b1;
                axi.awaddr  <= cmd.addr;
                axi.awlen   <= cmd.len - 1'b1;
                axi.awsize  <= cmd.size;
                axi.awid    <= cmd.id;
                axi.awburst <= 2'b01;
            end else if (aw_fire) begin
                axi.awvalid <= 1'b0;
            end

            case ({aw_fire, b_fire})
                2'b11: begin 
                    awlen_buffer[aw_head]  <= axi.awlen;
                    awaddr_buffer[aw_head] <= axi.awaddr;
                    awsize_buffer[aw_head] <= axi.awsize;
                    aw_head                <= aw_head + 1'b1;
                    add_valid[aw_head]     <= 1'b1;
                    
                    b_tail <= b_tail + 1'b1;
                    if (aw_head != b_tail) add_valid[b_tail] <= 1'b0;
                end
                2'b10: begin 
                    outstanding_writes     <= outstanding_writes + 1'b1;
                    awlen_buffer[aw_head]  <= axi.awlen;
                    awaddr_buffer[aw_head] <= axi.awaddr;
                    awsize_buffer[aw_head] <= axi.awsize;
                    aw_head                <= aw_head + 1'b1;
                    add_valid[aw_head]     <= 1'b1;
                end
                2'b01: begin 
                    outstanding_writes <= outstanding_writes - 1'b1;
                    b_tail             <= b_tail + 1'b1;
                    add_valid[b_tail]  <= 1'b0;
                end
                default: ; 
            endcase
        end
    end
    
    logic [7:0]            current_awlen;
    logic [ADDR_WIDTH-1:0] current_awaddr;
    logic [2:0]            current_awsize;
    logic                  w_channel_active;
    
    assign current_awlen    = awlen_buffer[w_tail]; 
    assign current_awaddr   = awaddr_buffer[w_tail];
    assign current_awsize   = awsize_buffer[w_tail];
    assign w_channel_active = add_valid[w_tail]; 

    logic [7:0]                w_beat_cnt;
    logic [ADDR_WIDTH-1:0]     w_current_addr;
    
    logic                      wvalid_reg;
    logic [DATA_WIDTH-1:0]     wdata_reg;
    logic [(DATA_WIDTH/8)-1:0] wstrb_reg;
    logic                      wlast_reg;

    logic [ADDR_WIDTH-1:0] w_addr_eff;
    logic w_advance;
    
    assign w_addr_eff = (w_beat_cnt == 0) ? current_awaddr : w_current_addr;
    assign w_advance  = (!wvalid_reg || (wvalid_reg && axi.wready)) && w_channel_active;
    
    logic [(DATA_WIDTH/8)-1:0] wstrb_comb;

    always_comb begin : w_channel_comb
        tx_ready   = w_advance;
        axi.wvalid = wvalid_reg;
        axi.wdata  = wdata_reg;
        axi.wstrb  = wstrb_reg;
        axi.wlast  = wlast_reg;

        wstrb_comb = {(DATA_WIDTH/8){1'b0}};
        for (int lane = 0; lane < (DATA_WIDTH/8); lane++) begin
            if ((lane >= (w_addr_eff % (DATA_WIDTH/8))) && 
                (lane <  (w_addr_eff % (DATA_WIDTH/8)) + (1 << current_awsize))) begin
                wstrb_comb[lane] = 1'b1;
            end
        end
    end

    always_ff @(posedge axi.clk or negedge axi.resetn) begin
        if (!axi.resetn) begin
            wvalid_reg     <= 1'b0;
            wdata_reg      <= {DATA_WIDTH{1'b0}};
            wstrb_reg      <= {(DATA_WIDTH/8){1'b0}};
            wlast_reg      <= 1'b0;
            w_beat_cnt     <= 8'd0;
            w_tail         <= 2'd0;
            w_current_addr <= {ADDR_WIDTH{1'b0}};
        end else begin
            if (wvalid_reg && axi.wready) begin
                wvalid_reg <= 1'b0;
            end

            if (w_advance && tx_valid) begin
                wvalid_reg <= 1'b1;
                wdata_reg  <= tx_data;
                wstrb_reg  <= wstrb_comb;
                wlast_reg  <= (w_beat_cnt == current_awlen);

                w_current_addr <= (w_addr_eff & ~((1 << current_awsize) - 1)) + (1 << current_awsize);

                if (w_beat_cnt == current_awlen) begin
                    w_beat_cnt <= 8'd0; 
                    w_tail     <= w_tail + 1'b1;
                end else begin
                    w_beat_cnt <= w_beat_cnt + 1'b1;
                end
            end
        end
    end
    
    always_comb begin
        axi.bready     = 1'b1; 
        cmd_error      = 1'b0;
        cmd_error_type = 2'b00;
        write_cmd_done = 1'b0;
        write_done_id  = axi.bid[Q_DEPTH_BITS:0];
        
        if (b_fire) begin
            write_cmd_done = 1'b1;
            if (axi.bresp != 2'b00) begin 
                cmd_error      = 1'b1; 
                cmd_error_type = axi.bresp;
            end
        end

        if (r_last_fire) begin
            if (axi.rresp != 2'b00 || latch_rresp_err) begin 
                cmd_error      = 1'b1;
                cmd_error_type = latch_rresp_err ? latch_rresp_type : axi.rresp;
            end
        end
    end
endmodule
