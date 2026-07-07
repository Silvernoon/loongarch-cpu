// =============================================================================
// forwarding_unit.v  —  data-hazard bypass selects for the EX stage
//
// Compares the two source registers read in ID/EX against the destination
// registers still in flight (EX/MEM, MEM/WB) and picks where each operand
// should come from.  EX/MEM takes priority (it is the more recent value).
//   FWD_NONE : use the value read from the register file
//   FWD_MEM  : forward the EX/MEM stage ALU result
//   FWD_WB   : forward the MEM/WB stage write-back value
//
// r0 never forwards (it is constant zero).
// =============================================================================
`timescale 1ns / 1ps
`include "defines.vh"

module forwarding_unit(
    input  wire [4:0] ex_rj,        // source A in EX
    input  wire [4:0] ex_rk,        // source B in EX

    input  wire       mem_we,       // EX/MEM will write a register
    input  wire [4:0] mem_rd,
    input  wire       wb_we,        // MEM/WB will write a register
    input  wire [4:0] wb_rd,

    output reg  [1:0] fwd_a,
    output reg  [1:0] fwd_b
);
    always @(*) begin
        // operand A (rj)
        if (mem_we && mem_rd != 5'd0 && mem_rd == ex_rj)
            fwd_a = `FWD_MEM;
        else if (wb_we && wb_rd != 5'd0 && wb_rd == ex_rj)
            fwd_a = `FWD_WB;
        else
            fwd_a = `FWD_NONE;

        // operand B (rk / store-data)
        if (mem_we && mem_rd != 5'd0 && mem_rd == ex_rk)
            fwd_b = `FWD_MEM;
        else if (wb_we && wb_rd != 5'd0 && wb_rd == ex_rk)
            fwd_b = `FWD_WB;
        else
            fwd_b = `FWD_NONE;
    end
endmodule
