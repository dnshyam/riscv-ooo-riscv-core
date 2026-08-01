`timescale 1ns/1ps

module l2_coherent_cache #(
    parameter int L2_LINES    = 512,
    parameter int LINE_BITS   = $clog2(L2_LINES),
    parameter int TAG_BITS    = 32 - LINE_BITS - 2
)(
    input  logic              clk,
    input  logic              rst_n,
    
    // Inbound Core L1 Cache Port Network
    input  logic              l1_req_valid,
    input  logic              l1_req_write,
    input  logic [31:0]       l1_req_addr,
    input  logic [31:0]       l1_req_wdata,
    output logic              l1_req_ready,
    output logic [31:0]       l1_resp_rdata,
    
    // Snoop/Coherence Interface
    output logic              snoop_invalidate_valid,
    output logic [31:0]       snoop_invalidate_addr,
    
    // System Main Memory Bus Interface
    output logic              mem_bus_valid,
    output logic              mem_bus_write,
    output logic [31:0]       mem_bus_addr,
    output logic [31:0]       mem_bus_wdata,
    input  logic              mem_bus_ready,
    input  logic [31:0]       mem_bus_rdata
);

    logic [31:0]         l2_data_array [0:L2_LINES-1];
    logic [TAG_BITS-1:0] l2_tag_array  [0:L2_LINES-1];
    logic                l2_valid_bits [0:L2_LINES-1];

    logic [LINE_BITS-1:0] index;
    logic [TAG_BITS-1:0]  tag;
    
    assign index = l1_req_addr[LINE_BITS+1:2];
    assign tag   = l1_req_addr[31:32-TAG_BITS];

    logic l2_hit;
    assign l2_hit = l2_valid_bits[index] && (l2_tag_array[index] == tag);

    typedef enum logic [1:0] {
        IDLE,
        MEM_ACCESS,
        SNOOP_BROADCAST
    } l2_state_e;

    l2_state_e current_state, next_state;

    always_comb begin
        next_state             = current_state;
        l1_req_ready           = 1'b0;
        l1_resp_rdata          = 32'b0;
        snoop_invalidate_valid = 1'b0;
        snoop_invalidate_addr  = l1_req_addr;
        mem_bus_valid          = 1'b0;
        mem_bus_write          = l1_req_write;
        mem_bus_addr           = l1_req_addr;
        mem_bus_wdata          = l1_req_wdata;

        case (current_state)
            IDLE: begin
                if (l1_req_valid) begin
                    if (l1_req_write) begin
                        next_state = SNOOP_BROADCAST;
                    end else if (l2_hit) begin
                        l1_resp_rdata = l2_data_array[index];
                        l1_req_ready  = 1'b1;
                    end else begin
                        next_state = MEM_ACCESS;
                    end
                end
            end

            SNOOP_BROADCAST: begin
                snoop_invalidate_valid = 1'b1;
                mem_bus_valid = 1'b1;
                if (mem_bus_ready) begin
                    l1_req_ready = 1'b1;
                    next_state   = IDLE;
                end
            end

            MEM_ACCESS: begin
                mem_bus_valid = 1'b1;
                if (mem_bus_ready) begin
                    l1_resp_rdata = mem_bus_rdata;
                    l1_req_ready  = 1'b1;
                    next_state    = IDLE;
                end
            end

            default: next_state = IDLE;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
            for (int i = 0; i < L2_LINES; i++) l2_valid_bits[i] = 1'b0; // FIXED: Blocking assignment
        end else begin
            current_state <= next_state;

            if (l1_req_valid && l1_req_ready) begin
                if (l1_req_write) begin
                    l2_data_array[index] <= l1_req_wdata;
                    l2_tag_array[index]  <= tag;
                    l2_valid_bits[index] <= 1'b1;
                end else if (!l2_hit) begin
                    l2_data_array[index] <= mem_bus_rdata;
                    l2_tag_array[index]  <= tag;
                    l2_valid_bits[index] <= 1'b1;
                end
            end
        end
    end

endmodule
