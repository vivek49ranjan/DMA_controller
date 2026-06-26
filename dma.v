module dmac_controller #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter Q_DEPTH_BITS = 2 
)(
    input  wire                   clk,
    input  wire                   resetn,

    output reg  [ADDR_WIDTH-1:0]  cmd_addr,
    output reg  [15:0]            cmd_len,
    output reg  [2:0]             cmd_size,
    output reg                    cmd_rnw,
    output reg  [Q_DEPTH_BITS:0]  cmd_id,       
    output reg                    cmd_valid,
    input  wire                   read_cmd_ready,
    input  wire                   write_cmd_ready,
    
    input  wire                   read_cmd_done,
    input  wire [Q_DEPTH_BITS:0]  read_done_id, 
    input  wire                   write_cmd_done,
    input  wire [Q_DEPTH_BITS:0]  write_done_id,
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
    
    output reg                    fifo_wr_en,
    output reg  [DATA_WIDTH-1:0]  fifo_wdata,
    input  wire                   fifo_full,
    
    output reg                    fifo_rd_en,
    input  wire [DATA_WIDTH-1:0]  fifo_rdata,
    input  wire                   fifo_empty
);

    reg [31:0] desc_queue [0:3][0:7];
    reg [1:0]  alloc_ptr;   
    reg [1:0]  disp_ptr;    
    reg [1:0]  commit_ptr;  

    reg [3:0]  valid_slots; 
    reg [3:0]  read_issued;
    reg [3:0]  read_completed, write_completed;

    wire queue_full  = (alloc_ptr + 1'b1 == commit_ptr) && valid_slots[alloc_ptr];
    
    reg  fetch_desc_update;
    reg  [31:0] fetch_desc_next_ptr;

    reg [31:0] reg_ctrl, reg_curr_desc_ptr, reg_irq_clear;     
    reg global_error;
    
    reg running;
    reg end_of_chain_fetched; 

    localparam U_IDLE = 2'd0, U_REQ = 2'd1, U_WAIT = 2'd2;
    reg [1:0] u_state;
    reg [2:0] desc_count; 

    wire is_batch_end  = (desc_count == 3'd7) || (desc_queue[commit_ptr][0] == 32'd0);
    wire status_retire = (u_state == U_WAIT) && write_cmd_done && (write_done_id == {1'b1, commit_ptr});

    reg [3:0] intr_pending_count;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            reg_ctrl           <= 32'd0;
            reg_curr_desc_ptr  <= 32'd0;
            reg_irq_clear      <= 32'd0;
            global_error       <= 1'b0;
            cpu_intr           <= 1'b0;
            running            <= 1'b0; 
            intr_pending_count <= 4'd0;
        end else begin
            if (cmd_error) 
                global_error <= 1'b1;

            if (reg_irq_clear[0]) begin
                reg_irq_clear[0] <= 1'b0;
                global_error     <= 1'b0; 
                
                if (!(status_retire && is_batch_end) && intr_pending_count > 0) begin
                    intr_pending_count <= intr_pending_count - 1'b1;
                    if (intr_pending_count == 4'd1) cpu_intr <= 1'b0;
                end
            end
            
            if (reg_ctrl[0]) begin
                reg_ctrl[0] <= 1'b0; 
                running     <= 1'b1; 
            end

            if (end_of_chain_fetched && valid_slots == 4'd0 && u_state == U_IDLE) begin
                running <= 1'b0;
            end
            
            if (global_error) begin
                running <= 1'b0;
            end

            if (reg_wr_en) begin
                case (reg_wr_addr[7:0])
                    8'h00: reg_ctrl          <= reg_wdata;
                    8'h14: reg_curr_desc_ptr <= reg_wdata;
                    8'h18: reg_irq_clear     <= reg_wdata;
                    default: ; 
                endcase
            end else if (fetch_desc_update) begin
                reg_curr_desc_ptr <= fetch_desc_next_ptr;
            end

            if (status_retire && is_batch_end) begin
                if (!reg_irq_clear[0]) begin
                    intr_pending_count <= intr_pending_count + 1'b1;
                    cpu_intr           <= 1'b1;
                end
            end
        end
    end

   
    localparam F_IDLE = 2'd0, F_REQ = 2'd1, F_WAIT = 2'd2;
    reg [1:0] f_state;
    reg [2:0] word_count;
    
    localparam D_IDLE = 2'd0, D_ISSUE_RD = 2'd1, D_ISSUE_WR = 2'd2;
    reg [1:0] d_state;

    wire grant_u    = (u_state == U_REQ);
    wire grant_f    = (f_state == F_REQ) && !grant_u;
    wire grant_d_rd = (d_state == D_ISSUE_RD) && !grant_u && !grant_f;
    wire grant_d_wr = (d_state == D_ISSUE_WR) && !grant_u && !grant_f;

    wire rx_is_fetch = (read_done_id[Q_DEPTH_BITS] == 1'b1);

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            f_state <= F_IDLE;
            alloc_ptr <= 2'd0;
            word_count <= 3'd0;
            valid_slots <= 4'd0;
            fetch_desc_update <= 1'b0;
            fetch_desc_next_ptr <= 32'd0;
            end_of_chain_fetched <= 1'b0;
        end else begin
            fetch_desc_update <= 1'b0;
            
            if (reg_ctrl[0]) end_of_chain_fetched <= 1'b0;

            case (f_state)
                F_IDLE: begin
                     if ((reg_ctrl[0] || running) && !end_of_chain_fetched && !queue_full && !global_error) begin
                          f_state <= F_REQ;
                     end
                end
                F_REQ: begin
                    if (grant_f && read_cmd_ready) begin
                        f_state <= F_WAIT;
                        word_count <= 3'd0;
                    end
                end
                F_WAIT: begin
                    if (rx_valid && rx_ready && rx_is_fetch) begin
                        desc_queue[alloc_ptr][word_count] <= rx_data;
                        word_count <= word_count + 1'b1;
                        if (word_count == 3'd7) begin 
                            valid_slots[alloc_ptr] <= 1'b1;
                            fetch_desc_update <= 1'b1;
                            fetch_desc_next_ptr <= desc_queue[alloc_ptr][0];
                            
                            if (desc_queue[alloc_ptr][0] == 32'd0)
                                end_of_chain_fetched <= 1'b1;
                                
                            alloc_ptr <= alloc_ptr + 1'b1;
                            f_state <= F_IDLE;
                        end
                    end
                end
                default: f_state <= F_IDLE;
            endcase
            
            if (status_retire) begin
                 valid_slots[commit_ptr] <= 1'b0;
            end
        end
    end

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            d_state <= D_IDLE;
            disp_ptr <= 2'd0;
            read_issued <= 4'd0;
        end else begin
            case (d_state)
                D_IDLE: begin
                    if (valid_slots[disp_ptr] && !read_issued[disp_ptr]) begin
                        d_state <= D_ISSUE_RD;
                    end
                end
                D_ISSUE_RD: begin
                    if (grant_d_rd && read_cmd_ready) begin
                        read_issued[disp_ptr] <= 1'b1;
                        d_state <= D_ISSUE_WR;
                    end
                end
                D_ISSUE_WR: begin
                    if (grant_d_wr && write_cmd_ready) begin
                        disp_ptr <= disp_ptr + 1'b1;
                        d_state <= D_IDLE;
                    end
                end
                default: d_state <= D_IDLE;
            endcase

            if (status_retire) begin
                read_issued[commit_ptr] <= 1'b0;
            end
        end
    end

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            u_state <= U_IDLE;
            commit_ptr <= 2'd0;
            read_completed <= 4'd0;
            write_completed <= 4'd0;
            desc_count <= 3'd0;
        end else begin
            if (read_cmd_done && read_done_id[Q_DEPTH_BITS] == 1'b0)  
                read_completed[read_done_id[Q_DEPTH_BITS-1:0]] <= 1'b1;
                
            if (write_cmd_done && write_done_id[Q_DEPTH_BITS] == 1'b0) 
                write_completed[write_done_id[Q_DEPTH_BITS-1:0]] <= 1'b1;

            case (u_state)
                U_IDLE: begin
                    if (valid_slots[commit_ptr] && read_completed[commit_ptr] && write_completed[commit_ptr]) begin
                        u_state <= U_REQ;
                    end
                end
                U_REQ: begin 
                    if (grant_u && write_cmd_ready) begin
                        u_state <= U_WAIT;
                    end
                end
                U_WAIT: begin
                    if (status_retire) begin
                        commit_ptr <= commit_ptr + 1'b1;
                        read_completed[commit_ptr]  <= 1'b0;
                        write_completed[commit_ptr] <= 1'b0;
                        
                        if (is_batch_end) begin
                            desc_count <= 3'd0; 
                        end else begin
                            desc_count <= desc_count + 1'b1;
                        end
                        
                        u_state <= U_IDLE;
                    end
                end
                default: u_state <= U_IDLE;
            endcase
        end
    end

   always @(*) begin
        cmd_valid = 1'b0;
        cmd_rnw   = 1'b0;
        cmd_addr  = 32'd0;
        cmd_len   = 16'd0;
        cmd_size  = 3'b010; 
        cmd_id    = {(Q_DEPTH_BITS+1){1'b0}};

        if (u_state == U_REQ) begin
            cmd_valid = 1'b1;
            cmd_rnw   = 1'b1;
            cmd_addr  = desc_queue[commit_ptr][6];
            cmd_len   = 16'd1;
            cmd_size  = 3'b010; 
            cmd_id    = {1'b1, commit_ptr}; 
        end else if (f_state == F_REQ) begin
            cmd_valid = 1'b1;
            cmd_rnw   = 1'b0;
            cmd_addr  = reg_curr_desc_ptr;
            cmd_len   = 16'd8;
            cmd_size  = 3'b010; 
            cmd_id    = {1'b1, alloc_ptr};  
        end else if (d_state == D_ISSUE_RD) begin
            cmd_valid = 1'b1;
            cmd_rnw   = 1'b0;
            cmd_addr  = desc_queue[disp_ptr][2]; 
            cmd_len   = desc_queue[disp_ptr][4][15:0];
            cmd_size  = desc_queue[disp_ptr][4][18:16]; 
            cmd_id    = {1'b0, disp_ptr};   
        end else if (d_state == D_ISSUE_WR) begin
            cmd_valid = 1'b1;
            cmd_rnw   = 1'b1;
            cmd_addr  = desc_queue[disp_ptr][3]; 
            cmd_len   = desc_queue[disp_ptr][4][15:0];
            cmd_size  = desc_queue[disp_ptr][4][18:16];
            cmd_id    = {1'b0, disp_ptr};   
        end
    end

    reg [16:0] tx_cmd_q [0:3]; 
    reg [1:0]  tx_q_head, tx_q_tail;
    reg [2:0]  tx_q_count;
    reg [15:0] tx_beat_cnt;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            tx_q_head <= 2'd0;
            tx_q_tail <= 2'd0;
            tx_q_count <= 3'd0;
            tx_beat_cnt <= 16'd0;
        end else begin
            if (cmd_valid && cmd_rnw && write_cmd_ready) begin
                tx_cmd_q[tx_q_tail] <= {(u_state == U_REQ), cmd_len};
                tx_q_tail <= tx_q_tail + 1'b1;
            end

            if (tx_valid && tx_ready) begin
                if (tx_beat_cnt == tx_cmd_q[tx_q_head][15:0] - 1'b1) begin
                    tx_beat_cnt <= 16'd0;
                    tx_q_head <= tx_q_head + 1'b1;
                end else begin
                    tx_beat_cnt <= tx_beat_cnt + 1'b1;
                end
            end

            if ((cmd_valid && cmd_rnw && write_cmd_ready) && !(tx_valid && tx_ready && (tx_beat_cnt == tx_cmd_q[tx_q_head][15:0] - 1'b1)))
                tx_q_count <= tx_q_count + 1'b1;
            else if (!(cmd_valid && cmd_rnw && write_cmd_ready) && (tx_valid && tx_ready && (tx_beat_cnt == tx_cmd_q[tx_q_head][15:0] - 1'b1)))
                tx_q_count <= tx_q_count - 1'b1;
        end
    end

    wire tx_active    = (tx_q_count > 0);
    wire tx_is_status = tx_cmd_q[tx_q_head][16];

   
    always @(*) begin
        rx_ready   = (rx_is_fetch) ? (f_state == F_WAIT) : !fifo_full;
        fifo_wr_en = (rx_valid && !rx_is_fetch && !fifo_full);
        fifo_wdata = rx_data;
        
        if (tx_active && tx_is_status) begin
            tx_data    = 32'h0000_0001; 
            tx_valid   = 1'b1;          
            fifo_rd_en = 1'b0;          
        end else if (tx_active && !tx_is_status) begin
            tx_data    = fifo_rdata;
            tx_valid   = !fifo_empty;
            fifo_rd_en = (tx_valid && tx_ready);
        end else begin
            tx_data    = 32'd0;
            tx_valid   = 1'b0;
            fifo_rd_en = 1'b0;
        end
    end

endmodule
