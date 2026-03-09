module dmac_controller #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input  wire                   clk,
    input  wire                   resetn,

    output reg  [ADDR_WIDTH-1:0]  cmd_addr,
    output reg  [15:0]            cmd_len,
    output reg                    cmd_rnw,
    output reg                    cmd_valid,
    input  wire                   cmd_ready,
    input  wire                   cmd_done,
    input  wire                   cmd_error,

    output reg  [DATA_WIDTH-1:0]  tx_data,
    output reg                    tx_valid,
    input  wire                   tx_ready,

    input  wire [DATA_WIDTH-1:0]  rx_data,
    input  wire                   rx_valid,
    output reg                    rx_ready,

    output reg                    cpu_intr,

    input  wire                   reg_wr_en,
    input  wire [ADDR_WIDTH-1:0]  reg_wr_addr,
    input  wire [DATA_WIDTH-1:0]  reg_wdata,
    input  wire                   reg_rd_en,
    input  wire [ADDR_WIDTH-1:0]  reg_rd_addr,
    output reg  [DATA_WIDTH-1:0]  reg_rdata,

    output reg                    fifo_wr_en,
    output reg  [DATA_WIDTH-1:0]  fifo_wdata,
    input  wire                   fifo_full,
    output reg                    fifo_rd_en,
    input  wire [DATA_WIDTH-1:0]  fifo_rdata,
    input  wire                   fifo_empty
);

    reg [31:0] reg_ctrl;          
    reg [31:0] reg_status;        
    reg [31:0] reg_curr_desc_ptr; 
    reg [31:0] reg_irq_clear;     

    localparam [3:0] 
        C_IDLE       = 4'd0,
        C_FETCH_REQ  = 4'd1,
        C_FETCH_WAIT = 4'd2,
        C_DISPATCH   = 4'd3,
        C_WAIT_ENG   = 4'd4,
        C_UPDATE_REQ = 4'd5,
        C_UPDATE_WAIT= 4'd6,
        C_NEXT       = 4'd7,
        C_DONE       = 4'd8;

    reg [3:0] c_state, c_next_state;
    reg [2:0] desc_ptr;
    reg [31:0] current_desc [0:7];
    
    reg        disp_start;
    wire       read_engine_done;
    wire       write_engine_done;
    reg        ctrl_cmd_req, read_cmd_req, write_cmd_req;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            reg_ctrl          <= 32'd0;
            reg_curr_desc_ptr <= 32'd0;
            reg_irq_clear     <= 32'd0;
        end else if (reg_wr_en) begin
            case (reg_wr_addr[7:0])
                8'h00: reg_ctrl          <= reg_wdata;
                8'h14: reg_curr_desc_ptr <= reg_wdata;
                8'h18: reg_irq_clear     <= reg_wdata;
            endcase
        end else begin
            if (reg_ctrl[0])      reg_ctrl[0]      <= 1'b0; 
            if (reg_irq_clear[0]) reg_irq_clear[0] <= 1'b0; 
            
            if (c_state == C_UPDATE_REQ && cmd_valid && cmd_ready && ctrl_cmd_req) begin
                reg_curr_desc_ptr <= current_desc[0];
            end
        end
    end

    always @(*) begin
        c_next_state = c_state; 
        
        case (c_state)
            C_IDLE: begin
                if (reg_ctrl[0]) c_next_state = C_FETCH_REQ;
            end
            C_FETCH_REQ: begin
                if (cmd_valid && cmd_ready && ctrl_cmd_req) c_next_state = C_FETCH_WAIT;
            end
            C_FETCH_WAIT: begin
                if (cmd_done) c_next_state = C_DISPATCH;
            end
            C_DISPATCH: begin
                c_next_state = C_WAIT_ENG;
            end
            C_WAIT_ENG: begin
                if (read_engine_done && write_engine_done) c_next_state = C_UPDATE_REQ;
            end
            C_UPDATE_REQ: begin
                if (cmd_valid && cmd_ready && ctrl_cmd_req) c_next_state = C_UPDATE_WAIT;
            end
            C_UPDATE_WAIT: begin
                if (cmd_done) c_next_state = C_NEXT;
            end
            C_NEXT: begin
                if (current_desc[0] == 32'd0) c_next_state = C_DONE;
                else c_next_state = C_FETCH_REQ;
            end
            C_DONE: begin
                if (reg_irq_clear[0]) c_next_state = C_IDLE;
            end
            default: c_next_state = C_IDLE;
        endcase
    end

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            c_state      <= C_IDLE;
            disp_start   <= 1'b0;
            ctrl_cmd_req <= 1'b0;
            desc_ptr     <= 3'd0;
            cpu_intr     <= 1'b0;
            reg_status   <= 32'd0;
        end else begin
            c_state    <= c_next_state;
            disp_start <= 1'b0; 
            
            case (c_state)
                C_IDLE: begin
                    desc_ptr     <= 3'd0;
                    ctrl_cmd_req <= 1'b0;
                    if (reg_ctrl[0]) begin
                        reg_status[0] <= 1'b1; 
                    end
                end
                
                C_FETCH_REQ: begin
                    ctrl_cmd_req <= 1'b1; 
                    if (cmd_valid && cmd_ready && ctrl_cmd_req) begin
                        ctrl_cmd_req <= 1'b0;
                    end
                end
                
                C_FETCH_WAIT: begin
                    if (rx_valid) begin
                        current_desc[desc_ptr] <= rx_data;
                        desc_ptr <= desc_ptr + 1'b1;
                    end
                end
                
                C_DISPATCH: begin
                    disp_start <= 1'b1; 
                end
                
                C_WAIT_ENG: begin
                end
                
                C_UPDATE_REQ: begin
                    ctrl_cmd_req    <= 1'b1;
                    current_desc[6] <= 32'd1; 
                    if (cmd_valid && cmd_ready && ctrl_cmd_req) begin
                        ctrl_cmd_req <= 1'b0;
                    end
                end
                
                C_UPDATE_WAIT: begin
                end
                
                C_NEXT: begin
                end
                
                C_DONE: begin
                    cpu_intr      <= 1'b1;
                    reg_status[1] <= 1'b1; 
                    reg_status[0] <= 1'b0; 
                    if (reg_irq_clear[0]) begin
                        cpu_intr <= 1'b0;
                    end
                end
            endcase
        end
    end

    localparam [1:0] R_IDLE = 2'd0, R_REQ = 2'd1, R_STREAM = 2'd2;
    reg [1:0] r_state;

    assign read_engine_done = (r_state == R_IDLE);

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            r_state      <= R_IDLE;
            read_cmd_req <= 1'b0;
            fifo_wr_en   <= 1'b0;
        end else begin
            fifo_wr_en <= 1'b0;
            
            case (r_state)
                R_IDLE: begin
                    if (disp_start) begin
                        r_state      <= R_REQ;
                        read_cmd_req <= 1'b1;
                    end
                end
                R_REQ: begin
                    if (cmd_valid && cmd_ready && read_cmd_req) begin
                        read_cmd_req <= 1'b0;
                        r_state      <= R_STREAM;
                    end
                end
                R_STREAM: begin
                    if (rx_valid && !fifo_full) begin
                        fifo_wr_en <= 1'b1;
                        fifo_wdata <= rx_data;
                    end
                    if (cmd_done) r_state <= R_IDLE;
                end
            endcase
        end
    end

    localparam [1:0] W_IDLE = 2'd0, W_REQ = 2'd1, W_STREAM = 2'd2;
    reg [1:0] w_state;

    assign write_engine_done = (w_state == W_IDLE);

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            w_state       <= W_IDLE;
            write_cmd_req <= 1'b0;
            fifo_rd_en    <= 1'b0;
            tx_valid      <= 1'b0;
        end else begin
            fifo_rd_en <= 1'b0;
            tx_valid   <= 1'b0;
            
            case (w_state)
                W_IDLE: begin
                    if (disp_start) begin
                        w_state       <= W_REQ;
                        write_cmd_req <= 1'b1;
                    end
                end
                W_REQ: begin
                    if (cmd_valid && cmd_ready && write_cmd_req) begin
                        write_cmd_req <= 1'b0;
                        w_state       <= W_STREAM;
                    end
                end
                W_STREAM: begin
                    if (!fifo_empty) begin
                        tx_valid <= 1'b1;
                        tx_data  <= fifo_rdata;
                        if (tx_ready) fifo_rd_en <= 1'b1;
                    end
                    if (cmd_done) w_state <= W_IDLE;
                end
            endcase
        end
    end

    always @(*) begin
        cmd_valid = 1'b0;
        cmd_addr  = 32'd0;
        cmd_len   = 16'd0;
        cmd_rnw   = 1'b0;
        rx_ready  = 1'b0;

        if (ctrl_cmd_req) begin
            cmd_valid = 1'b1;
            cmd_rnw   = (c_state == C_UPDATE_REQ) ? 1'b1 : 1'b0;
            cmd_addr  = reg_curr_desc_ptr;
            cmd_len   = (c_state == C_UPDATE_REQ) ? 16'd0 : 16'd7; 
            rx_ready  = (c_state == C_FETCH_WAIT);
        end 
        else if (read_cmd_req) begin
            cmd_valid = 1'b1;
            cmd_rnw   = 1'b0; 
            cmd_addr  = current_desc[2]; 
            cmd_len   = current_desc[4][15:0];
            rx_ready  = !fifo_full; 
        end 
        else if (write_cmd_req) begin
            cmd_valid = 1'b1;
            cmd_rnw   = 1'b1; 
            cmd_addr  = current_desc[3]; 
            cmd_len   = current_desc[4][15:0];
        end
        else begin
            rx_ready = (r_state == R_STREAM) ? !fifo_full : 1'b0;
        end
    end

endmodule