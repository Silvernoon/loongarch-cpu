// =============================================================================
// full_adder.v  —  1-bit full adder, pure gate primitives
//
//   sum   = a ^ b ^ cin
//   cout  = (a & b) | (cin & (a ^ b))
//
// Built from Verilog structural gate primitives so it maps directly onto
// physical AND/OR/XOR cells rather than an inferred "+" operator.
// =============================================================================
`timescale 1ns / 1ps

module full_adder(
    input  wire a,
    input  wire b,
    input  wire cin,
    output wire sum,
    output wire cout
);
    wire axb;        // a ^ b
    wire ab;         // a & b        (generate)
    wire cxab;       // cin & (a^b)  (propagate & carry)

    xor  g0(axb,  a, b);
    xor  g1(sum,  axb, cin);
    and  g2(ab,   a, b);
    and  g3(cxab, cin, axb);
    or   g4(cout, ab, cxab);
endmodule
