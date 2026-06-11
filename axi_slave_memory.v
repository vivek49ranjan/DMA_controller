module axi_slave_memory #(
    parameter DATA_WIDTH    = 32,
    parameter ADDR_WIDTH    = 32,
    parameter ID_WIDTH      = 4,
    parameter ALLOW_READ    = 1, 
    parameter ALLOW_WRITE   = 1, 
    parameter SUPPORT_FIXED = 0, 
    parameter SUPPORT_INCR  = 1, 
    parameter SUPPORT_WRAP  = 0  
)(
    input  wire                      ACLK,
    input  wire                      ARESETN,

    input  wire [ID_WIDTH-1:0]       AWID,
    input  wire [ADDR_WIDTH-1:0]     AWADDR,
    input  wire [3:0]                AWLEN,
    input  wire [2:0]                AWSIZE,
    input  wire [1:0]                AWBURST,
    input  wire                      AWVALID,
    output reg                       AWREADY,

    input  wire [ID_WIDTH-1:0]       WID,
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
    input  wire [3:0]                ARLEN,
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

   
    localparam WR_IDLE = 2'b00;
    localparam WR_DATA = 2'b01;
    localparam WR_RESP = 2'b10;

    reg [1:0]            wr_state, wr_next_state;
    reg                  w_err_latch;
    reg [ID_WIDTH-1:0]   latched_awid;
    reg [2:0]            latched_awsize;
    reg [1:0]            latched_awburst; 
    reg [ADDR_WIDTH-1:0] wr_addr_reg;

    always @(*) begin
        wr_next_state = wr_state;
        AWREADY       = 1'b0;
        WREADY        = 1'b0;
        MEMORY_WR_EN  = 1'b0;
        MEMORY_WR_AD  = wr_addr_reg;
        MEMORY_WDATA  = WDATA;
        MEMORY_WSTRB  = WSTRB;

        case (wr_state)
            WR_IDLE: begin
                AWREADY = 1'b1;
                if (AWVALID) begin
                    wr_next_state = WR_DATA;
                end
            end

            WR_DATA: begin
                WREADY = ~MEMORY_WR_BUSY;
                if (WVALID && WREADY) begin
                    if (!w_err_latch && (WSTRB != 0)) begin
                        MEMORY_WR_EN = 1'b1;
                    end
                    
                    if (WLAST) begin
                        wr_next_state = WR_RESP;
                    end
                end
            end

            WR_RESP: begin
                if (BVALID && BREADY) begin
                    wr_next_state = WR_IDLE;
                end
            end
            
            default: wr_next_state = WR_IDLE;
        endcase
    end

    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            wr_state        <= WR_IDLE;
            w_err_latch     <= 1'b0;
            latched_awid    <= {ID_WIDTH{1'b0}};
            latched_awsize  <= 3'd0;
            latched_awburst <= 2'b00;
            wr_addr_reg     <= {ADDR_WIDTH{1'b0}};
            BID             <= {ID_WIDTH{1'b0}};
            BRESP           <= 2'b00;
            BVALID          <= 1'b0;
        end else begin
            wr_state <= wr_next_state;

            case (wr_state)
                WR_IDLE: begin
                    if (AWVALID && AWREADY) begin
                        latched_awid    <= AWID;
                        latched_awsize  <= AWSIZE;
                        latched_awburst <= AWBURST; 
                        wr_addr_reg     <= AWADDR;
                        
                        w_err_latch     <= (!ALLOW_WRITE) || 
                                           ((1 << AWSIZE) > (DATA_WIDTH / 8)) ||
                                           (AWBURST == 2'b00 && !SUPPORT_FIXED) ||
                                           (AWBURST == 2'b01 && !SUPPORT_INCR) ||
                                           (AWBURST == 2'b10 && !SUPPORT_WRAP);
                    end
                end

                WR_DATA: begin
                    if (WVALID && WREADY) begin
                        if (!w_err_latch && latched_awburst == 2'b01) begin
                            wr_addr_reg <= (wr_addr_reg + (1 << latched_awsize)) & ~((1 << latched_awsize) - 1);
                        end
                        
                        if (WLAST) begin
                            BID    <= latched_awid;
                            BRESP  <= w_err_latch ? 2'b10 : 2'b00;
                            BVALID <= 1'b1;
                        end
                    end
                end

                WR_RESP: begin
                    if (BVALID && BREADY) begin
                        BVALID <= 1'b0;
                    end
                end
            endcase
        end
    end


    localparam RD_IDLE = 1'b0;
    localparam RD_DATA = 1'b1;

    reg                  rd_state, rd_next_state;
    reg                  r_err_latch;
    reg [3:0]            r_len_latch;
    reg [3:0]            read_count;
    reg [ID_WIDTH-1:0]   latched_arid;
    reg [2:0]            latched_arsize;
    reg [1:0]            latched_arburst; 
    reg [ADDR_WIDTH-1:0] rd_addr_reg;

    always @(*) begin
        rd_next_state = rd_state;
        ARREADY       = 1'b0;
        RVALID        = 1'b0;
        RLAST         = 1'b0;
        RRESP         = 2'b00;
        RDATA         = MEMORY_RDATA;
        MEMORY_RD_EN  = 1'b0;
        MEMORY_RD_AD  = rd_addr_reg;

        case (rd_state)
            RD_IDLE: begin
                ARREADY = 1'b1;
                if (ARVALID) begin
                    rd_next_state = RD_DATA;
                end
            end

            RD_DATA: begin
                RVALID = ~MEMORY_RD_BUSY;
                RLAST  = (read_count == r_len_latch);
                RRESP  = r_err_latch ? 2'b10 : 2'b00;

                if (RVALID && RREADY && !r_err_latch) begin
                    MEMORY_RD_EN = 1'b1;
                end

                if (RVALID && RREADY && RLAST) begin
                    rd_next_state = RD_IDLE;
                end
            end
            
            default: rd_next_state = RD_IDLE;
        endcase
    end

    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            rd_state        <= RD_IDLE;
            r_err_latch     <= 1'b0;
            r_len_latch     <= 4'd0;
            read_count      <= 4'd0;
            latched_arid    <= {ID_WIDTH{1'b0}};
            latched_arsize  <= 3'd0;
            latched_arburst <= 2'b00;
            rd_addr_reg     <= {ADDR_WIDTH{1'b0}};
            RID             <= {ID_WIDTH{1'b0}};
        end else begin
            rd_state <= rd_next_state;

            case (rd_state)
                RD_IDLE: begin
                    if (ARVALID && ARREADY) begin
                        r_len_latch     <= ARLEN;
                        read_count      <= 4'd0;
                        latched_arid    <= ARID;
                        latched_arsize  <= ARSIZE;
                        latched_arburst <= ARBURST; 
                        rd_addr_reg     <= ARADDR;
                        RID             <= ARID;
                        
                        r_err_latch     <= (!ALLOW_READ) || 
                                           ((1 << ARSIZE) > (DATA_WIDTH / 8)) ||
                                           (ARBURST == 2'b00 && !SUPPORT_FIXED) ||
                                           (ARBURST == 2'b01 && !SUPPORT_INCR) ||
                                           (ARBURST == 2'b10 && !SUPPORT_WRAP);
                    end
                end

                RD_DATA: begin
                    if (RVALID && RREADY) begin
                        if (!r_err_latch && latched_arburst == 2'b01) begin
                            rd_addr_reg <= (rd_addr_reg + (1 << latched_arsize)) & ~((1 << latched_arsize) - 1);
                        end
                        
                        if (!RLAST) begin
                            read_count <= read_count + 1'b1;
                        end
                    end
                end
            endcase
        end
    end

endmodule
