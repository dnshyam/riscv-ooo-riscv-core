`timescale 1ns/1ps

module physical_register_file
import riscv_pkg::*;
(
    input  logic                      clk,
    
    // Read Port 1
    input  logic [PHYS_REG_BITS-1:0]  raddr1,
    output logic [XLEN-1:0]           rdata1,
    
    // Read Port 2
    input  logic [PHYS_REG_BITS-1:0]  raddr2,
    output logic [XLEN-1:0]           rdata2,
    
    // Write Port 1 (ALU/Execution Unit 1)
    input  logic                      wen1,
    input  logic [PHYS_REG_BITS-1:0]  waddr1,
    input  logic [XLEN-1:0]           wdata1,
    
    // Write Port 2 (Memory/Execution Unit 2)
    input  logic                      wen2,
    input  logic [PHYS_REG_BITS-1:0]  waddr2,
    input  logic [XLEN-1:0]           wdata2
);

    logic [XLEN-1:0] prf_array [0:PHYS_REGS-1];

    // Asynchronous Read Output Assignments
    assign rdata1 = (raddr1 == '0) ? '0 : prf_array[raddr1];
    assign rdata2 = (raddr2 == '0) ? '0 : prf_array[raddr2];

    // Synchronous Dual Write Port Handling
    always_ff @(posedge clk) begin
        if (wen1 && (waddr1 != '0)) begin
            prf_array[waddr1] <= wdata1;
        end
        if (wen2 && (waddr2 != '0)) begin
            prf_array[waddr2] <= wdata2;
        end
    end

endmodule
