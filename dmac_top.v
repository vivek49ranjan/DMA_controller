module dmac_top #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4
)(
    input  wire                  clk,
    input  wire                  resetn,
    
    output wire                  tb_io0_tx_wr_en,
    output wire [DATA_WIDTH-1:0] tb_io0_tx_data,
    
    output wire                  tb_io0_rx_rd_en,
    input  wire [DATA_WIDTH-1:0] tb_io0_rx_data,
    input  wire                  tb_io0_rx_empty
);

    wire [ADDR_WIDTH-1:0] cmd_addr;
    wire [15:0]           cmd_len;
    wire                  cmd_rnw;
    wire                  cmd_valid, cmd_ready, cmd_done, cmd_error;

    wire [DATA_WIDTH-1:0] tx_data, rx_data;
    wire                  tx_valid, tx_ready, rx_valid, rx_ready;
    wire                  cpu_intr;

    wire                  fifo_wr_en, fifo_rd_en;
    wire [DATA_WIDTH-1:0] fifo_wdata, fifo_rdata;
    wire                  fifo_full, fifo_empty;
    wire                  reset_high = ~resetn; 

    wire                  reg_wr_en, reg_rd_en;
    wire [ADDR_WIDTH-1:0] reg_wr_addr, reg_rd_addr;
    wire [DATA_WIDTH-1:0] reg_wdata, reg_rdata;

    wire [ID_WIDTH-1:0]   m_awid, m_wid, m_arid;
    wire [ADDR_WIDTH-1:0] m_awaddr, m_araddr;
    wire [3:0]            m_awlen, m_arlen;
    wire [2:0]            m_awsize, m_arsize;
    wire [1:0]            m_awburst, m_arburst;
    wire [(DATA_WIDTH/8)-1:0] m_wstrb;
    wire [DATA_WIDTH-1:0] m_wdata;
    wire                  m_wlast;

    wire m_awvalid, m_awready;
    wire m_wvalid,  m_wready;
    wire m_bvalid,  m_bready;
    wire [1:0]      m_bresp;
    wire m_arvalid, m_arready;
    wire m_rvalid,  m_rready, m_rlast;
    wire [1:0]      m_rresp;
    wire [DATA_WIDTH-1:0] m_rdata;

    wire [7:0] io_tx_fifo_wr_en;
    wire [DATA_WIDTH-1:0] io_tx_fifo_wdata [0:7];
    wire [7:0] io_rx_fifo_rd_en;

    assign tb_io0_tx_wr_en = io_tx_fifo_wr_en[0];
    assign tb_io0_tx_data  = io_tx_fifo_wdata[0];
    assign tb_io0_rx_rd_en = io_rx_fifo_rd_en[0];

    dmac_controller #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)
    ) dma_ctrl_inst (
        .clk(clk),                 .resetn(resetn),
        .cmd_addr(cmd_addr),       .cmd_len(cmd_len),
        .cmd_rnw(cmd_rnw),         .cmd_valid(cmd_valid),
        .cmd_ready(cmd_ready),     .cmd_done(cmd_done),      .cmd_error(cmd_error),
        .tx_data(tx_data),         .tx_valid(tx_valid),      .tx_ready(tx_ready),
        .rx_data(rx_data),         .rx_valid(rx_valid),      .rx_ready(rx_ready),
        .cpu_intr(cpu_intr),
        .reg_wr_en(reg_wr_en),     .reg_wr_addr(reg_wr_addr),.reg_wdata(reg_wdata),
        .reg_rd_en(reg_rd_en),     .reg_rd_addr(reg_rd_addr),.reg_rdata(reg_rdata),
        .fifo_wr_en(fifo_wr_en),   .fifo_wdata(fifo_wdata),  .fifo_full(fifo_full),
        .fifo_rd_en(fifo_rd_en),   .fifo_rdata(fifo_rdata),  .fifo_empty(fifo_empty)
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
        .cmd_rnw(cmd_rnw),         .cmd_valid(cmd_valid),
        .cmd_ready(cmd_ready),     .cmd_done(cmd_done),      .cmd_error(cmd_error),
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

    wire s0_awvalid, s0_awready, s0_wvalid, s0_wready, s0_bvalid, s0_bready;
    wire s0_arvalid, s0_arready, s0_rvalid, s0_rready, s0_rlast;
    wire [1:0] s0_bresp, s0_rresp;
    wire [DATA_WIDTH-1:0] s0_rdata;

    wire [7:0] io_awvalid, io_awready, io_wvalid, io_wready, io_bvalid, io_bready;
    wire [7:0] io_arvalid, io_arready, io_rvalid, io_rready, io_rlast;
    wire [15:0] io_bresp, io_rresp;
    wire [(8*DATA_WIDTH)-1:0] io_rdata;

    wire dma_awvalid, dma_awready, dma_wvalid, dma_wready, dma_bvalid, dma_bready;
    wire dma_arvalid, dma_arready, dma_rvalid, dma_rready, dma_rlast;
    wire [1:0] dma_bresp, dma_rresp;
    wire [DATA_WIDTH-1:0] dma_rdata;

    axi_router #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)
    ) router_inst (
        .ACLK(clk), .ARESETn(resetn),
        .M_AWADDR(m_awaddr), .M_AWVALID(m_awvalid), .M_AWREADY(m_awready),
        .M_WLAST(m_wlast), .M_WVALID(m_wvalid), .M_WREADY(m_wready),
        .M_BRESP(m_bresp), .M_BVALID(m_bvalid), .M_BREADY(m_bready),
        .M_ARADDR(m_araddr), .M_ARVALID(m_arvalid), .M_ARREADY(m_arready),
        .M_RDATA(m_rdata), .M_RRESP(m_rresp), .M_RLAST(m_rlast), .M_RVALID(m_rvalid), .M_RREADY(m_rready),
        
        .MEM_AWVALID(s0_awvalid), .MEM_AWREADY(s0_awready), .MEM_WVALID(s0_wvalid), .MEM_WREADY(s0_wready),
        .MEM_BRESP(s0_bresp), .MEM_BVALID(s0_bvalid), .MEM_BREADY(s0_bready),
        .MEM_ARVALID(s0_arvalid), .MEM_ARREADY(s0_arready), .MEM_RDATA(s0_rdata), .MEM_RRESP(s0_rresp),
        .MEM_RLAST(s0_rlast), .MEM_RVALID(s0_rvalid), .MEM_RREADY(s0_rready),

        .IO_AWVALID(io_awvalid), .IO_AWREADY(io_awready), .IO_WVALID(io_wvalid), .IO_WREADY(io_wready),
        .IO_BRESP(io_bresp), .IO_BVALID(io_bvalid), .IO_BREADY(io_bready),
        .IO_ARVALID(io_arvalid), .IO_ARREADY(io_arready), .IO_RDATA(io_rdata), .IO_RRESP(io_rresp),
        .IO_RLAST(io_rlast), .IO_RVALID(io_rvalid), .IO_RREADY(io_rready),

        .DMA_AWVALID(dma_awvalid), .DMA_AWREADY(dma_awready), .DMA_WVALID(dma_wvalid), .DMA_WREADY(dma_wready),
        .DMA_BRESP(dma_bresp), .DMA_BVALID(dma_bvalid), .DMA_BREADY(dma_bready),
        .DMA_ARVALID(dma_arvalid), .DMA_ARREADY(dma_arready), .DMA_RDATA(dma_rdata), .DMA_RRESP(dma_rresp),
        .DMA_RLAST(dma_rlast), .DMA_RVALID(dma_rvalid), .DMA_RREADY(dma_rready)
    );

    axi_slave_memory #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)
    ) main_memory_inst (
        .ACLK(clk), .ARESETN(resetn),
        .AWID(m_awid), .AWADDR(m_awaddr), .AWLEN(m_awlen), .AWSIZE(m_awsize), .AWBURST(m_awburst),
        .WID(m_wid), .WDATA(m_wdata), .WSTRB(m_wstrb), .WLAST(m_wlast),
        .ARID(m_arid), .ARADDR(m_araddr), .ARLEN(m_arlen), .ARSIZE(m_arsize), .ARBURST(m_arburst),
        .AWVALID(s0_awvalid), .AWREADY(s0_awready),
        .WVALID(s0_wvalid),   .WREADY(s0_wready),
        .BID(), .BRESP(s0_bresp), .BVALID(s0_bvalid), .BREADY(s0_bready),
        .ARVALID(s0_arvalid), .ARREADY(s0_arready),
        .RID(), .RDATA(s0_rdata), .RRESP(s0_rresp), .RLAST(s0_rlast), .RVALID(s0_rvalid), .RREADY(s0_rready),
        .MEMORY_WR_BUSY(1'b0), .MEMORY_RD_BUSY(1'b0) 
    );

    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : io_array
            wire                  rx_empty_val = (i == 0) ? tb_io0_rx_empty : 1'b1;
            wire [DATA_WIDTH-1:0] rx_data_val  = (i == 0) ? tb_io0_rx_data  : {DATA_WIDTH{1'b0}};

            axi_slave_io #(
                .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
                .TX_ADDR(32'h4000_0000 + (i * 32'h0010_0000)), 
                .RX_ADDR(32'h4000_0004 + (i * 32'h0010_0000))
            ) io_inst (
                .ACLK(clk), .ARESETN(resetn),
                .AWID(m_awid), .AWADDR(m_awaddr), .AWLEN(m_awlen), .AWSIZE(m_awsize), .AWBURST(m_awburst),
                .WID(m_wid), .WDATA(m_wdata), .WSTRB(m_wstrb), .WLAST(m_wlast),
                .ARID(m_arid), .ARADDR(m_araddr), .ARLEN(m_arlen), .ARSIZE(m_arsize), .ARBURST(m_arburst),
                .AWVALID(io_awvalid[i]), .AWREADY(io_awready[i]),
                .WVALID(io_wvalid[i]),   .WREADY(io_wready[i]),
                .BID(), .BRESP(io_bresp[i*2 +: 2]), .BVALID(io_bvalid[i]), .BREADY(io_bready[i]),
                .ARVALID(io_arvalid[i]), .ARREADY(io_arready[i]),
                .RID(), .RDATA(io_rdata[i*DATA_WIDTH +: DATA_WIDTH]), .RRESP(io_rresp[i*2 +: 2]), 
                .RLAST(io_rlast[i]), .RVALID(io_rvalid[i]), .RREADY(io_rready[i]),
                
                .TX_FIFO_WR_EN(io_tx_fifo_wr_en[i]),
                .TX_FIFO_WDATA(io_tx_fifo_wdata[i]),
                .TX_FIFO_FULL(1'b0), 
                
                .RX_FIFO_RD_EN(io_rx_fifo_rd_en[i]),
                .RX_FIFO_RDATA(rx_data_val),
                .RX_FIFO_EMPTY(rx_empty_val)
            );
        end
    endgenerate

    assign dma_awready = 1'b1;
    assign dma_wready  = 1'b1;
    assign dma_bvalid  = dma_awvalid & dma_wvalid;
    assign dma_bresp   = 2'b00;

    assign reg_wr_en   = dma_wvalid & dma_wready;
    assign reg_wr_addr = m_awaddr; 
    assign reg_wdata   = m_wdata;  

    assign dma_arready = 1'b1;
    assign dma_rvalid  = dma_arvalid;
    assign dma_rlast   = 1'b1;
    assign dma_rresp   = 2'b00;
    assign dma_rdata   = reg_rdata;

    assign reg_rd_en   = dma_arvalid;
    assign reg_rd_addr = m_araddr; 

endmodule