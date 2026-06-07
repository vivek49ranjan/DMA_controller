module axi_stream_io #(
    parameter DATA_WIDTH = 32
)(
    input  wire                     clk,
    input  wire                     resetn,

    input  wire [DATA_WIDTH-1:0]    s_tdata,
    input  wire [(DATA_WIDTH/8)-1:0]s_tkeep,
    input  wire                     s_tvalid,
    input  wire                     s_tlast,
    output reg                      s_tready,

    output reg  [DATA_WIDTH-1:0]    m_tdata,
    output reg  [(DATA_WIDTH/8)-1:0]m_tkeep,
    output reg                      m_tvalid,
    output reg                      m_tlast,
    input  wire                     m_tready,

    output reg                      hw_tx_wr_en,
    output reg  [DATA_WIDTH-1:0]    hw_tx_wdata,
    input  wire                     hw_tx_full,

    output reg                      hw_rx_rd_en,
    input  wire [DATA_WIDTH-1:0]    hw_rx_rdata,
    input  wire                     hw_rx_empty
);

    localparam S_IDLE  = 2'd0;
    localparam S_WRITE = 2'd1;

    reg [1:0] s_state, s_next;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) s_state <= S_IDLE;
        else         s_state <= s_next;
    end

    always @(*) begin
        s_next      = s_state;
        s_tready    = 1'b0;
        hw_tx_wr_en = 1'b0;
        
        case (s_state)
            S_IDLE: begin
                if (!hw_tx_full) begin
                    s_tready = 1'b1; 
                    if (s_tvalid) begin
                        s_next = S_WRITE; 
                    end
                end
            end
            S_WRITE: begin
                hw_tx_wr_en = 1'b1; 
                s_next = S_IDLE;    
            end
            default: s_next = S_IDLE;
        endcase
    end

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            hw_tx_wdata <= {DATA_WIDTH{1'b0}};
        end else if (s_state == S_IDLE && s_tvalid && !hw_tx_full) begin
            hw_tx_wdata <= s_tdata; 
        end
    end


    localparam M_IDLE = 2'd0;
    localparam M_POP  = 2'd1;
    localparam M_SEND = 2'd2;

    reg [1:0] m_state, m_next;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) m_state <= M_IDLE;
        else         m_state <= m_next;
    end

    always @(*) begin
        m_next      = m_state;
        hw_rx_rd_en = 1'b0;
        m_tvalid    = 1'b0;
        
        case (m_state)
            M_IDLE: begin
                if (!hw_rx_empty) begin
                    hw_rx_rd_en = 1'b1; 
                    m_next = M_POP;
                end
            end
            M_POP: begin
                m_next = M_SEND; 
            end
            M_SEND: begin
                m_tvalid = 1'b1; 
                if (m_tready) begin
                    m_next = M_IDLE; 
                end
            end
            default: m_next = M_IDLE;
        endcase
    end

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            m_tdata <= {DATA_WIDTH{1'b0}};
            m_tkeep <= {(DATA_WIDTH/8){1'b0}};
            m_tlast <= 1'b0;
        end else if (m_state == M_POP) begin
            m_tdata <= hw_rx_rdata; 
            m_tkeep <= {(DATA_WIDTH/8){1'b1}};
            m_tlast <= 1'b1; 
        end
    end

endmodule
