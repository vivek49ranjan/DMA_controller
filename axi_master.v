module axi_master #(
    parameter ADDR_WIDTH   = 32,
    parameter DATA_WIDTH   = 32,
    parameter ID_WIDTH     = 4,
    parameter Q_DEPTH_BITS = 2
) (
    input  wire                      ACLK,
    input  wire                      ARESETn,
    
    input  wire [ADDR_WIDTH-1:0]     cmd_addr,
    input  wire [7:0]                cmd_len,       
    input  wire [2:0]                cmd_size,
    input  wire                      cmd_rnw,
    input  wire [Q_DEPTH_BITS:0]     cmd_id,
    input  wire                      cmd_valid,
    
    output reg                       read_cmd_ready,
    output reg                       write_cmd_ready,
    output reg                       read_cmd_done,
    output reg  [Q_DEPTH_BITS:0]     read_done_id,
    output reg                       write_cmd_done,
    output reg  [Q_DEPTH_BITS:0]     write_done_id,
    output reg                       cmd_error,
    output reg  [1:0]                cmd_error_type,

    input  wire [DATA_WIDTH-1:0]     tx_data,
    input  wire                      tx_valid,
    output reg                       tx_ready,
    
    output reg  [DATA_WIDTH-1:0]     rx_data,
    output reg                       rx_valid,
    input  wire                      rx_ready,

    output reg  [ID_WIDTH-1:0]       AWID,
    output reg  [ADDR_WIDTH-1:0]     AWADDR,
    output reg  [7:0]                AWLEN,
    output reg  [2:0]                AWSIZE,
    output reg  [1:0]                AWBURST,
    output reg                       AWVALID,
    input  wire                      AWREADY,
    
    output reg  [DATA_WIDTH-1:0]     WDATA,
    output reg  [(DATA_WIDTH/8)-1:0] WSTRB,
    output reg                       WLAST,
    output reg                       WVALID,
    input  wire                      WREADY,
    
    input  wire [ID_WIDTH-1:0]       BID,
    input  wire [1:0]                BRESP,
    input  wire                      BVALID,
    output reg                       BREADY,
    
    output reg  [ID_WIDTH-1:0]       ARID,
    output reg  [ADDR_WIDTH-1:0]     ARADDR,
    output reg  [7:0]                ARLEN, 
    output reg  [2:0]                ARSIZE,
    output reg  [1:0]                ARBURST,
    output reg                       ARVALID,
    input  wire                      ARREADY,
    
    input  wire [ID_WIDTH-1:0]       RID,
    input  wire [DATA_WIDTH-1:0]     RDATA,
    input  wire [1:0]                RRESP,
    input  wire                      RLAST,
    input  wire                      RVALID,
    output reg                       RREADY
);
    
    reg [2:0] outstanding_reads;
    wire      read_pipeline_full = (outstanding_reads == 3'd4);
    wire      ar_fire            = ARVALID && ARREADY;
    wire      r_fire             = RVALID && RREADY;
    wire      r_last_fire        = r_fire && RLAST;

    always @(*) begin
        read_cmd_ready = !read_pipeline_full && !ARVALID;
    end

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            ARVALID           <= 1'b0;
            outstanding_reads <= 3'd0;
            ARADDR            <= {ADDR_WIDTH{1'b0}};
            ARLEN             <= 8'd0;
            ARSIZE            <= 3'd0;
            ARID              <= {ID_WIDTH{1'b0}};
            ARBURST           <= 2'b01;
        end else begin
            if (cmd_valid && !cmd_rnw && read_cmd_ready) begin
                ARVALID <= 1'b1;
                ARADDR  <= cmd_addr;
                ARLEN   <= cmd_len - 1'b1; 
                ARSIZE  <= cmd_size;
                ARID    <= cmd_id;
                ARBURST <= 2'b01;
            end else if (ar_fire) begin
                ARVALID <= 1'b0;
            end

            case ({ar_fire, r_last_fire})
                2'b10: outstanding_reads <= outstanding_reads + 1'b1; 
                2'b01: outstanding_reads <= outstanding_reads - 1'b1; 
                default: ; 
            endcase
        end
    end

    reg latch_rresp_err;
    reg [1:0] latch_rresp_type;

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            latch_rresp_err  <= 1'b0;
            latch_rresp_type <= 2'b00;
        end else begin
            if (r_fire && RRESP != 2'b00) begin
                latch_rresp_err  <= 1'b1;
                latch_rresp_type <= RRESP;
            end
            if (r_last_fire) begin
                latch_rresp_err  <= 1'b0; 
            end
        end
    end

    always @(*) begin
        RREADY        = rx_ready;
        rx_valid      = RVALID;
        rx_data       = RDATA;
        read_cmd_done = 1'b0;
        read_done_id  = RID[Q_DEPTH_BITS:0]; 

        if (r_last_fire) begin
            read_cmd_done = 1'b1;
        end
    end

    localparam MAX_W_OUT = 4; 
    
    reg [2:0]                outstanding_writes;
    reg [1:0]                aw_head, w_tail, b_tail;  
    reg [7:0]                awlen_buffer  [0:MAX_W_OUT-1]; 
    reg [ADDR_WIDTH-1:0]     awaddr_buffer [0:MAX_W_OUT-1]; 
    reg [2:0]                awsize_buffer [0:MAX_W_OUT-1]; 
    reg [MAX_W_OUT-1:0]      add_valid; 

    wire write_pipeline_full = (outstanding_writes == 3'd4);
    wire aw_fire             = AWVALID && AWREADY;
    wire b_fire              = BVALID  && BREADY;

    always @(*) begin
        write_cmd_ready = !write_pipeline_full && !AWVALID;
    end

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            AWVALID            <= 1'b0;
            outstanding_writes <= 3'd0;
            AWADDR             <= {ADDR_WIDTH{1'b0}};
            AWLEN              <= 8'd0;
            AWSIZE             <= 3'd0;
            AWID               <= {ID_WIDTH{1'b0}};
            AWBURST            <= 2'b01;
            
            aw_head            <= 2'd0;
            b_tail             <= 2'd0; 
            add_valid          <= {MAX_W_OUT{1'b0}}; 
        end else begin
            if (cmd_valid && cmd_rnw && write_cmd_ready) begin
                AWVALID <= 1'b1;
                AWADDR  <= cmd_addr;
                AWLEN   <= cmd_len - 1'b1;
                AWSIZE  <= cmd_size;
                AWID    <= cmd_id;
                AWBURST <= 2'b01;
            end else if (aw_fire) begin
                AWVALID <= 1'b0;
            end

            case ({aw_fire, b_fire})
                2'b11: begin 
                    awlen_buffer[aw_head]  <= AWLEN;
                    awaddr_buffer[aw_head] <= AWADDR;
                    awsize_buffer[aw_head] <= AWSIZE;
                    aw_head                <= aw_head + 1'b1;
                    add_valid[aw_head]     <= 1'b1;
                    
                    b_tail <= b_tail + 1'b1;
                    if (aw_head != b_tail) begin
                        add_valid[b_tail] <= 1'b0;
                    end
                end
                
                2'b10: begin 
                    outstanding_writes     <= outstanding_writes + 1'b1;
                    awlen_buffer[aw_head]  <= AWLEN;
                    awaddr_buffer[aw_head] <= AWADDR;
                    awsize_buffer[aw_head] <= AWSIZE;
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
    
    wire [7:0]            current_awlen  = awlen_buffer[w_tail]; 
    wire [ADDR_WIDTH-1:0] current_awaddr = awaddr_buffer[w_tail];
    wire [2:0]            current_awsize = awsize_buffer[w_tail];
    wire                  w_channel_active = add_valid[w_tail]; 

    reg [7:0]                w_beat_cnt;
    reg [ADDR_WIDTH-1:0]     w_current_addr;
    
    reg                      wvalid_reg;
    reg [DATA_WIDTH-1:0]     wdata_reg;
    reg [(DATA_WIDTH/8)-1:0] wstrb_reg;
    reg                      wlast_reg;

    wire [ADDR_WIDTH-1:0] w_addr_eff = (w_beat_cnt == 0) ? current_awaddr : w_current_addr;
    wire w_advance = (!wvalid_reg || (wvalid_reg && WREADY)) && w_channel_active;
    
    reg [(DATA_WIDTH/8)-1:0] wstrb_comb;

    always @(*) begin : w_channel_comb
        integer lane;
        tx_ready = w_advance;
        WVALID   = wvalid_reg;
        WDATA    = wdata_reg;
        WSTRB    = wstrb_reg;
        WLAST    = wlast_reg;

        wstrb_comb = {(DATA_WIDTH/8){1'b0}};
        for (lane = 0; lane < (DATA_WIDTH/8); lane = lane + 1) begin
            if ((lane >= (w_addr_eff % (DATA_WIDTH/8))) && 
                (lane <  (w_addr_eff % (DATA_WIDTH/8)) + (1 << current_awsize))) begin
                wstrb_comb[lane] = 1'b1;
            end
        end
    end

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            wvalid_reg     <= 1'b0;
            wdata_reg      <= {DATA_WIDTH{1'b0}};
            wstrb_reg      <= {(DATA_WIDTH/8){1'b0}};
            wlast_reg      <= 1'b0;
            w_beat_cnt     <= 8'd0;
            w_tail         <= 2'd0;
            w_current_addr <= {ADDR_WIDTH{1'b0}};
        end else begin
            if (wvalid_reg && WREADY) begin
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
    
    always @(*) begin
        BREADY         = 1'b1; 
        cmd_error      = 1'b0;
        cmd_error_type = 2'b00;
        write_cmd_done = 1'b0;
        write_done_id  = BID[Q_DEPTH_BITS:0];
        
        if (b_fire) begin
            write_cmd_done = 1'b1;
            if (BRESP != 2'b00) begin 
                cmd_error      = 1'b1; 
                cmd_error_type = BRESP;
            end
        end

        if (r_last_fire) begin
            if (RRESP != 2'b00 || latch_rresp_err) begin 
                cmd_error      = 1'b1;
                cmd_error_type = latch_rresp_err ? latch_rresp_type : RRESP;
            end
        end
    end

endmodule
