// =============================================================================
// ex_mem_reg.v  —  EX/MEM pipeline register
//
// Passes the ALU result (address for loads/stores), the store data, and the
// memory / write-back control down to the MEM stage.  No stall input: once an
// instruction leaves EX it always advances (divide stalls are handled before
// EX by freezing ID/EX).
// =============================================================================
`timescale 1ns / 1ps
`include "defines.vh"

module ex_mem_reg(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        bubble,       // squash: no reg write, no mem op

    input  wire        reg_write_in,
    input  wire [1:0]  wb_sel_in,
    input  wire        mem_read_in,
    input  wire        mem_write_in,
    input  wire [1:0]  mem_width_in,
    input  wire        mem_unsigned_in,
    input  wire [31:0] alu_result_in,
    input  wire [31:0] store_data_in,
    input  wire [31:0] pc4_in,
    input  wire [4:0]  rd_addr_in,

    output reg         reg_write_out,
    output reg  [1:0]  wb_sel_out,
    output reg         mem_read_out,
    output reg         mem_write_out,
    output reg  [1:0]  mem_width_out,
    output reg         mem_unsigned_out,
    output reg  [31:0] alu_result_out,
    output reg  [31:0] store_data_out,
    output reg  [31:0] pc4_out,
    output reg  [4:0]  rd_addr_out
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_write_out    <= 1'b0;
            wb_sel_out       <= `WB_ALU;
            mem_read_out     <= 1'b0;
            mem_write_out    <= 1'b0;
            mem_width_out    <= `MEM_W;
            mem_unsigned_out <= 1'b0;
            alu_result_out   <= 32'd0;
            store_data_out   <= 32'd0;
            pc4_out          <= 32'd0;
            rd_addr_out      <= 5'd0;
        end else begin
            reg_write_out    <= bubble ? 1'b0 : reg_write_in;
            wb_sel_out       <= wb_sel_in;
            mem_read_out     <= bubble ? 1'b0 : mem_read_in;
            mem_write_out    <= bubble ? 1'b0 : mem_write_in;
            mem_width_out    <= mem_width_in;
            mem_unsigned_out <= mem_unsigned_in;
            alu_result_out   <= alu_result_in;
            store_data_out   <= store_data_in;
            pc4_out          <= pc4_in;
            rd_addr_out      <= rd_addr_in;
        end
    end
endmodule
