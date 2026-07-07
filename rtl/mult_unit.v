// =============================================================================
// mult_unit.v  —  signed/unsigned 32x32 multiply, low or high word
//
// Wraps the unsigned array_mult and adds sign handling with the classic
// "negate-inputs / negate-output" trick:
//   - MUL.W    : low 32 bits of product
//   - MULH.W   : high 32 bits, signed
//   - MULH.WU  : high 32 bits, unsigned
//
// Every arithmetic step reuses the structural adder32 (which is itself full
// adders), so there is no inferred "*" or "-" anywhere in the datapath.
// Combinational: the array multiplier is one deep gate network.
// =============================================================================
`timescale 1ns / 1ps

module mult_unit(
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire        is_signed,  // 1: treat operands as signed
    input  wire        want_high,  // 1: return high word, 0: low word
    output wire [31:0] result
);
    // ---- take input magnitudes (product sign = sa ^ sb) --------------------
    wire sa = is_signed & a[31];
    wire sb = is_signed & b[31];

    wire [31:0] a_neg, b_neg;
    wire        na_c, na_o, nb_c, nb_o;
    adder32 neg_a(.a(32'd0), .b(a), .sub(1'b1), .sum(a_neg), .cout(na_c), .overflow(na_o));
    adder32 neg_b(.a(32'd0), .b(b), .sub(1'b1), .sum(b_neg), .cout(nb_c), .overflow(nb_o));

    wire [31:0] a_mag = sa ? a_neg : a;
    wire [31:0] b_mag = sb ? b_neg : b;

    // ---- unsigned product of the magnitudes --------------------------------
    wire [63:0] prod_mag;
    array_mult mul(.a(a_mag), .b(b_mag), .product(prod_mag));

    // ---- restore product sign: 64-bit two's-complement negate --------------
    //   lo = 0 - prod_lo             (cout = 1  iff  prod_lo == 0)
    //   hi = ~prod_hi + carry_from_lo
    wire result_neg = sa ^ sb;
    wire [31:0] pn_lo, pn_hi;
    wire        pl_c, pl_o, ph_c, ph_o;
    adder32 negp_lo(.a(32'd0), .b(prod_mag[31:0]), .sub(1'b1),
                    .sum(pn_lo), .cout(pl_c), .overflow(pl_o));
    adder32 negp_hi(.a(~prod_mag[63:32]), .b({31'b0, pl_c}), .sub(1'b0),
                    .sum(pn_hi), .cout(ph_c), .overflow(ph_o));

    wire [63:0] prod_signed = result_neg ? {pn_hi, pn_lo} : prod_mag;

    assign result = want_high ? prod_signed[63:32] : prod_signed[31:0];
endmodule
