module axi_router #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4
)(
    input  wire ACLK,
    input  wire ARESETn,

    input  wire [ADDR_WIDTH-1:0] S_AWADDR,
    input  wire                  S_WLAST,
    input  wire [ADDR_WIDTH-1:0] S_ARADDR,

    input  wire                  S_AWVALID,
    output wire                  S_AWREADY,
    input  wire                  S_WVALID,
    output wire                  S_WREADY,
    output wire                  S_BVALID,
    input  wire                  S_BREADY,
    input  wire                  S_ARVALID,
    output wire                  S_ARREADY,
    output wire                  S_RVALID,
    input  wire                  S_RREADY,

    output wire [ID_WIDTH-1:0]   S_BID,
    output wire [1:0]            S_BRESP,
    output wire [ID_WIDTH-1:0]   S_RID,
    output wire [DATA_WIDTH-1:0] S_RDATA,
    output wire [1:0]            S_RRESP,
    output wire                  S_RLAST,

    output wire                  M0_AWVALID,
    input  wire                  M0_AWREADY,
    output wire                  M0_WVALID,
    input  wire                  M0_WREADY,
    input  wire                  M0_BVALID,
    output wire                  M0_BREADY,
    input  wire [ID_WIDTH-1:0]   M0_BID,
    input  wire [1:0]            M0_BRESP,
    
    output wire                  M0_ARVALID,
    input  wire                  M0_ARREADY,
    input  wire                  M0_RVALID,
    output wire                  M0_RREADY,
    input  wire [ID_WIDTH-1:0]   M0_RID,
    input  wire [DATA_WIDTH-1:0] M0_RDATA,
    input  wire [1:0]            M0_RRESP,
    input  wire                  M0_RLAST,

    output wire [7:0]                    M_IO_AWVALID,
    input  wire [7:0]                    M_IO_AWREADY,
    output wire [7:0]                    M_IO_WVALID,
    input  wire [7:0]                    M_IO_WREADY,
    input  wire [7:0]                    M_IO_BVALID,
    output wire [7:0]                    M_IO_BREADY,
    input  wire [(8*ID_WIDTH)-1:0]       M_IO_BID,
    input  wire [(8*2)-1:0]              M_IO_BRESP,
    
    output wire [7:0]                    M_IO_ARVALID,
    input  wire [7:0]                    M_IO_ARREADY,
    input  wire [7:0]                    M_IO_RVALID,
    output wire [7:0]                    M_IO_RREADY,
    input  wire [(8*ID_WIDTH)-1:0]       M_IO_RID,
    input  wire [(8*DATA_WIDTH)-1:0]     M_IO_RDATA,
    input  wire [(8*2)-1:0]              M_IO_RRESP,
    input  wire [7:0]                    M_IO_RLAST
);

    wire is_aw_m0  = (S_AWADDR[31:28] == 4'h0);
    wire is_aw_io  = (S_AWADDR[31:28] == 4'h4);
    wire [2:0] aw_io_idx = S_AWADDR[22:20];

    wire is_ar_m0  = (S_ARADDR[31:28] == 4'h0);
    wire is_ar_io  = (S_ARADDR[31:28] == 4'h4);
    wire [2:0] ar_io_idx = S_ARADDR[22:20];

    reg [3:0] w_target_fifo [0:3];
    reg [1:0] w_head, w_tail;
    reg [2:0] w_count;
    wire w_fifo_full  = (w_count == 3'd4);
    wire w_fifo_empty = (w_count == 3'd0);

    reg [3:0] b_target_fifo [0:3];
    reg [1:0] b_head, b_tail;
    reg [2:0] b_count;
    wire b_fifo_full  = (b_count == 3'd4);
    wire b_fifo_empty = (b_count == 3'd0);

    reg [3:0] r_target_fifo [0:3];
    reg [1:0] r_head, r_tail;
    reg [2:0] r_count;
    wire r_fifo_full  = (r_count == 3'd4);
    wire r_fifo_empty = (r_count == 3'd0);

   
    assign S_AWREADY = is_aw_m0 ? (M0_AWREADY && !w_fifo_full && !b_fifo_full) : 
                       is_aw_io ? (M_IO_AWREADY[aw_io_idx] && !w_fifo_full && !b_fifo_full) : 1'b0;

    assign M0_AWVALID = S_AWVALID && is_aw_m0 && !w_fifo_full && !b_fifo_full;

    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : io_aw_map
            assign M_IO_AWVALID[i] = S_AWVALID && is_aw_io && (aw_io_idx == i) && !w_fifo_full && !b_fifo_full;
        end
    endgenerate

	 always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            w_head <= 0; w_tail <= 0; w_count <= 0;
            b_head <= 0; b_tail <= 0; b_count <= 0;
        end else begin
            if (S_AWVALID && S_AWREADY) begin
                w_target_fifo[w_tail] <= is_aw_m0 ? 4'd0 : {1'b1, aw_io_idx};
                b_target_fifo[b_tail] <= is_aw_m0 ? 4'd0 : {1'b1, aw_io_idx};
                w_tail <= w_tail + 1'b1;
                b_tail <= b_tail + 1'b1;
            end
            
            if (S_WVALID && S_WREADY && S_WLAST) w_head <= w_head + 1'b1;
            if (S_BVALID && S_BREADY)            b_head <= b_head + 1'b1;

            w_count <= w_count + (S_AWVALID && S_AWREADY) - (S_WVALID && S_WREADY && S_WLAST);
            b_count <= b_count + (S_AWVALID && S_AWREADY) - (S_BVALID && S_BREADY);
        end
    end

    wire [3:0] w_target = w_target_fifo[w_head];
    wire w_is_mem       = (w_target == 4'd0);
    wire [2:0] w_io_idx = w_target[2:0];
    
    assign S_WREADY = w_fifo_empty ? 1'b0 : (w_is_mem ? M0_WREADY : M_IO_WREADY[w_io_idx]);
    assign M0_WVALID = S_WVALID && !w_fifo_empty && w_is_mem;
    
    generate
        for (i = 0; i < 8; i = i + 1) begin : io_w_map
            assign M_IO_WVALID[i] = S_WVALID && !w_fifo_empty && !w_is_mem && (w_io_idx == i);
        end
    endgenerate

    wire [3:0] b_target = b_target_fifo[b_head];
    wire b_is_mem       = (b_target == 4'd0);
    wire [2:0] b_io_idx = b_target[2:0];
    
    assign S_BVALID = b_fifo_empty ? 1'b0 : (b_is_mem ? M0_BVALID : M_IO_BVALID[b_io_idx]);
    assign S_BID    = b_is_mem ? M0_BID : M_IO_BID[b_io_idx*ID_WIDTH +: ID_WIDTH];
    assign S_BRESP  = b_is_mem ? M0_BRESP : M_IO_BRESP[b_io_idx*2 +: 2];
    
    assign M0_BREADY = S_BREADY && !b_fifo_empty && b_is_mem;
    generate
        for (i = 0; i < 8; i = i + 1) begin : io_b_map
            assign M_IO_BREADY[i] = S_BREADY && !b_fifo_empty && !b_is_mem && (b_io_idx == i);
        end
    endgenerate

    
    assign S_ARREADY = is_ar_m0 ? (M0_ARREADY && !r_fifo_full) : 
                       is_ar_io ? (M_IO_ARREADY[ar_io_idx] && !r_fifo_full) : 1'b0;

    assign M0_ARVALID = S_ARVALID && is_ar_m0 && !r_fifo_full;

    generate
        for (i = 0; i < 8; i = i + 1) begin : io_ar_map
            assign M_IO_ARVALID[i] = S_ARVALID && is_ar_io && (ar_io_idx == i) && !r_fifo_full;
        end
    endgenerate

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            r_head <= 0; r_tail <= 0; r_count <= 0;
        end else begin
            if (S_ARVALID && S_ARREADY) begin
                r_target_fifo[r_tail] <= is_ar_m0 ? 4'd0 : {1'b1, ar_io_idx};
                r_tail <= r_tail + 1'b1;
                r_count <= r_count + 1'b1;
            end
            if (S_RVALID && S_RREADY && S_RLAST) begin
                r_head <= r_head + 1'b1;
                r_count <= r_count - 1'b1;
            end
            if ((S_ARVALID && S_ARREADY) && (S_RVALID && S_RREADY && S_RLAST)) begin
                r_count <= r_count;
            end
        end
    end

    wire [3:0] r_target = r_target_fifo[r_head];
    wire r_is_mem       = (r_target == 4'd0);
    wire [2:0] r_io_idx = r_target[2:0];

    assign S_RVALID = r_fifo_empty ? 1'b0 : (r_is_mem ? M0_RVALID : M_IO_RVALID[r_io_idx]);
    assign S_RID    = r_is_mem ? M0_RID   : M_IO_RID  [r_io_idx*ID_WIDTH +: ID_WIDTH];
    assign S_RDATA  = r_is_mem ? M0_RDATA : M_IO_RDATA[r_io_idx*DATA_WIDTH +: DATA_WIDTH];
    assign S_RRESP  = r_is_mem ? M0_RRESP : M_IO_RRESP[r_io_idx*2 +: 2];
    assign S_RLAST  = r_is_mem ? M0_RLAST : M_IO_RLAST[r_io_idx];

    assign M0_RREADY = S_RREADY && !r_fifo_empty && r_is_mem;
    
    generate
        for (i = 0; i < 8; i = i + 1) begin : io_r_map
            assign M_IO_RREADY[i] = S_RREADY && !r_fifo_empty && !r_is_mem && (r_io_idx == i);
        end
    endgenerate

endmodule
