`timescale 1ns/1ps

module fetch_stage
import riscv_pkg::*;
(
    input  logic                   clk,
    input  logic                   rst_n,
    
    // Pipeline Controls
    input  logic                   stall,
    input  logic                   flush,
    input  logic [XLEN-1:0]        flush_pc,
    
    // Instruction Memory Interface (Simplified)
    output logic [XLEN-1:0]        imem_addr,
    input  logic [INST_WIDTH-1:0]  imem_rdata,
    input  logic                   imem_valid,
    
    // Branch Predictor Interface Updates
    input  logic                   bpu_update_en,
    input  logic [XLEN-1:0]        bpu_update_pc,
    input  logic                   bpu_actual_taken,
    
    // Pipeline Output
    output fetch_pkt_t             fetch_out
);

    logic [XLEN-1:0] pc_reg;
    logic [XLEN-1:0] next_pc;
    logic            bpu_pred_taken;
    logic [XLEN-1:0] bpu_pred_target;

    // Instantiate Base TAGE Predictor
    tage_base #(
        .ENTRY_COUNT(1024)
    ) u_tage_base (
        .clk          (clk),
        .rst_n        (rst_n),
        .look_up_pc   (pc_reg),
        .pred_taken   (bpu_pred_taken),
        .update_en    (bpu_update_en),
        .update_pc    (bpu_update_pc),
        .actual_taken (bpu_actual_taken)
    );

    // Simple Target Generation (PC + 4 for NT, immediate targets handled down-pipe)
    assign bpu_pred_target = pc_reg + 4; 

    // Next PC Mux Logic
    always_comb begin
        if (flush) begin
            next_pc = flush_pc;
        end else if (stall) begin
            next_pc = pc_reg;
        end else if (bpu_pred_taken) begin
            // Placeholder target calculation for direct branches if detected early
            next_pc = pc_reg + 4; 
        end else begin
            next_pc = pc_reg + 4;
        end
    end

    // Program Counter Register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_reg <= 32'h0000_0000;
        end else begin
            pc_reg <= next_pc;
        end
    end

    // Instruction Memory Address Output
    assign imem_addr = pc_reg;

    // Package the output register to Decode Stage
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fetch_out.pc          <= 32'h0000_0000;
            fetch_out.inst        <= 32'h0000_0013; // NOP (addi x0, x0, 0)
            fetch_out.valid       <= 1'b0;
            fetch_out.pred_taken  <= 1'b0;
            fetch_out.pred_target <= 32'h0000_0000;
        end else if (flush) begin
            fetch_out.valid       <= 1'b0;
            fetch_out.inst        <= 32'h0000_0013;
        end else if (!stall) begin
            fetch_out.pc          <= pc_reg;
            fetch_out.inst        <= imem_valid ? imem_rdata : 32'h0000_0013;
            fetch_out.valid       <= imem_valid;
            fetch_out.pred_taken  <= bpu_pred_taken;
            fetch_out.pred_target <= bpu_pred_target;
        end
    end

endmodule
