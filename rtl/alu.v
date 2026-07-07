// =============================================================================
// alu.v  —  single-cycle combinational ALU, composed from physical units
//
// Sub-units:
//   adder32        add / sub / compare (SLT, SLTU derive from the subtract)
//   barrel_shifter SLL / SRL / SRA
//   gate rows      AND / OR / XOR / NOR
//
// SLT / SLTU are computed from ONE subtract (a - b):
//   SLTU = borrow                          (unsigned a < b)  = ~cout
//   SLT  = overflow ^ sum[31]              (signed   a < b)
// No second adder, no ">" operator — this is the textbook comparison trick.
//
// Multiply and divide are NOT here: they are long-latency and live in
// mult_unit / div_unit, selected by the EX stage.  This keeps the ALU purely
// combinational and shallow.
// =============================================================================
`timescale 1ns / 1ps
`include "defines.vh"

module alu(
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [4:0]  op,        // ALU_* micro-op
    output reg  [31:0] y,
    output wire        zero       // y == 0  (for flag use)
);
    // ---- adder / subtractor ------------------------------------------------
    // sub for SUB/SLT/SLTU; add otherwise.
    wire do_sub = (op == `ALU_SUB) | (op == `ALU_SLT) | (op == `ALU_SLTU);
    wire [31:0] sum;
    wire        cout, ovf;
    adder32 add(.a(a), .b(b), .sub(do_sub), .sum(sum), .cout(cout), .overflow(ovf));

    // set-less-than derivations from the single subtract
    wire slt_signed   = ovf ^ sum[31];   // signed   a < b
    wire slt_unsigned = ~cout;           // unsigned a < b  (borrow occurred)

    // ---- barrel shifter ----------------------------------------------------
    wire is_right = (op == `ALU_SRL) | (op == `ALU_SRA);
    wire is_arith = (op == `ALU_SRA);
    wire [31:0] shifted;
    barrel_shifter shf(
        .in(a), .shamt(b[4:0]), .dir(is_right), .arith(is_arith), .out(shifted)
    );

    // ---- bitwise logic (gate rows) -----------------------------------------
    wire [31:0] and_r, or_r, xor_r, nor_r;
    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : logic_row
            and g_and(and_r[i], a[i], b[i]);
            or  g_or (or_r[i],  a[i], b[i]);
            xor g_xor(xor_r[i], a[i], b[i]);
            nor g_nor(nor_r[i], a[i], b[i]);
        end
    endgenerate

    // ---- result mux --------------------------------------------------------
    always @(*) begin
        case (op)
            `ALU_ADD, `ALU_SUB : y = sum;
            `ALU_SLT           : y = {31'b0, slt_signed};
            `ALU_SLTU          : y = {31'b0, slt_unsigned};
            `ALU_AND           : y = and_r;
            `ALU_OR            : y = or_r;
            `ALU_XOR           : y = xor_r;
            `ALU_NOR           : y = nor_r;
            `ALU_SLL,
            `ALU_SRL,
            `ALU_SRA           : y = shifted;
            `ALU_PASSB         : y = b;
            default            : y = 32'd0;
        endcase
    end

    assign zero = ~(|y);
endmodule
