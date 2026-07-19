module axi_io_slave #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter ID_WIDTH   = 4,
    parameter ROM_DEPTH  = 1024,
    parameter INIT_FILE  = "default_io.mem",
    parameter BASE_ADDR  = 32'h4000_0000 
)(
    input  wire                      ACLK,
    input  wire                      ARESETN,

    input  wire [ID_WIDTH-1:0]       AWID,
    input  wire [ADDR_WIDTH-1:0]     AWADDR,
    input  wire [7:0]                AWLEN,   
    input  wire [2:0]                AWSIZE,
    input  wire [1:0]                AWBURST,
    input  wire                      AWVALID,
    output reg                       AWREADY,

    input  wire [DATA_WIDTH-1:0]     WDATA,
    input  wire [(DATA_WIDTH/8)-1:0] WSTRB,
    input  wire                      WLAST,
    input  wire                      WVALID,
    output reg                       WREADY,

    output reg  [ID_WIDTH-1:0]       BID,
    output reg  [1:0]                BRESP,
    output reg                       BVALID,
    input  wire                      BREADY,

    input  wire [ID_WIDTH-1:0]       ARID,
    input  wire [ADDR_WIDTH-1:0]     ARADDR,
    input  wire [7:0]                ARLEN,   
    input  wire [2:0]                ARSIZE,
    input  wire [1:0]                ARBURST,
    input  wire                      ARVALID,
    output reg                       ARREADY,

    output reg  [ID_WIDTH-1:0]       RID,
    output reg  [DATA_WIDTH-1:0]     RDATA, 
    output reg  [1:0]                RRESP,
    output reg                       RLAST,
    output reg                       RVALID,
    input  wire                      RREADY
);

    reg [DATA_WIDTH-1:0] internal_rom [0:ROM_DEPTH-1];
    
    initial begin
        $readmemh(INIT_FILE, internal_rom);
    end

    reg [ID_WIDTH-1:0]   ar_id_queue    [0:3];
    reg [ADDR_WIDTH-1:0] ar_addr_queue  [0:3];
    reg [7:0]            ar_len_queue   [0:3]; 
    reg [2:0]            ar_size_queue  [0:3];
    reg [1:0]            ar_burst_queue [0:3];
    
    reg [1:0]            ar_head, ar_tail;
    reg [2:0]            ar_count;
    reg [7:0]            r_beat_count; 
    reg [ADDR_WIDTH-1:0] r_current_addr;

    reg                  ar_push, ar_pop;
    reg                  r_is_unsupported;
    reg [ADDR_WIDTH-1:0] r_addr_eff;
     
    reg [ID_WIDTH-1:0]   aw_id_queue    [0:3];
    reg [ADDR_WIDTH-1:0] aw_addr_queue  [0:3]; 
    reg [7:0]            aw_len_queue   [0:3]; 
    reg [2:0]            aw_size_queue  [0:3]; 
    reg [1:0]            aw_burst_queue [0:3];
    
    reg [1:0]            aw_head, aw_tail;
    reg [2:0]            aw_count;
    
    reg [7:0]            w_beat_count;         
    reg [ADDR_WIDTH-1:0] w_current_addr;       

    reg                  aw_push, aw_pop;
    reg                  w_is_unsupported;

    // FIXED: Organized evaluation order
    always @(*) begin
        r_addr_eff       = (r_beat_count == 0) ? ar_addr_queue[ar_head] : r_current_addr;
        RLAST            = (r_beat_count == ar_len_queue[ar_head]);
        r_is_unsupported = (ar_burst_queue[ar_head] != 2'b01) || (ar_size_queue[ar_head] > 3'd2);
        
        w_is_unsupported = (aw_burst_queue[aw_head] != 2'b01) || (aw_size_queue[aw_head] > 3'd2);

        // Read channel assignments
        ARREADY          = (ar_count < 3'd4);
        RVALID           = (ar_count > 0); 
        RID              = ar_id_queue[ar_head];
        RRESP            = r_is_unsupported ? 2'b10 : 2'b00;        
        RDATA            = internal_rom[(r_addr_eff - BASE_ADDR) >> 2]; 
          
        ar_push          = ARVALID && ARREADY;
        ar_pop           = RVALID  && RREADY  && RLAST;

        // Write channel assignments
        AWREADY          = (aw_count < 3'd4);
        WREADY           = (aw_count > 0) && !BVALID;
        aw_push          = AWVALID && AWREADY;
        aw_pop           = BVALID  && BREADY;
    end

    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            ar_head        <= 2'd0; 
            ar_tail        <= 2'd0; 
            ar_count       <= 3'd0;
            r_beat_count   <= 8'd0;
            r_current_addr <= {ADDR_WIDTH{1'b0}};
        end else begin
            if (ar_push) begin
                ar_id_queue[ar_tail]    <= ARID;
                ar_addr_queue[ar_tail]  <= ARADDR;
                ar_len_queue[ar_tail]   <= ARLEN;
                ar_size_queue[ar_tail]  <= ARSIZE;
                ar_burst_queue[ar_tail] <= ARBURST;
                ar_tail                 <= ar_tail + 1'b1;
            end
            if (ar_pop) begin
                ar_head <= ar_head + 1'b1;
            end
            ar_count <= ar_count + (ar_push) - (ar_pop);

            if (RVALID && RREADY) begin
                if (RLAST) begin
                    r_beat_count <= 8'd0;
                end else begin
                    r_beat_count   <= r_beat_count + 1'b1;
                    r_current_addr <= r_addr_eff + (1 << ar_size_queue[ar_head]);
                end
            end
        end
    end

    wire [ADDR_WIDTH-1:0] w_addr_eff = (w_beat_count == 0) ? aw_addr_queue[aw_head] : w_current_addr;

    integer lane;

    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            aw_head        <= 2'd0; 
            aw_tail        <= 2'd0; 
            aw_count       <= 3'd0;
            w_beat_count   <= 8'd0;
            w_current_addr <= {ADDR_WIDTH{1'b0}};
                
            BVALID         <= 1'b0; 
            BID            <= {ID_WIDTH{1'b0}}; 
            BRESP          <= 2'b00;
        end else begin
            
            if (aw_push) begin
                aw_id_queue[aw_tail]    <= AWID;
                aw_addr_queue[aw_tail]  <= AWADDR; 
                aw_len_queue[aw_tail]   <= AWLEN;  
                aw_size_queue[aw_tail]  <= AWSIZE;  
                aw_burst_queue[aw_tail] <= AWBURST;
                aw_tail                 <= aw_tail + 1'b1;
            end
            
            if (aw_pop) begin
                aw_head <= aw_head + 1'b1;
            end
            aw_count <= aw_count + (aw_push) - (aw_pop);

            if (WVALID && WREADY) begin
                if (!w_is_unsupported) begin
                    for (lane = 0; lane < (DATA_WIDTH/8); lane = lane + 1) begin
                        if (WSTRB[lane]) begin
                            internal_rom[(w_addr_eff - BASE_ADDR) >> 2][(lane*8) +: 8] <= WDATA[(lane*8) +: 8];
                        end
                    end
                end

                if (WLAST) begin
                    w_beat_count <= 8'd0;
                    BVALID       <= 1'b1; 
                    BID          <= aw_id_queue[aw_head]; 
                    BRESP        <= w_is_unsupported ? 2'b10 : 2'b00; 
                end else begin
                    w_beat_count   <= w_beat_count + 1'b1;
                    w_current_addr <= w_addr_eff + (1 << aw_size_queue[aw_head]);
                end
            end
            
            else if (BVALID && BREADY) begin
                BVALID <= 1'b0;
            end
        end
    end

endmodule
