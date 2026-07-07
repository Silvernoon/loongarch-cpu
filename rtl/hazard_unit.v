// =============================================================================
// hazard_unit.v  —  stalls and flushes for the 5-stage pipeline
//
// Two hazards need a bubble that forwarding alone cannot cover:
//
//  1. Load-use: a load in EX feeds an instruction in ID that needs the loaded
//     value now.  The value is not available until MEM, so stall IF/ID one
//     cycle and inject a bubble into ID/EX.
//
//  2. Control: a taken branch/jump is resolved in EX.  The two instructions
//     already fetched behind it (in IF and ID) are wrong-path and must be
//     flushed.
//
// Multi-cycle divide is handled with a separate ex_busy stall that freezes the
// front of the pipe until the divider asserts done.
// =============================================================================
`timescale 1ns / 1ps

module hazard_unit(
    // load-use detection: consumer in ID vs. load in EX
    input  wire        id_ex_mem_read,
    input  wire [4:0]  id_ex_rd,
    input  wire [4:0]  if_id_rj,
    input  wire [4:0]  if_id_rk,
    input  wire        if_id_uses_rj,   // 0 for ops that ignore rj (lu12i/b)
    input  wire        if_id_uses_rk,   // 0 for imm ops that ignore rk

    // control hazard: branch/jump taken in EX
    input  wire        branch_taken,

    // long-latency EX (divider running)
    input  wire        ex_busy,

    output wire        stall_pc,        // freeze PC
    output wire        stall_if_id,     // freeze IF/ID register
    output wire        bubble_id_ex,    // inject NOP into ID/EX
    output wire        flush_if_id,     // squash the instruction in IF/ID
    output wire        flush_id_ex      // squash the instruction in ID/EX
);
    // load-use: EX is a load whose rd is a source of the ID instruction
    wire load_use = id_ex_mem_read && (id_ex_rd != 5'd0) &&
                    ( (if_id_uses_rj && id_ex_rd == if_id_rj) ||
                      (if_id_uses_rk && id_ex_rd == if_id_rk) );

    // Divide stall dominates: hold everything until the unit is free.
    assign stall_pc    = load_use | ex_busy;
    assign stall_if_id = load_use | ex_busy;
    assign bubble_id_ex= load_use & ~ex_busy;   // insert bubble for load-use

    // On a taken branch (resolved in EX) squash the two wrong-path insns.
    assign flush_if_id = branch_taken;
    assign flush_id_ex = branch_taken;
endmodule
