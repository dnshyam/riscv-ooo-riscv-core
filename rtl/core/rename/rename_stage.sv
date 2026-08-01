`timescale 1ns/1ps

module rename_stage
import riscv_pkg::*;
(
    input  logic                   clk,
    input  logic                   rst_n,
    
    // Global Pipeline Controls
    input  logic                   stall,
    input  logic                   flush,
    
    // Decode Interface Inputs
    input  decode_pkt_t            rename_in,
    input  logic                   rename_in_valid,
    
    // Commit/Retire System Updates (For freeing committed registers)
    input  logic                   commit_valid,
    input  logic [PHYS_REG_BITS-1:0] commit_pprev_rd,
    input  logic                   commit_use_rd,
    
    // Outputs to Dispatch Stage
    output rename_pkt_t            rename_out,
    output logic                   free_reg_alloc_fail // Structural stall warning
);

    // Rename Map Table Array
    logic [PHYS_REG_BITS-1:0] map_table [0:ARCH_REGS-1];
    
    // Free List Tracking Array (Bitmask pattern for simplicity)
    logic [PHYS_REGS-1:0]     free_list;
    logic [PHYS_REG_BITS-1:0] allocated_preg;
    logic                     free_found;

    // Combinational Free Finder Logic
    always_comb begin
        allocated_preg = '0;
        free_found     = 1'b0;
        // Search free list from physical register 1 upwards (PR0 stays hardwired to zero)
        for (int i = 1; i < PHYS_REGS; i++) begin
            if (free_list[i] && !free_found) begin
                allocated_preg = PHYS_REG_BITS'(i);
                free_found     = 1'b1;
            end
        end
    end

    // Signal dynamic allocation failure if structural resources clear out
    assign free_reg_alloc_fail = rename_in_valid && rename_in.use_rd && !free_found;

    // Output Mapping Combinations
    rename_pkt_t renamed_comb;

    always_comb begin
        renamed_comb.pc       = rename_in.pc;
        renamed_comb.op_type  = rename_in.op_type;
        renamed_comb.alu_op   = rename_in.alu_op;
        renamed_comb.use_rs1  = rename_in.use_rs1;
        renamed_comb.use_rs2  = rename_in.use_rs2;
        renamed_comb.use_rd   = rename_in.use_rd;
        renamed_comb.imm      = rename_in.imm;
        renamed_comb.pred_taken = rename_in.pred_taken;
        renamed_comb.valid    = rename_in_valid && !free_reg_alloc_fail;

        // Source register translations (Read map table)
        renamed_comb.prs1 = (rename_in.rs1 == 5'd0) ? '0 : map_table[rename_in.rs1];
        renamed_comb.prs2 = (rename_in.rs2 == 5'd0) ? '0 : map_table[rename_in.rs2];

        // Destination tracking mapping
        if (rename_in.use_rd && (rename_in.rd != 5'd0)) begin
            renamed_comb.prd      = allocated_preg;
            renamed_comb.pprev_rd = map_table[rename_in.rd];
        end else begin
            renamed_comb.prd      = '0;
            renamed_comb.pprev_rd = '0;
        end
    end

    // Map Table and Free List Sequential Registries
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Architectural mappings mirror initialization bounds
            for (int i = 0; i < ARCH_REGS; i++) begin
                map_table[i] <= PHYS_REG_BITS'(i);
            end
            
            // PR0 is dedicated un-writeable. PR1-PR31 mirror state. PR32-PR63 are cleanly available.
            free_list[0]   <= 1'b0;
            for (int j = 1; j < ARCH_REGS; j++)  free_list[j] <= 1'b0;
            for (int k = ARCH_REGS; k < PHYS_REGS; k++) free_list[k] <= 1'b1;

        end else if (!stall && !flush) begin
            
            // Process Allocations
            if (rename_in_valid && rename_in.use_rd && (rename_in.rd != 5'd0) && !free_reg_alloc_fail) begin
                map_table[rename_in.rd] <= allocated_preg;
                free_list[allocated_preg] <= 1'b0;
            end

            // Process Deallocations from Retiring Elements
            if (commit_valid && commit_use_rd && (commit_pprev_rd != '0)) begin
                free_list[commit_pprev_rd] <= 1'b1;
            end
        end
    end

    // Sequential Output Registry Boundary Stage
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rename_out <= '0;
        end else if (flush) begin
            rename_out.valid <= 1'b0;
        end else if (!stall) begin
            rename_out <= renamed_comb;
        end
    end

endmodule
