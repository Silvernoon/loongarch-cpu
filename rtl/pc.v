// =============================================================================
// pc.v  —  program counter with structural PC+4 incrementer
//
// Holds the fetch address.  Sequential flow uses a dedicated adder32 as the
// "PC adder" shown in the datapath.  A branch/jump computed in EX redirects
// the PC via (redirect, redirect_pc); a stall freezes it.  Reset vector is
// parameterizable (LoongArch resets to 0x1c000000, but 0 is fine for sim).
// =============================================================================
`timescale 1ns / 1ps

module pc #(
    parameter [31:0] RESET_VECTOR = 32'h0000_0000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,        // hold PC (load-use / divide)
    input  wire        redirect,     // branch/jump taken in EX
    input  wire [31:0] redirect_pc,
    output reg  [31:0] pc,           // current fetch address
    output wire [31:0] pc_plus4      // sequential next address
);
    wire        c, o;
    adder32 inc(.a(pc), .b(32'd4), .sub(1'b0), .sum(pc_plus4), .cout(c), .overflow(o));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pc <= RESET_VECTOR;
        else if (redirect)
            pc <= redirect_pc;   // redirect wins over stall (branch resolved)
        else if (!stall)
            pc <= pc_plus4;
        // else: hold
    end
endmodule
