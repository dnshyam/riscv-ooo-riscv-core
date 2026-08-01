`timescale 1ns/1ps

module tage_tagged_table #(
    parameter int ENTRY_COUNT = 512,
    parameter int INDEX_BITS  = $clog2(ENTRY_COUNT),
    parameter int TAG_BITS    = 8
)(
    input  logic                   clk,
    input  logic                   rst_n,
    
    // Lookup Interfaces
    input  logic [INDEX_BITS-1:0]  look_up_idx,
    input  logic [TAG_BITS-1:0]    look_up_tag,
    output logic                   hit,
    output logic                   pred_taken,
    output logic [1:0]             u_bits,
    
    // Dynamic Training Allocation Updates
    input  logic                   update_en,
    input  logic [INDEX_BITS-1:0]  update_idx,
    input  logic [TAG_BITS-1:0]    update_tag,
    input  logic                   actual_taken,
    input  logic [1:0]             mod_u_cmd // 01: inc U, 10: dec U, 11: allocate
);

    // Structural Configuration Allocations
    logic [2:0]          ctr_table  [0:ENTRY_COUNT-1];
    logic [TAG_BITS-1:0] tag_table  [0:ENTRY_COUNT-1];
    logic [1:0]          u_table    [0:ENTRY_COUNT-1];
    logic                valid_bits [0:ENTRY_COUNT-1];

    // Combinational Verification Matches
    assign hit        = valid_bits[look_up_idx] && (tag_table[look_up_idx] == look_up_tag);
    assign pred_taken = ctr_table[look_up_idx][2]; // Return sign bit vector state
    assign u_bits     = u_table[look_up_idx];

    // Synchronous Update Controls
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < ENTRY_COUNT; i++) begin
                ctr_table[i]  <= 3'b011; // Weakly non-taken baseline
                tag_table[i]  <= '0;
                u_table[i]    <= 2'b00;
                valid_bits[i] <= 1'b0;
            end
        end else if (update_en) begin
            if (mod_u_cmd == 2'b11) begin
                // Force Entry Allocation Setup
                ctr_table[update_idx]  <= actual_taken ? 3'b100 : 3'b011;
                tag_table[update_idx]  <= update_tag;
                u_table[update_idx]    <= 2'b00;
                valid_bits[update_idx] <= 1'b1;
            end else begin
                // Update Prediction Counter State
                if (hit) begin
                    if (actual_taken && (ctr_table[update_idx] != 3'b111)) 
                        ctr_table[update_idx] <= ctr_table[update_idx] + 1'b1;
                    else if (!actual_taken && (ctr_table[update_idx] != 3'b000))
                        ctr_table[update_idx] <= ctr_table[update_idx] - 1'b1;
                end
                
                // Adjust Usefulness Bits State Matrices
                if (mod_u_cmd == 2'b01 && (u_table[update_idx] != 2'b11))
                    u_table[update_idx] <= u_table[update_idx] + 1'b1;
                else if (mod_u_cmd == 2'b10 && (u_table[update_idx] != 2'b00))
                    u_table[update_idx] <= u_table[update_idx] - 1'b1;
            end
        end
    end

endmodule
