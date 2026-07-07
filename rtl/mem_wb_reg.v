// =============================================================================
// mem_wb_reg.v  —  MEM/WB pipeline register
//
// Final stage register: carries the load data, the ALU result, PC+4 (for link
// instructions), the write-back source select, and the destination register
// into the write-back stage where the GPR file is updated.
// =============================================================================
`timescale 1ns / 1ps
`include "defines.vh"

module mem_wb_reg(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,

    input  wire        reg_write_in,
    input  wire [1:0]  wb_sel_in,
    input  wire [31:0] mem_data_in,
    input  wire [31:0] alu_result_in,
    input  wire [31:0] pc4_in,
    input  wire [4:0]  rd_addr_in,

    output reg         reg_write_out,
    output reg  [1:0]  wb_sel_out,
    output reg  [31:0] mem_data_out,
    output reg  [31:0] alu_result_out,
    output reg  [31:0] pc4_out,
    output reg  [4:0]  rd_addr_out
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_write_out  <= 1'b0;
            wb_sel_out     <= `WB_ALU;
            mem_data_out   <= 32'd0;
            alu_result_out <= 32'd0;
            pc4_out        <= 32'd0;
            rd_addr_out    <= 5'd0;
        end else if (stall) begin
            ;                       // hold during cache miss
        end else begin
            reg_write_out  <= reg_write_in;
            wb_sel_out     <= wb_sel_in;
            mem_data_out   <= mem_data_in;
            alu_result_out <= alu_result_in;
            pc4_out        <= pc4_in;
            rd_addr_out    <= rd_addr_in;
        end
    end
endmodule
