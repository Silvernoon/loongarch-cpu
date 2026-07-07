// =============================================================================
// branch_unit.v  —  evaluate a LoongArch branch condition
//
// Compares rj (a) against rd (b) and reports whether the branch is taken.
// Equality is a bitwise test; the ordered comparisons reuse the structural
// adder32 (a - b) exactly like the ALU's SLT, so there is no ">" operator:
//   LT  (signed)   = overflow ^ diff[31]
//   LTU (unsigned) = borrow (~cout)
// GE / GEU are the negations.  BR_ALWAYS covers b / bl / jirl.
// =============================================================================
`timescale 1ns / 1ps
`include "defines.vh"

module branch_unit(
    input  wire [31:0] a,        // rj
    input  wire [31:0] b,        // rd
    input  wire [2:0]  cond,     // BR_*
    output reg         taken
);
    wire [31:0] diff;
    wire        cout, ovf;
    adder32 cmp(.a(a), .b(b), .sub(1'b1), .sum(diff), .cout(cout), .overflow(ovf));

    wire eq      = ~(|diff);
    wire lt_s    = ovf ^ diff[31];   // signed   a < b
    wire lt_u    = ~cout;            // unsigned a < b

    always @(*) begin
        case (cond)
            `BR_EQ    : taken = eq;
            `BR_NE    : taken = ~eq;
            `BR_LT    : taken = lt_s;
            `BR_GE    : taken = ~lt_s;
            `BR_LTU   : taken = lt_u;
            `BR_GEU   : taken = ~lt_u;
            `BR_ALWAYS: taken = 1'b1;
            default   : taken = 1'b0;
        endcase
    end
endmodule
