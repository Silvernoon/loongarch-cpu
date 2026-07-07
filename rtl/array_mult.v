// =============================================================================
// array_mult.v  —  32x32 -> 64 unsigned array multiplier (carry-save reduction)
//
// This is the "physical" replacement for `a * b`.  It is built entirely from
// AND gates (partial-product generation) and full_adder cells (reduction):
//
//   1. Generate 32 partial products  pp_i = a & {32{b[i]}}  weighted by 2^i.
//   2. Reduce them to two 64-bit vectors (sum, carry) with a chain of 3:2
//      carry-save adders — one full_adder per bit per stage, no carry
//      propagation inside a stage.
//   3. Collapse the final (sum,carry) pair with one ripple-carry adder.
//
// Purely unsigned; signed products are handled in mult_unit by pre/post
// negation.  Latency is combinational (the multi-cycle sequencing lives in
// mult_unit so EX stays single-cycle-visible via a busy/stall handshake).
// =============================================================================
`timescale 1ns / 1ps

module array_mult(
    input  wire [31:0] a,
    input  wire [31:0] b,
    output wire [63:0] product
);
    // ---- partial products : pp[i] = (a & {32{b[i]}}) << i, in 64-bit frame --
    // pp_bit(i,k) is 1 only where a[k-i] exists and b[i]=1.
    wire [63:0] pp [0:31];
    genvar i, k;
    generate
        for (i = 0; i < 32; i = i + 1) begin : gen_pp
            for (k = 0; k < 64; k = k + 1) begin : gen_pp_bit
                if (k >= i && (k - i) < 32)
                    and pp_and(pp[i][k], a[k-i], b[i]);
                else
                    assign pp[i][k] = 1'b0;
            end
        end
    endgenerate

    // ---- carry-save reduction : fold 32 rows into a running (S, C) pair -----
    // S[0]=pp[0], C[0]=0.  Each stage does a bitwise 3:2 compression of
    // (S[s-1], C[s-1], pp[s]); the carry out of bit k lands at bit k+1.
    wire [63:0] S [0:31];
    wire [63:0] C [0:31];

    assign S[0] = pp[0];
    assign C[0] = 64'd0;

    generate
        for (i = 1; i < 32; i = i + 1) begin : gen_csa
            wire [63:0] carry_raw;   // carry-out of each bit, pre-shift
            assign C[i][0] = 1'b0;   // nothing shifts into bit 0
            for (k = 0; k < 64; k = k + 1) begin : gen_csa_bit
                full_adder fa(
                    .a   (S[i-1][k]),
                    .b   (C[i-1][k]),
                    .cin (pp[i][k]),
                    .sum (S[i][k]),
                    .cout(carry_raw[k])
                );
                if (k < 63)
                    assign C[i][k+1] = carry_raw[k];   // carry weight = 2^(k+1)
            end
        end
    endgenerate

    // ---- final carry-propagate add : product = S[31] + C[31] ---------------
    // One 64-bit ripple-carry chain of full adders collapses the carry-save
    // pair into the binary product.  C[31][0] is 0 by construction, so the
    // chain carry-in is 0.
    wire [64:0] fc;              // fc[0]=cin ... fc[64]=final cout
    assign fc[0] = 1'b0;
    genvar j;
    generate
        for (j = 0; j < 64; j = j + 1) begin : gen_cpa
            full_adder fa(
                .a   (S[31][j]),
                .b   (C[31][j]),
                .cin (fc[j]),
                .sum (product[j]),
                .cout(fc[j+1])
            );
        end
    endgenerate
endmodule
