import dmac_pkg::*;

module axi_lite_slave #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    axi_lite_if.slave s_axi,
    output logic                  reg_wr_valid,
    input  logic                  reg_wr_ready,
    output logic [ADDR_WIDTH-1:0] reg_wr_addr,
    output logic [DATA_WIDTH-1:0] reg_wdata
);
    logic aw_latched;
    logic w_latched;
    
    logic [ADDR_WIDTH-1:0] awaddr_reg;
    logic [DATA_WIDTH-1:0] wdata_reg;

    assign s_axi.awready = ~aw_latched && ~s_axi.bvalid;
    assign s_axi.wready  = ~w_latched  && ~s_axi.bvalid;
    assign s_axi.bresp   = 2'b00; 

    logic aw_complete;
    logic w_complete;
    
    assign aw_complete = aw_latched || (s_axi.awvalid && s_axi.awready);
    assign w_complete  = w_latched  || (s_axi.wvalid && s_axi.wready);
    assign reg_wr_valid = aw_complete && w_complete;
    
    assign reg_wr_addr = aw_latched ? awaddr_reg : s_axi.awaddr;
    assign reg_wdata   = w_latched  ? wdata_reg  : s_axi.wdata;
    
    always_ff @(posedge s_axi.clk or negedge s_axi.resetn) begin
        if (!s_axi.resetn) begin
            aw_latched   <= 1'b0;
            w_latched    <= 1'b0;
            s_axi.bvalid <= 1'b0;
            awaddr_reg   <= {ADDR_WIDTH{1'b0}};
            wdata_reg    <= {DATA_WIDTH{1'b0}};
        end else begin
            if (s_axi.bvalid && s_axi.bready) begin
                s_axi.bvalid <= 1'b0;
            end

            if (s_axi.awvalid && s_axi.awready) begin
                aw_latched <= 1'b1;
                awaddr_reg <= s_axi.awaddr;
            end

            if (s_axi.wvalid && s_axi.wready) begin
                w_latched <= 1'b1;
                wdata_reg <= s_axi.wdata;
            end

            if (reg_wr_valid && reg_wr_ready) begin
                s_axi.bvalid <= 1'b1;
                aw_latched   <= 1'b0;
                w_latched    <= 1'b0;
            end
        end
    end
endmodule
