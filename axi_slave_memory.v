module axi_slave_memory #(
    parameter DATA_WIDTH    = 32,
    parameter ADDR_WIDTH    = 32,
    parameter ID_WIDTH      = 4,
    parameter ALLOW_READ    = 1, 
    parameter ALLOW_WRITE   = 1, 
    parameter SUPPORT_FIXED = 1, 
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

    localparam [1:0] W_IDLE = 2'd0, W_DATA = 2'd1, W_RESP = 2'd2;
    
    reg [1:0]            write_state;
    reg                  w_err_latch;
    reg [ID_WIDTH-1:0]   latched_awid;
    reg [2:0]            latched_awsize;
    reg [ADDR_WIDTH-1:0] wr_addr_reg;

    wire aw_size_err   = ((1 << AWSIZE) > (DATA_WIDTH / 8)); 
    wire aw_burst_err  = (AWBURST == 2'b00 && !SUPPORT_FIXED) || 
                         (AWBURST == 2'b01 && !SUPPORT_INCR)  || 
                         (AWBURST == 2'b10 && !SUPPORT_WRAP);
    wire aw_error_flag = (!ALLOW_WRITE) | aw_size_err | aw_burst_err;

    always @(*) begin
        AWREADY      = 1'b0;
        WREADY       = 1'b0;
        BVALID       = 1'b0;
        BRESP        = w_err_latch ? 2'b10 : 2'b00;
        BID          = latched_awid;
        
        MEMORY_WR_EN = 1'b0;
        MEMORY_WR_AD = wr_addr_reg;
        MEMORY_WDATA = WDATA;
        MEMORY_WSTRB = WSTRB;

        case (write_state)
            W_IDLE: begin
                AWREADY = 1'b1;
            end
            W_DATA: begin
                WREADY = w_err_latch ? 1'b1 : !MEMORY_WR_BUSY;
                if (WVALID && WREADY && !w_err_latch && (WSTRB != 0)) begin
                    MEMORY_WR_EN = 1'b1;
                end
            end
            W_RESP: begin
                BVALID = 1'b1;
            end
        endcase
    end

    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            write_state    <= W_IDLE;
            w_err_latch    <= 1'b0;
            latched_awid   <= {ID_WIDTH{1'b0}};
            latched_awsize <= 3'd0;
            wr_addr_reg    <= {ADDR_WIDTH{1'b0}};
        end else begin
            case (write_state)
                W_IDLE: begin
                    if (AWVALID) begin
                        write_state    <= W_DATA;
                        w_err_latch    <= aw_error_flag;
                        latched_awid   <= AWID;
                        latched_awsize <= AWSIZE;
                        wr_addr_reg    <= AWADDR;
                    end
                end
                W_DATA: begin
                    if (WVALID && WREADY) begin
                        if (!w_err_latch) wr_addr_reg <= wr_addr_reg + (1 << latched_awsize);
                        if (WLAST)        write_state <= W_RESP;
                    end
                end
                W_RESP: begin
                    if (BREADY) write_state <= W_IDLE;
                end
            endcase
        end
    end

    localparam [1:0] R_IDLE = 2'd0, R_DATA = 2'd1;
    
    reg [1:0]            read_state;
    reg                  r_err_latch;
    reg [3:0]            r_len_latch;
    reg [3:0]            read_count;
    reg [ID_WIDTH-1:0]   latched_arid;
    reg [2:0]            latched_arsize;
    reg [ADDR_WIDTH-1:0] rd_addr_reg;

    wire ar_size_err   = ((1 << ARSIZE) > (DATA_WIDTH / 8));
    wire ar_burst_err  = (ARBURST == 2'b00 && !SUPPORT_FIXED) || 
                         (ARBURST == 2'b01 && !SUPPORT_INCR)  || 
                         (ARBURST == 2'b10 && !SUPPORT_WRAP);
    wire ar_error_flag = (!ALLOW_READ) | ar_size_err | ar_burst_err;

    always @(*) begin
        ARREADY      = 1'b0;
        RVALID       = 1'b0;
        RLAST        = 1'b0;
        RRESP        = r_err_latch ? 2'b10 : 2'b00;
        RID          = latched_arid;
        RDATA        = MEMORY_RDATA;
        
        MEMORY_RD_EN = 1'b0;
        MEMORY_RD_AD = rd_addr_reg;

        case (read_state)
            R_IDLE: begin
                ARREADY = 1'b1;
            end
            R_DATA: begin
                RVALID = r_err_latch ? 1'b1 : !MEMORY_RD_BUSY;
                RLAST  = (read_count == r_len_latch) && RVALID;
                
                if (RVALID && RREADY && !r_err_latch) begin
                    MEMORY_RD_EN = 1'b1;
                end
            end
        endcase
    end

    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            read_state     <= R_IDLE;
            r_err_latch    <= 1'b0;
            r_len_latch    <= 4'd0;
            latched_arid   <= {ID_WIDTH{1'b0}};
            latched_arsize <= 3'd0;
            read_count     <= 4'd0;
            rd_addr_reg    <= {ADDR_WIDTH{1'b0}};
        end else begin
            case (read_state)
                R_IDLE: begin
                    if (ARVALID) begin
                        read_state     <= R_DATA;
                        r_err_latch    <= ar_error_flag;
                        r_len_latch    <= ARLEN;
                        latched_arid   <= ARID;
                        latched_arsize <= ARSIZE;
                        read_count     <= 4'd0;
                        rd_addr_reg    <= ARADDR;
                    end
                end
                R_DATA: begin
                    if (RVALID && RREADY) begin
                        if (!r_err_latch) rd_addr_reg <= rd_addr_reg + (1 << latched_arsize);
                        
                        if (read_count == r_len_latch) begin
                            read_state <= R_IDLE;
                        end else begin
                            read_count <= read_count + 1'b1;
                        end
                    end
                end
            endcase
        end
    end

endmodule