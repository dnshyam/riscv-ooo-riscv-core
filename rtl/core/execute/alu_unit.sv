`timescale 1ns/1ps

module alu_unit
import riscv_pkg::*;
(
    // Execution Inputs
    input  iq_entry_t                 alu_in,
    input  logic [XLEN-1:0]           src1_val,
    input  logic [XLEN-1:0]           src2_val,
    
    // Execution Writeback Outputs
    output logic                      wb_valid,
    output logic [ROB_INDEX_BITS-1:0] wb_rob_id,
    output logic [PHYS_REG_BITS-1:0]  wb_prd,
    output logic [XLEN-1:0]           wb_data,
    output logic                      wb_exception,
    output logic                      wb_mispredicted
);

    logic [XLEN-1:0] alu_out;
    logic            branch_taken;

    // Map verification structures
    assign wb_rob_id    = alu_in.rob_id;
    assign wb_prd       = alu_in.prd;
    assign wb_exception = 1'b0; // System level exceptions placeholder

    // Processing Combinational Blocks
    always_comb begin
        alu_out      = '0;
        branch_taken = 1'b0;
        wb_valid     = (alu_in.op_type == OP_ALU || alu_in.op_type == OP_BRANCH);

        case (alu_in.op_type)
            OP_ALU: begin
                case (alu_in.alu_op[2:0])
                    3'b000: alu_out = alu_in.alu_op[3] ? (src1_val - src2_val) : (src1_val + src2_val); // ADD / SUB
                    3'b001: alu_out = src1_val << src2_val[4:0];                                      // SLL
                    3'b010: alu_out = ($signed(src1_val) < $signed(src2_val)) ? 32'b1 : 32'b0;        // SLT
                    3'b011: alu_out = (src1_val < src2_val) ? 32'b1 : 32'b0;                          // SLTU
                    3'b100: alu_out = src1_val ^ src2_val;                                            // XOR
                    3'b101: alu_out = alu_in.alu_op[3] ? ($signed(src1_val) >>> src2_val[4:0]) : (src1_val >> src2_val[4:0]); // SRL / SRA
                    3'b110: alu_out = src1_val | src2_val;                                            // OR
                    3'b111: alu_out = src1_val & src2_val;                                            // AND
                    default: alu_out = '0;
                endcase
            end

            OP_BRANCH: begin
                case (alu_in.alu_op[2:0])
                    3'b000: branch_taken = (src1_val == src2_val);             // BEQ
                    3'b001: branch_taken = (src1_val != src2_val);             // BNE
                    3'b100: branch_taken = ($signed(src1_val) < $signed(src2_val));   // BLT
                    3'b101: branch_taken = ($signed(src1_val) >= $signed(src2_val));  // BGE
                    3'b110: branch_taken = (src1_val < src2_val);              // BLTU
                    3'b111: branch_taken = (src1_val >= src2_val);             // BGEU
                    default: branch_taken = 1'b0;
                endcase
                // Target address is calculated at commit for functional tracking
                alu_out = alu_in.pc + alu_in.imm;
            end

            default: begin
                alu_out = '0;
            end
        endcase
    end

    // Resolution assignment logic comparing execution flags to predictor states
    assign wb_data         = alu_out;
    assign wb_mispredicted = (alu_in.op_type == OP_BRANCH) && (branch_taken != alu_in.pred_taken);

endmodule
