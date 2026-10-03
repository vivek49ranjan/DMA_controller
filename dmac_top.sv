import dmac_pkg::*;

module dmac_top #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4
)(
    input  logic                      clk,
    input  logic                      resetn,
    
    axi_lite_if.slave                 s_axi,
    
    output logic                      cpu_intr,

    output logic [7:0]                snoop_io_wvalid,
    output logic [(8*DATA_WIDTH)-1:0] snoop_io_wdata
);
    genvar i;

    axi_if #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH)
    ) m_axi_bus (
        .clk(clk), .resetn(resetn)
    );
    
    axi_if #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH)
    ) mem_axi_bus (
        .clk(clk), .resetn(resetn)
    );
    
    axi_if #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH)
    ) io_axi_bus [0:7] (
        .clk(clk), .resetn(resetn)
    );

    dma_cmd_t                cmd_payload;
    logic                    cmd_valid, read_cmd_ready, write_cmd_ready;
    logic                    read_cmd_done, write_cmd_done;
    logic [Q_DEPTH_BITS:0]   read_done_id, write_done_id;
    logic                    cmd_error;
    logic [1:0]              cmd_error_type;

    logic                    tx_valid, tx_ready, rx_valid, rx_ready;
    logic [DATA_WIDTH-1:0]   tx_data, rx_data;
    
    logic                    fifo_wr_en, fifo_rd_en, fifo_full, fifo_empty;
    logic [DATA_WIDTH-1:0]   fifo_wdata, fifo_rdata;

    logic                    reg_wr_valid, reg_wr_ready;
    logic [ADDR_WIDTH-1:0]   reg_wr_addr;
    logic [DATA_WIDTH-1:0]   reg_wdata;

    assign snoop_io_wdata = {8{m_axi_bus.wdata}};
    
    generate
        for (i = 0; i < 8; i = i + 1) begin : gen_snoop
            assign snoop_io_wvalid[i] = io_axi_bus[i].wvalid & io_axi_bus[i].wready;
        end
    endgenerate

    dmac_controller #(
        .ADDR_WIDTH(ADDR_WIDTH), 
        .DATA_WIDTH(DATA_WIDTH),
        .Q_DEPTH_BITS(Q_DEPTH_BITS)
    ) dma_ctrl_inst (
        .clk(clk), 
        .resetn(resetn),
        
        .cmd_out(cmd_payload),
        .cmd_valid(cmd_valid), 
        .read_cmd_ready(read_cmd_ready), 
        .write_cmd_ready(write_cmd_ready),
        .read_cmd_done(read_cmd_done), 
        .write_cmd_done(write_cmd_done),
        .read_done_id(read_done_id), 
        .write_done_id(write_done_id),
        .cmd_error(cmd_error), 
        .cmd_error_type(cmd_error_type),
        
        .tx_data(tx_data), 
        .tx_valid(tx_valid), 
        .tx_ready(tx_ready),
        
        .rx_data(rx_data), 
        .rx_valid(rx_valid), 
        .rx_ready(rx_ready),
        
        .cpu_intr(cpu_intr),
        
        .reg_wr_valid(reg_wr_valid), 
        .reg_wr_ready(reg_wr_ready),
        .reg_wr_addr(reg_wr_addr), 
        .reg_wdata(reg_wdata),
        
        .fifo_wr_en(fifo_wr_en), 
        .fifo_wdata(fifo_wdata), 
        .fifo_full(fifo_full),
        .fifo_rd_en(fifo_rd_en), 
        .fifo_rdata(fifo_rdata), 
        .fifo_empty(fifo_empty)
    );

    sync_fifo #(
        .A_WIDTH(4)
    ) internal_fifo (
        .clk(clk), 
        .resetn(resetn),
        .wr_en(fifo_wr_en), 
        .wdata(fifo_wdata), 
        .full(fifo_full),
        .rd_en(fifo_rd_en), 
        .rdata(fifo_rdata), 
        .empty(fifo_empty)
    );

    axi_master #(
        .ADDR_WIDTH(ADDR_WIDTH), 
        .DATA_WIDTH(DATA_WIDTH), 
        .ID_WIDTH(ID_WIDTH),
        .Q_DEPTH_BITS(Q_DEPTH_BITS)
    ) axi_master_inst (
        .axi(m_axi_bus),
        
        .cmd(cmd_payload),
        .cmd_valid(cmd_valid),
        .read_cmd_ready(read_cmd_ready), 
        .write_cmd_ready(write_cmd_ready),
        .read_cmd_done(read_cmd_done), 
        .write_cmd_done(write_cmd_done),
        .read_done_id(read_done_id), 
        .write_done_id(write_done_id),
        .cmd_error(cmd_error), 
        .cmd_error_type(cmd_error_type),
        
        .tx_data(tx_data), 
        .tx_valid(tx_valid), 
        .tx_ready(tx_ready),
        
        .rx_data(rx_data), 
        .rx_valid(rx_valid), 
        .rx_ready(rx_ready)
    );

    axi_router #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH)
    ) router_inst (
        .m_axi(m_axi_bus),
        .mem_axi(mem_axi_bus),
        .io_axi(io_axi_bus)
    );

    axi_slave_memory #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .ID_WIDTH(ID_WIDTH)
    ) main_memory_inst (
        .axi(mem_axi_bus)
    );

    axi_io_slave #(
        .ROM_DEPTH(1024),
        .INIT_FILE("/home/debian/Documents/project/SG_DMA/tb/io_data_0.hex"),
        .BASE_ADDR(32'h4000_0000)
    ) io_slave_inst_0 ( .axi(io_axi_bus[0]) );

    axi_io_slave #(
        .ROM_DEPTH(1024),
        .INIT_FILE("/home/debian/Documents/project/SG_DMA/tb/io_data_1.hex"),
        .BASE_ADDR(32'h4200_0000)
    ) io_slave_inst_1 ( .axi(io_axi_bus[1]) );

    axi_io_slave #(
        .ROM_DEPTH(1024),
        .INIT_FILE("/home/debian/Documents/project/SG_DMA/tb/io_data_2.hex"),
        .BASE_ADDR(32'h4400_0000)
    ) io_slave_inst_2 ( .axi(io_axi_bus[2]) );

    axi_io_slave #(
        .ROM_DEPTH(1024),
        .INIT_FILE("/home/debian/Documents/project/SG_DMA/tb/io_data_3.hex"),
        .BASE_ADDR(32'h4600_0000)
    ) io_slave_inst_3 ( .axi(io_axi_bus[3]) );

    axi_io_slave #(
        .ROM_DEPTH(1024),
        .INIT_FILE("/home/debian/Documents/project/SG_DMA/tb/io_data_4.hex"),
        .BASE_ADDR(32'h4800_0000)
    ) io_slave_inst_4 ( .axi(io_axi_bus[4]) );

    axi_io_slave #(
        .ROM_DEPTH(1024),
        .INIT_FILE("/home/debian/Documents/project/SG_DMA/tb/io_data_5.hex"),
        .BASE_ADDR(32'h4A00_0000)
    ) io_slave_inst_5 ( .axi(io_axi_bus[5]) );

    axi_io_slave #(
        .ROM_DEPTH(1024),
        .INIT_FILE("/home/debian/Documents/project/SG_DMA/tb/io_data_6.hex"),
        .BASE_ADDR(32'h4C00_0000)
    ) io_slave_inst_6 ( .axi(io_axi_bus[6]) );

    axi_io_slave #(
        .ROM_DEPTH(1024),
        .INIT_FILE("/home/debian/Documents/project/SG_DMA/tb/io_data_7.hex"),
        .BASE_ADDR(32'h4E00_0000)
    ) io_slave_inst_7 ( .axi(io_axi_bus[7]) );

    axi_lite_slave #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) axi_lite_inst (
        .s_axi(s_axi),
        .reg_wr_valid(reg_wr_valid), 
        .reg_wr_ready(reg_wr_ready),
        .reg_wr_addr(reg_wr_addr), 
        .reg_wdata(reg_wdata)
    );

endmodule
