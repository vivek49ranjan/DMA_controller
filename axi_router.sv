import dmac_pkg::*;

module axi_router #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4
)(
    axi_if.slave  m_axi,
    axi_if.master mem_axi,
    axi_if.master io_axi [0:7]
);
    genvar i;

    logic is_aw_mem;
    logic is_aw_io;
    logic [2:0] aw_io_idx;

    assign is_aw_mem = (m_axi.awaddr[31:28] == 4'h0);
    assign is_aw_io  = (m_axi.awaddr[31:28] == 4'h4);
    assign aw_io_idx = m_axi.awaddr[27:25]; 

    logic is_ar_mem;
    logic is_ar_io;
    logic [2:0] ar_io_idx;

    assign is_ar_mem = (m_axi.araddr[31:28] == 4'h0);
    assign is_ar_io  = (m_axi.araddr[31:28] == 4'h4);
    assign ar_io_idx = m_axi.araddr[27:25]; 

    logic [3:0] wr_target_ram [0:3];
    logic [2:0] aw_ptr, w_ptr, b_ptr; 

    logic [3:0] rd_target_ram [0:3];
    logic [2:0] ar_ptr, r_ptr;

    logic wr_full, w_empty, b_empty;
    logic rd_full, r_empty;

    assign wr_full = (aw_ptr[1:0] == b_ptr[1:0]) && (aw_ptr[2] != b_ptr[2]);
    assign w_empty = (w_ptr == aw_ptr);
    assign b_empty = (b_ptr == aw_ptr);

    assign rd_full = (ar_ptr[1:0] == r_ptr[1:0]) && (ar_ptr[2] != r_ptr[2]);
    assign r_empty = (r_ptr == ar_ptr);

    logic [7:0] io_awready_bus;
    generate
        for (i = 0; i < 8; i = i + 1) begin : gen_awready
            assign io_awready_bus[i] = io_axi[i].awready;
        end
    endgenerate

    assign m_axi.awready = is_aw_mem ? (mem_axi.awready && !wr_full) : 
                           is_aw_io  ? (io_awready_bus[aw_io_idx] && !wr_full) : 
                           !wr_full; 
                           
    assign mem_axi.awvalid = m_axi.awvalid && is_aw_mem && !wr_full;
    assign mem_axi.awaddr  = m_axi.awaddr;
    assign mem_axi.awid    = m_axi.awid;
    assign mem_axi.awlen   = m_axi.awlen;
    assign mem_axi.awsize  = m_axi.awsize;
    assign mem_axi.awburst = m_axi.awburst;

    generate
        for (i = 0; i < 8; i = i + 1) begin : io_aw_map
            assign io_axi[i].awvalid = m_axi.awvalid && is_aw_io && (aw_io_idx == i) && !wr_full;
            assign io_axi[i].awaddr  = m_axi.awaddr;
            assign io_axi[i].awid    = m_axi.awid;
            assign io_axi[i].awlen   = m_axi.awlen;
            assign io_axi[i].awsize  = m_axi.awsize;
            assign io_axi[i].awburst = m_axi.awburst;
        end
    endgenerate

    logic [7:0] io_arready_bus;
    generate
        for (i = 0; i < 8; i = i + 1) begin : gen_arready
            assign io_arready_bus[i] = io_axi[i].arready;
        end
    endgenerate

    assign m_axi.arready = is_ar_mem ? (mem_axi.arready && !rd_full) : 
                           is_ar_io  ? (io_arready_bus[ar_io_idx] && !rd_full) : 
                           !rd_full; 
                           
    assign mem_axi.arvalid = m_axi.arvalid && is_ar_mem && !rd_full;
    assign mem_axi.araddr  = m_axi.araddr;
    assign mem_axi.arid    = m_axi.arid;
    assign mem_axi.arlen   = m_axi.arlen;
    assign mem_axi.arsize  = m_axi.arsize;
    assign mem_axi.arburst = m_axi.arburst;

    generate
        for (i = 0; i < 8; i = i + 1) begin : io_ar_map
            assign io_axi[i].arvalid = m_axi.arvalid && is_ar_io && (ar_io_idx == i) && !rd_full;
            assign io_axi[i].araddr  = m_axi.araddr;
            assign io_axi[i].arid    = m_axi.arid;
            assign io_axi[i].arlen   = m_axi.arlen;
            assign io_axi[i].arsize  = m_axi.arsize;
            assign io_axi[i].arburst = m_axi.arburst;
        end
    endgenerate

    always_ff @(posedge m_axi.clk or negedge m_axi.resetn) begin
        if (!m_axi.resetn) begin
            aw_ptr <= 0; w_ptr <= 0; b_ptr <= 0;
            ar_ptr <= 0; r_ptr <= 0;
        end else begin
            if (m_axi.awvalid && m_axi.awready) begin
                wr_target_ram[aw_ptr[1:0]] <= is_aw_mem ? 4'd0 : is_aw_io ? {1'b1, aw_io_idx} : 4'hF;
                aw_ptr <= aw_ptr + 1'b1;
            end
            
            if (m_axi.wvalid && m_axi.wready && m_axi.wlast) w_ptr <= w_ptr + 1'b1;
            
            if (m_axi.bvalid && m_axi.bready) b_ptr <= b_ptr + 1'b1;

            if (m_axi.arvalid && m_axi.arready) begin
                rd_target_ram[ar_ptr[1:0]] <= is_ar_mem ? 4'd0 : is_ar_io ? {1'b1, ar_io_idx} : 4'hF;
                ar_ptr <= ar_ptr + 1'b1;
            end
            
            if (m_axi.rvalid && m_axi.rready && m_axi.rlast) r_ptr <= r_ptr + 1'b1;
        end
    end

    logic [3:0] w_target;
    logic       w_is_mem, w_is_err_targ;
    logic [2:0] w_io_idx;
    
    assign w_target       = wr_target_ram[w_ptr[1:0]];
    assign w_is_mem       = (w_target == 4'd0);
    assign w_is_err_targ  = (w_target == 4'hF);
    assign w_io_idx       = w_target[2:0];

    logic [7:0] io_wready_bus;
    generate
        for (i = 0; i < 8; i = i + 1) begin : gen_wready
            assign io_wready_bus[i] = io_axi[i].wready;
        end
    endgenerate
    
    assign m_axi.wready   = w_empty ? 1'b0 : (w_is_mem ? mem_axi.wready : w_is_err_targ ? 1'b1 : io_wready_bus[w_io_idx]);
    assign mem_axi.wvalid = m_axi.wvalid && !w_empty && w_is_mem;
    assign mem_axi.wdata  = m_axi.wdata;
    assign mem_axi.wstrb  = m_axi.wstrb;
    assign mem_axi.wlast  = m_axi.wlast;
    
    generate
        for (i = 0; i < 8; i = i + 1) begin : io_w_map
            assign io_axi[i].wvalid = m_axi.wvalid && !w_empty && !w_is_mem && !w_is_err_targ && (w_io_idx == i);
            assign io_axi[i].wdata  = m_axi.wdata;
            assign io_axi[i].wstrb  = m_axi.wstrb;
            assign io_axi[i].wlast  = m_axi.wlast;
        end
    endgenerate

    logic [3:0] b_target;
    logic       b_is_mem, b_is_err_targ;
    logic [2:0] b_io_idx;
    
    assign b_target       = wr_target_ram[b_ptr[1:0]];
    assign b_is_mem       = (b_target == 4'd0);
    assign b_is_err_targ  = (b_target == 4'hF);
    assign b_io_idx       = b_target[2:0];
    
    logic err_bvalid;
    assign err_bvalid = (w_ptr != b_ptr);
    
    logic [7:0] io_bvalid_bus;
    logic [ID_WIDTH-1:0] io_bid_bus [0:7];
    logic [1:0] io_bresp_bus [0:7];
    generate
        for (i = 0; i < 8; i = i + 1) begin : gen_b_buses
            assign io_bvalid_bus[i] = io_axi[i].bvalid;
            assign io_bid_bus[i]    = io_axi[i].bid;
            assign io_bresp_bus[i]  = io_axi[i].bresp;
        end
    endgenerate

    assign m_axi.bvalid   = b_empty ? 1'b0 : (b_is_mem ? mem_axi.bvalid : b_is_err_targ ? err_bvalid : io_bvalid_bus[b_io_idx]);
    assign m_axi.bid      = b_is_err_targ ? {ID_WIDTH{1'b0}} : (b_is_mem ? mem_axi.bid : io_bid_bus[b_io_idx]);
    assign m_axi.bresp    = b_is_err_targ ? 2'b11 : (b_is_mem ? mem_axi.bresp : io_bresp_bus[b_io_idx]); 
    assign mem_axi.bready = m_axi.bready && !b_empty && b_is_mem;
    
    generate
        for (i = 0; i < 8; i = i + 1) begin : io_b_map
            assign io_axi[i].bready = m_axi.bready && !b_empty && !b_is_mem && !b_is_err_targ && (b_io_idx == i);
        end
    endgenerate

    logic [3:0] r_target;
    logic       r_is_mem, r_is_err_targ;
    logic [2:0] r_io_idx;

    assign r_target       = rd_target_ram[r_ptr[1:0]];
    assign r_is_mem       = (r_target == 4'd0);
    assign r_is_err_targ  = (r_target == 4'hF);
    assign r_io_idx       = r_target[2:0];

    logic [7:0] io_rvalid_bus, io_rlast_bus;
    logic [ID_WIDTH-1:0] io_rid_bus [0:7];
    logic [DATA_WIDTH-1:0] io_rdata_bus [0:7];
    logic [1:0] io_rresp_bus [0:7];
    generate
        for (i = 0; i < 8; i = i + 1) begin : gen_r_buses
            assign io_rvalid_bus[i] = io_axi[i].rvalid;
            assign io_rlast_bus[i]  = io_axi[i].rlast;
            assign io_rid_bus[i]    = io_axi[i].rid;
            assign io_rdata_bus[i]  = io_axi[i].rdata;
            assign io_rresp_bus[i]  = io_axi[i].rresp;
        end
    endgenerate

    assign m_axi.rvalid   = r_empty ? 1'b0 : (r_is_mem ? mem_axi.rvalid : r_is_err_targ ? 1'b1 : io_rvalid_bus[r_io_idx]);
    assign m_axi.rid      = r_is_err_targ ? {ID_WIDTH{1'b0}} : (r_is_mem ? mem_axi.rid : io_rid_bus[r_io_idx]);
    assign m_axi.rdata    = r_is_err_targ ? {DATA_WIDTH{1'b0}} : (r_is_mem ? mem_axi.rdata : io_rdata_bus[r_io_idx]);
    assign m_axi.rresp    = r_is_err_targ ? 2'b11 : (r_is_mem ? mem_axi.rresp : io_rresp_bus[r_io_idx]); 
    assign m_axi.rlast    = r_is_err_targ ? 1'b1 : (r_is_mem ? mem_axi.rlast : io_rlast_bus[r_io_idx]);
    
    assign mem_axi.rready = m_axi.rready && !r_empty && r_is_mem;
    
    generate
        for (i = 0; i < 8; i = i + 1) begin : io_r_map
            assign io_axi[i].rready = m_axi.rready && !r_empty && !r_is_mem && !r_is_err_targ && (r_io_idx == i);
        end
    endgenerate

endmodule
