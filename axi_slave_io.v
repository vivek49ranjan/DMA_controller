module axi_slave_io #(
    parameter DATA_WIDTH    = 32,
    parameter ADDR_WIDTH    = 32,
    parameter ID_WIDTH      = 4,
    parameter TX_ADDR       = 32'h4000_0000, 
    parameter RX_ADDR       = 32'h4000_0004, 
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
    output wire                      AWREADY,

    input  wire [ID_WIDTH-1:0]       WID,
    input  wire [DATA_WIDTH-1:0]     WDATA,
    input  wire [(DATA_WIDTH/8)-1:0] WSTRB,
    input  wire                      WLAST,
    input  wire                      WVALID,
    output wire                      WREADY,

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
    output wire                      ARREADY,

    output reg  [ID_WIDTH-1:0]       RID,
    output wire [DATA_WIDTH-1:0]     RDATA,
    output wire [1:0]                RRESP,
    output wire                      RLAST,
    output wire                      RVALID,
    input  wire                      RREADY,

    output wire                      TX_FIFO_WR_EN,
    output wire [DATA_WIDTH-1:0]     TX_FIFO_WDATA,
    input  wire                      TX_FIFO_FULL,

    output wire                      RX_FIFO_RD_EN,
    input  wire [DATA_WIDTH-1:0]     RX_FIFO_RDATA,
    input  wire                      RX_FIFO_EMPTY
);

 
    reg                  aw_latched;
    reg                  w_err_latch;
    reg [ID_WIDTH-1:0]   latched_awid;

    wire aw_size_err   = ((1 << AWSIZE) > (DATA_WIDTH / 8)); 
    wire aw_burst_err  = (AWBURST == 2'b00 && !SUPPORT_FIXED) || 
                         (AWBURST == 2'b01 && !SUPPORT_INCR)  || 
                         (AWBURST == 2'b10 && !SUPPORT_WRAP);
    wire aw_addr_err   = (AWADDR != TX_ADDR);
    wire aw_error_flag = (!ALLOW_WRITE) | aw_size_err | aw_burst_err | aw_addr_err;

    
    assign AWREADY = ~aw_latched && ~BVALID; 
    
    assign WREADY  = aw_latched && (w_err_latch || ~TX_FIFO_FULL);
	 
    assign TX_FIFO_WR_EN = WVALID && WREADY && !w_err_latch && (WSTRB != 0);
    assign TX_FIFO_WDATA = WDATA; 

    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            aw_latched   <= 1'b0;
            w_err_latch  <= 1'b0;
            latched_awid <= {ID_WIDTH{1'b0}};
            BID          <= {ID_WIDTH{1'b0}};
            BRESP        <= 2'b00;
            BVALID       <= 1'b0;
        end else begin
            if (BVALID && BREADY) begin
                BVALID <= 1'b0;
            end
            if (AWVALID && AWREADY) begin
                aw_latched   <= 1'b1;
                w_err_latch  <= aw_error_flag;
                latched_awid <= AWID;
            end
            if (WVALID && WREADY) begin
                if (WLAST) begin
                    aw_latched <= 1'b0;
                    BID        <= latched_awid;
                    BRESP      <= w_err_latch ? 2'b10 : 2'b00;
                    BVALID     <= 1'b1;
                end
            end
        end
    end

    reg                  ar_latched; 
    reg                  r_err_latch;
    reg [3:0]            r_len_latch;
    reg [3:0]            read_count;
    reg [ID_WIDTH-1:0]   latched_arid;

    wire ar_size_err   = ((1 << ARSIZE) > (DATA_WIDTH / 8));
    wire ar_burst_err  = (ARBURST == 2'b00 && !SUPPORT_FIXED) || 
                         (ARBURST == 2'b01 && !SUPPORT_INCR)  || 
                         (ARBURST == 2'b10 && !SUPPORT_WRAP);
    wire ar_addr_err   = (ARADDR != RX_ADDR);
    wire ar_error_flag = (!ALLOW_READ) | ar_size_err | ar_burst_err | ar_addr_err;

    assign ARREADY = ~ar_latched;
    
    assign RVALID  = ar_latched && (r_err_latch || ~RX_FIFO_EMPTY);
    
    assign RLAST   = (read_count == r_len_latch);
    assign RRESP   = r_err_latch ? 2'b10 : 2'b00;
    
    assign RDATA   = r_err_latch ? {DATA_WIDTH{1'b0}} : RX_FIFO_RDATA; 

    
    assign RX_FIFO_RD_EN = RVALID && RREADY && !r_err_latch;

    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            ar_latched   <= 1'b0;
            r_err_latch  <= 1'b0;
            r_len_latch  <= 4'd0;
            latched_arid <= {ID_WIDTH{1'b0}};
            read_count   <= 4'd0;
            RID          <= {ID_WIDTH{1'b0}};
        end else begin
            if (ARVALID && ARREADY) begin
                ar_latched   <= 1'b1;
                r_err_latch  <= ar_error_flag;
                r_len_latch  <= ARLEN;
                latched_arid <= ARID;
                read_count   <= 4'd0;
                RID          <= ARID;
            end

            if (RVALID && RREADY) begin
                if (RLAST) begin
                    ar_latched <= 1'b0; 
                end else begin
                    read_count <= read_count + 1'b1;
                end
            end
        end
    end

endmodule
