// =============================================================================
// adder32.v  —  32-bit adder/subtractor from a ripple chain of full adders
//
//   sub = 0 : sum = a + b
//   sub = 1 : sum = a + (~b) + 1   (two's-complement subtract)
//
// The 32 full_adder cells are wired in a physical ripple-carry chain: each
// stage's carry-out feeds the next stage's carry-in.  B is conditionally
// inverted by a row of XOR gates and the initial carry-in is `sub`, which is
// exactly the textbook add/sub cell.  Carry-out and signed overflow are
// exported so the ALU can build SLT / flags without a second adder.
// =============================================================================
`timescale 1ns / 1ps

module adder32(
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire        sub,      // 0:add  1:subtract
    output wire [31:0] sum,
    output wire        cout,     // carry out of bit 31 (unsigned carry/borrow)
    output wire        overflow  // signed overflow
);
    wire [31:0] b_x;             // b, conditionally inverted for subtract
    wire [32:0] carry;           // carry[0]=cin ... carry[32]=cout

    assign carry[0] = sub;       // +1 for two's complement when subtracting

    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : chain
            xor invert(b_x[i], b[i], sub);
            full_adder fa(
                .a   (a[i]),
                .b   (b_x[i]),
                .cin (carry[i]),
                .sum (sum[i]),
                .cout(carry[i+1])
            );
        end
    endgenerate

    assign cout     = carry[32];
    // signed overflow: carry into MSB differs from carry out of MSB
    xor ov(overflow, carry[32], carry[31]);
endmodule
