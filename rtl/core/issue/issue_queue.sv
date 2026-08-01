`timescale 1ns/1ps

module issue_queue
import riscv_pkg::*;
(
    input  logic                      clk,
    input  logic                      rst_n,
    
    // Global Pipeline Controls
    input  logic                      flush,
    
    // Dispatch/Allocation Input Boundary
    input  logic                      dispatch_valid,
    input  rename_pkt_t               dispatch_pkt,
    input  logic [ROB_INDEX_BITS-1:0] dispatch_rob_id,
    
    // Wakeup Interface (Tag broadcast from executing units)
    input  logic                      wb_valid_1,
    input  logic [PHYS_REG_BITS-1:0]  wb_prd_1,
    input  logic                      wb_valid_2,
    input  logic [PHYS_REG_BITS-1:0]  wb_prd_2,
    
    // Output Issue Interface to Execution Registers
    output iq_entry_t                 issue_pkt,
    output logic                      issue_valid,
    output logic                      iq_full
);

    // Structural Array for Reservation Stations
    iq_entry_t iq_slots [0:IQ_DEPTH-1];
    logic [IQ_DEPTH-1:0] iq_valid_bits;

    // Compute dynamic capacities
    int unsigned occupied_slots;
    always_comb begin
        occupied_slots = 0;
        for (int i = 0; i < IQ_DEPTH; i++) begin
            if (iq_valid_bits[i]) occupied_slots++;
        end
        iq_full = (occupied_slots >= IQ_DEPTH);
    end

    // Combinational Select Logic (Find first ready instruction entry)
    logic [$clog2(IQ_DEPTH)-1:0] selected_idx;
    logic                        selected_found;

    always_comb begin
        selected_idx   = '0;
        selected_found = 1'b0;
        issue_pkt      = '0;
        issue_valid    = 1'b0;

        for (int i = 0; i < IQ_DEPTH; i++) begin
            if (iq_valid_bits[i] && iq_slots[i].rs1_ready && iq_slots[i].rs2_ready && !selected_found) begin
                selected_idx   = $clog2(IQ_DEPTH)'(i);
                selected_found = 1'b1;
                issue_pkt      = iq_slots[i];
                issue_valid    = 1'b1;
            end
        end
    end

    // Combinational Allocation Index Resolution
    logic [$clog2(IQ_DEPTH)-1:0] alloc_idx;
    logic                        alloc_found;

    always_comb begin
        alloc_idx   = '0;
        alloc_found = 1'b0;
        for (int j = 0; j < IQ_DEPTH; j++) begin
            if (!iq_valid_bits[j] && !alloc_found) begin
                alloc_idx   = $clog2(IQ_DEPTH)'(j);
                alloc_found = 1'b1;
            end
        end
    end

    // Sequential Processing and Dependency Updates
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            iq_valid_bits <= '0;
            for (int i = 0; i < IQ_DEPTH; i++) begin
                iq_slots[i] <= '0;
            end
        end else if (flush) begin
            iq_valid_bits <= '0;
        end else begin
            // Step 1: Continuous Wakeup Tag Verification
            for (int k = 0; k < IQ_DEPTH; k++) begin
                if (iq_valid_bits[k]) begin
                    if (wb_valid_1 && (iq_slots[k].prs1 == wb_prd_1)) iq_slots[k].rs1_ready <= 1'b1;
                    if (wb_valid_2 && (iq_slots[k].prs1 == wb_prd_2)) iq_slots[k].rs1_ready <= 1'b1;
                    if (wb_valid_1 && (iq_slots[k].prs2 == wb_prd_1)) iq_slots[k].rs2_ready <= 1'b1;
                    if (wb_valid_2 && (iq_slots[k].prs2 == wb_prd_2)) iq_slots[k].rs2_ready <= 1'b1;
                end
            end

            // Step 2: Clear Slot on Successful Issue
            if (issue_valid) begin
                iq_valid_bits[selected_idx] <= 1'b0;
            end

            // Step 3: Handle Entry Allocation on Dispatch
            if (dispatch_valid && !iq_full && alloc_found) begin
                // If allocating to the slot being issued this cycle, handle correctly
                if (!(issue_valid && (selected_idx == alloc_idx))) begin
                    iq_valid_bits[alloc_idx]     <= 1'b1;
                    iq_slots[alloc_idx].pc       <= dispatch_pkt.pc;
                    iq_slots[alloc_idx].op_type  <= dispatch_pkt.op_type;
                    iq_slots[alloc_idx].alu_op   <= dispatch_pkt.alu_op;
                    iq_slots[alloc_idx].prs1     <= dispatch_pkt.prs1;
                    iq_slots[alloc_idx].prs2     <= dispatch_pkt.prs2;
                    iq_slots[alloc_idx].prd      <= dispatch_pkt.prd;
                    iq_slots[alloc_idx].imm      <= dispatch_pkt.imm;
                    iq_slots[alloc_idx].rob_id   <= dispatch_rob_id;
                    iq_slots[alloc_idx].pred_taken <= dispatch_pkt.pred_taken;

                    // Source Readiness Checking: Ready if R0 or match to active writeback tags
                    iq_slots[alloc_idx].rs1_ready <= (!dispatch_pkt.use_rs1 || (dispatch_pkt.prs1 == '0) || 
                                                     (wb_valid_1 && (dispatch_pkt.prs1 == wb_prd_1)) || 
                                                     (wb_valid_2 && (dispatch_pkt.prs1 == wb_prd_2)));
                                                     
                    iq_slots[alloc_idx].rs2_ready <= (!dispatch_pkt.use_rs2 || (dispatch_pkt.prs2 == '0) || 
                                                     (wb_valid_1 && (dispatch_pkt.prs2 == wb_prd_1)) || 
                                                     (wb_valid_2 && (dispatch_pkt.prs2 == wb_prd_2)));
                end
            end
        end
    end

endmodule
