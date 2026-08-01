`timescale 1ns/1ps

module pipeline_top
import riscv_pkg::*;
(
    input  logic                   clk,
    input  logic                   rst_n,
    
    // Instruction Memory Interface Boundary Connections
    output logic [XLEN-1:0]        imem_addr,
    input  logic [INST_WIDTH-1:0]  imem_rdata,
    input  logic                   imem_valid,

    // Exported LSQ to L1 Cache Interface Ports
    output logic                   lsq_mem_req_valid,
    output logic                   lsq_mem_req_write,
    output logic [XLEN-1:0]        lsq_mem_req_addr,
    output logic [XLEN-1:0]        lsq_mem_req_wdata,
    input  logic                   lsq_mem_req_ready,
    input  logic [XLEN-1:0]        lsq_mem_rdata_out
);

    // Core Global Control Wires
    logic stall_pipeline;
    logic flush_pipeline;
    logic [XLEN-1:0] flush_target_pc;

    // Fetch to Decode Interconnect Packet
    fetch_pkt_t fetch_to_decode;

    // Decode to Rename Interconnect Packets
    decode_pkt_t decode_to_rename;
    logic        decode_valid;

    // Rename to Backend Structure Wires
    rename_pkt_t rename_to_backend;
    logic        rename_alloc_stall;

    // ROB Allocations and Commit Tracking Updates
    logic [ROB_INDEX_BITS-1:0] rob_allocated_id;
    logic                      rob_structure_full;
    
    logic                      commit_evt_valid;
    logic [PHYS_REG_BITS-1:0]  commit_prd_tag;
    logic [PHYS_REG_BITS-1:0]  commit_pprev_rd_tag;
    logic                      commit_writes_reg;
    logic [XLEN-1:0]           commit_event_pc;

    // Issue Queue Allocation and Tracking Signals
    iq_entry_t                 issued_backend_pkt;
    logic                      issued_pkt_valid;
    logic                      iq_structure_full;

    // Physical Register File Read Networks
    logic [XLEN-1:0]           prf_source1_data;
    logic [XLEN-1:0]           prf_source2_data;

    // Execution Unit Completion Writeback Channels
    logic                      wb_valid_ch1;
    logic [ROB_INDEX_BITS-1:0] wb_rob_id_ch1;
    logic [PHYS_REG_BITS-1:0]  wb_prd_tag_ch1;
    logic [XLEN-1:0]           wb_computed_data_ch1;
    logic                      wb_exception_ch1;
    logic                      wb_mispredict_ch1;

    // Load/Store Queue Interconnect Wires
    logic                      lsq_structure_full;
    logic                      lsq_wb_valid;
    logic [ROB_INDEX_BITS-1:0] lsq_wb_rob_id;
    logic [XLEN-1:0]           lsq_wb_data;

    // === Hardware Performance Counters (HPM) ===
    logic [63:0] hpm_cycles;
    logic [63:0] hpm_inst_retired;
    logic [63:0] hpm_bpu_mispredicts;
    logic [63:0] hpm_pipeline_stalls;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hpm_cycles           <= '0;
            hpm_inst_retired     <= '0;
            hpm_bpu_mispredicts  <= '0;
            hpm_pipeline_stalls  <= '0;
        end else begin
            hpm_cycles <= hpm_cycles + 1'b1;
            if (commit_evt_valid) hpm_inst_retired <= hpm_inst_retired + 1'b1;
            if (flush_pipeline)    hpm_bpu_mispredicts <= hpm_bpu_mispredicts + 1'b1;
            if (stall_pipeline)    hpm_pipeline_stalls <= hpm_pipeline_stalls + 1'b1;
        end
    end

    // Structural Hazard Evaluator Logic for Stall Activations
    assign stall_pipeline     = rob_structure_full || iq_structure_full || rename_alloc_stall || lsq_structure_full;
    assign decode_valid       = fetch_to_decode.valid && !stall_pipeline;
    assign flush_target_pc    = commit_event_pc + 4; 

    // 1. Fetch Stage Instantiation
    fetch_stage u_fetch (
        .clk              (clk),
        .rst_n            (rst_n),
        .stall            (stall_pipeline),
        .flush            (flush_pipeline),
        .flush_pc         (flush_target_pc),
        .imem_addr        (imem_addr),
        .imem_rdata       (imem_rdata),
        .imem_valid       (imem_valid),
        .bpu_update_en    (commit_evt_valid && (commit_prd_tag != '0)),
        .bpu_update_pc    (commit_event_pc),
        .bpu_actual_taken (flush_pipeline),
        .fetch_out        (fetch_to_decode)
    );

    // 2. Decode Stage Instantiation
    decode_stage u_decode (
        .clk        (clk),
        .rst_n      (rst_n),
        .stall      (stall_pipeline),
        .flush      (flush_pipeline),
        .decode_in  (fetch_to_decode),
        .decode_out (decode_to_rename)
    );

    // 3. Rename Stage Instantiation
    rename_stage u_rename (
        .clk                 (clk),
        .rst_n               (rst_n),
        .stall               (stall_pipeline),
        .flush               (flush_pipeline),
        .rename_in           (decode_to_rename),
        .rename_in_valid     (decode_valid),
        .commit_valid        (commit_evt_valid),
        .commit_pprev_rd     (commit_pprev_rd_tag),
        .commit_use_rd       (commit_writes_reg),
        .rename_out          (rename_to_backend),
        .free_reg_alloc_fail (rename_alloc_stall)
    );

    // 4. Reorder Buffer (ROB) Instantiation
    rob u_rob (
        .clk                (clk),
        .rst_n              (rst_n),
        .alloc_en           (rename_to_backend.valid && !stall_pipeline),
        .alloc_pkt          (rename_to_backend),
        .alloc_rob_id       (rob_allocated_id),
        .rob_full           (rob_structure_full),
        .wb_valid           (wb_valid_ch1 || lsq_wb_valid), 
        .wb_rob_id          (lsq_wb_valid ? lsq_wb_rob_id : wb_rob_id_ch1),
        .wb_exception       (lsq_wb_valid ? 1'b0 : wb_exception_ch1),
        .wb_mispredicted    (lsq_wb_valid ? 1'b0 : wb_mispredict_ch1),
        .commit_valid       (commit_evt_valid),
        .commit_prd         (commit_prd_tag),
        .commit_pprev_rd    (commit_pprev_rd_tag),
        .commit_use_rd      (commit_writes_reg),
        .commit_pc          (commit_event_pc),
        .flush_ooo_pipeline (flush_pipeline)
    );

    // 5. Issue Queue (Reservation Station) Instantiation
    issue_queue u_issue_queue (
        .clk               (clk),
        .rst_n             (rst_n),
        .flush             (flush_pipeline),
        .dispatch_valid    (rename_to_backend.valid && !stall_pipeline),
        .dispatch_pkt      (rename_to_backend),
        .dispatch_rob_id   (rob_allocated_id),
        .wb_valid_1        (wb_valid_ch1),
        .wb_prd_1          (wb_prd_tag_ch1),
        .wb_valid_2        (lsq_wb_valid), 
        .wb_prd_2          (u_rob.rob_ram[lsq_wb_rob_id].prd),
        .issue_pkt         (issued_backend_pkt),
        .issue_valid       (issued_pkt_valid),
        .iq_full           (iq_structure_full)
    );

    // 6. Physical Register File (PRF) Instantiation
    physical_register_file u_prf (
        .clk    (clk),
        .raddr1 (issued_backend_pkt.prs1),
        .rdata1 (prf_source1_data),
        .raddr2 (issued_backend_pkt.prs2),
        .rdata2 (prf_source2_data),
        .wen1   (wb_valid_ch1),
        .waddr1 (wb_prd_tag_ch1),
        .wdata1 (wb_computed_data_ch1),
        .wen2   (lsq_wb_valid), 
        .waddr2 (u_rob.rob_ram[lsq_wb_rob_id].prd),
        .wdata2 (lsq_wb_data)
    );

    // 7. Execution Engine ALU Instance Block
    alu_unit u_alu_unit (
        .alu_in          (issued_backend_pkt),
        .src1_val        (prf_source1_data),
        .src2_val        (prf_source2_data),
        .wb_valid        (wb_valid_ch1),
        .wb_rob_id       (wb_rob_id_ch1),
        .wb_prd          (wb_prd_tag_ch1),
        .wb_data         (wb_computed_data_ch1),
        .wb_exception    (wb_exception_ch1),
        .wb_mispredicted (wb_mispredict_ch1)
    );

    // 8. Load/Store Queue (LSQ) Instantiation
    load_store_queue u_load_store_queue (
        .clk               (clk),
        .rst_n             (rst_n),
        .flush             (flush_pipeline),
        .lsq_alloc_valid   (rename_to_backend.valid && !stall_pipeline && (rename_to_backend.op_type == OP_LOAD || rename_to_backend.op_type == OP_STORE)),
        .lsq_alloc_type    (rename_to_backend.op_type),
        .lsq_alloc_rob_id  (rob_allocated_id),
        .lsq_full          (lsq_structure_full),
        .addr_calc_valid   (issued_pkt_valid && (issued_backend_pkt.op_type == OP_LOAD || issued_backend_pkt.op_type == OP_STORE)),
        .addr_calc_rob_id  (issued_backend_pkt.rob_id),
        .resolved_addr     (prf_source1_data + issued_backend_pkt.imm), 
        .store_data_in     (prf_source2_data),
        .commit_valid      (commit_evt_valid),
        .commit_pc         (commit_event_pc),
        .mem_req_valid     (lsq_mem_req_valid), 
        .mem_req_write     (lsq_mem_req_write),
        .mem_req_addr      (lsq_mem_req_addr),
        .mem_req_wdata     (lsq_mem_req_wdata),
        .mem_req_ready     (lsq_mem_req_ready), 
        .mem_rdata_out     (lsq_mem_rdata_out),
        .lsq_wb_valid      (lsq_wb_valid),
        .lsq_wb_rob_id     (lsq_wb_rob_id),
        .lsq_wb_data       (lsq_wb_data)
    );

endmodule
