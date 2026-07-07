// =============================================================================
// control_unit.v  —  CU: decode one instruction into datapath control signals
//
// Reads the instruction word and drives every mux/enable in the pipeline, as
// described in the README ("读指令，指挥其他部件运作").  Purely combinational.
//
// Opcode match/mask values come from GNU binutils (loongarch-opc.c); the CU
// matches the masked fields to classify each instruction.
//
// Register-operand roles by format:
//   3R    : rd=inst[4:0]  rj=inst[9:5]  rk=inst[14:10]
//   2RI12 : rd=inst[4:0]  rj=inst[9:5]                    (ld/alu-imm)
//   store : reads rd(data)+rj(base), no writeback
//   2RI16 : rj=inst[9:5]  rd=inst[4:0]  (branch compares rj,rd; jirl writes rd)
//   1RI20 : rd=inst[4:0]                (lu12i/pcaddu12i)
// =============================================================================
`timescale 1ns / 1ps
`include "defines.vh"

module control_unit(
    input  wire [31:0] inst,

    output reg         reg_write,   // write GPR rd
    output reg  [1:0]  wb_sel,      // WB_ALU / WB_MEM / WB_PC4
    output reg         alu_src_imm, // 1: ALU B = imm, 0: ALU B = rk/reg
    output reg         alu_src_pc,  // 1: ALU A = PC (pcaddu12i)
    output reg  [4:0]  alu_op,      // ALU_* micro-op
    output reg  [2:0]  imm_sel,     // IMM_*

    output reg         mem_read,
    output reg         mem_write,
    output reg  [1:0]  mem_width,   // MEM_W/H/B
    output reg         mem_unsigned,// zero-extend loaded value

    output reg         is_branch,   // conditional or unconditional PC-rel
    output reg         is_jirl,     // register-indirect jump
    output reg  [2:0]  br_cond,     // BR_*

    output reg         use_mul,     // EX selects multiplier
    output reg         mul_high,    // return high word
    output reg         mul_signed,
    output reg         use_div,     // EX selects divider
    output reg         div_signed,
    output reg         div_rem,     // return remainder (MOD) vs quotient (DIV)

    output reg         rd_is_src,   // rd field is a SOURCE (stores/branches)
    output reg         link_r1,     // bl links return address into r1
    output wire        reads_rj,    // instruction reads register rj (port A)
    output wire        reads_rk,    // instruction reads the port-B register
    output reg         illegal      // unrecognized opcode
);
    // masked opcode views
    wire [31:0] m3r    = inst & `MASK_3R;
    wire [31:0] m2r12  = inst & `MASK_2RI12;
    wire [31:0] m1r20  = inst & `MASK_1RI20;
    wire [31:0] m2r16  = inst & `MASK_2RI16;

    // default assignment then per-class overrides
    task set_defaults; begin
        reg_write   = 1'b0;
        wb_sel      = `WB_ALU;
        alu_src_imm = 1'b0;
        alu_src_pc  = 1'b0;
        alu_op      = `ALU_ADD;
        imm_sel     = `IMM_NONE;
        mem_read    = 1'b0;
        mem_write   = 1'b0;
        mem_width   = `MEM_W;
        mem_unsigned= 1'b0;
        is_branch   = 1'b0;
        is_jirl     = 1'b0;
        br_cond     = `BR_NONE;
        use_mul     = 1'b0;
        mul_high    = 1'b0;
        mul_signed  = 1'b0;
        use_div     = 1'b0;
        div_signed  = 1'b0;
        div_rem     = 1'b0;
        rd_is_src   = 1'b0;
        link_r1     = 1'b0;
        illegal     = 1'b0;
    end endtask

    always @(*) begin
        set_defaults;
        // ---------------- 3R register-register ------------------------------
        if      (m3r == `OP_ADD_W ) begin reg_write=1; alu_op=`ALU_ADD;  end
        else if (m3r == `OP_SUB_W ) begin reg_write=1; alu_op=`ALU_SUB;  end
        else if (m3r == `OP_SLT   ) begin reg_write=1; alu_op=`ALU_SLT;  end
        else if (m3r == `OP_SLTU  ) begin reg_write=1; alu_op=`ALU_SLTU; end
        else if (m3r == `OP_AND   ) begin reg_write=1; alu_op=`ALU_AND;  end
        else if (m3r == `OP_OR    ) begin reg_write=1; alu_op=`ALU_OR;   end
        else if (m3r == `OP_XOR   ) begin reg_write=1; alu_op=`ALU_XOR;  end
        else if (m3r == `OP_NOR   ) begin reg_write=1; alu_op=`ALU_NOR;  end
        else if (m3r == `OP_SLL_W ) begin reg_write=1; alu_op=`ALU_SLL;  end
        else if (m3r == `OP_SRL_W ) begin reg_write=1; alu_op=`ALU_SRL;  end
        else if (m3r == `OP_SRA_W ) begin reg_write=1; alu_op=`ALU_SRA;  end
        else if (m3r == `OP_MUL_W ) begin reg_write=1; use_mul=1; mul_high=0; mul_signed=1; end
        else if (m3r == `OP_MULH_W ) begin reg_write=1; use_mul=1; mul_high=1; mul_signed=1; end
        else if (m3r == `OP_MULH_WU) begin reg_write=1; use_mul=1; mul_high=1; mul_signed=0; end
        else if (m3r == `OP_DIV_W ) begin reg_write=1; use_div=1; div_signed=1; div_rem=0; end
        else if (m3r == `OP_DIV_WU) begin reg_write=1; use_div=1; div_signed=0; div_rem=0; end
        else if (m3r == `OP_MOD_W ) begin reg_write=1; use_div=1; div_signed=1; div_rem=1; end
        else if (m3r == `OP_MOD_WU) begin reg_write=1; use_div=1; div_signed=0; div_rem=1; end
        // ---------------- 2RI5 shift-immediate ------------------------------
        else if (m3r == `OP_SLLI_W) begin reg_write=1; alu_op=`ALU_SLL; alu_src_imm=1; imm_sel=`IMM_SHAMT; end
        else if (m3r == `OP_SRLI_W) begin reg_write=1; alu_op=`ALU_SRL; alu_src_imm=1; imm_sel=`IMM_SHAMT; end
        else if (m3r == `OP_SRAI_W) begin reg_write=1; alu_op=`ALU_SRA; alu_src_imm=1; imm_sel=`IMM_SHAMT; end
        // ---------------- 2RI12 arithmetic-immediate ------------------------
        else if (m2r12 == `OP_ADDI_W) begin reg_write=1; alu_op=`ALU_ADD;  alu_src_imm=1; imm_sel=`IMM_SI12; end
        else if (m2r12 == `OP_SLTI  ) begin reg_write=1; alu_op=`ALU_SLT;  alu_src_imm=1; imm_sel=`IMM_SI12; end
        else if (m2r12 == `OP_SLTUI ) begin reg_write=1; alu_op=`ALU_SLTU; alu_src_imm=1; imm_sel=`IMM_SI12; end
        else if (m2r12 == `OP_ANDI  ) begin reg_write=1; alu_op=`ALU_AND;  alu_src_imm=1; imm_sel=`IMM_UI12; end
        else if (m2r12 == `OP_ORI   ) begin reg_write=1; alu_op=`ALU_OR;   alu_src_imm=1; imm_sel=`IMM_UI12; end
        else if (m2r12 == `OP_XORI  ) begin reg_write=1; alu_op=`ALU_XOR;  alu_src_imm=1; imm_sel=`IMM_UI12; end
        // ---------------- loads (2RI12) -------------------------------------
        else if (m2r12 == `OP_LD_W ) begin reg_write=1; wb_sel=`WB_MEM; alu_src_imm=1; imm_sel=`IMM_SI12; mem_read=1; mem_width=`MEM_W; end
        else if (m2r12 == `OP_LD_H ) begin reg_write=1; wb_sel=`WB_MEM; alu_src_imm=1; imm_sel=`IMM_SI12; mem_read=1; mem_width=`MEM_H; end
        else if (m2r12 == `OP_LD_B ) begin reg_write=1; wb_sel=`WB_MEM; alu_src_imm=1; imm_sel=`IMM_SI12; mem_read=1; mem_width=`MEM_B; end
        else if (m2r12 == `OP_LD_HU) begin reg_write=1; wb_sel=`WB_MEM; alu_src_imm=1; imm_sel=`IMM_SI12; mem_read=1; mem_width=`MEM_H; mem_unsigned=1; end
        else if (m2r12 == `OP_LD_BU) begin reg_write=1; wb_sel=`WB_MEM; alu_src_imm=1; imm_sel=`IMM_SI12; mem_read=1; mem_width=`MEM_B; mem_unsigned=1; end
        // ---------------- stores (2RI12) : rd is the data source ------------
        else if (m2r12 == `OP_ST_W ) begin alu_src_imm=1; imm_sel=`IMM_SI12; mem_write=1; mem_width=`MEM_W; rd_is_src=1; end
        else if (m2r12 == `OP_ST_H ) begin alu_src_imm=1; imm_sel=`IMM_SI12; mem_write=1; mem_width=`MEM_H; rd_is_src=1; end
        else if (m2r12 == `OP_ST_B ) begin alu_src_imm=1; imm_sel=`IMM_SI12; mem_write=1; mem_width=`MEM_B; rd_is_src=1; end
        // ---------------- 1RI20 upper-immediate / pc-relative ---------------
        else if (m1r20 == `OP_LU12I_W  ) begin reg_write=1; alu_op=`ALU_PASSB; alu_src_imm=1; imm_sel=`IMM_SI20; end
        else if (m1r20 == `OP_PCADDU12I) begin reg_write=1; alu_op=`ALU_ADD;   alu_src_imm=1; alu_src_pc=1; imm_sel=`IMM_SI20; end
        // ---------------- branches (2RI16) : compare rj vs rd ---------------
        else if (m2r16 == `OP_BEQ ) begin is_branch=1; br_cond=`BR_EQ;  imm_sel=`IMM_OFF16; rd_is_src=1; end
        else if (m2r16 == `OP_BNE ) begin is_branch=1; br_cond=`BR_NE;  imm_sel=`IMM_OFF16; rd_is_src=1; end
        else if (m2r16 == `OP_BLT ) begin is_branch=1; br_cond=`BR_LT;  imm_sel=`IMM_OFF16; rd_is_src=1; end
        else if (m2r16 == `OP_BGE ) begin is_branch=1; br_cond=`BR_GE;  imm_sel=`IMM_OFF16; rd_is_src=1; end
        else if (m2r16 == `OP_BLTU) begin is_branch=1; br_cond=`BR_LTU; imm_sel=`IMM_OFF16; rd_is_src=1; end
        else if (m2r16 == `OP_BGEU) begin is_branch=1; br_cond=`BR_GEU; imm_sel=`IMM_OFF16; rd_is_src=1; end
        // ---------------- jirl : rd = PC+4 ; PC = rj + off16<<2 -------------
        else if (m2r16 == `OP_JIRL) begin reg_write=1; wb_sel=`WB_PC4; is_jirl=1; br_cond=`BR_ALWAYS; imm_sel=`IMM_OFF16; end
        // ---------------- b / bl (I26) --------------------------------------
        else if ((inst & `MASK_2RI16) == `OP_B ) begin is_branch=1; br_cond=`BR_ALWAYS; imm_sel=`IMM_OFF26; end
        else if ((inst & `MASK_2RI16) == `OP_BL) begin is_branch=1; br_cond=`BR_ALWAYS; imm_sel=`IMM_OFF26; reg_write=1; wb_sel=`WB_PC4; link_r1=1; end
        else begin
            illegal = 1'b1;   // includes NOP (andi r0,r0,0) which is harmless
        end
    end

    // ---- source-register usage (for hazard/forwarding), derived from the
    //      already-decoded controls so it can never disagree with them -------
    // reg-reg ALU/mul/div ops are the writers that take operand B from rk.
    wire is_reg_reg = reg_write & ~alu_src_imm & (wb_sel == `WB_ALU) & ~mem_read;
    assign reads_rk = is_reg_reg | rd_is_src;         // rk, or rd for st/branch
    // rj is read by all but lu12i/pcaddu12i (SI20) and b/bl (unconditional).
    assign reads_rj = ~( (imm_sel == `IMM_SI20) |
                         (is_branch & (br_cond == `BR_ALWAYS)) );
endmodule
