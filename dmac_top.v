module dmac_top #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4
)(
    input  wire                     clk,
    input  wire                     resetn,
    
    input  wire [ADDR_WIDTH-1:0]    s_axi_awaddr,
    input  wire                     s_axi_awvalid,
    output wire                     s_axi_awready,
    input  wire [DATA_WIDTH-1:0]    s_axi_wdata,
    input  wire [(DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  wire                     s_axi_wvalid,
    output wire                     s_axi_wready,
    output wire [1:0]               s_axi_bresp,
    output wire                     s_axi_bvalid,
    input  wire                     s_axi_bready,
    
    output wire                     cpu_intr,

    output wire [7:0]               snoop_io_wvalid,
    output wire [(8*DATA_WIDTH)-1:0] snoop_io_wdata
);

    wire [ID_WIDTH-1:0]       m_awid, m_arid, m_bid, m_rid;
    wire [ADDR_WIDTH-1:0]     m_awaddr, m_araddr;
    wire [7:0]                m_awlen, m_arlen; 
    wire [2:0]                m_awsize, m_arsize;
    wire [1:0]                m_awburst, m_arburst;
    wire [(DATA_WIDTH/8)-1:0] m_wstrb;
    wire [DATA_WIDTH-1:0]     m_wdata, m_rdata;
    wire                      m_wlast, m_awvalid, m_awready, m_wvalid, m_wready;
    wire                      m_bvalid, m_bready, m_arvalid, m_arready, m_rvalid, m_rready, m_rlast;
    wire [1:0]                m_bresp, m_rresp;

    wire                      mem_awvalid, mem_awready, mem_wvalid, mem_wready;
    wire                      mem_bvalid, mem_bready, mem_arvalid, mem_arready, mem_rvalid, mem_rready, mem_rlast;
    wire [ID_WIDTH-1:0]       mem_bid, mem_rid;
    wire [1:0]                mem_bresp, mem_rresp;
    wire [DATA_WIDTH-1:0]     mem_rdata;

    wire [7:0]                io_awvalid, io_awready, io_wvalid, io_wready;
    wire [7:0]                io_bvalid, io_bready, io_arvalid, io_arready, io_rvalid, io_rready, io_rlast;
    wire [(8*ID_WIDTH)-1:0]   io_bid, io_rid;
    wire [(8*2)-1:0]          io_bresp, io_rresp;
    wire [(8*DATA_WIDTH)-1:0] io_rdata;

    assign snoop_io_wvalid = io_wvalid & io_wready; 
    assign snoop_io_wdata  = {8{m_wdata}};            

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
        .tx_data(tx_data),               .tx_valid(tx_valid),       .tx_ready(tx_ready),
        .rx_data(rx_data),               .rx_valid(rx_valid),       .rx_ready(rx_ready),
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
        .cmd_size(cmd_size),       .cmd_rnw(cmd_rnw),          .cmd_valid(cmd_valid),
        .read_cmd_ready(read_cmd_ready), .write_cmd_ready(write_cmd_ready),
        .read_cmd_done(read_cmd_done),   .write_cmd_done(write_cmd_done),
        .read_done_id(m_read_done_id), .write_done_id(m_write_done_id), .cmd_id(m_cmd_id),
        .cmd_error(cmd_error),
        .tx_data(tx_data),         .tx_valid(tx_valid),       .tx_ready(tx_ready),
        .rx_data(rx_data),         .rx_valid(rx_valid),       .rx_ready(rx_ready),
        
        .AWID(m_awid), .AWADDR(m_awaddr), .AWLEN(m_awlen), .AWSIZE(m_awsize), .AWBURST(m_awburst),
        .AWVALID(m_awvalid), .AWREADY(m_awready),
        
        .WDATA(m_wdata), .WSTRB(m_wstrb), .WLAST(m_wlast),
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
        
        .M_AWADDR(m_awaddr), .M_AWVALID(m_awvalid), .M_AWREADY(m_awready),
        .M_WLAST(m_wlast),   .M_WVALID(m_wvalid),   .M_WREADY(m_wready),
        .M_BID(m_bid),       .M_BRESP(m_bresp),     .M_BVALID(m_bvalid),   .M_BREADY(m_bready),
        .M_ARADDR(m_araddr), .M_ARVALID(m_arvalid), .M_ARREADY(m_arready),
        .M_RID(m_rid),       .M_RDATA(m_rdata),     .M_RRESP(m_rresp),     .M_RLAST(m_rlast), .M_RVALID(m_rvalid), .M_RREADY(m_rready),
        
        .MEM_AWVALID(mem_awvalid), .MEM_AWREADY(mem_awready),
        .MEM_WVALID(mem_wvalid),   .MEM_WREADY(mem_wready),
        .MEM_BID(mem_bid),         .MEM_BRESP(mem_bresp),       .MEM_BVALID(mem_bvalid), .MEM_BREADY(mem_bready),
        .MEM_ARVALID(mem_arvalid), .MEM_ARREADY(mem_arready),
        .MEM_RID(mem_rid),         .MEM_RDATA(mem_rdata),       .MEM_RRESP(mem_rresp),   .MEM_RLAST(mem_rlast), .MEM_RVALID(mem_rvalid), .MEM_RREADY(mem_rready),

        .IO_AWVALID(io_awvalid), .IO_AWREADY(io_awready),
        .IO_WVALID(io_wvalid),   .IO_WREADY(io_wready),
        .IO_BID(io_bid),         .IO_BRESP(io_bresp),       .IO_BVALID(io_bvalid), .IO_BREADY(io_bready),
        .IO_ARVALID(io_arvalid), .IO_ARREADY(io_arready),
        .IO_RID(io_rid),         .IO_RDATA(io_rdata),       .IO_RRESP(io_rresp),   .IO_RLAST(io_rlast), .IO_RVALID(io_rvalid), .IO_RREADY(io_rready)
    );

    wire                      ram_wr_en, ram_rd_en;
    wire [ADDR_WIDTH-1:0]     ram_wr_ad, ram_rd_ad;
    wire [DATA_WIDTH-1:0]     ram_wdata, ram_rdata;
    wire [(DATA_WIDTH/8)-1:0] ram_wstrb;

    axi_slave_memory #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH)
    ) main_memory_inst (
        .ACLK(clk), .ARESETN(resetn),
        .AWID(m_awid), .AWADDR(m_awaddr), .AWLEN(m_awlen), .AWSIZE(m_awsize), .AWBURST(m_awburst),
        .WDATA(m_wdata),   .WSTRB(m_wstrb), .WLAST(m_wlast),
        .ARID(m_arid), .ARADDR(m_araddr), .ARLEN(m_arlen), .ARSIZE(m_arsize), .ARBURST(m_arburst),
        
        .AWVALID(mem_awvalid), .AWREADY(mem_awready),
        .WVALID(mem_wvalid),   .WREADY(mem_wready),
        .BID(mem_bid),         .BRESP(mem_bresp),   .BVALID(mem_bvalid), .BREADY(mem_bready),
        .ARVALID(mem_arvalid), .ARREADY(mem_arready),
        .RID(mem_rid),         .RDATA(mem_rdata),   .RRESP(mem_rresp),   .RLAST(mem_rlast), .RVALID(mem_rvalid), .RREADY(mem_rready),
        
        .MEMORY_WR_EN(ram_wr_en), .MEMORY_WR_AD(ram_wr_ad), .MEMORY_WDATA(ram_wdata), .MEMORY_WSTRB(ram_wstrb),
        .MEMORY_RD_EN(ram_rd_en), .MEMORY_RD_AD(ram_rd_ad), .MEMORY_RDATA(ram_rdata),
        .MEMORY_WR_BUSY(1'b0),    .MEMORY_RD_BUSY(1'b0) 
    );

    ram #(
        .DEPTH(8192), .DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)
    ) internal_sram_inst (
        .clk(clk),
        .wr_en(ram_wr_en), .wr_addr(ram_wr_ad), .wdata(ram_wdata), .wstrb(ram_wstrb),
        .rd_en(ram_rd_en), .rd_addr(ram_rd_ad), .rdata(ram_rdata)
    );

    axi_io_slave #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH),
        .ROM_DEPTH(8192), .INIT_FILE("/home/debian/Documents/project/dma_controller/tb/io_data_0.hex"), .BASE_ADDR(32'h4000_0000)
    ) io_slave_0 (
        .ACLK(clk), .ARESETN(resetn),
        .AWID(m_awid), .AWADDR(m_awaddr), .AWLEN(m_awlen), .AWSIZE(m_awsize), .AWBURST(m_awburst),
        .WDATA(m_wdata), .WSTRB(m_wstrb), .WLAST(m_wlast),
        .ARID(m_arid), .ARADDR(m_araddr), .ARLEN(m_arlen), .ARSIZE(m_arsize), .ARBURST(m_arburst),
        .AWVALID(io_awvalid[0]), .AWREADY(io_awready[0]),
        .WVALID(io_wvalid[0]),   .WREADY(io_wready[0]),
        .BID(io_bid[0*ID_WIDTH +: ID_WIDTH]), .BRESP(io_bresp[0*2 +: 2]), .BVALID(io_bvalid[0]), .BREADY(io_bready[0]),
        .ARVALID(io_arvalid[0]), .ARREADY(io_arready[0]),
        .RID(io_rid[0*ID_WIDTH +: ID_WIDTH]), .RDATA(io_rdata[0*DATA_WIDTH +: DATA_WIDTH]),
        .RRESP(io_rresp[0*2 +: 2]), .RLAST(io_rlast[0]), .RVALID(io_rvalid[0]), .RREADY(io_rready[0])
    );

    axi_io_slave #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH),
        .ROM_DEPTH(8192), .INIT_FILE("/home/debian/Documents/project/dma_controller/tb/io_data_1.hex"), .BASE_ADDR(32'h4010_0000)
    ) io_slave_1 (
        .ACLK(clk), .ARESETN(resetn),
        .AWID(m_awid), .AWADDR(m_awaddr), .AWLEN(m_awlen), .AWSIZE(m_awsize), .AWBURST(m_awburst),
        .WDATA(m_wdata), .WSTRB(m_wstrb), .WLAST(m_wlast),
        .ARID(m_arid), .ARADDR(m_araddr), .ARLEN(m_arlen), .ARSIZE(m_arsize), .ARBURST(m_arburst),
        .AWVALID(io_awvalid[1]), .AWREADY(io_awready[1]),
        .WVALID(io_wvalid[1]),   .WREADY(io_wready[1]),
        .BID(io_bid[1*ID_WIDTH +: ID_WIDTH]), .BRESP(io_bresp[1*2 +: 2]), .BVALID(io_bvalid[1]), .BREADY(io_bready[1]),
        .ARVALID(io_arvalid[1]), .ARREADY(io_arready[1]),
        .RID(io_rid[1*ID_WIDTH +: ID_WIDTH]), .RDATA(io_rdata[1*DATA_WIDTH +: DATA_WIDTH]),
        .RRESP(io_rresp[1*2 +: 2]), .RLAST(io_rlast[1]), .RVALID(io_rvalid[1]), .RREADY(io_rready[1])
    );

    axi_io_slave #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH),
        .ROM_DEPTH(8192), .INIT_FILE("/home/debian/Documents/project/dma_controller/tb/io_data_2.hex"), .BASE_ADDR(32'h4020_0000)
    ) io_slave_2 (
        .ACLK(clk), .ARESETN(resetn),
        .AWID(m_awid), .AWADDR(m_awaddr), .AWLEN(m_awlen), .AWSIZE(m_awsize), .AWBURST(m_awburst),
        .WDATA(m_wdata), .WSTRB(m_wstrb), .WLAST(m_wlast),
        .ARID(m_arid), .ARADDR(m_araddr), .ARLEN(m_arlen), .ARSIZE(m_arsize), .ARBURST(m_arburst),
        .AWVALID(io_awvalid[2]), .AWREADY(io_awready[2]),
        .WVALID(io_wvalid[2]),   .WREADY(io_wready[2]),
        .BID(io_bid[2*ID_WIDTH +: ID_WIDTH]), .BRESP(io_bresp[2*2 +: 2]), .BVALID(io_bvalid[2]), .BREADY(io_bready[2]),
        .ARVALID(io_arvalid[2]), .ARREADY(io_arready[2]),
        .RID(io_rid[2*ID_WIDTH +: ID_WIDTH]), .RDATA(io_rdata[2*DATA_WIDTH +: DATA_WIDTH]),
        .RRESP(io_rresp[2*2 +: 2]), .RLAST(io_rlast[2]), .RVALID(io_rvalid[2]), .RREADY(io_rready[2])
    );

    axi_io_slave #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH),
        .ROM_DEPTH(8192), .INIT_FILE("/home/debian/Documents/project/dma_controller/tb/io_data_3.hex"), .BASE_ADDR(32'h4030_0000)
    ) io_slave_3 (
        .ACLK(clk), .ARESETN(resetn),
        .AWID(m_awid), .AWADDR(m_awaddr), .AWLEN(m_awlen), .AWSIZE(m_awsize), .AWBURST(m_awburst),
        .WDATA(m_wdata), .WSTRB(m_wstrb), .WLAST(m_wlast),
        .ARID(m_arid), .ARADDR(m_araddr), .ARLEN(m_arlen), .ARSIZE(m_arsize), .ARBURST(m_arburst),
        .AWVALID(io_awvalid[3]), .AWREADY(io_awready[3]),
        .WVALID(io_wvalid[3]),   .WREADY(io_wready[3]),
        .BID(io_bid[3*ID_WIDTH +: ID_WIDTH]), .BRESP(io_bresp[3*2 +: 2]), .BVALID(io_bvalid[3]), .BREADY(io_bready[3]),
        .ARVALID(io_arvalid[3]), .ARREADY(io_arready[3]),
        .RID(io_rid[3*ID_WIDTH +: ID_WIDTH]), .RDATA(io_rdata[3*DATA_WIDTH +: DATA_WIDTH]),
        .RRESP(io_rresp[3*2 +: 2]), .RLAST(io_rlast[3]), .RVALID(io_rvalid[3]), .RREADY(io_rready[3])
    );

    axi_io_slave #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH),
        .ROM_DEPTH(8192), .INIT_FILE("/home/debian/Documents/project/dma_controller/tb/io_data_4.hex"), .BASE_ADDR(32'h4040_0000)
    ) io_slave_4 (
        .ACLK(clk), .ARESETN(resetn),
        .AWID(m_awid), .AWADDR(m_awaddr), .AWLEN(m_awlen), .AWSIZE(m_awsize), .AWBURST(m_awburst),
        .WDATA(m_wdata), .WSTRB(m_wstrb), .WLAST(m_wlast),
        .ARID(m_arid), .ARADDR(m_araddr), .ARLEN(m_arlen), .ARSIZE(m_arsize), .ARBURST(m_arburst),
        .AWVALID(io_awvalid[4]), .AWREADY(io_awready[4]),
        .WVALID(io_wvalid[4]),   .WREADY(io_wready[4]),
        .BID(io_bid[4*ID_WIDTH +: ID_WIDTH]), .BRESP(io_bresp[4*2 +: 2]), .BVALID(io_bvalid[4]), .BREADY(io_bready[4]),
        .ARVALID(io_arvalid[4]), .ARREADY(io_arready[4]),
        .RID(io_rid[4*ID_WIDTH +: ID_WIDTH]), .RDATA(io_rdata[4*DATA_WIDTH +: DATA_WIDTH]),
        .RRESP(io_rresp[4*2 +: 2]), .RLAST(io_rlast[4]), .RVALID(io_rvalid[4]), .RREADY(io_rready[4])
    );

    axi_io_slave #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH),
        .ROM_DEPTH(8192), .INIT_FILE("/home/debian/Documents/project/dma_controller/tb/io_data_5.hex"), .BASE_ADDR(32'h4050_0000)
    ) io_slave_5 (
        .ACLK(clk), .ARESETN(resetn),
        .AWID(m_awid), .AWADDR(m_awaddr), .AWLEN(m_awlen), .AWSIZE(m_awsize), .AWBURST(m_awburst),
        .WDATA(m_wdata), .WSTRB(m_wstrb), .WLAST(m_wlast),
        .ARID(m_arid), .ARADDR(m_araddr), .ARLEN(m_arlen), .ARSIZE(m_arsize), .ARBURST(m_arburst),
        .AWVALID(io_awvalid[5]), .AWREADY(io_awready[5]),
        .WVALID(io_wvalid[5]),   .WREADY(io_wready[5]),
        .BID(io_bid[5*ID_WIDTH +: ID_WIDTH]), .BRESP(io_bresp[5*2 +: 2]), .BVALID(io_bvalid[5]), .BREADY(io_bready[5]),
        .ARVALID(io_arvalid[5]), .ARREADY(io_arready[5]),
        .RID(io_rid[5*ID_WIDTH +: ID_WIDTH]), .RDATA(io_rdata[5*DATA_WIDTH +: DATA_WIDTH]),
        .RRESP(io_rresp[5*2 +: 2]), .RLAST(io_rlast[5]), .RVALID(io_rvalid[5]), .RREADY(io_rready[5])
    );

    axi_io_slave #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH),
        .ROM_DEPTH(8192), .INIT_FILE("/home/debian/Documents/project/dma_controller/tb/io_data_6.hex"), .BASE_ADDR(32'h4060_0000)
    ) io_slave_6 (
        .ACLK(clk), .ARESETN(resetn),
        .AWID(m_awid), .AWADDR(m_awaddr), .AWLEN(m_awlen), .AWSIZE(m_awsize), .AWBURST(m_awburst),
        .WDATA(m_wdata), .WSTRB(m_wstrb), .WLAST(m_wlast),
        .ARID(m_arid), .ARADDR(m_araddr), .ARLEN(m_arlen), .ARSIZE(m_arsize), .ARBURST(m_arburst),
        .AWVALID(io_awvalid[6]), .AWREADY(io_awready[6]),
        .WVALID(io_wvalid[6]),   .WREADY(io_wready[6]),
        .BID(io_bid[6*ID_WIDTH +: ID_WIDTH]), .BRESP(io_bresp[6*2 +: 2]), .BVALID(io_bvalid[6]), .BREADY(io_bready[6]),
        .ARVALID(io_arvalid[6]), .ARREADY(io_arready[6]),
        .RID(io_rid[6*ID_WIDTH +: ID_WIDTH]), .RDATA(io_rdata[6*DATA_WIDTH +: DATA_WIDTH]),
        .RRESP(io_rresp[6*2 +: 2]), .RLAST(io_rlast[6]), .RVALID(io_rvalid[6]), .RREADY(io_rready[6])
    );

    axi_io_slave #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH),
        .ROM_DEPTH(8192), .INIT_FILE("/home/debian/Documents/project/dma_controller/tb/io_data_7.hex"), .BASE_ADDR(32'h4070_0000)
    ) io_slave_7 (
        .ACLK(clk), .ARESETN(resetn),
        .AWID(m_awid), .AWADDR(m_awaddr), .AWLEN(m_awlen), .AWSIZE(m_awsize), .AWBURST(m_awburst),
        .WDATA(m_wdata), .WSTRB(m_wstrb), .WLAST(m_wlast),
        .ARID(m_arid), .ARADDR(m_araddr), .ARLEN(m_arlen), .ARSIZE(m_arsize), .ARBURST(m_arburst),
        .AWVALID(io_awvalid[7]), .AWREADY(io_awready[7]),
        .WVALID(io_wvalid[7]),   .WREADY(io_wready[7]),
        .BID(io_bid[7*ID_WIDTH +: ID_WIDTH]), .BRESP(io_bresp[7*2 +: 2]), .BVALID(io_bvalid[7]), .BREADY(io_bready[7]),
        .ARVALID(io_arvalid[7]), .ARREADY(io_arready[7]),
        .RID(io_rid[7*ID_WIDTH +: ID_WIDTH]), .RDATA(io_rdata[7*DATA_WIDTH +: DATA_WIDTH]),
        .RRESP(io_rresp[7*2 +: 2]), .RLAST(io_rlast[7]), .RVALID(io_rvalid[7]), .RREADY(io_rready[7])
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
