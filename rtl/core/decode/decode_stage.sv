`timescale 1ns/1ps

module decode_stage
import riscv_pkg::*;
(
    input  logic         clk,
    input  logic         rst_n,
    
    // Pipeline Control Interconnects
    input  logic         stall,
    input  logic         flush,
    
    // Input Packet from Fetch Stage
    input  fetch_pkt_t   decode_in,
    
    // Output Packet to Rename Stage
    output decode_pkt_t  decode_out
);

    // Internal wires for instruction parsing
    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;
    
    assign opcode = decode_in.inst[6:0];
    assign funct3 = decode_in.inst[14:12];
    assign funct7 = decode_in.inst[31:25];

    // Combinational Decoding Logic
    decode_pkt_t decoded_comb;

    always_comb begin
        // Default structural initializations
        decoded_comb.pc         = decode_in.pc;
        decoded_comb.op_type    = OP_ALU;
        decoded_comb.alu_op     = 5'b00000;
        decoded_comb.rs1        = decode_in.inst[19:15];
        decoded_comb.rs2        = decode_in.inst[24:20];
        decoded_comb.rd         = decode_in.inst[11:7];
        decoded_comb.use_rs1    = 1'b0;
        decoded_comb.use_rs2    = 1'b0;
        decoded_comb.use_rd     = 1'b0;
        decoded_comb.imm        = '0;
        decoded_comb.pred_taken = decode_in.pred_taken;

        if (decode_in.valid) begin
            case (opcode)
                // OP-IMM (addi, slli, slti, etc.)
                7'b0010011: begin
                    decoded_comb.op_type = OP_ALU;
                    decoded_comb.use_rs1 = 1'b1;
                    decoded_comb.use_rd  = 1'b1;
                    decoded_comb.imm     = {{20{decode_in.inst[31]}}, decode_in.inst[31:20]};
                    decoded_comb.alu_op  = {2'b00, funct3}; // Map funct3 straight to ALU control
                end

                // OP (add, sub, sll, xor, etc.)
                7'b0110011: begin
                    decoded_comb.op_type = OP_ALU;
                    decoded_comb.use_rs1 = 1'b1;
                    decoded_comb.use_rs2 = 1'b1;
                    decoded_comb.use_rd  = 1'b1;
                    // Differentiate ADD (funct7=0x00) vs SUB (funct7=0x20)
                    decoded_comb.alu_op  = (funct3 == 3'b000 && funct7[5]) ? 5'b01000 : {2'b00, funct3};
                end

                // BRANCH (beq, bne, blt, bge)
                7'b1100011: begin
                    decoded_comb.op_type = OP_BRANCH;
                    decoded_comb.use_rs1 = 1'b1;
                    decoded_comb.use_rs2 = 1'b1;
                    decoded_comb.imm     = {{20{decode_in.inst[31]}}, decode_in.inst[7], decode_in.inst[30:25], decode_in.inst[11:8], 1'b0};
                    decoded_comb.alu_op  = {2'b10, funct3};
                end

                // LOAD (lb, lh, lw, lbu, lhu)
                7'b0000011: begin
                    decoded_comb.op_type = OP_LOAD;
                    decoded_comb.use_rs1 = 1'b1;
                    decoded_comb.use_rd  = 1'b1;
                    decoded_comb.imm     = {{20{decode_in.inst[31]}}, decode_in.inst[31:20]};
                end

                // STORE (sb, sh, sw)
                7'b0100011: begin
                    decoded_comb.op_type = OP_STORE;
                    decoded_comb.use_rs1 = 1'b1;
                    decoded_comb.use_rs2 = 1'b1;
                    decoded_comb.imm     = {{20{decode_in.inst[31]}}, decode_in.inst[31:25], decode_in.inst[11:7]};
                end

                // JAL
                7'b1101111: begin
                    decoded_comb.op_type = OP_JAL;
                    decoded_comb.use_rd  = 1'b1;
                    decoded_comb.imm     = {{12{decode_in.inst[31]}}, decode_in.inst[19:12], decode_in.inst[20], decode_in.inst[30:21], 1'b0};
                end

                // JALR
                7'b1100111: begin
                    decoded_comb.op_type = OP_JALR;
                    decoded_comb.use_rs1 = 1'b1;
                    decoded_comb.use_rd  = 1'b1;
                    decoded_comb.imm     = {{20{decode_in.inst[31]}}, decode_in.inst[31:20]};
                end

                default: begin
                    // Unknown instruction falls back to a NOP mapping
                    decoded_comb.op_type = OP_SYSTEM;
                end
            endcase
        end
    end

    // Sequential Pipeline Registry Update
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            decode_out.pc         <= '0;
            decode_out.op_type    <= OP_SYSTEM;
            decode_out.alu_op     <= '0;
            decode_out.rs1        <= '0;
            decode_out.rs2        <= '0;
            decode_out.rd         <= '0;
            decode_out.use_rs1    <= 1'b0;
            decode_out.use_rs2    <= 1'b0;
            decode_out.use_rd     <= 1'b0;
            decode_out.imm        <= '0;
            decode_out.pred_taken <= 1'b0;
        end else if (flush) begin
            decode_out.op_type    <= OP_SYSTEM;
            decode_out.use_rs1    <= 1'b0;
            decode_out.use_rs2    <= 1'b0;
            decode_out.use_rd     <= 1'b0;
        end else if (!stall) begin
            decode_out            <= decoded_comb;
        end
    end

endmodule
