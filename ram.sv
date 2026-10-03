import dmac_pkg::*;

module ram #(
    parameter DEPTH = 1024,
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter MEM_FILE = "/home/debian/Documents/project/SG_DMA/tb/mem.hex"
)(
    input  logic                      clk,
    input  logic                      wr_en,
    input  logic [ADDR_WIDTH-1:0]     wr_addr,
    input  logic [DATA_WIDTH-1:0]     wdata,
    input  logic [(DATA_WIDTH/8)-1:0] wstrb,
    input  logic                      rd_en,
    input  logic [ADDR_WIDTH-1:0]     rd_addr,
    output logic [DATA_WIDTH-1:0]     rdata
);
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    initial begin
        $readmemh(MEM_FILE, mem);
    end

    assign rdata = mem[rd_addr >> 2];

    always_ff @(posedge clk) begin
        if (wr_en) begin
            if (wstrb[0]) mem[wr_addr >> 2][7:0]   <= wdata[7:0];
            if (wstrb[1]) mem[wr_addr >> 2][15:8]  <= wdata[15:8];
            if (wstrb[2]) mem[wr_addr >> 2][23:16] <= wdata[23:16];
            if (wstrb[3]) mem[wr_addr >> 2][31:24] <= wdata[31:24];
        end
    end
endmodule
