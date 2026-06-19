module axi_io_slave #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter ID_WIDTH   = 4,
    parameter ROM_DEPTH  = 1024,
    parameter INIT_FILE  = "default_io.mem",
    parameter BASE_ADDR  = 32'h4000_0000 
)(
    input  wire                     ACLK,
    input  wire                     ARESETN,

    input  wire [ID_WIDTH-1:0]      AWID,
    input  wire [ADDR_WIDTH-1:0]    AWADDR,
    input  wire [3:0]               AWLEN,
    input  wire [2:0]               AWSIZE,
    input  wire [1:0]               AWBURST,
    input  wire                     AWVALID,
    output wire                     AWREADY,

    input  wire [ID_WIDTH-1:0]      WID,
    input  wire [DATA_WIDTH-1:0]    WDATA,
    input  wire [(DATA_WIDTH/8)-1:0] WSTRB,
    input  wire                     WLAST,
    input  wire                     WVALID,
    output wire                     WREADY,

    output reg  [ID_WIDTH-1:0]      BID,
    output reg  [1:0]               BRESP,
    output reg                      BVALID,
    input  wire                     BREADY,

    input  wire [ID_WIDTH-1:0]      ARID,
    input  wire [ADDR_WIDTH-1:0]    ARADDR,
    input  wire [3:0]               ARLEN,
    input  wire [2:0]               ARSIZE,
    input  wire [1:0]               ARBURST,
    input  wire                     ARVALID,
    output wire                     ARREADY,

    output reg  [ID_WIDTH-1:0]      RID,
    output reg  [DATA_WIDTH-1:0]    RDATA,
    output reg  [1:0]               RRESP,
    output reg                      RLAST,
    output reg                      RVALID,
    input  wire                     RREADY
);

  
    reg [DATA_WIDTH-1:0] internal_rom [0:ROM_DEPTH-1];
    
    initial begin
        $readmemh(INIT_FILE, internal_rom);
    end

    
    reg [ID_WIDTH-1:0]   ar_id_queue    [0:3];
    reg [ADDR_WIDTH-1:0] ar_addr_queue  [0:3];
    reg [3:0]            ar_len_queue   [0:3];
    reg [2:0]            ar_size_queue  [0:3];
    reg [1:0]            ar_burst_queue [0:3];
    
    reg [1:0] ar_head, ar_tail;
    reg [2:0] ar_count;
    
    assign ARREADY = (ar_count < 3'd4);

    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            ar_head  <= 2'd0; ar_tail  <= 2'd0; ar_count <= 3'd0;
        end else begin
            if (ARVALID && ARREADY && !(RVALID && RREADY && RLAST)) begin
                ar_id_queue[ar_tail]    <= ARID;
                ar_addr_queue[ar_tail]  <= ARADDR;
                ar_len_queue[ar_tail]   <= ARLEN;
                ar_size_queue[ar_tail]  <= ARSIZE;
                ar_burst_queue[ar_tail] <= ARBURST;
                ar_tail  <= ar_tail + 1'b1;
                ar_count <= ar_count + 1'b1;
            end else if (!(ARVALID && ARREADY) && (RVALID && RREADY && RLAST)) begin
                ar_head  <= ar_head + 1'b1;
                ar_count <= ar_count - 1'b1;
            end else if ((ARVALID && ARREADY) && (RVALID && RREADY && RLAST)) begin
                ar_id_queue[ar_tail]    <= ARID;
                ar_addr_queue[ar_tail]  <= ARADDR;
                ar_len_queue[ar_tail]   <= ARLEN;
                ar_size_queue[ar_tail]  <= ARSIZE;
                ar_burst_queue[ar_tail] <= ARBURST;
                ar_tail <= ar_tail + 1'b1;
                ar_head <= ar_head + 1'b1;
            end
        end
    end

  
    reg [3:0]  r_beat_count;
    reg        rvalid_reg;
    reg [31:0] rom_read_ptr;
    reg [ADDR_WIDTH-1:0] r_current_addr;

    wire handshaking = (RVALID && RREADY);
    
   
    wire [ADDR_WIDTH-1:0] r_align_mask = ~((32'd1 << ar_size_queue[ar_head]) - 1);
    wire r_is_unsupported = (ar_burst_queue[ar_head] != 2'b01);
	 
    wire [31:0] next_rom_ptr = (handshaking && !r_is_unsupported) ? 
                               ((rom_read_ptr == ROM_DEPTH - 1) ? 32'd0 : rom_read_ptr + 1'b1) : 
                               rom_read_ptr;

    always @(*) begin
        RVALID = rvalid_reg;
        RID    = ar_id_queue[ar_head];
        RRESP  = r_is_unsupported ? 2'b10 : 2'b00; 
        RLAST  = (r_beat_count == ar_len_queue[ar_head]);
    end

    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            rom_read_ptr <= 32'd0;
        end else begin
            rom_read_ptr <= next_rom_ptr;
        end
    end

    always @(posedge ACLK) begin
        RDATA <= internal_rom[next_rom_ptr];
    end

    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            r_beat_count <= 4'd0;
            rvalid_reg   <= 1'b0;
            r_current_addr <= {ADDR_WIDTH{1'b0}};
        end else begin
            if (ar_count > 0) begin
                if (!rvalid_reg) begin
                    rvalid_reg <= 1'b1;
                end else if (handshaking) begin
                    if (RLAST) begin
                        rvalid_reg   <= (ar_count > 1);
                        r_beat_count <= 4'd0;
                    end else begin
                        r_beat_count <= r_beat_count + 1'b1;
                        if (r_beat_count == 0)
                            r_current_addr <= (ar_addr_queue[ar_head] & r_align_mask) + (1 << ar_size_queue[ar_head]);
                        else
                            r_current_addr <= r_current_addr + (1 << ar_size_queue[ar_head]);
                    end
                end
            end else begin
                rvalid_reg <= 1'b0;
            end
        end
    end

    
    reg [ID_WIDTH-1:0]   aw_id_queue    [0:3];
    reg [ADDR_WIDTH-1:0] aw_addr_queue  [0:3];
    reg [2:0]            aw_size_queue  [0:3];
    reg [1:0]            aw_burst_queue [0:3];
    
    reg [1:0] aw_head, aw_tail;
    reg [2:0] aw_count;

    assign AWREADY = (aw_count < 3'd4);

    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            aw_head <= 2'd0; aw_tail <= 2'd0; aw_count <= 3'd0;
        end else begin
            if (AWVALID && AWREADY && !(BVALID && BREADY)) begin
                aw_id_queue[aw_tail]    <= AWID;
                aw_addr_queue[aw_tail]  <= AWADDR;
                aw_size_queue[aw_tail]  <= AWSIZE;
                aw_burst_queue[aw_tail] <= AWBURST;
                aw_tail  <= aw_tail + 1'b1;
                aw_count <= aw_count + 1'b1;
            end else if (!(AWVALID && AWREADY) && (BVALID && BREADY)) begin
                aw_head  <= aw_head + 1'b1;
                aw_count <= aw_count - 1'b1;
            end else if ((AWVALID && AWREADY) && (BVALID && BREADY)) begin
                aw_id_queue[aw_tail]    <= AWID;
                aw_addr_queue[aw_tail]  <= AWADDR;
                aw_size_queue[aw_tail]  <= AWSIZE;
                aw_burst_queue[aw_tail] <= AWBURST;
                aw_tail <= aw_tail + 1'b1;
                aw_head <= aw_head + 1'b1;
            end
        end
    end
    
    reg w_first_beat;
    reg [ADDR_WIDTH-1:0] w_current_addr;

    wire [ADDR_WIDTH-1:0] w_align_mask = ~((32'd1 << aw_size_queue[aw_head]) - 1);
    wire w_is_unsupported = (aw_burst_queue[aw_head] != 2'b01);

    assign WREADY = (aw_count > 0) && !BVALID;
    
    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            BVALID <= 1'b0; 
            BID <= {ID_WIDTH{1'b0}}; 
            BRESP <= 2'b00;
            w_first_beat <= 1'b1;
            w_current_addr <= {ADDR_WIDTH{1'b0}};
        end else begin
            if (WVALID && WREADY) begin
                w_first_beat <= WLAST;
                
                if (w_first_beat)
                    w_current_addr <= (aw_addr_queue[aw_head] & w_align_mask) + (1 << aw_size_queue[aw_head]);
                else
                    w_current_addr <= w_current_addr + (1 << aw_size_queue[aw_head]);

                if (WLAST) begin
                    BVALID <= 1'b1; 
                    BID    <= aw_id_queue[aw_head]; 
                    BRESP  <= w_is_unsupported ? 2'b10 : 2'b00; 
                end
            end else if (BVALID && BREADY) begin
                BVALID <= 1'b0;
            end
        end
    end
endmodule
