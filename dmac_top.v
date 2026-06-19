module dmac_top #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4
)(
    input  wire                   clk,
    input  wire                   resetn,
    
    input  wire [ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  wire                   s_axi_awvalid,
    output wire                   s_axi_awready,
    input  wire [DATA_WIDTH-1:0]  s_axi_wdata,
    input  wire [(DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  wire                   s_axi_wvalid,
    output wire                   s_axi_wready,
    output wire [1:0]             s_axi_bresp,
    output wire                   s_axi_bvalid,
    input  wire                   s_axi_bready,
    
    output wire                   cpu_intr
);

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

    wire                      m0_awvalid, m0_awready, m0_wvalid, m0_wready;
    wire                      m0_bvalid, m0_bready, m0_arvalid, m0_arready, m0_rvalid, m0_rready, m0_rlast;
    wire [ID_WIDTH-1:0]       m0_bid, m0_rid;
    wire [1:0]                m0_bresp, m0_rresp;
    wire [DATA_WIDTH-1:0]     m0_rdata;

    wire [7:0]                mio_awvalid, mio_awready, mio_wvalid, mio_wready;
    wire [7:0]                mio_bvalid, mio_bready, mio_arvalid, mio_arready, mio_rvalid, mio_rready, mio_rlast;
    wire [(8*ID_WIDTH)-1:0]   mio_bid, mio_rid;
    wire [(8*2)-1:0]          mio_bresp, mio_rresp;
    wire [(8*DATA_WIDTH)-1:0] mio_rdata;

    wire [ADDR_WIDTH-1:0]     cmd_addr;
    wire [15:0]               cmd_len;
    wire [2:0]                cmd_size;
    wire                      cmd_rnw, cmd_valid, cmd_error;
    wire                      read_cmd_ready, write_cmd_ready, read_cmd_done, write_cmd_done;
    wire [DATA_WIDTH-1:0]     tx_data, rx_data;
    wire                      tx_valid, tx_ready, rx_valid, rx_ready;
    wire                      fifo_wr_en, fifo_rd_en, fifo_full, fifo_empty;
    wire [DATA_WIDTH-1:0]     fifo_wdata, fifo_rdata;
    wire                      reg_wr_en;
    wire [ADDR_WIDTH-1:0]     reg_wr_addr;
    wire [DATA_WIDTH-1:0]     reg_wdata;

    wire reset_high = ~resetn; 
    wire [2:0] m_cmd_id, m_read_done_id, m_write_done_id;

 
    dmac_controller #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)
    ) dma_ctrl_inst (
        .clk(clk), .resetn(resetn),
        .cmd_addr(cmd_addr), .cmd_len(cmd_len), .cmd_size(cmd_size), .cmd_rnw(cmd_rnw),
        .cmd_id(m_cmd_id), 
        .cmd_valid(cmd_valid), .read_cmd_ready(read_cmd_ready),
        .write_cmd_ready(write_cmd_ready), .read_cmd_done(read_cmd_done),
        .read_done_id(m_read_done_id),     
        .write_cmd_done(write_cmd_done), 
        .write_done_id(m_write_done_id),   
        .cmd_error(cmd_error),
        .tx_data(tx_data),               .tx_valid(tx_valid),      .tx_ready(tx_ready),
        .rx_data(rx_data),               .rx_valid(rx_valid),      .rx_ready(rx_ready),
        .cpu_intr(cpu_intr),             .reg_wr_en(reg_wr_en),    .reg_wr_addr(reg_wr_addr),
        .reg_wdata(reg_wdata),           .fifo_wr_en(fifo_wr_en),  .fifo_wdata(fifo_wdata),
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
        .read_done_id(m_read_done_id), .write_done_id(m_write_done_id), .cmd_id(m_cmd_id),
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
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH)
    ) router_inst (
        .ACLK(clk), .ARESETn(resetn),
        
        .S_AWADDR(m_awaddr), .S_AWVALID(m_awvalid), .S_AWREADY(m_awready),
        .S_WLAST(m_wlast),   .S_WVALID(m_wvalid),   .S_WREADY(m_wready),
        .S_BID(m_bid),       .S_BRESP(m_bresp),     .S_BVALID(m_bvalid),   .S_BREADY(m_bready),
        .S_ARADDR(m_araddr), .S_ARVALID(m_arvalid), .S_ARREADY(m_arready),
        .S_RID(m_rid),       .S_RDATA(m_rdata),     .S_RRESP(m_rresp),     .S_RLAST(m_rlast), .S_RVALID(m_rvalid), .S_RREADY(m_rready),
        
        .M0_AWVALID(m0_awvalid), .M0_AWREADY(m0_awready),
        .M0_WVALID(m0_wvalid),   .M0_WREADY(m0_wready),
        .M0_BID(m0_bid),         .M0_BRESP(m0_bresp),       .M0_BVALID(m0_bvalid), .M0_BREADY(m0_bready),
        .M0_ARVALID(m0_arvalid), .M0_ARREADY(m0_arready),
        .M0_RID(m0_rid),         .M0_RDATA(m0_rdata),       .M0_RRESP(m0_rresp),   .M0_RLAST(m0_rlast), .M0_RVALID(m0_rvalid), .M0_RREADY(m0_rready),

        .M_IO_AWVALID(mio_awvalid), .M_IO_AWREADY(mio_awready),
        .M_IO_WVALID(mio_wvalid),   .M_IO_WREADY(mio_wready),
        .M_IO_BID(mio_bid),         .M_IO_BRESP(mio_bresp),     .M_IO_BVALID(mio_bvalid), .M_IO_BREADY(mio_bready),
        .M_IO_ARVALID(mio_arvalid), .M_IO_ARREADY(mio_arready),
        .M_IO_RID(mio_rid),         .M_IO_RDATA(mio_rdata),     .M_IO_RRESP(mio_rresp),   .M_IO_RLAST(mio_rlast), .M_IO_RVALID(mio_rvalid), .M_IO_RREADY(mio_rready)
    );

  
    wire                      mem_wr_en, mem_rd_en;
    wire [ADDR_WIDTH-1:0]     mem_wr_ad, mem_rd_ad;
    wire [DATA_WIDTH-1:0]     mem_wdata, mem_rdata;
    wire [(DATA_WIDTH/8)-1:0] mem_wstrb;

    axi_slave_memory #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH)
    ) main_memory_inst (
        .ACLK(clk), .ARESETN(resetn),
        .AWID(m_awid), .AWADDR(m_awaddr), .AWLEN(m_awlen), .AWSIZE(m_awsize), .AWBURST(m_awburst),
        .WID(m_wid),   .WDATA(m_wdata),   .WSTRB(m_wstrb), .WLAST(m_wlast),
        .ARID(m_arid), .ARADDR(m_araddr), .ARLEN(m_arlen), .ARSIZE(m_arsize), .ARBURST(m_arburst),
        
        .AWVALID(m0_awvalid), .AWREADY(m0_awready),
        .WVALID(m0_wvalid),   .WREADY(m0_wready),
        .BID(m0_bid),         .BRESP(m0_bresp),   .BVALID(m0_bvalid), .BREADY(m0_bready),
        .ARVALID(m0_arvalid), .ARREADY(m0_arready),
        .RID(m0_rid),         .RDATA(m0_rdata),   .RRESP(m0_rresp),   .RLAST(m0_rlast), .RVALID(m0_rvalid), .RREADY(m0_rready),
        
        .MEMORY_WR_EN(mem_wr_en), .MEMORY_WR_AD(mem_wr_ad), .MEMORY_WDATA(mem_wdata), .MEMORY_WSTRB(mem_wstrb),
        .MEMORY_RD_EN(mem_rd_en), .MEMORY_RD_AD(mem_rd_ad), .MEMORY_RDATA(mem_rdata),
        .MEMORY_WR_BUSY(1'b0),    .MEMORY_RD_BUSY(1'b0) 
    );

    ram #(
        .DEPTH(1024), .DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)
    ) internal_sram_inst (
        .clk(clk),
        .wr_en(mem_wr_en), .wr_addr(mem_wr_ad), .wdata(mem_wdata), .wstrb(mem_wstrb),
        .rd_en(mem_rd_en), .rd_addr(mem_rd_ad), .rdata(mem_rdata)
    );

    
    axi_io_slave #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH),
        .ROM_DEPTH(1024), .INIT_FILE("/home/debian/Documents/project/dma_controller/tb/io_data_0.hex"), .BASE_ADDR(32'h4000_0000)
    ) io_slave_0 (
        .ACLK(clk), .ARESETN(resetn),
        .AWID(m_awid), .AWADDR(m_awaddr), .AWLEN(m_awlen), .AWSIZE(m_awsize), .AWBURST(m_awburst),
        .WID(m_wid), .WDATA(m_wdata), .WSTRB(m_wstrb), .WLAST(m_wlast),
        .ARID(m_arid), .ARADDR(m_araddr), .ARLEN(m_arlen), .ARSIZE(m_arsize), .ARBURST(m_arburst),
        
        .AWVALID(mio_awvalid[0]), .AWREADY(mio_awready[0]),
        .WVALID(mio_wvalid[0]),   .WREADY(mio_wready[0]),
        .BID(mio_bid[0*ID_WIDTH +: ID_WIDTH]), .BRESP(mio_bresp[0*2 +: 2]), .BVALID(mio_bvalid[0]), .BREADY(mio_bready[0]),
        .ARVALID(mio_arvalid[0]), .ARREADY(mio_arready[0]),
        .RID(mio_rid[0*ID_WIDTH +: ID_WIDTH]), .RDATA(mio_rdata[0*DATA_WIDTH +: DATA_WIDTH]),
        .RRESP(mio_rresp[0*2 +: 2]), .RLAST(mio_rlast[0]), .RVALID(mio_rvalid[0]), .RREADY(mio_rready[0])
    );

    axi_io_slave #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH),
        .ROM_DEPTH(1024), .INIT_FILE("/home/debian/Documents/project/dma_controller/tb/io_data_1.hex"), .BASE_ADDR(32'h4010_0000)
    ) io_slave_1 (
        .ACLK(clk), .ARESETN(resetn),
        .AWID(m_awid), .AWADDR(m_awaddr), .AWLEN(m_awlen), .AWSIZE(m_awsize), .AWBURST(m_awburst),
        .WID(m_wid), .WDATA(m_wdata), .WSTRB(m_wstrb), .WLAST(m_wlast),
        .ARID(m_arid), .ARADDR(m_araddr), .ARLEN(m_arlen), .ARSIZE(m_arsize), .ARBURST(m_arburst),
        
        .AWVALID(mio_awvalid[1]), .AWREADY(mio_awready[1]),
        .WVALID(mio_wvalid[1]),   .WREADY(mio_wready[1]),
        .BID(mio_bid[1*ID_WIDTH +: ID_WIDTH]), .BRESP(mio_bresp[1*2 +: 2]), .BVALID(mio_bvalid[1]), .BREADY(mio_bready[1]),
        .ARVALID(mio_arvalid[1]), .ARREADY(mio_arready[1]),
        .RID(mio_rid[1*ID_WIDTH +: ID_WIDTH]), .RDATA(mio_rdata[1*DATA_WIDTH +: DATA_WIDTH]),
        .RRESP(mio_rresp[1*2 +: 2]), .RLAST(mio_rlast[1]), .RVALID(mio_rvalid[1]), .RREADY(mio_rready[1])
    );

    axi_io_slave #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH),
        .ROM_DEPTH(1024), .INIT_FILE("/home/debian/Documents/project/dma_controller/tb/io_data_2.hex"), .BASE_ADDR(32'h4020_0000)
    ) io_slave_2 (
        .ACLK(clk), .ARESETN(resetn),
        .AWID(m_awid), .AWADDR(m_awaddr), .AWLEN(m_awlen), .AWSIZE(m_awsize), .AWBURST(m_awburst),
        .WID(m_wid), .WDATA(m_wdata), .WSTRB(m_wstrb), .WLAST(m_wlast),
        .ARID(m_arid), .ARADDR(m_araddr), .ARLEN(m_arlen), .ARSIZE(m_arsize), .ARBURST(m_arburst),
        
        .AWVALID(mio_awvalid[2]), .AWREADY(mio_awready[2]),
        .WVALID(mio_wvalid[2]),   .WREADY(mio_wready[2]),
        .BID(mio_bid[2*ID_WIDTH +: ID_WIDTH]), .BRESP(mio_bresp[2*2 +: 2]), .BVALID(mio_bvalid[2]), .BREADY(mio_bready[2]),
        .ARVALID(mio_arvalid[2]), .ARREADY(mio_arready[2]),
        .RID(mio_rid[2*ID_WIDTH +: ID_WIDTH]), .RDATA(mio_rdata[2*DATA_WIDTH +: DATA_WIDTH]),
        .RRESP(mio_rresp[2*2 +: 2]), .RLAST(mio_rlast[2]), .RVALID(mio_rvalid[2]), .RREADY(mio_rready[2])
    );

    axi_io_slave #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH),
        .ROM_DEPTH(1024), .INIT_FILE("/home/debian/Documents/project/dma_controller/tb/io_data_3.hex"), .BASE_ADDR(32'h4030_0000)
    ) io_slave_3 (
        .ACLK(clk), .ARESETN(resetn),
        .AWID(m_awid), .AWADDR(m_awaddr), .AWLEN(m_awlen), .AWSIZE(m_awsize), .AWBURST(m_awburst),
        .WID(m_wid), .WDATA(m_wdata), .WSTRB(m_wstrb), .WLAST(m_wlast),
        .ARID(m_arid), .ARADDR(m_araddr), .ARLEN(m_arlen), .ARSIZE(m_arsize), .ARBURST(m_arburst),
        
        .AWVALID(mio_awvalid[3]), .AWREADY(mio_awready[3]),
        .WVALID(mio_wvalid[3]),   .WREADY(mio_wready[3]),
        .BID(mio_bid[3*ID_WIDTH +: ID_WIDTH]), .BRESP(mio_bresp[3*2 +: 2]), .BVALID(mio_bvalid[3]), .BREADY(mio_bready[3]),
        .ARVALID(mio_arvalid[3]), .ARREADY(mio_arready[3]),
        .RID(mio_rid[3*ID_WIDTH +: ID_WIDTH]), .RDATA(mio_rdata[3*DATA_WIDTH +: DATA_WIDTH]),
        .RRESP(mio_rresp[3*2 +: 2]), .RLAST(mio_rlast[3]), .RVALID(mio_rvalid[3]), .RREADY(mio_rready[3])
    );

    axi_io_slave #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH),
        .ROM_DEPTH(1024), .INIT_FILE("/home/debian/Documents/project/dma_controller/tb/io_data_4.hex"), .BASE_ADDR(32'h4040_0000)
    ) io_slave_4 (
        .ACLK(clk), .ARESETN(resetn),
        .AWID(m_awid), .AWADDR(m_awaddr), .AWLEN(m_awlen), .AWSIZE(m_awsize), .AWBURST(m_awburst),
        .WID(m_wid), .WDATA(m_wdata), .WSTRB(m_wstrb), .WLAST(m_wlast),
        .ARID(m_arid), .ARADDR(m_araddr), .ARLEN(m_arlen), .ARSIZE(m_arsize), .ARBURST(m_arburst),
        
        .AWVALID(mio_awvalid[4]), .AWREADY(mio_awready[4]),
        .WVALID(mio_wvalid[4]),   .WREADY(mio_wready[4]),
        .BID(mio_bid[4*ID_WIDTH +: ID_WIDTH]), .BRESP(mio_bresp[4*2 +: 2]), .BVALID(mio_bvalid[4]), .BREADY(mio_bready[4]),
        .ARVALID(mio_arvalid[4]), .ARREADY(mio_arready[4]),
        .RID(mio_rid[4*ID_WIDTH +: ID_WIDTH]), .RDATA(mio_rdata[4*DATA_WIDTH +: DATA_WIDTH]),
        .RRESP(mio_rresp[4*2 +: 2]), .RLAST(mio_rlast[4]), .RVALID(mio_rvalid[4]), .RREADY(mio_rready[4])
    );

    axi_io_slave #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH),
        .ROM_DEPTH(1024), .INIT_FILE("/home/debian/Documents/project/dma_controller/tb/io_data_5.hex"), .BASE_ADDR(32'h4050_0000)
    ) io_slave_5 (
        .ACLK(clk), .ARESETN(resetn),
        .AWID(m_awid), .AWADDR(m_awaddr), .AWLEN(m_awlen), .AWSIZE(m_awsize), .AWBURST(m_awburst),
        .WID(m_wid), .WDATA(m_wdata), .WSTRB(m_wstrb), .WLAST(m_wlast),
        .ARID(m_arid), .ARADDR(m_araddr), .ARLEN(m_arlen), .ARSIZE(m_arsize), .ARBURST(m_arburst),
        
        .AWVALID(mio_awvalid[5]), .AWREADY(mio_awready[5]),
        .WVALID(mio_wvalid[5]),   .WREADY(mio_wready[5]),
        .BID(mio_bid[5*ID_WIDTH +: ID_WIDTH]), .BRESP(mio_bresp[5*2 +: 2]), .BVALID(mio_bvalid[5]), .BREADY(mio_bready[5]),
        .ARVALID(mio_arvalid[5]), .ARREADY(mio_arready[5]),
        .RID(mio_rid[5*ID_WIDTH +: ID_WIDTH]), .RDATA(mio_rdata[5*DATA_WIDTH +: DATA_WIDTH]),
        .RRESP(mio_rresp[5*2 +: 2]), .RLAST(mio_rlast[5]), .RVALID(mio_rvalid[5]), .RREADY(mio_rready[5])
    );

    axi_io_slave #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH),
        .ROM_DEPTH(1024), .INIT_FILE("/home/debian/Documents/project/dma_controller/tb/io_data_6.hex"), .BASE_ADDR(32'h4060_0000)
    ) io_slave_6 (
        .ACLK(clk), .ARESETN(resetn),
        .AWID(m_awid), .AWADDR(m_awaddr), .AWLEN(m_awlen), .AWSIZE(m_awsize), .AWBURST(m_awburst),
        .WID(m_wid), .WDATA(m_wdata), .WSTRB(m_wstrb), .WLAST(m_wlast),
        .ARID(m_arid), .ARADDR(m_araddr), .ARLEN(m_arlen), .ARSIZE(m_arsize), .ARBURST(m_arburst),
        
        .AWVALID(mio_awvalid[6]), .AWREADY(mio_awready[6]),
        .WVALID(mio_wvalid[6]),   .WREADY(mio_wready[6]),
        .BID(mio_bid[6*ID_WIDTH +: ID_WIDTH]), .BRESP(mio_bresp[6*2 +: 2]), .BVALID(mio_bvalid[6]), .BREADY(mio_bready[6]),
        .ARVALID(mio_arvalid[6]), .ARREADY(mio_arready[6]),
        .RID(mio_rid[6*ID_WIDTH +: ID_WIDTH]), .RDATA(mio_rdata[6*DATA_WIDTH +: DATA_WIDTH]),
        .RRESP(mio_rresp[6*2 +: 2]), .RLAST(mio_rlast[6]), .RVALID(mio_rvalid[6]), .RREADY(mio_rready[6])
    );

    axi_io_slave #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH),
        .ROM_DEPTH(1024), .INIT_FILE("/home/debian/Documents/project/dma_controller/tb/io_data_7.hex"), .BASE_ADDR(32'h4070_0000)
    ) io_slave_7 (
        .ACLK(clk), .ARESETN(resetn),
        .AWID(m_awid), .AWADDR(m_awaddr), .AWLEN(m_awlen), .AWSIZE(m_awsize), .AWBURST(m_awburst),
        .WID(m_wid), .WDATA(m_wdata), .WSTRB(m_wstrb), .WLAST(m_wlast),
        .ARID(m_arid), .ARADDR(m_araddr), .ARLEN(m_arlen), .ARSIZE(m_arsize), .ARBURST(m_arburst),
        
        .AWVALID(mio_awvalid[7]), .AWREADY(mio_awready[7]),
        .WVALID(mio_wvalid[7]),   .WREADY(mio_wready[7]),
        .BID(mio_bid[7*ID_WIDTH +: ID_WIDTH]), .BRESP(mio_bresp[7*2 +: 2]), .BVALID(mio_bvalid[7]), .BREADY(mio_bready[7]),
        .ARVALID(mio_arvalid[7]), .ARREADY(mio_arready[7]),
        .RID(mio_rid[7*ID_WIDTH +: ID_WIDTH]), .RDATA(mio_rdata[7*DATA_WIDTH +: DATA_WIDTH]),
        .RRESP(mio_rresp[7*2 +: 2]), .RLAST(mio_rlast[7]), .RVALID(mio_rvalid[7]), .RREADY(mio_rready[7])
    );

   
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

endmodule
