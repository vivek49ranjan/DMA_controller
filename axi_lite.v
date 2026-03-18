module axi_lite_slave #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input  wire                   ACLK,
    input  wire                   ARESETN,

    input  wire [ADDR_WIDTH-1:0]  S_AXI_AWADDR,
    input  wire                   S_AXI_AWVALID,
    output wire                   S_AXI_AWREADY,

    input  wire [DATA_WIDTH-1:0]  S_AXI_WDATA,
    input  wire [(DATA_WIDTH/8)-1:0] S_AXI_WSTRB,
    input  wire                   S_AXI_WVALID,
    output wire                   S_AXI_WREADY,

    output wire [1:0]             S_AXI_BRESP,
    output wire                   S_AXI_BVALID,
    input  wire                   S_AXI_BREADY,

    output wire                   reg_wr_en,
    output wire [ADDR_WIDTH-1:0]  reg_wr_addr,
    output wire [DATA_WIDTH-1:0]  reg_wdata
);

    reg awready_reg;
    reg wready_reg;
    reg bvalid_reg;

    assign S_AXI_AWREADY = awready_reg;
    assign S_AXI_WREADY  = wready_reg;
    assign S_AXI_BRESP   = 2'b00; 
    assign S_AXI_BVALID  = bvalid_reg;

    wire write_transaction = S_AXI_AWVALID && S_AXI_WVALID && !bvalid_reg;

    assign reg_wr_en   = write_transaction;
    assign reg_wr_addr = S_AXI_AWADDR;
    assign reg_wdata   = S_AXI_WDATA;

    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            awready_reg <= 1'b0;
            wready_reg  <= 1'b0;
            bvalid_reg  <= 1'b0;
        end else begin
            if (S_AXI_AWVALID && !awready_reg && !bvalid_reg) begin
                awready_reg <= 1'b1;
            end else begin
                awready_reg <= 1'b0;
            end

            if (S_AXI_WVALID && !wready_reg && !bvalid_reg) begin
                wready_reg <= 1'b1;
            end else begin
                wready_reg <= 1'b0;
            end

            if (write_transaction) begin
                bvalid_reg <= 1'b1;
            end else if (S_AXI_BREADY && bvalid_reg) begin
                bvalid_reg <= 1'b0;
            end
        end
    end
endmodule