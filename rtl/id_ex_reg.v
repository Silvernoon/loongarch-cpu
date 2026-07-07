// =============================================================================
// id_ex_reg.v  —  ID/EX pipeline register
//
// Carries the decoded control bundle, register values, immediate, PC, and
// operand addresses from decode into execute.
//   bubble/flush : clear every control-enable so the slot becomes a NOP
//                  (no reg write, no memory op, no branch) while leaving the
//                  datapath values harmless.
// A cleared slot must not write registers, touch memory, or redirect the PC.
// =============================================================================
`timescale 1ns / 1ps
`include "defines.vh"

module id_ex_reg(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,     // hold (divide)
    input  wire        clear,     // bubble/flush -> NOP

    // ---- control in ----
    input  wire        reg_write_in,
    input  wire [1:0]  wb_sel_in,
    input  wire        alu_src_imm_in,
    input  wire        alu_src_pc_in,
    input  wire [4:0]  alu_op_in,
    input  wire        mem_read_in,
    input  wire        mem_write_in,
    input  wire [1:0]  mem_width_in,
    input  wire        mem_unsigned_in,
    input  wire        is_branch_in,
    input  wire        is_jirl_in,
    input  wire [2:0]  br_cond_in,
    input  wire        use_mul_in,
    input  wire        mul_high_in,
    input  wire        mul_signed_in,
    input  wire        use_div_in,
    input  wire        div_signed_in,
    input  wire        div_rem_in,
    // ---- data in ----
    input  wire [31:0] pc_in,
    input  wire [31:0] pc4_in,
    input  wire [31:0] rj_data_in,
    input  wire [31:0] rk_data_in,
    input  wire [31:0] imm_in,
    input  wire [4:0]  rj_addr_in,
    input  wire [4:0]  rk_addr_in,
    input  wire [4:0]  rd_addr_in,

    // ---- control out ----
    output reg         reg_write_out,
    output reg  [1:0]  wb_sel_out,
    output reg         alu_src_imm_out,
    output reg         alu_src_pc_out,
    output reg  [4:0]  alu_op_out,
    output reg         mem_read_out,
    output reg         mem_write_out,
    output reg  [1:0]  mem_width_out,
    output reg         mem_unsigned_out,
    output reg         is_branch_out,
    output reg         is_jirl_out,
    output reg  [2:0]  br_cond_out,
    output reg         use_mul_out,
    output reg         mul_high_out,
    output reg         mul_signed_out,
    output reg         use_div_out,
    output reg         div_signed_out,
    output reg         div_rem_out,
    // ---- data out ----
    output reg  [31:0] pc_out,
    output reg  [31:0] pc4_out,
    output reg  [31:0] rj_data_out,
    output reg  [31:0] rk_data_out,
    output reg  [31:0] imm_out,
    output reg  [4:0]  rj_addr_out,
    output reg  [4:0]  rk_addr_out,
    output reg  [4:0]  rd_addr_out
);
    task load_bubble; begin
        reg_write_out    <= 1'b0;
        wb_sel_out       <= `WB_ALU;
        alu_src_imm_out  <= 1'b0;
        alu_src_pc_out   <= 1'b0;
        alu_op_out       <= `ALU_ADD;
        mem_read_out     <= 1'b0;
        mem_write_out    <= 1'b0;
        mem_width_out    <= `MEM_W;
        mem_unsigned_out <= 1'b0;
        is_branch_out    <= 1'b0;
        is_jirl_out      <= 1'b0;
        br_cond_out      <= `BR_NONE;
        use_mul_out      <= 1'b0;
        mul_high_out     <= 1'b0;
        mul_signed_out   <= 1'b0;
        use_div_out      <= 1'b0;
        div_signed_out   <= 1'b0;
        div_rem_out      <= 1'b0;
        pc_out           <= 32'd0;
        pc4_out          <= 32'd0;
        rj_data_out      <= 32'd0;
        rk_data_out      <= 32'd0;
        imm_out          <= 32'd0;
        rj_addr_out      <= 5'd0;
        rk_addr_out      <= 5'd0;
        rd_addr_out      <= 5'd0;
    end endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            load_bubble;
        else if (stall)
            ;                       // hold everything
        else if (clear)
            load_bubble;
        else begin
            reg_write_out    <= reg_write_in;
            wb_sel_out       <= wb_sel_in;
            alu_src_imm_out  <= alu_src_imm_in;
            alu_src_pc_out   <= alu_src_pc_in;
            alu_op_out       <= alu_op_in;
            mem_read_out     <= mem_read_in;
            mem_write_out    <= mem_write_in;
            mem_width_out    <= mem_width_in;
            mem_unsigned_out <= mem_unsigned_in;
            is_branch_out    <= is_branch_in;
            is_jirl_out      <= is_jirl_in;
            br_cond_out      <= br_cond_in;
            use_mul_out      <= use_mul_in;
            mul_high_out     <= mul_high_in;
            mul_signed_out   <= mul_signed_in;
            use_div_out      <= use_div_in;
            div_signed_out   <= div_signed_in;
            div_rem_out      <= div_rem_in;
            pc_out           <= pc_in;
            pc4_out          <= pc4_in;
            rj_data_out      <= rj_data_in;
            rk_data_out      <= rk_data_in;
            imm_out          <= imm_in;
            rj_addr_out      <= rj_addr_in;
            rk_addr_out      <= rk_addr_in;
            rd_addr_out      <= rd_addr_in;
        end
    end
endmodule
