`timescale 1ns/1ps

module load_store_queue
import riscv_pkg::*;
(
    input  logic                      clk,
    input  logic                      rst_n,
    input  logic                      flush,
    
    // Dispatch Interface Allocation Inputs
    input  logic                      lsq_alloc_valid,
    input  op_type_e                  lsq_alloc_type,
    input  logic [ROB_INDEX_BITS-1:0] lsq_alloc_rob_id,
    output logic                      lsq_full,
    
    // Execution Unit Address Resolution Inputs
    input  logic                      addr_calc_valid,
    input  logic [ROB_INDEX_BITS-1:0] addr_calc_rob_id,
    input  logic [XLEN-1:0]           resolved_addr,
    input  logic [XLEN-1:0]           store_data_in,
    
    // Commit Release Interface Boundary
    input  logic                      commit_valid,
    input  logic [XLEN-1:0]           commit_pc,
    
    // Cache Processing Access Port Networks
    output logic                      mem_req_valid,
    output logic                      mem_req_write,
    output logic [XLEN-1:0]           mem_req_addr,
    output logic [XLEN-1:0]           mem_req_wdata,
    input  logic                      mem_req_ready,
    input  logic [XLEN-1:0]           mem_rdata_out,
    
    // Complete Backend Writeback Channels
    output logic                      lsq_wb_valid,
    output logic [ROB_INDEX_BITS-1:0] lsq_wb_rob_id,
    output logic [XLEN-1:0]           lsq_wb_data
);

    // Structural Storage Elements for Memory Scheduling
    typedef struct packed {
        logic                     valid;
        logic                     is_store;
        logic [ROB_INDEX_BITS-1:0] rob_id;
        logic                     addr_valid;
        logic [XLEN-1:0]          address;
        logic [XLEN-1:0]          data;
        logic                     committed;
    } lsq_entry_t;

    lsq_entry_t lsq_slots [0:7]; 
    
    // Capacity logic check calculations
    always_comb begin
        lsq_full = 1'b1;
        for (int i = 0; i < 8; i++) begin
            if (!lsq_slots[i].valid) lsq_full = 1'b0;
        end
    end

    // Forwarding logic and cache request dispatch
    logic forwarding_hit;
    logic [XLEN-1:0] forwarded_data;

    always_comb begin
        mem_req_valid  = 1'b0;
        mem_req_write  = 1'b0;
        mem_req_addr   = '0;
        mem_req_wdata  = '0;
        lsq_wb_valid   = 1'b0;
        lsq_wb_rob_id  = '0;
        lsq_wb_data    = '0;
        forwarding_hit = 1'b0;
        forwarded_data = '0;

        for (int i = 0; i < 8; i++) begin
            if (lsq_slots[i].valid && lsq_slots[i].addr_valid) begin
                if (lsq_slots[i].is_store && lsq_slots[i].committed) begin
                    mem_req_valid = 1'b1;
                    mem_req_write = 1'b1;
                    mem_req_addr  = lsq_slots[i].address;
                    mem_req_wdata = lsq_slots[i].data;
                end else if (!lsq_slots[i].is_store) begin
                    // Reset lookup trackers for each pass
                    forwarding_hit = 1'b0;
                    forwarded_data = '0;
                    
                    for (int j = 0; j < 8; j++) begin
                        if (lsq_slots[j].valid && lsq_slots[j].is_store && lsq_slots[j].addr_valid && (lsq_slots[j].address == lsq_slots[i].address)) begin
                            forwarding_hit = 1'b1;
                            forwarded_data = lsq_slots[j].data;
                        end
                    end
                    
                    if (forwarding_hit) begin
                        lsq_wb_valid  = 1'b1;
                        lsq_wb_rob_id = lsq_slots[i].rob_id;
                        lsq_wb_data   = forwarded_data;
                    end else begin
                        mem_req_valid = 1'b1;
                        mem_req_write = 1'b0;
                        mem_req_addr  = lsq_slots[i].address;
                        
                        if (mem_req_ready) begin
                            lsq_wb_valid  = 1'b1;
                            lsq_wb_rob_id = lsq_slots[i].rob_id;
                            lsq_wb_data   = mem_rdata_out;
                        end
                    end
                end
            end
        end
    end

    // Sequential update tracking registers
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 8; i++) lsq_slots[i] <= '0;
        end else if (flush) begin
            for (int i = 0; i < 8; i++) begin
                if (!lsq_slots[i].committed) lsq_slots[i] <= '0;
            end
        end else begin
            if (lsq_alloc_valid && !lsq_full) begin
                logic alloc_done = 1'b0;
                for (int i = 0; i < 8; i++) begin
                    if (!lsq_slots[i].valid && !alloc_done) begin
                        lsq_slots[i].valid     <= 1'b1;
                        lsq_slots[i].is_store  <= (lsq_alloc_type == OP_STORE);
                        lsq_slots[i].rob_id    <= lsq_alloc_rob_id;
                        lsq_slots[i].addr_valid<= 1'b0;
                        lsq_slots[i].committed <= 1'b0;
                        alloc_done             = 1'b1;
                    end
                end
            end

            if (addr_calc_valid) begin
                for (int i = 0; i < 8; i++) begin
                    if (lsq_slots[i].valid && (lsq_slots[i].rob_id == addr_calc_rob_id)) begin
                        lsq_slots[i].address    <= resolved_addr;
                        lsq_slots[i].data       <= store_data_in;
                        lsq_slots[i].addr_valid <= 1'b1;
                    end
                end
            end

            if (commit_valid) begin
                for (int i = 0; i < 8; i++) begin
                    if (lsq_slots[i].valid && lsq_slots[i].is_store && !lsq_slots[i].committed) begin
                        lsq_slots[i].committed <= 1'b1;
                    end
                end
            end

            if (mem_req_valid && mem_req_ready) begin
                for (int i = 0; i < 8; i++) begin
                    if (lsq_slots[i].valid && (lsq_slots[i].address == mem_req_addr)) begin
                        if (lsq_slots[i].is_store && lsq_slots[i].committed) lsq_slots[i] <= '0;
                        else if (!lsq_slots[i].is_store) lsq_slots[i] <= '0;
                    end
                end
            end
        end
    end

endmodule
