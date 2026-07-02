module axi_router #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4
)(
    input  wire ACLK,
    input  wire ARESETn,

    input  wire [ADDR_WIDTH-1:0] M_AWADDR,
    input  wire                  M_WLAST,
    input  wire [ADDR_WIDTH-1:0] M_ARADDR,

    input  wire                  M_AWVALID,
    output wire                  M_AWREADY,
    input  wire                  M_WVALID,
    output wire                  M_WREADY,
    output wire                  M_BVALID,
    input  wire                  M_BREADY,
    input  wire                  M_ARVALID,
    output wire                  M_ARREADY,
    output wire                  M_RVALID,
    input  wire                  M_RREADY,

    output wire [ID_WIDTH-1:0]   M_BID,
    output wire [1:0]            M_BRESP,
    output wire [ID_WIDTH-1:0]   M_RID,
    output wire [DATA_WIDTH-1:0] M_RDATA,
    output wire [1:0]            M_RRESP,
    output wire                  M_RLAST,

    output wire                  MEM_AWVALID,
    input  wire                  MEM_AWREADY,
    output wire                  MEM_WVALID,
    input  wire                  MEM_WREADY,
    input  wire                  MEM_BVALID,
    output wire                  MEM_BREADY,
    input  wire [ID_WIDTH-1:0]   MEM_BID,
    input  wire [1:0]            MEM_BRESP,
    
    output wire                  MEM_ARVALID,
    input  wire                  MEM_ARREADY,
    input  wire                  MEM_RVALID,
    output wire                  MEM_RREADY,
    input  wire [ID_WIDTH-1:0]   MEM_RID,
    input  wire [DATA_WIDTH-1:0] MEM_RDATA,
    input  wire [1:0]            MEM_RRESP,
    input  wire                  MEM_RLAST,

    output wire [7:0]                    IO_AWVALID,
    input  wire [7:0]                    IO_AWREADY,
    output wire [7:0]                    IO_WVALID,
    input  wire [7:0]                    IO_WREADY,
    input  wire [7:0]                    IO_BVALID,
    output wire [7:0]                    IO_BREADY,
    input  wire [(8*ID_WIDTH)-1:0]       IO_BID,
    input  wire [(8*2)-1:0]              IO_BRESP,
    
    output wire [7:0]                    IO_ARVALID,
    input  wire [7:0]                    IO_ARREADY,
    input  wire [7:0]                    IO_RVALID,
    output wire [7:0]                    IO_RREADY,
    input  wire [(8*ID_WIDTH)-1:0]       IO_RID,
    input  wire [(8*DATA_WIDTH)-1:0]     IO_RDATA,
    input  wire [(8*2)-1:0]              IO_RRESP,
    input  wire [7:0]                    IO_RLAST
);

    
    wire is_aw_mem = (M_AWADDR[31:28] == 4'h0);
    wire is_aw_io  = (M_AWADDR[31:28] == 4'h4);
    wire [2:0] aw_io_idx = M_AWADDR[22:20];

    wire is_ar_mem = (M_ARADDR[31:28] == 4'h0);
    wire is_ar_io  = (M_ARADDR[31:28] == 4'h4);
    wire [2:0] ar_io_idx = M_ARADDR[22:20];

   
    reg [3:0] wr_target_ram [0:3];
    reg [2:0] aw_ptr, w_ptr, b_ptr; 

    reg [3:0] rd_target_ram [0:3];
    reg [2:0] ar_ptr, r_ptr;

    wire wr_full  = (aw_ptr[1:0] == b_ptr[1:0]) && (aw_ptr[2] != b_ptr[2]);
    wire w_empty  = (w_ptr == aw_ptr);
    wire b_empty  = (b_ptr == aw_ptr);

    wire rd_full  = (ar_ptr[1:0] == r_ptr[1:0]) && (ar_ptr[2] != r_ptr[2]);
    wire r_empty  = (r_ptr == ar_ptr);

  
    assign M_AWREADY  = is_aw_mem ? (MEM_AWREADY && !wr_full) : 
                        is_aw_io ? (IO_AWREADY[aw_io_idx] && !wr_full) : 1'b0;
    assign MEM_AWVALID = M_AWVALID && is_aw_mem && !wr_full;

    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : io_aw_map
            assign IO_AWVALID[i] = M_AWVALID && is_aw_io && (aw_io_idx == i) && !wr_full;
        end
    endgenerate

    assign M_ARREADY  = is_ar_mem ? (MEM_ARREADY && !rd_full) : 
                        is_ar_io ? (IO_ARREADY[ar_io_idx] && !rd_full) : 1'b0;
    assign MEM_ARVALID = M_ARVALID && is_ar_mem && !rd_full;

    generate
        for (i = 0; i < 8; i = i + 1) begin : io_ar_map
            assign IO_ARVALID[i] = M_ARVALID && is_ar_io && (ar_io_idx == i) && !rd_full;
        end
    endgenerate

 
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            aw_ptr <= 0; w_ptr <= 0; b_ptr <= 0;
            ar_ptr <= 0; r_ptr <= 0;
        end else begin
            if (M_AWVALID && M_AWREADY) begin
                wr_target_ram[aw_ptr[1:0]] <= is_aw_mem ? 4'd0 : {1'b1, aw_io_idx};
                aw_ptr <= aw_ptr + 1'b1;
            end
            
            if (M_WVALID && M_WREADY && M_WLAST) w_ptr <= w_ptr + 1'b1;
            
            if (M_BVALID && M_BREADY)            b_ptr <= b_ptr + 1'b1;

            if (M_ARVALID && M_ARREADY) begin
                rd_target_ram[ar_ptr[1:0]] <= is_ar_mem ? 4'd0 : {1'b1, ar_io_idx};
                ar_ptr <= ar_ptr + 1'b1;
            end
            if (M_RVALID && M_RREADY && M_RLAST) r_ptr <= r_ptr + 1'b1;
        end
    end


    wire [3:0] w_target = wr_target_ram[w_ptr[1:0]];
    wire w_is_mem       = (w_target == 4'd0);
    wire [2:0] w_io_idx = w_target[2:0];
    
    assign M_WREADY  = w_empty ? 1'b0 : (w_is_mem ? MEM_WREADY : IO_WREADY[w_io_idx]);
    assign MEM_WVALID = M_WVALID && !w_empty && w_is_mem;
    
    generate
        for (i = 0; i < 8; i = i + 1) begin : io_w_map
            assign IO_WVALID[i] = M_WVALID && !w_empty && !w_is_mem && (w_io_idx == i);
        end
    endgenerate

    wire [3:0] b_target = wr_target_ram[b_ptr[1:0]];
    wire b_is_mem       = (b_target == 4'd0);
    wire [2:0] b_io_idx = b_target[2:0];
    
    assign M_BVALID  = b_empty ? 1'b0 : (b_is_mem ? MEM_BVALID : IO_BVALID[b_io_idx]);
    assign M_BID     = b_is_mem ? MEM_BID : IO_BID[b_io_idx*ID_WIDTH +: ID_WIDTH];
    assign M_BRESP   = b_is_mem ? MEM_BRESP : IO_BRESP[b_io_idx*2 +: 2];
    assign MEM_BREADY = M_BREADY && !b_empty && b_is_mem;
    
    generate
        for (i = 0; i < 8; i = i + 1) begin : io_b_map
            assign IO_BREADY[i] = M_BREADY && !b_empty && !b_is_mem && (b_io_idx == i);
        end
    endgenerate

    wire [3:0] r_target = rd_target_ram[r_ptr[1:0]];
    wire r_is_mem       = (r_target == 4'd0);
    wire [2:0] r_io_idx = r_target[2:0];

    assign M_RVALID  = r_empty ? 1'b0 : (r_is_mem ? MEM_RVALID : IO_RVALID[r_io_idx]);
    assign M_RID     = r_is_mem ? MEM_RID   : IO_RID  [r_io_idx*ID_WIDTH +: ID_WIDTH];
    assign M_RDATA   = r_is_mem ? MEM_RDATA : IO_RDATA[r_io_idx*DATA_WIDTH +: DATA_WIDTH];
    assign M_RRESP   = r_is_mem ? MEM_RRESP : IO_RRESP[r_io_idx*2 +: 2];
    assign M_RLAST   = r_is_mem ? MEM_RLAST : IO_RLAST[r_io_idx];
    assign MEM_RREADY = M_RREADY && !r_empty && r_is_mem;
    
    generate
        for (i = 0; i < 8; i = i + 1) begin : io_r_map
            assign IO_RREADY[i] = M_RREADY && !r_empty && !r_is_mem && (r_io_idx == i);
        end
    endgenerate

endmodule
