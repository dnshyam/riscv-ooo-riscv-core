`timescale 1ns/1ps

module tage_base 
import riscv_pkg::*;
#(
    parameter int ENTRY_COUNT = 1024,
    parameter int INDEX_BITS = $clog2(ENTRY_COUNT)
)(
    input  logic                   clk,
    input  logic                   rst_n,
    
    // Look-up Interface
    input  logic [XLEN-1:0]        look_up_pc,
    output logic                   pred_taken,
    
    // Update Interface
    input  logic                   update_en,
    input  logic [XLEN-1:0]        update_pc,
    input  logic                   actual_taken
);

    logic [1:0] bimodal_table [0:ENTRY_COUNT-1];
    logic [INDEX_BITS-1:0] look_up_idx;
    logic [INDEX_BITS-1:0] update_idx;

    assign look_up_idx = look_up_pc[INDEX_BITS+1:2];
    assign update_idx  = update_pc[INDEX_BITS+1:2];

    // Prediction Lookup
    assign pred_taken = bimodal_table[look_up_idx][1];

    // Synchronous Update Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < ENTRY_COUNT; i++) begin
                bimodal_table[i] = 2'b01; // FIXED: Blocking assignment for loop init
            end
        end else if (update_en) begin
            case (bimodal_table[update_idx])
                2'b00: bimodal_table[update_idx] <= actual_taken ? 2'b01 : 2'b00;
                2'b01: bimodal_table[update_idx] <= actual_taken ? 2'b10 : 2'b00;
                2'b10: bimodal_table[update_idx] <= actual_taken ? 2'b11 : 2'b01;
                2'b11: bimodal_table[update_idx] <= actual_taken ? 2'b11 : 2'b10;
            endcase
        end
    end

endmodule
