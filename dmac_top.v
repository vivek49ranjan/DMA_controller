module dmac_top #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4
)(
    input  wire                               clk,
    input  wire                               resetn,
    
    output wire [7:0]                         tb_io_tx_wr_en,
    output wire [(8*DATA_WIDTH)-1:0]          tb_io_tx_data,
    
    output wire [7:0]                         tb_io_rx_rd_en,
    input  wire [(8*DATA_WIDTH)-1:0]          tb_io_rx_data,
    input  wire [7:0]                         tb_io_rx_empty,

    input  wire [ADDR_WIDTH-1:0]              s_axi_awaddr,
    input  wire                               s_axi_awvalid,
    output wire                               s_axi_awready,
    input  wire [DATA_WIDTH-1:0]              s_axi_wdata,
    input  wire [(DATA_WIDTH/8)-1:0]          s_axi_wstrb,
    input  wire                               s_axi_wvalid,
    output wire                               s_axi_wready,
    output wire [1:0]                         s_axi_bresp,
    output wire                               s_axi_bvalid,
    input  wire                               s_axi_bready,
    
    output wire                               cpu_intr
);

    
    wire [(8*DATA_WIDTH)-1:0]     router_tx_tdata;
    wire [(8*(DATA_WIDTH/8))-1:0] router_tx_tkeep;
    wire [7:0]                    router_tx_tvalid, router_tx_tlast, router_tx_tready;

    wire [(8*DATA_WIDTH)-1:0]     router_rx_tdata;
    wire [7:0]                    router_rx_tvalid, router_rx_tlast, router_rx_tready;

    wire [ID_WIDTH-1:0]       m_awid, m_wid, m_arid, m_bid, m_rid;
    wire [ADDR_WIDTH-1:0]     m_awaddr, m_araddr;
    wire [3:0]                m_awlen, m_arlen;
    wire [2:0]                m_awsize, m_arsize;
    wire [1:0]                m_awburst, m_arburst;
    wire [(DATA_WIDTH/8)-1:0] m_wstrb;
    wire [DATA_WIDTH-1:0]     m_wdata, m_rdata;
    wire                      m_wlast, m_awvalid, m_awready, m_wvalid, m_wready;
    wire                      m_bvalid, m_bready, m_arvalid, m_arready, m_rvalid, m_rready, m_rlast;
    wire [1:0]                m_bresp, m_rresp;

    wire                      mem_axi_awvalid, mem_axi_awready, mem_axi_wvalid, mem_axi_wready;
    wire                      mem_axi_bvalid, mem_axi_bready, mem_axi_arvalid, mem_axi_arready;
    wire                      mem_axi_rvalid, mem_axi_rready, mem_axi_rlast;
    wire [1:0]                mem_axi_bresp, mem_axi_rresp;
    wire [DATA_WIDTH-1:0]     mem_axi_rdata;

    wire                      mem_wr_en, mem_rd_en;
    wire [ADDR_WIDTH-1:0]     mem_wr_ad, mem_rd_ad;
    wire [DATA_WIDTH-1:0]     mem_wdata, mem_rdata;
    wire [(DATA_WIDTH/8)-1:0] mem_wstrb;

    wire [ADDR_WIDTH-1:0]     cmd_addr;
    wire [15:0]               cmd_len;
    wire [2:0]                cmd_size;
    wire                      cmd_rnw, cmd_valid, cmd_error;
    wire                      read_cmd_ready, write_cmd_ready, read_cmd_done, write_cmd_done;
    wire [DATA_WIDTH-1:0]     tx_data, rx_data;
    wire                      tx_valid, tx_ready, rx_valid, rx_ready;
    wire                      fifo_wr_en, fifo_rd_en, fifo_full, fifo_empty;
    wire [DATA_WIDTH-1:0]     fifo_wdata, fifo_rdata;
    wire                      reg_wr_en, reg_rd_en;
    wire [ADDR_WIDTH-1:0]     reg_wr_addr, reg_rd_addr;
    wire [DATA_WIDTH-1:0]     reg_wdata, reg_rdata;

    wire reset_high = ~resetn; 

    dmac_controller #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)
    ) dma_ctrl_inst (
        .clk(clk),                       .resetn(resetn),
        .cmd_addr(cmd_addr),             .cmd_len(cmd_len),
        .cmd_size(cmd_size),             .cmd_rnw(cmd_rnw),
        .cmd_valid(cmd_valid),           .read_cmd_ready(read_cmd_ready),
        .write_cmd_ready(write_cmd_ready),.read_cmd_done(read_cmd_done),
        .write_cmd_done(write_cmd_done), .cmd_error(cmd_error),
        .tx_data(tx_data),               .tx_valid(tx_valid),      .tx_ready(tx_ready),
        .rx_data(rx_data),               .rx_valid(rx_valid),      .rx_ready(rx_ready),
        .cpu_intr(cpu_intr),             .reg_wr_en(reg_wr_en),    .reg_wr_addr(reg_wr_addr),
        .reg_wdata(reg_wdata),           .reg_rd_en(reg_rd_en),    .reg_rd_addr(reg_rd_addr),
        .reg_rdata(reg_rdata),           .fifo_wr_en(fifo_wr_en),  .fifo_wdata(fifo_wdata),
        .fifo_full(fifo_full),           .fifo_rd_en(fifo_rd_en),  .fifo_rdata(fifo_rdata),
        .fifo_empty(fifo_empty)
    );

    fifo #(
        .D_size(32), .A_size(4) 
    ) internal_fifo (
        .w_clk(clk),               .r_clk(clk),
        .w_reset(reset_high),      .r_reset(reset_high),
        .w_inc(fifo_wr_en),        .r_inc(fifo_rd_en),
        .write_data(fifo_wdata),   .read_data(fifo_rdata),
        .full(fifo_full),          .empty(fifo_empty)
    );

    axi_master #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH)
    ) axi_master_inst (
        .ACLK(clk),                .ARESETn(resetn),
        .cmd_addr(cmd_addr),       .cmd_len(cmd_len),
        .cmd_size(cmd_size),       .cmd_rnw(cmd_rnw),         .cmd_valid(cmd_valid),
        .read_cmd_ready(read_cmd_ready), .write_cmd_ready(write_cmd_ready),
        .read_cmd_done(read_cmd_done),   .write_cmd_done(write_cmd_done),
        .cmd_error(cmd_error),
        .tx_data(tx_data),         .tx_valid(tx_valid),      .tx_ready(tx_ready),
        .rx_data(rx_data),         .rx_valid(rx_valid),      .rx_ready(rx_ready),
        
        .AWID(m_awid), .AWADDR(m_awaddr), .AWLEN(m_awlen), .AWSIZE(m_awsize), .AWBURST(m_awburst),
        .AWVALID(m_awvalid), .AWREADY(m_awready),
        .WID(m_wid), .WDATA(m_wdata), .WSTRB(m_wstrb), .WLAST(m_wlast),
        .WVALID(m_wvalid), .WREADY(m_wready),
        .BID(m_bid), .BRESP(m_bresp), .BVALID(m_bvalid), .BREADY(m_bready),
        .ARID(m_arid), .ARADDR(m_araddr), .ARLEN(m_arlen), .ARSIZE(m_arsize), .ARBURST(m_arburst),
        .ARVALID(m_arvalid), .ARREADY(m_arready),
        .RID(m_rid), .RDATA(m_rdata), .RRESP(m_rresp), .RLAST(m_rlast),
        .RVALID(m_rvalid), .RREADY(m_rready)
    );

    
    axi_router #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)
    ) router_inst (
        .ACLK(clk), .ARESETn(resetn),
        
        .M_AWADDR(m_awaddr), .M_AWLEN(m_awlen), .M_AWVALID(m_awvalid), .M_AWREADY(m_awready),
        .M_WDATA(m_wdata),   .M_WSTRB(m_wstrb), .M_WLAST(m_wlast),     .M_WVALID(m_wvalid), .M_WREADY(m_wready),
        .M_BRESP(m_bresp),   .M_BVALID(m_bvalid), .M_BREADY(m_bready),
        .M_ARADDR(m_araddr), .M_ARLEN(m_arlen), .M_ARVALID(m_arvalid), .M_ARREADY(m_arready),
        .M_RDATA(m_rdata),   .M_RRESP(m_rresp), .M_RLAST(m_rlast),     .M_RVALID(m_rvalid), .M_RREADY(m_rready),
        
        .MEM_AWVALID(mem_axi_awvalid), .MEM_AWREADY(mem_axi_awready), 
        .MEM_WVALID(mem_axi_wvalid),   .MEM_WREADY(mem_axi_wready),
        .MEM_BRESP(mem_axi_bresp),     .MEM_BVALID(mem_axi_bvalid), .MEM_BREADY(mem_axi_bready),
        .MEM_ARVALID(mem_axi_arvalid), .MEM_ARREADY(mem_axi_arready), 
        .MEM_RDATA(mem_axi_rdata),     .MEM_RRESP(mem_axi_rresp),
        .MEM_RLAST(mem_axi_rlast),     .MEM_RVALID(mem_axi_rvalid), .MEM_RREADY(mem_axi_rready),
        
        .m_tdata(router_tx_tdata), .m_tkeep(router_tx_tkeep), .m_tvalid(router_tx_tvalid), 
        .m_tlast(router_tx_tlast), .m_tready(router_tx_tready),
        .s_tdata(router_rx_tdata), .s_tvalid(router_rx_tvalid), .s_tlast(router_rx_tlast), 
        .s_tready(router_rx_tready)
    );

    
    axi_slave_memory #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)
    ) main_memory_inst (
        .ACLK(clk), .ARESETN(resetn),
        
        .AWID(m_awid), .AWADDR(m_awaddr), .AWLEN(m_awlen), .AWSIZE(m_awsize), .AWBURST(m_awburst),
        .WID(m_wid),   .WDATA(m_wdata),   .WSTRB(m_wstrb), .WLAST(m_wlast),
        .ARID(m_arid), .ARADDR(m_araddr), .ARLEN(m_arlen), .ARSIZE(m_arsize), .ARBURST(m_arburst),
        
        .AWVALID(mem_axi_awvalid), .AWREADY(mem_axi_awready),
        .WVALID(mem_axi_wvalid),   .WREADY(mem_axi_wready),
        .BID(),                    .BRESP(mem_axi_bresp),   .BVALID(mem_axi_bvalid), .BREADY(mem_axi_bready),
        .ARVALID(mem_axi_arvalid), .ARREADY(mem_axi_arready),
        .RID(),                    .RDATA(mem_axi_rdata),   .RRESP(mem_axi_rresp),   .RLAST(mem_axi_rlast), .RVALID(mem_axi_rvalid), .RREADY(mem_axi_rready),
        
        .MEMORY_WR_EN(mem_wr_en), .MEMORY_WR_AD(mem_wr_ad), .MEMORY_WDATA(mem_wdata), .MEMORY_WSTRB(mem_wstrb),
        .MEMORY_RD_EN(mem_rd_en), .MEMORY_RD_AD(mem_rd_ad), .MEMORY_RDATA(mem_rdata),
        .MEMORY_WR_BUSY(1'b0),    .MEMORY_RD_BUSY(1'b0) 
    );

    ram #(
        .DEPTH(1024),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) internal_sram_inst (
        .clk(clk),
        .wr_en(mem_wr_en),
        .wr_addr(mem_wr_ad),
        .wdata(mem_wdata),
        .wstrb(mem_wstrb),
        .rd_en(mem_rd_en),
        .rd_addr(mem_rd_ad),
        .rdata(mem_rdata)
    );

    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : io_array
            axi_stream_io #(
                .DATA_WIDTH(DATA_WIDTH)
            ) io_inst (
                .clk(clk), .resetn(resetn),
                
                .s_tdata (router_tx_tdata [i*DATA_WIDTH +: DATA_WIDTH]),
                .s_tkeep (router_tx_tkeep [i*(DATA_WIDTH/8) +: (DATA_WIDTH/8)]),
                .s_tvalid(router_tx_tvalid[i]),
                .s_tlast (router_tx_tlast [i]),
                .s_tready(router_tx_tready[i]),
                
                .m_tdata (router_rx_tdata [i*DATA_WIDTH +: DATA_WIDTH]),
                .m_tkeep (), 
                .m_tvalid(router_rx_tvalid[i]),
                .m_tlast (router_rx_tlast [i]),
                .m_tready(router_rx_tready[i]),
                
                .hw_tx_wr_en(tb_io_tx_wr_en[i]),
                .hw_tx_wdata(tb_io_tx_data [i*DATA_WIDTH +: DATA_WIDTH]),
                .hw_tx_full(1'b0), 
                
                .hw_rx_rd_en(tb_io_rx_rd_en[i]),
                .hw_rx_rdata(tb_io_rx_data [i*DATA_WIDTH +: DATA_WIDTH]),
                .hw_rx_empty(tb_io_rx_empty[i])
            );
        end
    endgenerate

   
    axi_lite_slave #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) axi_lite_inst (
        .ACLK(clk),                    .ARESETN(resetn),
        .S_AXI_AWADDR(s_axi_awaddr),   .S_AXI_AWVALID(s_axi_awvalid), .S_AXI_AWREADY(s_axi_awready),
        .S_AXI_WDATA(s_axi_wdata),     .S_AXI_WSTRB(s_axi_wstrb),
        .S_AXI_WVALID(s_axi_wvalid),   .S_AXI_WREADY(s_axi_wready),
        .S_AXI_BRESP(s_axi_bresp),     .S_AXI_BVALID(s_axi_bvalid),   .S_AXI_BREADY(s_axi_bready),
        
        .reg_wr_en(reg_wr_en),         .reg_wr_addr(reg_wr_addr),     .reg_wdata(reg_wdata)
    );

    assign reg_rd_en   = 1'b0; 
    assign reg_rd_addr = {ADDR_WIDTH{1'b0}};

endmodule
