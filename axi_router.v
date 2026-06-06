module axi_router #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input  wire ACLK,
    input  wire ARESETn,

    input  wire [ADDR_WIDTH-1:0] M_AWADDR,
    input  wire                  M_AWVALID,
    output wire                  M_AWREADY,
    input  wire                  M_WLAST,
    input  wire                  M_WVALID,
    output wire                  M_WREADY,
    output wire [1:0]            M_BRESP,
    output wire                  M_BVALID,
    input  wire                  M_BREADY,
    input  wire [ADDR_WIDTH-1:0] M_ARADDR,
    input  wire                  M_ARVALID,
    output wire                  M_ARREADY,
    
    output wire [DATA_WIDTH-1:0] M_RDATA,
    output wire [1:0]            M_RRESP,
    output wire                  M_RLAST,
    output wire                  M_RVALID,
    input  wire                  M_RREADY,

    output wire                  MEM_AWVALID,
    input  wire                  MEM_AWREADY,
    output wire                  MEM_WVALID,
    input  wire                  MEM_WREADY,
    input  wire [1:0]            MEM_BRESP,
    input  wire                  MEM_BVALID,
    output wire                  MEM_BREADY,
    output wire                  MEM_ARVALID,
    input  wire                  MEM_ARREADY,
    input  wire [DATA_WIDTH-1:0] MEM_RDATA,
    input  wire [1:0]            MEM_RRESP,
    input  wire                  MEM_RLAST,
    input  wire                  MEM_RVALID,
    output wire                  MEM_RREADY,

    output wire [7:0]                  IO_AWVALID,
    input  wire [7:0]                  IO_AWREADY,
    output wire [7:0]                  IO_WVALID,
    input  wire [7:0]                  IO_WREADY,
    input  wire [15:0]                 IO_BRESP,  
    input  wire [7:0]                  IO_BVALID,
    output wire [7:0]                  IO_BREADY,
    output wire [7:0]                  IO_ARVALID,
    input  wire [7:0]                  IO_ARREADY,
    input  wire [(8*DATA_WIDTH)-1:0]   IO_RDATA,  
    input  wire [15:0]                 IO_RRESP,  
    input  wire [7:0]                  IO_RLAST,
    input  wire [7:0]                  IO_RVALID,
    output wire [7:0]                  IO_RREADY,

    output wire                  DMA_AWVALID,
    input  wire                  DMA_AWREADY,
    output wire                  DMA_WVALID,
    input  wire                  DMA_WREADY,
    input  wire [1:0]            DMA_BRESP,
    input  wire                  DMA_BVALID,
    output wire                  DMA_BREADY,
    output wire                  DMA_ARVALID,
    input  wire                  DMA_ARREADY,
    input  wire [DATA_WIDTH-1:0] DMA_RDATA,
    input  wire [1:0]            DMA_RRESP,
    input  wire                  DMA_RLAST,
    input  wire                  DMA_RVALID,
    output wire                  DMA_RREADY
);

    // 1. Decode the Addresses
    wire is_aw_mem = (M_AWADDR[31:28] == 4'h0);
    wire is_aw_io  = (M_AWADDR[31:28] == 4'h4);
    wire is_aw_dma = (M_AWADDR[31:28] == 4'h8);
    wire [2:0] aw_io_idx = M_AWADDR[22:20];

    wire is_ar_mem = (M_ARADDR[31:28] == 4'h0);
    wire is_ar_io  = (M_ARADDR[31:28] == 4'h4);
    wire is_ar_dma = (M_ARADDR[31:28] == 4'h8);
    wire [2:0] ar_io_idx = M_ARADDR[22:20];

    reg [1:0] w_target_type;
    reg [2:0] w_target_idx; 
    reg [1:0] r_target_type; 
    reg [2:0] r_target_idx;  

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            w_target_type <= 2'd0; w_target_idx <= 3'd0;
            r_target_type <= 2'd0; r_target_idx <= 3'd0;
        end else begin
            if (M_AWVALID && M_AWREADY) begin
                if      (is_aw_mem) w_target_type <= 2'd0;
                else if (is_aw_io)  begin w_target_type <= 2'd1; w_target_idx <= aw_io_idx; end
                else if (is_aw_dma) w_target_type <= 2'd2;
            end
            
            if (M_ARVALID && M_ARREADY) begin
                if      (is_ar_mem) r_target_type <= 2'd0;
                else if (is_ar_io)  begin r_target_type <= 2'd1; r_target_idx <= ar_io_idx; end
                else if (is_ar_dma) r_target_type <= 2'd2;
            end
        end
    end

    assign MEM_AWVALID = is_aw_mem ? M_AWVALID : 1'b0;
    assign IO_AWVALID  = is_aw_io  ? (8'b1 << aw_io_idx) & {8{M_AWVALID}} : 8'd0;
    assign DMA_AWVALID = is_aw_dma ? M_AWVALID : 1'b0;

    assign MEM_ARVALID = is_ar_mem ? M_ARVALID : 1'b0;
    assign IO_ARVALID  = is_ar_io  ? (8'b1 << ar_io_idx) & {8{M_ARVALID}} : 8'd0;
    assign DMA_ARVALID = is_ar_dma ? M_ARVALID : 1'b0;

    assign MEM_WVALID  = (w_target_type == 2'd0) ? M_WVALID : 1'b0;
    assign IO_WVALID   = (w_target_type == 2'd1) ? (8'b1 << w_target_idx) & {8{M_WVALID}} : 8'd0;
    assign DMA_WVALID  = (w_target_type == 2'd2) ? M_WVALID : 1'b0;

    assign MEM_BREADY  = (w_target_type == 2'd0) ? M_BREADY : 1'b0;
    assign IO_BREADY   = (w_target_type == 2'd1) ? (8'b1 << w_target_idx) & {8{M_BREADY}} : 8'd0;
    assign DMA_BREADY  = (w_target_type == 2'd2) ? M_BREADY : 1'b0;

    assign MEM_RREADY  = (r_target_type == 2'd0) ? M_RREADY : 1'b0;
    assign IO_RREADY   = (r_target_type == 2'd1) ? (8'b1 << r_target_idx) & {8{M_RREADY}} : 8'd0;
    assign DMA_RREADY  = (r_target_type == 2'd2) ? M_RREADY : 1'b0;

    assign M_AWREADY = is_aw_mem ? MEM_AWREADY :
                       is_aw_io  ? IO_AWREADY[aw_io_idx] :
                       is_aw_dma ? DMA_AWREADY : 1'b1;

    assign M_ARREADY = is_ar_mem ? MEM_ARREADY :
                       is_ar_io  ? IO_ARREADY[ar_io_idx] :
                       is_ar_dma ? DMA_ARREADY : 1'b1;

    assign M_WREADY  = (w_target_type == 2'd0) ? MEM_WREADY :
                       (w_target_type == 2'd1) ? IO_WREADY[w_target_idx] :
                       (w_target_type == 2'd2) ? DMA_WREADY : 1'b1;

    assign M_BVALID  = (w_target_type == 2'd0) ? MEM_BVALID :
                       (w_target_type == 2'd1) ? IO_BVALID[w_target_idx] :
                       (w_target_type == 2'd2) ? DMA_BVALID : 1'b0;

    assign M_BRESP   = (w_target_type == 2'd0) ? MEM_BRESP :
                       (w_target_type == 2'd1) ? IO_BRESP[w_target_idx*2 +: 2] :
                       (w_target_type == 2'd2) ? DMA_BRESP : 2'b11; 

    assign M_RVALID  = (r_target_type == 2'd0) ? MEM_RVALID :
                       (r_target_type == 2'd1) ? IO_RVALID[r_target_idx] :
                       (r_target_type == 2'd2) ? DMA_RVALID : 1'b0;

    assign M_RLAST   = (r_target_type == 2'd0) ? MEM_RLAST :
                       (r_target_type == 2'd1) ? IO_RLAST[r_target_idx] :
                       (r_target_type == 2'd2) ? DMA_RLAST : 1'b1;

    assign M_RRESP   = (r_target_type == 2'd0) ? MEM_RRESP :
                       (r_target_type == 2'd1) ? IO_RRESP[r_target_idx*2 +: 2] :
                       (r_target_type == 2'd2) ? DMA_RRESP : 2'b11;

    assign M_RDATA   = (r_target_type == 2'd0) ? MEM_RDATA :
                       (r_target_type == 2'd1) ? IO_RDATA[r_target_idx*DATA_WIDTH +: DATA_WIDTH] :
                       (r_target_type == 2'd2) ? DMA_RDATA : {DATA_WIDTH{1'b0}};

endmodule
