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

  
    reg write_active;
    reg aw_pending;  
    reg w_pending;   

    reg read_active;
    reg ar_pending;  

    reg [ADDR_WIDTH-1:0] aw_addr_reg;  
    reg [ADDR_WIDTH-1:0] w_addr_reg;  
    reg [ADDR_WIDTH-1:0] r_addr_reg;   
    
    reg [2:0]            w_size_reg, r_size_reg;
    reg [15:0]           w_len_reg, r_len_reg;
    reg [3:0]            w_burst_count;

    wire [ADDR_WIDTH-1:0] w_align_mask = ~((1 << w_size_reg) - 1);
    
    reg [127:0] unshifted_strb; 
    reg [31:0]  addr_offset;

  
    always @(*) begin
        write_cmd_ready = !write_active;
        read_cmd_ready  = !read_active;

        write_cmd_done = (write_active && BVALID && BREADY && (BRESP[1] == 1'b0));
        read_cmd_done  = (read_active  && RVALID && RREADY && RLAST && (RRESP[1] == 1'b0));
        
        cmd_error = ((write_active && BVALID && BREADY && BRESP[1] == 1'b1) ||
                     (read_active  && RVALID && RREADY && RLAST && RRESP[1] == 1'b1));

        AWID    = ID_VAL;
        AWADDR  = aw_addr_reg;
        AWSIZE  = w_size_reg;
        AWLEN   = w_len_reg[3:0] - 1'b1;
        AWBURST = 2'b01;
        AWVALID = aw_pending;

        WID      = ID_VAL;
        WDATA    = tx_data;
        WLAST    = (w_burst_count == (w_len_reg[3:0] - 1'b1));
        WVALID   = w_pending & tx_valid; 
        tx_ready = w_pending & WREADY;   

        unshifted_strb = (128'b1 << (1 << w_size_reg)) - 1;
        addr_offset    = w_addr_reg & ((DATA_WIDTH/8) - 1);
        WSTRB          = unshifted_strb << addr_offset;

        
        BREADY = write_active;

        ARID    = ID_VAL;
        ARADDR  = r_addr_reg;
        ARSIZE  = r_size_reg;
        ARLEN   = r_len_reg[3:0] - 1'b1;
        ARBURST = 2'b01;
        ARVALID = ar_pending;

        RREADY   = read_active & rx_ready;
        rx_valid = read_active & RVALID;
        rx_data  = RDATA;
    end

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            write_active  <= 1'b0;
            aw_pending    <= 1'b0;
            w_pending     <= 1'b0;
            w_burst_count <= 4'd0;
            
            aw_addr_reg <= {ADDR_WIDTH{1'b0}};
            w_addr_reg  <= {ADDR_WIDTH{1'b0}};
            w_size_reg  <= 3'd0;
            w_len_reg   <= 16'd0;
        end else begin
            if (cmd_valid && cmd_rnw && !write_active) begin
                write_active  <= 1'b1;
                aw_pending    <= 1'b1;
                w_pending     <= 1'b1;
                w_burst_count <= 4'd0;
                
                aw_addr_reg <= cmd_addr;
                w_addr_reg  <= cmd_addr;
                w_size_reg  <= cmd_size;
                w_len_reg   <= cmd_len;
            end
            
            if (aw_pending && AWREADY) begin
                aw_pending <= 1'b0;
            end
            
            if (w_pending && WVALID && WREADY) begin
                w_addr_reg <= (w_addr_reg + (1 << w_size_reg)) & w_align_mask;
                
                if (WLAST) w_pending <= 1'b0;
                else       w_burst_count <= w_burst_count + 1'b1;
            end
            
            if (write_active && BVALID && BREADY) begin
                write_active <= 1'b0;
            end
        end
    end

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            read_active <= 1'b0;
            ar_pending  <= 1'b0;
            
            r_addr_reg <= {ADDR_WIDTH{1'b0}};
            r_size_reg <= 3'd0;
            r_len_reg  <= 16'd0;
        end else begin
            if (cmd_valid && !cmd_rnw && !read_active) begin
                read_active <= 1'b1;
                ar_pending  <= 1'b1;
                
                r_addr_reg <= cmd_addr;
                r_size_reg <= cmd_size;
                r_len_reg  <= cmd_len;
            end
            
            if (ar_pending && ARREADY) begin
                ar_pending <= 1'b0;
            end
            
            if (read_active && RVALID && RREADY && RLAST) begin
                read_active <= 1'b0;
            end
        end
    end

endmodule
