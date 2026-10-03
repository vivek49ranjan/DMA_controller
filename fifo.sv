import dmac_pkg::*;

module sync_fifo #(
    parameter A_WIDTH = 4
)(
    input  logic                  clk,
    input  logic                  resetn,
    
    input  logic                  wr_en,
    input  logic [DATA_WIDTH-1:0] wdata,
    output logic                  full,
    
    input  logic                  rd_en,
    output logic [DATA_WIDTH-1:0] rdata,
    output logic                  empty
);
    localparam DEPTH = 1 << A_WIDTH;
    
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    logic [A_WIDTH:0]      count;
    logic [A_WIDTH-1:0]    wr_ptr;
    logic [A_WIDTH-1:0]    rd_ptr;

    logic do_write;
    logic do_read;

    assign do_write = wr_en && !full;
    assign do_read  = rd_en && !empty;
    assign full     = (count == DEPTH);
    assign empty    = (count == 0);
    assign rdata    = mem[rd_ptr];

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            count  <= '0;
            wr_ptr <= '0;
            rd_ptr <= '0;
        end else begin
            if (do_write) begin
                mem[wr_ptr] <= wdata;
                wr_ptr      <= wr_ptr + 1'b1;
            end
            if (do_read) begin
                rd_ptr <= rd_ptr + 1'b1;
            end
            case ({do_write, do_read})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end
endmodule
