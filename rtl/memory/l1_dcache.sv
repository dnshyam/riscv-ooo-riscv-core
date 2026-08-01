`timescale 1ns/1ps

module l1_dcache #(
    parameter int CACHE_LINES = 256,
    parameter int LINE_BITS   = $clog2(CACHE_LINES),
    parameter int TAG_BITS    = 32 - LINE_BITS - 2
)(
    input  logic              clk,
    input  logic              rst_n,
    
    // Core structural control channels
    input  logic              req_valid,
    input  logic              req_write,
    input  logic [31:0]       req_addr,
    input  logic [31:0]       req_wdata,
    output logic              req_ready,
    output logic [31:0]       resp_rdata,
    
    // Main system broadcast interconnect interface
    output logic              l2_req_valid,
    output logic              l2_req_write,
    output logic [31:0]       l2_req_addr,
    output logic [31:0]       l2_req_wdata,
    input  logic              l2_req_ready,
    input  logic [31:0]       l2_resp_rdata
);

    logic [31:0]     data_array [0:CACHE_LINES-1];
    logic [TAG_BITS-1:0] tag_array  [0:CACHE_LINES-1];
    logic            valid_bits [0:CACHE_LINES-1];

    logic [LINE_BITS-1:0] index;
    logic [TAG_BITS-1:0]  tag;
    
    assign index = req_addr[LINE_BITS+1:2];
    assign tag   = req_addr[31:32-TAG_BITS];

    logic cache_hit;
    assign cache_hit = valid_bits[index] && (tag_array[index] == tag);

    always_comb begin
        req_ready     = 1'b0;
        resp_rdata    = 32'b0;
        l2_req_valid  = 1'b0;
        l2_req_write  = 1'b0;
        l2_req_addr   = req_addr;
        l2_req_wdata  = req_wdata;

        if (req_valid) begin
            if (req_write) begin
                l2_req_valid  = 1'b1;
                l2_req_write  = 1'b1;
                req_ready     = l2_req_ready;
            end else begin
                if (cache_hit) begin
                    resp_rdata = data_array[index];
                    req_ready  = 1'b1;
                end else begin
                    l2_req_valid = 1'b1;
                    l2_req_write = 1'b0;
                    req_ready    = l2_req_ready;
                    resp_rdata   = l2_resp_rdata;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < CACHE_LINES; i++) valid_bits[i] = 1'b0; // FIXED: Blocking assignment
        end else if (req_valid && l2_req_ready) begin
            if (req_write) begin
                data_array[index] <= req_wdata;
                tag_array[index]  <= tag;
                valid_bits[index] <= 1'b1;
            end else if (!cache_hit) begin
                data_array[index] <= l2_resp_rdata;
                tag_array[index]  <= tag;
                valid_bits[index] <= 1'b1;
            end
        end
    end

endmodule
