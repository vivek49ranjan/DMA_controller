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
    input  wire [2:0]                cmd_size,
    input  wire                      cmd_rnw,
    input  wire                      cmd_valid,
    
    output reg                       read_cmd_ready,
    output reg                       write_cmd_ready,
    output reg                       read_cmd_done,
    output reg                       write_cmd_done,
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


    reg wr_cmd_error;
    reg rd_cmd_error;
    
    always @(*) begin
        cmd_error = wr_cmd_error | rd_cmd_error;
    end
    
    localparam WR_IDLE   = 3'd0;
    localparam WR_ISSUE  = 3'd1; 
    localparam WR_W_DATA = 3'd2; 
    localparam WR_AW_REQ = 3'd3; 
    localparam WR_RESP   = 3'd4; 

    reg [2:0]            wr_state, wr_next_state;
    reg [ADDR_WIDTH-1:0] aw_addr_reg; 
    reg [ADDR_WIDTH-1:0] w_addr_reg;  
    reg [2:0]            w_size_reg;
    reg [15:0]           w_len_reg;
    reg [3:0]            w_burst_count;

    reg [127:0]          unshifted_strb; 
    reg [31:0]           addr_offset;

    always @(*) begin
        wr_next_state   = wr_state;
        write_cmd_ready = 1'b0;
        write_cmd_done  = 1'b0;
        wr_cmd_error    = 1'b0;

        AWVALID = 1'b0;
        AWID    = ID_VAL;
        AWADDR  = aw_addr_reg;
        AWSIZE  = w_size_reg;
        AWLEN   = w_len_reg[3:0] - 1'b1;
        AWBURST = 2'b01;

        WVALID   = 1'b0;
        WID      = ID_VAL;
        WDATA    = tx_data;
        WLAST    = (w_burst_count == (w_len_reg[3:0] - 1'b1));
        tx_ready = 1'b0;

        BREADY   = (wr_state != WR_IDLE);

        unshifted_strb = (128'b1 << (1 << w_size_reg)) - 1;
        addr_offset    = w_addr_reg & ((DATA_WIDTH/8) - 1);
        WSTRB          = unshifted_strb << addr_offset;

        case (wr_state)
            WR_IDLE: begin
                write_cmd_ready = 1'b1;
                if (cmd_valid && cmd_rnw) begin
                    wr_next_state = WR_ISSUE;
                end
            end

            WR_ISSUE: begin
                AWVALID  = 1'b1;
                WVALID   = tx_valid;
                tx_ready = WREADY;

                if (AWREADY && (WVALID && WREADY && WLAST)) begin
                    wr_next_state = WR_RESP;
                end else if (AWREADY) begin
                    wr_next_state = WR_W_DATA;
                end else if (WVALID && WREADY && WLAST) begin
                    wr_next_state = WR_AW_REQ;
                end
            end

            WR_W_DATA: begin
                WVALID   = tx_valid;
                tx_ready = WREADY;

                if (WVALID && WREADY && WLAST) begin
                    wr_next_state = WR_RESP;
                end
            end

            WR_AW_REQ: begin
                AWVALID = 1'b1;

                if (AWREADY) begin
                    wr_next_state = WR_RESP;
                end
            end

            WR_RESP: begin
                if (BVALID && BREADY) begin
                    write_cmd_done = (BRESP[1] == 1'b0);
                    wr_cmd_error   = (BRESP[1] == 1'b1);
                    wr_next_state  = WR_IDLE;
                end
            end
            
            default: wr_next_state = WR_IDLE;
        endcase
    end

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            wr_state      <= WR_IDLE;
            aw_addr_reg   <= {ADDR_WIDTH{1'b0}};
            w_addr_reg    <= {ADDR_WIDTH{1'b0}};
            w_size_reg    <= 3'd0;
            w_len_reg     <= 16'd0;
            w_burst_count <= 4'd0;
        end else begin
            wr_state <= wr_next_state;

            case (wr_state)
                WR_IDLE: begin
                    if (cmd_valid && cmd_rnw) begin
                        aw_addr_reg   <= cmd_addr;
                        w_addr_reg    <= cmd_addr;
                        w_size_reg    <= cmd_size;
                        w_len_reg     <= cmd_len;
                        w_burst_count <= 4'd0;
                    end
                end

                WR_ISSUE, WR_W_DATA: begin
                    if (WVALID && WREADY) begin
                        w_addr_reg <= (w_addr_reg + (1 << w_size_reg)) & ~((1 << w_size_reg) - 1);
                        
                        if (!WLAST) begin
                            w_burst_count <= w_burst_count + 1'b1;
                        end
                    end
                end
            endcase
        end
    end

   
    localparam RD_IDLE   = 2'd0;
    localparam RD_AR_REQ = 2'd1;
    localparam RD_R_DATA = 2'd2;

    reg [1:0]            rd_state, rd_next_state;
    reg [ADDR_WIDTH-1:0] r_addr_reg;  
    reg [2:0]            r_size_reg;
    reg [15:0]           r_len_reg;

    always @(*) begin
        rd_next_state  = rd_state;
        read_cmd_ready = 1'b0;
        read_cmd_done  = 1'b0;
        rd_cmd_error   = 1'b0;

        ARVALID  = 1'b0;
        ARID     = ID_VAL;
        ARADDR   = r_addr_reg;
        ARSIZE   = r_size_reg;
        ARLEN    = r_len_reg[3:0] - 1'b1;
        ARBURST  = 2'b01;

        RREADY   = 1'b0;
        rx_valid = 1'b0;
        rx_data  = RDATA;

        case (rd_state)
            RD_IDLE: begin
                read_cmd_ready = 1'b1;
                if (cmd_valid && !cmd_rnw) begin
                    rd_next_state = RD_AR_REQ;
                end
            end

            RD_AR_REQ: begin
                ARVALID = 1'b1;
                if (ARREADY) begin
                    rd_next_state = RD_R_DATA;
                end
            end

            RD_R_DATA: begin
                RREADY   = rx_ready;
                rx_valid = RVALID;

                if (RVALID && RREADY && RLAST) begin
                    read_cmd_done = (RRESP[1] == 1'b0);
                    rd_cmd_error  = (RRESP[1] == 1'b1);
                    rd_next_state = RD_IDLE;
                end
            end
            
            default: rd_next_state = RD_IDLE;
        endcase
    end

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            rd_state   <= RD_IDLE;
            r_addr_reg <= {ADDR_WIDTH{1'b0}};
            r_size_reg <= 3'd0;
            r_len_reg  <= 16'd0;
        end else begin
            rd_state <= rd_next_state;

            case (rd_state)
                RD_IDLE: begin
                    if (cmd_valid && !cmd_rnw) begin
                        r_addr_reg <= cmd_addr;
                        r_size_reg <= cmd_size;
                        r_len_reg  <= cmd_len;
                    end
                end
            endcase
        end
    end

endmodule
