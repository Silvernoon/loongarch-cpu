// =============================================================================
// dmem.v  —  Harvard data memory / D-Cache model (byte-addressable)
//
// Supports LoongArch LD/ST at byte, halfword, and word granularity with
// sign/zero extension on load.  Synchronous write, asynchronous read (fine for
// a single-cycle MEM stage in simulation).  Stored as a byte array so
// sub-word accesses are natural and little-endian, matching LoongArch.
//
// Word/half accesses assume natural alignment (the ISA raises an unaligned
// exception otherwise; we do not model that trap here).
// =============================================================================
`timescale 1ns / 1ps
`include "defines.vh"

module dmem #(
    parameter BYTES = 4096
)(
    input  wire        clk,
    input  wire [31:0] addr,
    input  wire        we,          // store enable
    input  wire        re,          // load enable (for X-cleanliness only)
    input  wire [1:0]  width,       // MEM_W / MEM_H / MEM_B
    input  wire        load_unsigned,
    input  wire [31:0] wdata,       // store data (from rd)
    output reg  [31:0] rdata        // load result, extended
);
    reg [7:0] mem [0:BYTES-1];
    integer i;
    initial for (i = 0; i < BYTES; i = i + 1) mem[i] = 8'h00;

    wire [31:0] idx = addr;   // byte index

    // ---- store : little-endian, sized -------------------------------------
    always @(posedge clk) begin
        if (we) begin
            mem[idx] <= wdata[7:0];
            if (width != `MEM_B) begin
                mem[idx+1] <= wdata[15:8];
            end
            if (width == `MEM_W) begin
                mem[idx+2] <= wdata[23:16];
                mem[idx+3] <= wdata[31:24];
            end
        end
    end

    // ---- load : assemble then sign/zero extend ----------------------------
    wire [7:0]  b0 = mem[idx];
    wire [7:0]  b1 = mem[idx+1];
    wire [7:0]  b2 = mem[idx+2];
    wire [7:0]  b3 = mem[idx+3];
    wire [15:0] half = {b1, b0};
    wire [31:0] word = {b3, b2, b1, b0};

    always @(*) begin
        case (width)
            `MEM_B : rdata = load_unsigned ? {24'b0, b0}
                                           : {{24{b0[7]}}, b0};
            `MEM_H : rdata = load_unsigned ? {16'b0, half}
                                           : {{16{half[15]}}, half};
            default: rdata = word;   // MEM_W
        endcase
    end
endmodule
