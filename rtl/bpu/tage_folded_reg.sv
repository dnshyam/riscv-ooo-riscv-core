`timescale 1ns/1ps

module tage_folded_reg #(
    parameter int HIST_LEN = 32,
    parameter int OUT_BITS = 10
)(
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 ghr_bit_in,
    input  logic                 ghr_shift_en,
    output logic [OUT_BITS-1:0]  folded_hist
);

    logic [OUT_BITS-1:0] folded_reg;
    assign folded_hist = folded_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            folded_reg <= '0;
        end else if (ghr_shift_en) begin
            // Perform compressed XOR circular shift update matrix
            folded_reg <= {folded_reg[OUT_BITS-2:0], folded_reg[OUT_BITS-1]} ^ 
                          OUT_BITS'(ghr_bit_in) ^ 
                          (OUT_BITS'(ghr_bit_in) << (HIST_LEN % OUT_BITS));
        end
    end

endmodule
