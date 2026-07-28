module sync_fifo #(
    parameter D_WIDTH = 32,
    parameter A_WIDTH = 4
)(
    input  wire               clk,
    input  wire               resetn,
    
    input  wire               wr_en,
    input  wire [D_WIDTH-1:0] wdata,
    output wire               full,
    
    input  wire               rd_en,
    output wire [D_WIDTH-1:0] rdata,
    output wire               empty
);
    localparam DEPTH = 1 << A_WIDTH;
    
    reg [D_WIDTH-1:0] mem [0:DEPTH-1];
    reg [A_WIDTH:0]   count;
    reg [A_WIDTH-1:0] wr_ptr;
    reg [A_WIDTH-1:0] rd_ptr;

    wire do_write = wr_en && !full;
    wire do_read  = rd_en && !empty;

    assign full  = (count == DEPTH);
    assign empty = (count == 0);

    assign rdata = mem[rd_ptr];

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            count  <= 0;
            wr_ptr <= 0;
            rd_ptr <= 0;
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
