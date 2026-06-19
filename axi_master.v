module axi_master #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4,
    parameter Q_DEPTH_BITS = 2
) (
    input  wire                      ACLK,
    input  wire                      ARESETn,
    
    input  wire [ADDR_WIDTH-1:0]     cmd_addr,
    input  wire [15:0]               cmd_len,
    input  wire [2:0]                cmd_size,
    input  wire                      cmd_rnw,
    input  wire [Q_DEPTH_BITS:0]     cmd_id,
    input  wire                      cmd_valid,
    
    output reg                       read_cmd_ready,
    output reg                       write_cmd_ready,
    output reg                       read_cmd_done,
    output reg  [Q_DEPTH_BITS:0]     read_done_id,
    output reg                       write_cmd_done,
    output reg  [Q_DEPTH_BITS:0]     write_done_id,
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

   
    reg [2:0] outstanding_reads;
    wire read_pipeline_full = (outstanding_reads == 3'd4);

    always @(*) begin
        read_cmd_ready = !read_pipeline_full && !ARVALID;
    end

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            ARVALID <= 1'b0;
            outstanding_reads <= 3'd0;
        end else begin
            if (cmd_valid && !cmd_rnw && read_cmd_ready) begin
                ARVALID <= 1'b1;
                ARADDR  <= cmd_addr;
                ARLEN   <= cmd_len[3:0] - 1'b1;
                ARSIZE  <= cmd_size;
                ARID    <= cmd_id;
                ARBURST <= 2'b01;
            end else if (ARVALID && ARREADY) begin
                ARVALID <= 1'b0;
            end

            if (ARVALID && ARREADY && !(RVALID && RREADY && RLAST))
                outstanding_reads <= outstanding_reads + 1'b1;
            else if (!(ARVALID && ARREADY) && (RVALID && RREADY && RLAST))
                outstanding_reads <= outstanding_reads - 1'b1;
        end
    end

    always @(*) begin
        RREADY = rx_ready;
        rx_valid = RVALID;
        rx_data = RDATA;
        
        read_cmd_done = 1'b0;
        read_done_id  = RID[Q_DEPTH_BITS:0]; 

        if (RVALID && RREADY && RLAST) begin
            read_cmd_done = 1'b1;
        end
    end

    
    reg [2:0] outstanding_writes;
    reg [3:0] w_beat_cnt;
    reg [3:0] awlen_store;
    
    wire write_pipeline_full = (outstanding_writes != 3'd0);

    always @(*) begin
        write_cmd_ready = !write_pipeline_full && !AWVALID;
    end

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            AWVALID <= 1'b0;
            outstanding_writes <= 3'd0;
            w_beat_cnt <= 4'd0;
            awlen_store <= 4'd0;
        end else begin
            if (cmd_valid && cmd_rnw && write_cmd_ready) begin
                AWVALID <= 1'b1;
                AWADDR  <= cmd_addr;
                AWLEN   <= cmd_len[3:0] - 1'b1;
                AWSIZE  <= cmd_size;
                AWID    <= cmd_id;
                AWBURST <= 2'b01;
                awlen_store <= cmd_len[3:0] - 1'b1;
            end else if (AWVALID && AWREADY) begin
                AWVALID <= 1'b0;
            end

            if (AWVALID && AWREADY && !(BVALID && BREADY))
                outstanding_writes <= outstanding_writes + 1'b1;
            else if (!(AWVALID && AWREADY) && (BVALID && BREADY))
                outstanding_writes <= outstanding_writes - 1'b1;

            if (WVALID && WREADY) begin
                if (w_beat_cnt == awlen_store)
                    w_beat_cnt <= 4'd0;
                else
                    w_beat_cnt <= w_beat_cnt + 1'b1;
            end
        end
    end

    always @(*) begin
        WVALID = tx_valid;
        tx_ready = WREADY;
        WDATA = tx_data;
        
        WID = {ID_WIDTH{1'b0}}; 
        WSTRB = {(DATA_WIDTH/8){1'b1}};
        cmd_error = 1'b0;
        WLAST = (w_beat_cnt == awlen_store);
        
        BREADY = 1'b1; 
        write_cmd_done = 1'b0;
        write_done_id  = BID[Q_DEPTH_BITS:0];
        
        if (BVALID && BREADY) begin
            write_cmd_done = 1'b1;
        end
    end

endmodule
