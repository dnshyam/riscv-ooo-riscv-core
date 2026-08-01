`timescale 1ns/1ps

module rob
import riscv_pkg::*;
(
    input  logic                      clk,
    input  logic                      rst_n,
    
    // Dispatch/Allocation Interface
    input  logic                      alloc_en,
    input  rename_pkt_t               alloc_pkt,
    output logic [ROB_INDEX_BITS-1:0] alloc_rob_id,
    output logic                      rob_full,
    
    // Writeback Interface (From Execution Units)
    input  logic                      wb_valid,
    input  logic [ROB_INDEX_BITS-1:0] wb_rob_id,
    input  logic                      wb_exception,
    input  logic                      wb_mispredicted,
    
    // Commit/Retire Interface (To Rename Stage & Architecture Reg File)
    output logic                      commit_valid,
    output logic [PHYS_REG_BITS-1:0]  commit_prd,
    output logic [PHYS_REG_BITS-1:0]  commit_pprev_rd,
    output logic                      commit_use_rd,
    output logic [XLEN-1:0]           commit_pc,
    
    // Global Pipeline Recovery Controls
    output logic                      flush_ooo_pipeline
);

    // Circular FIFO Tracking Core Structures
    rob_entry_t rob_ram [0:ROB_DEPTH-1];
    logic [ROB_INDEX_BITS:0] head_ptr; // Extra bit to detect empty/full states
    logic [ROB_INDEX_BITS:0] tail_ptr;

    // Pointer matching indicators
    logic [ROB_INDEX_BITS-1:0] head_idx;
    logic [ROB_INDEX_BITS-1:0] tail_idx;

    assign head_idx = head_ptr[ROB_INDEX_BITS-1:0];
    assign tail_idx = tail_ptr[ROB_INDEX_BITS-1:0];

    // Status logic checking limits
    assign rob_full = (head_idx == tail_idx) && (head_ptr[ROB_INDEX_BITS] != tail_ptr[ROB_INDEX_BITS]);
    logic  rob_empty;
    assign rob_empty = (head_ptr == tail_ptr);

    // Provide the dynamic target tracking reference
    assign alloc_rob_id = tail_idx;

    // Continuous Combinational Commit Evaluation
    rob_entry_t commit_candidate;
    assign commit_candidate = rob_ram[head_idx];

    always_comb begin
        commit_valid    = 1'b0;
        commit_prd      = '0;
        commit_pprev_rd = '0;
        commit_use_rd   = 1'b0;
        commit_pc       = '0;
        flush_ooo_pipeline = 1'b0;

        if (!rob_empty && commit_candidate.completed) begin
            commit_valid    = 1'b1;
            commit_prd      = commit_candidate.prd;
            commit_pprev_rd = commit_candidate.pprev_rd;
            commit_use_rd   = commit_candidate.use_rd;
            commit_pc       = commit_candidate.pc;
            
            // Trigger flush sequence upon misprediction or instruction exception boundaries
            if (commit_candidate.exception || (commit_candidate.is_branch && commit_candidate.mispredicted)) begin
                flush_ooo_pipeline = 1'b1;
            end
        end
    end

    // Sequential Update Loops
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head_ptr <= '0;
            tail_ptr <= '0;
            for (int i = 0; i < ROB_DEPTH; i++) begin
                rob_ram[i] <= '0;
            end
        end else begin
            // Complete standard architecture recovery reset if flushing is mandated down-pipe
            if (flush_ooo_pipeline) begin
                head_ptr <= '0;
                tail_ptr <= '0;
            end else begin
                // Step 1: Handle instruction entry allocation at dispatch
                if (alloc_en && !rob_full) begin
                    rob_ram[tail_idx].pc           <= alloc_pkt.pc;
                    rob_ram[tail_idx].prd          <= alloc_pkt.prd;
                    rob_ram[tail_idx].pprev_rd     <= alloc_pkt.pprev_rd;
                    rob_ram[tail_idx].use_rd       <= alloc_pkt.use_rd;
                    rob_ram[tail_idx].completed    <= 1'b0;
                    rob_ram[tail_idx].exception    <= 1'b0;
                    rob_ram[tail_idx].is_branch    <= (alloc_pkt.op_type == OP_BRANCH);
                    rob_ram[tail_idx].mispredicted <= 1'b0;
                    tail_ptr                       <= tail_ptr + 1'b1;
                end

                // Step 2: Update status on execution completions
                if (wb_valid) begin
                    rob_ram[wb_rob_id].completed    <= 1'b1;
                    rob_ram[wb_rob_id].exception    <= wb_exception;
                    rob_ram[wb_rob_id].mispredicted <= wb_mispredicted;
                end

                // Step 3: Increment read head during standard instruction commit intervals
                if (commit_valid) begin
                    head_ptr <= head_ptr + 1'b1;
                end
            end
        end
    end

endmodule
