// =============================================================================
// defines.vh  —  LoongArch32 (LA32 base integer) ISA + micro-arch encodings
//
// Instruction match/mask values are taken verbatim from GNU binutils
// (opcodes/loongarch-opc.c).  Field layout, per the reference manual:
//   register operands grow upward from bit 0, opcode grows downward from
//   bit 31, immediate sits in between.
//     rd = inst[ 4: 0]   rj = inst[ 9: 5]   rk = inst[14:10]
// =============================================================================
`ifndef LA32_DEFINES_VH
`define LA32_DEFINES_VH

// ---- machine width -----------------------------------------------------------
`define XLEN        32
`define REG_ADDR_W  5

// ---- ALU operation select (internal micro-op, not the ISA opcode) -----------
`define ALU_ADD    5'd0
`define ALU_SUB    5'd1
`define ALU_SLT    5'd2    // signed  set-less-than
`define ALU_SLTU   5'd3    // unsigned set-less-than
`define ALU_AND    5'd4
`define ALU_OR     5'd5
`define ALU_XOR    5'd6
`define ALU_NOR    5'd7
`define ALU_SLL    5'd8
`define ALU_SRL    5'd9
`define ALU_SRA    5'd10
`define ALU_MUL    5'd11   // low  32 bits of product
`define ALU_MULH   5'd12   // high 32 bits, signed
`define ALU_MULHU  5'd13   // high 32 bits, unsigned
`define ALU_DIV    5'd14   // signed   quotient
`define ALU_DIVU   5'd15   // unsigned quotient
`define ALU_MOD    5'd16   // signed   remainder
`define ALU_MODU   5'd17   // unsigned remainder
`define ALU_PASSB  5'd18   // pass operand B (used by lu12i.w)

// ---- immediate encodings (what imm_gen must build) --------------------------
`define IMM_NONE   3'd0
`define IMM_SI12   3'd1    // sign-extended  inst[21:10]           (addi/slti/ld/st)
`define IMM_UI12   3'd2    // zero-extended  inst[21:10]           (andi/ori/xori)
`define IMM_SHAMT  3'd3    // shift amount   inst[14:10]           (slli/srli/srai)
`define IMM_SI20   3'd4    // {inst[24:5],12'b0}                   (lu12i/pcaddu12i)
`define IMM_OFF16  3'd5    // sign-ext inst[25:10] << 2            (branch/jirl)
`define IMM_OFF26  3'd6    // sign-ext {inst[9:0],inst[25:10]} <<2 (b/bl)

// ---- next-PC select ---------------------------------------------------------
`define NPC_PLUS4  2'd0
`define NPC_BRANCH 2'd1    // PC + off16<<2 (conditional / b / bl)
`define NPC_JIRL   2'd2    // rj + off16<<2

// ---- branch condition -------------------------------------------------------
`define BR_NONE    3'd0
`define BR_EQ      3'd1
`define BR_NE      3'd2
`define BR_LT      3'd3
`define BR_GE      3'd4
`define BR_LTU     3'd5
`define BR_GEU     3'd6
`define BR_ALWAYS  3'd7    // b / bl / jirl (unconditional)

// ---- memory access width ----------------------------------------------------
`define MEM_W      2'd0
`define MEM_H      2'd1
`define MEM_B      2'd2

// ---- write-back source ------------------------------------------------------
`define WB_ALU     2'd0
`define WB_MEM     2'd1
`define WB_PC4     2'd2    // link register (bl / jirl)

// ---- forwarding select ------------------------------------------------------
`define FWD_NONE   2'd0
`define FWD_MEM    2'd1    // from EX/MEM stage
`define FWD_WB     2'd2    // from MEM/WB stage

// =============================================================================
// Raw ISA opcode match/mask (from binutils loongarch-opc.c)
// =============================================================================
// 3R-type  : mask 0xffff8000
`define OP_ADD_W    32'h00100000
`define OP_SUB_W    32'h00110000
`define OP_SLT      32'h00120000
`define OP_SLTU     32'h00128000
`define OP_NOR      32'h00140000
`define OP_AND      32'h00148000
`define OP_OR       32'h00150000
`define OP_XOR      32'h00158000
`define OP_SLL_W    32'h00170000
`define OP_SRL_W    32'h00178000
`define OP_SRA_W    32'h00180000
`define OP_MUL_W    32'h001c0000
`define OP_MULH_W   32'h001c8000
`define OP_MULH_WU  32'h001d0000
`define OP_DIV_W    32'h00200000
`define OP_MOD_W    32'h00208000
`define OP_DIV_WU   32'h00210000
`define OP_MOD_WU   32'h00218000
`define MASK_3R     32'hffff8000

// 2RI5 shift : mask 0xffff8000
`define OP_SLLI_W   32'h00408000
`define OP_SRLI_W   32'h00448000
`define OP_SRAI_W   32'h00488000

// 2RI12 : mask 0xffc00000
`define OP_SLTI     32'h02000000
`define OP_SLTUI    32'h02400000
`define OP_ADDI_W   32'h02800000
`define OP_ANDI     32'h03400000
`define OP_ORI      32'h03800000
`define OP_XORI     32'h03c00000
`define OP_LD_B     32'h28000000
`define OP_LD_H     32'h28400000
`define OP_LD_W     32'h28800000
`define OP_ST_B     32'h29000000
`define OP_ST_H     32'h29400000
`define OP_ST_W     32'h29800000
`define OP_LD_BU    32'h2a000000
`define OP_LD_HU    32'h2a400000
`define MASK_2RI12  32'hffc00000

// 1RI20 : mask 0xfe000000
`define OP_LU12I_W    32'h14000000
`define OP_PCADDU12I  32'h1c000000
`define MASK_1RI20    32'hfe000000

// 2RI16 : mask 0xfc000000
`define OP_JIRL     32'h4c000000
`define OP_BEQ      32'h58000000
`define OP_BNE      32'h5c000000
`define OP_BLT      32'h60000000
`define OP_BGE      32'h64000000
`define OP_BLTU     32'h68000000
`define OP_BGEU     32'h6c000000
`define MASK_2RI16  32'hfc000000

// I26 : mask 0xfc000000
`define OP_B        32'h50000000
`define OP_BL       32'h54000000

`endif
