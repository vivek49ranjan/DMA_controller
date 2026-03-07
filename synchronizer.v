module synchronizer #(parameter A_size=5) (
    input clk, reset,
    input [A_size:0] d_in,
    output reg [A_size:0] d_out
);
    reg [A_size:0] q1;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            q1 <= 0;
            d_out <= 0;
        end else begin
            q1 <= d_in;
            d_out <= q1;
        end
    end
endmodule