// =============================================================================
// cpu.v  —  LoongArch32 5-stage pipelined core (top level)
//
// Stages:  IF -> ID/RF -> EX -> MA -> WB   (classic 5-stage, README §运行)
//
// Structure follows the datapath diagram:
//   - Harvard memories: separate imem (IF) and dmem (MA)
//   - Dual-port register file read in ID, written in WB (write-first bypass)
//   - Physical ALU (structural), plus mult_unit / div_unit in EX
//   - Full forwarding (EX/MEM, MEM/WB -> EX) and load-use / control hazards
//   - Branches and jumps resolve in EX; the two wrong-path fetches are flushed
//
// Instruction fields (LoongArch, low-to-high operands):
//   rd = inst[4:0]   rj = inst[9:5]   rk = inst[14:10]
// The port-B read address is rk normally, but rd for stores/branches (they
// read the rd-named register as a source), selected by the control unit.
// =============================================================================
`timescale 1ns / 1ps
`include "defines.vh"

module cpu #(
    parameter INIT_FILE = "",
    parameter [31:0] RESET_VECTOR = 32'h0000_0000
)(
    input  wire clk,
    input  wire rst_n,

    // debug/inspection taps (for the testbench)
    output wire [31:0] dbg_pc,
    output wire        dbg_wb_we,
    output wire [4:0]  dbg_wb_rd,
    output wire [31:0] dbg_wb_data
);
    // =====================================================================
    //  IF — instruction fetch
    // =====================================================================
    wire        stall_pc, stall_if_id, bubble_id_ex, flush_if_id, flush_id_ex;
    wire        ex_busy;               // divide in flight (declared here, driven in EX)
    wire        i_stall, d_stall;
    wire        branch_taken;          // resolved in EX
    wire [31:0] branch_target;         // resolved in EX

    wire [31:0] if_pc, if_pc4, if_inst;

    pc #(.RESET_VECTOR(RESET_VECTOR)) u_pc(
        .clk(clk), .rst_n(rst_n),
        .stall(stall_pc),
        .redirect(branch_taken), .redirect_pc(branch_target),
        .pc(if_pc), .pc_plus4(if_pc4)
    );

    imem #(.INIT_FILE(INIT_FILE)) u_imem(
        .clk(clk), .rst_n(rst_n),
        .addr(if_pc), .inst(if_inst), .stall(i_stall)
    );

    // =====================================================================
    //  IF/ID
    // =====================================================================
    wire [31:0] id_pc, id_pc4, id_inst;

    if_id_reg u_if_id(
        .clk(clk), .rst_n(rst_n),
        .stall(stall_if_id), .flush(flush_if_id),
        .pc_in(if_pc), .pc4_in(if_pc4), .inst_in(if_inst),
        .pc_out(id_pc), .pc4_out(id_pc4), .inst_out(id_inst)
    );

    // =====================================================================
    //  ID — decode + register read
    // =====================================================================
    wire [4:0] id_rd = id_inst[4:0];
    wire [4:0] id_rj = id_inst[9:5];
    wire [4:0] id_rk = id_inst[14:10];

    // control
    wire        c_reg_write, c_alu_src_imm, c_alu_src_pc;
    wire [1:0]  c_wb_sel;
    wire [4:0]  c_alu_op;
    wire [2:0]  c_imm_sel;
    wire        c_mem_read, c_mem_write, c_mem_unsigned;
    wire [1:0]  c_mem_width;
    wire        c_is_branch, c_is_jirl;
    wire [2:0]  c_br_cond;
    wire        c_use_mul, c_mul_high, c_mul_signed;
    wire        c_use_div, c_div_signed, c_div_rem;
    wire        c_rd_is_src, c_link_r1, c_reads_rj, c_reads_rk, c_illegal;

    control_unit u_cu(
        .inst(id_inst),
        .reg_write(c_reg_write), .wb_sel(c_wb_sel),
        .alu_src_imm(c_alu_src_imm), .alu_src_pc(c_alu_src_pc),
        .alu_op(c_alu_op), .imm_sel(c_imm_sel),
        .mem_read(c_mem_read), .mem_write(c_mem_write),
        .mem_width(c_mem_width), .mem_unsigned(c_mem_unsigned),
        .is_branch(c_is_branch), .is_jirl(c_is_jirl), .br_cond(c_br_cond),
        .use_mul(c_use_mul), .mul_high(c_mul_high), .mul_signed(c_mul_signed),
        .use_div(c_use_div), .div_signed(c_div_signed), .div_rem(c_div_rem),
        .rd_is_src(c_rd_is_src), .link_r1(c_link_r1),
        .reads_rj(c_reads_rj), .reads_rk(c_reads_rk), .illegal(c_illegal)
    );

    // port-B read address: rk normally, rd for stores/branches
    wire [4:0] id_rb_addr = c_rd_is_src ? id_rd : id_rk;
    // destination: rd normally, r1 for bl
    wire [4:0] id_dst = c_link_r1 ? 5'd1 : id_rd;

    // immediate
    wire [31:0] id_imm;
    imm_gen u_imm(.inst(id_inst), .imm_sel(c_imm_sel), .imm(id_imm));

    // register file (write side comes from WB below)
    wire        wb_reg_write;
    wire [4:0]  wb_rd;
    wire [31:0] wb_data;
    wire [31:0] id_rj_data, id_rb_data;

    regfile u_rf(
        .clk(clk), .rst_n(rst_n),
        .ra_addr(id_rj), .ra_data(id_rj_data),
        .rb_addr(id_rb_addr), .rb_data(id_rb_data),
        .we(wb_reg_write), .wa_addr(wb_rd), .wa_data(wb_data)
    );

    // =====================================================================
    //  ID/EX
    // =====================================================================
    wire        x_reg_write, x_alu_src_imm, x_alu_src_pc;
    wire [1:0]  x_wb_sel;
    wire [4:0]  x_alu_op;
    wire        x_mem_read, x_mem_write, x_mem_unsigned;
    wire [1:0]  x_mem_width;
    wire        x_is_branch, x_is_jirl;
    wire [2:0]  x_br_cond;
    wire        x_use_mul, x_mul_high, x_mul_signed;
    wire        x_use_div, x_div_signed, x_div_rem;
    wire [31:0] x_pc, x_pc4, x_rj_data, x_rk_data, x_imm;
    wire [4:0]  x_rj_addr, x_rk_addr, x_rd_addr;

    // A slot is a bubble when the decoded instruction is illegal (e.g. the NOP
    // andi r0,r0,0 or filler) OR when hazard logic requests a bubble/flush.
    wire id_ex_clear = bubble_id_ex | flush_id_ex;

    id_ex_reg u_id_ex(
        .clk(clk), .rst_n(rst_n),
        .stall(ex_busy | d_stall), // long EX op or D-cache miss freezes ID/EX
        .clear(id_ex_clear),
        .reg_write_in(c_reg_write), .wb_sel_in(c_wb_sel),
        .alu_src_imm_in(c_alu_src_imm), .alu_src_pc_in(c_alu_src_pc),
        .alu_op_in(c_alu_op),
        .mem_read_in(c_mem_read), .mem_write_in(c_mem_write),
        .mem_width_in(c_mem_width), .mem_unsigned_in(c_mem_unsigned),
        .is_branch_in(c_is_branch), .is_jirl_in(c_is_jirl), .br_cond_in(c_br_cond),
        .use_mul_in(c_use_mul), .mul_high_in(c_mul_high), .mul_signed_in(c_mul_signed),
        .use_div_in(c_use_div), .div_signed_in(c_div_signed), .div_rem_in(c_div_rem),
        .pc_in(id_pc), .pc4_in(id_pc4),
        .rj_data_in(id_rj_data), .rk_data_in(id_rb_data), .imm_in(id_imm),
        .rj_addr_in(id_rj), .rk_addr_in(id_rb_addr), .rd_addr_in(id_dst),

        .reg_write_out(x_reg_write), .wb_sel_out(x_wb_sel),
        .alu_src_imm_out(x_alu_src_imm), .alu_src_pc_out(x_alu_src_pc),
        .alu_op_out(x_alu_op),
        .mem_read_out(x_mem_read), .mem_write_out(x_mem_write),
        .mem_width_out(x_mem_width), .mem_unsigned_out(x_mem_unsigned),
        .is_branch_out(x_is_branch), .is_jirl_out(x_is_jirl), .br_cond_out(x_br_cond),
        .use_mul_out(x_use_mul), .mul_high_out(x_mul_high), .mul_signed_out(x_mul_signed),
        .use_div_out(x_use_div), .div_signed_out(x_div_signed), .div_rem_out(x_div_rem),
        .pc_out(x_pc), .pc4_out(x_pc4),
        .rj_data_out(x_rj_data), .rk_data_out(x_rk_data), .imm_out(x_imm),
        .rj_addr_out(x_rj_addr), .rk_addr_out(x_rk_addr), .rd_addr_out(x_rd_addr)
    );

    // =====================================================================
    //  EX — execute
    // =====================================================================
    // forwarding
    wire [1:0] fwd_a, fwd_b;
    wire       m_reg_write;
    wire [4:0] m_rd_addr;
    wire [31:0] m_alu_result;

    forwarding_unit u_fwd(
        .ex_rj(x_rj_addr), .ex_rk(x_rk_addr),
        .mem_we(m_reg_write), .mem_rd(m_rd_addr),
        .wb_we(wb_reg_write), .wb_rd(wb_rd),
        .fwd_a(fwd_a), .fwd_b(fwd_b)
    );

    // forwarded operand values
    reg [31:0] ex_a_fwd, ex_b_fwd;
    always @(*) begin
        case (fwd_a)
            `FWD_MEM: ex_a_fwd = m_alu_result;
            `FWD_WB : ex_a_fwd = wb_data;
            default : ex_a_fwd = x_rj_data;
        endcase
        case (fwd_b)
            `FWD_MEM: ex_b_fwd = m_alu_result;
            `FWD_WB : ex_b_fwd = wb_data;
            default : ex_b_fwd = x_rk_data;
        endcase
    end

    // ALU operand selects
    wire [31:0] alu_a = x_alu_src_pc  ? x_pc  : ex_a_fwd;
    wire [31:0] alu_b = x_alu_src_imm ? x_imm : ex_b_fwd;

    wire [31:0] alu_y;
    wire        alu_zero;
    alu u_alu(.a(alu_a), .b(alu_b), .op(x_alu_op), .y(alu_y), .zero(alu_zero));

    // multiplier
    wire [31:0] mul_y;
    mult_unit u_mul(
        .a(ex_a_fwd), .b(ex_b_fwd),
        .is_signed(x_mul_signed), .want_high(x_mul_high), .result(mul_y)
    );

    // divider (multi-cycle) — started when a valid divide sits in EX
    wire        div_busy, div_done;
    wire [31:0] div_q, div_r;
    reg         div_started;
    wire        div_start = x_use_div & ~div_started & ~div_busy;

    div_unit u_div(
        .clk(clk), .rst_n(rst_n),
        .start(div_start), .is_signed(x_div_signed),
        .dividend(ex_a_fwd), .divisor(ex_b_fwd),
        .quotient(div_q), .remainder(div_r),
        .busy(div_busy), .done(div_done)
    );

    // Track that we've kicked off the divide for the instruction in EX so we
    // don't restart it every cycle while stalled.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)              div_started <= 1'b0;
        else if (div_done)       div_started <= 1'b0;   // done -> ready for next
        else if (div_start)      div_started <= 1'b1;
    end

    // EX stalls the pipe while a divide is in flight (start or running,
    // and not yet done).
    assign ex_busy = x_use_div & ~div_done;
    wire [31:0] div_y = x_div_rem ? div_r : div_q;

    // choose the EX result: divide > multiply > ALU
    wire [31:0] ex_result = x_use_div ? div_y :
                            x_use_mul ? mul_y : alu_y;

    // branch / jump resolution
    wire        br_taken_cond;
    branch_unit u_br(.a(ex_a_fwd), .b(ex_b_fwd), .cond(x_br_cond), .taken(br_taken_cond));

    // target = (jirl) rj + off16<<2 ; else PC + off<<2
    wire [31:0] br_pc_target, jr_target;
    wire        bt_c, bt_o, jt_c, jt_o;
    adder32 add_brpc(.a(x_pc),     .b(x_imm), .sub(1'b0), .sum(br_pc_target), .cout(bt_c), .overflow(bt_o));
    adder32 add_jr  (.a(ex_a_fwd), .b(x_imm), .sub(1'b0), .sum(jr_target),    .cout(jt_c), .overflow(jt_o));

    assign branch_taken  = (x_is_branch | x_is_jirl) & br_taken_cond & ~ex_busy;
    assign branch_target = x_is_jirl ? jr_target : br_pc_target;

    // =====================================================================
    //  EX/MEM
    // =====================================================================
    wire [1:0]  m_wb_sel;
    wire        m_mem_read, m_mem_write, m_mem_unsigned;
    wire [1:0]  m_mem_width;
    wire [31:0] m_store_data, m_pc4;

    // A divide still running must not commit; freeze via bubble.
    ex_mem_reg u_ex_mem(
        .clk(clk), .rst_n(rst_n),
        .stall(d_stall),
        .bubble(ex_busy),
        .reg_write_in(x_reg_write), .wb_sel_in(x_wb_sel),
        .mem_read_in(x_mem_read), .mem_write_in(x_mem_write),
        .mem_width_in(x_mem_width), .mem_unsigned_in(x_mem_unsigned),
        .alu_result_in(ex_result), .store_data_in(ex_b_fwd),
        .pc4_in(x_pc4), .rd_addr_in(x_rd_addr),

        .reg_write_out(m_reg_write), .wb_sel_out(m_wb_sel),
        .mem_read_out(m_mem_read), .mem_write_out(m_mem_write),
        .mem_width_out(m_mem_width), .mem_unsigned_out(m_mem_unsigned),
        .alu_result_out(m_alu_result), .store_data_out(m_store_data),
        .pc4_out(m_pc4), .rd_addr_out(m_rd_addr)
    );

    // =====================================================================
    //  MA — memory access
    // =====================================================================
    wire [31:0] m_load_data;

    dmem u_dmem(
        .clk(clk), .rst_n(rst_n),
        .addr(m_alu_result), .we(m_mem_write), .re(m_mem_read),
        .width(m_mem_width), .load_unsigned(m_mem_unsigned),
        .wdata(m_store_data), .rdata(m_load_data), .stall(d_stall)
    );

    // =====================================================================
    //  MEM/WB
    // =====================================================================
    wire [1:0]  w_wb_sel;
    wire [31:0] w_mem_data, w_alu_result, w_pc4;

    mem_wb_reg u_mem_wb(
        .clk(clk), .rst_n(rst_n),
        .stall(d_stall),
        .reg_write_in(m_reg_write), .wb_sel_in(m_wb_sel),
        .mem_data_in(m_load_data), .alu_result_in(m_alu_result),
        .pc4_in(m_pc4), .rd_addr_in(m_rd_addr),

        .reg_write_out(wb_reg_write), .wb_sel_out(w_wb_sel),
        .mem_data_out(w_mem_data), .alu_result_out(w_alu_result),
        .pc4_out(w_pc4), .rd_addr_out(wb_rd)
    );

    // =====================================================================
    //  WB — write back
    // =====================================================================
    reg [31:0] wb_mux;
    always @(*) begin
        case (w_wb_sel)
            `WB_MEM: wb_mux = w_mem_data;
            `WB_PC4: wb_mux = w_pc4;      // link register (bl / jirl)
            default: wb_mux = w_alu_result;
        endcase
    end
    assign wb_data = wb_mux;

    // =====================================================================
    //  Hazard control
    // =====================================================================
    hazard_unit u_hz(
        .id_ex_mem_read(x_mem_read), .id_ex_rd(x_rd_addr),
        .if_id_rj(id_rj), .if_id_rk(id_rb_addr),
        .if_id_uses_rj(c_reads_rj), .if_id_uses_rk(c_reads_rk),
        .branch_taken(branch_taken),
        .ex_busy(ex_busy),
        .i_stall(i_stall),
        .d_stall(d_stall),
        .stall_pc(stall_pc), .stall_if_id(stall_if_id),
        .bubble_id_ex(bubble_id_ex),
        .flush_if_id(flush_if_id), .flush_id_ex(flush_id_ex)
    );

    // =====================================================================
    //  Debug taps
    // =====================================================================
    assign dbg_pc      = if_pc;
    assign dbg_wb_we   = wb_reg_write;
    assign dbg_wb_rd   = wb_rd;
    assign dbg_wb_data = wb_data;
endmodule
