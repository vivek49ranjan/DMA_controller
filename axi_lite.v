module axi_lite_slave #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input  wire                      ACLK,
    input  wire                      ARESETN,

    input  wire [ADDR_WIDTH-1:0]     S_AXI_AWADDR,
    input  wire                      S_AXI_AWVALID,
    output wire                      S_AXI_AWREADY,

    input  wire [DATA_WIDTH-1:0]     S_AXI_WDATA,
    input  wire [(DATA_WIDTH/8)-1:0] S_AXI_WSTRB,
    input  wire                      S_AXI_WVALID,
    output wire                      S_AXI_WREADY,

    output wire [1:0]                S_AXI_BRESP,
    output reg                       S_AXI_BVALID,
    input  wire                      S_AXI_BREADY,

    output wire                      reg_wr_en,
    output wire [ADDR_WIDTH-1:0]     reg_wr_addr,
    output wire [DATA_WIDTH-1:0]     reg_wdata
);

    reg aw_latched;
    reg w_latched;
    
    reg [ADDR_WIDTH-1:0] awaddr_reg;
    reg [DATA_WIDTH-1:0] wdata_reg;

    assign S_AXI_AWREADY = ~aw_latched && ~S_AXI_BVALID;
    assign S_AXI_WREADY  = ~w_latched  && ~S_AXI_BVALID;
    
    assign S_AXI_BRESP   = 2'b00; 

    wire aw_complete = aw_latched || (S_AXI_AWVALID && S_AXI_AWREADY);
    wire w_complete  = w_latched  || (S_AXI_WVALID && S_AXI_WREADY);
    
    assign reg_wr_en   = aw_complete && w_complete && ~S_AXI_BVALID;
    
    assign reg_wr_addr = aw_latched ? awaddr_reg : S_AXI_AWADDR;
    assign reg_wdata   = w_latched  ? wdata_reg  : S_AXI_WDATA;
	 
    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            aw_latched   <= 1'b0;
            w_latched    <= 1'b0;
            S_AXI_BVALID <= 1'b0;
            awaddr_reg   <= {ADDR_WIDTH{1'b0}};
            wdata_reg    <= {DATA_WIDTH{1'b0}};
        end else begin
            if (S_AXI_BVALID && S_AXI_BREADY) begin
                S_AXI_BVALID <= 1'b0;
            end

            if (S_AXI_AWVALID && S_AXI_AWREADY) begin
                aw_latched <= 1'b1;
                awaddr_reg <= S_AXI_AWADDR;
            end

            if (S_AXI_WVALID && S_AXI_WREADY) begin
                w_latched <= 1'b1;
                wdata_reg <= S_AXI_WDATA;
            end

            if (reg_wr_en) begin
                S_AXI_BVALID <= 1'b1;
                aw_latched   <= 1'b0;
                w_latched    <= 1'b0;
            end
        end
    end

endmodule
