// =============================================================================
// imm_gen.v  —  immediate extraction / extension for all LA32 formats
//
// Field positions (LoongArch, low-to-high register operands):
//   si12  = inst[21:10]                       (addi/slti/ld/st)   sign-ext
//   ui12  = inst[21:10]                       (andi/ori/xori)     zero-ext
//   shamt = inst[14:10]                       (slli/srli/srai)    zero-ext
//   si20  = inst[24:5]                        (lu12i/pcaddu12i) -> {si20,12'b0}
//   off16 = inst[25:10]                       (branch/jirl)  sign-ext, <<2
//   off26 = {inst[9:0],inst[25:10]}           (b/bl)         sign-ext, <<2
// =============================================================================
`timescale 1ns / 1ps
`include "defines.vh"

module imm_gen(
    input  wire [31:0] inst,
    input  wire [2:0]  imm_sel,     // IMM_*
    output reg  [31:0] imm
);
    wire [11:0] i12   = inst[21:10];
    wire [4:0]  sh    = inst[14:10];
    wire [19:0] i20   = inst[24:5];
    wire [15:0] o16   = inst[25:10];
    wire [25:0] o26   = {inst[9:0], inst[25:10]};

    always @(*) begin
        case (imm_sel)
            `IMM_SI12 : imm = {{20{i12[11]}}, i12};
            `IMM_UI12 : imm = {20'b0, i12};
            `IMM_SHAMT: imm = {27'b0, sh};
            `IMM_SI20 : imm = {i20, 12'b0};
            `IMM_OFF16: imm = {{14{o16[15]}}, o16, 2'b0};
            `IMM_OFF26: imm = {{4{o26[25]}}, o26, 2'b0};
            default   : imm = 32'd0;
        endcase
    end
endmodule
