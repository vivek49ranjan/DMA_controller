 ram #(
    parameter DEPTH = 8192,
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter MEM_FILE = "/home/debian/Documents/project/dma_controller/tb/mem.hex"
)(
    input  wire                      clk,
    input  wire                      wr_en,
    input  wire [ADDR_WIDTH-1:0]     wr_addr,
    input  wire [DATA_WIDTH-1:0]     wdata,
    input  wire [(DATA_WIDTH/8)-1:0] wstrb,
    input  wire                      rd_en,
    input  wire [ADDR_WIDTH-1:0]     rd_addr,
    output wire [DATA_WIDTH-1:0]     rdata
);

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    initial begin
        $readmemh(MEM_FILE, mem);
    end

    assign rdata = mem[rd_addr >> 2];

    always @(posedge clk) begin
        if (wr_en) begin
            if (wstrb[0]) mem[wr_addr >> 2][7:0]   <= wdata[7:0];
            if (wstrb[1]) mem[wr_addr >> 2][15:8]  <= wdata[15:8];
            if (wstrb[2]) mem[wr_addr >> 2][23:16] <= wdata[23:16];
            if (wstrb[3]) mem[wr_addr >> 2][31:24] <= wdata[31:24];
        end
    end

endmodule
