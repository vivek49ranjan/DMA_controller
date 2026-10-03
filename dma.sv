import dmac_pkg::*;

module dmac_controller #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter Q_DEPTH_BITS = 2 
)(
    input  logic                  clk,
    input  logic                  resetn,

    output dma_cmd_t              cmd_out,
    output logic                  cmd_valid,
    input  logic                  read_cmd_ready,
    input  logic                  write_cmd_ready,
    
    input  logic                  read_cmd_done,
    input  logic [Q_DEPTH_BITS:0] read_done_id,  
    input  logic                  write_cmd_done,
    input  logic [Q_DEPTH_BITS:0] write_done_id,
    input  logic                  cmd_error,
    input  logic [1:0]            cmd_error_type,

    output logic [DATA_WIDTH-1:0] tx_data,
    output logic                  tx_valid,
    input  logic                  tx_ready,
    
    input  logic [DATA_WIDTH-1:0] rx_data,
    input  logic                  rx_valid,
    output logic                  rx_ready,

    output logic                  cpu_intr,

    input  logic                  reg_wr_valid,
    output logic                  reg_wr_ready,
    input  logic [ADDR_WIDTH-1:0] reg_wr_addr,
    input  logic [DATA_WIDTH-1:0] reg_wdata,
    
    output logic                  fifo_wr_en,
    output logic [DATA_WIDTH-1:0] fifo_wdata,
    input  logic                  fifo_full,
    
    output logic                  fifo_rd_en,
    input  logic [DATA_WIDTH-1:0] fifo_rdata,
    input  logic                  fifo_empty
);

    dma_desc_t desc_queue [0:3];
    logic [31:0] desc_addr_q [0:3]; 
    logic [1:0]  alloc_ptr, disp_ptr, commit_ptr;   

    logic [3:0]  valid_slots; 
    logic [3:0]  read_issued, read_completed, write_completed;
    logic        queue_full;
    assign queue_full = valid_slots[alloc_ptr];
    
    logic        fetch_desc_update;
    logic [31:0] fetch_desc_next_ptr;
    logic [31:0] reg_ctrl, reg_curr_desc_ptr, reg_irq_clear;        
    
    logic        halt_pipeline;
    logic        desc_err_pulse;
    logic [1:0]  err_alloc_ptr;
    logic        axi_fetch_err_pulse;
    logic [1:0]  axi_fetch_err_ptr;

    logic        running, end_of_chain_fetched; 

    logic [2:0]  slot_err [0:3]; 
    logic [3:0]  slot_has_err;

    u_state_e u_state;
    logic [2:0]  desc_count; 

    logic        is_batch_end;
    logic        status_retire;
    assign is_batch_end  = (desc_count == 3'd7) || (desc_queue[commit_ptr].next_desc_ptr == 32'd0);
    assign status_retire = (u_state == U_WAIT) && write_cmd_done && (write_done_id == {1'b1, commit_ptr});
    
    assign reg_wr_ready = 1'b1;

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            reg_ctrl            <= 32'd0;
            reg_curr_desc_ptr   <= 32'd0;
            reg_irq_clear       <= 32'd0;
            halt_pipeline       <= 1'b0;
            cpu_intr            <= 1'b0;
            running             <= 1'b0; 
            slot_has_err        <= 4'd0;
            axi_fetch_err_pulse <= 1'b0;
            axi_fetch_err_ptr   <= 2'd0;
            slot_err[0] <= 3'd0; slot_err[1] <= 3'd0;
            slot_err[2] <= 3'd0; slot_err[3] <= 3'd0;
        end else begin
            axi_fetch_err_pulse <= 1'b0; 

            if (reg_wr_valid) begin
                case (reg_wr_addr[7:0])
                    8'h00: reg_ctrl          <= reg_wdata;
                    8'h14: reg_curr_desc_ptr <= reg_wdata;
                    8'h18: reg_irq_clear     <= reg_wdata;
                    default: ; 
                endcase
            end else if (fetch_desc_update) begin
                reg_curr_desc_ptr <= fetch_desc_next_ptr;
            end
                
            if (reg_ctrl[0]) begin
                reg_ctrl[0] <= 1'b0; 
                running     <= 1'b1; 
            end else if (end_of_chain_fetched && valid_slots == 4'd0 && u_state == U_IDLE) begin
                running <= 1'b0;
            end

            if (cmd_error || desc_err_pulse || axi_fetch_err_pulse) begin
                halt_pipeline <= 1'b1;
            end else if (reg_irq_clear[0]) begin
                halt_pipeline <= 1'b0;
            end

            if (status_retire && (is_batch_end || slot_has_err[commit_ptr])) begin
                cpu_intr <= 1'b1;
            end else if (reg_irq_clear[0]) begin
                cpu_intr <= 1'b0;
            end

            if (reg_irq_clear[0]) begin
                reg_irq_clear[0] <= 1'b0;
                slot_has_err     <= 4'd0;
            end

            if (cmd_error) begin
                if (write_cmd_done) begin
                    slot_has_err[write_done_id[1:0]] <= 1'b1;
                    slot_err[write_done_id[1:0]]     <= {1'b0, cmd_error_type};
                end
                if (read_cmd_done) begin
                    if (read_done_id[Q_DEPTH_BITS] == 1'b0) begin
                        slot_has_err[read_done_id[1:0]] <= 1'b1;
                        slot_err[read_done_id[1:0]]     <= {1'b0, cmd_error_type};
                    end else begin
                        axi_fetch_err_pulse <= 1'b1;
                        axi_fetch_err_ptr   <= read_done_id[1:0];
                        slot_has_err[read_done_id[1:0]] <= 1'b1;
                        slot_err[read_done_id[1:0]]     <= {1'b1, cmd_error_type};
                    end
                end
            end
            
            if (desc_err_pulse) begin
                slot_has_err[err_alloc_ptr] <= 1'b1;
                slot_err[err_alloc_ptr]     <= {1'b1, 2'b00}; 
            end

            if (status_retire) slot_has_err[commit_ptr] <= 1'b0;
        end
    end

    f_state_e f_state;
    logic [2:0] word_count;
    
    d_state_e d_state;

    logic grant_u;
    logic grant_f;
    logic grant_d_rd;
    logic grant_d_wr;
    
    assign grant_u    = (u_state == U_REQ);
    assign grant_f    = (f_state == F_REQ) && !grant_u && !halt_pipeline;
    assign grant_d_rd = (d_state == D_ISSUE_RD) && !grant_u && !grant_f && !halt_pipeline;
    assign grant_d_wr = (d_state == D_ISSUE_WR) && !grant_u && !grant_f && !halt_pipeline;

    rx_cmd_info_t rx_cmd_q [0:3]; 
    logic [1:0] rx_q_head, rx_q_tail;
    logic [2:0] rx_q_count;

    logic rx_active;
    logic rx_is_fetch;
    logic read_issued_now;
    
    assign rx_active       = (rx_q_count > 0);
    assign rx_is_fetch     = rx_active && rx_cmd_q[rx_q_head].is_fetch;
    assign read_issued_now = cmd_valid && !cmd_out.rnw && read_cmd_ready;

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            rx_q_head  <= 2'd0;
            rx_q_tail  <= 2'd0;
            rx_q_count <= 3'd0;
        end else begin
            if (read_issued_now) begin
                rx_cmd_q[rx_q_tail].is_fetch <= (f_state == F_REQ);
                rx_cmd_q[rx_q_tail].len      <= cmd_out.len;
                rx_q_tail           <= rx_q_tail + 1'b1;
            end
            if (read_cmd_done) rx_q_head <= rx_q_head + 1'b1;
            rx_q_count <= rx_q_count + read_issued_now - read_cmd_done;
        end
    end

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            f_state              <= F_IDLE;
            alloc_ptr            <= 2'd0;
            word_count           <= 3'd0;
            valid_slots          <= 4'd0;
            end_of_chain_fetched <= 1'b0;
            desc_err_pulse       <= 1'b0;
            err_alloc_ptr        <= 2'd0;
            fetch_desc_update    <= 1'b0;
            for (int i=0; i<4; i++) desc_addr_q[i] <= 32'd0;
        end else begin
            fetch_desc_update <= 1'b0;
            desc_err_pulse    <= 1'b0; 
            if (reg_ctrl[0]) end_of_chain_fetched <= 1'b0;

            case (f_state)
                F_IDLE: begin
                    if ((reg_ctrl[0] || running) && !end_of_chain_fetched && !queue_full) begin
                        f_state <= F_REQ;
                    end
                end
                F_REQ: begin
                    if (grant_f && read_cmd_ready) begin
                        f_state                <= F_WAIT;
                        word_count             <= 3'd0;
                        desc_addr_q[alloc_ptr] <= reg_curr_desc_ptr;
                    end
                end
                F_WAIT: begin
                    if (rx_valid && rx_ready && rx_is_fetch) begin
                        case(word_count)
                            3'd0: desc_queue[alloc_ptr].next_desc_ptr <= rx_data;
                            3'd1: desc_queue[alloc_ptr].src_addr      <= rx_data;
                            3'd2: desc_queue[alloc_ptr].dst_addr      <= rx_data;
                            3'd3: desc_queue[alloc_ptr].ctrl_len      <= rx_data;
                            3'd4: desc_queue[alloc_ptr].status        <= rx_data;
                        endcase
                        word_count <= word_count + 1'b1;
                        
                        if (word_count == 3'd4) begin 
                            fetch_desc_update   <= 1'b1;
                            fetch_desc_next_ptr <= desc_queue[alloc_ptr].next_desc_ptr;
                            
                            if (desc_queue[alloc_ptr].next_desc_ptr == 32'd0) end_of_chain_fetched <= 1'b1;

                            if (rx_data[0] == 1'b1) begin
                                desc_err_pulse <= 1'b1; 
                                err_alloc_ptr  <= alloc_ptr;
                            end
                            
                            valid_slots[alloc_ptr] <= 1'b1; 
                            alloc_ptr              <= alloc_ptr + 1'b1;
                            f_state <= F_IDLE;
                        end
                    end
                end
                default: f_state <= F_IDLE;
            endcase
            
            if (status_retire) valid_slots[commit_ptr] <= 1'b0;
        end
    end

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            d_state     <= D_IDLE;
            disp_ptr    <= 2'd0;
            read_issued <= 4'd0;
        end else begin
            case (d_state)
                D_IDLE: begin
                    if (valid_slots[disp_ptr]) begin
                        if (read_issued[disp_ptr]) begin
                            disp_ptr <= disp_ptr + 1'b1;
                        end else begin
                            d_state <= D_ISSUE_RD;
                        end
                    end
                end
                D_ISSUE_RD: begin
                    if (grant_d_rd && read_cmd_ready) begin
                        read_issued[disp_ptr] <= 1'b1;
                        d_state               <= D_ISSUE_WR;
                    end
                end
                D_ISSUE_WR: begin
                    if (grant_d_wr && write_cmd_ready) begin
                        disp_ptr <= disp_ptr + 1'b1;
                        d_state  <= D_IDLE;
                    end
                end
                default: d_state <= D_IDLE;
            endcase

            if (desc_err_pulse)      read_issued[err_alloc_ptr]     <= 1'b1; 
            if (axi_fetch_err_pulse) read_issued[axi_fetch_err_ptr] <= 1'b1;

            if (status_retire) read_issued[commit_ptr] <= 1'b0;
        end
    end

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            u_state         <= U_IDLE;
            commit_ptr      <= 2'd0;
            read_completed  <= 4'd0;
            write_completed <= 4'd0;
            desc_count      <= 3'd0;
        end else begin
            if (read_cmd_done && read_done_id[Q_DEPTH_BITS] == 1'b0)  
                read_completed[read_done_id[Q_DEPTH_BITS-1:0]] <= 1'b1;
                
            if (write_cmd_done && write_done_id[Q_DEPTH_BITS] == 1'b0) 
                write_completed[write_done_id[Q_DEPTH_BITS-1:0]] <= 1'b1;
            
            if (desc_err_pulse) begin
                read_completed[err_alloc_ptr]  <= 1'b1;
                write_completed[err_alloc_ptr] <= 1'b1;
            end
            if (axi_fetch_err_pulse) begin
                read_completed[axi_fetch_err_ptr]  <= 1'b1;
                write_completed[axi_fetch_err_ptr] <= 1'b1;
            end

            case (u_state)
                U_IDLE: begin
                    if (valid_slots[commit_ptr] && read_completed[commit_ptr] && write_completed[commit_ptr]) begin
                        u_state <= U_REQ;
                    end
                end
                U_REQ: begin 
                    if (grant_u && write_cmd_ready) u_state <= U_WAIT;
                end
                U_WAIT: begin
                    if (status_retire) begin
                        commit_ptr                  <= commit_ptr + 1'b1;
                        read_completed[commit_ptr]  <= 1'b0;
                        write_completed[commit_ptr] <= 1'b0;
                        desc_count                  <= is_batch_end ? 3'd0 : desc_count + 1'b1;
                        u_state                     <= U_IDLE;
                    end
                end
                default: u_state <= U_IDLE;
            endcase
        end
    end

    always_comb begin
        cmd_valid    = 1'b0;
        cmd_out      = '0;

        if (grant_u) begin 
            cmd_valid    = 1'b1;
            cmd_out.rnw  = 1'b1;
            cmd_out.addr = desc_addr_q[commit_ptr] + 8'd16; 
            cmd_out.len  = 8'd1;
            cmd_out.size = 3'b010; 
            cmd_out.id   = {1'b1, commit_ptr}; 
        end else if (f_state == F_REQ) begin
            cmd_valid    = 1'b1;
            cmd_out.rnw  = 1'b0;
            cmd_out.addr = reg_curr_desc_ptr;
            cmd_out.len  = 8'd5; 
            cmd_out.size = 3'b010; 
            cmd_out.id   = {1'b1, alloc_ptr};  
        end else if (d_state == D_ISSUE_RD) begin
            cmd_valid    = 1'b1;
            cmd_out.rnw  = 1'b0;
            cmd_out.addr = desc_queue[disp_ptr].src_addr;
            cmd_out.len  = desc_queue[disp_ptr].ctrl_len[7:0]; 
            cmd_out.size = desc_queue[disp_ptr].ctrl_len[18:16]; 
            cmd_out.id   = {1'b0, disp_ptr};   
        end else if (d_state == D_ISSUE_WR) begin
            cmd_valid    = 1'b1;
            cmd_out.rnw  = 1'b1;
            cmd_out.addr = desc_queue[disp_ptr].dst_addr;
            cmd_out.len  = desc_queue[disp_ptr].ctrl_len[7:0]; 
            cmd_out.size = desc_queue[disp_ptr].ctrl_len[18:16];
            cmd_out.id   = {1'b0, disp_ptr};   
        end
    end

    tx_cmd_info_t tx_cmd_q [0:3]; 
    logic [1:0]  tx_q_head, tx_q_tail;
    logic [2:0]  tx_q_count;
    logic [7:0]  tx_beat_cnt;   

    logic tx_push;
    logic tx_pop;
    
    assign tx_push = cmd_valid && cmd_out.rnw && write_cmd_ready;
    assign tx_pop  = tx_valid && tx_ready && (tx_beat_cnt == tx_cmd_q[tx_q_head].len - 1'b1);

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            tx_q_head   <= 2'd0;
            tx_q_tail   <= 2'd0;
            tx_q_count  <= 3'd0;
            tx_beat_cnt <= 8'd0;
        end else begin
            if (tx_push) begin
                tx_cmd_q[tx_q_tail].is_status <= (u_state == U_REQ);
                tx_cmd_q[tx_q_tail].stat_id   <= cmd_out.id[1:0];
                tx_cmd_q[tx_q_tail].len       <= cmd_out.len;
                tx_q_tail           <= tx_q_tail + 1'b1;
            end

            if (tx_valid && tx_ready) begin
                if (tx_beat_cnt == tx_cmd_q[tx_q_head].len - 1'b1) begin
                    tx_beat_cnt <= 8'd0;
                    tx_q_head   <= tx_q_head + 1'b1;
                end else begin
                    tx_beat_cnt <= tx_beat_cnt + 1'b1;
                end
            end

            tx_q_count <= tx_q_count + tx_push - tx_pop;
        end
    end

    logic tx_active;
    logic tx_is_status;
    logic [1:0] tx_stat_id;
    
    assign tx_active    = (tx_q_count > 0);
    assign tx_is_status = tx_cmd_q[tx_q_head].is_status;
    assign tx_stat_id   = tx_cmd_q[tx_q_head].stat_id;

    always_comb begin
        rx_ready   = (rx_is_fetch) ? (f_state == F_WAIT) : !fifo_full;
        fifo_wr_en = (rx_valid && rx_ready && !rx_is_fetch);
        fifo_wdata = rx_data;
        
        if (tx_active && tx_is_status) begin
            if (slot_has_err[tx_stat_id]) begin
                tx_data = {27'd0, slot_err[tx_stat_id], 2'b11};
            end else begin
                tx_data = 32'h0000_0001; 
            end
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
