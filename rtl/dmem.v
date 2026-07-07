// =============================================================================
// dmem.v  --  Harvard data memory with a tiny direct-mapped D-cache
//
// Supports LoongArch LD/ST at byte, halfword, and word granularity with
// sign/zero extension on load.  The backing store remains byte-addressable and
// little-endian, while the CPU-facing path goes through a one-word-line
// direct-mapped cache.  Misses assert stall for MISS_PENALTY cycles, then fill
// from the backing memory.  Stores are write-through and update resident lines.
//
// Word/half accesses assume natural alignment (the ISA raises an unaligned
// exception otherwise; we do not model that trap here).
// =============================================================================
`timescale 1ns / 1ps
`include "defines.vh"

module dmem #(
    parameter BYTES = 4096,
    parameter LINES = 16,
    parameter MISS_PENALTY = 2
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] addr,
    input  wire        we,          // store enable
    input  wire        re,          // load enable (for X-cleanliness only)
    input  wire [1:0]  width,       // MEM_W / MEM_H / MEM_B
    input  wire        load_unsigned,
    input  wire [31:0] wdata,       // store data (from rd)
    output reg  [31:0] rdata,       // load result, extended
    output wire        stall
);
    reg [7:0] mem [0:BYTES-1];
    reg [31:0] cache_data [0:LINES-1];
    reg [31:0] cache_tag  [0:LINES-1];
    reg        cache_valid[0:LINES-1];

    integer i;
    initial begin
        for (i = 0; i < BYTES; i = i + 1)
            mem[i] = 8'h00;
        for (i = 0; i < LINES; i = i + 1) begin
            cache_data[i]  = 32'd0;
            cache_tag[i]   = 32'd0;
            cache_valid[i] = 1'b0;
        end
    end

    localparam INDEX_BITS = (LINES <= 1) ? 1 : $clog2(LINES);
    localparam PENALTY = (MISS_PENALTY < 1) ? 1 : MISS_PENALTY;

    wire        access = rst_n && (we || re);
    wire [31:0] word_addr = addr >> 2;
    wire [INDEX_BITS-1:0] index = word_addr[INDEX_BITS-1:0];
    wire [31:0] tag = word_addr >> INDEX_BITS;
    wire [1:0]  byte_off = addr[1:0];

    reg        busy;
    reg [7:0]  miss_count;
    reg [31:0] miss_addr;
    reg [INDEX_BITS-1:0] miss_index;
    reg [31:0] miss_tag;
    reg        miss_we;
    reg [1:0]  miss_width;
    reg [31:0] miss_wdata;

    wire hit = cache_valid[index] && (cache_tag[index] == tag);
    wire miss = access && !hit && !busy;
    assign stall = access && (busy || miss);

    function [31:0] read_backing_word;
        input [31:0] a;
        reg [31:0] base;
        begin
            base = {a[31:2], 2'b00};
            read_backing_word = {mem[base+3], mem[base+2], mem[base+1], mem[base]};
        end
    endfunction

    function [31:0] merge_store_word;
        input [31:0] old_word;
        input [31:0] store_data;
        input [1:0]  store_width;
        input [1:0]  off;
        reg [31:0] tmp;
        begin
            tmp = old_word;
            case (store_width)
                `MEM_B: begin
                    case (off)
                        2'd0: tmp[7:0]   = store_data[7:0];
                        2'd1: tmp[15:8]  = store_data[7:0];
                        2'd2: tmp[23:16] = store_data[7:0];
                        default: tmp[31:24] = store_data[7:0];
                    endcase
                end
                `MEM_H: begin
                    if (off[1])
                        tmp[31:16] = store_data[15:0];
                    else
                        tmp[15:0] = store_data[15:0];
                end
                default: tmp = store_data;
            endcase
            merge_store_word = tmp;
        end
    endfunction

    function [31:0] load_extend_word;
        input [31:0] word;
        input [1:0]  load_width;
        input        is_unsigned;
        input [1:0]  off;
        reg [7:0]  b;
        reg [15:0] h;
        begin
            case (off)
                2'd0: b = word[7:0];
                2'd1: b = word[15:8];
                2'd2: b = word[23:16];
                default: b = word[31:24];
            endcase
            h = off[1] ? word[31:16] : word[15:0];
            case (load_width)
                `MEM_B : load_extend_word = is_unsigned ? {24'b0, b}
                                                        : {{24{b[7]}}, b};
                `MEM_H : load_extend_word = is_unsigned ? {16'b0, h}
                                                        : {{16{h[15]}}, h};
                default: load_extend_word = word;
            endcase
        end
    endfunction

    task write_backing;
        input [31:0] a;
        input [1:0]  store_width;
        input [31:0] store_data;
        begin
            mem[a] <= store_data[7:0];
            if (store_width != `MEM_B)
                mem[a+1] <= store_data[15:8];
            if (store_width == `MEM_W) begin
                mem[a+2] <= store_data[23:16];
                mem[a+3] <= store_data[31:24];
            end
        end
    endtask

    reg [31:0] fill_word;
    reg [31:0] store_word;

    always @(*) begin
        if (hit)
            rdata = load_extend_word(cache_data[index], width, load_unsigned, byte_off);
        else
            rdata = 32'd0;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0;
            miss_count <= 8'd0;
            miss_addr <= 32'd0;
            miss_index <= {INDEX_BITS{1'b0}};
            miss_tag <= 32'd0;
            miss_we <= 1'b0;
            miss_width <= `MEM_W;
            miss_wdata <= 32'd0;
            for (i = 0; i < LINES; i = i + 1)
                cache_valid[i] <= 1'b0;
        end else if (busy) begin
            if (miss_count >= PENALTY - 1) begin
                fill_word = read_backing_word(miss_addr);
                if (miss_we) begin
                    fill_word = merge_store_word(fill_word, miss_wdata, miss_width, miss_addr[1:0]);
                    write_backing(miss_addr, miss_width, miss_wdata);
                end
                cache_data[miss_index] <= fill_word;
                cache_tag[miss_index] <= miss_tag;
                cache_valid[miss_index] <= 1'b1;
                busy <= 1'b0;
            end else begin
                miss_count <= miss_count + 8'd1;
            end
        end else if (miss) begin
            busy <= 1'b1;
            miss_count <= 8'd0;
            miss_addr <= addr;
            miss_index <= index;
            miss_tag <= tag;
            miss_we <= we;
            miss_width <= width;
            miss_wdata <= wdata;
        end else if (access && hit && we) begin
            store_word = merge_store_word(cache_data[index], wdata, width, byte_off);
            cache_data[index] <= store_word;
            write_backing(addr, width, wdata);
        end
    end
endmodule
