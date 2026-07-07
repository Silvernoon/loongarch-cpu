// =============================================================================
// barrel_shifter.v  —  32-bit combinational barrel shifter (logarithmic)
//
//   dir  = 0 : shift left
//   dir  = 1 : shift right
//   arith= 1 : arithmetic right shift (replicate sign bit); ignored on left
//
// Five cascaded mux stages shift by 1,2,4,8,16.  Each stage is a 2:1 mux (a
// row of per-bit muxes) selected by one bit of the shift amount, so the whole
// shift is O(log N) deep — the standard physical barrel shifter, not a "<<"
// operator.  Each stage forms its shifted candidate by concatenation:
//   left  by S : {data[31-S:0], S x fill}
//   right by S : {S x fill,      data[31:S]}
// The fill bit is 0 for left / logical-right, or the sign bit for arithmetic
// right.  Concatenation keeps every index in range (no out-of-bounds selects).
// =============================================================================
`timescale 1ns / 1ps

module barrel_shifter(
    input  wire [31:0] in,
    input  wire [4:0]  shamt,
    input  wire        dir,     // 0:left 1:right
    input  wire        arith,   // 1:arithmetic right
    output wire [31:0] out
);
    wire fill = dir & arith & in[31];   // bit shifted into the vacated side

    wire [31:0] s0, s1, s2, s3;

    // ---- stage: shift by 1 ----
    wire [31:0] l0 = {in[30:0], fill};              // left  1
    wire [31:0] r0 = {fill, in[31:1]};              // right 1
    assign s0 = shamt[0] ? (dir ? r0 : l0) : in;

    // ---- stage: shift by 2 ----
    wire [31:0] l1 = {s0[29:0], {2{fill}}};
    wire [31:0] r1 = {{2{fill}}, s0[31:2]};
    assign s1 = shamt[1] ? (dir ? r1 : l1) : s0;

    // ---- stage: shift by 4 ----
    wire [31:0] l2 = {s1[27:0], {4{fill}}};
    wire [31:0] r2 = {{4{fill}}, s1[31:4]};
    assign s2 = shamt[2] ? (dir ? r2 : l2) : s1;

    // ---- stage: shift by 8 ----
    wire [31:0] l3 = {s2[23:0], {8{fill}}};
    wire [31:0] r3 = {{8{fill}}, s2[31:8]};
    assign s3 = shamt[3] ? (dir ? r3 : l3) : s2;

    // ---- stage: shift by 16 ----
    wire [31:0] l4 = {s3[15:0], {16{fill}}};
    wire [31:0] r4 = {{16{fill}}, s3[31:16]};
    assign out = shamt[4] ? (dir ? r4 : l4) : s3;
endmodule
