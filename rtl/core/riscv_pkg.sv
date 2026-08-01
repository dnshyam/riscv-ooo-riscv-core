`timescale 1ns/1ps

package riscv_pkg;

    // Architectural Parameters
    localparam int XLEN = 32;
    localparam int INST_WIDTH = 32;
    localparam int PHYS_REGS = 64;
    localparam int ARCH_REGS = 32;

    // Out-of-Order Parameters
    localparam int ROB_DEPTH = 64;
    localparam int ROB_INDEX_BITS = $clog2(ROB_DEPTH);
    localparam int IQ_DEPTH = 16;
    localparam int PHYS_REG_BITS = $clog2(PHYS_REGS);
    localparam int ARCH_REG_BITS = $clog2(ARCH_REGS);

    // Branch Prediction Parameters
    localparam int TAGE_TABLES = 4;
    localparam int TAGE_PRED_BITS = 2;

    // Opcode Types
    typedef enum logic [4:0] {
        OP_ALU,
        OP_BRANCH,
        OP_LOAD,
        OP_STORE,
        OP_JAL,
        OP_JALR,
        OP_SYSTEM
    } op_type_e;

    // Pipeline Structures
    typedef struct packed {
        logic [XLEN-1:0] pc;
        logic [INST_WIDTH-1:0] inst;
        logic valid;
        logic pred_taken;
        logic [XLEN-1:0] pred_target;
    } fetch_pkt_t;

    typedef struct packed {
        logic [XLEN-1:0] pc;
        op_type_e op_type;
        logic [4:0] alu_op;
        logic [ARCH_REG_BITS-1:0] rs1;
        logic [ARCH_REG_BITS-1:0] rs2;
        logic [ARCH_REG_BITS-1:0] rd;
        logic use_rs1;
        logic use_rs2;
        logic use_rd;
        logic [XLEN-1:0] imm;
        logic pred_taken;
    } decode_pkt_t;

    // Rename Packet Structure
    typedef struct packed {
        logic [XLEN-1:0]     pc;
        op_type_e            op_type;
        logic [4:0]          alu_op;
        logic [PHYS_REG_BITS-1:0] prs1;
        logic [PHYS_REG_BITS-1:0] prs2;
        logic [PHYS_REG_BITS-1:0] prd;
        logic [PHYS_REG_BITS-1:0] pprev_rd;
        logic                use_rs1;
        logic                use_rs2;
        logic                use_rd;
        logic [XLEN-1:0]     imm;
        logic                pred_taken;
        logic                valid;
    } rename_pkt_t;

    // ROB Storage Packet Structure
    typedef struct packed {
        logic [XLEN-1:0]          pc;
        logic [PHYS_REG_BITS-1:0] prd;
        logic [PHYS_REG_BITS-1:0] pprev_rd;
        logic                     use_rd;
        logic                     completed;
        logic                     exception;
        logic                     is_branch;
        logic                     mispredicted;
    } rob_entry_t;

    // Issue Queue Payload Entry Structure
    typedef struct packed {
        logic [XLEN-1:0]          pc;
        op_type_e                 op_type;
        logic [4:0]               alu_op;
        logic [PHYS_REG_BITS-1:0] prs1;
        logic [PHYS_REG_BITS-1:0] prs2;
        logic [PHYS_REG_BITS-1:0] prd;
        logic                     rs1_ready;
        logic                     rs2_ready;
        logic [XLEN-1:0]          imm;
        logic [ROB_INDEX_BITS-1:0] rob_id;
        logic                     pred_taken;
    } iq_entry_t;

endpackage : riscv_pkg
