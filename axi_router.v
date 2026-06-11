module axi_router #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input  wire ACLK,
    input  wire ARESETn,

    input  wire [ADDR_WIDTH-1:0]     M_AWADDR,
    input  wire [3:0]                M_AWLEN, 
    input  wire                      M_AWVALID,
    output wire                      M_AWREADY,
    input  wire [DATA_WIDTH-1:0]     M_WDATA,
    input  wire [(DATA_WIDTH/8)-1:0] M_WSTRB,
    input  wire                      M_WLAST,
    input  wire                      M_WVALID,
    output wire                      M_WREADY,
    output wire [1:0]                M_BRESP,
    output wire                      M_BVALID,
    input  wire                      M_BREADY,
    
    input  wire [ADDR_WIDTH-1:0]     M_ARADDR,
    input  wire [3:0]                M_ARLEN,
    input  wire                      M_ARVALID,
    output wire                      M_ARREADY,
    output wire [DATA_WIDTH-1:0]     M_RDATA,
    output wire [1:0]                M_RRESP,
    output wire                      M_RLAST,
    output wire                      M_RVALID,
    input  wire                      M_RREADY,

    output wire                      MEM_AWVALID,
    input  wire                      MEM_AWREADY,
    output wire                      MEM_WVALID,
    input  wire                      MEM_WREADY,
    input  wire [1:0]                MEM_BRESP,
    input  wire                      MEM_BVALID,
    output wire                      MEM_BREADY,
    output wire                      MEM_ARVALID,
    input  wire                      MEM_ARREADY,
    input  wire [DATA_WIDTH-1:0]     MEM_RDATA,
    input  wire [1:0]                MEM_RRESP,
    input  wire                      MEM_RLAST,
    input  wire                      MEM_RVALID,
    output wire                      MEM_RREADY,

    output wire [(8*DATA_WIDTH)-1:0]     m_tdata,
    output wire [(8*(DATA_WIDTH/8))-1:0] m_tkeep,
    output wire [7:0]                    m_tvalid,
    output wire [7:0]                    m_tlast,
    input  wire [7:0]                    m_tready,

    input  wire [(8*DATA_WIDTH)-1:0]     s_tdata,
    input  wire [7:0]                    s_tvalid,
    input  wire [7:0]                    s_tlast,
    output wire [7:0]                    s_tready
);

   
    wire is_aw_mem = (M_AWADDR[31:28] == 4'h0);
    wire is_aw_io  = (M_AWADDR[31:28] == 4'h4);
    wire [2:0] aw_io_idx = M_AWADDR[22:20];

    wire is_ar_mem = (M_ARADDR[31:28] == 4'h0);
    wire is_ar_io  = (M_ARADDR[31:28] == 4'h4);
    wire [2:0] ar_io_idx = M_ARADDR[22:20];

    wire [12:0] aw_bytes_to_4k = 13'h1000 - M_AWADDR[11:0];
    wire [10:0] aw_beats_to_4k = aw_bytes_to_4k >> $clog2(DATA_WIDTH/8);
    wire        aw_4k_violation = is_aw_mem && (({7'b0, M_AWLEN} + 1'b1) > aw_beats_to_4k);

    wire [12:0] ar_bytes_to_4k = 13'h1000 - M_ARADDR[11:0];
    wire [10:0] ar_beats_to_4k = ar_bytes_to_4k >> $clog2(DATA_WIDTH/8);
    wire        ar_4k_violation = is_ar_mem && (({7'b0, M_ARLEN} + 1'b1) > ar_beats_to_4k);

  
    reg [2:0] w_state;
    localparam W_IDLE        = 3'd0;
    localparam W_NORM_ACTIVE = 3'd1;
    localparam W_SPLIT_AW1   = 3'd2;
    localparam W_SPLIT_W1    = 3'd3;
    localparam W_SPLIT_B1    = 3'd4;
    localparam W_SPLIT_AW2   = 3'd5;
    localparam W_SPLIT_W2    = 3'd6;
    localparam W_SPLIT_B2    = 3'd7;

    reg [ADDR_WIDTH-1:0] r_awaddr;
    reg [3:0]            r_awlen;
    reg [10:0]           r_aw_split_beats;
    reg [10:0]           w_beat_count;
    
    reg [1:0] w_target_type; 
    reg [2:0] w_target_idx;  
    reg       io_bvalid_reg;

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            w_state       <= W_IDLE;
            io_bvalid_reg <= 1'b0;
        end else begin
            case (w_state)
                W_IDLE: begin
                    if (M_AWVALID && M_AWREADY) begin
                        w_target_type <= is_aw_io ? 2'd1 : 2'd0;
                        w_target_idx  <= aw_io_idx;

                        if (aw_4k_violation) begin
                            r_awaddr         <= M_AWADDR;
                            r_awlen          <= M_AWLEN;
                            r_aw_split_beats <= aw_beats_to_4k;
                            w_beat_count     <= 0;
                            w_state          <= W_SPLIT_AW1;
                        end else begin
                            w_state <= W_NORM_ACTIVE;
                        end
                    end
                end
                
                W_NORM_ACTIVE: begin
                    if (M_BVALID && M_BREADY) 
                        w_state <= W_IDLE;
                    
                    if (w_target_type == 2'd1 && M_WVALID && M_WREADY && M_WLAST)
                        io_bvalid_reg <= 1'b1;
                    else if (io_bvalid_reg && M_BREADY)
                        io_bvalid_reg <= 1'b0;
                end
                
                W_SPLIT_AW1: begin
                    if (MEM_AWREADY) w_state <= W_SPLIT_W1;
                end
                
                W_SPLIT_W1: begin
                    if (M_WVALID && MEM_WREADY) begin
                        w_beat_count <= w_beat_count + 1'b1;
                        if (w_beat_count == r_aw_split_beats - 1) 
                            w_state <= W_SPLIT_B1;
                    end
                end
                
                W_SPLIT_B1: begin
                    if (MEM_BVALID) w_state <= W_SPLIT_AW2; 
                end
                
                W_SPLIT_AW2: begin
                    if (MEM_AWREADY) w_state <= W_SPLIT_W2;
                end
                
                W_SPLIT_W2: begin
                    if (M_WVALID && MEM_WREADY && M_WLAST) w_state <= W_SPLIT_B2;
                end
                
                W_SPLIT_B2: begin
                    if (MEM_BVALID && M_BREADY) w_state <= W_IDLE; 
                end
            endcase
        end
    end

    assign MEM_AWVALID = (w_state == W_IDLE && !aw_4k_violation && is_aw_mem) ? M_AWVALID :
                         (w_state == W_SPLIT_AW1 || w_state == W_SPLIT_AW2) ? 1'b1 : 1'b0;

    assign MEM_AWADDR  = (w_state == W_SPLIT_AW1) ? r_awaddr :
                         (w_state == W_SPLIT_AW2) ? r_awaddr + (r_aw_split_beats * (DATA_WIDTH/8)) :
                         M_AWADDR;

    assign MEM_AWLEN   = (w_state == W_SPLIT_AW1) ? r_aw_split_beats[3:0] - 1'b1 :
                         (w_state == W_SPLIT_AW2) ? r_awlen - r_aw_split_beats[3:0] :
                         M_AWLEN;

    assign M_AWREADY   = (w_state == W_IDLE) ? (aw_4k_violation ? 1'b1 : (is_aw_mem ? MEM_AWREADY : 1'b1)) : 1'b0;

    wire current_tx_tready = m_tready[w_target_idx];
    assign m_tdata  = {8{M_WDATA}};
    assign m_tkeep  = {8{M_WSTRB}};
    assign m_tlast  = {8{M_WLAST}};

    assign MEM_WVALID  = (w_state == W_NORM_ACTIVE && w_target_type == 2'd0) ? M_WVALID :
                         (w_state == W_SPLIT_W1 || w_state == W_SPLIT_W2) ? M_WVALID : 1'b0;
                         
    assign m_tvalid    = (w_state == W_NORM_ACTIVE && w_target_type == 2'd1) ? (8'b1 << w_target_idx) & {8{M_WVALID}} : 8'd0;

    assign M_WREADY    = (w_state == W_NORM_ACTIVE) ? (w_target_type == 2'd0 ? MEM_WREADY : current_tx_tready) :
                         (w_state == W_SPLIT_W1 || w_state == W_SPLIT_W2) ? MEM_WREADY : 1'b0;

    assign MEM_WLAST   = (w_state == W_SPLIT_W1) ? (w_beat_count == r_aw_split_beats - 1) : M_WLAST;

    assign M_BVALID    = (w_state == W_NORM_ACTIVE) ? (w_target_type == 2'd0 ? MEM_BVALID : io_bvalid_reg) :
                         (w_state == W_SPLIT_B2) ? MEM_BVALID : 1'b0;

    assign MEM_BREADY  = (w_state == W_NORM_ACTIVE && w_target_type == 2'd0) ? M_BREADY :
                         (w_state == W_SPLIT_B1) ? 1'b1 :
                         (w_state == W_SPLIT_B2) ? M_BREADY : 1'b0;

    assign M_BRESP     = (w_state == W_NORM_ACTIVE && w_target_type == 2'd0) ? MEM_BRESP :
                         (w_state == W_SPLIT_B2) ? MEM_BRESP : 2'b00;


   
    reg [2:0] r_state;
    localparam R_IDLE        = 3'd0;
    localparam R_NORM_ACTIVE = 3'd1;
    localparam R_SPLIT_AR1   = 3'd2;
    localparam R_SPLIT_R1    = 3'd3;
    localparam R_SPLIT_AR2   = 3'd4;
    localparam R_SPLIT_R2    = 3'd5;

    reg [ADDR_WIDTH-1:0] r_araddr;
    reg [3:0]            r_arlen;
    reg [10:0]           r_ar_split_beats;
    
    reg [1:0] r_target_type; 
    reg [2:0] r_target_idx;  
    reg [3:0] io_rlast_count;
    reg [3:0] io_rlast_target;

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            r_state <= R_IDLE;
        end else begin
            case (r_state)
                R_IDLE: begin
                    if (M_ARVALID && M_ARREADY) begin
                        r_target_type <= is_ar_io ? 2'd1 : 2'd0;
                        r_target_idx  <= ar_io_idx;

                        if (ar_4k_violation) begin
                            r_araddr         <= M_ARADDR;
                            r_arlen          <= M_ARLEN;
                            r_ar_split_beats <= ar_beats_to_4k;
                            r_state          <= R_SPLIT_AR1;
                        end else begin
                            r_state <= R_NORM_ACTIVE;
                            if (is_ar_io) begin
                                io_rlast_target <= M_ARLEN;
                                io_rlast_count  <= 4'd0;
                            end
                        end
                    end
                end
                
                R_NORM_ACTIVE: begin
                    if (M_RVALID && M_RREADY && M_RLAST) r_state <= R_IDLE;
                    
                    if (r_target_type == 2'd1 && M_RVALID && M_RREADY) begin
                        io_rlast_count <= io_rlast_count + 1'b1;
                    end
                end
                
                R_SPLIT_AR1: begin
                    if (MEM_ARREADY) r_state <= R_SPLIT_R1;
                end
                
                R_SPLIT_R1: begin
                    if (MEM_RVALID && M_RREADY && MEM_RLAST) r_state <= R_SPLIT_AR2;
                end
                
                R_SPLIT_AR2: begin
                    if (MEM_ARREADY) r_state <= R_SPLIT_R2;
                end
                
                R_SPLIT_R2: begin
                    if (MEM_RVALID && M_RREADY && MEM_RLAST) r_state <= R_IDLE;
                end
            endcase
        end
    end

    wire io_rlast_gen = (io_rlast_count == io_rlast_target);

    assign MEM_ARVALID = (r_state == R_IDLE && !ar_4k_violation && is_ar_mem) ? M_ARVALID :
                         (r_state == R_SPLIT_AR1 || r_state == R_SPLIT_AR2) ? 1'b1 : 1'b0;

    assign MEM_ARADDR  = (r_state == R_SPLIT_AR1) ? r_araddr :
                         (r_state == R_SPLIT_AR2) ? r_araddr + (r_ar_split_beats * (DATA_WIDTH/8)) :
                         M_ARADDR;

    assign MEM_ARLEN   = (r_state == R_SPLIT_AR1) ? r_ar_split_beats[3:0] - 1'b1 :
                         (r_state == R_SPLIT_AR2) ? r_arlen - r_ar_split_beats[3:0] :
                         M_ARLEN;

    assign M_ARREADY   = (r_state == R_IDLE) ? (ar_4k_violation ? 1'b1 : (is_ar_mem ? MEM_ARREADY : 1'b1)) : 1'b0;

    wire [DATA_WIDTH-1:0] current_rx_tdata  = s_tdata[r_target_idx * DATA_WIDTH +: DATA_WIDTH];
    wire                  current_rx_tvalid = s_tvalid[r_target_idx];

    assign s_tready    = (r_state == R_NORM_ACTIVE && r_target_type == 2'd1) ? (8'b1 << r_target_idx) & {8{M_RREADY}} : 8'd0;
    
    assign MEM_RREADY  = (r_state == R_NORM_ACTIVE && r_target_type == 2'd0) ? M_RREADY :
                         (r_state == R_SPLIT_R1 || r_state == R_SPLIT_R2) ? M_RREADY : 1'b0;

    assign M_RVALID    = (r_state == R_NORM_ACTIVE) ? (r_target_type == 2'd0 ? MEM_RVALID : current_rx_tvalid) :
                         (r_state == R_SPLIT_R1 || r_state == R_SPLIT_R2) ? MEM_RVALID : 1'b0;

    assign M_RDATA     = (r_state == R_NORM_ACTIVE) ? (r_target_type == 2'd0 ? MEM_RDATA : current_rx_tdata) :
                         (r_state == R_SPLIT_R1 || r_state == R_SPLIT_R2) ? MEM_RDATA : {DATA_WIDTH{1'b0}};

    assign M_RLAST     = (r_state == R_NORM_ACTIVE) ? (r_target_type == 2'd0 ? MEM_RLAST : io_rlast_gen) :
                         (r_state == R_SPLIT_R1) ? 1'b0 : 
                         (r_state == R_SPLIT_R2) ? MEM_RLAST : 1'b0;

    assign M_RRESP     = (r_state == R_NORM_ACTIVE && r_target_type == 2'd0) ? MEM_RRESP :
                         (r_state == R_SPLIT_R1 || r_state == R_SPLIT_R2) ? MEM_RRESP : 2'b00;

endmodule
