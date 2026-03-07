module axi_master #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4,
    parameter [ID_WIDTH-1:0] ID_VAL = 0
) (
    input  wire                      ACLK,
    input  wire                      ARESETn,
    
    input  wire [ADDR_WIDTH-1:0]     cmd_addr,
    input  wire [15:0]               cmd_len,
    input  wire                      cmd_rnw,
    input  wire                      cmd_valid,
    output reg                       cmd_ready,
    output reg                       cmd_done,
    output reg                       cmd_error,

    input  wire [DATA_WIDTH-1:0]     tx_data,
    input  wire                      tx_valid,
    output reg                       tx_ready,
    output reg  [DATA_WIDTH-1:0]     rx_data,
    output reg                       rx_valid,
    input  wire                      rx_ready,

    output reg  [ID_WIDTH-1:0]       AWID,
    output reg  [ADDR_WIDTH-1:0]     AWADDR,
    output reg  [3:0]                AWLEN,
    output reg  [2:0]                AWSIZE,
    output reg  [1:0]                AWBURST,
    output reg                       AWVALID,
    input  wire                      AWREADY,
    
    output reg  [ID_WIDTH-1:0]       WID,
    output reg  [DATA_WIDTH-1:0]     WDATA,
    output reg  [(DATA_WIDTH/8)-1:0] WSTRB,
    output reg                       WLAST,
    output reg                       WVALID,
    input  wire                      WREADY,
    
    input  wire [ID_WIDTH-1:0]       BID,
    input  wire [1:0]                BRESP,
    input  wire                      BVALID,
    output reg                       BREADY,
    
    output reg  [ID_WIDTH-1:0]       ARID,
    output reg  [ADDR_WIDTH-1:0]     ARADDR,
    output reg  [3:0]                ARLEN,
    output reg  [2:0]                ARSIZE,
    output reg  [1:0]                ARBURST,
    output reg                       ARVALID,
    input  wire                      ARREADY,
    
    input  wire [ID_WIDTH-1:0]       RID,
    input  wire [DATA_WIDTH-1:0]     RDATA,
    input  wire [1:0]                RRESP,
    input  wire                      RLAST,
    input  wire                      RVALID,
    output reg                       RREADY
);

    localparam [2:0] 
        W_IDLE = 3'd0,
        W_ADDR = 3'd1,
        W_DATA = 3'd2,
        W_RESP = 3'd3,
        W_ERR  = 3'd4;

    localparam [2:0] 
        R_IDLE = 3'd0,
        R_ADDR = 3'd1,
        R_DATA = 3'd2,
        R_ERR  = 3'd3;

    reg [2:0] write_state;
    reg [2:0] read_state;
    reg [3:0] w_burst_count;

    always @(*) begin
        cmd_ready = (write_state == W_IDLE) && (read_state == R_IDLE);
        
        cmd_done  = ((write_state == W_RESP && BVALID && (BRESP == 2'b00 || BRESP == 2'b01)) ||
                     (read_state == R_DATA  && RVALID && RLAST && (RRESP == 2'b00 || RRESP == 2'b01)));
                     
        cmd_error = ((write_state == W_RESP && BVALID && (BRESP == 2'b10 || BRESP == 2'b11)) ||
                     (read_state == R_DATA  && RVALID && (RRESP == 2'b10 || RRESP == 2'b11)));
    end

    always @(*) begin
        AWID     = ID_VAL;
        AWSIZE   = 3'b010; 
        AWBURST  = 2'b01;  
        AWADDR   = cmd_addr;
        AWLEN    = cmd_len[3:0] - 1'b1;
        AWVALID  = 1'b0;
        
        WID      = ID_VAL;
        WDATA    = tx_data;
        WSTRB    = {(DATA_WIDTH/8){1'b1}}; 
        WLAST    = (w_burst_count == (cmd_len[3:0] - 1'b1));
        WVALID   = 1'b0;
        
        tx_ready = 1'b0;
        BREADY   = 1'b0;

        case (write_state)
            W_ADDR: begin
                AWVALID = 1'b1;
            end
            W_DATA: begin
                WVALID   = tx_valid;
                tx_ready = WREADY;
            end
            W_RESP: begin
                BREADY = 1'b1;
            end
        endcase
    end

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            write_state   <= W_IDLE;
            w_burst_count <= 4'd0;
        end else begin
            case (write_state)
                W_IDLE: begin
                    w_burst_count <= 4'd0;
                    if (cmd_valid && cmd_rnw) begin
                        write_state <= W_ADDR;
                    end
                end
                W_ADDR: begin
                    if (AWREADY) begin
                        write_state <= W_DATA;
                    end
                end
                W_DATA: begin
                    if (WREADY && WVALID) begin
                        if (!WLAST) begin
                            w_burst_count <= w_burst_count + 1'b1;
                        end else begin
                            write_state <= W_RESP;
                        end
                    end
                end
                W_RESP: begin
                    if (BVALID) begin
                        if (BRESP == 2'b10 || BRESP == 2'b11) begin
                            write_state <= W_ERR;
                        end else begin
                            write_state <= W_IDLE;
                        end
                    end
                end
                W_ERR: begin
                    write_state <= W_IDLE; 
                end
                default: write_state <= W_IDLE;
            endcase
        end
    end

    always @(*) begin
        ARID     = ID_VAL;
        ARSIZE   = 3'b010; 
        ARBURST  = 2'b01;  
        ARADDR   = cmd_addr;
        ARLEN    = cmd_len[3:0] - 1'b1;
        ARVALID  = 1'b0;
        
        RREADY   = 1'b0;
        rx_valid = 1'b0;
        rx_data  = RDATA; 

        case (read_state)
            R_ADDR: begin
                ARVALID = 1'b1;
            end
            R_DATA: begin
                RREADY   = rx_ready;
                rx_valid = RVALID;
            end
        endcase
    end

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            read_state <= R_IDLE;
        end else begin
            case (read_state)
                R_IDLE: begin
                    if (cmd_valid && !cmd_rnw) begin
                        read_state <= R_ADDR;
                    end
                end
                R_ADDR: begin
                    if (ARREADY) begin
                        read_state <= R_DATA;
                    end
                end
                R_DATA: begin
                    if (RVALID && RREADY) begin
                        if (RRESP == 2'b10 || RRESP == 2'b11) begin
                            read_state <= R_ERR;
                        end else if (RLAST) begin
                            read_state <= R_IDLE;
                        end
                    end
                end
                R_ERR: begin
                    read_state <= R_IDLE;
                end
                default: read_state <= R_IDLE;
            endcase
        end
    end

endmodule
