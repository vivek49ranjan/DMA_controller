interface axi_if #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4
)(
    input logic clk,
    input logic resetn
);
    logic [ID_WIDTH-1:0]       awid;
    logic [ADDR_WIDTH-1:0]     awaddr;
    logic [7:0]                awlen;
    logic [2:0]                awsize;
    logic [1:0]                awburst;
    logic                      awvalid;
    logic                      awready;

    logic [DATA_WIDTH-1:0]     wdata;
    logic [(DATA_WIDTH/8)-1:0] wstrb;
    logic                      wlast;
    logic                      wvalid;
    logic                      wready;

    logic [ID_WIDTH-1:0]       bid;
    logic [1:0]                bresp;
    logic                      bvalid;
    logic                      bready;

    logic [ID_WIDTH-1:0]       arid;
    logic [ADDR_WIDTH-1:0]     araddr;
    logic [7:0]                arlen;
    logic [2:0]                arsize;
    logic [1:0]                arburst;
    logic                      arvalid;
    logic                      arready;

    logic [ID_WIDTH-1:0]       rid;
    logic [DATA_WIDTH-1:0]     rdata;
    logic [1:0]                rresp;
    logic                      rlast;
    logic                      rvalid;
    logic                      rready;

    modport master (
        input  clk, resetn,
        output awid, awaddr, awlen, awsize, awburst, awvalid,
        input  awready,
        output wdata, wstrb, wlast, wvalid,
        input  wready,
        input  bid, bresp, bvalid,
        output bready,
        output arid, araddr, arlen, arsize, arburst, arvalid,
        input  arready,
        input  rid, rdata, rresp, rlast, rvalid,
        output rready
    );

    modport slave (
        input  clk, resetn,
        input  awid, awaddr, awlen, awsize, awburst, awvalid,
        output awready,
        input  wdata, wstrb, wlast, wvalid,
        output wready,
        output bid, bresp, bvalid,
        input  bready,
        input  arid, araddr, arlen, arsize, arburst, arvalid,
        output arready,
        output rid, rdata, rresp, rlast, rvalid,
        input  rready
    );
endinterface

interface axi_lite_if #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input logic clk,
    input logic resetn
);
    logic [ADDR_WIDTH-1:0]     awaddr;
    logic                      awvalid;
    logic                      awready;
    logic [DATA_WIDTH-1:0]     wdata;
    logic [(DATA_WIDTH/8)-1:0] wstrb;
    logic                      wvalid;
    logic                      wready;
    logic [1:0]                bresp;
    logic                      bvalid;
    logic                      bready;

    modport master (
        input  clk, resetn,
        output awaddr, awvalid, wdata, wstrb, wvalid, bready,
        input  awready, wready, bresp, bvalid
    );

    modport slave (
        input  clk, resetn,
        input  awaddr, awvalid, wdata, wstrb, wvalid, bready,
        output awready, wready, bresp, bvalid
    );
endinterface
