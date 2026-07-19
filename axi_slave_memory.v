module axi_slave_memory #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter ID_WIDTH   = 4
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
    input  wire                      RREADY,

    output reg                       MEMORY_WR_EN,
    output reg  [ADDR_WIDTH-1:0]     MEMORY_WR_AD,
    output reg  [DATA_WIDTH-1:0]     MEMORY_WDATA,
    output reg  [(DATA_WIDTH/8)-1:0] MEMORY_WSTRB,
    input  wire                      MEMORY_WR_BUSY,

    output reg                       MEMORY_RD_EN,
    output reg  [ADDR_WIDTH-1:0]     MEMORY_RD_AD,
    input  wire [DATA_WIDTH-1:0]     MEMORY_RDATA,
    input  wire                      MEMORY_RD_BUSY
);

    reg [ID_WIDTH-1:0]   ar_id_q   [0:3];
    reg [ADDR_WIDTH-1:0] ar_addr_q [0:3];
    reg [7:0]            ar_len_q  [0:3]; 
    reg [2:0]            ar_size_q [0:3];
    reg [1:0]            ar_burst_q[0:3]; 
    
    reg [1:0] ar_head, ar_tail;
    reg [2:0] ar_count;
    reg [7:0] r_beat; 
    reg [ADDR_WIDTH-1:0] r_current_addr;

    reg ar_push, ar_pop;
    reg r_is_unsupported;
    reg [ADDR_WIDTH-1:0] r_addr_eff;

    // FIXED: Evaluated dependencies first to prevent delta cycle mismatches
    always @(*) begin
        r_addr_eff       = (r_beat == 0) ? ar_addr_q[ar_head] : r_current_addr;
        RLAST            = (r_beat == ar_len_q[ar_head]);
        r_is_unsupported = (ar_burst_q[ar_head] != 2'b01);
        
        ARREADY          = (ar_count < 3'd4);
        ar_push          = ARVALID && ARREADY;
        ar_pop           = RVALID  && RREADY && RLAST;

        RID              = ar_id_q[ar_head];
        RRESP            = r_is_unsupported ? 2'b10 : 2'b00;
        RDATA            = MEMORY_RDATA;

        MEMORY_RD_EN     = RVALID && RREADY && !r_is_unsupported; 
        MEMORY_RD_AD     = r_addr_eff;
    end
    
    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            ar_head  <= 2'd0; 
            ar_tail  <= 2'd0; 
            ar_count <= 3'd0;
            RVALID   <= 1'b0;
            r_beat   <= 8'd0;
            r_current_addr <= {ADDR_WIDTH{1'b0}};
        end else begin
            if (ar_push) begin
                ar_id_q[ar_tail]    <= ARID;
                ar_addr_q[ar_tail]  <= ARADDR;
                ar_len_q[ar_tail]   <= ARLEN;
                ar_size_q[ar_tail]  <= ARSIZE;
                ar_burst_q[ar_tail] <= ARBURST;
                ar_tail             <= ar_tail + 1'b1;
            end
            if (ar_pop) begin
                ar_head <= ar_head + 1'b1;
            end
            ar_count <= ar_count + (ar_push) - (ar_pop);

            if (RVALID && RREADY) begin
                RVALID <= RLAST ? 1'b0 : !MEMORY_RD_BUSY;
                if (RLAST) begin
                    r_beat <= 8'd0;
                end else begin
                    r_beat         <= r_beat + 1'b1;
                    r_current_addr <= r_addr_eff + (1 << ar_size_q[ar_head]);
                end
            end else if (!RVALID && ar_count > 0 && !MEMORY_RD_BUSY) begin
                RVALID <= 1'b1;
            end
        end
    end

    reg [ID_WIDTH-1:0]   aw_id_q    [0:3];
    reg [ADDR_WIDTH-1:0] aw_addr_q  [0:3];
    reg [2:0]            aw_size_q  [0:3];
    reg [1:0]            aw_burst_q [0:3]; 
    
    reg [1:0] aw_head, aw_tail;
    reg [2:0] aw_count;
    reg       w_first_beat;
    reg [ADDR_WIDTH-1:0] w_current_addr;

    reg aw_push, aw_pop;
    reg w_is_unsupported;
    reg [ADDR_WIDTH-1:0] w_addr_eff;

    always @(*) begin
        w_is_unsupported = (aw_burst_q[aw_head] != 2'b01);
        w_addr_eff       = w_first_beat ? aw_addr_q[aw_head] : w_current_addr;

        AWREADY          = (aw_count < 3'd4);
        WREADY           = (aw_count > 0) && !MEMORY_WR_BUSY && !BVALID;
        aw_push          = AWVALID && AWREADY;
        aw_pop           = BVALID  && BREADY;

        MEMORY_WR_EN     = WVALID && WREADY && (WSTRB != 0) && !w_is_unsupported;
        MEMORY_WDATA     = WDATA;
        MEMORY_WSTRB     = WSTRB;
        MEMORY_WR_AD     = w_addr_eff;
    end

    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            aw_head        <= 2'd0; 
            aw_tail        <= 2'd0; 
            aw_count       <= 3'd0;
            w_first_beat   <= 1'b1;
            w_current_addr <= {ADDR_WIDTH{1'b0}};
            BVALID         <= 1'b0;
            BID            <= {ID_WIDTH{1'b0}};
            BRESP          <= 2'b00;
        end else begin
            if (aw_push) begin
                aw_id_q[aw_tail]    <= AWID;
                aw_addr_q[aw_tail]  <= AWADDR;
                aw_size_q[aw_tail]  <= AWSIZE;
                aw_burst_q[aw_tail] <= AWBURST;
                aw_tail             <= aw_tail + 1'b1;
            end
            if (aw_pop) begin
                aw_head <= aw_head + 1'b1;
            end
            aw_count <= aw_count + (aw_push) - (aw_pop);

            if (WVALID && WREADY) begin
                w_first_beat   <= WLAST;
                w_current_addr <= w_addr_eff + (1 << aw_size_q[aw_head]);
                
                if (WLAST) begin
                    BVALID <= 1'b1;
                    BID    <= aw_id_q[aw_head];
                    BRESP  <= w_is_unsupported ? 2'b10 : 2'b00; 
                end
            end else if (BVALID && BREADY) begin
                BVALID <= 1'b0;
            end
        end
    end

endmodule
