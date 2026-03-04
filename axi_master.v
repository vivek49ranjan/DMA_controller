module axi_master #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4,
    parameter [2:0] PROT_VAL  = 3'b000,
    parameter [3:0] CACHE_VAL = 4'b0000,
    parameter [1:0] BURST_VAL = 2'b01,
    parameter [1:0] LOCK_VAL  = 2'b00,
    parameter [2:0] SIZE_VAL  = 3'b010,
    parameter [ID_WIDTH-1:0] ID_VAL = 0
) (
    input ACLK,
    input ARESETn,
    
    input  [ADDR_WIDTH-1:0] cmd_addr,
    input  [15:0]           cmd_len,
    input                   cmd_rnw,
    input                   cmd_valid,
    output                  cmd_ready,
    output reg              cmd_done,
    output reg              cmd_error,

    input  [DATA_WIDTH-1:0] tx_data,
    input                   tx_valid,
    output                  tx_ready,

    output [DATA_WIDTH-1:0] rx_data,
    output                  rx_valid,
    input                   rx_ready,

    output [ID_WIDTH-1:0]   AWID,
    output [ADDR_WIDTH-1:0] AWADDR,
    output [7:0]            AWLEN,
    output [2:0]            AWSIZE,
    output [1:0]            AWBURST,
    output [1:0]            AWLOCK,
    output [3:0]            AWCACHE,
    output [2:0]            AWPROT,
    output reg              AWVALID,
    input                   AWREADY,
    
    output [ID_WIDTH-1:0]   WID,
    output [DATA_WIDTH-1:0] WDATA,
    output [(DATA_WIDTH/8)-1:0] WSTRB,
    output                  WLAST,
    output                  WVALID,
    input                   WREADY,
    
    input  [ID_WIDTH-1:0]   BID,
    input  [1:0]            BRESP,
    input                   BVALID,
    output reg              BREADY,
    
    output [ID_WIDTH-1:0]   ARID,
    output [ADDR_WIDTH-1:0] ARADDR,
    output [7:0]            ARLEN,
    output [2:0]            ARSIZE,
    output [1:0]            ARBURST,
    output [1:0]            ARLOCK,
    output [3:0]            ARCACHE,
    output [2:0]            ARPROT,
    output reg              ARVALID,
    input                   ARREADY,
    
    input  [ID_WIDTH-1:0]   RID,
    input  [DATA_WIDTH-1:0] RDATA,
    input  [1:0]            RRESP,
    input                   RLAST,
    input                   RVALID,
    output                  RREADY
);

    assign AWID    = ID_VAL;
    assign AWSIZE  = SIZE_VAL;
    assign AWBURST = BURST_VAL;
    assign AWLOCK  = LOCK_VAL;
    assign AWCACHE = CACHE_VAL;
    assign AWPROT  = PROT_VAL;

    assign ARID    = ID_VAL;
    assign ARSIZE  = SIZE_VAL;
    assign ARBURST = BURST_VAL;
    assign ARLOCK  = LOCK_VAL;
    assign ARCACHE = CACHE_VAL;
    assign ARPROT  = PROT_VAL;
    assign WID     = ID_VAL;

    localparam [2:0] 
        IDLE       = 3'd0,
        ADDR_PHASE = 3'd1,
        DATA_PHASE = 3'd2,
        RESP_PHASE = 3'd3,
        ERR_STATE  = 3'd4;

    reg [2:0] write_state, read_state;
    reg [15:0] w_burst_count;

    assign AWADDR = cmd_addr;
    assign AWLEN  = cmd_len[7:0] - 1'b1;
    
    assign WVALID   = (write_state == DATA_PHASE) ? tx_valid : 1'b0;
    assign tx_ready = (write_state == DATA_PHASE) ? WREADY : 1'b0;
    assign WDATA    = tx_data;
    assign WSTRB    = {(DATA_WIDTH/8){1'b1}};
    assign WLAST    = (w_burst_count == cmd_len - 1);

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            write_state   <= IDLE;
            AWVALID       <= 1'b0;
            BREADY        <= 1'b0;
            cmd_done      <= 1'b0;
            cmd_error     <= 1'b0;
            w_burst_count <= 16'd0;
        end else begin
            cmd_done <= 1'b0;
            
            case (write_state)
                IDLE: begin
                    cmd_error <= 1'b0;
                    w_burst_count <= 16'd0;
                    if (cmd_valid && cmd_rnw) begin
                        write_state <= ADDR_PHASE;
                        AWVALID     <= 1'b1;
                    end
                end

                ADDR_PHASE: begin
                    if (AWREADY && AWVALID) begin
                        AWVALID     <= 1'b0;
                        write_state <= DATA_PHASE;
                    end
                end

                DATA_PHASE: begin
                    if (WREADY && WVALID) begin
                        if (WLAST) begin
                            write_state <= RESP_PHASE;
                            BREADY      <= 1'b1;
                        end else begin
                            w_burst_count <= w_burst_count + 1'b1;
                        end
                    end
                end

                RESP_PHASE: begin
                    if (BVALID && BREADY) begin
                        BREADY <= 1'b0;
                        
                        case (BRESP)
                            2'b00: begin
                                write_state <= IDLE;
                                cmd_done    <= 1'b1;
                            end
                            2'b01: begin
                                write_state <= IDLE;
                                cmd_done    <= 1'b1; 
                            end
                            2'b10: begin
                                write_state <= ERR_STATE;
                                cmd_error   <= 1'b1;
                            end
                            2'b11: begin
                                write_state <= ERR_STATE;
                                cmd_error   <= 1'b1;
                            end
                        endcase
                    end
                end

                ERR_STATE: begin
                    write_state <= IDLE; 
                end
            endcase
        end
    end

    assign ARADDR = cmd_addr;
    assign ARLEN  = cmd_len[7:0] - 1'b1;

    assign rx_valid = (read_state == DATA_PHASE) ? RVALID : 1'b0;
    assign RREADY   = (read_state == DATA_PHASE) ? rx_ready : 1'b0;
    assign rx_data  = RDATA;

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            read_state <= IDLE;
            ARVALID    <= 1'b0;
        end else begin
            case (read_state)
                IDLE: begin
                    if (cmd_valid && !cmd_rnw) begin
                        read_state <= ADDR_PHASE;
                        ARVALID    <= 1'b1;
                    end
                end

                ADDR_PHASE: begin
                    if (ARREADY && ARVALID) begin
                        ARVALID    <= 1'b0;
                        read_state <= DATA_PHASE;
                    end
                end

                DATA_PHASE: begin
                    if (RVALID && RREADY) begin
                        if (RRESP == 2'b10 || RRESP == 2'b11) begin
                            read_state <= ERR_STATE;
                            cmd_error  <= 1'b1;
                        end 
                        else if (RLAST) begin
                            read_state <= IDLE;
                            cmd_done   <= 1'b1;
                        end
                    end
                end
                
                ERR_STATE: begin
                    read_state <= IDLE;
                end
            endcase
        end
    end

    assign cmd_ready = (write_state == IDLE) && (read_state == IDLE);

endmodule