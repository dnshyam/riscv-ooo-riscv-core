`timescale 1ns/1ps

module tb_top;

    import riscv_pkg::*;

    // System Signals
    logic clk;
    logic rst_n;

    // Core Interconnect Wires
    logic [XLEN-1:0]        imem_addr;
    logic [INST_WIDTH-1:0]  imem_rdata;
    logic                   imem_valid;

    // Core Pipeline to L1 Cache Interconnect Wires
    logic                   core_to_l1_valid;
    logic                   core_to_l1_write;
    logic [31:0]            core_to_l1_addr;
    logic [31:0]            core_to_l1_wdata;
    logic                   l1_to_core_ready;
    logic [31:0]            l1_to_core_rdata;

    // L1 Cache to L2 Cache Interconnect Wires
    logic                   l1_to_l2_valid;
    logic                   l1_to_l2_write;
    logic [31:0]            l1_to_l2_addr;
    logic [31:0]            l1_to_l2_wdata;
    logic                   l2_to_l1_ready;
    logic [31:0]            l2_to_l1_rdata;

    // L2 Cache to Main Memory Bus Interconnect Wires
    logic                   mem_bus_valid;
    logic                   mem_bus_write;
    logic [31:0]            mem_bus_addr;
    logic [31:0]            mem_bus_wdata;
    logic                   mem_bus_ready;
    logic [31:0]            mem_bus_rdata;

    // Coherence Status Signals
    logic                   snoop_invalidate_valid;
    logic [31:0]            snoop_invalidate_addr;

    // Mock Memory Arrays
    logic [31:0] mock_imem [0:31];
    logic [31:0] mock_dmem [0:31];

    // Clock Generator Loop
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Instruction Memory Interconnect Driver Logic
    always_comb begin
        imem_valid = rst_n;
        if (imem_addr[6:2] < 32) begin
            imem_rdata = mock_imem[imem_addr[6:2]];
        end else begin
            imem_rdata = 32'h0000_0013; 
        end
    end

    // System Main Memory Bus Interconnect Latency Simulation Model
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_bus_ready <= 1'b0;
            mem_bus_rdata <= 32'b0;
        end else begin
            if (mem_bus_valid && !mem_bus_ready) begin
                #1; 
                mem_bus_ready <= 1'b1;
                if (mem_bus_write) begin
                    if (mem_bus_addr[6:2] < 32) mock_dmem[mem_bus_addr[6:2]] <= mem_bus_wdata;
                end else begin
                    mem_bus_rdata <= (mem_bus_addr[6:2] < 32) ? mock_dmem[mem_bus_addr[6:2]] : 32'hDEADBEEF;
                end
            end else begin
                mem_bus_ready <= 1'b0;
            end
        end
    end

    // 1. Core speculative Pipeline Top Instance
    pipeline_top u_pipeline_top (
        .clk                 (clk),
        .rst_n               (rst_n),
        .imem_addr           (imem_addr),
        .imem_rdata          (imem_rdata),
        .imem_valid          (imem_valid),
        .lsq_mem_req_valid   (core_to_l1_valid),
        .lsq_mem_req_write   (core_to_l1_write),
        .lsq_mem_req_addr    (core_to_l1_addr),
        .lsq_mem_req_wdata   (core_to_l1_wdata),
        .lsq_mem_req_ready   (l1_to_core_ready),
        .lsq_mem_rdata_out   (l1_to_core_rdata)
    );

    // 2. L1 Data Cache Instance
    l1_dcache u_l1_dcache (
        .clk            (clk),
        .rst_n          (rst_n),
        .req_valid      (core_to_l1_valid),
        .req_write      (core_to_l1_write),
        .req_addr       (core_to_l1_addr),
        .req_wdata      (core_to_l1_wdata),
        .req_ready      (l1_to_core_ready),
        .resp_rdata     (l1_to_core_rdata),
        .l2_req_valid   (l1_to_l2_valid),
        .l2_req_write   (l1_to_l2_write),
        .l2_req_addr    (l1_to_l2_addr),
        .l2_req_wdata   (l1_to_l2_wdata),
        .l2_req_ready   (l2_to_l1_ready),
        .l2_resp_rdata  (l2_to_l1_rdata)
    );

    // 3. L2 Coherent Cache Controller Instance
    l2_coherent_cache u_l2_coherent_cache (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .l1_req_valid           (l1_to_l2_valid),
        .l1_req_write           (l1_to_l2_write),
        .l1_req_addr            (l1_to_l2_addr),
        .l1_req_wdata           (l1_to_l2_wdata),
        .l1_req_ready           (l2_to_l1_ready),
        .l1_resp_rdata          (l2_to_l1_rdata),
        .snoop_invalidate_valid (snoop_invalidate_valid),
        .snoop_invalidate_addr  (snoop_invalidate_addr),
        .mem_bus_valid          (mem_bus_valid),
        .mem_bus_write          (mem_bus_write),
        .mem_bus_addr           (mem_bus_addr),
        .mem_bus_wdata          (mem_bus_wdata),
        .mem_bus_ready          (mem_bus_ready),
        .mem_bus_rdata          (mem_bus_rdata)
    );

    // Continuous Monitoring of Instruction Commit Pipeline Phases
    always @(posedge clk) begin
        if (u_pipeline_top.u_rob.commit_valid) begin
            $display("[COMMIT EVENT] Time: %0t | PC: 0x%h | Freeing physical tag: PR%0d", 
                     $time, u_pipeline_top.u_rob.commit_pc, u_pipeline_top.u_rob.commit_pprev_rd);
        end
    end

    // Simulation Task Sequence Execution Blocks
    initial begin
        $display("=== Launching RISC-V Out-of-Order Core Verification Testbench ===");
        
        // Initialize Mock Data Instruction streams (Standard RV32I hex commands)
        mock_imem[0] = 32'h00500093; // addi x1, x0, 5   (PR1 allocated)
        mock_imem[1] = 32'h00a00113; // addi x2, x0, 10  (PR2 allocated)
        mock_imem[2] = 32'h002081b3; // add  x3, x1, x2  (Speculative RAW structural dependency)
        mock_imem[3] = 32'h00000013; // NOP
        mock_imem[4] = 32'h00000013; // NOP
        
        for (int i = 5; i < 32; i++) mock_imem[i] = 32'h0000_0013; 
        for (int j = 0; j < 32; j++) mock_dmem[j] = 32'h0000_0000;

        // Sequence Triggers
        rst_n = 1'b0;
        #20;
        rst_n = 1'b1;
        
        // Execute structural run cycle windows
        #500;
        
        $display("\n=======================================================");
        $display("===    MICROARCHITECTURAL PERFORMANCE DASHBOARD     ===");
        $display("=======================================================");
        $display(" Total Simulation Cycles : %0d", u_pipeline_top.hpm_cycles);
        $display(" Instructions Retired    : %0d", u_pipeline_top.hpm_inst_retired);
        $display(" TAGE Predictor Flushes  : %0d", u_pipeline_top.hpm_bpu_mispredicts);
        $display(" Pipeline Structural Stalls: %0d", u_pipeline_top.hpm_pipeline_stalls);
        $display("=======================================================\n");

        $display("=== Speculative Out-of-Order Verification Cycle Sequence Complete! ===");
        $finish;
    end

endmodule


